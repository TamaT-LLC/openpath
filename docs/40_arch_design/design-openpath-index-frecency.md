---
id: PROJ-DSN-002
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

# 詳細設計: 候補インデックスと frecency（CandidateIndex / HistoryStore / ConfigStore）

## 1. 対象要件

FR-PALETTE-02/03/06、FR-SOURCE-01〜05、FR-HISTORY-01〜04、FR-CONFIG-01。

## 2. データモデル

```swift
struct Candidate: Hashable {
    let path: String          // 正規化済み絶対パス
    let name: String          // 表示名（lastPathComponent）
    let isDirectory: Bool
    let source: Source        // .history / .root(String) / .ghq
    let frecency: Double      // HistoryStore 由来。履歴なしは 0
    let lastUsed: Date?
}

struct HistoryEntry: Codable {
    var path: String
    var count: Int
    var lastUsed: Date        // JSON キーは CodingKeys で "last_used" に変換（ARCH-001 §8 に合わせる）
}
```

`history.json` は `[HistoryEntry]`。日付は UTC の ISO 8601・秒精度（例 `2026-05-09T06:13:20Z`。frecency の減衰は最短でも 1 時間単位のためミリ秒精度は不要、PR #34 / #42）。上限 2,000 件、超過時は frecency 下位から削除する。

- **`Candidate.frecency` / `lastUsed` は `let`**: クエリ時点の値を詰めた結果として返すため不変にした（当初案は `var`、PR #57）。
- **上限超過時のタイブレーク**: frecency が同点なら `lastUsed` が古い方を先に消し、`lastUsed` も同じならパスの辞書順で後ろの方を消す。並び順は frecency 降順 → `lastUsed` が新しい順 → パス昇順で固定する（PR #34）。
- **直前に record したパスは削除対象外**（設計にない追加の判断）: 新規パス（count 1、frecency 最大 4.0）が既存 2,000 件よりすべて低い場合、単純に最下位を消すと記録した直後のパスが消えてしまうため（PR #34）。
- **`init(entries:)` は重複パスを統合する**: 同一パスが複数あれば最初の位置の 1 件にまとめ、count は合算、`lastUsed` は新しい方を使う（`record` の「同一パスは 1 件」という前提を型側で保証するため、PR #34）。
- **掃除条件（FR-HISTORY-03）は `>=` 判定**: ちょうど 90 日も削除対象。存在確認は 90 日以上使われていないエントリにのみ行う（保存のたびに全件確認しない、PR #34）。

## 3. 候補ソース

```swift
protocol CandidateSource: Sendable {
    var kind: Source { get }
    func snapshot() async throws -> CandidateSourceSnapshot  // { items: [SourceItem(path, isDirectory)], warnings }
}
```

| ソース | 収集方法 | 更新契機 |
| --- | --- | --- |
| history | `HistoryCandidateSource(store:)` → `HistoryStore.entries` | 確定のたび（`CandidateIndexRebuilder.refreshHistory()` 経由。全件再構築のカウントには含めない） |
| roots | `RootCandidateSource.sources(for: config)` が **ルートごとに 1 ソース**を生成。`RootDirectoryScanner`（`FileManager.enumerator` を同期 API でラップ）で `config.depth` まで走査。`.skipsHiddenFiles`、`node_modules` / `.git` / `target` / `DerivedData` は既定で除外（`config.ignore` で変更可） | 起動時、全件再構築が終わってから 5 分後、メニューの「候補を再構築」、`roots` / `depth` / `ignore` / `ghq.enabled` の設定変更 |
| ghq | `GhqCandidateSource(lister:)` → `GhqRepositoryLister` が `Process` で `ghq root` → `ghq list -p` を実行。`PATH` は `LoginShellPathResolver`（login shell から取得するキャッシュ持ちの actor）で解決し、候補ソースと ConfigStore（§6）で 1 インスタンスを共有する | 同上 |

