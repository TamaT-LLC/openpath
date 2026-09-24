---
id: PROJ-TST-003
layer: L5
feature: openpath
scope: global
status: Draft
upstream:
- PROJ-TST-001
downstream: []
owner: TakehiroT
updated: 2026-09-24
---

# 非機能テストの計測結果: openpath

TST-001 §5 の非機能テストを `scripts/measure-*.sh` で計測した手順と結果を記録する（Issue #30）。対象の要件は REQ-001 の NFR-01（通信ゼロ）、NFR-03（アイドル CPU 0.1% 未満・常駐メモリ 50MB 以下）、NFR-04（Notarization）と FR-DETECT-03（検知からパレット表示まで 300ms 以下）。

## 1. 結果の要約

| 項目 | 合格基準 | 結果（2026-09-24） | 判定 |
| --- | --- | --- | --- |
| アイドル CPU | 平均 0.1% 未満 | 候補 20,000 件: **0.1784%**（10 分指定・実 684 秒）。候補 5,000 件: 0.0570%（実 649 秒）。いずれも権限なし | **FAIL**（候補 20,000 件）。5 分ごとの候補の周期の再構築が大半を占める（§3.2）。候補 5,000 件は PASS。権限付きは未計測。扱いは §6.4 |
| メモリ | 50MB 以下 | 候補 20,000 件の phys_footprint 現在値: 中央値 36.42 MB・最大 40.67 MB（5 回） | PASS。ただし周期の再構築の最中はピークが 53.91〜55.77 MB になり、一時的に 50MB を超える（§4、§6.4） |
| ネットワーク | 通信ゼロ | 起動直後から 391 秒、送受信 0 バイト・インターネットソケット 0 個（起動時の構築と周期の再構築を含む） | PASS |
| 検知レイテンシ | p95 300ms 以下 | 計測できず（§3.4） | 未計測（オーナーが実行、§6.1） |
| Notarization | accepted | 未実施（Developer ID 証明書と notarytool の資格情報が必要） | 未計測（オーナーが実行、§6.3） |

## 2. 計測環境

| 項目 | 内容 |
| --- | --- |
| 日時 | 2026-09-24 11:12〜11:58（JST） |
| マシン | MacBook Air（Mac15,13）、Apple M3（高性能 4 + 高効率 4 コア）、メモリ 24 GB |
| macOS | 26.3.1 (a)（25D771280a） |
| ビルド | main の ea52baa を `./scripts/build.sh && ./scripts/sign.sh` でビルドした universal（x86_64 + arm64）の release ビルド。ad-hoc 署名（Hardened Runtime 有効）、version 0.1.0。初回起動フロー（#67）は未マージのため含まない |
| 計測用インスタンス | `scripts/measure-isolated.sh start` で起動（下記） |

計測用インスタンスは、一時ディレクトリ（`$TMPDIR/openpath-measure-TASK-030.XXXXXX`）の `home/` を一時 HOME にして `open -n -g --env CFFIXED_USER_HOME=<一時 HOME>` で起動する。設定・履歴・ログはすべて一時 HOME 配下にでき、実ユーザーの `~/.config/openpath`・`~/Library/Application Support/openpath`・`~/Library/Logs/openpath` には触れない。設定は次のとおり。

- `roots` に depth 2 のディレクトリだけのツリーを 1 つ置く。`--candidates 20000` では、ルートあたりの上限（`RootScanOptions.defaultItemLimit` = 20,000 件）を少し超える 20,100 件を作り、上限まで読み込ませる。上限到達の警告がログに出たことで 20,000 件を読み込んだと確かめる
- `include_files = false`、`depth = 2`、ghq は無効
- アクセシビリティ権限は無い。そのためパネルの検知（PanelWatcher の 200ms ポーリング）は動かない

## 3. 手順と結果

計測スクリプトの終了コードは 0 = PASS、1 = FAIL、2 = 計測できなかった（対象のプロセスやログが無い等）。計測用インスタンスを止めるときは `measure-isolated.sh stop` を使い、start で起動した pid だけを止める（`pkill` / `killall` は使わない）。

