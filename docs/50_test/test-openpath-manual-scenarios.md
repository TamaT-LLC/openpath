---
id: PROJ-TST-002
layer: L5
feature: openpath
scope: global
status: Draft
upstream:
- PROJ-TST-001
downstream: []
owner: TakehiroT
updated: 2026-10-04
---

# 手動シナリオテスト: openpath（実機確認チェックリスト）

## 1. 使い方

アクセシビリティ（AX）を使う検知と注入は CI で自動化できない（TST-001 §1）。そのため、権限を付与した `openpath.app` で確かめる項目をこの文書にまとめた。

出典は次のとおり。

- TST-001 §3 の S-01〜S-13 と §3.1（統合時の追加確認項目）
- PR #65 の実機確認チェックリスト（0〜6 章）
- PR #67（初回起動）の実機確認チェックリスト
- PR #66 の「反映しなかったもの」のうち、TST への申し送り
- オーナー判断で決まった仕様（§1.2）

使う場面:

- Phase 1 の受け入れ（TST-001 §6）では全項目を確かめる。
- アプリの挙動に関わる PR では、変更の影響範囲の項目だけを確かめる。§14 の対応表で項目を選び、PR テンプレートの「手動シナリオ」欄に ID と結果を書く。

記録の仕方:

- §2 の実施環境と、各表の「結果」「備考」を埋めた写しを、PR 本文か Issue のコメントに貼る。
- 「結果」は次のいずれか。日をまたいで実施したら、備考に日時も書く。
  - `OK` / `NG`
  - `未確認`: 実施しなかった、または確認できなかった（アクセシビリティ権限の無い環境など）。理由を備考に書く
  - `—`: 対象外（その変更に関係しない項目、未実装の仕様）
- NG の項目は、ID を題名に含めた個別の Issue を起票し、備考に Issue 番号を書く。

項目 ID は、TST-001 §3 のシナリオは `S-01`〜`S-13` のまま使い、それ以外は章ごとの接頭辞と連番にした（例: `PAL-03`）。項目を追加するときは、既存の番号を振り直さずに末尾へ足す。

### 1.1 手順の読み替え

TST-001 §3 と PR #65 の手順のうち、そのままでは実施できないものを次のように読み替える。

- S-01: Finder の ⌘O は選択中の項目を開く操作で、「開く」ダイアログは出ない（PR #67）。TextEdit の「ファイル > 開く…」（⌘O）で確かめる。
- S-11: TextEdit の ⇧⌘S は「複製」に割り当てられていることがある。保存ダイアログは、未保存の新規書類で ⌘S を押して出す。
- S-12: PR #65 の手順は Finder（`com.apple.finder`）を使うが、Finder には「開く」ダイアログが無い。TextEdit（`com.apple.TextEdit`）で確かめる。

### 1.2 オーナー判断で決まった仕様

次の 3 点はオーナー判断で決まり、PR #69 で実装した。PR #69 より前のビルドで実施する場合は、該当する項目の結果を `—`（対象外）にする。

- パスワードマネージャーなどの機密クリップボード（`org.nspasteboard.ConcealedType` を含む内容）は、注入後に復元せず空にする。書き戻すとパスワードマネージャーの自動消去が効かなくなるため（CLIP-02、DSN-001 §3.1）。
- メニューの「有効」は UserDefaults（`jp.tamat.openpath` のキー `enabled`）に記録し、次の起動は前回の値で始める。PR #65 時点の「起動のたびに有効に戻る」から変わった（MENU-02、UX-001 §6）。起動処理の完了のログにも「有効」が付く（`起動処理を終えました（アクセシビリティ権限: あり、有効: はい）`）。
- 候補 0 件の文言は「一致する候補がありません。~/ や / で始まるパスも入力できます」（PAL-06、UX-001 §5）。

パレットを出すたびに、`panel detected (id: …)` と同じパネル ID の `palette shown (id: …)` がログに出る（PR #69、DSN-001 §2.2）。スモークテスト（SMK-02）はこの 2 行の時刻の差を検知からパレット表示までの時間として出す。

## 2. 実施環境

| 項目 | 記録 | 確かめ方 |
| --- | --- | --- |
| 実施日時 |  | 開始と終了 |
| 実施者 |  |  |
| macOS |  | `sw_vers -productVersion` |
| openpath |  | `plutil -extract CFBundleShortVersionString raw build/openpath.app/Contents/Info.plist` とコミット（`git rev-parse --short HEAD`） |
| ビルドと署名 |  | `./scripts/build.sh`（universal / arm64）、`./scripts/sign.sh`（ad-hoc / Developer ID） |
| ディスプレイ |  | 台数、Retina と非 Retina の混在の有無 |
| 入力ソース |  | ことえり（ライブ変換の有無）/ Google 日本語入力 / ATOK など |

対象アプリのバージョンは `plutil -extract CFBundleShortVersionString raw <アプリ>/Contents/Info.plist` で確かめる。

| アプリ | 場所 | バージョン |
| --- | --- | --- |
| TextEdit | `/System/Applications/TextEdit.app` |  |
| Claude Desktop | `/Applications/Claude.app` |  |
| Cursor | `/Applications/Cursor.app` |  |
| VS Code | `/Applications/Visual Studio Code.app` |  |
| Safari | `/Applications/Safari.app` |  |
| その他（INJ-03 / INJ-04 で使ったアプリ） |  |  |

## 3. 準備（PRE）

出典: PR #65 §0、PR #67 §0。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| PRE-01 | `./scripts/build.sh && ./scripts/sign.sh` | 警告なく `build/openpath.app` ができ、署名の検証が通る |  |  |
| PRE-02 | 起動中の openpath（インストール版・別の場所のビルド）を終了する。初回の状態に戻す: `tccutil reset Accessibility jp.tamat.openpath`、`defaults delete jp.tamat.openpath onboardingFinished`、`defaults delete jp.tamat.openpath enabled`（「有効」の記録）、`~/.config/openpath/config.toml` を退避する | 同じ bundle id の openpath が残っていない（ログを共有するため、スモークテストは複数起動を前提不足にする）。ad-hoc 署名は再ビルドのたびに権限の付け直しが要る。`defaults delete` は記録が無ければエラーになるが問題ない |  |  |
| PRE-03 | 別の端末で `tail -f ~/Library/Logs/openpath/openpath.log` | 以降の項目でログを確かめられる |  |  |
| PRE-04 | 注入（§6・§9）を切り分けられるよう、リリースビルドでも debug ログを出す: openpath を終了し、`defaults write jp.tamat.openpath logLevel debug` を実行してから起動し直す | 起動時のログに `設定 logLevel により、ログの最小レベルを debug にしました` が出る。注入のたびに `注入するパス`・`主方式:` / `副方式:` の各ステップ（経過時間付き）・`確定前の確認:` が出る。次の 2 つは条件付きで、出なくても失敗ではない: `確定前の移動先シートの入力欄` / `候補の選択` は移動先シートの入力欄を見つけられたときだけ出る（見つからなければ `確定前の確認: 移動先シートの入力欄が見つからないため確かめません`）。`移動後のパネルの現在地（表示名）` は自動確定しない注入（Enter）の成功後だけ出る（auto_confirm・⌘Enter ではパネルが閉じるため読まない）（Issue #74） |  |  |

