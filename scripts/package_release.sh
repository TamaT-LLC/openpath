#!/usr/bin/env bash
# Smoke / Preview / Stable の Universal ZIP と SHA256SUMS を build/release-dist に揃える。
# 使い方: scripts/package_release.sh <smoke|preview|stable> <X.Y.Z> [preview番号]
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

channel="${1:-}"
version="${2:-}"
preview="${3:-}"
validate_version "${version}"
[[ "${version}" == "$(source_version)" ]] || die "source version does not match ${version}"
suffix=""
case "${channel}" in
  smoke) suffix="-smoke" ;;
  preview)
    [[ "${preview}" =~ ^[1-9][0-9]*$ ]] || die "preview number must be positive without leading zeroes"
    suffix="-preview.${preview}"
    ;;
  stable)
    [[ -n "${APPLE_TEAM_ID:-}" ]] || die "APPLE_TEAM_ID is required"
    ;;
  *) die "channel must be smoke, preview, or stable" ;;
esac

if [[ "${channel}" == "stable" ]]; then
  "${REPO_ROOT}/scripts/release.sh" --version "${version}"
  codesign --display --verbose=2 "${APP_BUNDLE}" 2>&1 | grep -Fx "TeamIdentifier=${APPLE_TEAM_ID}"
else
  "${REPO_ROOT}/scripts/build.sh" --version "${version}"
  OPENPATH_SIGN_IDENTITY="" "${REPO_ROOT}/scripts/sign.sh"
fi
lipo "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" -verify_arch arm64 x86_64
codesign --verify --deep --strict "${APP_BUNDLE}"

dist="${BUILD_DIR}/release-dist"
rm -rf "${dist}"
mkdir -p "${dist}"
asset="${APP_NAME}-${version}${suffix}.zip"
assets=("${asset}")
if [[ "${channel}" == "stable" ]]; then
  cp "${BUILD_DIR}/${APP_NAME}-${version}.zip" "${dist}/${asset}"
  cp "${BUILD_DIR}/Casks/${APP_NAME}.rb" "${dist}/${APP_NAME}.rb"
  assets+=("${APP_NAME}.rb")
else
  ditto -c -k --norsrc --keepParent "${APP_BUNDLE}" "${dist}/${asset}"
fi
(
  cd "${dist}"
  shasum -a 256 "${assets[@]}" > SHA256SUMS
  shasum -a 256 --check SHA256SUMS
)
