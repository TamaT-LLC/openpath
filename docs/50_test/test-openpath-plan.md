---
id: PROJ-TST-001
layer: L5
feature: openpath
scope: global
status: Draft
upstream:
- PROJ-ARCH-001
- PROJ-DSN-001
- PROJ-DSN-002
downstream:
- PROJ-TST-002
owner: TakehiroT
updated: 2026-09-24
---

# テスト計画: openpath

## 1. 方針

- `OpenPathCore`（ファジーマッチ、frecency、設定パース、状態機械）は Swift Testing によるユニットテストで網羅する。XCTest と違い Xcode を必要とせず Command Line Tools だけで実行できるため、Swift Testing を採用する。ローカルでは `./scripts/test.sh` を使う（Command Line Tools のみの環境では素の `swift test` が `no such module 'Testing'` で失敗するためのラッパー。CLT が選択されているときだけ `-F`・rpath・cross-import overlay の無効化を足し、Xcode 環境では素の `swift test` と同じ、PR #32）。
- `OpenPathMac`（AX 観測、注入）は自動化が困難なため、手動シナリオテストと、Finder の「開く」ダイアログを使ったスモークスクリプト（AppleScript で `choose folder` を出す）で確認する。
- CI（GitHub Actions）は `macos-15` ランナー、Xcode 16.4（`DEVELOPER_DIR` で明示）でユニットテストと `swift build` のみ実行する。`macos-14` は既定の Xcode が 15.4（Swift 5.10）で swift-tools-version 6.0 のマニフェストを扱えず、2026-11-02 にサポートも終了するため採用しない（PR #33）。AX を要するテストはローカル限定。

## 2. ユニットテスト（OpenPathCoreTests）

### 2.1 FuzzyMatcher

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 先頭一致が最上位 | query `fern`, 候補 `fern`, `fernet-config`, `my-fern` | `fern` > `fernet-config` > `my-fern` |
| 区切り直後ボーナス | query `sda`, 候補 `system-doc-agent`, `sdasd` | `system-doc-agent` が上位（s/d/a が `-` 直後） |
| 日本語 NFC/NFD 同一視 | query `資料`, 候補（NFD で保存された `資料`） | マッチする |
| かな同一視 | query `しりょう`, 候補 `シリョウ` | マッチする |
| 幅同一視 | query `ａｂｃ`, 候補 `abc` | マッチする |
| 非マッチ | query `xyz`, 候補 `fern` | nil |
| positions | query `fn`, 候補 `fern` | positions == [0, 3] |

### 2.2 Frecency

| ケース | 期待 |
| --- | --- |
| 1 時間以内は decay 4.0 | count 1, lastUsed = now - 30min → score 4.0 |
| 1 週間超は decay 0.25 | count 4, lastUsed = now - 10d → score 1.0 |
| 確定で count++ と lastUsed 更新 | `record(path)` 後に反映 |
| 90 日未使用かつ不存在で削除 | 保存時に消える |
| 上限 2,000 件 | 2,001 件目追加で最下位が消える |

### 2.3 ConfigStore

| ケース | 期待 |
| --- | --- |
| 既定値生成 | ファイルなし → roots に ghq root（モック）を含む TOML が生成される |
| 各キーのパース | 上記サンプル TOML が `Config` に一致 |
| 不正 TOML | 直前の設定が維持され、`lastError` が非 nil |
| `~` 展開 | `roots = ["~/repos"]` → 絶対パス |
| ホットキー文字列 | `"ctrl+shift+o"` → `(keyCode: kVK_ANSI_O, modifiers: [.control, .shift])` |

### 2.4 CandidateIndex

| ケース | 期待 |
| --- | --- |
| ソース統合 | 同一パスが history と ghq にある → 1 件、source == .history |
| ディレクトリのみ要求 | `query(directoriesOnly: true)` にファイルが含まれない |
| 空クエリ | frecency 降順 8 件 |
| ignore 適用 | `node_modules` 配下が走査結果に含まれない |
| アトミック差し替え | 走査中に query しても旧結果が返り、クラッシュしない |

### 2.5 AppCoordinator（状態機械）

