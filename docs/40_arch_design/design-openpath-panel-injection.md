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
updated: 2026-09-25
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
- 補助ポーリング: 200ms 間隔でフロントアプリの `kAXWindowsAttribute` を列挙し、`isOpenPanel` を評価。**一時停止する条件は「AppCoordinator が Idle でなく、AX 通知を受信でき、かつ追跡中のパネルに選択モードの推定し直しの予定（`PanelContext.isSelectionModeProvisional`、DSN-001 §2.3）が無い」（`PanelShown` / `Injecting`）に統一する**（AXObserver を張れなかったアプリでは、パネルの消滅を検知するため Idle 以外でもポーリングを続ける。判定条件を 1 つにまとめるため、PR #46）。`PanelShown` / `Injecting` 中もパネルの消滅（FR-DETECT-05）を検知するため、AX 通知による走査は続ける（止まり得るのはポーリングだけ、PR #46）。
- 走査は同時に 1 つに絞り、走査中に届いた通知は 1 回の再走査にまとめる。走査中に来たポーリングの周期は捨てる（シリアルな `axQueue` を埋めて、注入の AX 呼び出しを遅らせないため、PR #46）。
- 選択モードの推定し直しの予定がある間もポーリングを続けるのは、推定し直す走査の機会を作るためで、最大 4 回・約 4 秒で終わる。推定し直す時刻を PanelWatchPolicy まで運んで一度だけの走査を予約する方式は、走査結果の型・engine・環境まで変更が広がり、並行するパネル判定の修正 PR と衝突しやすいため、ポーリングを続ける方式にした（走査はキャッシュ済みの判定と矩形の読み取りのみで AX 呼び出しは数回/回、PR #65）。
- ウィンドウ一覧の取得に失敗した場合（`noValue` / `attributeUnsupported` / `cannotComplete` / `invalidUIElement` など）は一時的な失敗（`unavailable`）として扱い、パネルが消えたとはみなさない。有無は実際に一覧を取得できたときだけ判断する（PR #46、CodeRabbit 指摘対応）。
- `disabledAppsDidChange()`: ConfigStore（PROJ-DSN-002 §6）の変更通知から呼び、最前面アプリの張り付け対象を判定し直す。

### 2.2 パネル判定

