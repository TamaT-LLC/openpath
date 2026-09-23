---
id: PROJ-DSN-001
layer: L4
feature: openpath
scope: feature
status: Draft
upstream:
- PROJ-REQ-001
- PROJ-UX-001
- PROJ-ARCH-001
downstream:
- PROJ-TST-001
owner: TakehiroT
updated: 2026-09-23
---

# 詳細設計: パネル検知とパス注入（PanelWatcher / PanelInjector）

## 1. 対象要件

FR-DETECT-01〜05、FR-INJECT-01〜05、NFR-02。

## 2. PanelWatcher

### 2.1 観測対象の張り替え

```swift
final class PanelWatcher {
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var pollTimer: DispatchSourceTimer?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, ...) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attach(to: app.processIdentifier)
        }
        if let front = NSWorkspace.shared.frontmostApplication { attach(to: front.processIdentifier) }
    }
}
```

- `attach(pid)`: 既存 observer を `CFRunLoopRemoveSource` で外し、新 PID に対して `AXObserverCreate` → `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification`, `kAXFocusedWindowChangedNotification` を `AXObserverAddNotification` で登録。
- 自プロセス（openpath）と `disabled_apps` に含まれる bundle id は張り付けない。
- 補助ポーリング: `PanelShown` でない間のみ 200ms 間隔でフロントアプリの `kAXWindowsAttribute` を列挙し、`isOpenPanel` を評価。AXObserver 通知が来た時点でポーリングは一時停止。

### 2.2 パネル判定

```swift
func isOpenPanel(_ window: AXUIElement) -> Bool {
    guard let subrole: String = window.attr(kAXSubroleAttribute),
          subrole == kAXDialogSubrole || subrole == kAXSheetSubrole /* "AXSheet" */ else { return false }
    let confirmTitles: Set<String> = ["開く", "Open", "選択", "Choose", "追加", "Add"]
    let hasConfirm = window.descendants(role: kAXButtonRole, maxDepth: 6)
        .contains { confirmTitles.contains($0.title ?? "") }
    let hasFileList = window.descendants(roles: [kAXBrowserRole, kAXOutlineRole, kAXTableRole], maxDepth: 6).isEmpty == false
    let isSavePanel = window.descendants(role: kAXTextFieldRole, maxDepth: 6)
        .contains { ($0.attr(kAXDescriptionAttribute) as String?)?.contains("Save") == true || $0.title?.contains("名前") == true }
    return hasConfirm && hasFileList && !isSavePanel
}
```

- `descendants` は幅優先で最大 6 階層、1 パネルあたり 400 要素で打ち切る（サンドボックスパネルはリモート要素のため往復コストが高い）。
- 判定結果はウィンドウの `AXUIElement` をキーにキャッシュし、`kAXUIElementDestroyedNotification` で破棄。
- サンドボックスアプリでは、パネルは `openAndSavePanelService` のプロセスで描画されるが、AX ツリー上はホストアプリのウィンドウの `AXSheet` 子要素として見える。ホスト側の観測だけで検知できるが、要素アクセスの往復が遅いため判定は非同期キュー（`.userInteractive`）で行い、メインスレッドをブロックしない。

### 2.3 パネルの選択モード推定

- `canChooseDirectories` のみのパネル（Claude Desktop の「フォルダを追加」等）は、ファイル行が `AXDisabled` になる。ファイルリスト内の先頭 20 行を見て、ディレクトリ以外がすべて disabled なら「フォルダのみモード」と推定し、`CandidateIndex` にディレクトリのみを要求する。
- 推定できない場合は設定 `include_files` に従う。

### 2.4 パネルの位置取得

- `kAXPositionAttribute` / `kAXSizeAttribute` からパネル矩形を取得し、`PaletteWindow` の配置に渡す。AX 座標系は左上原点のため、`NSScreen` の座標へ変換する。

## 3. PanelInjector

### 3.1 主方式: Cmd+Shift+G + ペースト

```
1. NSPasteboard.general の全 items を退避（types ごとに Data で保持）
2. NSPasteboard に path を setString(_:forType: .string)
3. CGEvent: Cmd+Shift+G  keyDown/keyUp（kVK_ANSI_G, flags [.maskCommand, .maskShift]）
4. 最大 600ms、50ms 間隔で「移動先シート」の出現を AX で待つ
   - 判定: パネルの子孫に AXSheet または AXTextField(placeholder に "パス"/"Path"/"Go to") が出現
5. CGEvent: Cmd+A → Cmd+V（フィールドの既存値を置換）
6. 100ms 待機（ペースト反映）
7. CGEvent: Return（シート確定 → パネルが移動）
8. auto_confirm または Cmd+Enter の場合: 300ms 待機後、パネル内「開く」ボタンを AXPress
9. 200ms 後にペーストボードを退避内容から復元
```

- CGEvent は `CGEventTapLocation.cghidEventTap` へ post。`CGEventSource(stateID: .combinedSessionState)` を使用。
- 各ステップは `Task` で実行し、全体タイムアウト 1.5 秒。タイムアウト時は `InjectError.timeout(step:)` を返す。
- ステップ 4 でシートが出ない場合（一部アプリで Cmd+Shift+G が無効）→ 副方式にフォールバック。

### 3.2 副方式: AX 直接セット

```
1. 主方式のステップ 3 で出たシート内の AXTextField を取得
   （出ていない場合はパネルのツールバー検索フィールドではなく、失敗として扱う）
2. AXUIElementSetAttributeValue(field, kAXValueAttribute, path as CFString)
3. シート内 AXButton(title: "移動" / "Go") を AXPress。無ければ field に kAXConfirmAction
4. 以降は主方式のステップ 8〜9 と同じ
```

- `AXValue` の書き込みが `kAXErrorAttributeUnsupported` を返す場合は失敗。ペーストボードは復元する。

### 3.3 エラー分類

| エラー | ユーザー表示 | 復旧 |
| --- | --- | --- |
| `timeout(step: .waitSheet)` | 「⌘⇧G が開きません」 | 副方式へ。それも失敗ならパレット残置 |
| `timeout(step: .waitPaste)` | 「パスの貼り付けに失敗」 | ペーストボード復元、パレット残置 |
| `axError(code)` | 「アクセシビリティ操作に失敗 (code)」 | 同上 |
| `panelGone` | 表示なし（パレットを閉じる） | Idle へ |

## 4. パス正規化

- 注入前に `URL(fileURLWithPath:).standardizedFileURL.path` へ正規化。`~` は展開する。
- シンボリックリンクは解決しない（ghq のリンク運用を壊さないため）。
- 末尾 `/` は付けない（Cmd+Shift+G は末尾スラッシュなしでもディレクトリへ移動できる）。

## 5. スレッド・タイミング

- AX 呼び出しはすべて `axQueue`（serial, `.userInteractive`）で行い、結果を `MainActor` に戻す。
- `PanelShown` 中の AX 呼び出し合計を 1 パネルあたり 50 回以下に抑える（判定キャッシュ + 位置取得は 1 回）。
- 注入中は `PaletteWindow.isLocked = true`。ロック中のキー入力は捨てる。

## 6. 権限

- 起動時: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])`。未付与なら StatusItem にバッジを出し、`PanelWatcher.start()` は呼ばない。
- 権限変更の検知: 5 秒間隔で `AXIsProcessTrusted()` をポーリング（付与直後に自動で有効化するため）。