| ケース | 期待 |
| --- | --- |
| Idle → PanelShown | `panelAppeared` でパレット表示が呼ばれる |
| PanelShown → Injecting → Idle | `confirm(path)` で注入が呼ばれ、成功後 Idle |
| 注入タイムアウト | 1.5 秒で Idle に戻り、エラーがパレットに渡る |
| 注入失敗（タイムアウト・`panelGone` 以外） | `PanelShown` に戻り、パレットにエラー表示が残る。Esc または `panelGone` で閉じる（PR #39） |
| パネル消滅 | `PanelShown` では Idle に戻る。`Injecting` でも基本は Idle に戻るが、auto_confirm 開始後は例外的に注入の結果を待ってから Idle に戻る（ARCH-001 §5、PR #52） |
| 注入成功後の再通知 | 成功したパネルの再検知（`panelAppeared`）ではパレットを出し直さない。成功後のホットキーでは再表示する（PR #52） |
| 自動確定中の `panelGone` | 注入をキャンセルせず結果を待つ。injector が `panelGone` / `pasteboardRestoreFailed` で終えたら成功として履歴に記録する（PR #52） |
| Esc | PanelShown のままパレットのみ非表示、ホットキーで再表示 |

## 3. 手動シナリオテスト（Phase 1 受け入れ）

前提: アクセシビリティ権限付与済み、`roots = ["~/repos"]`, `ghq.enabled = true`。

実施の手順と結果の記録には、チェックリスト PROJ-TST-002（`docs/50_test/test-openpath-manual-scenarios.md`）を使う。S-01〜S-13 に、§3.1 の項目・各 PR の実機確認項目（PR #65 / #66 / #67）・準備とスモークテスト（§4）を合わせて 1 か所にまとめ、実施環境（日時・macOS・対象アプリのバージョン）と項目ごとの結果（OK / NG / 未確認 / 対象外と備考）を書き込める形にしている（#29）。アプリの挙動に関わる PR では、PR テンプレート（`.github/pull_request_template.md`）の「手動シナリオ」欄に、影響範囲の項目の結果を書く。

| # | アプリ | 手順 | 期待 |
| --- | --- | --- | --- |
| S-01 | Finder | Cmd+O で「開く」 | 300ms 以内にパレットが右上に出る |
| S-02 | Claude Desktop | 「フォルダを追加」 | パレットが出て、ディレクトリのみ候補に出る |
| S-03 | Claude Desktop | `fern` と打って Enter | パネルが該当リポへ移動、パレットが閉じる。Enter で追加できる |
| S-04 | Cursor | File > Open Folder → `open` Enter | 同上 |
| S-05 | VS Code | File > Open… → Cmd+Enter | 移動 + 自動で開く |
| S-06 | Safari | ファイルアップロード input | パレットが出て、ファイルも候補に出る（include_files=true 時） |
| S-07 | 任意 | 日本語ディレクトリ `~/Documents/資料` を選択 | 正しく移動する |
| S-08 | 任意 | Esc → Ctrl+Shift+O | パレットが消え、再表示される |
| S-09 | 任意 | パレット表示中にパネルをキャンセル | パレットが消え、アプリは落ちない |
| S-10 | 任意 | ペーストボードにテキストを入れてから注入 | 注入後にペーストボードが元に戻る |
| S-11 | TextEdit | Cmd+Shift+S（保存ダイアログ） | パレットが出ない |
| S-12 | 任意 | `disabled_apps` に対象アプリを追加 | そのアプリではパレットが出ない |
| S-13 | 任意 | 権限を外す | メニューバーにバッジ、検知停止。再付与で 5 秒以内に復帰 |

- S-01: Finder の ⌘O は選択中の項目を開く操作で、「開く」ダイアログは出ない（PR #67）。TextEdit の「ファイル > 開く…」で確かめる。
- S-10: パスワードマネージャーなどの機密の内容（`org.nspasteboard.ConcealedType` を含む）は、注入後に復元せず空にする（オーナー判断、PR #69）。
- S-11: TextEdit の ⇧⌘S は「複製」に割り当てられていることがあるため、未保存の新規書類で ⌘S を押して保存ダイアログを出す。
- S-12: 起動中に `disabled_apps` を変えたときの即時反映も確かめる（PR #65）。

