#!/usr/bin/env bash
# scripts/cask.sh が書く cask に brew style をかけ、Homebrew tap の brew audit で落ちない形かを確かめる。
#
# 使い方: scripts/cask_style.sh [CASK]
#   CASK  確かめる cask ファイル。省略時は Resources/Info.plist だけを入れた zip から
#         scripts/cask.sh で生成する（生成物は build/cask-style に置く）
# tap には登録しない（Homebrew の Taps を書き換えない）。Homebrew の規則は、パスが Casks/ の下に
# あるファイルを cask として扱う。その判定の `**` は `.` で始まるディレクトリに一致しないため、
# 確かめる cask は一時ディレクトリの Casks/openpath.rb に写してから brew style に渡す。
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly STYLE_DIR="${BUILD_DIR}/cask-style"
CHECK_DIR=""

# 一時ディレクトリには Casks/openpath.rb しか置かないため、1 つずつ消す
remove_check_dir() {
  [[ -n "${CHECK_DIR}" ]] || return 0
  rm -f "${CHECK_DIR}/Casks/${APP_NAME}.rb"
  rmdir "${CHECK_DIR}/Casks" "${CHECK_DIR}" 2>/dev/null || warn "${CHECK_DIR} を消せませんでした"
}

# アプリの本体は不要で、cask.sh が読む Info.plist だけを zip の openpath.app に入れる
generate_cask() {
  local cask_path="$1"
  local version app_dir zip_path
  require_command ditto
  version="$(source_version)"
  app_dir="${STYLE_DIR}/${APP_NAME}.app"
  zip_path="${STYLE_DIR}/${APP_NAME}-${version}.zip"
  mkdir -p "${app_dir}/Contents"
  cp "${INFO_PLIST_SOURCE}" "${app_dir}/Contents/Info.plist"
  rm -f "${zip_path}"
  ditto -c -k --keepParent "${app_dir}" "${zip_path}"
  "${REPO_ROOT}/scripts/cask.sh" --version "${version}" --zip "${zip_path}" --output "${cask_path}"
}

main() {
  case "${1:-}" in
    -h | --help)
      print_usage "$0"
      exit 0
      ;;
  esac
  [[ $# -le 1 ]] || die "引数は確かめる cask の 1 つだけです（--help を参照）"
  require_command brew

  local source_cask
  if [[ $# -eq 1 ]]; then
    source_cask="$1"
    [[ -f "${source_cask}" ]] || die "${source_cask} がありません"
  else
    source_cask="${STYLE_DIR}/Casks/${APP_NAME}.rb"
    mkdir -p "${STYLE_DIR}/Casks"
    generate_cask "${source_cask}"
  fi

  CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openpath-cask-style.XXXXXX")"
  trap remove_check_dir EXIT
  mkdir "${CHECK_DIR}/Casks"
  cp "${source_cask}" "${CHECK_DIR}/Casks/${APP_NAME}.rb"

  # 自動更新で Homebrew の版や所要時間が実行ごとに揺れないようにする（tap の CI と同じ設定）
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
  brew --version
  brew style "${CHECK_DIR}/Casks/${APP_NAME}.rb"
  log "brew style の指摘はありません: ${source_cask}"
}

main "$@"