| スクリプト | 役割 |
| --- | --- |
| `scripts/measure-isolated.sh` | 計測用インスタンスの起動（`start [--candidates N] [--settle-seconds S]`）と停止（`stop <計測ディレクトリ>`）。start は累積 CPU 時間の増分が 5 秒間 0.02 秒以下になるまで（候補の構築が落ち着くまで）待ち、`OPENPATH_PID` 等を KEY=VALUE で出力する |
| `scripts/measure-memory.sh` | phys_footprint の現在値で常駐メモリを判定する。ピークと RSS は参考値 |
| `scripts/measure-idle-cpu.sh` | 累積 CPU 時間の増分 ÷ 経過実時間でアイドル時の平均 CPU% を出す。`top` の %CPU を参考値として併記する |
| `scripts/measure-network.sh` | `nettop` の送受信バイト数と `lsof -i` のインターネットソケット数を監視する |
| `scripts/measure-detection-latency.sh` | ログの `panel detected` → `palette shown` のタイムスタンプ差から p50 / p95 / 最大を出す |

### 3.1 メモリ（NFR-03）

候補の構築が落ち着いてから 30 秒後に測る。測るタイミングで値が変わるため、起動・構築完了からの経過時間を揃えて 5 回起動し直して測った。

```bash
eval "$(scripts/measure-isolated.sh start --candidates 20000)"
sleep 30
scripts/measure-memory.sh --pid "$OPENPATH_PID"
scripts/measure-isolated.sh stop "$OPENPATH_MEASURE_DIR"
```

1 回だけ測るなら `scripts/measure-memory.sh --candidates 20000` でもよい（起動から停止までを行い、落ち着いた直後に測る）。

候補 20,000 件、落ち着いてから 30 秒後（`footprint` で取得。1 MB = 1,048,576 バイト）:

| 回 | 計測時刻 | phys_footprint 現在値 | ピーク（起動後の最大） | RSS（参考） | 判定 |
| --- | --- | --- | --- | --- | --- |
| 1 | 11:21:22 | 40.67 MB | 46.25 MB | 40.70 MB | PASS |
| 2 | 11:34:15 | 36.19 MB | 45.99 MB | 40.84 MB | PASS |
| 3 | 11:35:52 | 36.47 MB | 46.00 MB | 38.25 MB | PASS |
| 4 | 11:37:09 | 35.17 MB | 46.83 MB | 43.75 MB | PASS |
| 5 | 11:38:19 | 36.42 MB | 46.30 MB | 35.16 MB | PASS |

現在値の中央値は 36.42 MB、最大は 40.67 MB（基準まで 9.33 MB）。起動時の構築中のピークは最大 46.83 MB。

周期の再構築（構築完了から 5 分ごと）を経た後と、候補 0 件の値（参考）:

| 状況 | phys_footprint 現在値 | ピーク（起動後の最大） | RSS（参考） |
| --- | --- | --- | --- |
| 再構築 1 回の後（通信の計測に使ったインスタンス、起動から約 8 分後。2 回） | 35.74 MB / 35.70 MB | **53.91 MB / 54.66 MB** | 30.38 MB / 20.69 MB |
| 再構築 2 回の後（アイドル CPU の計測に使ったインスタンス、起動から約 12 分後） | 35.44 MB | **55.77 MB** | 20.16 MB |
| 候補 5,000 件（アイドル CPU の計測の前・後。後は再構築 2 回の後） | 22.14 MB / 22.31 MB | 23.94 MB / 26.41 MB | — |
| 候補 0 件（2 回） | 16.00 MB / 16.25 MB | 16.50 MB / 16.92 MB | 31.55 MB / 31.56 MB |

再構築を経ても現在値は 35〜36 MB に戻るが、再構築の最中は一時的に 50 MB を超える（§4）。

### 3.2 アイドル CPU（NFR-03）

```bash
eval "$(scripts/measure-isolated.sh start --candidates 20000)"
sleep 30
scripts/measure-idle-cpu.sh --pid "$OPENPATH_PID"   # 既定 10 分、top は 5 秒間隔
scripts/measure-isolated.sh stop "$OPENPATH_MEASURE_DIR"
```

候補数への依存を見るため、候補 5,000 件（DSN-002 §8 の roots 走査の目標と同じ件数）でも同じ手順で測った。

| 候補数 | 計測期間（経過実時間） | 累積 CPU 時間の増分 | 平均 CPU% | `top` の %CPU（参考） | 判定 |
| --- | --- | --- | --- | --- | --- |
| 20,000 件 | 11:21:24〜11:32:48（684 秒） | 1.22 秒 | **0.1784%** | 119 サンプル、平均 0.159% / 最大 9.8% | **FAIL** |
| 5,000 件 | 11:47:17〜11:58:06（649 秒） | 0.37 秒 | 0.0570% | 119 サンプル、平均 0.043% / 最大 2.4% | PASS |

