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
updated: 2026-09-24
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

- `attach(pid)`: 既存 observer を外し、新 PID に対して `AXObserverCreate` → `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification`, `kAXFocusedWindowChangedNotification` を `AXObserverAddNotification` で登録。**登録・解除は `axQueue`、RunLoop ソースの追加・削除は `main` で行う**（`AXObserverAddNotification` はプロセス間通信で、応答しないアプリが相手だと呼び出しが main を止めうるため。main でソースを外してから axQueue で登録解除する。張り替え中の取り違えは世代番号で検出する。AXObserver の作成・登録に失敗しても観測は続け、`PanelShown` 中もポーリングを止めない、PR #46）。
- 自プロセス（openpath）と `disabled_apps` に含まれる bundle id は張り付けない。**自プロセスがアクティブになった場合は観測対象を張り替えない**（メニューバー操作などで前面に来ただけで、追跡中のパネルを見失わないため、PR #46）。
- **アプリを切り替えたら、追跡中のパネルについて `panelGone` を送る**（切替先のアプリでは消滅を検知できないため。パレットは閉じる）。元のアプリに戻ると、開いたままのパネルを通知し直す。アプリの終了（`NSWorkspace` の `didTerminate` 通知）も購読し、確実に観測を外す（PR #46）。
- 補助ポーリング: 200ms 間隔でフロントアプリの `kAXWindowsAttribute` を列挙し、`isOpenPanel` を評価。**一時停止する条件は「AppCoordinator が Idle でない」（`PanelShown` / `Injecting`）の 1 つに一本化する**（AXObserver 通知そのものでは止めない。判定条件を 1 つにまとめるため）。`PanelShown` / `Injecting` 中もパネルの消滅（FR-DETECT-05）を検知するため、AX 通知による走査は続ける（止めるのはポーリングだけ、PR #46）。
- 走査は同時に 1 つに絞り、走査中に届いた通知は 1 回の再走査にまとめる。走査中に来たポーリングの周期は捨てる（シリアルな `axQueue` を埋めて、注入の AX 呼び出しを遅らせないため、PR #46）。
- ウィンドウ一覧の取得に失敗した場合（`noValue` / `attributeUnsupported` / `cannotComplete` / `invalidUIElement` など）は一時的な失敗（`unavailable`）として扱い、パネルが消えたとはみなさない。有無は実際に一覧を取得できたときだけ判断する（PR #46、CodeRabbit 指摘対応）。
- `disabledAppsDidChange()`: ConfigStore（PROJ-DSN-002 §6）の変更通知から呼び、最前面アプリの張り付け対象を判定し直す。

### 2.2 パネル判定

```swift
func isOpenPanel(_ window: AXUIElement) -> Bool {
    guard isDialogOrSheet(window) else { return false }  // AXSubrole in [AXDialog, AXSheet] または AXRole == AXSheet
    let confirmTitles: Set<String> = ["開く", "Open", "選択", "Choose", "追加", "Add", "アップロード", "Upload"]
    let hasConfirm = window.descendants(role: kAXButtonRole, maxDepth: 6)
        .contains { confirmTitles.contains($0.title ?? "") }
    let hasFileList = window.descendants(roles: [kAXBrowserRole, kAXOutlineRole, kAXTableRole], maxDepth: 6).isEmpty == false
    let isSavePanel = window.descendants(role: kAXTextFieldRole, maxDepth: 6)
        .contains {
            [$0.attr(kAXDescriptionAttribute) as String?, $0.title].contains {
                $0?.contains("Save") == true || $0?.contains("保存") == true || $0?.contains("名前") == true
            }
        }
    return hasConfirm && hasFileList && !isSavePanel
}
```