```swift
func isOpenPanel(_ window: AXUIElement) -> Bool {
    guard isDialogOrSheet(window) || window.identifier == "open-panel" else { return false }  // AXSubrole in [AXDialog, AXSheet] または AXRole == AXSheet、または AXIdentifier == "open-panel"（非モーダル、Issue #83）
    let confirmTitles: Set<String> = ["開く", "Open", "選択", "Choose", "追加", "Add", "アップロード", "Upload"]
    let hasConfirm = window.descendants(role: kAXButtonRole, maxDepth: 6)
        .contains { confirmTitles.contains($0.title ?? "") }
    let hasFileList = window.descendants(roles: [kAXBrowserRole, kAXOutlineRole, kAXTableRole], maxDepth: 6).isEmpty == false
        || window.descendants(role: kAXListRole, maxDepth: 6)
            .contains { ($0.attr(kAXSubroleAttribute) as String?) == "AXCollectionList" }  // アイコン表示
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
- `AXIdentifier` が `open-panel` のトップレベルのウィンドウも候補にする。非モーダルの NSOpenPanel（NSDocumentController の「ファイル > 開く…」。TextEdit の ⌘O など書類ベースのアプリ、`begin(completionHandler:)`）は、ホストのウィンドウ一覧に AXWindow として現れるが、サブロールが `AXDialog` ではなく `AXStandardWindow`（`AXModal` は false）になり、当初の条件 1 で弾かれていた。`runModal`（`choose folder` など）は `AXDialog`。識別子はモーダルでも同じ `open-panel`、保存パネルは `save-panel` で、ローカライズされない（macOS 27 の自プロセスのパネルで確認。ウィンドウの所有者はホストのプロセスで、中身はリモートビュー）。通常のウィンドウ全般は、これまでどおり候補にしない。`AXIdentifier` は、ロール・サブロールで候補にならないトップレベルのウィンドウでだけ、ウィンドウごとに 1 回読んでキャッシュする（Issue #83）。ロール・サブロールと同じく、識別子もアプリが決める属性で、パネルであることの証明にはならない（候補にする手がかりとしてだけ使い、条件 2〜4 の判定を経る）。偽のパネルでパレットが出ても、注入は利用者の確定と注入先の確認（§3）を経る点は、`AXDialog` による既存の条件と変わらない。
- 確定ボタンに「アップロード」/「Upload」を追加した（Safari の `input[type=file]` パネル対策。TST-001 S-06）。
- ファイル一覧の条件（判定条件 3）に、アイコン表示（ロールが `AXList` でサブロールが `AXCollectionList` の要素）を加えた。`AXList` 全般ではなくサブロールを `AXCollectionList` に限定したのは、`AXList` が設定シートの一覧などファイル一覧でない要素にも使われ、限定しないと確定ボタンを持つ設定シート等を開くパネルと誤判定するため（`AXCollectionList` は `NSCollectionView` の公開サブロールでローカライズされない）。サブロールは `AXList` の要素だけ読むため、リスト表示・カラム表示の判定では AX 呼び出しは増えない（PR #64）。
- 子のシートを 2 段まで探す（リモートビューが外側のシートの下にさらにシートを重ねる構成に対応）。ただし、ファイル一覧の行（ファイル名を保存欄と誤認しないため）と、子のシート自体の中（開くパネルでないダイアログをパネルと誤判定しないため）へは降りない。
- 保存パネルの除外条件は `AXDescription` とタイトルの両方を「Save」「保存」「名前」で調べる（当初案のコードは説明を「Save」、タイトルを「名前」でしか見ておらず、ARCH-001 §6 の「保存」「Save As」とも食い違っていたため統一した、PR #56）。検索フィールドは対象外。
- `descendants` は幅優先で最大 6 階層、1 パネルあたり 400 要素で打ち切る（サンドボックスパネルはリモート要素のため往復コストが高い）。
- 判定結果は **パネルの要素（ダイアログ・シート）をキーに** キャッシュする（ホストのウィンドウはシートの有無で変わらないため。ウィンドウにはロールと直前のパネルだけを持たせる、PR #56）。要素が欠けていて判定できなかった候補は、間隔を倍々に空けて判定し直す（サンドボックスアプリのパネルは別プロセス描画のため、出現直後は中身がまだ無いことがある）。
- 判定はクロージャ（`PanelDetector`）ではなく `PanelDetecting` プロトコル（既定実装 `OpenPanelDetector()`）として持つ（PR #56。#17 時点のクロージャ API は削除）。`AXApplicationObserver` の破棄通知は対象要素も判定側へ渡し、走査で見つけたパネルの要素にも `kAXUIElementDestroyedNotification` を追加登録する（最大 8 要素、古いものから解除。PR #46 で見送った対処案を PR #56 で採用）。
- AX の要素参照には 1 回 0.25 秒のメッセージングタイムアウトを設定する（既定の約 6 秒のままだと応答しないアプリで `axQueue` が止まるため）。タイムアウトした要素は子なしとして扱い、一時的な失敗としてパネルを消えたとはみなさない。
- `panelAppeared` を送るとき `panel detected` を、パネルの消滅では `panel gone` を info でログに出す（`Log.configure` が必須。TST-001 §4 のスモークスクリプトが grep する。Idle に戻った後の再通知でも出す）。判定のコスト（AX 呼び出し回数・所要ミリ秒）は debug で出す。どちらもパスは含まない（PR #56）。
- 判定の診断を debug で出す（`logLevel debug`、Issue #83）。ウィンドウを初めて見たときと候補を判定したとき（判定し直しを含む）だけ、`panel check (…)` を 1 行ずつ出す: 対象（ウィンドウ / シート）、role・subrole・AXIdentifier、候補にした理由、弾いた条件（`notCandidate` / `noConfirmButton` / `noFileList` / `looksLikeSavePanel`、探索の上限で打ち切ったら `truncated`。中身を読めなかった候補は `unreadable` を候補ごとに 1 回だけ）、子孫の要約（ボタンの表題と有効状態、一覧の role・subrole、入力欄の説明・タイトルの有無と一致した保存パネルの語、訪問数と深さ、role ごとの数）。走査の要約 `panel scan (pid, bundleId, windows)` は変わったときだけ、張り付け・AXObserver の失敗・ウィンドウ生成とフォーカス移動の通知は `panel watch …` で出す。パス・ファイル名・ウィンドウタイトル・入力欄の文字列は出さない（ボタンの表題も、"/" を含むものは `<path-like>`、末尾が「.拡張子」のものは `<file-like>` に伏せる）。要約のための AX の読み取りは debug のときだけ行い、失敗しても判定の結果を変えない。`open panel classified` の `axCalls` からは除き、`diagnosticAXCalls` として別に出す（`elapsedMs` には含まれる）。
- パレットを表示するたびに `palette shown (id: …)` を info でログに出す（`PalettePresenter` がウィンドウを出した直後。同じパネルの再表示・ホットキーでの再表示でも出す）。`panel detected (id: …)` と同じパネル ID を含むため、同じ ID の `panel detected` の後の最初の `palette shown` とのタイムスタンプ（ミリ秒）の差を検知レイテンシ（FR-DETECT-03）として計測できる（#30）。パスは含まない。
- サンドボックスアプリでは、パネルは `openAndSavePanelService` のプロセスで描画されるが、AX ツリー上はホストアプリのウィンドウの `AXSheet` 子要素（シート型）か、ホストのウィンドウ一覧の AXWindow（ダイアログ型・非モーダル。上記）として見える。ホスト側の観測だけで検知できるが、要素アクセスの往復が遅いため判定は `axQueue` 上で同期的に行う（各ウィンドウに判定関数を適用する形。DSN-001 の当初案は判定関数を async にする想定だったが、axQueue 上の 1 ジョブにまとめる方が単純で速い、PR #46）。

### 2.3 パネルの選択モード推定

- 選べるかどうかの判定は表示形式で分かれる。**リスト表示・カラム表示**は名前の文字色（`AXForegroundColor`）の不透明度を主に使う。実機の AX ツリーを調べた結果、ファイル行の `AXEnabled` は選べる/選べないで変わらず（両方 true）、名前の文字色の不透明度だけが変わる（選べる行 0.847、選べない行 0.247）。しきい値は 0.5（通常 0.85 と選べない 0.25〜0.26 の間）。文字色を読めない行は判断しない（当初案の `AXDisabled` 判定から変更、PR #60）。
- **アイコン表示**は名前の要素が `AXImage`（`AXTitleUIElement` を持たず、属性付き文字列の読み取りにも非対応）のため文字色を読めない。代わりに `AXEnabled` をそのまま使う（選べない項目だけ false になることを実機で確認済み）。`FileListRow.isEnabledAuthoritative` で、その行が `AXEnabled` を判断にそのまま使ってよい行かどうかを表す（PR #64）。
- ディレクトリかどうかは、名前の要素（リスト表示・カラム表示は `AXTextField`、アイコン表示は `AXImage`）が持つ `AXURL`（`file:///.file/id=…`）の末尾が `/` かで判別する（表示形式・言語に依存しないため。種類列やアイコンの説明はローカライズされる、展開の三角はリスト表示にしかない等の理由で不採用、PR #60）。
- 行の読み取り: カラム表示は最後の `AXColumns` 列（プレビュー列がある場合はその左）の `AXList.AXVisibleChildren`、リスト表示（`AXOutline` / `AXTable`）は `AXVisibleRows`、**アイコン表示は `AXList`（`AXCollectionList`）の `AXVisibleChildren`（セクション）の、それぞれの `AXVisibleChildren`（項目 `AXGroup`。最初の子の `AXImage` を名前の要素とする）**。いずれも表示中の行だけを読む（`AXChildren` はフォルダの全項目を返してしまうため）。20 行を読む AX 呼び出しはカラム表示最大 54 回、リスト表示 69 回、アイコン表示 52 回（テストで固定、PR #60 / #64）。
- 先頭 20 行のうちディレクトリ以外の行を見て、選べる行が 1 つでもあれば「ファイルも選べる」、すべて選べなければ「フォルダのみ」、ディレクトリ以外の行が無い・判断できない行があれば「推定できない」の 3 値で決める。推定できない場合は `isDirectoriesOnly = false`（設定 `include_files` に従う。`PanelContext` の形は変えない）。
- 表示中の行だけでは推定できない場合を補う（Issue #73）。
  - **末尾の行**: 先頭の行がディレクトリばかり（ディレクトリ以外の行が無い）で、一覧に続きがあれば、一覧の末尾から最大 10 行を読み、先頭の行と合わせて同じ規則で推定する。「フォルダを先頭に表示」の並びやサブフォルダの多いフォルダでは、ファイルが表示範囲の外（末尾）に並ぶため。`AXUIElementGetAttributeValueCount` で要素数を読み、`AXUIElementCopyAttributeValues` で末尾の範囲だけを読む（フォルダの全項目を受け取らない）。カラム表示（列の `AXList` の `AXChildren`）とリスト表示（`AXRows`）だけが対象で、アイコン表示は読まない（NSCollectionView は表示範囲の外の項目を実体化しておらず、要素数は全項目を数えるが範囲外の要素は読むと `invalidUIElement` になる。macOS 27 のプロセス内のパネルで確認）。末尾の読み取りに失敗しても先頭の行だけで推定する。増える AX 呼び出しは、要素数 1 + 範囲の読み取り 1 + 10 行（ディレクトリの行はカラム表示 2 回・リスト表示 3 回、ファイルの行は 3 回・4 回、文字色を読めないファイルの行は `AXEnabled` も読むため 4 回・5 回）で、最大でカラム表示 42 回・リスト表示 52 回（数え方は `FileListSampleTests.trailingAXCallCount` で固定）。末尾を読むのは先頭の行がディレクトリばかりのときだけなので、推定 1 回の最大は、先頭 20 行がディレクトリ・末尾 10 行が文字色を読めないファイルの場合でカラム表示 86 回・リスト表示 112 回になる（文字色を読める選べないファイルなら 76 回・102 回。`FileListSampleTests.worstCaseAXCallCount` で固定）。末尾は種類の分かる行を読めたとき（推定し直さないとき）にしか読まないため、推定し直しの 1 回あたりの上限（§5 の最大 69 回）には加わらない。
  - **表示範囲の外にある今のフォルダの列**: カラム表示で今のフォルダの列に表示中の項目が無い（ブラウザが今のフォルダの列まで横にスクロールしていない）場合は、列の `AXChildren` の先頭 20 件を読む（macOS 27 のプロセス内のパネルで、深い階層を開くと `AXVisibleChildren` が空になることを確認）。増えるのは範囲の読み取りの 1 回で、行の読み取りは表示中の行を読む場合と同じ回数になる（空の列でも 1 回増えるが、推定し直しの 1 回あたりの上限には収まる）。
  - それでも、空のフォルダ・ディレクトリしか無いフォルダは推定できない。パネルの形（サイドバーや確定ボタン）にフォルダのみのパネルを見分ける手がかりは見つからなかった（サイドバーの「メディア」はファイルも選べるパネルにだけ出るが、種類で絞り込むパネルでは出ない）。推定できない場合の扱いは変えない（`include_files` に従う）。既定の `include_files = false` ではディレクトリだけが候補になるため影響は無く、`include_files = true` でもファイルを選べるパネルでファイルを隠す誤りより、フォルダのみのパネルで選べない候補が混ざる方を許容する。
  - 推定の結果は、info のログ `panel detected` / `panel updated` の後ろに `selectionMode`（`directoriesOnly` / `filesSelectable` / `undetermined`）と、推定に使った行の内訳（`sampledRows` / `sampledDirectories` / `sampledFiles`）として出す（書式は `PanelWatchLogMessage`。`panel detected (id: …, directoriesOnly: …` までは変えない）。`directoriesOnly: false` が「ファイルも選べる」か「推定できない」か、推定できない理由（行 0: 空・読み込み前・読み取り失敗、ディレクトリ以外 0: ディレクトリしか無い、ディレクトリ以外があるのに推定できない: 選べるかを読めない）をリリースビルドのログで見分けるため。
