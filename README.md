# openpath

macOS のファイル選択ダイアログ（NSOpenPanel）に、`cdr` / `fzf` 風のファジー検索パレットを重ねるメニューバー常駐アプリ。

Claude Desktop・Cursor・VS Code・ブラウザなど、どのアプリの「フォルダを開く」「ファイルを添付」でも、Finder のツリーを辿らずに **数文字タイプ → Enter** で目的のパスへ飛べます。

## 仕組み

1. アクセシビリティ API で最前面アプリの NSOpenPanel 出現を検知
2. パネルの上にフローティングパレットを表示（パネルのフォーカスは奪わない）
3. 履歴（frecency）・ghq root・任意のルートディレクトリから候補をファジー検索
4. 選んだパスを `⌘⇧G`（フォルダへ移動）経由でパネルに注入

NSOpenPanel 自体は置き換えません。Esc でパレットを閉じれば、いつもの Finder ダイアログがそのまま使えます。

## ステータス

設計フェーズ。実装は未着手です。設計ドキュメントは `docs/` を参照してください（[system-doc-agent](https://github.com/TamaT-LLC/system-doc-agent-cli) 形式）。

| Layer | ドキュメント |
| --- | --- |
| L1 ビジネス | `docs/10_business/bus-global-product-overview.md` |
| L1 要件 | `docs/20_requirements/req-openpath-baseline.md` |
| L2 UX | `docs/30_ux/ux-openpath-palette.md` |
| L3 アーキテクチャ | `docs/40_arch_design/arch-openpath-app.md` |
| L4 詳細設計 | `docs/40_arch_design/design-openpath-panel-injection.md`, `docs/40_arch_design/design-openpath-index-frecency.md` |
| L5 テスト | `docs/50_test/test-openpath-plan.md` |
| インデックス | `docs/00_index/index.md` |

## 予定している技術スタック

- Swift 5.10+ / SwiftUI + AppKit
- 外部依存なし・ネットワーク通信なし
- 要求権限: アクセシビリティのみ
- 配布: Developer ID 署名 + Notarization、Homebrew cask

## ライセンス

MIT
