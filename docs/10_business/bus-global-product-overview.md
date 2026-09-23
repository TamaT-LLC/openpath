---
id: PROJ-BUS-001
layer: L1
feature: global
scope: global
status: Draft
upstream: []
downstream:
- PROJ-REQ-001
owner: TakehiroT
updated: 2026-09-23
---

# プロダクト概要（openpath / OSS 方針）

## ビジョン

macOS のファイル選択ダイアログ（NSOpenPanel）を「Finder で辿る」体験から「cdr のようにファジー検索して一発で飛ぶ」体験に置き換える。Claude Desktop・Cursor・VS Code・ブラウザなど、あらゆるアプリの「フォルダを開く」「ファイルを添付する」を同じ操作で完結させる。

## 課題

- 開発者は日常的に `~/repos/github.com/<org>/<repo>` のような深いパスを NSOpenPanel で開く必要があり、都度 Finder のツリーを辿るかパスを手打ちしている。
- ターミナルでは `cdr` / `zoxide` / `fzf` で解決済みの「最近使った場所に即座に飛ぶ」体験が、GUI アプリのダイアログには存在しない。
- 既存製品（Default Folder X 等）は有料・クローズドで、開発者向けの frecency 検索や ghq 連携といったカスタマイズが難しい。

## ミッション

1. **NSOpenPanel の体験をターミナル並みにする**
   - パネル出現を自動検知し、ファジー検索パレットを即座に重ねる
   - 選択したパスをパネルへ注入し、ユーザーは Enter だけで確定できる
2. **開発者のワークフローに寄り添う**
   - ghq root、frecency 履歴、任意のルートディレクトリを候補ソースにする
   - 設定はテキストファイル（TOML）で管理し、dotfiles に載せられる
3. **OSS として信頼できる小さなツールにする**
   - Swift 単体アプリ、外部サービス依存なし、ネットワーク不要
   - アクセシビリティ権限の用途を透明に説明する

## 位置づけと補助範囲

- 位置づけ: macOS メニューバー常駐の補助ツール。NSOpenPanel を置き換えるのではなく、その上に「操作レイヤー」を重ねる。
- 補助範囲: パネル検知、ファジー検索 UI、パスの注入（Cmd+Shift+G 経由 / AX 直接セット）、frecency 履歴管理、ghq / ルートディレクトリの走査。
- 非補助範囲: NSOpenPanel 自体の差し替え、サンドボックス外への権限昇格、ファイル内容の検索（Spotlight の代替）。

## 展開戦略（OSS 前提）

- Phase 1: MVP
  - 目的: 自分（TamaT）の日常業務で Claude Desktop / Cursor のフォルダ選択を置き換える
  - 成果: パネル検知、パレット UI、Cmd+Shift+G 注入、ghq root + 履歴の候補ソース
- Phase 2: 堅牢化
  - 目的: 日本語パス・多段シート・非サンドボックスアプリでも安定させる
  - 成果: AX 直接セット方式、アプリ別プロファイル、Homebrew cask 配布
- Phase 3: 拡張
  - 目的: コミュニティからの候補ソース拡張を受け入れる
  - 成果: 候補ソースのプラグイン境界、Raycast / Alfred からの外部呼び出し

## 成功指標

- パネル出現からパス確定までの操作が「ホットキーなし・タイプ数 5 文字以内・Enter 1 回」で完了する割合が 90% 以上
- 検知〜パレット表示のレイテンシが 300ms 以下
- 自社の Claude Desktop / Cursor のフォルダ選択が 100% openpath 経由になる（dogfooding）