- 推定は開くパネルと判定した最初の検知（Idle 中）でのみ行い、判定結果と一緒にキャッシュする。**種類の分かる行を 1 行も読めなかった場合だけ**、判定の再確認と同じ間隔（250ms から倍々に 4 回）で推定し直す。行を読めたうえで推定できなかった場合（例: 先頭がディレクトリのみ）は、フォルダを移動しても推定し直さない（PanelShown 中の走査で 20 行を読み直すと DSN-001 §5 の AX 呼び出し上限を超えるため）。推定し直した結果は `panelContextChanged`（DSN-001 §2.1）で AppCoordinator に届け、表示中のパレットへ反映する（PR #60 の時点では並行実装中の #21 / #22 / #27 と衝突するため #27 へ申し送っていたもの。PR #65 で実装、ARCH-001 §5）。
- 中身のファイル一覧は、判定と同じ幅優先探索で最後に見つけたファイル一覧ロールの要素とする。サイドバー（`AXOutline`）も同じロール条件を満たすが、中身の一覧より先に見つかるため対象にならない（PR #60）。アイコン表示のパネルでサイドバーを表示している場合、DSN-001 §2.2 の条件 3 の追加（PR #64）以前はサイドバーが唯一のファイル一覧として検知され、行が `AXURL` を持たないため常に「推定できない」になっていた（PR #64 で中身のアイコン表示自体が対象になり解消）。

