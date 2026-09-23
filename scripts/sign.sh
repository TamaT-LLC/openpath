#!/usr/bin/env bash
# build/openpath.app に Hardened Runtime を有効にしてコード署名し、検証する。
#
# 使い方: OPENPATH_SIGN_IDENTITY="Developer ID Application: ..." scripts/sign.sh
#   OPENPATH_SIGN_IDENTITY  署名 ID（`security find-identity -v -p codesigning` の名前か SHA-1）。
#                           未設定なら ad-hoc 署名（`-`）にする。ad-hoc 署名のアプリは配布も Notarization もできない。
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly ADHOC_IDENTITY="-"

main() {
  case "${1:-}" in
    "") ;;
    -h | --help)
      print_usage "$0"
      exit 0
      ;;
    *) die "不明な引数: $1（--help を参照）" ;;
  esac

  require_command codesign
  require_app_bundle "${APP_BUNDLE}"
  [[ -f "${ENTITLEMENTS_SOURCE}" ]] || die "${ENTITLEMENTS_SOURCE} がありません"
  plutil -lint "${ENTITLEMENTS_SOURCE}" >&2

  local identity="${OPENPATH_SIGN_IDENTITY:-}"
  local timestamp_option
  if [[ -z "${identity}" ]]; then
    warn "OPENPATH_SIGN_IDENTITY が未設定のため ad-hoc 署名します。配布・Notarization には使えません"
    warn "ad-hoc 署名はビルドごとに署名要件（cdhash）が変わるため、再ビルド後はアクセシビリティ権限を付け直す必要があります"
    identity="${ADHOC_IDENTITY}"
    # ad-hoc 署名には証明書が無く、タイムスタンプを付けられない
    timestamp_option="--timestamp=none"
  else
    # Notarization にはセキュアタイムスタンプが必須
    timestamp_option="--timestamp"
  fi

  # 入れ子のコード（フレームワーク等）は無いため、.app を 1 回署名すれば足りる。--deep は使わない
  log "codesign --sign '${identity}' ${APP_BUNDLE}"
  codesign --force \
    --options runtime \
    "${timestamp_option}" \
    --entitlements "${ENTITLEMENTS_SOURCE}" \
    --sign "${identity}" \
    "${APP_BUNDLE}"

  log "codesign --verify --deep --strict"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

  codesign --display --verbose=2 "${APP_BUNDLE}"
  log "完了: ${APP_BUNDLE} を署名しました"
}

main "$@"
