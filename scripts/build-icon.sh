#!/usr/bin/env bash
# Resources/AppIcon.png から macOS 用の全サイズを含む AppIcon.icns を生成する。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${ICON_WORK_DIR}"' EXIT
ICONSET="${ICON_WORK_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET}"

for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${REPO_ROOT}/Resources/AppIcon.png" \
    --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
  pixels=$((size * 2))
  sips -z "${pixels}" "${pixels}" "${REPO_ROOT}/Resources/AppIcon.png" \
    --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET}" -o "${REPO_ROOT}/Resources/AppIcon.icns"
