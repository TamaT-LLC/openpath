#!/usr/bin/env bash
# リリースビルドを行い、build/openpath.app を組み立てる。
#
# 使い方: scripts/build.sh [--arch universal|arm64|x86_64] [--version X.Y.Z]
#   --arch     既定は universal（arm64 + x86_64）
#   --version  Resources/Info.plist のバージョンと一致するかを検証する（書き換えはしない）
#
# Universal 2 について: SwiftPM に `--arch` を複数渡すと XCBuild（Xcode 同梱）でのビルドになり、
# Command Line Tools だけの環境では失敗する。そのためアーキテクチャごとに `swift build --arch` を実行し、
# lipo で 1 つのバイナリに結合する。この方式は Xcode 環境でも同じように動く。
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly PKG_INFO_CONTENT="APPL????"

# SwiftPM は Info.plist を入力として追跡しないため、-sectcreate で埋め込んだ Info.plist が古いまま
# リンク済みバイナリが再利用されることがある。成果物を消してリンクをやり直させ、埋め込み内容も照合する。
# bash 3.2 ではコマンド置換の中で set -e が効かないため、この関数は $(...) の中で呼ばない。
build_arch() {
  local arch="$1"
  local binary="$2"
  rm -f "${binary}"

  log "swift build -c release --arch ${arch}"
  swift build -c release --arch "${arch}" --product "${APP_NAME}"

  verify_embedded_info_plist "${binary}" "${arch}"
}

verify_embedded_info_plist() {
  local binary="$1"
  local arch="$2"
  local extracted="${WORK_DIR}/info_plist.${arch}"

  segedit "${binary}" -extract __TEXT __info_plist "${extracted}" \
    || die "${binary} に埋め込まれた Info.plist を取り出せません"
  cmp -s "${extracted}" "${INFO_PLIST_SOURCE}" \
    || die "${arch} のバイナリに埋め込まれた Info.plist が Resources/Info.plist と一致しません（swift package clean してから再実行してください）"
}

assemble_app() {
  local binary="$1"
  local contents="${APP_BUNDLE}/Contents"

  rm -rf "${APP_BUNDLE}"
  mkdir -p "${contents}/MacOS"
  cp "${binary}" "${contents}/MacOS/${APP_NAME}"
  cp "${INFO_PLIST_SOURCE}" "${contents}/Info.plist"
  printf '%s' "${PKG_INFO_CONTENT}" >"${contents}/PkgInfo"

  # アイコン等のリソースは現時点で無い。置かれたら Contents/Resources にコピーする
  # （表示には Info.plist の CFBundleIconFile も必要）
  local icons=("${REPO_ROOT}"/Resources/*.icns)
  if [[ -e "${icons[0]}" ]]; then
    mkdir -p "${contents}/Resources"
    cp "${icons[@]}" "${contents}/Resources/"
  fi

  plutil -lint "${contents}/Info.plist" >&2
}

main() {
  local arch_option="universal"
  local expected_version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch)
        [[ $# -ge 2 ]] || die "--arch に値がありません"
        arch_option="$2"
        shift 2
        ;;
      --version)
        [[ $# -ge 2 ]] || die "--version に値がありません"
        expected_version="$2"
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

  local archs=()
  case "${arch_option}" in
    universal) archs=(arm64 x86_64) ;;
    arm64 | x86_64) archs=("${arch_option}") ;;
    *) die "--arch は universal / arm64 / x86_64 のいずれかを指定してください: ${arch_option}" ;;
  esac

  require_command swift
  require_command lipo
  require_command plutil
  require_command segedit

  plutil -lint "${INFO_PLIST_SOURCE}" >&2
  local version
  version="$(source_version)"
  if [[ -n "${expected_version}" && "${expected_version}" != "${version}" ]]; then
    die "指定バージョン ${expected_version} が Resources/Info.plist の ${version} と一致しません。Resources/Info.plist と Sources/OpenPathCore/AppInfo.swift のバージョンを更新してください"
  fi

  cd "${REPO_ROOT}"
  mkdir -p "${BUILD_DIR}"
  WORK_DIR="$(mktemp -d "${BUILD_DIR}/.build-work.XXXXXX")"
  readonly WORK_DIR
  trap 'rm -rf "${WORK_DIR}"' EXIT

  local binaries=()
  local arch bin_dir
  for arch in "${archs[@]}"; do
    bin_dir="$(swift build -c release --arch "${arch}" --show-bin-path)"
    build_arch "${arch}" "${bin_dir}/${APP_NAME}"
    binaries+=("${bin_dir}/${APP_NAME}")
  done

  local binary="${WORK_DIR}/${APP_NAME}"
  if [[ ${#binaries[@]} -gt 1 ]]; then
    log "lipo -create ${archs[*]}"
    lipo -create -output "${binary}" "${binaries[@]}"
  else
    cp "${binaries[0]}" "${binary}"
  fi

  log "${APP_BUNDLE} を組み立て"
  assemble_app "${binary}"

  log "完了: ${APP_BUNDLE}（version ${version}、$(lipo -archs "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}")）"
  log "未署名です。続けて scripts/sign.sh を実行してください"
}

main "$@"