平均 CPU% の分解能（増分 0.01 秒あたり）はどちらも 0.0015%。経過実時間が 10 分より長いのは `top` の 1 サンプルあたりの所要時間の分で、平均は実際の経過実時間で割っている。

計測中に累積 CPU 時間を 5 秒ごとに記録した（`ps -o time`。読み取りは対象の CPU 時間を消費しない）ところ、増分の大半は構築完了から 5 分ごとの周期の再構築（`CandidateIndexRebuilder.defaultInterval`）だった。

| 候補数 | 周期の再構築 1 回あたりの CPU 時間 | 再構築以外（窓全体に対する平均） |
| --- | --- | --- |
| 20,000 件 | 約 0.53 秒（11:25:48〜11:25:54）、約 0.47 秒（11:30:58〜11:31:03）。いずれもログの上限到達の警告と同時刻 | 約 0.22 秒（約 0.03%）。0.01〜0.04 秒の増分が 15〜60 秒おき |
| 5,000 件 | 約 0.11 秒（11:51:43）、約 0.13 秒（11:56:46） | 約 0.13 秒（約 0.02%） |

再構築を除けばアイドル時の CPU は 0.02〜0.03% で基準を大きく下回るが、候補 20,000 件では 5 分ごとに約 0.5 秒（5 分あたり約 0.17%）を再構築に使うため、平均が 0.1% を超える。再構築のコストが候補数に比例すると仮定すると、8,000〜9,000 件前後が境目になる（推定。計測はしていない）。

### 3.3 ネットワーク（NFR-01）

起動直後から監視するため、`--settle-seconds 0` で起動を待たずに監視を始める。監視期間には起動時の候補の構築と、その 5 分後の周期の再構築を含める。

```bash
eval "$(scripts/measure-isolated.sh start --candidates 20000 --settle-seconds 0)"
scripts/measure-network.sh --pid "$OPENPATH_PID" --seconds 390
scripts/measure-isolated.sh stop "$OPENPATH_MEASURE_DIR"
```

| 項目 | 値 |
| --- | --- |
| 監視期間 | 11:39:58〜11:46:29（391 秒）。起動は 11:39:57.983、起動時の構築は 11:39:58.982 に上限に到達、周期の再構築は 11:45:01 に上限に到達（いずれも監視期間内） |
| `nettop` | 79 サンプル（5 秒間隔）。対象 pid の行 0 件、送受信 0 / 0 バイト |
| `lsof -i` | 79 回。インターネットソケット（IPv4 / IPv6、loopback を含む）最大 0 個 |
| 判定 | PASS |

`lsof` の採取を開始時刻からの決まった時刻に揃える前のスクリプトでも 1 回測り（11:12:36〜11:20:29。`lsof` の所要時間の分だけ採取が遅れ、経過実時間が 473 秒に延びた）、同じく送受信 0 バイト・ソケット 0 個だった。

### 3.4 検知レイテンシ（FR-DETECT-03）: 計測できず

この環境ではアクセシビリティ権限を付けられず、PanelWatcher が動かないため `panel detected` がログに出ない。また、計測時点の main はパレットを表示したときのログ（終点の `palette shown`）を出さない。`palette shown` は、並行する修正 PR で `panel detected` と同じ形式（info、ミリ秒付きのタイムスタンプ）で出す予定。終点の行が無いログに対しては、スクリプトは終了コード 2 で案内を出して終わる。

`measure-detection-latency.sh` は合成ログで次を確かめた（期待値は手計算）。

- 20 組の差から p50 / p95 / 最大を nearest-rank 法で出し、閾値ちょうどは PASS、超えると FAIL
- 秒・分・日・月末・閏日・年をまたぐ差、`+09:00` / `-05:00` / `Z` / `+0900` のオフセット、小数 1 桁のミリ秒
- 組めない `panel detected`（次の検知や `panel gone` が先に来た）、直前に検知の無い `palette shown`（ホットキーでの再表示）、end が start より前の組、解釈できないタイムスタンプを除外して件数を報告する
- ローテーションされた `openpath.log.1` と `openpath.log` をこの順に続けて読む（既定のログの探索も含む）
- ログが無い・`palette shown` が 1 行も無い・`panel detected` が 1 行も無い・1 組も組めないときは終了コード 2

