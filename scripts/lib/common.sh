# 配布用スクリプト（build / sign / notarize / cask / release）が source する共通処理。
# 単体では実行しない。macOS 標準の bash 3.2 で動くように書く。
# 定数は source した側のスクリプトで使うため、このファイル単体では未使用に見える（SC2034）。
# shellcheck shell=bash disable=SC2034

readonly APP_NAME="openpath"

# このファイルの位置（scripts/lib）からリポジトリルートを求める
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT
readonly BUILD_DIR="${REPO_ROOT}/build"
readonly APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
readonly INFO_PLIST_SOURCE="${REPO_ROOT}/Resources/Info.plist"
readonly ENTITLEMENTS_SOURCE="${REPO_ROOT}/Resources/openpath.entitlements"

# cask の version や zip のファイル名に埋め込むため、X.Y.Z の数値 3 つに限定する
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

log() {
  printf '==> %s\n' "$*" >&2
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# スクリプト冒頭（shebang の次行から最初の非コメント行の手前まで）のコメントを使い方として表示する
print_usage() {
  local script_path="$1"
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${script_path}"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "${command_name} が見つかりません"
}

# notarytool / stapler は PATH に無く xcrun 経由でのみ呼べるため、別に確認する
require_xcrun_tool() {
  local tool_name="$1"
  xcrun --find "${tool_name}" >/dev/null 2>&1 \
    || die "xcrun ${tool_name} が見つかりません（Command Line Tools か Xcode を入れてください）"
}

# plist（XML / バイナリ / JSON）の値を 1 つ取り出す。`-` を渡すと標準入力から読む
plist_value() {
  local plist_path="$1"
  local key_path="$2"
  plutil -extract "${key_path}" raw -o - "${plist_path}"
}

validate_version() {
  local version="$1"
  [[ "${version}" =~ ${VERSION_PATTERN} ]] \
    || die "バージョン '${version}' は X.Y.Z 形式（数字 3 つ）ではありません"
}

# バージョンの正本は Resources/Info.plist。実行ファイルへの埋め込みと AppInfo.version（テストで一致を検証）
# も同じ値を使うため、スクリプト側でバージョンを書き換えずここから読む
source_version() {
  local version
  version="$(plist_value "${INFO_PLIST_SOURCE}" CFBundleShortVersionString)" \
    || die "${INFO_PLIST_SOURCE} から CFBundleShortVersionString を読めません"
  validate_version "${version}"
  printf '%s\n' "${version}"
}

require_app_bundle() {
  local app_path="$1"
  [[ -d "${app_path}" ]] || die "${app_path} がありません。先に scripts/build.sh を実行してください"
}
