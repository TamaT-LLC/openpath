## 概要

<!-- 何を、なぜ変えたか。 -->

## 変更内容

-

## 関連 Issue

<!-- `Closes #123` または `Refs #123` を記載してください。 -->

## 検証結果

- [ ] `swift build` が警告なく通る
- [ ] `./scripts/test.sh`（Xcode 環境では `swift test`）が通る
- [ ] release workflow や `scripts/` のリリース処理を変えた場合は `python3 scripts/release_ci_test.py` が通る
- [ ] `.github/` を変えた場合は `python3 scripts/github_policy_test.py` と `python3 scripts/github_policy_check.py` が通る
- [ ] Homebrew cask（`scripts/cask.sh`）を変えた場合は `./scripts/cask_style.sh` が通る
- [ ] 実行できなかった検証は、理由と影響範囲を本文に記載した

## Privacy と security

- [ ] パス、ユーザー名、debug ログ、credential を含めていない
- [ ] 検知の対象、キー入力、クリップボード、ログに残す内容、保存するデータへの影響を確認した
- [ ] 新しい権限、子プロセス、ネットワーク通信を加える場合は、理由を本文に記載した

## 文書

- [ ] 挙動の変更に合わせて README と `docs/` の設計文書を更新した
- [ ] 利用者に見える変更を `docs/releases/unreleased.md` に追記した

## 手動シナリオ（アプリの挙動に関わる PR のみ）

<!--
検知・パレット・注入・メニュー・設定・権限・初回起動など、アプリの挙動が変わる PR で記入する。
ドキュメント・CI・テストだけの PR は「該当しない」にチェックして、残りは消してよい。
項目と ID は docs/50_test/test-openpath-manual-scenarios.md（PROJ-TST-002）。§14 の対応表で影響範囲の項目を選ぶ。
アクセシビリティ権限の無い環境で確認できなかった項目は「未確認」とし、オーナーに確認してほしい項目として残す。
-->

- [ ] 該当しない（アプリの挙動に影響しない）
- 実施環境: macOS / openpath（コミット）/ 対象アプリとバージョン
- スモークテスト `./scripts/smoke-open-panel.sh`: OK / NG / 前提不足 / 未確認

S-01〜S-13 のうち影響範囲のもの（影響しない行は `—`）:

| # | シナリオ | 結果（OK / NG / 未確認 / —） | 備考 |
| --- | --- | --- | --- |
| S-01 | 「開く」ダイアログ（TextEdit の ⌘O）で 300ms 以内にパレット |  |  |
| S-02 | Claude Desktop「フォルダを追加」でディレクトリのみ |  |  |
| S-03 | Claude Desktop で `fern` → Enter → パネルの Enter |  |  |
| S-04 | Cursor の Open Folder |  |  |
| S-05 | VS Code の Open… で Cmd+Enter |  |  |
| S-06 | Safari のファイルアップロード（`include_files = true`） |  |  |
| S-07 | 日本語ディレクトリへの移動 |  |  |
| S-08 | Esc → Ctrl+Shift+O で再表示 |  |  |
| S-09 | パレット表示中にパネルをキャンセル |  |  |
| S-10 | 注入後にクリップボードが戻る |  |  |
| S-11 | 保存ダイアログではパレットが出ない |  |  |
| S-12 | `disabled_apps` のアプリでは出ない |  |  |
| S-13 | 権限を外す → バッジ・検知停止 → 再付与で 5 秒以内に復帰 |  |  |

S-01〜S-13 以外に確かめた項目（PROJ-TST-002 の ID）:

| ID | 結果 | 備考 |
| --- | --- | --- |
|  |  |  |