debug ログは注入したパスなどを含む。実施が終わったら openpath を終了し、`defaults delete jp.tamat.openpath logLevel` で既定（info）に戻す。ログを共有する前に、パスを含む行（`[DEBUG]`）を取り除くか、共有してよい範囲か確かめる。

## 4. 初回起動と権限（ONB / PERM）

出典: PR #67 §1〜§3、PR #65 §1、UX-001 §5〜§7。上から順に実施する。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| ONB-01 | `open build/openpath.app` | `lsappinfo info -app jp.tamat.openpath` の type が `UIElement`（Dock に出ない。macOS 27 では `type="UIElement"`、26 までは `"type"="UIElement"` と出る）。ログに `openpath 0.1.0 を起動します` → `起動処理を終えました（アクセシビリティ権限: なし、有効: はい）` → `ホットキー ctrl+shift+o を登録しました` → `初回起動の案内: notShown → explainingPermission` |  |  |
| ONB-02 | 案内を見る | 「openpath へようこそ」が画面中央に前面で出る。本文が 3 行（用途 / キー操作とパスを送る / アクセシビリティだけ・通信しない・保存しない） |  |  |
| ONB-03 | `~/.config/openpath/config.toml` を見る | 起動時に既定値で作られている（ghq があれば `roots` に ghq root。ghq の root が取れなければ `roots = ["~"]`）。`roots` の上のコメントが、どちらを検索対象にしたかに合っている。`roots = ["~"]` の場合は、起動直後にデスクトップ・書類・ダウンロードのアクセス確認が出ることがある（ONB-20） |  |  |
| PERM-01 | 案内を出したまま、メニューバーのフォルダアイコンを開く | アイコンにバッジ。先頭に通知「アクセシビリティ権限がありません」。項目が「有効 / 候補を再構築 / 設定ファイルを開く… / 履歴をクリア…」「ログイン時に起動 / アクセシビリティ設定を開く… / はじめに…」「終了」の 3 グループで、どれも選べる |  |  |
| PERM-02 | TextEdit で ⌘O | パレットが出ない |  |  |
| PERM-03 | メニュー先頭の通知、または「アクセシビリティ設定を開く…」を選ぶ（開いたシステム設定は閉じておく） | システム設定の「プライバシーとセキュリティ > アクセシビリティ」が開く |  |  |
| ONB-04 | Return（「システム設定を開く」） | 案内が「システム設定で openpath を許可してください」に替わり、「プライバシーとセキュリティ > アクセシビリティ」が前面に開く |  |  |
| ONB-05 | システム設定の一覧を見る | openpath が載っている。載っていなければ「+」で `openpath.app` を追加できる（案内の文言どおり） |  |  |
| ONB-06 | 案内の「システム設定をもう一度開く」 | システム設定が前面に来る |  |  |
| ONB-07 | config.toml を消してから、openpath をオンにする | 5 秒以内に案内が「準備ができました」に替わって前面に出る。ログに `awaitingPermission → completed`、`アクセシビリティ権限が付与されました`、`パネルの監視を始めました`、`設定ファイルが無かったため既定の内容で作成しました`。バッジと先頭の通知が消える |  |  |
| ONB-08 | 「試してみる」 | 案内が閉じ、フォルダ選択のダイアログ（「選択」ボタン、案内の文言付き）が前面に出る。ログに `「試してみる」のダイアログを出しました` |  |  |
| ONB-09 | ダイアログを見る | パレットが重なり、ディレクトリだけが候補に出る（ログ `panel detected (… directoriesOnly: true)`）。同じパネル ID の `palette shown` までが 300ms 以内（S-01 と同じ測り方）。ログに `「試してみる」のダイアログを前面に出しました（試行 N 回、…ms）` が出る（試行回数と ms を備考に写す）。前面に出なかった場合は、ログの `「試してみる」のダイアログを前面に出せませんでした（試行 N 回、…ms、最後の状態: …）` を備考に写し、案内のとおりダイアログを一度クリックするとパレットが出るかも書く（PR #77） |  |  |
| ONB-10 | フォルダ名か `~/Library` のようなパスを打って Enter → 最後にキャンセル | ダイアログがそこへ移動する。キャンセルで閉じるとパレットも消える |  |  |
| ONB-11 | ONB-08〜ONB-10 の間を通して | オートメーションの許可ダイアログ（「openpath が "…" を制御しようとしています」）が出ない |  |  |

## 5. 設定の前提とスモークテスト（SMK）

出典: TST-001 §3 の前提、§4。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| SMK-01 | config.toml を `roots = ["~/repos"]`、`[ghq] enabled = true` にして保存 | ログに `設定の変更に合わせて候補を再構築します` |  |  |
| SMK-02 | `./scripts/smoke-open-panel.sh`（ダイアログが最前面に出なければクリックする） | 最後の行が `OK`、終了コード 0。`panel detected` の時刻と、同じパネル ID の `palette shown` までの時間（`palette shown: …（panel detected から Nms）`）を備考に写す |  |  |

## 6. 中心フロー（S-01〜S-05、S-07a、S-07b、FLOW）

