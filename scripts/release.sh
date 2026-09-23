#!/usr/bin/env bash
# build → sign → notarize → cask を順に実行し、配布物を build/ に揃える。
#
# 使い方: OPENPATH_SIGN_IDENTITY=... OPENPATH_NOTARY_PROFILE=... scripts/release.sh [--version X.Y.Z]
#   --version  省略時は HEAD の vX.Y.Z タグ、タグが無ければ Resources/Info.plist の値。
#              いずれも Resources/Info.plist と一致しなければ止まる（バージョンは書き換えない）
# 成果物: build/openpath-<version>.zip, build/Casks/openpath.rb
# GitHub Release の作成と tap リポジトリへの反映は行わず、最後に手順を表示する。
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly SCRIPTS_DIR="${REPO_ROOT}/scripts"
readonly CASK_OUTPUT="${BUILD_DIR}/Casks/${APP_NAME}.rb"
readonly TAG_PREFIX="v"

# 配布物は Developer ID 署名 + Notarization が前提。ad-hoc 署名の成果物を作らないよう、ビルド前に確認する
require_release_credentials() {
  [[ -n "${OPENPATH_SIGN_IDENTITY:-}" ]] \
    || die "OPENPATH_SIGN_IDENTITY が未設定です（Developer ID Application 証明書の名前か SHA-1）"
  [[ -n "${OPENPATH_NOTARY_PROFILE:-}" ]] \
    || die "OPENPATH_NOTARY_PROFILE が未設定です（xcrun notarytool store-credentials で作ったプロファイル名）"
}

# HEAD に付いた vX.Y.Z タグからバージョンを得る。タグが無ければ空文字
version_from_tag() {
  local tag
  tag="$(git -C "${REPO_ROOT}" describe --tags --exact-match HEAD 2>/dev/null || true)"
  [[ -n "${tag}" ]] || return 0
  [[ "${tag}" == "${TAG_PREFIX}"* ]] || die "HEAD のタグ ${tag} が ${TAG_PREFIX}X.Y.Z 形式ではありません"
  printf '%s\n' "${tag#"${TAG_PREFIX}"}"
}

main() {
  local version=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die "--version に値がありません"
        version="$2"
        shift 2
        ;;
      -h | --help)
        print_usage "$0"
        exit 0
        ;;
      *)
        die "不明な引数: $1（--help を参照）"
        ;;
    esac
  done

  require_release_credentials
  require_command git

  if [[ -z "${version}" ]]; then
    version="$(version_from_tag)"
  fi
  if [[ -z "${version}" ]]; then
    version="$(source_version)"
    warn "HEAD に ${TAG_PREFIX}X.Y.Z タグがないため、Resources/Info.plist の ${version} を使います"
  fi
  validate_version "${version}"

  if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    warn "作業ツリーに未コミットの変更があります。配布物はコミット済みの状態から作ることを推奨します"
  fi

  "${SCRIPTS_DIR}/build.sh" --version "${version}"
  "${SCRIPTS_DIR}/sign.sh"
  "${SCRIPTS_DIR}/notarize.sh"
  "${SCRIPTS_DIR}/cask.sh" --version "${version}" --output "${CASK_OUTPUT}"

  local dist_zip="${BUILD_DIR}/${APP_NAME}-${version}.zip"
  log "リリース成果物:"
  log "  ${dist_zip}"
  log "  ${CASK_OUTPUT}"
  cat >&2 <<EOF
次の手順（このスクリプトでは実行しません）:
  1. git tag ${TAG_PREFIX}${version} && git push origin ${TAG_PREFIX}${version}   # 未作成の場合
  2. gh release create ${TAG_PREFIX}${version} "${dist_zip}"
  3. ${CASK_OUTPUT} を tap リポジトリの Casks/${APP_NAME}.rb にコピーしてコミット
EOF
}

main "$@"