### 3.5 Notarization（NFR-04）: 未実施

Developer ID Application 証明書と notarytool の資格情報がこの環境に無いため実施していない。手順は §6.3。

## 4. 注意点

- **メモリの余裕が小さい**: 候補 20,000 件の現在値は最大 40.67 MB で、基準の 50 MB まで 9.33 MB しかない。起動時の構築中のピークは最大 46.83 MB（余裕 3.17 MB）で、周期の再構築の最中は 53.91〜55.77 MB と 50 MB を超える。再構築中は旧い候補をインデックスに残したまま新しい候補を作るため、その分が一時的に上乗せされると考えられる。常駐メモリを「落ち着いた後の値」と読むなら PASS だが、「ピークも含めて 50 MB 以下」と読むなら FAIL であり、どちらで判定するかはオーナーの判断が要る。候補 0 件（約 16 MB）との差は約 20 MB で、DSN-002 §8 の `CandidateIndex` が保持する分（8.6 MB、PR #57）より大きい。残りの内訳（走査や前処理の一時領域がプロセスに残る分等）は調べていない。候補数はルートあたり 20,000 件が上限だが、ルートを複数置く・`include_files = true` にすると候補はさらに増える。
- **RSS ではなく phys_footprint で判定する**: phys_footprint は Activity Monitor の「メモリ」列・`footprint` コマンドと同じ値で、プロセスが専有するメモリ（圧縮・スワップされた分を含む）を表す。RSS は共有フレームワークのページを含む一方、圧縮・スワップされたページを含まないため、phys_footprint より大きくも小さくもなる（今回も、候補 0 件で phys_footprint 16.00 MB に対し RSS 31.55 MB、再構築 2 回の後で phys_footprint 35.44 MB に対し RSS 20.16 MB と、どちらの向きにもずれた）。`footprint` が task port を取れないときは `top -stats mem`（K / M 単位に丸められ、ピークは取れない）で代わりに取り、どちらを使ったかを出力に書く。
- **nettop は起動直後から回す**: `nettop` の値は、動かし始めてから観測したフロー（途中で閉じたものを含む）の累積で、監視を始める前に閉じたフローは数えられない。そのため `measure-isolated.sh start --settle-seconds 0` の直後に `measure-network.sh` を実行する。それでも起動からログファイルができるまで（1 秒未満）は監視の外になる。ソケットを持たないプロセスは `nettop` の出力に行が出ないため 0 バイトとして扱い、プロセスが動き続けていることは別に確かめる。
- **権限なしで測っている**: 計測用インスタンスにはアクセシビリティ権限が無いため、パネルの検知の 200ms ポーリングはアイドル CPU に含まれていない。権限付きでの計測はオーナーが行う（§6.2）。
- **アイドル CPU は 5 分ごとの周期の再構築を含めて測る**: 再構築の CPU 時間はアイドル時の平均の大半を占めるため、再構築を含まない短い計測（例: 30 秒）では過小評価になる。10 分（再構築 2 回分）以上測る。また、候補数によって合否が変わるため、計測時の候補数を必ず記録する。
- **計測中は操作しない**: パレットを開く・ホットキーを押す等の操作は計測値に入る。計測用インスタンスはホットキー（ctrl+shift+o）も登録するため、計測中は押さない。
- **初回起動フロー（#67）のマージ後**: 案内を終えたかを UserDefaults に記録し、未記録なら起動時に案内のウインドウを出す。一時 HOME での起動で案内のウインドウが出ると、その分メモリが増える。再計測のときは起動直後にウインドウが出ていないかを確かめる。

## 5. 前回の計測との比較

同じマシン・同じスクリプトで、#27（アプリ統合）のマージ直後のビルド（39db87a）を前回の担当が測った値は次のとおり（候補 20,000 件、一時 HOME）。今回のビルド（ea52baa）との差分はドキュメントだけで、アプリのコードは同じ。

| 項目 | 前回 | 今回 |
| --- | --- | --- |
| メモリ（phys_footprint 現在値） | 40.69〜46.59 MB（ピーク 46.05〜47.59 MB） | 35.17〜40.67 MB（ピーク 45.99〜46.83 MB）。周期の再構築の最中のピークは 53.91〜55.77 MB |
| メモリ（候補 0 件） | 16.38 MB | 16.00 / 16.25 MB |
| アイドル CPU | 0.0000〜0.0333%（30 秒） | 0.1784%（10 分、候補 20,000 件）/ 0.0570%（10 分、候補 5,000 件） |
| ネットワーク | 15 秒で 0 バイト・ソケット 0 個 | 起動直後から 391 秒で 0 バイト・ソケット 0 個 |