出典: TST-001 §3 と §3.1（再通知・履歴、注入）、PR #65 §2、REQ-001 §5。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| S-01 | TextEdit の「ファイル > 開く…」（⌘O、§1.1） | パレットがパネルの右上（内側 12pt）に出る。検知からパレット表示まで 300ms 以内（FR-DETECT-03）: 起点はログの `panel detected (id: …)` の時刻、終点は同じパネル ID の `palette shown (id: …)` の時刻で、その差を備考に写す（ログの時刻はミリ秒まで出る。パネルが画面に出てから検知までの時間はログに出ないため含まない）。検索フィールドにフォーカスがあり、打った文字がパレットに入る。空入力では frecency の上位（履歴が無ければパス順）が出る |  |  |
| FLOW-01 | パレットが出た直後を見る | 「一致する候補がありません」が一瞬見えてから候補に変わる、というちらつきが無い |  | #91 で修正。最初の候補が届くまで最長 100ms パレットを出さないため、`palette shown` の時刻は候補を反映して出した時刻になる（S-01 の差に候補の検索の時間が含まれる）。100ms を過ぎて出た場合は debug ログに `最初の候補が待ちの上限（initialRowsWaitLimit）までに届かなかったため、…` が出て、候補が届くまでリストは空になる（0 件の案内は出ない）。録画で初出の瞬間を捉えられないときは debug ログ（PRE-04）で判定する: 新しいパネルの `palette shown (id: X)` の直後の `palette reveal (id: X, rows: N, emptyMessage: false, waitedForInitialRows: true, waited: …ms, …)` で `emptyMessage: false` なら OK（最初のフレームで案内を出していない）。`waitLimitReached: true` は上限で出した（リストは空で案内も無い）ことを表し、頻度を備考に写す。`emptyMessage: true` は候補が本当に 0 件のときだけ正しい |
| FLOW-02 | 起動直後にパネルを開く | フッターに「候補を構築中…」。構築を終えると消え、候補が増える（選択は保たれる）。5 分ごとの再構築ではフッターが変わらない |  |  |
| S-02 | Claude Desktop の「フォルダを追加」 | パレットが出て、ディレクトリだけが候補に出る（ログ `directoriesOnly: true`） |  |  |
| S-03 | Claude Desktop で `fern` と打って Enter | 「パネルへ移動中…」を出したままパネルが該当リポジトリへ移動し、パレットが閉じる。パネル側の Enter でリポジトリを開ける（受け入れ基準） |  |  |
| FLOW-03 | S-03 の注入中のキー操作を見る | ⌘⇧G・ペースト・Return がパレットではなくパネルに届く |  |  |
| FLOW-04 | S-03 の成功後、パネルを開いたままにする → Ctrl+Shift+O | パレットが出直さない。Ctrl+Shift+O では再表示でき、前回の検索語と選択が残っている（PR #52） |  |  |
| S-04 | Cursor の File > Open Folder で `open` → Enter → Enter | 該当フォルダを開ける（受け入れ基準） |  |  |
| S-05 | VS Code の File > Open… で候補を選んで Cmd+Enter | 移動して「開く」まで押される。次にパネルを開くと、その場所が空入力の上位に出る（履歴の記録） |  | #89: シート型・非モーダルのパネルでも「開く」を探し、押せる状態（AXEnabled）になるまで待ってから押す。debug ログの `auto_confirm: 確定ボタンを表題で特定しました`（または `…既定ボタン（AXDefaultButton）で特定しました`）と `auto_confirm: 確定ボタンを押しました` を見る。#29: macOS 26 の VS Code のパネル（リモートのパネル）では、注入先のプロセスへの ⌘⇧G が届かず、システム経由の / か ⌘⇧G で移動先シートが開く（INJ-07）。#29（全体タイムアウトを 2.5 秒に延長）: openpath を起動し直した直後（経路の記憶が無い 1 回目）の Cmd+Enter でも、`timeout(overall)` にならずに「開く」まで押されること。PR #110 の QA では、経路を覚えた後の Cmd+Enter が主方式の fieldMismatch から副方式に回って 1,383ms で成功した。1 回目は ① の待ち（約 200ms）が加わるため 1.5 秒を超えうる。debug ログの `副方式で注入しました（+Nms）`（主方式なら `主方式で注入しました（+Nms）`）の Nms を備考に控える |
| FLOW-05 | `auto_confirm = true` にして Enter（確かめたら戻す） | 移動して「開く」まで押され、パネルが閉じた後も履歴に残る |  |  |
| S-07a | `~/Documents/資料` を作って選ぶ | 正しく移動できる（日本語を含むパスの注入、REQ-001 §5 受け入れ基準） |  |  |
| S-07b | カタカナ名のディレクトリ（例 `~/repos/シリョウ`）を作り、ひらがな（`しりょう`）で検索する | 候補に出て移動できる（かな同一視、DSN-002 §5）。漢字の読みでの検索（`しりょう` で `資料` を検索すること）は現仕様の対象外（Issue #87、Phase 2） |  |  |
| FLOW-06 | NFD の名前のディレクトリ（`mkdir ~/Documents/"$(printf 'データ' \| iconv -f UTF-8 -t UTF-8-MAC)"`）を選ぶ | NFC で打っても候補に出て、移動できる（NFC/NFD 同一視、DSN-002 §5） |  | Issue #86 の QA で確認済み |
| FLOW-07 | openpath を終了して `~/Library/Application Support/openpath/history.json` を見る | 確定したパスが保存されている |  |  |

S-01 の備考（パレットが出ないときの切り分け、Issue #83）: debug ログで、ダイアログのウィンドウをどう判定したかが分かる。

1. openpath を終了し、`defaults write jp.tamat.openpath logLevel debug` を実行してから起動し直す。
2. TextEdit を前面にして ⌘O を押し、2 秒待ってからダイアログを閉じる。
3. `grep -E 'panel (watch|scan|check|detected|gone)|open panel classified|palette shown' ~/Library/Logs/openpath/openpath.log` の、手順 2 の時刻の行を備考か Issue に貼る。
4. 終わったら openpath を終了し、`defaults delete jp.tamat.openpath logLevel` で元に戻す。

| ログ | 意味 |
| --- | --- |
| `panel check (… identifier: open-panel, candidate: openPanelIdentifier, … result: openPanel, …)` の後に `panel detected` | 検知できた |
| `panel check (target: window, … subrole: AXStandardWindow, identifier: …, result: rejected: notCandidate)` | ダイアログのウィンドウを候補にしなかった。identifier の表示（`save-panel`・`<other len: …, contains: panel>` など）を Issue に書く（`open-panel` 以外なら判定条件の追加が要る） |
| `result: rejected: noConfirmButton` / `noFileList` / `looksLikeSavePanel`（`+truncated` は探索の上限で打ち切った） | 判定の条件で弾いた。同じ行の `buttons` / `lists` / `textFields` / `search` をそのまま貼る。`noConfirmButton` で `buttons` に `<other len: …, contains: 開く>` があれば、確定ボタンの表題が「開く」と少し違う（「開く…」など） |
| `result: undetermined: unreadable` | 候補にしたが、中身を読めなかった（応答のタイムアウトなど）。直後の `panel detection undetermined` の行もあわせて貼る |
| ⌘O の後も `panel scan (…, windows: N)` の N が増えず、新しい `panel check` も出ない | ダイアログが TextEdit のウィンドウ一覧に現れていない |
| `panel watch observer failed` | AXObserver を張れていない（ポーリングで補うため、検知はできる想定） |

