# 未リリース

次の Stable `v0.1.0` に入る変更を記録する。
`v0.1.0` は openpath の最初のリリースで、Preview `preview-v0.1.0-1` を実機で確かめてから公開する。
このファイルを追加しただけでは公開にならない。
Stable の tag、GitHub Release、添付の `SHA256SUMS` がそろったときに、正式版として扱う。
Stable を公開するときは、このファイルを `v0.1.0.md` に改め、新しい `unreleased.md` を作る。

## 最初のリリースに含める機能

- ファイル選択パネル（NSOpenPanel）の出現を検知し、ファジー検索のパレットを重ねる。保存ダイアログと `disabled_apps` のアプリでは出さない。
- 候補は、確定したパスの履歴（frecency）、ghq のリポジトリ、`roots` の配下から作る。候補は 5 分ごとと、メニューの「候補を再構築」で作り直す。
- 選んだパスを「フォルダへ移動」（⌘⇧G）とクリップボード経由の貼り付けでパネルに入力する。入力欄をアクセシビリティ API で直接書き換える副方式を持ち、入力後はクリップボードを元に戻す。
- Enter は移動までで止め、Cmd+Enter または `auto_confirm = true` のときは「開く」まで押す。
- メニューバーから、有効と無効の切り替え、候補の再構築、設定ファイルを開く操作、履歴のクリア、ログイン時の起動を操作できる。
- 設定ファイル `~/.config/openpath/config.toml` を保存すると自動で読み込み直す。初回は、ghq の root、ghq が無ければホーム（`~`）を `roots` に書いて生成する。
- 初回起動で、アクセシビリティ権限の用途の説明、許可の案内、「試してみる」を順に表示する。
- ログを `~/Library/Logs/openpath/` に出力する。パスは debug レベルでだけ記録する。

## 動作環境と配布

- macOS 14 以降。ZIP は Apple Silicon と Intel の両方を含む Universal 形式。
- Stable は Developer ID で署名し、Apple の公証を受ける。Homebrew cask（`openpath.rb`）を添付する。
- Preview は ad-hoc 署名で公証しない。評価用で、サポート対象外。
- 画面の表示は日本語だけ。

## 既知の制約

- アクセシビリティ API とキー入力に関わる挙動は CI で確かめられないため、[手動シナリオテスト](../50_test/test-openpath-manual-scenarios.md) で確認する。
- `roots` に保護フォルダを含むときの macOS の確認の挙動は、実機で確かめる途中である（手動シナリオの ONB-20）。
- 自動更新の機能は無い。新しい version は GitHub Releases または Homebrew から入れ直す。
- テンキーの Enter は、Return の代わりとしては扱わない。