- ロールが `AXSheet` の要素も候補にする（サブロールだけでなく、シートは通常ロールも `AXSheet` のため。当初案のコードはサブロールのみ比較していた、PR #56）。
- 確定ボタンに「アップロード」/「Upload」を追加した（Safari の `input[type=file]` パネル対策。TST-001 S-06）。
- 子のシートを 2 段まで探す（リモートビューが外側のシートの下にさらにシートを重ねる構成に対応）。ただし、ファイル一覧の行（ファイル名を保存欄と誤認しないため）と、子のシート自体の中（開くパネルでないダイアログをパネルと誤判定しないため）へは降りない。
- 保存パネルの除外条件は `AXDescription` とタイトルの両方を「Save」「保存」「名前」で調べる（当初案のコードは説明を「Save」、タイトルを「名前」でしか見ておらず、ARCH-001 §6 の「保存」「Save As」とも食い違っていたため統一した、PR #56）。検索フィールドは対象外。
- `descendants` は幅優先で最大 6 階層、1 パネルあたり 400 要素で打ち切る（サンドボックスパネルはリモート要素のため往復コストが高い）。
- 判定結果は **パネルの要素（ダイアログ・シート）をキーに** キャッシュする（ホストのウィンドウはシートの有無で変わらないため。ウィンドウにはロールと直前のパネルだけを持たせる、PR #56）。要素が欠けていて判定できなかった候補は、間隔を倍々に空けて判定し直す（サンドボックスアプリのパネルは別プロセス描画のため、出現直後は中身がまだ無いことがある）。
- 判定はクロージャ（`PanelDetector`）ではなく `PanelDetecting` プロトコル（既定実装 `OpenPanelDetector()`）として持つ（PR #56。#17 時点のクロージャ API は削除）。`AXApplicationObserver` の破棄通知は対象要素も判定側へ渡し、走査で見つけたパネルの要素にも `kAXUIElementDestroyedNotification` を追加登録する（最大 8 要素、古いものから解除。PR #46 で見送った対処案を PR #56 で採用）。
- AX の要素参照には 1 回 0.25 秒のメッセージングタイムアウトを設定する（既定の約 6 秒のままだと応答しないアプリで `axQueue` が止まるため）。タイムアウトした要素は子なしとして扱い、一時的な失敗としてパネルを消えたとはみなさない。
- `panelAppeared` を送るとき `panel detected` を、パネルの消滅では `panel gone` を info でログに出す（`Log.configure` が必須。TST-001 §4 のスモークスクリプトが grep する。Idle に戻った後の再通知でも出す）。判定のコスト（AX 呼び出し回数・所要ミリ秒）は debug で出す。どちらもパスは含まない（PR #56）。
- サンドボックスアプリでは、パネルは `openAndSavePanelService` のプロセスで描画されるが、AX ツリー上はホストアプリのウィンドウの `AXSheet` 子要素として見える。ホスト側の観測だけで検知できるが、要素アクセスの往復が遅いため判定は `axQueue` 上で同期的に行う（各ウィンドウに判定関数を適用する形。DSN-001 の当初案は判定関数を async にする想定だったが、axQueue 上の 1 ジョブにまとめる方が単純で速い、PR #46）。

### 2.3 パネルの選択モード推定

- `canChooseDirectories` のみのパネル（Claude Desktop の「フォルダを追加」等）は、ファイル行が `AXDisabled` になる。ファイルリスト内の先頭 20 行を見て、ディレクトリ以外がすべて disabled なら「フォルダのみモード」と推定し、`CandidateIndex` にディレクトリのみを要求する。
- 推定できない場合は設定 `include_files` に従う。

### 2.4 パネルの位置取得

- `kAXPositionAttribute` / `kAXSizeAttribute` からパネル矩形を取得し、`PaletteWindow` の配置に渡す。AX 座標系は左上原点のため、`NSScreen` の座標へ変換する。

## 3. PanelInjector

### 3.1 主方式: Cmd+Shift+G + ペースト

```
1. アクセシビリティ権限を currentStatus() で確認（未付与なら axError(apiDisabled) で即失敗）
2. 基準走査: 現在の AXSheet 数とパス入力欄（placeholder に "パス"/"Path"/"Go to" を含む AXTextField / AXComboBox）数を記録（上限 600ms）
3. CGEvent: Cmd+Shift+G  keyDown/keyUp（kVK_ANSI_G, flags [.maskCommand, .maskShift]）
4. 最大 600ms、50ms 間隔（50, 100, …, 550ms）で「移動先シート」の出現を基準比で判定
   - 判定: 2. の基準より AXSheet 数またはパス入力欄数が増えた
   - パネル自体がシートとして表示される場合（サンドボックスアプリ等、⌘⇧G 前から AXSheet がある場合）も、基準からの増分で見るため誤検知しない
5. シート出現を確認できたら、NSPasteboard.general の全 items を退避（types ごとに Data で保持）→ path を org.nspasteboard.TransientType 付きで setString(_:forType: .string)
6. CGEvent: Cmd+A → Cmd+V（フィールドの既存値を置換）
7. 100ms 待機（ペースト反映）
8. CGEvent: Return（シート確定 → パネルが移動）
9. auto_confirm または Cmd+Enter の場合: 300ms 待機後、パネル内「開く」ボタンを AXPress（auto_confirm フック。DSN-001 §2.2 のタイトル一覧で確定ボタンを探す）
10. Return から 200ms 後（9. のフックが 200ms を超えた場合はフック完了直後）に、ペーストボードの changeCount が退避時から変わっていなければ退避内容へ復元する。変わっていれば、注入中に書き込まれた新しい内容を優先し復元しない
```