`panel check` / `panel scan` / `panel watch` の行は、パス・ファイル名・ウィンドウタイトルを含まない（AX の定数のロール名、`open-panel` / `save-panel` の AXIdentifier、パネルでよく使うボタンの表題だけ。それ以外は `<other len: 3, contains: 開く>` のように長さなどの分類だけを出す）。ほかの debug ログ（注入したパスなど）は含み得るため、共有する前に §3 の注意のとおり確かめる。

## 7. パレットの操作（S-08、S-09、PAL）

出典: TST-001 §3、PR #65 §3、PR #66（パスの直接入力）、UX-001 §4 §5。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| S-08 | パレット表示中に Esc → Ctrl+Shift+O | パレットだけ消えてパネルは残る。再表示すると検索語と選択が残っている |  | Esc は離したときに閉じる。長押しは物理キーと CGEvent の autoRepeat の両方で確かめる。3 秒未満の長押しでは、押している間にパネルが閉じず、離した後にパレットだけが閉じること。3 秒以上押し続けた場合は、離してもパレットが閉じず（パネルも残る）、もう一度 Esc を押して離すとパレットだけが閉じること（Issue #100）。debug ログ（PRE-04）での判定: `palette key hold ended (event: dismiss, key: escape, outcome: sent, held: …ms, …, discardedRepeats: N, …)` の直後に `palette hidden (id: X, wasVisible: true)` が出て、その後、パネルを自分で閉じるまで `panel gone` が出なければ OK（N が長押し中に捨てたリピートの数）。3 秒以上なら `outcome: expired, limitReached: true` が出て、`palette hidden` が続かないこと |
| S-09 | パレット表示中にパネルをキャンセルする（Esc でパネルを閉じる場合も） | パレットが消え、アプリは落ちない（受け入れ基準） |  |  |
| PAL-01 | ↑↓ / Ctrl+N / Ctrl+P、Tab | 選択が動く。Tab で選択中の候補のパスが検索フィールドに展開され（ディレクトリは末尾 `/`）、続けて配下の名前で絞り込める |  |  |
| PAL-02 | 候補に無い場所のパス（例 `~/Library`）を打つ → Enter | 先頭に `Library` の行が出て、Enter でパネルがそこへ移動する（FR-PALETTE-07） |  |  |
| PAL-03 | 末尾に `/` を付ける（`~/Library/`） | 直接入力の行が消え、配下の検索になる |  |  |
| PAL-04 | 存在しないパス（例 `~/no-such-dir`）を打つ | 直接入力の行が出ない |  |  |
| PAL-05 | フォルダのみのパネル（S-02 など）でファイルのパス（例 `~/.zshrc`）を打つ | 直接入力の行が出ない |  |  |
| PAL-06 | 一致しない語を打つ | リストに「一致する候補がありません。~/ や / で始まるパスも入力できます」が出る（PR #69） |  |  |
| PAL-07 | 日本語 IME の変換中に Enter・矢印を押す（入力ソースごとに） | 変換の操作になり、パレットの操作（確定・選択の移動）にならない（PR #49） |  |  |
| PAL-08 | 変換中にパネルをクリック、Enter を長押し、候補行をクリックしてから入力、Cmd+V / Cmd+A | 変換中の文字が失われない。Enter のリピートがパネルに届かない。クリック後も入力できる。ペーストと全選択が効く（PR #49） |  | Enter は離したときに移動を始める。長押しは物理キーと CGEvent の autoRepeat の両方で確かめ、auto_confirm=false なら移動後もパネルが残ること。3 秒以上押し続けると移動しない（Issue #90）。debug ログ（PRE-04）での判定: `palette key hold started (event: confirm, key: return, cmd: false)` → `palette key hold ended (…, outcome: sent, held: …ms, …, discardedRepeats: N, …)` → `coordinator injection start (id: X, …)` → `注入を主方式（⌘⇧G + ペースト）で始めます…` の順に出れば OK（注入は離した後に始まる。2 行の時刻差が離してから注入を始めるまでの間隔、N が捨てたリピートの数）。3 秒以上押し続けた場合は `outcome: expired, limitReached: true` が出て、`coordinator injection start` が続かないこと |

## 8. 検知の範囲（S-06、S-11、S-12、DET）

出典: TST-001 §3 と §3.1（検知、選択モード推定・位置、アイコン表示）、PR #65 §4、PR #66。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| S-11 | TextEdit の新規書類で保存ダイアログを出す（⌘S、§1.1） | パレットが出ない |  |  |
| S-06 | `include_files = true` にして、Safari で `<input type="file">` を置いた HTML（例: `echo '<input type="file">' > ~/Desktop/openpath-upload.html` を Safari で開く）のボタンを押す | パレットが出て、ファイルも候補に出る。確定ボタンが「アップロード」と判定される（PR #56） |  |  |
| S-12 | TextEdit でパネルを開いたまま、`disabled_apps` に `com.apple.TextEdit` を追加して保存（§1.1） | アプリを切り替えなくても、開いていたパネルのパレットが閉じる。以後 TextEdit ではパレットが出ない。外して保存すると出る（実行中の変更の即時反映、PR #65・PR #66） |  |  |
| DET-01 | TextEdit・Claude Desktop・Cursor・Finder の間でアプリを切り替える | 観測が追従し、切り替え先で開いているパネルを拾う（PR #46） |  |  |
| DET-02 | パネル表示中に ⌘⇧G で移動先シートを出す | `panel gone` → `panel detected` が出ない（PR #56） |  |  |
| DET-03 | シート型のパネル（S-06 の Safari のアップロードなど）を閉じる | `panel gone` が出て、パレットが消える（PR #46） |  |  |
| DET-04 | `include_files = true` で、一覧の読み込みが遅いフォルダのみのパネル（大きなフォルダ、ネットワークボリューム）を開く | ログに `panel updated (… directoriesOnly: true)` が出たら、表示中のパレットの候補がディレクトリだけに絞り直される（選択は保たれる。PR #65・PR #66） |  |  |
| DET-05 | 表示形式をアイコンにした「開く」パネルを開く | 検知され、選択モードが推定される（PR #64） |  |  |
| DET-06 | 表示形式をアイコンにした保存パネルを開く | 「開く」パネルと誤検知しない（PR #64） |  |  |
| DET-07 | マルチディスプレイ・Retina 混在の環境で、各ディスプレイでパネルを開く | パレットがパネルの右上に出る（PR #60） |  |  |

