# Security policy

openpath は、アクセシビリティ権限で他のアプリのファイル選択パネルを検知し、キー入力を合成してパスを入力するメニューバー常駐アプリです。
他のアプリへ入力を送れる強い権限を使うため、意図しない場面での入力、パスの漏えい、配布物の改ざんを security 上の問題として扱います。

## Vulnerability reporting

security issue は公開 Issue に詳細を書かず、GitHub の [private vulnerability report](https://github.com/TamaT-LLC/openpath/security/advisories/new) から報告してください。
対象の version または commit、macOS の version、影響、再現手順を含めてください。
ログやスクリーンショットにはフォルダ名やファイル名が含まれることがあるため、再現に不要なパスとユーザー名は伏せてください。

private vulnerability report のフォームが使えない場合も、内容を公開しないでください。
[TamaT のお問い合わせフォーム](https://tamat.jp/contact)から、詳細を書かずに非公開の窓口が使えないことだけを知らせてください。

## Supported versions

現在、公開済みの Stable はありません。
最初の Stable `v0.1.0` を公開した後は、最新の Stable だけを security update の対象にします。

| Version | Security update |
| --- | --- |
| 最新の Stable（`vX.Y.Z`） | 対象。最初の Stable は `v0.1.0` の予定です |
| Preview（`preview-vX.Y.Z-N`） | 対象外。ad-hoc 署名で公証していない評価用のビルドです |
| `main` とソースからのビルド | best effort。修正は `main` に先に入れます |
| 古い Stable | 対象外。最新の Stable へ更新してください |

## Security boundary

openpath が守る範囲は次のとおりです。
仕組みの詳細は [アーキテクチャ設計](./docs/40_arch_design/arch-openpath-app.md) の「セキュリティ・権限」を参照してください。

- **アクセシビリティ権限**：最前面のアプリのウィンドウ階層を、ファイル選択パネル（NSOpenPanel）の判定に必要な範囲で読みます。保存ダイアログやアラートには反応せず、ウィンドウの内容や入力値は保存しません。
- **キー入力の合成とクリップボード**：パスの入力では「フォルダへ移動」（⌘⇧G）を開き、クリップボード経由でパスを貼り付けます。入力前のクリップボードの内容を退避し、入力後に元へ戻します。戻せなかった場合は、パレットまたはメニューバーで知らせます。機密の印（`org.nspasteboard.ConcealedType`）が付いた内容は読み出さずに手放し、入力後にクリップボードを空にします。入力の途中で別の内容がコピーされた場合は、その内容を残します。
- **ネットワーク**：通信するコードを持ちません。通信が無いことは `scripts/measure-network.sh` で計測しています（[非機能テストの計測結果](./docs/50_test/test-openpath-nfr-measurement.md)）。
- **子プロセス**：`ghq` が有効なときは `ghq root` と `ghq list -p` を実行し、初回起動の「試してみる」では `osascript` を実行します。どちらも利用者の Mac の中で完結します。
- **ローカルのデータ**：設定（`~/.config/openpath/config.toml`）、確定したパスの履歴（`~/Library/Application Support/openpath/history.json`）、ログ（`~/Library/Logs/openpath/`）を保存します。info 以上のログにはパスを書かず、パスは debug レベルでだけ記録します。
- **配布物**：Stable は Developer ID で署名し、Apple の公証を受けます。すべての Release に `SHA256SUMS` を添付します。署名と公証の認証情報は、Stable を作る job にだけ渡します。

報告を受け付ける問題の例は次のとおりです。

- ファイル選択パネル以外の場面や、利用者が確定していない場面で、他のアプリへキー入力やパスを送る
- info 以上のログ、通知、外部へ、パスや入力値が漏れる
- 退避したクリップボードの内容が、戻らずに残る、または別の場所へ渡る
- openpath がネットワーク通信を行う
- Release の成果物、Homebrew cask、GitHub Actions の workflow が改ざんされる、または secret が漏れる

次は対象外です。

- 同じ macOS ユーザーとして任意のコードを実行できる process（openpath の設定、履歴、ログを直接読み書きできます）
- アクセシビリティ権限を持つ別のアプリや、macOS 自体の脆弱性
- 利用者が debug ログやスクリーンショットを自分で公開した場合のパスの露出
- Preview や ad-hoc 署名のビルドが Gatekeeper の警告を出すこと

## What to expect

security の対応は best effort で、応答時間の SLA はありません。
maintainer は報告を確認し、影響と対象 version を評価します。
必要に応じて private advisory で修正を準備し、修正を含む Release を公開してから、報告者と合意した時期と credit で公表します。
悪用が進んでいる場合など、利用者の安全を優先すべきときは公表の時期を変えることがあります。

検証は、自分が所有する Mac とデータ、または許可を得た環境だけで行ってください。
