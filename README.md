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

### .app バンドルのビルドと署名

`swift build` の成果物は実行ファイル単体です。常用や配布には `scripts/` のスクリプトで `.app` バンドルを組み立てて署名します。どのスクリプトも Command Line Tools だけで動きます。

```bash
./scripts/build.sh        # リリースビルド → build/openpath.app（Universal 2）
./scripts/sign.sh         # 署名。OPENPATH_SIGN_IDENTITY が未設定なら ad-hoc 署名
open build/openpath.app   # Dock には出ず、メニューバーに常駐する
```

| スクリプト | 内容 | 環境変数 |
| --- | --- | --- |
| `build.sh [--arch universal\|arm64\|x86_64] [--version X.Y.Z]` | `swift build -c release` をアーキテクチャごとに実行して lipo で結合し、`build/openpath.app` を組み立てる | なし |
| `sign.sh` | Hardened Runtime と `Resources/openpath.entitlements` を付けて署名し、`codesign --verify --deep --strict` で検証する | `OPENPATH_SIGN_IDENTITY`（任意） |
| `notarize.sh` | zip にして `notarytool submit --wait` → `stapler staple` → `spctl -a -vv` を行い、staple 済みの `build/openpath-<version>.zip` を作る | `OPENPATH_NOTARY_PROFILE`（必須） |
| `cask.sh [--version X.Y.Z] [--zip PATH] [--output FILE]` | 配布用 zip の sha256 から Homebrew cask 定義を生成する（既定は標準出力） | なし |
| `release.sh [--version X.Y.Z]` | build → sign → notarize → cask を順に実行し、`build/openpath-<version>.zip` と `build/Casks/openpath.rb` を作る | 上の 2 つとも必須 |

`.app` から起動すると `Bundle.main.bundleURL` が `.app` を指すため、`swift run` では不安定な次の 2 点が安定します。

- メニューの「ログイン時に起動」: `SMAppService.mainApp` は `.app` を登録する仕組みのため、バンドル外（`swift run` 等）では項目を選べません。`.app` から起動すると使えます。
- アクセシビリティ権限（TCC）: `.app` として起動すると、権限は openpath 自身（bundle id とコード署名）に対して付与されます。ターミナルから `swift run` した場合は、ターミナルアプリ側の権限として扱われることがあります。
  - ad-hoc 署名では署名の要件（cdhash）が再ビルドのたびに変わります。再ビルド後は「システム設定 → プライバシーとセキュリティ → アクセシビリティ」で openpath をいったん削除して追加し直してください。Developer ID で署名すると要件が bundle id と Team ID になるため、更新しても権限はそのまま残ります。

補足:

- Universal 2: Command Line Tools だけの環境では `swift build --arch arm64 --arch x86_64` が XCBuild（Xcode 同梱）を要求して失敗します。そのため `build.sh` はアーキテクチャごとにビルドしてから lipo で結合します。
- バージョン: 正本は `Resources/Info.plist` の `CFBundleShortVersionString` で、スクリプトは書き換えません。上げるときは `Resources/Info.plist` と `Sources/OpenPathCore/AppInfo.swift` を一緒に更新してください（不一致はテストで検出されます）。`build.sh --version` と `release.sh` は、指定値や `vX.Y.Z` タグが Info.plist と一致しなければ止まります。
- `build.sh` は毎回リンクをやり直し、埋め込まれた Info.plist が `Resources/Info.plist` と一致するかを検証します。このため `swift package clean` は不要です。

### 初回起動の案内

初めて起動すると、アクセシビリティ権限の用途の説明 → システム設定での許可 → 「試してみる」の順に案内するウインドウが出ます（UX-001 §7）。

- 権限が既にあれば説明を飛ばし、「試してみる」から始まります。「試してみる」は `osascript` の `choose folder` でフォルダ選択のダイアログを出し、パレットが重なることを確かめられます（選んだフォルダは使いません）。
- 案内を終える（「試してみる」「閉じる」「あとで」）と `~/Library/Preferences/jp.tamat.openpath.plist` の `onboardingFinished` に記録し、次の起動からは出ません。メニューの「はじめに…」でいつでも開き直せます。
- 最初からやり直すには、openpath を終了してから `defaults delete jp.tamat.openpath onboardingFinished` を実行します。
- 設定ファイル `~/.config/openpath/config.toml` が無ければ、既定の内容で作ります（既存のファイルは上書きしません）。候補として走査するディレクトリ `roots` は、`ghq root` の結果を絶対パスに解決できればその root、できなければ（ghq が未インストール・実行に失敗した・結果が相対パスなど）ホーム（`~`）になります。ホームにした場合、`~/Desktop`・`~/Documents`・`~/Downloads` の中を初めて読むときに macOS がアクセスの許可を確認することがあります。

### ログ

- 出力先は `~/Library/Logs/openpath/openpath.log`（5 MiB を超えると `openpath.log.1` に退避）。統合ログ（Console.app、subsystem `jp.tamat.openpath`）にも出ます。
- 最小レベルは DEBUG ビルド（`swift run` 等）で debug、リリースビルド（`build.sh`）で info です。パス（注入したパスなど）は debug でだけ記録します（NFR-05）。
- QA などでリリースビルドの debug ログを出すには、openpath を終了してから次を実行し、起動し直します。注入したパス・使った方式（主方式 / 副方式）・各ステップの経過時間が残ります。確定前の移動先シートの入力欄の値と候補の選択は入力欄を AX で見つけられたとき、移動後のパネルの現在地（表示名）は自動確定しない注入の後に残ります（Issue #74）。

  ```bash
  defaults write jp.tamat.openpath logLevel debug
  ```

- debug ログはパスを含むため、確認が終わったら openpath を終了して既定に戻します。値は `debug` / `info` / `warning` / `error` で、不正な値なら既定のレベルのまま警告をログに残します。

  ```bash
  defaults delete jp.tamat.openpath logLevel
  ```

### 配布（Developer ID 署名・Notarization・Homebrew cask）

リリース担当者向けの手順です。Apple ID・パスワード・Team ID・証明書はスクリプトにもリポジトリにも書かず、keychain と環境変数で渡します。

```bash
# Developer ID Application 証明書を keychain に入れておく
security find-identity -v -p codesigning        # 証明書の名前か SHA-1 を確認
export OPENPATH_SIGN_IDENTITY="Developer ID Application: <名前> (<Team ID>)"

xcrun notarytool store-credentials <profile>    # Apple ID・Team ID・App 用パスワードを対話的に keychain へ保存
export OPENPATH_NOTARY_PROFILE=<profile>

./scripts/release.sh                            # HEAD の vX.Y.Z タグ（無ければ Info.plist）のバージョンで作る
```

できた `build/openpath-<version>.zip` を `gh release create v<version> build/openpath-<version>.zip` で GitHub Releases に添付し、`build/Casks/openpath.rb` を tap リポジトリの `Casks/openpath.rb` にコピーします。cask の URL は `https://github.com/TamaT-LLC/openpath/releases/download/v#{version}/openpath-#{version}.zip` を前提にしています。

## 予定している技術スタック

- Swift 6.0+ ツールチェーン / SwiftUI + AppKit
- 外部依存なし・ネットワーク通信なし
- 要求権限: アクセシビリティのみ
- 配布: Developer ID 署名 + Notarization、Homebrew cask

## ライセンス

MIT
