---
id: PROJ-ARCH-002
layer: L3
feature: openpath
scope: global
status: Active
upstream:
- PROJ-ARCH-001
downstream:
- PROJ-TST-001
owner: TakehiroT
updated: 2026-10-09
---

# openpath のリリース運用

openpath は、Fern と同じ Smoke / Preview / Stable の3経路で配布する。
手動実行でビルドを確認し、Preview で実機検証した後、Stable のタグを push して正式版を公開する。
配布形式は既存の Universal ZIP を維持し、macOS 14 以降の Apple Silicon と Intel に対応する。

## 公開条件と成果物

GitHub Actions の `Release macOS` がビルドから GitHub Release の公開までを実行する。
Swift テストとリリース条件のテストに失敗した場合は公開しない。

| 経路 | 起動条件 | 署名・公証 | 公開先と成果物 |
| --- | --- | --- | --- |
| Smoke | `workflow_dispatch` | ad-hoc 署名、公証なし | artifact: `openpath-X.Y.Z-smoke.zip`、`SHA256SUMS` |
| Preview | annotated tag `preview-vX.Y.Z-N` | ad-hoc 署名、公証なし | prerelease: `openpath-X.Y.Z-preview.N.zip`、`SHA256SUMS` |
| Stable | annotated tag `vX.Y.Z` | Developer ID 署名、公証、staple、Gatekeeper 検証 | 正式 Release: `openpath-X.Y.Z.zip`、`openpath.rb`、`SHA256SUMS` |

Preview は Latest にせず、Stable は Latest にする。
Actions artifact の保存期間は14日で、GitHub Release に添付した成果物は残る。
Smoke と Preview は Apple の公証を受けていないため、通常の配布版と同じ起動体験にはならない。
検証者に用途を伝え、正式配布には Stable を使う。

