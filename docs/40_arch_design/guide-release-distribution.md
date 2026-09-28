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
updated: 2026-09-28
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
Homebrew tap への反映は、Stable に添付された cask を使って別途行う。

## バージョンとタグ

`Resources/Info.plist` の `CFBundleShortVersionString` と `Sources/OpenPathCore/AppInfo.swift` の `version` を同時に更新する。
バージョンは先頭ゼロのない `X.Y.Z`、Preview 番号は1以上の整数とする。
アプリ内の表示バージョンはどの経路でも `X.Y.Z` のままで、Preview 番号はタグと ZIP 名に付く。

公開用タグは annotated tag に限定し、そのコミットが `origin/main` に含まれることを検証する。
タグのバージョン、ソースのバージョン、checkout されたコミットが一致しなければ署名処理へ進まない。
Smoke は任意の ref で実行できるが、署名・公証の Secrets は渡さない。

## 公開する手順

最初に、この workflow を含む変更を main にマージする。
Actions → `Release macOS` → `Run workflow` で main を選ぶと、公開せずに Smoke を確認できる。

Preview は、最新の main にバージョン更新をマージしてから作る。
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

Homebrew tap は、公開された `openpath.rb` を `Casks/openpath.rb` に反映する。
この cask の URL と SHA256 は、その Stable の ZIP に対応する。
Preview の ZIP を Stable 用 cask に差し替えない。

## 認証情報と実行時の扱い

登録する Secrets と Variables は [README の一覧](../../README.md#github-actions-でリリースする)を正本とする。
公証 API キーは openpath 専用の Team API キーを使用し、署名証明書は同じ会社のものを共用する。

署名・公証の認証情報は Stable の package job だけに渡す。
一時キーチェーンへ P12 と公証プロファイルを取り込み、終了時には検索リストを復元してキーチェーンを削除する。
復元や削除が失敗しても残りの削除を試み、いずれかが失敗した場合は job を失敗にする。
publish job に Apple の秘密鍵は渡さず、GitHub の `contents: write` はその job だけに付与する。

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

## 自動検証と残る実機確認

`python3 scripts/release_ci_test.py` は、隔離した Git リポジトリでタグとバージョンの条件を検証する。
公開処理は GitHub CLI をモックし、チェックサム不一致・余分なファイル・公開済みタグを拒否することを確かめる。
アップロード不足時に Draft のまま止まることと、Preview / Stable の公開フラグも対象にする。

これらのテストは Apple の公証審査や配布先 Mac の動作を代替しない。
最初の Stable では、Actions の公証結果、ダウンロード後の Gatekeeper 評価、Apple Silicon / Intel の実機起動を確認する。