- 走査は `Task.detached(priority: .utility)` から `snapshot()` を呼び、完了した時点で `CandidateIndex.replace(source:with:)` によりアトミックに差し替える（同一ソースの走査は直列）。ルートが設定から外れた場合は空配列で `replace` する。
- roots は 1 ルートあたり 20,000 件で打ち切る（`RootDirectoryScanner` が発生元で警告ログを出す）。パッケージ（`.app` 等）判定は `includingPropertiesForKeys: [.isPackageKey]` を先読みせず、**拡張子のあるディレクトリにだけ個別に問い合わせる**（先読みは LaunchServices を引くため 5,000 件の列挙だけで数百 ms かかった。ベンチの最小値が 289ms → 45ms に改善、PR #51）。
- ghq: login shell から取れた PATH に既定 PATH（`/opt/homebrew/bin` 等）の不足分を補う。`ghq root` が空なら `emptyRoot` として失敗扱いにし、`ghq list -p` は実行しない（`ghq list -p` の出力が空なのは失敗ではなく空の一覧として返す）。login shell 起動のフォールバック結果はキャッシュする（5 分ごとの再構築のたびに待たないため）。`fetchRoot` は内部実装に留め、既定 config 生成（§6）との関係は未確定（PR #43）。
- 全件の再構築は「5 分ごと」の固定時刻ではなく「前回の再構築を終えてから 5 分」で数える。設定の変更ではどの設定に依存するソースかを問わず全ソースを走査し直す（対応表を持つ複雑さを避けるため。候補ソースに関わらない設定（hotkey・auto_confirm・disabled_apps）では再構築しない）。roots から外れたルート・無効にした ghq の除去は、次の再構築の冒頭で直列に行う（設定変更時に即座に `replace(source:with: [])` すると、走査中の差し替えと並行して後勝ちで候補が復活しうるため、PR #61）。
- 同一パスが複数ソースにある場合は 1 件に統合し、`source` は優先度 history > ghq > roots で決める。統合キーはファイルシステムを引かない字句的な正規化（末尾 `/`・`//`・`.`・`..`。`RootPathResolver` と同じ規則）を使う。isDirectory の判定が食い違う場合はファイル扱いにする（フォルダ選択のパネルにファイルを誤って出すより、ディレクトリを 1 件出し損ねる方が害が小さいため）。絶対パスにできない候補は含めない。frecency / `lastUsed` は同じ正規化をかけた上で `HistoryStore` から引く（PR #57）。
- 空クエリで履歴（frecency > 0）が 8 件未満のときは、frecency 0 の候補をパスの昇順で補う（初回起動で履歴が空のときに「一致する候補がありません」を出さないため、PR #57）。
- 候補数が 10,000 件以上のときの前置フィルタは「取りこぼさない」よう、先頭 2 文字（正規化後）のどちらかを含まない候補を外す判定として実装する（候補ごとに含む文字を 256 ビットへ畳んで 1 回の AND で判定。ファジーマッチはクエリを部分列として含む必要があるため結果は変わらない、PR #57）。
- 履歴をクリアしたときは `CandidateIndexRebuilder.historyDidClear()` を呼ぶ。全件の再構築の走査中なら取り消して走査し直し、それ以外は履歴だけを取り直す（走査の終わりまで待つと、消した場所が全件走査の間ずっと候補に残るため、PR #65）。
- 検索語が `/` または `~/` で始まり末尾が `/` でないときは、`RootPathResolver`（roots と同じ字句的な正規化）で正規化した上で存在と種別（ディレクトリに絞るときはディレクトリ。パッケージはファイル扱い）を確かめ、候補の先頭に加える（`DirectPathEntry`、UX-001 §5「Tab でパスを直接入力」）。同じパスの候補は除き、その最終使用日時を引き継ぐ。存在確認はクエリと同じく MainActor の外で行い、取り消された検索では行わない（PR #65）。

## 4. frecency スコア

zoxide の aging 方式を簡略化して採用する。