### 2.4 パネルの位置取得

- `kAXPositionAttribute` / `kAXSizeAttribute` からパネル矩形を取得する。AX 座標（Quartz のグローバル座標、プライマリ画面基準）と `NSScreen` 座標（Cocoa のグローバル座標）はどちらもポイント単位でプライマリ画面基準のため、`y' = プライマリの高さ - (y + 高さ)` の反転だけで変換できる（メイン以外のディスプレイ・Retina 混在でも同じ式で成立し、スクリーン一覧は不要）。プライマリの高さは `CGDisplayBounds(CGMainDisplayID())` から取る（`NSScreen` は main スレッド前提のため使わない）。
- `PanelContext.frame` は変換後の `NSScreen` 座標で持つ（`PalettePlacement` / `PaletteWindow.show(near:)` にそのまま渡せる）。Core の `OpenPanelLocator` / `LocatedOpenPanel` と Mac の `DetectedPanel` は AX 座標のまま持つ。矩形を読めなかったパネルはプライマリ画面左上の点（`(0, 高さ)`）になる（PR #60）。
- 変換は `PanelScanner`（axQueue）で走査のたびに行う。矩形は DSN-001 §5 のとおり走査のたびに読み直す（1 回に固定しない。パネルが動いたときに最新の位置でパレットを出し直すため、PR #56 の判断を PR #60 が踏襲）。

