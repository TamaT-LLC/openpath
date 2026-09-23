---
id: PROJ-ARCH-001
layer: L3
feature: openpath
scope: global
status: Draft
upstream:
- PROJ-REQ-001
- PROJ-UX-001
downstream:
- PROJ-DSN-001
- PROJ-DSN-002
- PROJ-TST-001
owner: TakehiroT
updated: 2026-09-24
---

# アーキテクチャ設計: openpath

## 1. 目的

NSOpenPanel の出現を検知し、ファジー検索パレットを重ね、選択したパスをパネルへ注入する macOS 常駐アプリの構成を定義する。外部サービス依存を持たず、Swift 単体で完結させる。

## 2. 技術スタック

- 言語: Swift（Swift 6.0+ ツールチェーン）。`OpenPathCore` は Swift 6 言語モード、AppKit 依存層（`OpenPathMac` と実行ターゲット `openpath`）は AX の C コールバックを扱うため Swift 5 言語モード
- UI: SwiftUI（パレット内容）+ AppKit（NSPanel / NSStatusItem / イベント）
- ビルド: Swift Package Manager（`swift build`）+ `scripts/`（build / sign / notarize / cask 生成）。Xcode プロジェクトは持たない。署名は `codesign`、Notarization は `notarytool` / `stapler`（いずれも Command Line Tools に同梱、#59）
- 依存: 標準フレームワークのみ（AppKit, ApplicationServices, Carbon.HIToolbox, ServiceManagement）。TOML パースは軽量な自前実装 or `TOMLDecoder` を検討（L4 で確定）
- 配布: Developer ID 署名 + Notarization、Homebrew cask

## 3. 全体像

```
┌──────────────────────────────────────────────────────────────┐
│ openpath.app (LSUIElement, メニューバー常駐)                   │
│                                                              │
│  ┌────────────┐   ┌─────────────┐   ┌──────────────────────┐ │
│  │ StatusItem │   │ ConfigStore │   │ HistoryStore         │ │
│  │ (menu)     │   │ (TOML,監視) │   │ (history.json,frecency)│ │
│  └─────┬──────┘   └──────┬──────┘   └──────────┬───────────┘ │
│        │                 │                     │             │
│  ┌─────▼─────────────────▼─────────────────────▼───────────┐ │
│  │ AppCoordinator (状態機械: Idle→PanelShown→Injecting→Idle)│ │
│  └─────┬───────────────────┬───────────────────┬───────────┘ │
│        │                   │                   │             │
│  ┌─────▼──────┐   ┌────────▼────────┐   ┌──────▼──────────┐  │
│  │ PanelWatcher│   │ PaletteWindow   │   │ PanelInjector   │  │
│  │ (AX観測)   │   │ (NSPanel+SwiftUI)│   │ (CGEvent / AX)  │  │
│  └─────┬──────┘   └────────┬────────┘   └──────┬──────────┘  │
│        │                   │                   │             │
│        │            ┌──────▼────────┐          │             │
│        │            │ CandidateIndex│          │             │
│        │            │ (sources+fuzzy)│          │             │
│        │            └──────┬────────┘          │             │
└────────┼───────────────────┼───────────────────┼─────────────┘
         │                   │                   │
   AX API (観測)      ghq / FileManager    CGEvent / AX (注入)
         │                                       │
   ┌─────▼───────────────────────────────────────▼───────┐
   │ 最前面アプリの NSOpenPanel                            │
   │ (サンドボックス時は openAndSavePanelService が描画)    │
   └─────────────────────────────────────────────────────┘
```

## 4. モジュール責務

| モジュール | 責務 | 主要 API |
| --- | --- | --- |
| `AppCoordinator` | 状態機械の保持、各モジュール間のイベント配線 | 内部 |
| `PanelWatcher` | 最前面アプリの AX 観測、NSOpenPanel の出現 / 消滅検知 | `AXObserverCreate`, `NSWorkspace.didActivateApplicationNotification` |
| `PaletteWindow` | 非アクティブ化フローティング NSPanel、SwiftUI ビューのホスト、キー処理 | `NSPanel(.nonactivatingPanel)`, `NSEvent.addLocalMonitorForEvents` |
| `CandidateIndex` | 候補ソースの集約、ファジーマッチ、frecency ソート | 内部 |
| `HistoryStore` | 使用回数 / 最終使用日時の永続化と時間減衰 | `FileManager`, `JSONEncoder` |
| `ConfigStore` | TOML 読み込み、`DispatchSource` でのファイル監視 | `DispatchSource.makeFileSystemObjectSource` |
| `PanelInjector` | Cmd+Shift+G → ペースト → Enter の送出、AX 直接セットのフォールバック | `CGEvent`, `AXUIElementSetAttributeValue` |
| `StatusItem` | メニューバー UI、権限案内、自動起動 | `NSStatusBar`, `SMAppService` |

## 5. 状態機械

```
        パネル検知              Enter 確定        1.5秒タイムアウト / panelGone
Idle ─────────────▶ PanelShown ─────────────▶ Injecting ─────────────▶ Idle
  ▲                    │  ▲                        │
  │   パネル消滅 / Esc  │  └── 注入失敗（panelGone   └── 注入成功 → Idle（成功パネルを記憶）
  └────────────────────┘      以外）はここへ戻り
                               パレット残置
```

