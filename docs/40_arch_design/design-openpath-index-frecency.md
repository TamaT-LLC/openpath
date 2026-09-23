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
updated: 2026-09-23
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
    var frecency: Double      // HistoryStore 由来。履歴なしは 0
    var lastUsed: Date?
}

struct HistoryEntry: Codable {
    var path: String
    var count: Int
    var lastUsed: Date
}
```

`history.json` は `[HistoryEntry]`。上限 2,000 件、超過時は frecency 下位から削除。

## 3. 候補ソース

| ソース | 収集方法 | 更新契機 |
| --- | --- | --- |
| history | `HistoryStore.entries` | 確定のたび |
| roots | `config.roots` 各パスを `FileManager.enumerator(at:includingPropertiesForKeys:options:)` で `config.depth` まで走査。`.skipsHiddenFiles`、`node_modules` / `.git` / `target` / `DerivedData` は既定で除外（`config.ignore` で変更可） | 起動時、5 分間隔、メニューの「候補を再構築」 |
| ghq | `Process` で `ghq root` → `ghq list -p` を実行（`PATH` は login shell から取得: `/bin/zsh -lc 'echo $PATH'`）。失敗時は警告ログのみ | 同上 |

- 走査は `Task.detached(priority: .utility)` で行い、完了した時点で `CandidateIndex.replace(source:with:)` によりアトミックに差し替える。
- roots は 1 ルートあたり 20,000 件で打ち切る（それ以上は警告）。
- 同一パスが複数ソースにある場合は 1 件に統合し、`source` は優先度 history > ghq > roots で決める。

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
- 表示時の総合順位: `fuzzyScore × (1 + log1p(frecency))`。入力が空のときは `frecency` のみで降順。
- 存在確認: 表示直前に `FileManager.fileExists` で確認し、存在しないものは除外。90 日以上使われず存在しないエントリは保存時に削除（FR-HISTORY-03）。

## 5. ファジーマッチ

- アルゴリズム: fzf v2 に準ずる簡略版（Smith-Waterman 系ではなく、先頭一致・区切り直後一致・連続一致にボーナスを付ける貪欲マッチ）。
- 対象文字列: `name` を主、`path` を副として両方にマッチさせ、高い方を採用（`name` マッチには +20% のボーナス）。
- 正規化: Unicode NFC に正規化した上で `folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])`。日本語はひらがな / カタカナの同一視まで（`kanaInsensitive` 相当）を行い、ローマ字変換は行わない。
- 入力が空: マッチ処理をスキップし、frecency 上位 8 件を返す。
- 候補数が 10,000 件以上のとき: 先頭 2 文字で前置フィルタしてからマッチ。

```swift
struct FuzzyMatcher {
    func score(query: String, in text: String) -> (score: Int, positions: [Int])?
}
```

- ボーナス: 先頭一致 +16、`/` `-` `_` `.` 直後 +12、CamelCase 境界 +8、連続一致 +6、ギャップ 1 文字ごとに -3。
- 戻り値の `positions` は UI のハイライトに使う。

## 6. ConfigStore

`~/.config/openpath/config.toml`:

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

- 読み込み: 起動時 + `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask: [.write, .rename, .delete])`。エディタのアトミック保存（rename）に追従するため、`rename`/`delete` 後は 200ms 後に再オープンする。
- パース失敗時: 直前の有効設定を維持し、StatusItem にバッジ + ログ出力。
- 既定値の生成: ファイルが無い場合、`ghq root` が取れれば `roots` に含めて生成する。
- TOML ライブラリ: 上記キーのみをサポートする自前パーサ（文字列 / 真偽 / 整数 / 文字列配列 / 1 階層テーブル）で十分。外部依存を避ける。

## 7. HistoryStore の永続化

- 書き込みは確定のたびに `Task` でデバウンス（500ms）し、`Data.write(to:options: .atomic)`。
- 読み込み失敗（破損）時は `history.json.broken-<timestamp>` にリネームして空から開始。
- ファイル権限: 0600。

## 8. パフォーマンス目標

| 項目 | 目標 |
| --- | --- |
| 空入力時のパレット初期表示 | 30ms 以内（history のみ、メモリ上） |
| 1 文字入力ごとのマッチ（候補 5,000 件） | 16ms 以内（メインスレッドをブロックしない） |
| roots 走査（2 階層、5,000 件） | 2 秒以内、バックグラウンド |
| 常駐メモリ | 候補 20,000 件で 30MB 以下 |