### 3.1 統合（#27）時の追加確認項目

各 Issue の実装 PR は、この環境にアクセシビリティ権限が無く実機で確認できないため、申し送りとして次の確認項目を残している。#27（アプリ統合）で上記 S-01〜S-13 と合わせて確認する。

- **検知（PanelWatcher、PR #46 / #56）**: Finder / TextEdit / Claude Desktop / Cursor 間の切り替えで観測が追従する。`disabled_apps` のアプリではパネルを開いても検知しない。シート型パネル（`beginSheetModal`、サンドボックスアプリ）を閉じたときも `panel gone` が出る。⌘⇧G でフォルダを移動しても `panel gone`→`panel detected` が出ない（`PanelContext.ID` が変わらない）。Safari の `input[type=file]`（S-06）で確定ボタンが「アップロード」と判定される。アイドル時の CPU（200ms ポーリング）が非機能要件の範囲に収まる。
- **注入（PanelInjector、PR #45 / #54）**: 副方式が効くアプリがあるか。auto_confirm / Cmd+Enter の両方で動く。日本語パス（NFC / NFD）で正しく移動する。注入中にアプリを切り替えるとキー操作が送られない（`targetNotFrontmost`）。独自の確定ボタン名（「読み込む」等）を持つアプリでの挙動。
- **再通知・履歴（AppCoordinator、PR #52）**: auto_confirm=false で Enter を押して注入に成功した後、パレットが出直さず、パネル側の Enter で確定できる（S-03）。その状態で Ctrl+Shift+O を押すとパレットを再表示できる。auto_confirm=true と Cmd+Enter のそれぞれで、パネルが閉じた後に履歴へ残る。
- **ログ（PR #56）**: `panel detected` / `panel gone` が info でログに出る（`Log.configure` を起動時に呼ぶ必要がある）。debug ログの `open panel classified` に含まれる `axCalls` / `elapsedMs`（判定コストの実測値）を確認する。
- **選択モード推定・位置（PanelWatcher、PR #60）**: 「コントラストを上げる」設定時の名前の文字色不透明度（プロセス内では外観を切り替えられず未確認）。サンドボックスアプリ（リモートパネル）での推定・矩形取得の AX 呼び出し回数と所要時間（プロセス内測定は 66〜127 回・9〜15ms）。マルチディスプレイ / Retina 混在環境でのパレット位置。
- **アイコン表示の検知（PanelWatcher、PR #64）**: アイコン表示の保存パネル（リモートのため権限なしでは確認できなかった）が開くパネルと誤検知されない。リモートのパネル（サンドボックスアプリ・macOS 26 の非サンドボックスアプリ）でアイコン表示の一覧のサブロールが `AXCollectionList` のまま見え、項目の `AXImage` の `AXURL` / `AXEnabled` が読めるか。セクションが複数あるアイコン表示（グループ分け）で、セクションの順に読めるか。
- **メニュー・設定・直接入力（PR #65、PR #66 からの申し送り）**: パスの直接入力（存在する / しないパス、末尾 `/` での非表示、フォルダのみのパネルでのファイルのパスの除外）。選択モードの推定し直しを表示中のパレットへ反映する（PanelShown 中のポーリングの継続）。メニューの「有効」で監視とホットキーが止まり・再開し、再起動後も保持される（オーナー判断で PR #65 の「起動のたびに有効」から変更、PR #69）。履歴のクリアで保存に失敗したときのダイアログと、全件の再構築中のクリアの反映。自動確定後のクリップボードの復元失敗の通知（バッジ・通知の消去）。`disabled_apps` の実行中の変更の即時反映。

§3.1 の項目も PROJ-TST-002 に取り込んでいる。

## 4. スモークスクリプト

`scripts/smoke-open-panel.sh`（#29）は、フォルダ選択のダイアログを出して、openpath がそれを検知することをログで確かめる。アクセシビリティ権限を付与した `openpath.app` を起動しておくこと（スクリプトはアプリを起動も終了もしない）。PROJ-TST-002 の SMK-02 / SMK-03 で使う。

