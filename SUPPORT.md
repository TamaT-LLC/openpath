# Support

openpath は best effort で保守しています。
このリポジトリを通した応答時間や解決時間の約束はなく、SLA もありません。

## サポート対象の version

サポート対象は、GitHub Releases で公開した最新の Stable（`vX.Y.Z`）です。
最初の Stable `v0.1.0` を 2026-10-04 に公開しました。
Preview（`preview-vX.Y.Z-N`）は評価用のビルドで、サポート対象外です。
`main` からのビルドは開発用で、修正は `main` に先に入れます。

openpath の動作環境は macOS 14 以降で、Apple Silicon と Intel の両方に対応します。
画面の表示は日本語だけです。

## どこで聞くか

- サポート対象の version で再現する不具合は、Bug report のフォームを使ってください。
- 範囲を絞った機能の提案は、Feature request のフォームを使ってください。
- 使い方は、まず [README](./README.md)、[リリースノート](./docs/releases/)、既存の Issue を確認してください。文書どおりに動かない場合は Bug report、新しい動作が必要な場合は Feature request を使ってください。
- 脆弱性の可能性がある内容は、[SECURITY.md](./SECURITY.md) の非公開の窓口から報告してください。公開 Issue には書かないでください。
- 行動規範やモデレーションに関する相談は、[CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) に従ってください。

## 報告に含める情報

- openpath の version（Release の tag、またはソースからビルドした commit）と入手方法
- macOS の version と、Apple Silicon か Intel か
- ファイル選択パネルを開いたアプリと、その version
- 再現手順、期待した動作、実際の動作
- 関係する手動シナリオの ID（[手動シナリオテスト](./docs/50_test/test-openpath-manual-scenarios.md)。分かる場合だけ）
- 必要に応じて、パスを伏せた debug ログ

debug ログは、openpath を終了してから次を実行し、起動し直して問題を再現すると `~/Library/Logs/openpath/openpath.log` に残ります。

```bash
defaults write jp.tamat.openpath logLevel debug
```

debug ログには、注入したパスなどが平文で残ります。
貼り付ける前に、再現に不要なパスとユーザー名を伏せてください。
確認が終わったら、openpath を終了して既定のレベルに戻してください。

```bash
defaults delete jp.tamat.openpath logLevel
```

## triage の方針

maintainer は余力に応じて triage します。
重複、長期間の無応答、範囲外、安全でない内容、嫌がらせ、spam の Issue には、ラベル付け、移動、close、lock を行うことがあります。
期限による自動 close はなく、無応答の期間は、再現性、影響、maintainer の余力とあわせて判断します。
このリポジトリの Issue は、商用サポートやインシデント対応の代わりにはなりません。