## 9. 注入の失敗とクリップボード（S-10、CLIP、INJ）

出典: TST-001 §3 と §3.1（注入）、PR #65 §5、PR #66、§1.2。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| S-10 | クリップボードにテキストをコピーしてから注入 | 注入後にクリップボードが元に戻っている |  |  |
| CLIP-01 | 画像（例: ⌃⇧⌘4 で撮ったスクリーンショット）をクリップボードに入れてから注入 | 注入後に画像が元に戻っている（型ごとに退避・復元する。DSN-001 §3.1） |  |  |
| CLIP-02 | パスワードマネージャーでパスワードをコピーしてから注入。コピー後に `osascript -l JavaScript -e 'ObjC.import("AppKit"); ObjC.deepUnwrap($.NSPasteboard.generalPasteboard.types).join("\n")'` に `org.nspasteboard.ConcealedType` が含まれることを確かめておく | 移動できる。注入後のクリップボードは空になり、パスワードもパスも残らない。メニューバーに「クリップボードを元に戻せませんでした」は出ない（空にするのは意図どおりのため。§1.2、PR #69） |  |  |
| CLIP-03 | 自動確定の後にクリップボードを戻せなかった場合を見る（再現は難しいため、起きたときの見え方でよい） | メニューバーにバッジと通知「クリップボードを元に戻せませんでした」が出て、選ぶと消える（PR #65・PR #66） |  |  |
| INJ-01 | 注入中（2.5 秒以内）に別のアプリへ切り替える | キーが別のアプリに届かない。パレットに赤字「移動できませんでした（パネルが最前面でなくなりました）」。パレットにキーが戻り、Enter で再試行・Esc で閉じられる |  | #94 で修正。切り替えている間はパレットを出さない（他のアプリの上に出さない）。赤字の失敗は、元のアプリに戻ってパネルが再通知されたときに出る（ログは `panel gone` → 戻ると `panel detected` / `palette shown`）。検索語と選択が残っていることも見る。#101: パレットの表示中に全体タイムアウト（2.5 秒）に達した場合も、同じ仕組みで赤字「移動できませんでした（タイムアウト）」が残り、Enter で再試行・Esc で閉じられる（再現は難しいため、起きたときの見え方でよい）。debug ログ（PRE-04）での判定: 切り替えで `coordinator failure remembered (id: X, failure: targetNotFrontmost, cause: panelGoneWhileInjecting)`、戻ると `palette shown (id: X)` の後に `coordinator failure reshown (id: X, failure: targetNotFrontmost)`、Enter で `coordinator failure forgotten (id: X, …, reason: retry)` → `coordinator injection start (id: X, …, retry: true)`、Esc なら `reason: escape` が出れば OK。タイムアウトは `failure: timeout(overall), cause: timedOut` で覚え、再通知で `reshown` が出る |
| INJ-02 | AXDialog 型・AXSheet 型のパネル、移動先シートの表示中のフォーカスウィンドウで注入する。#95: macOS 26 の VS Code（「フォルダーを開く…」のリモートのパネル）と TextEdit（⌘O）のそれぞれで、パネルに ⌘⇧G で移動先シートを先に開き、アプリを前面に戻してからパレットで実在するフォルダを選び、Enter と Cmd+Enter のそれぞれで注入する。`/tmp/…` のパス（実体は `/private/tmp/…`）でも行う | どれも 2.5 秒以内に移動できる（PR #54）。#95: 移動先シートが閉じ、パネルの現在地が移動先に変わる（Cmd+Enter なら「開く」まで進む）。シートが残ったままパレットが閉じる（成功扱い）なら NG。シートがどうしても閉じない場合は、パレットに赤字「移動できませんでした（「フォルダへ移動」を確定できません）」が出てパレットが残る |  | #95 で、Return を送っても閉じないシートを成功としないようにした（Preview 2 の QA で、VS Code で `主方式で注入しました` が出てもシートが残っていた）。debug ログ（PRE-04）での判定: `注入先: 移動先シートが既に開いていたため…`、`主方式: 移動先シートが既に開いているため、⌘⇧G を送らずにその入力欄を使います`、`主方式: 開いていたシートでは、注入先のプロセスへ送った Return が届かないことがあるため、Return はシステム経由で送ります（+Nms）`、`キーを送りました（Return、経路: システム（HID）、…）` に続いて `確定後の移動先シート: closed（待った時間 Nms、確認 N 回）` と `主方式で注入しました（+Nms）` が出て、画面でもシートが消えていれば OK。待った時間（Return からシートが閉じるまで）と全体の Nms を備考に控える（閉じるまでの時間は 600ms の上限の妥当性の確認に使う）。`closed` の代わりに `stillOpen` が出た場合は、`主方式が waitSheetClose で失敗したため、副方式（AX 直接セット）へ切り替えます` → `副方式: 入力欄に値をセットしました` → `副方式: 移動先シートが閉じたかを確かめました（closed、…）` → `副方式で注入しました` と進むこと（既存シートから副方式への移行。経路とアプリを備考に書く）。`/tmp/…` では `確定前の確認: ready` になり、`suggestionNotUpdated` で 250ms 待たないこと。Cmd+Enter では `確定後の移動先シート: closed` の後に `auto_confirm: 確定ボタンを押しました` が出て、移動先のフォルダで開くこと（元の場所で開けば NG）。⌘A / ⌘V は従来どおり注入先のプロセスへ送る（`キーを送りました（⌘V、経路: 注入先のプロセス（…））`） |
| INJ-03 | いくつかのアプリで注入し、ログで方式を見る | 副方式（AX で直接値を入れる）が効くアプリがあれば、備考にアプリ名とバージョン（PR #45・PR #54） |  |  |
| INJ-04 | 独自の確定ボタン名（「読み込む」など）を持つアプリで注入する | 備考にアプリ名と挙動を書く（TST-001 §3.1） |  | #89: パネルとして検知された後の auto_confirm / Cmd+Enter は、確定ボタンの表題が一覧に無くても既定ボタン（AXDefaultButton）で押す。パネル判定（DSN-001 §2.2）は表題の一覧のままのため、独自の表題の確定ボタンしか無いパネルは検知されずパレットが出ない（変更なし） |
| INJ-05 | 「システム設定 > キーボード > 入力ソース」で「Dvorak」「Dvorak - QWERTY ⌘」「Colemak」を追加して切り替え、それぞれで S-03 を行う。JIS キーボードでは入力ソースを「ABC」にして同様に行う | いずれの配列でも ⌘⇧G が横取りされず、2.5 秒以内に移動できる（#68・#107 で対応） |  | #24 からの申し送りだった未対応は #107 で解消。`InjectionKeyCodeResolver` が現在の入力ソースのキー配列から ⌘⇧G・⌘A・⌘V・/ のキーコードを求める（DSN-001 §3.1「キー配列」）。debug ログ（PRE-04）での判定: `キーを送りました（⌘⇧G、…、キーコード 0x…（キー配列から））` のキーコードが、Dvorak は `0x20`、Colemak は `0x11`、「Dvorak - QWERTY ⌘」と ABC（JIS キーボード）は US と同じ `0x5` になっていること。配列から求められない場合は `（キー配列から求められないため QWERTY の位置）` が出て物理位置（従来どおり）に落ちる。確かめたら入力ソースを元に戻す |
| INJ-06 | Raycast を起動し、ホットキーに ⌘⇧G を割り当てて Google 検索を開けるようにしたまま起動し続けた状態で、S-03（Claude Desktop）・INJ-02（移動先シートを先に開いた状態）・S-05（VS Code の ⌘O + Cmd+Enter）・TextEdit の ⌘O・Safari の `<input type="file">`（S-06）へ注入する。別に、パネルの検索欄をクリックしてフォーカスを移してから注入する場合も見る | 検索欄にフォーカスしていない通常の注入では、注入先のプロセスへ送った ⌘⇧G でシートが開き、Raycast の Google 検索を起動せずにパネルが移動する（#107 で対応）。検索欄にフォーカスした状態からの注入で代替（システム経由の ⌘⇧G）に入った場合は、既知の制約により Raycast に横取りされて移動できないことがある（この枝は失敗と判定せず、経路とフォーカスを備考に記録する） |  | ⌘⇧G を `CGEvent.postToPid` で注入先のプロセスへ直接送るため、Carbon の `RegisterEventHotKey` で登録された Raycast のホットキーを経由しない（DSN-001 §3.1「キーの経路」）。debug ログ（PRE-04）での判定: `キーを送りました（⌘⇧G、経路: 注入先のプロセス（…））` の宛先 pid（フォーカス中の要素のプロセスか、読めなければ注入先のアプリ）と、続く `主方式: 移動先シートが出ました（+Nms）` を備考に控える。注入先のプロセスへ送った ⌘⇧G で 200ms までにシートが出なければ（#29 で 600ms から短縮）代替に入り、ファイル一覧にフォーカスがあれば `/ をシステム経由で送り、移動先シートを開きます（フォーカス: fileList）`（横取りされない）、`/` でも出なければ、またはそれ以外のフォーカスでは `⌘⇧G をシステム経由で送り、移動先シートを開きます（フォーカス: …）` に続いて ⌘⇧G をシステム経由で送り直す（`主方式: システム経由の ⌘⇧G は、⌘⇧G をグローバルホットキーにしている他アプリに横取りされることがあります`）。検索欄にフォーカスした状態からの注入はこの代替で ⌘⇧G が送られるため横取りされ得る（送り先のプロセスへの ⌘⇧G でシートが出ていればこの経路を通らない）。代替に入ったかと経路・フォーカスを備考に書く。代替に入った注入先では、2 回目以降の注入で `この注入先では、前に ⌘⇧G を注入先のプロセスへ送っても移動先シートが出なかったため、システム経由で送ります` が出て、注入先のプロセスへの ⌘⇧G を送らずに代替から始まる（openpath を再起動すると忘れる。INJ-07）。INJ-02（移動先シートを先行して開いた状態）では `主方式: 注入先のプロセスへ送った ⌘A / ⌘V が入力欄に届かなかったため、以降のキーはシステム経由で送ります（+Nms）` が出ないこと。#95 以降、INJ-02 の確定の Return はシステム経由で送る（⌘⇧G は送らない）ため、Raycast を起動したままでもシートが閉じて移動すること（Return は横取りされない） |
| INJ-07 | macOS 26 で、VS Code の「ファイル > フォルダーを開く…」（openAndSavePanelService が描くリモートのパネル）を開き、ファイル一覧にフォーカスがある状態と、サイドバー・検索欄をクリックした状態のそれぞれから注入する。続けて同じパネルでもう一度注入する。Raycast で ⌘⇧G をホットキーにしている環境では、Raycast を起動したままでも同じことを行う | どの状態でも、注入先のプロセスへの ⌘⇧G（①）が届かなくても、システム経由の `/`（②、ファイル一覧のとき）かシステム経由の ⌘⇧G（③）で移動先シートが開き、2.5 秒以内に移動する（1 回目は ③ で開くと 1.5 秒を超えることがある。#29）。2 回目は ① を送らずにシステム経由から始まり、1 回目より早く移動する。Raycast が ⌘⇧G を横取りする環境で ② も効かない（ファイル一覧にフォーカスが無い・`/` でシートが開かない）場合は、③ が横取りされて主方式では開けないことがあり、これは既知の制約（DSN-001 §3.1「代替」）とする。この枝は失敗と判定せず、副方式（AX 直接セット）で移動したか・`timeout(waitSheet)` になったかを備考に記録する |  | #29 で対応（PR #107 以降、VS Code で `timeout(waitSheet)` になっていた）。debug ログ（PRE-04）での判定: 1 回目は `キーを送りました（⌘⇧G、経路: 注入先のプロセス（…））` の括弧内で、送り先の pid の決め方（`フォーカス中の要素の pid は注入先のアプリと同じ` / `…（別のプロセス）` / `…を読めないため注入先のアプリ`）とフォーカス中の要素のロール・サブロールを備考に控える。続いて `/ をシステム経由で送り…` または `⌘⇧G をシステム経由で送り…` の後に `主方式: 移動先シートが出ました（+Nms）` が出て、`キーを送りました（⌘A、経路: システム（HID）、…）` が続けば OK。`/` を送る前の `主方式: フォーカス中の要素（ロール: …、サブロール: …、…）` も控える（サイドバーの AXOutline に `/` が吸われる可能性の切り分け）。2 回目は最初の ⌘⇧G が `経路: システム（HID）` になり、`この注入先では、前に ⌘⇧G を注入先のプロセスへ送っても…` が出ること。#29（全体タイムアウトの延長）: PR #110 の QA では、1 回目に ③ でシートが +887ms に開いた後、ペーストと確定が 1.5 秒に間に合わず `timeout(overall)` になった。全体タイムアウトを 2.5 秒にした後は、openpath を起動し直した直後の 1 回目でも `coordinator failure remembered (id: X, failure: timeout(overall), cause: timedOut)` が出ずに移動すること。`主方式で注入しました（+Nms）`（副方式なら `副方式で注入しました（+Nms）`）の Nms を備考に控える |