```bash
./scripts/build.sh && ./scripts/sign.sh
open build/openpath.app          # アクセシビリティ権限を付与しておく
./scripts/smoke-open-panel.sh    # --app / --log / --timeout で既定値を変えられる（--help）
```

- 手順:
  1. 指定の .app（既定 `build/openpath.app`）が 1 つだけ起動していることと、ログの最新の起動以降で権限があり、パネルを監視中であることを確かめる（`起動処理を終えました（アクセシビリティ権限: …）`・`アクセシビリティ権限が付与されました`・`パネルの監視を始めました` などの行で判定する）。
  2. `osascript -e 'choose folder …'` で、別プロセスのフォルダ選択のダイアログを出す。初回起動の「試してみる」と同じ方式で、キー操作の送出や他のアプリへの Apple Events は使わない（PR #67）。
  3. 開始時点のオフセット以降のログに `panel detected` が出るまで待つ（既定 15 秒）。ログにはどのアプリのパネルかが出ないため、行を見つけた時点でダイアログ（osascript）が最前面でなければ、別のアプリのパネルとみなして読み飛ばす（openpath は最前面のアプリのパネルだけを検知する）。
  4. 受け入れた `panel detected (id: …)` と同じパネル ID の `palette shown (id: …)` が出れば、その時刻との差を検知からパレット表示までの時間として出す。1 回の計測なので判定には使わず、300ms（FR-DETECT-03）を超えたら警告だけ出す。p95 は §5 の方法で測る。
  5. osascript を終了してダイアログを閉じ、`panel gone` が出るまで待つ（5 秒）。openpath は同時に 1 つのパネルだけを追跡し、次の `panel detected` の前に必ず `panel gone` を出すため、受け入れた `panel detected` の後の最初の `panel gone` をこのダイアログのものとみなす。閉じる前に出ていたら（最前面の切り替えやキャンセル）、閉じたことの確認にならないため NG にする。openpath は最前面が変わっただけでも `panel gone` を出すため、閉じる直前にダイアログが最前面でなければ NG にし、閉じたことは osascript のプロセスが終わった（ダイアログのウインドウは osascript が持つ）ことで確かめる。
- 結果は最後の行に `OK` / `NG: 理由` / `前提不足: 理由` で出し、終了コードは 0 = OK / 1 = NG / 2 = 前提不足とする。
  - NG: `panel detected` が出ない、閉じた後に `panel gone` が出ない、閉じる前に `panel gone` が出た・最前面が切り替わった、osascript が終わらない、検知の前にダイアログが閉じられた。
  - 前提不足: .app が起動していない（別の場所の .app が起動している場合、起動中の実行ファイルの場所を確かめられない場合を含む）、同じ bundle id の openpath が複数起動している（ログを共有するため、どのインスタンスの記録か区別できない）、ログが無い・読めない（実行中に読めなくなった場合を含む）、起動中のインスタンスがログに書いていない（最新の記録が終了）、権限が無い、監視が止まっている（「有効」が外れている）、引数の誤り。
- 端末から起動した osascript は、自分では最前面にならないことがある（PR #67 と同じ。この PR の確認でも最前面にならなかった）。openpath は最前面のアプリのパネルだけを検知するため、2 秒たってもダイアログが最前面でなければ、クリックして前面に出すよう案内して待つ。ダイアログの文言にも同じ案内を入れている。
- 選択モードは参考として出す。`choose folder` はフォルダのみのパネルなので、`directoriesOnly: true`（推定し直し後の `panel updated` を含む）にならなければ警告する。
- `palette shown (id: …)` は PR #69 で追加したログで、パレットを出すたびに（ホットキーでの再表示でも）出る。PR #69 より前のビルドでは出ないため、2 秒待って出なければその旨を警告し、検知だけで判定する。
- ログの形式は PR #69 以降の起動処理の完了の行（`起動処理を終えました（アクセシビリティ権限: あり、有効: はい）`）と、それより前の形式（「有効」が無い）の両方を読む。`lsappinfo` の出力も macOS 27 の形式（`pid = …` / `executable path="…"`）と 26 までの形式（`"pid"=…` / `"CFBundleExecutablePath"="…"`）の両方を読む。