- **ペーストボードの差し替えは ⌘⇧G の前ではなく、シート出現後（⌘A の直前）に移した**（当初案は ⌘⇧G の前）。⌘⇧G が効かず副方式へフォールバックするアプリではペーストボードに一切触れずに済み、パスがペーストボード上にある時間も最大 900ms 前後から約 300ms（⌘V〜Return〜200ms）に縮む（PR #45）。
- CGEvent は `CGEventTapLocation.cghidEventTap` へ post。`CGEventSource(stateID: .combinedSessionState)` を使用。
- 各ステップは `Task` で実行し、全体タイムアウト 1.5 秒（AppCoordinator 側）。Injector 内部にも基準走査・シート待ちそれぞれ 600ms の上限があり、超えたら ⌘⇧G を送らず／それ以上進まず `timeout(step: .waitSheet)` を返す。
- AX の走査には打ち切り条件（期限到来 or キャンセル）を渡し、`axQueue` 上で進む走査もキャンセルに応じて途中で打ち切る（応答しないアプリの走査が `InjectionSerialGate` を塞いで次の注入を待たせ続けないため、PR #45）。
- AX の要素参照には 1 回 0.25 秒のメッセージングタイムアウトを設定する（既定の約 6 秒のままだと `axQueue` 全体が止まるため）。
- 注入は `InjectionSerialGate` で 1 件ずつ直列に実行する（キャンセル済みの注入が後始末を待つ間に次の注入が始まると、前のパスを「元の内容」として退避してしまい、ユーザーのクリップボードを失うため、PR #45）。
- ステップ 4 で出現を確認できない場合（一部アプリで Cmd+Shift+G が無効、または基準走査・シート判定が打ち切り条件に達した）→ 副方式にフォールバック（DSN-001 §3.2）。

### 3.2 副方式: AX 直接セット

主方式が `timeout(.waitSheet)` または `timeout(.waitPaste)` になった場合に、⌘⇧G で出たはずの移動先 UI を別の手掛かりで探し直す（`GoToFieldSearch`）。「⌘⇧G がまったく効かない」場合は救えないが、「移動先 UI は出たが主方式の基準比較で拾えなかった」場合（600ms より後に出た、AXSheet ではない要素として出た等）を救うためのもの（PR #54）。

```
1. 注入開始時に記録したウィンドウ（とそのシート）を走査し、次の順で入力欄を選ぶ
   a. 「移動」/「Go」ボタンと同じシートにある AXTextField / AXComboBox（旧来の移動先シート）
   b. placeholder がパスを示す入力欄（主方式と同じ語）
   （検索フィールドは対象外。起点が通常のウィンドウなら、シートの外の要素は対象外）
2. 入力欄が見つからなければ、主方式のエラー（timeout(.waitSheet) または timeout(.waitPaste)）をそのまま返す
3. AXUIElementSetAttributeValue(field, kAXValueAttribute, path as CFString)
4. シート内 AXButton(title: "移動" / "Go") を AXPress。無ければ field に kAXConfirmAction
5. 以降は主方式のステップ 9〜10 と同じ（副方式はペーストボードを使わないため、timeout(.waitPaste) 経由のフォールバックでも退避・復元は発生しない）
```

- `timeout(.waitPaste)`（シートは出たがペーストボードの書き込み・キー送出に失敗）でもフォールバックする。Return を送る前の失敗なのでパネルはまだ移動しておらず、ペーストボードもキー操作も使わない AX 直接セットで救えるため（PR #54）。
- `pasteboardRestoreFailed` や、Return 送出後（auto_confirm 等）の失敗ではフォールバックしない。
- `AXValue` の書き込みが `kAXErrorAttributeUnsupported` 等を返す場合は `axError(code)` として失敗する。

### 3.3 エラー分類