## 10. メニューと設定（MENU、CFG）

出典: PR #65 §6、PR #66、§1.2。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| MENU-01 | 「有効」を外す → 付け直す | 外すとログ `パネルの監視を止めました`、アイコンが薄くなり、パネルを開いてもパレットが出ず、Ctrl+Shift+O も反応しない。付け直すと `パネルの監視を始めました` / `ホットキー … を登録しました` |  |  |
| MENU-02 | 「有効」を外したまま終了して起動し直す → 付け直して起動し直す | 無効のまま起動する: ログ `起動処理を終えました（アクセシビリティ権限: あり、有効: いいえ）`、`パネルの監視を始めました` とホットキーの登録が無い、アイコンが薄くツールチップに「（無効）」、メニューの「有効」のチェックが外れている、`defaults read jp.tamat.openpath enabled` が `0`。付け直した後は有効で起動する（§1.2、PR #69） |  |  |
| MENU-03 | `roots` 配下にディレクトリを作ってから「候補を再構築」 | ログ `メニューから候補の再構築を選択しました`。作ったディレクトリが候補に出る |  |  |
| MENU-04 | 「履歴をクリア…」→ 確認ダイアログでクリア | ログ `メニューから履歴をクリアしました`。空入力の候補から履歴の並びと最終使用日時が消える |  | debug ログ（PRE-04）での判定: `history clear removed (candidates: N, elapsed: …ms, rebuilding: false)` で履歴の候補を N 件取り除いたこと、パレットの表示中なら続く `palette candidates changed (presented: true, …)` → `palette rows refreshed (…, trigger: candidatesChanged, rows: …, lastUsedRows: 0, …)` で、表示中の候補から最終使用日時が消えたことを見る |
| MENU-05 | 起動直後（「候補を構築中…」の間）に履歴をクリア | 履歴にだけあった場所がすぐ候補から消える（PR #65・PR #66） |  | Issue #92 で修正: 表示中のパレットも構築の完了を待たずに引き直す（消えた候補を選んでいたら先頭を選ぶ）。フッターの「候補を構築中…」は構築を終えるまで残ってよい。debug ログ（PRE-04）での判定: `history clear removed (…, rebuilding: true)` の直後（`候補の再構築を終えました` より前）に `palette candidates changed (presented: true, …, building: true)` → `palette rows refreshed (…, trigger: candidatesChanged, …, selectionKept: false)` が出れば OK（取り除いた時刻と、選んでいた履歴だけの候補が消えて先頭を選び直したこと）。構築を終えた後に履歴だけの候補が戻らないことは画面で見る（ログには候補のパスを出さない） |
| MENU-06 | `chmod u-w ~/Library/Application\ Support/openpath` の後に履歴をクリア（確かめたら `chmod u+w` で戻す） | 保存できなかったことをダイアログで知らせる（PR #65・PR #66） |  |  |
| MENU-07 | 「設定ファイルを開く…」 | `config.toml` が開く |  |  |
| MENU-08 | 「ログイン時に起動」を入れる（確かめたら外す） | システム設定の「一般 > ログイン項目」に openpath が出る（.app から起動したときだけ。PR #55） |  |  |
| MENU-09 | 「終了」 | ログ `openpath を終了します`。プロセスが終わる |  |  |
| CFG-01 | config.toml を壊して保存（例: 行末に `roots = [` を足す）→ 直す | バッジと先頭の通知「設定ファイルにエラーがあります」。直前の設定のまま動く。直すと消える |  |  |
| CFG-02 | `hotkey = "ctrl+shift+p"` で保存 → 衝突するキー（例 `cmd+space`）で保存 → 戻す | `ホットキー ctrl+shift+p を登録しました`、新しいキーで再表示できる。衝突するキーでは `… の登録に失敗しました … を維持します` |  |  |
| CFG-03 | `roots` / `depth` / `ignore` / `[ghq] enabled` を変えて保存 | 再構築されて候補に反映される |  |  |

