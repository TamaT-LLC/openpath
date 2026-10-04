# 未リリース

次の版（`v0.1.1` 以降）に入る変更を記録する。
最初の Stable `v0.1.0` の内容は、[v0.1.0 のリリースノート](./v0.1.0.md) にある。
このファイルを追加しただけでは公開にならない。
Stable の tag、GitHub Release、添付の `SHA256SUMS` がそろったときに、正式版として扱う。
Stable を公開するときは、このファイルを `vX.Y.Z.md` に改め、新しい `unreleased.md` を作る。

## 変更

- Stable の公開後に、GitHub App で Homebrew tap（`TamaT-LLC/homebrew-tap`）へ cask の更新 Pull Request を自動で出し、auto-merge を要求するようにした。
- cask の最小 macOS を `depends_on macos: ">= :sonoma"` から `depends_on macos: :sonoma` に改めた。Homebrew 6.0.0 から記号だけで「Sonoma 以降」を表し、`">= :sonoma"` は非推奨で `brew style` が失敗するためである。Homebrew 5.x 以前はこの書き方を「Sonoma のみ」と解釈する。
