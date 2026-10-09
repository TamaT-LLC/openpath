# 未リリースの変更

次の版に入る変更を記録する。
`v0.1.2` の内容は [v0.1.2 のリリースノート](./v0.1.2.md) にある。
Stable のタグは Preview と同じコミットに付けるので、Preview を作る前に、このファイルを `vX.Y.Z.md` に改めて 1 行目を `# vX.Y.Z` または `# vX.Y.Z（補足）` にし、新しい `unreleased.md` を作る。
続けて `python3 scripts/release_notes_index.py` で [ドキュメントインデックス](../00_index/index.md) のリリースノート一覧を作り直す（CI が `--check` で検査する）。

## 変更

- アプリの動作に変更はない。

## 配布と開発環境の変更

- README の「検索」まわりの説明から、`cdr` や `fzf` を引き合いに出す表現を外した（#123）。UX 設計、プロダクト概要、ドキュメントインデックスの題も合わせた。
- `FileListRowSampler` と `FileListSample` のテストで、パラメータ化テストの引数の配列に型注釈（`as [(String, String, Int)]` など）を付けた（#123）。テストの内容は変えていない。
- README.md に約 35 秒の日本語版の紹介動画（日本語ナレーション付き）を（#124）、README.en.md に約 34 秒の英語版の紹介動画（英語のナレーションと画面表記）を（#125）、GitHub の動画添付（user-attachments）で埋め込んだ。GitHub の README ではリポジトリ内の mp4 を再生できないため、添付の URL を単独の行で置き、README 上でプレーヤーとして再生される形にしている。動画とポスター画像はリポジトリに置かない。
- ドキュメントインデックスのリリースノート一覧を、`docs/releases/` から `scripts/release_notes_index.py` で生成するようにした。CI の `repository policy` が `--check` で一覧の食い違いを検出する。リンクの補足は、各リリースノートの 1 行目の括弧（例: `# v0.1.0（最初の Stable）`）から取る。
- 署名・公証の Secrets を environment `release`（デプロイ対象は tag `v*`）に、Homebrew tap 更新用の GitHub App の秘密鍵と Client ID を environment `homebrew-tap`（tag `v*` と branch `main`）に移した。`Release macOS` は Stable を `package-stable` job、Smoke と Preview を environment なしの `package` job で作る。`.github/settings-desired-v1.json` に両 environment を宣言し、Required reviewers のない environment はデプロイ対象の ref を限定することを `github_policy_check.py` で検査する。
- ruleset `protect-release-tags` の宣言に、タグ作成の禁止（`creation` ルール）と、リポジトリのロール admin の bypass を加えた。Stable と Preview のタグを作れるのは admin だけになる。manifest に tag ruleset 用の `allow_creations` を加え、drift の照合も対応させた。

## 実機で確かめる項目

[v0.1.1 のリリースノート](./v0.1.1.md) の「実機で確かめていない項目」を引き継ぐ。