## 11. 初回起動の案内（2 回目以降・スキップ・開き直し）（ONB）

出典: PR #67 §3〜§5。起動し直しを伴うため、ほかの章の後で実施する。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| ONB-12 | 「はじめに…」→「試してみる」でダイアログを開いたまま openpath を終了 | ダイアログ（osascript）も閉じる |  |  |
| ONB-13 | 完了のページで「閉じる」か「試してみる」→ 起動し直す | 案内が出ない（`defaults read jp.tamat.openpath onboardingFinished` が `1`） |  |  |
| ONB-14 | PRE-02 の手順で初回に戻し、案内で「あとで」（Esc、クローズボタンも）→ 起動し直す | 案内が出ない。メニューバーのバッジと「アクセシビリティ設定を開く…」は残る |  |  |
| ONB-15 | 初回に戻し、案内の表示中にメニューの「終了」→ 起動し直す | また案内が出る（途中の終了は記録しない） |  |  |
| ONB-16 | メニューの「はじめに…」（権限なし・ありの両方、表示中にも選ぶ） | 権限がなければ説明から、あれば「準備ができました」から出る。表示中に選ぶと前面に出るだけ |  |  |
| ONB-17 | 権限を残したまま `defaults delete jp.tamat.openpath onboardingFinished` → 起動し直す | 説明を飛ばして「準備ができました」から出る。既にある config.toml は書き換わらない（SMK-01 で変えた内容のまま） |  |  |
| ONB-18 | 「準備ができました」の表示中に権限を取り消す | 説明のページに戻る |  |  |
| ONB-19 | `./scripts/cask.sh` の出力を見る | zap に `~/Library/Preferences/jp.tamat.openpath.plist` が入っている |  |  |
| ONB-20 | 先に確認用のフォルダを作り、できたことを確かめる（`mkdir ~/{Desktop,Documents,Downloads}/openpath-onb20` → `ls -d ~/{Desktop,Documents,Downloads}/openpath-onb20` で 3 つとも出る。ターミナル自身のアクセス確認が出たら許可する）。次に openpath を終了し、保護フォルダの記録を消す（`tccutil reset SystemPolicyDesktopFolder jp.tamat.openpath`。`SystemPolicyDocumentsFolder`・`SystemPolicyDownloadsFolder` も同様）。config.toml の `roots` を `["~"]` にして（ghq の root が取れない環境では ONB-03 の既定のまま）起動し、確認の 1 つで「許可しない」、ほかで「許可」を選ぶ。パレットで `onb20` と打ち、次に拒否したフォルダの名前（`Desktop` など）を打つ。確かめたら確認用のフォルダを消し（`rmdir ~/{Desktop,Documents,Downloads}/openpath-onb20`）、`roots` を戻す | デスクトップ・書類・ダウンロードのアクセス確認が 1 つずつ（最大 3 回）出て、用途の説明（「openpath は、ファイル選択ダイアログで目的の場所へ素早く移動できるよう…」）が表示される。Full Disk Access を求める案内は出ない。どう答えても openpath は落ちず、候補の構築が終わる。`onb20` の候補には、許可したフォルダの `openpath-onb20` だけが出て、許可しなかったフォルダの `openpath-onb20` は出ない。許可しなかったフォルダ自体（`~/Desktop` など）は、その名前で打つと候補に出る。「システム設定 > プライバシーとセキュリティ > ファイルとフォルダ」の openpath が答えたとおりになっている。起動し直しても確認は出ない（ad-hoc 署名は再ビルド後に出直すことがある）。確認に答えるまでの間の挙動（パレットの「候補を構築中…」、ほかのダイアログでの検知）を備考に書く（NFR-02、2026-09-24 オーナー判断） |  |  |