## 3. PanelInjector

### 3.1 主方式: Cmd+Shift+G + ペースト

```
1. アクセシビリティ権限を currentStatus() で確認（未付与なら axError(apiDisabled) で即失敗）
2. 基準走査: 現在の AXSheet 数とパス入力欄（placeholder に "パス"/"Path"/"Go to" を含む AXTextField / AXComboBox）数を記録（上限 600ms）
3. CGEvent: Cmd+Shift+G  keyDown/keyUp（kVK_ANSI_G, flags [.maskCommand, .maskShift]）
4. 最大 600ms、50ms 間隔（50, 100, …, 550ms）で「移動先シート」の出現を基準比で判定
   - 判定: 2. の基準より AXSheet 数またはパス入力欄数が増えた
   - パネル自体がシートとして表示される場合（サンドボックスアプリ等、⌘⇧G 前から AXSheet がある場合）も、基準からの増分で見るため誤検知しない
5. シート出現を確認できたら、NSPasteboard.general の全 items を退避（types ごとに Data で保持。いずれかの item が org.nspasteboard.ConcealedType を持つ場合はデータを読み出さず退避もしない）→ path を org.nspasteboard.TransientType 付きで setString(_:forType: .string)
6. CGEvent: Cmd+A → Cmd+V（フィールドの既存値を置換）
7. 100ms 待機（ペースト反映）
8. CGEvent: Return（シート確定 → パネルが移動）
9. auto_confirm または Cmd+Enter の場合: 300ms 待機後、パネル内「開く」ボタンを AXPress（auto_confirm フック。DSN-001 §2.2 のタイトル一覧で確定ボタンを探す）
10. Return から 200ms 後（9. のフックが 200ms を超えた場合はフック完了直後）に、ペーストボードの changeCount が 5. でパスを書き込んだ直後の値から変わっていなければ退避内容へ復元する。変わっていれば、注入中に書き込まれた新しい内容を優先し復元しない。元の内容が機密（5. の ConcealedType）だった場合は復元せず、差し替えたパスを消して空にする
```

