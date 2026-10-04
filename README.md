# openpath

日本語 | [English](README.en.md)

[![CI](https://github.com/TamaT-LLC/openpath/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/TamaT-LLC/openpath/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

openpath は、macOS のファイル選択ダイアログ（NSOpenPanel）に、`cdr` や `fzf` のようなファジー検索のパレットを重ねるメニューバー常駐アプリです。
Claude Desktop、Cursor、VS Code、ブラウザなど、どのアプリの「フォルダを開く」や「ファイルを添付」でも、Finder のツリーを辿らずに、数文字を入力して Enter を押すだけで目的の場所へ移動できます。

最初の Stable [`v0.1.0`](https://github.com/TamaT-LLC/openpath/releases/tag/v0.1.0) を、2026-10-04 に GitHub Releases で公開しました。
[インストール](#インストール) の手順で、ZIP から入れて使えます。
[ソースからビルド](#ソースからビルドする) して使うこともできます。
求める権限はアクセシビリティだけで、ネットワーク通信は行いません。

## 目的別の案内

| 目的 | 読む場所 |
| --- | --- |
| 何ができるかを知る | [特徴](#特徴)、[仕組み](#仕組み) |
| インストールする | [インストール](#インストール) |
| 操作を覚える | [使い方](#使い方) |
| 候補の範囲やホットキーを変える | [設定](#設定) |
| 権限とデータの扱いを確認する | [権限](#権限)、[プライバシー](#プライバシー) |
| 動かないときに調べる | [トラブルシュート](#トラブルシュート) |
| 開発に参加する | [開発](#開発)、[コントリビューション](#コントリビューション) |
| リリースの手順を確認する | [リリース](#リリース) |

## 特徴

- **開くだけで出る**：ファイル選択パネルが開くと、パレットが自動で重なります。ホットキー（既定は Ctrl+Shift+O）は、閉じたパレットを出し直すときだけ使います。
- **ターミナルと同じ指の動き**：↑↓ と Ctrl+N / Ctrl+P で選び、Enter で移動し、Tab で下のディレクトリへ絞り込みます。
- **よく使う場所が上に来る**：確定したパスを使用回数と最終使用日時（frecency）で並べます。[ghq](https://github.com/x-motemen/ghq) のリポジトリと、設定した `roots` の配下も候補にします。
- **パネルを置き換えない**：Esc でパレットを閉じれば、いつものダイアログをそのまま使えます。
- **確定は利用者が行う**：既定では移動までで止まり、最後の「開く」は利用者が押します。Cmd+Enter なら、移動してそのまま開きます。
- **日本語のパスを扱える**：パスはクリップボード経由で貼り付けるため、日本語のフォルダ名でも入力が崩れません。クリップボードの扱いは [プライバシー](#プライバシー) を参照してください。

## 仕組み

1. アクセシビリティ API で、最前面のアプリにファイル選択パネルが出たことを検知します。保存ダイアログには反応しません。
2. パネルのフォーカスを奪わずに、パネルの右上へパレットを重ねます。
3. 履歴、ghq、`roots` から作った候補をファジー検索します。
4. 選んだパスを「フォルダへ移動」（⌘⇧G）でパネルに入力します。

設計の詳細は [ドキュメントインデックス](docs/00_index/index.md) から辿れます。

## インストール

動作環境は macOS 14 (Sonoma) 以降で、Apple Silicon と Intel の両方に対応します。
画面の表示は日本語だけです。

### GitHub Releases の ZIP

配布物は [GitHub Releases](https://github.com/TamaT-LLC/openpath/releases) で公開しています。
最新の Stable は [v0.1.0](https://github.com/TamaT-LLC/openpath/releases/tag/v0.1.0) で、`openpath-0.1.0.zip`、`SHA256SUMS`、Homebrew cask の `openpath.rb` を添付しています。
Preview の `preview-v0.1.0-1` と `preview-v0.1.0-2` は評価用の prerelease で、サポート対象外です。
通常の利用には Stable を使ってください。

| 種類 | tag | 署名と公証 | 用途 |
| --- | --- | --- | --- |
| Stable | `vX.Y.Z` | Developer ID 署名、Apple の公証 | 通常の利用 |
| Preview | `preview-vX.Y.Z-N` | ad-hoc 署名、公証なし | 公開前の評価 |

ZIP は Apple Silicon と Intel の両方を含む Universal 形式です。
Release の添付ファイルをすべて同じディレクトリに保存し、チェックサムを確かめてから ZIP を展開します。

```bash
shasum -a 256 --check SHA256SUMS
```

展開した `openpath.app` を「アプリケーション」フォルダへ移して起動します。
初回の起動で出る案内に従い、「システム設定 > プライバシーとセキュリティ > アクセシビリティ」で openpath を許可してください。
許可するまでは、ファイル選択パネルの検知が止まります（[権限](#権限)）。

Preview は Apple の公証を受けていないため、初回の起動で Gatekeeper に止められます。
評価のために開く場合は、システム設定の「プライバシーとセキュリティ」から許可してください。

### Homebrew cask

Stable には、その ZIP に対応する Homebrew cask（`openpath.rb`）を添付しています。
Homebrew tap からのインストールは、現時点では使えません。
ZIP かソースからのビルドで入れてください。

### ソースからビルドする

Command Line Tools（`xcode-select --install`）と Swift 6.0 以降のツールチェーンでビルドできます。
Xcode は不要です。

```bash
git clone https://github.com/TamaT-LLC/openpath.git
cd openpath
./scripts/build.sh        # build/openpath.app（Universal 2）を組み立てる
./scripts/sign.sh         # OPENPATH_SIGN_IDENTITY が未設定なら ad-hoc 署名
open build/openpath.app   # Dock には出ず、メニューバーに常駐する
```

ad-hoc 署名の `.app` は、再ビルドのたびにアクセシビリティ権限の対象が変わります。
再ビルドした後は「システム設定 > プライバシーとセキュリティ > アクセシビリティ」で openpath をいったん削除し、追加し直してください。
Developer ID で署名した `.app` は、更新しても権限がそのまま残ります。

## 使い方

### 初回起動

初めて起動すると、アクセシビリティ権限の用途の説明、システム設定での許可、「試してみる」の順に案内するウインドウが出ます。
「試してみる」はフォルダ選択のダイアログを開き、パレットが重なることを確かめられます（選んだフォルダは使いません）。
案内を終えると次の起動からは出ず、メニューの「はじめに…」でいつでも開き直せます。

起動したときに設定ファイル `~/.config/openpath/config.toml` が無ければ、既定の内容で作ります（[設定](#設定)）。

### パレットの操作

| キー | 動作 |
| --- | --- |
| 文字を入力 | 候補をファジー検索する。日本語入力の変換中は絞り込みを保留する |
| ↑ / ↓、Ctrl+P / Ctrl+N | 候補を選ぶ |
| Enter | 選んだ候補へパネルを移動する。`auto_confirm = true` なら「開く」まで押す |
| Cmd+Enter | 選んだ候補へ移動し、そのまま「開く」を押す |
| Tab | 選んだ候補のパスを検索欄に展開し、下のディレクトリを絞り込む |
| Cmd+Z | Tab による展開を取り消す |
| Esc | パレットを閉じる。パネルはそのまま使える |
| Ctrl+Shift+O | 閉じたパレットを出し直す（[設定](#設定) で変えられる） |

`/` または `~/` で始まるパスを入力すると、そのパスが存在する場合は候補の先頭に出ます。
Enter でそのまま移動できます。

### メニューバー

メニューバーのアイコンから、次の操作ができます。

- 「有効」：パネルの検知とホットキーを止める、または再開する。状態は次の起動にも引き継ぐ。
- 「候補を再構築」：`roots` と ghq を走査し直す。走査は 5 分ごとにも行う。
- 「設定ファイルを開く…」（⌘,）：`config.toml` を開く。
- 「履歴をクリア…」：確定したパスの履歴を消す。
- 「ログイン時に起動」：`openpath.app` として起動したときだけ選べる。
- 「はじめに…」：初回起動の案内を開く。

アクセシビリティ権限が無いときや、設定ファイルに誤りがあるときは、アイコンにバッジが付き、メニューの先頭に対処の項目が出ます。

## 設定

設定は `~/.config/openpath/config.toml` に TOML で書きます。
保存すると自動で読み込み直し、誤りがあるときは直前の設定のまま動作します。

| キー | 初回に生成される値 | 内容 |
| --- | --- | --- |
| `roots` | ghq の root。ghq が無ければ `["~"]` | 候補として走査するディレクトリ。`~` はホームを表す |
| `depth` | `2` | `roots` を走査する深さ（0 以上） |
| `include_files` | `false` | ディレクトリに加えてファイルも候補にするか。パネルがファイル選択か推定できないときに使う |
| `auto_confirm` | `false` | 移動した後に「開く」まで自動で押すか |
| `hotkey` | `"ctrl+shift+o"` | パレットを出し直すホットキー。修飾キー（`ctrl`、`opt`、`shift`、`cmd`）とキーを `+` でつなぐ |
| `disabled_apps` | `[]` | パレットを出さないアプリの bundle id（例: `["com.apple.finder"]`） |
| `ignore` | `["node_modules", ".git", "target", "DerivedData", ".build"]` | 走査で除外するディレクトリ名 |
| `[ghq]` の `enabled` | `true` | `ghq list -p` のリポジトリを候補に含めるか |

`roots` の値は、初めて起動したときの環境で決まります。
`ghq root` の結果を絶対パスに解決できればその root を書き、ghq が無い場合や実行に失敗した場合はホーム（`["~"]`）を書きます。
ホームを検索対象にすると候補が多くなるため、よく使うディレクトリ（例: `roots = ["~/repos", "~/Documents"]`）に絞ることを勧めます。
既存のファイルは上書きしないため、生成済みの `roots` は後から変わりません。
キーごとの詳しい規則は [詳細設計: 候補インデックスと frecency](docs/40_arch_design/design-openpath-index-frecency.md) の「ConfigStore」にあります。

## 権限

求める権限はアクセシビリティだけです。
パネルの検知とパスの入力に使い、「システム設定 > プライバシーとセキュリティ > アクセシビリティ」で openpath を許可します。
権限が無い間は検知を止め、メニューバーのアイコンにバッジを付けて案内します。
Full Disk Access は求めません。

`roots` にホーム（`~`）など、デスクトップ、書類、ダウンロードを含む場所を指定した場合（ghq が無いときの既定を含む）は、その中を初めて読むときに macOS がアクセスの許可を確認することがあります。
確認には、フォルダ内の項目の名前を候補にするためという用途の説明が出ます。
許可しなくても openpath は動き、そのフォルダの中が候補に入らないだけです。
あとから変えるときは「システム設定 > プライバシーとセキュリティ > ファイルとフォルダ」で openpath の項目を切り替え、メニューの「候補を再構築」を選びます。

## プライバシー

- ネットワーク通信を行わず、外部サービスにも依存しません。
- 読み取るのは、最前面のアプリのウィンドウ階層のうち、ファイル選択パネルの判定に必要な範囲だけです。ウィンドウの内容や入力値は保存しません。
- パスの入力にクリップボードを一時的に使い、入力後に元の内容へ戻します。ただし、パスワードマネージャーなどが機密の印（`org.nspasteboard.ConcealedType`）を付けた内容は退避せず、パスの入力が成功しても失敗しても、クリップボードを空にします。入力の途中で別の内容がコピーされた場合は、その内容を残します。
- 保存するデータは、設定（`~/.config/openpath/config.toml`）、確定したパスの履歴（`~/Library/Application Support/openpath/history.json`）、ログ（`~/Library/Logs/openpath/`）です。どれも Mac の外へ送りません。
- 通常のログ（info 以上）にはパスやファイル名を書きません。パスは debug レベルでだけ記録します（[トラブルシュート](#トラブルシュート)）。

security の報告窓口と対象範囲は [SECURITY.md](SECURITY.md) を参照してください。

## トラブルシュート

- パレットが出ない場合は、メニューの「有効」にチェックが付いていること、アクセシビリティ権限があること、対象のアプリが `disabled_apps` に入っていないことを確かめてください。Esc で閉じた後は、Ctrl+Shift+O で出し直せます。
- ソースから再ビルドした後に権限が効かない場合は、アクセシビリティの一覧から openpath を削除して追加し直してください（[ソースからビルドする](#ソースからビルドする)）。
- 初回起動の案内を最初からやり直すには、openpath を終了してから `defaults delete jp.tamat.openpath onboardingFinished` を実行します。

ログは `~/Library/Logs/openpath/openpath.log` に出力し、5 MiB を超えると `openpath.log.1` に退避します。
統合ログ（Console.app の subsystem `jp.tamat.openpath`）にも出ます。
最小レベルは、リリースビルド（`build.sh`）で info、DEBUG ビルド（`swift run` など）で debug です。

不具合の調査で debug ログが必要な場合は、openpath を終了してから次を実行し、起動し直して問題を再現します。

```bash
defaults write jp.tamat.openpath logLevel debug
```

debug ログには、注入したパス、使った方式（主方式または副方式）、各ステップの経過時間が残ります。
確定前の移動先シートの入力欄の値と候補の選択は、入力欄をアクセシビリティ API で見つけられたときに残ります。
移動後のパネルの現在地（表示名）は、自動確定しない注入の後に残ります。
Issue に貼る前に、再現に不要なパスとユーザー名を伏せてください。

確認が終わったら、openpath を終了して既定に戻します。
値は `debug`、`info`、`warning`、`error` のいずれかで、不正な値なら既定のレベルのまま警告をログに残します。

```bash
defaults delete jp.tamat.openpath logLevel
```

## 開発

### ビルドとテスト

```bash
swift build          # ビルド
./scripts/test.sh    # ユニットテスト（Swift Testing）。Xcode 環境なら `swift test` でも可
swift run openpath   # 起動。Dock には出ず、メニューバーにアイコンが出る（メニューの「終了」で終了）
```

- Command Line Tools だけの環境では、素の `swift test` は `no such module 'Testing'` で失敗します。SwiftPM が CLT 同梱の Swift Testing を見つけられないためで、`scripts/test.sh` が必要なフラグを補ってから `swift test` を実行します。引数はそのまま `swift test` に渡せます（例: `./scripts/test.sh --filter AppInfo`）。
- `Resources/Info.plist` は実行ファイルに埋め込まれます。SwiftPM は Info.plist の変更を検知しないため、編集後は `swift package clean` してからビルドしてください。
- `swift run` で起動した場合、アクセシビリティ権限がターミナルアプリ側の権限として扱われることがあり、「ログイン時に起動」も選べません。挙動を確かめるときは `.app` から起動してください。

アクセシビリティ API とキー入力に関わる挙動は CI で確かめられないため、[手動シナリオテスト](docs/50_test/test-openpath-manual-scenarios.md) で確認します。
変更の手順と検証の一覧は [CONTRIBUTING.md](CONTRIBUTING.md) にあります。

### .app バンドルのビルドと署名

`swift build` の成果物は実行ファイル単体です。
常用や配布には、`scripts/` のスクリプトで `.app` バンドルを組み立てて署名します。
Homebrew を使う `cask_style.sh` を除き、どのスクリプトも Command Line Tools だけで動きます。

| スクリプト | 内容 | 環境変数 |
| --- | --- | --- |
| `build.sh [--arch universal\|arm64\|x86_64] [--version X.Y.Z]` | `swift build -c release` をアーキテクチャごとに実行して lipo で結合し、`build/openpath.app` を組み立てる | なし |
| `sign.sh` | Hardened Runtime と `Resources/openpath.entitlements` を付けて署名し、`codesign --verify --deep --strict` で検証する | `OPENPATH_SIGN_IDENTITY`（任意） |
| `notarize.sh` | zip にして `notarytool submit --wait`、`stapler staple`、`spctl -a -vv` を行い、staple 済みの `build/openpath-<version>.zip` を作る | `OPENPATH_NOTARY_PROFILE`（必須） |
| `cask.sh [--version X.Y.Z] [--zip PATH] [--output FILE]` | 配布用 zip の sha256 から Homebrew cask 定義を生成する（既定は標準出力） | なし |
| `cask_style.sh [CASK]` | cask に `brew style` をかける。省略時は `Resources/Info.plist` から生成した cask を確かめる。Homebrew が必要で、tap はしない | なし |
| `release.sh [--version X.Y.Z]` | build、sign、notarize、cask を順に実行し、`build/openpath-<version>.zip` と `build/Casks/openpath.rb` を作る | 上の 2 つとも必須 |

- Universal 2: Command Line Tools だけの環境では `swift build --arch arm64 --arch x86_64` が XCBuild（Xcode 同梱）を要求して失敗します。そのため `build.sh` はアーキテクチャごとにビルドしてから lipo で結合します。
- バージョン: 正本は `Resources/Info.plist` の `CFBundleShortVersionString` で、スクリプトは書き換えません。上げるときは `Resources/Info.plist` と `Sources/OpenPathCore/AppInfo.swift` を一緒に更新してください（不一致はテストで検出されます）。`build.sh --version` と `release.sh` は、指定値や `vX.Y.Z` タグが Info.plist と一致しなければ止まります。
- `build.sh` は毎回リンクをやり直し、埋め込まれた Info.plist が `Resources/Info.plist` と一致するかを検証します。このため `swift package clean` は不要です。

## リリース

リリースは maintainer が [リリース運用](docs/40_arch_design/guide-release-distribution.md) に従って行います。
変更内容は [リリースノート](docs/releases/) に記録します。
最初の Stable は [v0.1.0](docs/releases/v0.1.0.md) で、次のリリースに入る変更は [未リリースの変更](docs/releases/unreleased.md) に追記します。

### ローカルでの署名と公証

リリース担当者向けの手順です。
Apple ID、パスワード、Team ID、証明書はスクリプトにもリポジトリにも書かず、keychain と環境変数で渡します。

```bash
# Developer ID Application 証明書を keychain に入れておく
security find-identity -v -p codesigning        # 証明書の名前か SHA-1 を確認
export OPENPATH_SIGN_IDENTITY="Developer ID Application: <名前> (<Team ID>)"

xcrun notarytool store-credentials <profile>    # Apple ID、Team ID、App 用パスワードを対話的に keychain へ保存
export OPENPATH_NOTARY_PROFILE=<profile>

./scripts/release.sh                            # HEAD の vX.Y.Z タグ（無ければ Info.plist）のバージョンで作る
```

ローカルの成果物は、署名と公証の検証に使えます。
正式な公開には、次の GitHub Actions の経路を使ってください。
ローカルと CI では署名時刻などで ZIP の SHA256 が異なるため、cask を混在させないでください。

### GitHub Actions でリリースする

`Release macOS` は、Fern と同じ Smoke、Preview、Stable の 3 つの経路で配布物を作ります。
手動実行は公開前のビルド確認に、tag の push は GitHub Release の公開に使います。

| 経路 | 起動条件 | 署名と公証 | 出力 |
|---|---|---|---|
| Smoke | `workflow_dispatch` | ad-hoc 署名、公証なし | Actions artifact のみ |
| Preview | annotated tag `preview-vX.Y.Z-N` | ad-hoc 署名、公証なし | prerelease。Latest にしない |
| Stable | annotated tag `vX.Y.Z` | Developer ID 署名、公証、staple | 正式 Release。Latest にする |

tag は `main` に含まれる commit に付け、バージョンを `Resources/Info.plist` と一致させます。
すべての経路で `SHA256SUMS` を生成し、Stable にだけ Homebrew cask を添付します。
Stable の公開に成功すると、添付した `openpath.rb` で [Homebrew tap](https://github.com/TamaT-LLC/homebrew-tap) に更新の Pull Request を自動で出します。
公開手順と失敗時の復旧は [リリース運用](docs/40_arch_design/guide-release-distribution.md) を参照してください。

リポジトリの Settings → Secrets and variables → Actions に、次の値を登録します。

| 種別 | 名前 | 値 |
|---|---|---|
| Secret | `APPLE_CERTIFICATE_BASE64` | 秘密鍵付き Developer ID Application 証明書（P12）の Base64 |
| Secret | `APPLE_CERTIFICATE_PASSWORD` | P12 の書き出しパスワード |
| Secret | `APPLE_NOTARY_PRIVATE_KEY_BASE64` | openpath 専用の Team API キー（P8）の Base64 |
| Secret | `HOMEBREW_TAP_APP_PRIVATE_KEY` | Homebrew tap を更新する GitHub App の秘密鍵（ダウンロードした `.pem` の内容） |
| Variable | `APPLE_SIGNING_IDENTITY` | `Developer ID Application: 組織名 (TEAMID)` |
| Variable | `APPLE_TEAM_ID` | 証明書の Team ID |
| Variable | `APPLE_NOTARY_KEY_ID` | Team API キーの Key ID |
| Variable | `APPLE_NOTARY_ISSUER_ID` | App Store Connect の Issuer ID |
| Variable | `HOMEBREW_TAP_APP_CLIENT_ID` | 同じ GitHub App の Client ID（App ID ではない） |

公証用の Team API キーは Developer 権限で作成します。
プロジェクトごとに別のキーを作ると、個別に失効と交換ができます。
同じ組織の署名証明書は共用できます。
workflow は一時キーチェーンに認証情報を保存し、終了時に削除します。

`HOMEBREW_TAP_*` の 2 つは、Stable の公開後に `TamaT-LLC/homebrew-tap` へ cask の更新 Pull Request を出すために使います。
GitHub App は tap（`TamaT-LLC/homebrew-tap`）だけにインストールし、Repository permissions の Contents と Pull requests を Read and write にします。
ほかの権限は付けません。
`actions/create-github-app-token` は v3 で App ID の入力を非推奨にしたため、App ID ではなく Client ID を登録します。

CI では `OPENPATH_NOTARY_KEYCHAIN` に一時キーチェーンのパスを指定します。
ローカルで省略した場合は、従来どおり標準のキーチェーンからプロファイルを探します。

## コントリビューション

Issue と Pull Request を歓迎します。
始める前に [CONTRIBUTING.md](CONTRIBUTING.md) を読んでください。
使い方の質問とサポート対象の version は [SUPPORT.md](SUPPORT.md)、意思決定と maintainer の役割は [GOVERNANCE.md](GOVERNANCE.md) にあります。
参加者には [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) が適用されます。

脆弱性の可能性がある内容は公開 Issue に書かず、[SECURITY.md](SECURITY.md) の非公開の窓口から報告してください。

## ライセンス

[MIT](LICENSE)

Copyright (c) 2026 TamaT LLC.
