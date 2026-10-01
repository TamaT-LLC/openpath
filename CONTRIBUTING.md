# Contributing to openpath

Issue、文書、テスト、コードへの貢献を歓迎します。
openpath は他のアプリへキー入力を送る権限で動くため、機能の正しさに加えて、意図しない入力を起こさないことと、パスを外へ漏らさないことを重視します。

## 報告先を選ぶ

- 再現できる不具合は [Bug report](https://github.com/TamaT-LLC/openpath/issues/new?template=bug_report.yml) から報告してください。
- 機能の提案は [Feature request](https://github.com/TamaT-LLC/openpath/issues/new?template=feature_request.yml) から提案してください。
- 使い方の質問とサポート対象の version は [SUPPORT.md](./SUPPORT.md) を確認してください。
- security vulnerability は公開 Issue に書かず、[SECURITY.md](./SECURITY.md) の private vulnerability report から報告してください。

Issue を作る前に、既存の Issue と [README](./README.md) を確認してください。
ログ、設定、スクリーンショットを添える場合は、再現に不要なパスとユーザー名を伏せてください。

## 開発環境を準備する

macOS 14 以降と、Swift 6.0 以降のツールチェーンを使います。
Xcode は不要で、Command Line Tools（`xcode-select --install`）だけでビルドとテストができます。
CI は macOS 15 の runner で Xcode 16.4 を使います。
リリース条件とリポジトリの方針の検証には、Command Line Tools に含まれる `python3`（3.9 以降）を使います。

```console
swift build
./scripts/test.sh
swift run openpath
```

Command Line Tools だけの環境では、素の `swift test` が `no such module 'Testing'` で失敗します。
`./scripts/test.sh` は必要なフラグを補ってから `swift test` を実行し、引数はそのまま渡します（例: `./scripts/test.sh --filter AppInfo`）。

## 変更を作る

`main` へは Pull Request を通して変更します。
変更ごとに短い branch を作り、目的と関係しない変更を同じ Pull Request に含めないでください。
commit message は [Conventional Commits](https://www.conventionalcommits.org/ja/v1.0.0/) の形式（`fix(palette): ...` など）で書きます。

不具合の修正には、修正前に失敗し、修正後に成功するテストを追加してください。
ファジーマッチ、frecency、設定の読み込み、状態機械などの判断は、AppKit に依存しない `OpenPathCore` に置き、Swift Testing で確かめます。
アクセシビリティ API とキー入力に関わる部分（`OpenPathMac`）は CI で動かせないため、次の「手動シナリオ」で確かめます。

挙動や設計を変える場合は、`docs/` の該当する設計文書も更新してください。
文書の一覧は [ドキュメントインデックス](./docs/00_index/index.md) にあります。
利用者に見える変更は、[未リリースの変更](./docs/releases/unreleased.md) にも追記してください。
version を上げるときは、`Resources/Info.plist` と `Sources/OpenPathCore/AppInfo.swift` を一緒に更新します（不一致はテストで検出されます）。

テストの fixture には架空のパスを使ってください。
実際のホームディレクトリ、ユーザー名、debug ログを commit しないでください。

## 変更を検証する

Pull Request を作る前に、次を実行してください。

```console
swift build
./scripts/test.sh
python3 scripts/release_ci_test.py
python3 scripts/github_policy_test.py
python3 scripts/github_policy_check.py
```

`github_policy_check.py` は、workflow が使う Actions が [.github/actions-policy.json](./.github/actions-policy.json) の commit SHA に固定されていることと、[.github/settings-desired-v1.json](./.github/settings-desired-v1.json) の必須チェックが CI の job 名と一致することを確かめます。
Pull Request の CI は、Swift のビルドとテストに加えて、この検証も実行します。

### 手動シナリオ

検知、パレット、注入、メニュー、設定、権限、初回起動の挙動が変わる Pull Request では、アクセシビリティ権限を付与した `openpath.app` で手動シナリオを確かめます。
項目と ID は [手動シナリオテスト](./docs/50_test/test-openpath-manual-scenarios.md) にあり、§14 の対応表で影響範囲の項目を選びます。
結果は Pull Request テンプレートの表に記入してください。
権限の無い環境で確認できなかった項目は「未確認」とし、maintainer に確認を依頼してください。

### GitHub Actions を変える場合

workflow の `uses:` は、tag ではなく commit SHA に固定し、末尾に `# vX.Y.Z` の形で version を書きます。
`github_policy_check.py` は workflow を行単位で読み、正しく読めると保証できない書き方は拒否します（fail closed）。
`on:` と、Pull Request で動く job の見出しの直下は、2 スペース字下げの block style で書いてください（`{}` や `[]` のインライン、anchor、alias は使えません）。
新しい Action を使う場合や version を上げる場合は、upstream の tag から SHA を解決し、`.github/actions-policy.json` も同じ変更で更新してください。

```console
gh api repos/actions/checkout/git/ref/tags/v7.0.1 --jq '.object'
```

`type` が `tag`（annotated tag）の場合は、`gh api repos/<owner>/<repo>/git/tags/<sha> --jq '.object.sha'` で commit の SHA を取り出します。
GitHub Actions の更新は Renovate が Pull Request を作ります。
Renovate は `.github/actions-policy.json` を更新しないため、内容を確認した maintainer が同じ Pull Request で policy を更新します。

## Pull Request を作る

Pull Request には、変更理由、変更内容、関連 Issue、検証結果を記載してください。
実行できなかった検証がある場合は、理由と影響範囲を明記してください。

次の変更では、privacy と security への影響を本文で説明してください。

- 検知の対象、キー入力の合成、クリップボードの扱いを変える変更
- ログに残す内容や、保存するデータを変える変更
- 新しい権限、子プロセス、外部の依存を加える変更
- release workflow、署名、公証、配布物を変える変更

CODEOWNERS の review と必須 CI が完了し、review の会話がすべて解決するまで merge できません。
例外として、緊急時に限り `@TakehiroT` は承認（CODEOWNERS の review を含む）を省略して merge できます（[GOVERNANCE.md](./GOVERNANCE.md)）。
この場合も、必須 CI の成功と会話の解決は省略できません。
Pull Request で提出した変更は、このリポジトリの [MIT License](./LICENSE) で提供されたものとして扱います。

## リリース

version tag と GitHub Release は、maintainer が [リリース運用](./docs/40_arch_design/guide-release-distribution.md) に従って作ります。
Stable を公開するときは、`docs/releases/unreleased.md` を `docs/releases/v<version>.md` に改め、新しい `unreleased.md` を作ります。
意思決定とリリースの責任は [GOVERNANCE.md](./GOVERNANCE.md) にまとめています。

## 行動規範

すべての参加者は [Code of Conduct](./CODE_OF_CONDUCT.md) に従ってください。