アイドル CPU の差は、前回の 30 秒の窓に周期の再構築が入っていなかったことによる。メモリの現在値は測るタイミング（構築直後か、落ち着いてからの経過時間）で数 MB 変わるため、今回は落ち着いてから 30 秒後に揃えた。

## 6. オーナーに実行してほしいこと

### 6.1 検知レイテンシ

`palette shown` を出す修正 PR がマージされた main で行う。実ユーザーの設定・ログに触れないよう、計測用インスタンスで測る（アクセシビリティ権限は .app に付くため、一時 HOME で起動しても権限付きで動く）。

```bash
./scripts/build.sh && ./scripts/sign.sh
eval "$(scripts/measure-isolated.sh start --candidates 20000)"
# システム設定 > プライバシーとセキュリティ > アクセシビリティ で build/openpath.app を許可する（5 秒以内に反映される）
grep 'アクセシビリティ権限' "$OPENPATH_LOG"   # 「アクセシビリティ権限が付与されました」か、起動時の「あり」が出ていること
# Finder で Cmd+O → パレットが出たのを確かめて「キャンセル」、を 20 回程度繰り返す（TST-001 §3 の S-01）
scripts/measure-detection-latency.sh --log "$OPENPATH_LOG"
scripts/measure-isolated.sh stop "$OPENPATH_MEASURE_DIR"
```

- ad-hoc 署名ではビルドごとに署名要件（cdhash）が変わるため、再ビルドしたら権限を付け直す
- 普段の環境で測る場合は、アプリを起動して同じ操作をした後に `scripts/measure-detection-latency.sh`（`~/Library/Logs/openpath/openpath.log.1` と `openpath.log` を読む）を実行する
- 結果（p50 / p95 / 最大 / 組にできた件数）を本書 §1 と §3.4 に追記する

### 6.2 権限付きでのアイドル CPU

§6.1 と同じく権限を付けた計測用インスタンスで、パネルの検知（200ms ポーリング）を含めて 10 分測る。計測中は Finder 等を前面にしたまま操作しない。候補 20,000 件では周期の再構築だけで基準を超える（§3.2）ため、ポーリングの寄与を見るには候補 0 件か 5,000 件でも測る。

```bash
eval "$(scripts/measure-isolated.sh start --candidates 5000)"   # 20000 / 0 でも測る
grep 'アクセシビリティ権限' "$OPENPATH_LOG"                        # 権限が付いていること
sleep 30
scripts/measure-idle-cpu.sh --pid "$OPENPATH_PID"
scripts/measure-isolated.sh stop "$OPENPATH_MEASURE_DIR"
```

### 6.3 Notarization

```bash
./scripts/build.sh
OPENPATH_SIGN_IDENTITY="Developer ID Application: ..." ./scripts/sign.sh
OPENPATH_NOTARY_PROFILE=<profile> ./scripts/notarize.sh   # 提出・staple の後に spctl --assess --type execute -vv まで実行する
spctl -a -vv build/openpath.app   # 単独で確かめ直す場合。"accepted" と "source=Notarized Developer ID" を確認する
```

`OPENPATH_NOTARY_PROFILE` は `xcrun notarytool store-credentials <profile>` で keychain に保存したプロファイル名。結果を本書 §1 と §3.5 に追記する。

### 6.4 アイドル CPU の FAIL とメモリのピークの扱いを決める

TST-001 §6 の完了条件（5 章の合格基準を満たす）に対し、候補 20,000 件のアイドル CPU は基準を満たさない。また、常駐メモリは周期の再構築の最中に一時的に 50 MB を超える。次のどれで扱うかの判断が要る。

- 合格基準の条件を明確にする（例: アイドル CPU は候補数を定めて測る、常駐メモリは落ち着いた後の値で判定する）
- アプリ側で周期の再構築のコストを下げる（例: ルートの変更が無ければ走査を省く、FSEvents で変更を検知する、周期を延ばす）。いずれも `Sources/` の変更で、本 PR の範囲外
- 現状を既知の制約として受け入れ、REQ-001 NFR-03 の「目標」の扱いを記録する
