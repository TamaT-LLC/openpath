---
id: PROJ-TST-001
layer: L5
feature: openpath
scope: global
status: Draft
upstream:
- PROJ-ARCH-001
- PROJ-DSN-001
- PROJ-DSN-002
downstream: []
owner: TakehiroT
updated: 2026-09-23
---

# テスト計画: openpath

## 1. 方針

- `OpenPathCore`（ファジーマッチ、frecency、設定パース、状態機械）は Swift Testing によるユニットテストで網羅する。XCTest と違い Xcode を必要とせず Command Line Tools だけで実行できるため、Swift Testing を採用する。
- `OpenPathMac`（AX 観測、注入）は自動化が困難なため、手動シナリオテストと、Finder の「開く」ダイアログを使ったスモークスクリプト（AppleScript で `choose folder` を出す）で確認する。
- CI（GitHub Actions, macOS runner）ではユニットテストと `swift build` のみ実行。AX を要するテストはローカル限定。

## 2. ユニットテスト（OpenPathCoreTests）

### 2.1 FuzzyMatcher

| ケース | 入力 | 期待 |
| --- | --- | --- |
| 先頭一致が最上位 | query `fern`, 候補 `fern`, `fernet-config`, `my-fern` | `fern` > `fernet-config` > `my-fern` |
| 区切り直後ボーナス | query `sda`, 候補 `system-doc-agent`, `sdasd` | `system-doc-agent` が上位（s/d/a が `-` 直後） |
| 日本語 NFC/NFD 同一視 | query `資料`, 候補（NFD で保存された `資料`） | マッチする |
| かな同一視 | query `しりょう`, 候補 `シリョウ` | マッチする |
| 幅同一視 | query `ａｂｃ`, 候補 `abc` | マッチする |
| 非マッチ | query `xyz`, 候補 `fern` | nil |
| positions | query `fn`, 候補 `fern` | positions == [0, 3] |

### 2.2 Frecency

| ケース | 期待 |
| --- | --- |
| 1 時間以内は decay 4.0 | count 1, lastUsed = now - 30min → score 4.0 |
| 1 週間超は decay 0.25 | count 4, lastUsed = now - 10d → score 1.0 |
| 確定で count++ と lastUsed 更新 | `record(path)` 後に反映 |
| 90 日未使用かつ不存在で削除 | 保存時に消える |
| 上限 2,000 件 | 2,001 件目追加で最下位が消える |

### 2.3 ConfigStore

| ケース | 期待 |
| --- | --- |
| 既定値生成 | ファイルなし → roots に ghq root（モック）を含む TOML が生成される |
| 各キーのパース | 上記サンプル TOML が `Config` に一致 |
| 不正 TOML | 直前の設定が維持され、`lastError` が非 nil |
| `~` 展開 | `roots = ["~/repos"]` → 絶対パス |
| ホットキー文字列 | `"ctrl+shift+o"` → `(keyCode: kVK_ANSI_O, modifiers: [.control, .shift])` |

### 2.4 CandidateIndex

| ケース | 期待 |
| --- | --- |
| ソース統合 | 同一パスが history と ghq にある → 1 件、source == .history |
| ディレクトリのみ要求 | `query(directoriesOnly: true)` にファイルが含まれない |
| 空クエリ | frecency 降順 8 件 |
| ignore 適用 | `node_modules` 配下が走査結果に含まれない |
| アトミック差し替え | 走査中に query しても旧結果が返り、クラッシュしない |

### 2.5 AppCoordinator（状態機械）

| ケース | 期待 |
| --- | --- |
| Idle → PanelShown | `panelAppeared` でパレット表示が呼ばれる |
| PanelShown → Injecting → Idle | `confirm(path)` で注入が呼ばれ、成功後 Idle |
| 注入タイムアウト | 1.5 秒で Idle に戻り、エラーがパレットに渡る |
| パネル消滅 | PanelShown / Injecting どちらでも Idle に戻る |
| Esc | PanelShown のままパレットのみ非表示、ホットキーで再表示 |

## 3. 手動シナリオテスト（Phase 1 受け入れ）

前提: アクセシビリティ権限付与済み、`roots = ["~/repos"]`, `ghq.enabled = true`。

| # | アプリ | 手順 | 期待 |
| --- | --- | --- | --- |
| S-01 | Finder | Cmd+O で「開く」 | 300ms 以内にパレットが右上に出る |
| S-02 | Claude Desktop | 「フォルダを追加」 | パレットが出て、ディレクトリのみ候補に出る |
| S-03 | Claude Desktop | `fern` と打って Enter | パネルが該当リポへ移動、パレットが閉じる。Enter で追加できる |
| S-04 | Cursor | File > Open Folder → `open` Enter | 同上 |
| S-05 | VS Code | File > Open… → Cmd+Enter | 移動 + 自動で開く |
| S-06 | Safari | ファイルアップロード input | パレットが出て、ファイルも候補に出る（include_files=true 時） |
| S-07 | 任意 | 日本語ディレクトリ `~/Documents/資料` を選択 | 正しく移動する |
| S-08 | 任意 | Esc → Ctrl+Shift+O | パレットが消え、再表示される |
| S-09 | 任意 | パレット表示中にパネルをキャンセル | パレットが消え、アプリは落ちない |
| S-10 | 任意 | ペーストボードにテキストを入れてから注入 | 注入後にペーストボードが元に戻る |
| S-11 | TextEdit | Cmd+Shift+S（保存ダイアログ） | パレットが出ない |
| S-12 | 任意 | `disabled_apps` に対象アプリを追加 | そのアプリではパレットが出ない |
| S-13 | 任意 | 権限を外す | メニューバーにバッジ、検知停止。再付与で 5 秒以内に復帰 |

## 4. スモークスクリプト

```bash
# scripts/smoke-open-panel.sh
osascript -e 'tell application "Finder" to activate' \
          -e 'choose folder with prompt "openpath smoke"' &
sleep 1
# ここで openpath のログに "panel detected" が出ることを確認
grep -q "panel detected" ~/Library/Logs/openpath/openpath.log && echo OK || echo NG
```

## 5. 非機能テスト

| 項目 | 方法 | 合格基準 |
| --- | --- | --- |
| アイドル CPU | Activity Monitor で 10 分計測 | 平均 0.1% 未満 |
| メモリ | 候補 20,000 件を読み込み | 50MB 以下 |
| 検知レイテンシ | ログのタイムスタンプ（panel created → palette shown） | p95 300ms 以下 |
| ネットワーク | Little Snitch / `nettop` で監視 | 通信ゼロ |
| Notarization | `spctl -a -vv openpath.app` | accepted |

## 6. 完了条件

- 2 章のユニットテストがすべて通る（CI）。
- 3 章の S-01〜S-13 がすべて期待どおり（ローカル、チェックリストを PR に添付）。
- 5 章の合格基準を満たす。