- `PanelShown` では PaletteWindow を表示し、CandidateIndex に問い合わせる。
- `Injecting` 中はパレット入力をロックする。`Idle` に戻すのは 1.5 秒のタイムアウトと `panelGone` のみで、パレットも閉じる。injector が投げたそれ以外のエラー（timeout / axError 等）は `PanelShown` に戻し、パレットにエラー表示を残したままその場で再試行できるようにする（Esc または `panelGone` で閉じる、PR #39）。
- 注入に成功したパネルは `Idle` の間だけ内部で記憶し、同じ id の `panelAppeared` によるパレットの再通知を抑止する。`Idle` 中のホットキーは通常無視するが、成功パネルを記憶している間だけは例外的にパレットを再表示できる（PR #52）。
- `auto_confirm` が有効な場合、`Injecting` の最後に「開く」ボタンの AXPress を行う。自動確定の注入を開始した後に `panelGone` を受けても注入はキャンセルせず結果を待つ（パレットはその場で閉じる）。injector が `panelGone` または `pasteboardRestoreFailed` で終えた場合も、確定操作まで進んだとみなして成功扱いにし履歴へ記録する（PR #52）。

## 6. 検知方式の選定

| 方式 | 採否 | 理由 |
| --- | --- | --- |
| `AXObserver` + `kAXWindowCreatedNotification` | 採用（主） | イベント駆動でレイテンシ最小。アプリ切替時に観測対象を張り替える |
| 200ms ポーリング（`AXUIElementCopyAttributeValue` で windows 列挙） | 採用（補助） | AXObserver が通知を落とすケース（XPC サービス描画）の保険。PanelShown 中は停止 |
| `NSWorkspace` の通知のみ | 不採用 | パネル出現は取れない |
| SIMBL / dylib injection | 不採用 | SIP・署名制約、サンドボックスアプリでは不可能 |

判定条件（すべて満たす）:

1. 対象ウィンドウの `AXSubrole` が `AXDialog` または `AXSheet`（サンドボックス時は `AXSheet` としてホストアプリの子に現れる）
2. 子孫に `AXButton` で title が `開く` / `Open` / `選択` / `Choose` のいずれか
3. 子孫に `AXBrowser` / `AXOutline` / `AXTable`（ファイルリスト）が存在する
4. 子孫に `AXTextField` で `AXDescription` が「保存」「Save As」を含まない（NSSavePanel の除外）

## 7. 注入方式の選定

| 方式 | 採否 | 理由 |
| --- | --- | --- |
| Cmd+Shift+G → ペーストボード + Cmd+V → Return | 採用（主） | すべての NSOpenPanel で動く。日本語パスもペーストなら安全 |
| Cmd+Shift+G シートの `AXTextField` に `AXValue` を直接セット → 「移動」ボタン AXPress | 採用（副） | キーイベントより決定的。シートの構造がバージョン依存のため主にしない |
| `AXURL` 属性の書き換え | 不採用 | NSOpenPanel は書き込み不可 |
| Drag & Drop エミュレーション | 不採用 | CGEvent での D&D は不安定 |

ペーストボード汚染への対策: 注入前に `NSPasteboard.general` の内容を退避し、注入完了後（Return 送出から 200ms 後）に復元する。

## 8. データ

- 設定: `~/.config/openpath/config.toml`（`roots`, `depth`, `include_files`, `auto_confirm`, `hotkey`, `disabled_apps`, `ghq`）
- 履歴: `~/Library/Application Support/openpath/history.json`（`{ path, count, last_used }` の配列。日付は UTC ISO 8601・秒精度）
- ログ: `~/Library/Logs/openpath/openpath.log`（`os.Logger`（統合ログ）+ ファイル出力、5MiB 超過で `.1` に 1 世代ローテーション）。`Log.configure(_:)` を呼ぶまではファイルへ書き込まず統合ログにのみ出力する（アプリは起動直後に呼ぶ。Core のテストでも実ファイルに触れない、PR #36 / #53）。既定の最小レベルは DEBUG ビルドで `.debug`、リリースビルドで `.info`。info 以上のメッセージにはパス・ファイル名を含めない（NFR-05）。パスは `Log.debugPath` で別記録し、統合ログでは常に `.private`、ファイルには平文で出す

## 9. セキュリティ・権限

- 要求する権限: アクセシビリティのみ。`AXIsProcessTrustedWithOptions` で確認し、未付与時は機能を停止して案内する。
- 読み取るデータ: 最前面アプリのウィンドウ階層（パネル判定に必要な範囲のみ）。ウィンドウの内容や入力値は保存しない。
- ネットワーク: 一切使用しない。`com.apple.security.network.client` は付与しない。
- サンドボックス: openpath 自体は非サンドボックス（AX 観測のため）。

## 10. リポジトリ構成（予定）

```
openpath/
├── Package.swift
├── Sources/
│   ├── openpath/            # 実行可能ターゲット (main.swift, AppDelegate)
│   ├── OpenPathCore/        # 状態機械, CandidateIndex, HistoryStore, ConfigStore（純 Swift, テスト可能）
│   └── OpenPathMac/         # PanelWatcher, PaletteWindow, PanelInjector, StatusItem（AppKit 依存）
├── Tests/
│   └── OpenPathCoreTests/   # Swift Testing によるユニットテスト
├── Resources/
│   ├── Info.plist           # LSUIElement = YES（実行ファイルにも埋め込む）
│   └── openpath.entitlements
├── scripts/                 # test（CLT 環境向け swift test ラッパー）, build, sign, notarize, cask 生成
└── docs/                    # 本ドキュメント群
```

`OpenPathCore` は AppKit に依存させず、ファジーマッチ・frecency・設定パースをユニットテスト可能に保つ。
