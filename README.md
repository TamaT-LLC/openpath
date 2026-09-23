# openpath

[![CI](https://github.com/TamaT-LLC/openpath/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/TamaT-LLC/openpath/actions/workflows/ci.yml)

macOS のファイル選択ダイアログ（NSOpenPanel）に、`cdr` / `fzf` 風のファジー検索パレットを重ねるメニューバー常駐アプリ。

Claude Desktop・Cursor・VS Code・ブラウザなど、どのアプリの「フォルダを開く」「ファイルを添付」でも、Finder のツリーを辿らずに **数文字タイプ → Enter** で目的のパスへ飛べます。

## 仕組み

1. アクセシビリティ API で最前面アプリの NSOpenPanel 出現を検知
2. パネルの上にフローティングパレットを表示（パネルのフォーカスは奪わない）
3. 履歴（frecency）・ghq root・任意のルートディレクトリから候補をファジー検索
4. 選んだパスを `⌘⇧G`（フォルダへ移動）経由でパネルに注入

NSOpenPanel 自体は置き換えません。Esc でパレットを閉じれば、いつもの Finder ダイアログがそのまま使えます。

## ステータス

Phase 1 実装中。SPM プロジェクトの雛形ができ、メニューバーに常駐するだけの最小アプリが起動します（パネル検知・パレット・注入は未実装）。設計ドキュメントは `docs/` を参照してください（[system-doc-agent](https://github.com/TamaT-LLC/system-doc-agent-cli) 形式）。

| Layer | ドキュメント |
| --- | --- |
| L1 ビジネス | `docs/10_business/bus-global-product-overview.md` |
| L1 要件 | `docs/20_requirements/req-openpath-baseline.md` |
| L2 UX | `docs/30_ux/ux-openpath-palette.md` |
| L3 アーキテクチャ | `docs/40_arch_design/arch-openpath-app.md` |
| L4 詳細設計 | `docs/40_arch_design/design-openpath-panel-injection.md`, `docs/40_arch_design/design-openpath-index-frecency.md` |
| L5 テスト | `docs/50_test/test-openpath-plan.md` |
| インデックス | `docs/00_index/index.md` |

## 開発

### 必要環境

- macOS 14 (Sonoma) 以降
- Swift 6.0 以降のツールチェーン。Xcode は不要で、Command Line Tools（`xcode-select --install`）だけでビルド・テストできます。

### ビルド・テスト・実行

```bash
swift build          # ビルド
./scripts/test.sh    # ユニットテスト（Swift Testing）。Xcode 環境なら `swift test` でも可
swift run openpath   # 起動。Dock には出ず、メニューバーにアイコンが出る（メニューの「終了」で終了）
```

- Command Line Tools のみの環境では、素の `swift test` は `no such module 'Testing'` で失敗します。SwiftPM が CLT 同梱の Swift Testing を見つけられないためで、`scripts/test.sh` が必要なフラグを補ってから `swift test` を実行します。引数はそのまま `swift test` に渡せます（例: `./scripts/test.sh --filter AppInfo`）。
- `Resources/Info.plist` は実行ファイルに埋め込まれます。SwiftPM は Info.plist の変更を検知しないため、編集後は `swift package clean` してからビルドしてください。

## 予定している技術スタック

- Swift 6.0+ ツールチェーン / SwiftUI + AppKit
- 外部依存なし・ネットワーク通信なし
- 要求権限: アクセシビリティのみ
- 配布: Developer ID 署名 + Notarization、Homebrew cask

## ライセンス

MIT