| エラー | ユーザー表示 | 復旧 |
| --- | --- | --- |
| `timeout(step: .waitSheet)` | 「⌘⇧G が開きません」 | 副方式へ。それも失敗なら PanelShown に戻りパレット残置（Esc / panelGone で閉じる） |
| `timeout(step: .waitPaste)` | 「パスの貼り付けに失敗」 | 同上（副方式へフォールバック） |
| `axError(code)` | 「アクセシビリティ操作に失敗 (code)」 | PanelShown に戻りパレット残置 |
| `axError(-25211)`（apiDisabled、権限なし） | 同上 | 同上（注入開始時に `currentStatus()` で先に検知する、DSN-001 §3.1・§6） |
| `targetNotFrontmost`（新設、PR #54） | 「移動できませんでした（パネルが最前面でなくなりました）」 | PanelShown に戻りパレット残置 |
| `panelGoneBeforeConfirm`（新設、PR #54） | 表示なし（自動確定で「開く」を押す前にパネルが消えた） | Idle へ。履歴に残さない |
| `pasteboardRestoreFailed`（新設、PR #45） | 「クリップボードを元に戻せませんでした」 | PanelShown に戻りパレット残置。他の結果（成功・失敗）より優先して伝える |
| `panelGone`（上記以外。auto_confirm 開始後を除く） | 表示なし（パレットを閉じる） | Idle へ |

- 自動確定（auto_confirm / Cmd+Enter）で注入を開始した後の `panelGone` は、AppCoordinator が成功として扱う（ARCH-001 §5、PR #52）。
- 注入先ガード（`InjectionTargetGuard`）: 注入開始時に最前面アプリの pid とフォーカス中のウィンドウを記録し、以降の各キー送出・AX 操作の直前に確認する（確認 1 回の上限 100ms）。最前面から外れていれば `targetNotFrontmost`、ウィンドウが消えていれば `panelGone` を投げる（PR #52 で自動確定中に `panelGone` でも注入を止めなくなった結果、切替先のアプリへキーが届く恐れが生まれたための対策、PR #54）。

## 4. パス正規化

- `URL(fileURLWithPath:).standardizedFileURL.path` を当初案としていたが、この方式は実行時に NFC へ正規化する・実行ユーザーのホームで `~` を展開する・カレントディレクトリで相対パスを絶対化するため、純粋関数として扱えず表記も保持できない。代わりに config の roots と同じ `RootPathResolver`（`~` / `~/` の展開と、`.`・`..`・空要素・末尾 `/` の字句的な除去のみ）で正規化する（PR #54）。
- シンボリックリンクは解決しない（`/tmp` は `/private/tmp` にしない。ghq のリンク運用を壊さないため）。
- 絶対パスにできないもの（相対パス、`~user`）は、推測で別の場所を指さないようそのまま返す。
- 正規化は注入にだけ使う。履歴には AppCoordinator が受け取った元のパスをそのまま記録する（変更なし）。

## 5. スレッド・タイミング

- AX 呼び出しはすべて `axQueue`（serial）で行い、結果を `MainActor` に戻す。要素参照には 1 回 0.25 秒のメッセージングタイムアウトを設定し、応答しないアプリで `axQueue` 全体が止まらないようにする（既定の約 6 秒のままだと注入の AX 呼び出しまで待たされる。PanelWatcher の走査・GoToSheetDetector・注入先ガードのいずれにも適用、PR #45 / #46 / #54）。
- `PanelShown` 中の AX 呼び出し合計を 1 パネルあたり 50 回以下に抑える（判定キャッシュは 1 回。位置取得は Idle への再通知のたびに最新の位置で通知し直すため、1 パネルにつき最大 2 回読む、PR #56）。
- 注入中は `PaletteWindow.isLocked = true`。ロック中のキー入力は捨てる。
- 注入は `InjectionSerialGate` で 1 件ずつ直列に実行する（DSN-001 §3.1、PR #45）。

## 6. 権限

- 起動時・ポーリングとも `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])` に統一する（`AccessibilityPermission.currentStatus()`。当初案はポーリングに `AXIsProcessTrusted()` としていたが、意味は同じで「プロンプトを出さない」ことをコード上で明示するため統一した、PR #37）。未付与なら StatusItem にバッジを出し、`PanelWatcher.start()` は呼ばない。
- 権限変更の検知: 5 秒間隔でポーリングする（付与直後に自動で有効化するため）。実装は `DispatchSourceTimer` ではなく `Task.sleep` のループ（`ValueChangePoller`）で、生成時に状態を読み、以降は変化があったときだけ通知する。
- 権限のないプロセスから他アプリへ AX を呼ぶと、`apiDisabled` ではなく `cannotComplete (-25204)` が返る（macOS 26 で実機確認済み）。エラーコードでは権限の有無を判定できないため、PanelInjector は注入開始時に `AccessibilityPermission.currentStatus()` で直接確認する（DSN-001 §3.1、PR #37 / #45）。