- **機密の内容（`org.nspasteboard.ConcealedType`）は注入後に復元しない**（オーナー判断）。パスワードマネージャーは一定時間後に自分が置いた内容を消すが、openpath が書き戻すと changeCount が進んで「ユーザーが別の内容をコピーした」とみなされ、自動消去が働かなくなるため。空にするのは意図どおりなので `pasteboardRestoreFailed` にはしない（空にする書き込みが失敗しても、利用者の内容は失われていないため失敗にしない）。パスを書き込めなかった場合（`timeout(.waitPaste)`）も書き戻さない。機密の内容は型の一覧だけで判定し、データを読み出して複製を持つこともしない。退避した通常の内容も、復元を済ませた時点で手放す。
- 機密かの判定と退避はペーストボードを別々に読むため、その間に機密の内容へ書き換わると、機密の内容を退避して書き戻してしまい得る。判定の直前の changeCount を記録し、判定の直後と退避の直後に変わっていたら、何も書き込まずに `timeout(.waitPaste)` として副方式（ペーストボードを使わない AX 直接セット）へ回す。
- nspasteboard.org の他の印の扱い: `org.nspasteboard.TransientType`（置いたアプリがすぐ片付ける一時的な内容）と `org.nspasteboard.AutoGeneratedType`（アプリが自動で置いた内容）は機密ではないため、従来どおり印ごと書き戻す（印も戻るので、クリップボード履歴アプリに記録されない扱いも保たれる）。

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
- `PanelShown` 中、選択モードの推定が確定した後の 1 回の走査あたりの AX 呼び出しを 50 回以下に抑える（判定キャッシュは 1 回。位置取得は 1 回に固定せず走査のたびに読み直す。パネルが動いたときに最新の位置で出し直すため、PR #56 / #60）。選択モード推定（§2.3）は、種類の分かる行を 1 行も読めない間だけ、最初の検知を含め最大 4 回、走査のたびに読み直す（1 回あたり最大 69 回）。`isSelectionModeProvisional` の間は `PanelShown` 中もこの読み直しが起こり得るため、上記の 50 回には含めない。行を読めて確定すれば、以降の走査では増えない（PR #60 / #65）。
- 注入中は `PaletteWindow.isLocked = true`。ロック中のキー入力は捨てる。
- 注入は `InjectionSerialGate` で 1 件ずつ直列に実行する（DSN-001 §3.1、PR #45）。

## 6. 権限

- 起動時・ポーリングとも `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])` に統一する（`AccessibilityPermission.currentStatus()`。当初案はポーリングに `AXIsProcessTrusted()` としていたが、意味は同じで「プロンプトを出さない」ことをコード上で明示するため統一した、PR #37）。未付与なら StatusItem にバッジを出し、`PanelWatcher.start()` は呼ばない。
- 権限変更の検知: 5 秒間隔でポーリングする（付与直後に自動で有効化するため）。実装は `DispatchSourceTimer` ではなく `Task.sleep` のループ（`ValueChangePoller`）で、生成時に状態を読み、以降は変化があったときだけ通知する。
- 権限のないプロセスから他アプリへ AX を呼ぶと、`apiDisabled` ではなく `cannotComplete (-25204)` が返る（macOS 26 で実機確認済み）。エラーコードでは権限の有無を判定できないため、PanelInjector は注入開始時に `AccessibilityPermission.currentStatus()` で直接確認する（DSN-001 §3.1、PR #37 / #45）。
