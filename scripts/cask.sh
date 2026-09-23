#!/usr/bin/env bash
# 配布用 zip から Homebrew cask 定義（tap リポジトリの Casks/openpath.rb）を生成する。
#
# 使い方: scripts/cask.sh [--version X.Y.Z] [--zip PATH] [--output FILE]
#   --version  既定は Resources/Info.plist の CFBundleShortVersionString
#   --zip      既定は build/openpath-<version>.zip（scripts/notarize.sh の成果物）
#   --output   書き出し先。省略時は標準出力
# zip は GitHub Releases の v<version> に openpath-<version>.zip として添付する前提で URL を組み立てる。
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly HOMEPAGE_URL="https://github.com/TamaT-LLC/openpath"
# Info.plist の LSMinimumSystemVersion（14.0 = Sonoma）と揃える
readonly CASK_MIN_MACOS=":sonoma"
readonly CASK_MIN_MACOS_MAJOR="14"
readonly SHA256_PATTERN='^[0-9a-f]{64}$'
readonly BUNDLE_ID_PATTERN='^[A-Za-z0-9.-]+$'

# zip の直下に openpath.app があり、その Info.plist が期待するバージョンかを確かめる
read_zipped_info_plist() {
  local zip_path="$1"
  local output_path="$2"
  unzip -p "${zip_path}" "${APP_NAME}.app/Contents/Info.plist" >"${output_path}" \
    || die "${zip_path} の直下に ${APP_NAME}.app/Contents/Info.plist がありません（ditto -c -k --keepParent で作った zip を渡してください）"
}

write_cask() {
  local version="$1"
  local sha256="$2"
  local bundle_id="$3"

  cat <<EOF
cask "${APP_NAME}" do
  version "${version}"
  sha256 "${sha256}"

  url "${HOMEPAGE_URL}/releases/download/v#{version}/${APP_NAME}-#{version}.zip"
  name "${APP_NAME}"
  desc "Fuzzy search palette for file open dialogs"
  homepage "${HOMEPAGE_URL}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= ${CASK_MIN_MACOS}"

  app "${APP_NAME}.app"

  uninstall quit: "${bundle_id}"

  zap trash: [
    "~/.config/openpath",
    "~/Library/Application Support/openpath",
    "~/Library/Logs/openpath",
  ]
end
EOF
}

main() {
  local version=""
  local zip_path=""
  local output_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version | --zip | --output)
        [[ $# -ge 2 ]] || die "$1 に値がありません"
        case "$1" in
          --version) version="$2" ;;
          --zip) zip_path="$2" ;;
          --output) output_path="$2" ;;
        esac
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

  require_command unzip
  require_command shasum
  require_command plutil

  if [[ -z "${version}" ]]; then
    version="$(source_version)"
  fi
  validate_version "${version}"
  if [[ -z "${zip_path}" ]]; then
    zip_path="${BUILD_DIR}/${APP_NAME}-${version}.zip"
  fi
  [[ -f "${zip_path}" ]] || die "${zip_path} がありません。先に scripts/notarize.sh で配布用 zip を作ってください"

  local work_dir
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/openpath-cask.XXXXXX")"
  CASK_WORK_DIR="${work_dir}"
  trap 'rm -rf "${CASK_WORK_DIR}"' EXIT

  local zipped_plist="${work_dir}/Info.plist"
  read_zipped_info_plist "${zip_path}" "${zipped_plist}"

  local zipped_version bundle_id minimum_macos
  zipped_version="$(plist_value "${zipped_plist}" CFBundleShortVersionString)" \
    || die "zip 内の Info.plist から CFBundleShortVersionString を読めません"
  [[ "${zipped_version}" == "${version}" ]] \
    || die "zip 内の ${APP_NAME}.app のバージョン ${zipped_version} が指定の ${version} と一致しません"
  bundle_id="$(plist_value "${zipped_plist}" CFBundleIdentifier)" \
    || die "zip 内の Info.plist から CFBundleIdentifier を読めません"
  [[ "${bundle_id}" =~ ${BUNDLE_ID_PATTERN} ]] || die "CFBundleIdentifier '${bundle_id}' の形式が不正です"
  minimum_macos="$(plist_value "${zipped_plist}" LSMinimumSystemVersion)" \
    || die "zip 内の Info.plist から LSMinimumSystemVersion を読めません"
  [[ "${minimum_macos%%.*}" == "${CASK_MIN_MACOS_MAJOR}" ]] \
    || die "LSMinimumSystemVersion ${minimum_macos} が cask の depends_on（${CASK_MIN_MACOS}）と合いません。scripts/cask.sh を更新してください"

  local sha256
  sha256="$(shasum -a 256 "${zip_path}" | awk '{ print $1 }')"
  [[ "${sha256}" =~ ${SHA256_PATTERN} ]] || die "sha256 を計算できません: ${zip_path}"

  if [[ -z "${output_path}" ]]; then
    write_cask "${version}" "${sha256}" "${bundle_id}"
    return 0
  fi

  mkdir -p "$(dirname "${output_path}")"
  write_cask "${version}" "${sha256}" "${bundle_id}" >"${output_path}"
  log "完了: ${output_path}（version ${version}, sha256 ${sha256}）"
}

main "$@"