openpath には自動更新機能がないため、Fern の updater manifest や R2 公開処理は導入しない。
Stable の公開に成功すると、添付した cask で Homebrew tap に更新の Pull Request を自動で出す（[Homebrew tap への反映](#homebrew-tap-への反映)）。

## バージョンとタグ

`Resources/Info.plist` の `CFBundleShortVersionString` と `Sources/OpenPathCore/AppInfo.swift` の `version` を同時に更新する。
バージョンは先頭ゼロのない `X.Y.Z`、Preview 番号は1以上の整数とする。
アプリ内の表示バージョンはどの経路でも `X.Y.Z` のままで、Preview 番号はタグと ZIP 名に付く。

公開用タグは annotated tag に限定し、そのコミットが `origin/main` に含まれることを検証する。
Stable と Preview のタグ（`v*` と `preview-v*`）を作れるのは、リポジトリの admin だけである。
ruleset `protect-release-tags` がタグの作成・更新・削除を禁止し、リポジトリのロール admin だけを bypass にしている。
bypass は ruleset のすべてのルールに及ぶため、admin は更新と削除もできる。公開済みのタグは差し替えない（[失敗と再実行](#失敗と再実行)）。
タグのバージョン、ソースのバージョン、checkout されたコミットが一致しなければ署名処理へ進まない。
Smoke は任意の ref で実行できるが、署名・公証の Secrets は渡さない。
Smoke と Preview は `package` job で、Stable は environment `release` を使う `package-stable` job で作る（[認証情報と実行時の扱い](#認証情報と実行時の扱い)）。

## 公開する手順

最初に、この workflow を含む変更を main にマージする。
Actions → `Release macOS` → `Run workflow` で main を選ぶと、公開せずに Smoke を確認できる。

Stable のタグは Preview と同じコミットに付けるので、リリースノートの準備は Preview を作る前に済ませる。
`docs/releases/unreleased.md` を `docs/releases/vX.Y.Z.md` に改め、新しい `unreleased.md` を作る。
改めたファイルの 1 行目は `# vX.Y.Z` または `# vX.Y.Z（補足）` にする。括弧の中の補足は、ドキュメントインデックスのリンクにも付く。
続けて `python3 scripts/release_notes_index.py` で [ドキュメントインデックス](../00_index/index.md) のリリースノート一覧を再生成する。
CI の `repository policy` が `python3 scripts/release_notes_index.py --check` で一覧と `docs/releases/` の一致を検査する。
この変更とバージョン更新を Pull Request で main にマージする。

Preview は、上のマージ後の最新の main から作る。
次は `0.1.0` の最初の Preview の例で、既存タグと重複しない番号を使う。

```bash
git switch main
git pull --ff-only
git tag -a preview-v0.1.0-1 -m "openpath 0.1.0 Preview 1"
git push origin refs/tags/preview-v0.1.0-1
```

Preview の ZIP を実機で確認したら、確認済みのコミットに Stable タグを付ける。
次の例では Preview と同じコミットを指定する。修正が必要だった場合は新しい Preview を検証してから進める。

```bash
git tag -a v0.1.0 'preview-v0.1.0-1^{commit}' -m "openpath 0.1.0"
git push origin refs/tags/v0.1.0
```

Stable は CI で署名・公証をやり直し、staple 済みの ZIP と cask を公開する。
ZIP をダウンロードしたら `shasum -a 256 --check SHA256SUMS` で確認する。
Stable では `openpath.rb` も検証対象なので、添付ファイルをすべて同じディレクトリに保存する。
ZIP を展開して Applications に移し、起動とアクセシビリティ許可後の動作を確認する。

Stable の公開後は、`Release macOS` が Homebrew tap に `Casks/openpath.rb` の更新 Pull Request を出す。
この cask の URL と SHA256 は、その Stable の ZIP に対応する。
Preview の ZIP を Stable 用 cask に差し替えない。

## Homebrew tap への反映

Stable の publish job が成功すると、`Release macOS` は `Homebrew tap`（`.github/workflows/homebrew-tap.yml`）を呼ぶ。
Smoke と Preview では呼ばない。
この workflow は GitHub App のトークンで、[TamaT-LLC/homebrew-tap](https://github.com/TamaT-LLC/homebrew-tap) に cask の更新 Pull Request を出す。
処理は `scripts/update_homebrew_tap.py` にまとめてあり、次の順に進む。

1. 公開済みの Release が、Draft でも prerelease でもない Stable で、tag が `vX.Y.Z` の形であることを確かめる。
2. Release から `openpath-X.Y.Z.zip`、`openpath.rb`、`SHA256SUMS` を取得する。添付ファイルに過不足があれば失敗にする。
3. `SHA256SUMS` と ZIP・cask の SHA256、cask の `version` と tag、cask の `sha256` と ZIP、`url` の形を照合する。どれかが合わなければ失敗にする。
4. 照合が通ってから App のトークンを発行する。トークンの対象は `homebrew-tap` だけで、Contents と Pull requests の書き込みだけを要求する。
5. tap を clone して `Casks/openpath.rb` と比べる。反映済みなら、何もせずに成功で終わる。
6. 反映されていなければ、`openpath-vX.Y.Z` ブランチに cask を commit して push し、Pull Request を出して auto-merge（squash）を要求する。

tap 側とは、次のように取り決めている。

- ブランチ名は `openpath-vX.Y.Z`、Pull Request のタイトルは `openpath X.Y.Z` とする。tap はタイトルで自動処理を分けることがあるため、形を変えない。
- 変更するのは `Casks/openpath.rb` だけで、中身は Release に添付した `openpath.rb` をそのまま使う。ほかのファイルを変えるブランチは、push せずに失敗にする。
- tap の必須チェックは `brew audit` と `release check` で、auto-merge はこれらの成功を待ってマージする。
- tap で auto-merge を要求できない場合は、警告を出して Pull Request を残す。job は失敗にしない。
- commit の作者は App の bot（`<app-slug>[bot]`）とする。名前は固定で書かず、トークンを発行した action の出力から組み立てる。

tap の `release check` は、tap の cask と Release 添付の cask の `version`・`sha256`・`url` を照合する。
それ以外の行は、Homebrew の変更に合わせて tap 側で直すことがある（`v0.1.0` の `depends_on` など）。
このため、`version`・`sha256`・`url` が Release と同じなら反映済みとみなし、ほかの行の違いはログに出すだけで戻さない。
既存の `openpath-vX.Y.Z` ブランチに tap 側の修正が入っている場合も、同じ基準で上書きしない。
同じ版なのに `sha256` か `url` が違う場合は、tap を手で確かめる必要があるため失敗にする。
tap の版のほうが新しい場合は、警告を出して変更しない。

同じブランチや開いた Pull Request がすでにあれば、作り直さずにそのブランチへ commit を足す。
App のトークンで作った Pull Request では、tap の必須チェックの workflow が動く（`GITHUB_TOKEN` で作った Pull Request では動かない）。

### cask の最小 macOS の書き方

`scripts/cask.sh` は、最小の macOS を `depends_on macos: :sonoma` と書く。
Homebrew 6.0.0（2026-06-11）から、記号だけの `:sonoma` は「Sonoma 以降」を意味するようになり、それまでの `">= :sonoma"` は非推奨になった。
`">= :sonoma"` のままでは `brew style` が失敗して tap の `brew audit` を通らず、Pull Request は auto-merge されない。
Homebrew 5.x 以前は `:sonoma` を「Sonoma のみ」と解釈するため、古い Homebrew では Sonoma 以外の macOS にインストールできない。
`v0.1.0` の添付は `">= :sonoma"` のままで、tap 側で `:sonoma` に直してある。
CI は、生成した cask に `brew style` をかける（`scripts/cask_style.sh`）。

### App を設定した直後の確認

App を作成し、[README の一覧](../../README.md#github-actions-でリリースする)の Variable と Secret を environment `homebrew-tap` に登録したら、公開済みの `v0.1.0` で dry run を実行する。
dry run は、トークンの発行、tap の clone、差分の確認までで止まり、push も Pull Request の作成もしない。

1. Actions → `Homebrew tap` → `Run workflow` で、branch に `main`、`tag` に `v0.1.0` を指定し、`dry_run` をチェックしたまま実行する。CLI では `gh workflow run homebrew-tap.yml --ref main -f tag=v0.1.0 -f dry_run=true` を使う。
2. `Issue a token for the tap` が成功すれば、トークンを発行できている。App が tap にインストールされ、Contents と Pull requests の書き込み権限を持つことも、この step で確かめられる。
3. `Update the cask in the tap` のログに `Cloned TamaT-LLC/homebrew-tap (main).` が出れば、tap を clone できている。
4. 同じログで差分の有無を確かめる。tap 側で `depends_on` を直した `v0.1.0` の cask なら、`already has the version, sha256, and url of v0.1.0` と、ほかの行の差分が出て、何もせずに終わる。

## 認証情報と実行時の扱い

登録する Secrets と Variables、environment とそのデプロイ対象は [README の一覧](../../README.md#github-actions-でリリースする)を正本とする。
公証 API キーは openpath 専用の Team API キーを使用し、署名証明書は同じ会社のものを共用する。

Secrets はリポジトリ全体には置かず、次の 2 つの environment に置く。
リポジトリ全体の Secret は、write 権限を持つアカウントが任意のブランチで workflow を書き換えれば読み出せる。
environment の Secret は、デプロイ対象の ref で動く job にしか渡らない。

| environment | Secret / Variable | 使う job | デプロイを許す ref |
| --- | --- | --- | --- |
| `release` | Secret `APPLE_CERTIFICATE_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_NOTARY_PRIVATE_KEY_BASE64` | `Release macOS` の `package-stable` | tag `v*` |
| `homebrew-tap` | Secret `HOMEBREW_TAP_APP_PRIVATE_KEY`、Variable `HOMEBREW_TAP_APP_CLIENT_ID` | `Homebrew tap` の `update cask` | tag `v*`、branch `main` |

`release` は Stable のタグだけを許す。Preview（`preview-v*`）と Smoke は署名・公証の Secrets を使わないため、environment を付けない `package` job で作る。
`homebrew-tap` は、`Release macOS` から呼ばれたとき（ref は Stable のタグ）と、main から手動実行したときの両方で動く必要があるため、`main` も許す。
main には、ruleset `protect-main` と `require-code-owner-review` により Pull Request を経た変更しか入らない。
タグ `v*` と `preview-v*` は admin だけが作れ、admin 以外は更新も削除もできない（ruleset `protect-release-tags`）。
このため、`release` の Secrets を受け取る job を動かせるのは admin だけになる。
どちらの environment にも Required reviewers は付けていない。admin のアカウントが乗っ取られた場合は、タグを作って Secrets を使えてしまうことを前提とする。
Apple の Variable 4 つ（署名 ID、Team ID、Key ID、Issuer ID）は秘密ではないため、リポジトリ全体に置く。
environment の構成は `.github/settings-desired-v1.json` に宣言し、`python3 scripts/github_settings_drift.py` で実際の設定と照合する。

署名・公証の認証情報は Stable の `package-stable` job だけに渡す。
一時キーチェーンへ P12 と公証プロファイルを取り込み、終了時には検索リストを復元してキーチェーンを削除する。
復元や削除が失敗しても残りの削除を試み、いずれかが失敗した場合は job を失敗にする。
publish job に Apple の秘密鍵は渡さず、GitHub の `contents: write` はその job だけに付与する。

Homebrew tap を更新する GitHub App の秘密鍵は、`Homebrew tap` の `update cask` job だけが environment `homebrew-tap` から受け取る。
environment の Secret は呼び出し元の workflow から渡せないため、`Release macOS` は秘密鍵を渡さず、`secrets: inherit` も使わない。
秘密鍵は `actions/create-github-app-token` の入力にだけ使い、run の環境変数には入れない。設定の確認では、値ではなく有無だけを見る。
発行するトークンは `TamaT-LLC/homebrew-tap` だけを対象にし、権限を Contents と Pull requests の書き込みに絞る。job の終了時に、action がトークンを失効させる。
`scripts/update_homebrew_tap.py` は、トークンを引数にもログにも出さない。`gh` は `GH_TOKEN` から読み、git は push のときだけ `gh auth git-credential` を通して受け取る。
この job の `GITHUB_TOKEN` は `contents: read` だけで、Release の取得に使う。

## 失敗と再実行

既存の GitHub Release は上書きしない。
公開処理は添付ファイルの種類と SHA256 を検証してから Draft を作り、アップロード完了を確認して公開に切り替える。
Preview / Stable の区分も、公開後に再確認する。

ビルドや公証に失敗し、まだ Release が存在しない場合は `Re-run all jobs` で再実行する。
成果物には実行番号を付けているため、失敗した job だけの再実行は使わない。
署名や公証の設定不足を、ad-hoc 署名への切り替えで回避しない。

Draft が残った場合は、添付ファイルとログを確認してから復旧する。
再実行で自動上書きはされないため、不完全な Draft を削除して全 job を再実行するか、検証済みの Draft を手動で公開する。
公開直後の状態確認だけが失敗した場合は、Release がすでに公開されていることがある。
添付ファイル・SHA256SUMS・prerelease / Latest の状態を確認し、問題がなければ公開済みとして扱う。
公開済みの成果物やタグは差し替えず、新しい Preview 番号または Stable バージョンで修正する。

Homebrew tap の job（`homebrew-tap / update cask`）は、公開済みの Release から添付ファイルを取得し直し、Actions の artifact を使わない。
このため、Release の公開後にこの job だけが失敗した場合は、`Re-run failed jobs` でこの job だけを再実行してよい。
上の「失敗した job だけの再実行は使わない」は、実行番号付きの artifact を受け渡す package（Stable では package-stable）と publish の job についての方針で、この job には当てはまらない。
逆に、この場合に `Re-run all jobs` は使わない。公開済みの Release は上書きしないため、publish job が失敗する。
`Release macOS` を再実行する代わりに、`Homebrew tap` を手動実行してもよい。`tag` に対象の版を指定し、`dry_run` を外す。
公開直後の状態確認で publish job が失敗し、Release を公開済みとして扱う場合は、tap の job が動かないため、同じ手動実行で反映する。
App の設定不足で失敗した場合は、README の一覧のとおり environment `homebrew-tap` の Variable と Secret を直してから再実行する。
手動実行は main か Stable のタグから行う。ほかのブランチから実行すると、environment のデプロイ対象外として job が始まらない。
どの方法で再実行しても、反映済みなら何もせず、既存のブランチと Pull Request は作り直さない。

## 自動検証と残る実機確認

`python3 scripts/release_ci_test.py` は、隔離した Git リポジトリでタグとバージョンの条件を検証する。
公開処理は GitHub CLI をモックし、チェックサム不一致・余分なファイル・公開済みタグを拒否することを確かめる。
アップロード不足時に Draft のまま止まることと、Preview / Stable の公開フラグも対象にする。

Homebrew tap への反映は、隔離した bare リポジトリを tap に見立て、GitHub CLI をモックして確かめる。
照合の失敗、Preview の拒否、反映済みなら何もしないこと（tap 側で直した行を含む）、既存のブランチと Pull Request の扱い、auto-merge を要求できないときの警告、dry run が対象である。
`Release macOS` が Stable の publish の後にだけ tap の workflow を呼ぶことと、App の秘密鍵の渡し方も、workflow の定義から確かめる。
署名・公証の Secrets を参照するのが environment `release` の `package-stable` job だけであることと、tap の job が environment `homebrew-tap` を使うことも同様に確かめる。
`scripts/cask.sh` の生成物は、`depends_on macos: :sonoma` であることと、tap と同じ照合に通ることをテストで確かめる。
CI では、生成物に `brew style` もかける。

これらのテストは Apple の公証審査や配布先 Mac の動作を代替しない。
最初の Stable では、Actions の公証結果、ダウンロード後の Gatekeeper 評価、Apple Silicon / Intel の実機起動を確認する。
tap の必須チェックと auto-merge の実際の動作は、App を設定した後の最初の Stable で確認する。