## 5. 非機能テスト

| 項目 | 方法 | 合格基準 |
| --- | --- | --- |
| アイドル CPU | `scripts/measure-idle-cpu.sh` で 10 分計測（累積 CPU 時間 `ps -o time` の増分 ÷ 経過実時間 × 100。1 コア = 100%。`top` の %CPU を参考値として併記）。5 分ごとの候補の周期の再構築を含めて測り、候補数を記録する | 平均 0.1% 未満 |
| メモリ | 候補 20,000 件を読み込ませた計測用インスタンスで、構築が落ち着いてから 30 秒後に `scripts/measure-memory.sh --pid` で phys_footprint の現在値を測る（`--candidates 20000` なら、起動・落ち着いてから 30 秒の待機（`--measure-delay`）・計測・停止を 1 回で行う） | 50MB 以下 |
| 検知レイテンシ | `scripts/measure-detection-latency.sh`（ログのタイムスタンプ `panel detected (id: …)` → `palette shown (id: …)` の差。同じパネル ID の行を組にし、パレットが出なかった検知が 1 件でもあれば判定しない。権限付きの .app で S-01 を 20 回程度繰り返した後に実行）。`panel detected` は PanelWatcher がパネルを検知した直後に出るため、パネルが生成されてから検知されるまで（AX 通知の遅れや 200ms ポーリングの待ち）の時間は含まれない | p95 300ms 以下 |
| ネットワーク | `scripts/measure-network.sh`（`nettop` の送受信バイト数と `lsof -i` のインターネットソケット数。起動直後から監視する） | 通信ゼロ |
| Notarization | `spctl -a -vv openpath.app`（`scripts/notarize.sh` 内で実行。提出前に ad-hoc 署名でないこと・`Developer ID Application:` 署名・`runtime` フラグの付与を確認してから提出する、PR #59） | accepted |

- 計測スクリプトの終了コードは 0 = PASS、1 = FAIL、2 = 計測できなかった（対象のプロセスやログが無い等）。
- アイドル CPU・メモリ・ネットワークは、`scripts/measure-isolated.sh start` で一時 HOME（`CFFIXED_USER_HOME`）を使う計測用インスタンスを起動して測る。実ユーザーの設定・履歴・ログには触れず、止めるときは `stop` で自分が起動した pid だけを止める。起動引数 `-onboardingFinished YES -enabled YES`（UserDefaults の引数ドメイン。保存されない）で、初回起動の案内を出さず有効の状態で起動する。アクセシビリティ権限の無い状態ではパネルの検知（200ms ポーリング）は動かないため、検知レイテンシと、ポーリングを含むアイドル CPU は .app に権限を付けてから測る。
- メモリは RSS ではなく phys_footprint（Activity Monitor の「メモリ」列と同じ値）で判定する。RSS は共有フレームワークのページを含み、圧縮・スワップされたページを含まないため。
- 計測の手順・環境（macOS のバージョンで値が変わるため必ず記録する）・Phase 1 の実測値と、オーナーが実行・判断する項目（検知レイテンシ・Notarization・権限付きでのアイドル CPU・候補 20,000 件でのアイドル CPU の FAIL とメモリの扱い）は PROJ-TST-003（`docs/50_test/test-openpath-nfr-measurement.md`）に記録する。
- 個別の実装 PR で測った値は各 PR の「テスト」節に記録している（roots 走査・候補の前処理時間・常駐メモリ: DSN-002 §5 / §8、PR #40 / #47 / #51 / #57。CI 実行環境: PR #33）。本表は Phase 1 の合格基準と計測方法を示すもので、実測値そのものは記載しない。

## 6. 完了条件

- 2 章のユニットテストがすべて通る（CI）。
- 3 章の S-01〜S-13 がすべて期待どおり（ローカル、チェックリストを PR に添付）。
- 5 章の合格基準を満たす。