```
score(entry, now) = count × decay(hours = (now - lastUsed) / 3600)

decay(h):
  h <  1     → 4.0
  h < 24     → 2.0
  h < 24×7   → 0.5
  otherwise  → 0.25
```

- 確定時: `count += 1`, `lastUsed = now`。
- 経過時間は暦（`Calendar`）ではなく経過秒で判定する（夏時間の影響を受けない）。`lastUsed` が未来（時計の巻き戻り）の場合は直前に使ったものとして 4.0 を返す（PR #34）。
- `entries` は最初に記録した順で保持し、frecency 順には並べ替えない（保存時の差分を小さくするため）。frecency 順が必要な場合は `sortedByFrecency(now:)` を使う。
- 表示時の総合順位: `fuzzyScore × (1 + log1p(frecency))`。入力が空のときは `frecency` のみで降順。
- 存在確認: 表示直前に `FileManager.fileExists` で確認し、存在しないものは除外。90 日以上使われず存在しないエントリは保存時に削除（FR-HISTORY-03）。

## 5. ファジーマッチ

- アルゴリズム: fzf v2 に準ずる簡略版。Smith-Waterman 系の DP ではなく、後方走査で各クエリ文字の置ける最も後ろの位置を求めたうえで、1 文字目の出現ごとに前方へ貪欲に位置を選ぶ（各文字は局所加点が最大の位置、同点なら手前）二段の貪欲法。計算量は通常 O(n)、最悪 O(n × 1 文字目の出現数)（PR #40）。
- 対象文字列: `name` を主、`path` を副として両方にマッチさせ、高い方を採用（`name` マッチには +20% のボーナス）。
- 正規化: Unicode NFC に正規化した上で `folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])`。ただし **かな（ひらがな・カタカナ・カタカナ拡張・半角カナ）は `.diacriticInsensitive` を外し、濁点・半濁点は保持する**（「しりょう」で「じりょう」にマッチさせないため。IME 入力では濁点は常に正しく付き、NFD の濁点分離は NFC への合成で解決するので落とす必要がない、PR #47）。**小書きのかな（ゃ/っ/ヵ/ヶ 等）も同一視しない**（IME 入力で常に区別されるため）。ローマ字変換は行わない。Character 単位で正規化し、展開（`ß`→`ss` 等）があっても元の位置を保てるようにする。
- 高速化: ASCII の小文字化と CJK 統合漢字（U+4E00〜U+9FFF、NFC 済みで折り畳んでも不変）は Foundation を呼ばず、かな 1 文字は結果を表にして引く（1 文字ごとに Foundation を呼ぶと、日本語ファイル名中心の候補 5,000 件の正規化が 4 倍以上遅くなったため、PR #47）。
- 入力が空: マッチ処理をスキップし、frecency 上位 8 件（8 件に満たない場合は §3 のとおり frecency 0 をパス昇順で補う）を返す。空クエリも score 1・positions `[]` のマッチとして扱う。
- 候補数が 10,000 件以上のとき: 先頭 2 文字で前置フィルタしてからマッチ（§3 参照。取りこぼさない実装）。
- 前処理済み API（`prepareQuery` / `prepareTarget`）を用意し、結果を `FuzzyTarget` として CandidateIndex 側に保持する（キー入力のたびに候補全件を正規化し直さないため）。`FuzzyTarget` は 1 文字を「文字コード 24 ビット + 位置ボーナス 8 ビット」の 4 バイトに圧縮する（20,000 件で実測 8.6MB。name / path の前処理結果を両方保持する当初案では 20,000 件で 56.8MB になったため、PR #7 → #13・#57）。

```swift
struct FuzzyMatcher {
    func score(query: PreparedQuery, in target: FuzzyTarget) -> (score: Int, positions: [Int])?
}
```