## 12. 権限の取り消しと復帰（S-13）

出典: TST-001 §3、UX-001 §5。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| S-13 | 動作中にシステム設定で openpath の権限を外す → 再び許可する | 外すとメニューバーにバッジが付き、検知が止まる（ログ `アクセシビリティ権限が取り消されました` / `パネルの監視を止めました`、パネルを開いてもパレットが出ない）。再び許可すると 5 秒以内に復帰する（`アクセシビリティ権限が付与されました` / `パネルの監視を始めました`） |  |  |
| SMK-03 | 権限を外した状態で `./scripts/smoke-open-panel.sh` | `前提不足: アクセシビリティ権限が取り消されています…` と出て、終了コード 2 |  |  |

## 13. 開発者向けの確認（DEV）

DEBUG ビルド（`swift run openpath` など）の debug ログや、プロセス内では再現できない条件を使う項目。Phase 1 の受け入れの必須ではなく、該当する変更をした PR で確かめる。出典は TST-001 §3.1。

| ID | 手順 | 期待 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| DEV-01 | DEBUG ビルドでパネルを開き、debug ログ `open panel classified` を見る | 判定コスト（`axCalls` / `elapsedMs`）を備考に写す。初回検知の `elapsedMs` が 300ms 以内（PR #56） |  |  |
| DEV-02 | サンドボックスアプリ（リモートのパネル）で選択モードの推定と矩形の取得を見る | AX 呼び出しの回数と所要時間を備考に写す（プロセス内の測定は 66〜127 回・9〜15ms。PR #60） |  |  |
| DEV-03 | 「アクセシビリティ > ディスプレイ > コントラストを上げる」をオンにしてフォルダのみのパネルを開く | 名前の文字色の不透明度による選択モードの推定が保たれる（PR #60） |  |  |
| DEV-04 | リモートのパネル（サンドボックスアプリ、macOS 26 の非サンドボックスアプリ）をアイコン表示にする。グループ分けで複数のセクションにもする | 一覧のサブロールが `AXCollectionList` のまま見え、項目の `AXImage` の `AXURL` / `AXEnabled` が読める。セクションの順に読める（PR #64） |  |  |

アイドル時の CPU・メモリ・検知レイテンシの p95 は、TST-001 §5 の方法で確かめる。

## 14. PR で確かめる項目の選び方

アプリの挙動に関わる PR では、変更した箇所に応じて次の項目を確かめ、PR テンプレートの「手動シナリオ」欄に書く。複数に当たる場合は和集合をとる。

| 変更した箇所（`Sources/` 配下） | 確かめる項目 |
| --- | --- |
| パネルの検知（`OpenPathCore/PanelDetection`、`OpenPathMac/PanelWatcher`） | SMK-02、S-01、S-02、S-06、S-11、S-12、DET-01〜DET-07 |
| パレット・検索（`Palette`、`Search`） | S-01、S-02、S-07b、S-08、PAL-01〜PAL-08、FLOW-01、FLOW-02 |
| 注入（`Injection`） | S-03〜S-05、S-07a、S-10、FLOW-03、FLOW-06、CLIP-01〜CLIP-03、INJ-01〜INJ-07 |
| 状態機械（`Coordinator`） | S-03、S-08、S-09、FLOW-03〜FLOW-05、INJ-01、CLIP-03 |
| 候補・履歴（`CandidateSources`、`Index`、`History`） | S-05、FLOW-02、FLOW-07、MENU-03〜MENU-06、CFG-03 |
| 設定（`Config`） | CFG-01〜CFG-03、S-12、SMK-01 |
| メニューバー（`StatusItem`） | PERM-01、PERM-03、MENU-01〜MENU-09、CLIP-03、S-13 |
| 権限・起動・初回起動（`Accessibility`、`App`、`Onboarding`） | ONB-01〜ONB-20、PERM-01〜PERM-03、S-13、SMK-02 |
| ホットキー（`Hotkey`） | S-08、MENU-01、CFG-02 |
| ログ（`Logging`） | SMK-02、SMK-03 |
| 配布スクリプト（`scripts/`） | PRE-01、ONB-19。`scripts/smoke-open-panel.sh` を変えたら SMK-02、SMK-03 |
