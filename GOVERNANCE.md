# Governance

## 範囲と権限

openpath は、TamaT-LLC が管理する open source project です。
対象は、macOS のファイル選択パネルにファジー検索のパレットを重ね、選んだパスへ移動させるメニューバー常駐アプリです。
外部サービスに依存せず、ネットワーク通信を行わず、求める権限をアクセシビリティに限ることを project の前提にします（[プロダクト概要](./docs/10_business/bus-global-product-overview.md)、[要件](./docs/20_requirements/req-openpath-baseline.md) の NFR-01、NFR-02）。

TamaT-LLC の organization owner は、法的な権限、リポジトリの公開範囲、役割の割り当て、リリースの最終判断に責任を持ちます。
organization owner が割り当てた maintainer は、ロードマップ、triage、review、security、リリース、サポート、モデレーションを担います。
リポジトリへのアクセス権だけでは project の権限になりません。
maintainer は、割り当てられた役割と権限の範囲で行動します。

## 意思決定と変更

通常の変更は、review を経た Pull Request で決めます。
maintainer は、利用者への影響、正しさ、security、互換性、保守性、project の余力をもとに合意を探します。
合意に至らない場合は、担当の maintainer が判断と理由を Pull Request に記録します。
アーキテクチャ、security の境界、リリース、governance を変える場合は、`docs/` の設計文書に判断を記録し、作者以外の maintainer が review します。

作者は自分の変更を承認しません。
必須 CI の成功と、review の会話の解決が merge の条件です。
`@TakehiroT` には、緊急時に code owner の review だけを省略できる Pull Request 限定の bypass を割り当てます。
この bypass は、必須 CI、`main` の履歴保護、version tag の保護を省略しません。
これらの設定の正本は [.github/settings-desired-v1.json](./.github/settings-desired-v1.json) です。
実際の設定との差分は、管理者の権限で `python3 scripts/github_settings_drift.py` を実行すると一覧できます。
このスクリプトは GitHub API の読み取りだけを行い、設定を変更しません。

Issue はロードマップの参考にしますが、実装の約束にはなりません。
maintainer は、範囲、リスク、互換性、余力をもとに作業の優先度を決め、見送ることもあります。
project の方向に関わる判断は、個人の好みではなく、Issue、Pull Request、リリースノート、設計文書に記録します。

## maintainer の任命と退任

organization owner は、継続的で建設的な貢献があり、project の security、review、行動規範の方針を適用できる人を maintainer に任命します。
任命では、役割、範囲、必要最小限のアクセス権を記録します。
アクセス権と役割は、maintainer が活動を止めたとき、担当が変わったとき、離れたときに見直します。

maintainer はいつでも退任できます。
organization owner は、長期の不在、信頼の喪失、方針への違反、未解決の利益相反、security 上のリスクを理由に、maintainer の権限を制限または解除できます。
解除するときはアクセス権を速やかに取り消し、引き継ぎの記録を残します。

`CODEOWNERS` に載せるのは、organization owner が TamaT-LLC の maintainer であり、リポジトリへのアクセス権を持つと確認したアカウントだけです。
現在の code owner は `@TakehiroT` と `@Fuelda` です。
アクセス権や役割を変える場合は、同じ変更で `CODEOWNERS` を更新します。

## リリースと保守

リリースは、review を経て `main` に入った commit から作ります。
GitHub Actions の `Release macOS` は、Smoke、Preview、Stable の 3 つの経路で配布物を作ります。
Stable は、同じ version の Preview を実機で確かめた後に、Developer ID 署名と Apple の公証を経て公開します。
手順と失敗時の復旧は [リリース運用](./docs/40_arch_design/guide-release-distribution.md) に従います。

公開した tag と Release の成果物は、差し替えも削除もしません。
修正が必要な場合は、新しい Preview 番号または新しい Stable の version で公開します。
サポート対象は最新の Stable だけで、保守用の branch は持ちません。
現在は公開済みの Stable が無く、最初の Stable は `v0.1.0` の予定です。

リリースのサポートは best effort で、SLA はありません。
security の修正は [SECURITY.md](./SECURITY.md)、その他のサポートは [SUPPORT.md](./SUPPORT.md) に従います。

## モデレーション、利益相反、異議申し立て

maintainer は、重複、範囲外、安全上の問題、spam、嫌がらせ、行動規範の違反を理由に、Issue や Pull Request へのラベル付け、close、移動、編集、非表示、lock を行えます。
通常の対応は、安全な範囲で理由を公開します。
非公開の証拠と対応の記録は、関係者だけで扱います。

利益相反がある maintainer は、review や対応の前に申し出て、判断から外れます。
技術的な判断には、新しい根拠を添えて、元の Issue または Pull Request で異議を申し立てられます。
行動規範と非公開の governance に関する異議は、[CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) の手順に従います。
役割、法務、公開範囲、project の範囲に関する最終判断は、TamaT-LLC の organization owner が行います。

貢献の手順は [CONTRIBUTING.md](./CONTRIBUTING.md)、参加者の行動は [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) に従います。
