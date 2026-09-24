---
id: PROJ-REQ-001
layer: L1
feature: openpath
scope: global
status: Draft
upstream:
- PROJ-BUS-001
downstream:
- PROJ-UX-001
- PROJ-ARCH-001
owner: TakehiroT
updated: 2026-09-24
---

# openpath 要件（L1 / Draft）

プロダクト概要（PROJ-BUS-001）を実現するための最低限の要求を定義する。

## 1. スコープ

- 対象: macOS 14 (Sonoma) 以降。Apple Silicon / Intel 両対応。
- 提供物: メニューバー常駐アプリ（.app）、設定ファイル `~/.config/openpath/config.toml`、履歴ストア。
- 非スコープ: Windows / Linux、NSSavePanel（保存ダイアログ）の Phase 1 対応、ファイル内容検索。

## 2. 機能要件

### 2.1 パネル検知（FR-DETECT）

- FR-DETECT-01: 最前面アプリが NSOpenPanel（AXSubrole = AXDialog / AXSheet、かつ「開く」「Open」「選択」「Choose」等の確定ボタンを持つ）を表示したことを、ユーザー操作なしで検知できること。
- FR-DETECT-02: サンドボックスアプリ（`com.apple.appkit.xpc.openAndSavePanelService` 経由で描画されるパネル）も検知できること。
- FR-DETECT-03: 検知からパレット表示までのレイテンシが 300ms 以下であること。
- FR-DETECT-04: アプリ別に「有効 / 無効」を設定でき、既定は全アプリ有効であること。
- FR-DETECT-05: パネルが閉じられたら、パレットも自動で閉じること。

### 2.2 検索パレット（FR-PALETTE）

- FR-PALETTE-01: パネルの上にフローティングパレットを表示し、パネル側のフォーカスを奪わないこと（`.nonactivatingPanel`）。
- FR-PALETTE-02: 入力文字列に対してファジーマッチした候補を、frecency スコア順に表示すること。
- FR-PALETTE-03: 候補は「表示名」「フルパス（短縮表記）」「最終使用日時」を持つこと。
- FR-PALETTE-04: ↑↓ / Ctrl+N / Ctrl+P で選択、Enter で確定、Esc でパレットのみ閉じる（パネルは残す）こと。
- FR-PALETTE-05: パレットを閉じた後、ホットキー（既定: Ctrl+Shift+O）で再表示できること。
- FR-PALETTE-06: 日本語を含むパス・ファイル名を正しく検索・表示できること。
- FR-PALETTE-07: 候補ソースに無い場所でも、存在する絶対パスまたは `~/` から始まるパスを検索フィールドに入力すれば、その場所を移動先として選べること。末尾が `/` の入力は配下を絞り込む検索語として扱い、その場所自体は移動先として選べない。

### 2.3 候補ソース（FR-SOURCE）

- FR-SOURCE-01: 履歴ストア（過去に openpath で確定したパス）を候補ソースとして持つこと。
- FR-SOURCE-02: 設定ファイルで指定したルートディレクトリ配下を、指定した深さ（既定 2）まで走査し候補にすること。
- FR-SOURCE-03: `ghq root` が存在する場合、`ghq list -p` の結果を候補にすること（ghq 未インストール時はスキップ）。
- FR-SOURCE-04: 候補ソースは起動時と一定間隔（既定 5 分）で非同期に再構築され、パレット表示をブロックしないこと。
- FR-SOURCE-05: 設定でファイル / ディレクトリのどちらを候補に含めるか選べること。パネルが「フォルダ選択モード」(canChooseDirectories のみ) の場合はディレクトリのみを表示すること。

### 2.4 パス注入（FR-INJECT）

- FR-INJECT-01: 確定したパスを NSOpenPanel に渡し、パネルがそのパスへ移動した状態にすること。
- FR-INJECT-02: 注入方式は「Cmd+Shift+G シート経由（ペーストボード + Cmd+V）」を基本とし、「AX 経由でテキストフィールドに直接セット」を代替手段として持つこと。
- FR-INJECT-03: 注入後に自動確定（「開く」ボタン押下）するかどうかを設定で選べること。既定は自動確定しない（ユーザーが Enter で確定）。
- FR-INJECT-04: 注入に使ったペーストボードの内容は、注入完了後に元の内容へ復元すること。
- FR-INJECT-05: 注入失敗（シートが出ない、フィールドが見つからない）を検知し、パレットにエラーを表示すること。

### 2.5 履歴・frecency（FR-HISTORY）

- FR-HISTORY-01: 確定したパスごとに「使用回数」「最終使用日時」を記録すること。
- FR-HISTORY-02: スコアは `count × 時間減衰(最終使用からの経過時間)` を基本とし、実装詳細は L4 で定義する。
- FR-HISTORY-03: 存在しなくなったパスは表示時に除外し、一定期間後に履歴から削除すること。
- FR-HISTORY-04: 履歴は `~/Library/Application Support/openpath/history.json` に保存すること。

### 2.6 設定（FR-CONFIG）

- FR-CONFIG-01: 設定は TOML ファイルで管理し、変更をファイル監視で即時反映すること。
- FR-CONFIG-02: メニューバーから「設定ファイルを開く」「候補を再構築」「終了」ができること。
- FR-CONFIG-03: ログイン時自動起動を設定できること（SMAppService）。

## 3. 非機能要件

- NFR-01: ネットワーク通信を一切行わないこと。
- NFR-02: アクセシビリティ権限のみを要求し、Full Disk Access は要求しないこと。
  - 例外: `roots` にホーム（`~`）など macOS の保護フォルダ（デスクトップ・書類・ダウンロード）を含む場所、または保護フォルダの中を指定した場合（ghq の root が取れないときの既定 `roots = ["~"]` を含む）は、候補の走査で初めてその中を読むときに、保護フォルダへのアクセス確認が出る。確認には Info.plist の用途の説明で理由を示す。拒否しても動作は継続し、そのフォルダの中身が候補に入らないだけとする（2026-09-24 オーナー判断）。
- NFR-03: アイドル時の CPU 使用率 0.1% 未満、常駐メモリ 50MB 以下を目標とする。
- NFR-04: Developer ID 署名 + Notarization を行い、Homebrew cask で配布できること。
- NFR-05: ログは `~/Library/Logs/openpath/` に出力し、パスの内容はデバッグレベルでのみ記録すること。

## 4. 制約・前提

- NSOpenPanel の実装差し替え（SIMBL / dylib injection）は SIP と署名制約により行わない。
- アクセシビリティ権限が未付与の場合は、パネル検知と注入は機能せず、メニューバーから権限付与を案内する。
- 対応アプリの検証対象（Phase 1）: Claude Desktop、Cursor、VS Code、Safari、Chrome、Finder（「開く」ダイアログ）。

## 5. 受け入れ基準（Phase 1 完了）

- Claude Desktop の「フォルダを追加」で、パネル出現後にタイプ → Enter → Enter でリポジトリを開ける。
- Cursor の「Open Folder」で同様に動作する。
- 日本語を含むパスで注入が成功する。
- パネルを Esc で閉じてもアプリが落ちない。