- ボーナス: 先頭一致 +16、`/` `-` `_` `.` 直後 +12、CamelCase 境界（小文字 → 大文字のみ。数字境界は含まない）+8、連続一致 +6、**完全一致 +16（追加）**。
- ギャップ罰則: 1 文字ごとに -3。ただし **区切り直後 / CamelCase 境界に着地するギャップだけは 1 文字 -1**（仕様どおり一律 -3 だと、頭文字入力や連続一致を含む短い候補が不当に不利になり TST-001 §2.1 の期待順位を満たせないため。-1 は頭文字入力と連続一致を両立できる唯一の整数値、PR #40）。
- マッチ時のスコアの下限は 1（総合順位 `fuzzyScore × (1 + log1p(frecency))` が、frecency の高い候補ほど不利になる逆転を避けるため、PR #40）。
- 型名は `FuzzyCandidateMatch` / `FuzzyMatchField`（`Candidate` 系の型との名前衝突を避けるため接頭辞 `Fuzzy` を付けた）。
- 戻り値の `positions` は UI のハイライトに使う。

## 6. ConfigStore

`~/.config/openpath/config.toml`（記入例。実際の既定生成では `roots` は空、`disabled_apps` も空になる。以下は値の書き方のサンプルであって既定値ではない、PR #41）:

```toml
roots = ["~/repos", "~/Documents"]
depth = 2
include_files = false
auto_confirm = false
hotkey = "ctrl+shift+o"
disabled_apps = ["com.apple.finder"]
ignore = ["node_modules", ".git", "target", "DerivedData", ".build"]

[ghq]
enabled = true
```

- **既定値**: `roots` は空配列（環境によっては `~/repos` 等が存在しないため。既定ファイル生成時に ConfigStore が `ghq root` を書き込む運用に任せる）。`disabled_apps` も空（REQ-001 FR-DETECT-04「既定は全アプリ有効」のため。Finder を既定で無効にすると UX-001 §7 の「試してみる」が成立しない）。`disabledApps` は `Set<String>`（包含判定にしか使わないため）、`ignore` は `[String]` のまま（PR #41）。
- `roots` の正規化は字句的（空要素・`.`・`..`・末尾 `/` を除く。ファイルシステムは参照せずシンボリックリンクも解決しない）。相対パス・`~user` 形式・空文字は `invalidRootPath` エラーにする。正規化後の重複は先に書かれたものを残す。`depth` は下限 0（負値はエラー）、上限なし（roots 走査自体が 1 ルート 20,000 件で打ち切られるため、PR #41）。
- **ホットキーの文法**: 修飾キーは `ctrl`/`control`、`shift`、`opt`/`option`/`alt`、`cmd`/`command`。キーは A–Z・0–9・記号 11 種（`-` `=` `[` `]` `\` `;` `'` `,` `.` `/` とグレーブアクセント）・`space`・`return`/`enter`・`tab`・`delete`/`backspace`・`escape`/`esc`・矢印・`f1`–`f12`。大文字小文字・順序・前後の空白は区別しない。**修飾キーが shift だけの場合はエラー**（`shiftOnlyModifier`。大文字入力そのものを奪うため）。値は Carbon の `kVK_*` / 修飾キー定数と同じ表現で持ち（`RegisterEventHotKey` に変換なしで渡せる）、`Hotkey.description` は `ctrl+opt+shift+cmd+<key>` の順で正規表記を返す（PR #41）。
- 読み込み: 起動時 + ファイルのディレクトリ監視（`DispatchSource`、メインキューで配送）。`rename` / `delete` 後にまだファイルが無ければ 200ms 間隔で最大 10 回（約 2 秒）リトライし、それでも無ければ `lastError = .fileNotFound` を公開する。以降の再作成は親ディレクトリの書き込みイベントで拾う。デバウンスは 100ms（PR #50）。
- パース失敗時: 直前の有効設定を維持し、StatusItem にバッジ + ログ出力。エラーはキーパス（`ghq.enabled` 等。`TOMLTable` は出現位置を持たないため行番号の代わり）で示す。複数の誤りがあれば `roots → depth → include_files → auto_confirm → hotkey → disabled_apps → ignore → ghq` の順で最初の 1 件を報告する。未知のキーはエラーにせず `ConfigWarning.unknownKey(キーパス)` として警告する（PR #41）。
- 既定値の生成: ファイルが無い場合に生成する。`roots` は `ghq root` が絶対パスに解決できればホーム配下を `~` で書いて含める（dotfiles で別マシンと共有しやすくするため）。解決できない場合（相対パス・`~user`）は `roots` に含めない。既存ファイルは上書きしない（`.withoutOverwriting`）。
- TOML ライブラリ: 上記キーのみをサポートする自前パーサ（文字列 / 真偽 / 整数 / 文字列配列 / 1 階層テーブル）。サポート外の構文（浮動小数・日時・インラインテーブル・ネストテーブル・ドット区切りキー・複数行文字列・16/8/2 進整数・文字列以外の配列）は TOML として正しくても `unsupported(...)` として明示的にエラーにする（黙って誤読しない）。外部依存を避ける（PR #35）。

