#!/usr/bin/env bash
# Developer ID 署名済みの build/openpath.app を Notarization に提出し、staple してから配布用 zip を作る。
#
# 使い方: OPENPATH_NOTARY_PROFILE=<profile> scripts/notarize.sh
#   OPENPATH_NOTARY_PROFILE  `xcrun notarytool store-credentials <profile>` で keychain に保存したプロファイル名
# 成果物: build/openpath-<version>.zip（staple 済みの .app を ditto で固めたもの。cask.sh の入力）
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly NOTARY_WAIT_TIMEOUT="1h"
readonly NOTARY_ACCEPTED_STATUS="Accepted"

require_notary_profile() {
  [[ -n "${OPENPATH_NOTARY_PROFILE:-}" ]] && return 0
  cat >&2 <<'EOF'
error: OPENPATH_NOTARY_PROFILE が未設定です。
  Apple ID・Team ID・App 用パスワードは keychain に保存し、スクリプトにはプロファイル名だけを渡してください:
    xcrun notarytool store-credentials <profile>   # 対話的に Apple ID 等を入力
    export OPENPATH_NOTARY_PROFILE=<profile>
EOF
  exit 1
}

# Notarization は Developer ID Application 証明書・Hardened Runtime・セキュアタイムスタンプの 3 つが揃っていないと
# 提出後に Invalid になる。提出して待つ前に手元で確認する。
require_developer_id_signature() {
  local app_path="$1"
  codesign --verify --deep --strict "${app_path}" \
    || die "${app_path} の署名を検証できません。scripts/sign.sh を実行してください"

  local details
  details="$(codesign --display --verbose=2 "${app_path}" 2>&1)"
  if grep -q '^Signature=adhoc' <<<"${details}"; then
    die "ad-hoc 署名は Notarization できません。OPENPATH_SIGN_IDENTITY を設定して scripts/sign.sh を再実行してください"
  fi
  grep -q '^Authority=Developer ID Application:' <<<"${details}" \
    || die "Developer ID Application 証明書で署名されていません"
  grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"${details}" \
    || die "Hardened Runtime が有効ではありません（codesign --options runtime が必要）"
  grep -q '^Timestamp=' <<<"${details}" \
    || die "セキュアタイムスタンプがありません（codesign --timestamp が必要）"
}

# .app を親ディレクトリごと zip にする。署名は _CodeSignature と Mach-O、staple のチケットは
# Contents/CodeResources にファイルとして入るため拡張属性は不要。--norsrc で com.apple.provenance 等を除き、
# unzip で展開されても ._* ファイルがバンドル内に残らないようにする。
create_zip() {
  local app_path="$1"
  local zip_path="$2"
  ditto -c -k --norsrc --keepParent "${app_path}" "${zip_path}"
}

submit() {
  local zip_path="$1"
  local result_path="$2"
  local profile="$3"

  log "xcrun notarytool submit --wait（数分かかります）"
  # 終了コードだけでは審査結果（Accepted / Invalid / Rejected）を区別できないため、出力の status で判定する
  local exit_code=0
  xcrun notarytool submit "${zip_path}" \
    --keychain-profile "${profile}" \
    --wait \
    --timeout "${NOTARY_WAIT_TIMEOUT}" \
    --output-format json >"${result_path}" || exit_code=$?

  local status submission_id
  status="$(plist_value "${result_path}" status 2>/dev/null || true)"
  submission_id="$(plist_value "${result_path}" id 2>/dev/null || true)"
  if [[ "${status}" == "${NOTARY_ACCEPTED_STATUS}" ]]; then
    log "Notarization: ${status}（id: ${submission_id}）"
    return 0
  fi

  warn "notarytool の結果: status='${status}' exit=${exit_code}"
  cat "${result_path}" >&2 || true
  if [[ -n "${submission_id}" ]]; then
    warn "審査ログ（xcrun notarytool log ${submission_id}）:"
    xcrun notarytool log "${submission_id}" --keychain-profile "${profile}" >&2 || true
  fi
  die "Notarization が受理されませんでした"
}

main() {
  case "${1:-}" in
    "") ;;
    -h | --help)
      print_usage "$0"
      exit 0
      ;;
    *) die "不明な引数: $1（--help を参照）" ;;
  esac

  # 認証情報が無ければ、ほかの確認より先に止める
  require_notary_profile
  local profile="${OPENPATH_NOTARY_PROFILE}"

  require_command codesign
  require_command ditto
  require_command spctl
  require_command shasum
  require_xcrun_tool notarytool
  require_xcrun_tool stapler
  require_app_bundle "${APP_BUNDLE}"
  require_developer_id_signature "${APP_BUNDLE}"

  local version
  version="$(plist_value "${APP_BUNDLE}/Contents/Info.plist" CFBundleShortVersionString)" \
    || die "${APP_BUNDLE}/Contents/Info.plist から CFBundleShortVersionString を読めません"
  validate_version "${version}"

  local work_dir
  work_dir="$(mktemp -d "${BUILD_DIR}/.notarize-work.XXXXXX")"
  # trap の実行時には local 変数が消えているため、グローバルに退避する
  NOTARIZE_WORK_DIR="${work_dir}"
  trap 'rm -rf "${NOTARIZE_WORK_DIR}"' EXIT

  local submission_zip="${work_dir}/${APP_NAME}-submission.zip"
  log "提出用 zip を作成"
  create_zip "${APP_BUNDLE}" "${submission_zip}"
  submit "${submission_zip}" "${work_dir}/notarytool-result.json" "${profile}"

  log "xcrun stapler staple"
  xcrun stapler staple "${APP_BUNDLE}"
  xcrun stapler validate "${APP_BUNDLE}"

  log "spctl -a -vv（Gatekeeper の評価）"
  spctl --assess --type execute -vv "${APP_BUNDLE}"

  # staple したチケットを含めるため、配布用 zip は staple の後に作り直す
  local dist_zip="${BUILD_DIR}/${APP_NAME}-${version}.zip"
  rm -f "${dist_zip}"
  create_zip "${APP_BUNDLE}" "${dist_zip}"
  log "完了: ${dist_zip}"
  shasum -a 256 "${dist_zip}"
}

main "$@"