## 7. HistoryStore の永続化

- 並行性は `@MainActor` クラス（`HistoryRecording` 準拠）を選択した。CandidateIndex がパレット表示時に UI スレッドから同期的に読む必要があり（§8「空入力時 30ms 以内」）、actor にすると読み出しのたびに `await` が要る。保存も MainActor 上で直列に実行するため、デバウンス保存と終了時の `flush()` の順序が入れ替わらない（PR #42）。
- 読み書き先は `HistoryPersisting`（`HistoryFile`）として `HistoryStore` から分離する。保存タイミングの制御（デバウンス等）と、ファイル形式・権限・破損時の退避を分けることで、実ファイルなしでテストできるようにするため。
- 書き込みは確定のたびに trailing デバウンス（最後の `record` から 500ms。期限は `record` 呼び出し時に確定させ、Task の起動が遅れても起点はずれない）で `Data.write(to:options: .atomic)`。**`clear()` はデバウンスせず即時保存する**（利用者が明示的に消した履歴が、直後の異常終了でディスクに残らないようにするため）。保存に失敗した場合は変更を未保存のまま保持し、次の `record` / `flush()` で保存し直す（自動リトライはしない）。`clear()` は保存できたかを `Bool` で返し、呼び出し側がダイアログで知らせられるようにする（UX-001 §6、PR #65）。
- ファイルが無い（`notFound`）以外の読み込み失敗・デコード失敗はすべて破損とみなし、`history.json.broken-<timestamp>` にリネームして空から開始する。退避にも失敗した場合は空のまま起動し、次の保存で上書きする。
- ファイル権限: 書き込みのたびに 0600 を設定し直す（`.atomic` 書き込みは新規ファイルとして rename するため、設定までの一瞬は既定の 0644 になる）。ディレクトリは 0700 で作成する。
- 保存時の掃除（§4 の 90 日ルール）はメモリ上の履歴にも反映する。

## 8. パフォーマンス目標

| 項目 | 目標 |
| --- | --- |
| 空入力時のパレット初期表示 | 30ms 以内（history のみ、メモリ上） |
| 1 文字入力ごとのマッチ（候補 5,000 件） | 16ms 以内（メインスレッドをブロックしない） |
| 候補の前処理（正規化・`FuzzyTarget` 構築） | 200ms 以内（独自追加の目標。roots 走査目標の 1 割として設定。デバッグビルドは 10 倍まで緩和、PR #47） |
| roots 走査（2 階層、5,000 件） | 2 秒以内、バックグラウンド |
| 常駐メモリ | 候補 20,000 件で 30MB 以下（`CandidateIndex` が保持する分・ヒープ増分として計測。実測は `FuzzyTarget` 圧縮後で 8.6MB、PR #57。アプリ全体の常駐量は #27 の統合後に実機で確認する） |
