#!/usr/bin/env bash
# openpath の常駐メモリを計測する（NFR-03「常駐メモリ 50MB 以下」、TST-001 §5「候補 20,000 件を読み込み」）。
#
# 使い方:
#   scripts/measure-memory.sh [--pid PID] [--threshold-mb MB] [--method auto|footprint|top]
#   scripts/measure-memory.sh --candidates N [--settle-seconds S] [--app PATH] [--threshold-mb MB] [--method ...]
#   --pid             計測するプロセス。省略時は openpath という名前のプロセスがちょうど 1 つならそれを使う
#   --candidates N    scripts/measure-isolated.sh start --candidates N で計測用のインスタンスを起動して計測し、
#                     終わったら（失敗・中断したときも）stop で止める。--pid とは併用できない
#   --settle-seconds S, --app PATH
#                     --candidates のとき measure-isolated.sh start にそのまま渡す
#   --threshold-mb MB 合格とする phys_footprint の上限（以下なら PASS）。既定 50（1 MB = 1,048,576 バイト）
#   --method          phys_footprint の取得方法。既定 auto（footprint で取れなければ top）
#
# 指標: phys_footprint（Activity Monitor の「メモリ」列・footprint コマンドと同じ値）の現在値で判定する。
#   footprint --pid PID --noCategories -f bytes の補助データ（phys_footprint / phys_footprint_peak）をバイト単位で読む。
#   footprint が task port を取れずに失敗するときは top -l 1 -pid PID -stats pid,mem（Physical memory footprint。
#   K / M 単位に丸められ、ピークは取れない）で代わりに取る。どちらを使ったかを出力に書く。
#   ピーク（起動後の最大値。候補の構築中の一時的な増加を含む）と RSS（ps -o rss）は参考値として併記する。
#   RSS は共有フレームワークのページを含む一方、圧縮・スワップされたページを含まないため、phys_footprint より
#   大きくも小さくもなり、常駐メモリの判定には使わない。
#
# 終了コード: 0 = PASS、1 = FAIL、2 = 計測できなかった
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=scripts/measure-common.sh
source "$(dirname "$0")/measure-common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR

readonly DEFAULT_THRESHOLD_MB=50
readonly METHOD_AUTO="auto"
readonly METHOD_FOOTPRINT="footprint"
readonly METHOD_TOP="top"
readonly FOOTPRINT_ERROR_LINES=3
# measure-isolated.sh start の出力を eval する前に、KEY=VALUE 以外（コマンド置換等）が混ざっていないかを確かめる
# 正規表現なのでシェルでは展開しない
# shellcheck disable=SC2016
readonly ISOLATED_OUTPUT_PATTERN='^OPENPATH_[A-Z_]+=[^;&|`$()<>]*$'

# footprint の補助データの行（例: "    phys_footprint: 17138504 B"）から、key のバイト数を取り出す
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly FOOTPRINT_VALUE_AWK='
$1 == key ":" && $3 == "B" && $2 ~ /^[0-9]+$/ {
  print $2
  found = 1
  exit
}
END {
  if (!found) {
    exit 1
  }
}'

# top -stats pid,mem の行（例: "28610  16M"、"784K"、"1024M+"）から、pid のメモリをバイト数にする
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly TOP_MEMORY_TO_BYTES_AWK='
$1 == pid {
  value = $2
  sub(/[+-]$/, "", value)
  unit = substr(value, length(value), 1)
  number = substr(value, 1, length(value) - 1)
  multiplier = 0
  if (unit == "B") {
    multiplier = 1
  } else if (unit == "K") {
    multiplier = kib
  } else if (unit == "M") {
    multiplier = kib * kib
  } else if (unit == "G") {
    multiplier = kib * kib * kib
  }
  if (multiplier > 0 && number ~ /^[0-9]+([.][0-9]+)?$/) {
    bytes = number * multiplier
    found = 1
  }
}
END {
  if (!found) {
    exit 1
  }
  printf "%d\n", bytes
}'

# 計測結果
METHOD_LABEL=""
FOOTPRINT_BYTES=""
PEAK_BYTES=""

# --candidates で起動した計測用インスタンス
ISOLATED_START_OUTPUT=""
ISOLATED_MEASURE_DIR=""
ISOLATED_CANDIDATES=""
ISOLATED_LIMIT_WARNING=""

measure_with_footprint() {
  local pid="$1"
  local output
  if ! output="$(footprint --pid "${pid}" --noCategories -f bytes 2>&1)"; then
    warn "footprint が失敗しました: $(printf '%s\n' "${output}" | head -n "${FOOTPRINT_ERROR_LINES}" | tr '\n' ' ')"
    return 1
  fi
  if ! FOOTPRINT_BYTES="$(printf '%s\n' "${output}" | awk -v key=phys_footprint "${FOOTPRINT_VALUE_AWK}")"; then
    warn "footprint の出力に phys_footprint がありません"
    return 1
  fi
  PEAK_BYTES="$(printf '%s\n' "${output}" | awk -v key=phys_footprint_peak "${FOOTPRINT_VALUE_AWK}" || true)"
  METHOD_LABEL="footprint --pid ${pid} --noCategories -f bytes の phys_footprint"
}

measure_with_top() {
  local pid="$1"
  local output
  if ! output="$(top -l 1 -pid "${pid}" -stats pid,mem 2>&1)"; then
    warn "top が失敗しました"
    return 1
  fi
  if ! FOOTPRINT_BYTES="$(printf '%s\n' "${output}" | awk -v pid="${pid}" -v kib="${BYTES_PER_KIBIBYTE}" "${TOP_MEMORY_TO_BYTES_AWK}")"; then
    warn "top の出力に pid ${pid} の MEM がありません"
    return 1
  fi
  PEAK_BYTES=""
  METHOD_LABEL="top -l 1 -pid ${pid} -stats pid,mem の MEM（Physical memory footprint。K / M 単位に丸められた値）"
}

measure_footprint() {
  local pid="$1"
  local method="$2"
  case "${method}" in
    "${METHOD_FOOTPRINT}")
      measure_with_footprint "${pid}" || die_unmeasurable "footprint で phys_footprint を取得できません"
      ;;
    "${METHOD_TOP}")
      measure_with_top "${pid}" || die_unmeasurable "top で phys_footprint を取得できません"
      ;;
    *)
      if ! measure_with_footprint "${pid}"; then
        warn "top -stats mem で代わりに取得します"
        measure_with_top "${pid}" || die_unmeasurable "footprint でも top でも phys_footprint を取得できません"
      fi
      ;;
  esac
}

rss_bytes() {
  local pid="$1"
  local rss_kibibytes
  rss_kibibytes="$(ps -o rss= -p "${pid}" | tr -d ' ')" || return 1
  is_non_negative_integer "${rss_kibibytes}" || return 1
  printf '%s\n' "$((rss_kibibytes * BYTES_PER_KIBIBYTE))"
}

start_isolated_instance() {
  local candidates="$1"
  local settle_seconds="$2"
  local app_path="$3"
  local arguments=(start --candidates "${candidates}")
  if [[ -n "${settle_seconds}" ]]; then
    arguments+=(--settle-seconds "${settle_seconds}")
  fi
  if [[ -n "${app_path}" ]]; then
    arguments+=(--app "${app_path}")
  fi

  # bash はコマンド置換が終わるまでシグナルの trap を遅らせるため、起動を終えた直後に中断されても
  # stop_isolated_instance が止められるよう、出力をすぐにグローバル変数へ入れる
  ISOLATED_START_OUTPUT="$("${SCRIPT_DIR}/measure-isolated.sh" "${arguments[@]}")" \
    || die_unmeasurable "計測用インスタンスを起動できません"
  local line
  while IFS= read -r line; do
    [[ "${line}" =~ ${ISOLATED_OUTPUT_PATTERN} ]] || die_unmeasurable "measure-isolated.sh の出力を解釈できません: ${line}"
  done <<<"${ISOLATED_START_OUTPUT}"

  # eval で代入される変数をこの関数の中に閉じ込める
  local OPENPATH_PID="" OPENPATH_MEASURE_DIR="" OPENPATH_LOG="" OPENPATH_HOME=""
  local OPENPATH_CANDIDATES="" OPENPATH_LIMIT_WARNING=""
  eval "${ISOLATED_START_OUTPUT}"
  ISOLATED_MEASURE_DIR="${OPENPATH_MEASURE_DIR}"
  ISOLATED_CANDIDATES="${OPENPATH_CANDIDATES}"
  ISOLATED_LIMIT_WARNING="${OPENPATH_LIMIT_WARNING}"
  [[ -n "${OPENPATH_PID}" && -n "${ISOLATED_MEASURE_DIR}" ]] || die_unmeasurable "measure-isolated.sh が pid を出力しませんでした"
  STARTED_PID="${OPENPATH_PID}"
}

stop_isolated_instance() {
  local status=$?
  trap - EXIT
  local measure_dir="${ISOLATED_MEASURE_DIR}"
  if [[ -z "${measure_dir}" ]]; then
    measure_dir="$(printf '%s\n' "${ISOLATED_START_OUTPUT}" | sed -n 's/^OPENPATH_MEASURE_DIR=//p')"
  fi
  if [[ -n "${measure_dir}" ]]; then
    "${SCRIPT_DIR}/measure-isolated.sh" stop "${measure_dir}" \
      || printf 'error: 計測用インスタンスを止められませんでした。scripts/measure-isolated.sh stop %s を実行してください\n' \
        "${measure_dir}" >&2
  fi
  exit "${status}"
}

print_report() {
  local threshold_mb="$1"
  local rss="$2"
  printf '== 常駐メモリ（NFR-03）==\n'
  printf 'pid: %s（%s）\n' "${TARGET_PID}" "${TARGET_EXECUTABLE}"
  if [[ -n "${ISOLATED_CANDIDATES}" ]]; then
    local warning_label="なし"
    if [[ "${ISOLATED_LIMIT_WARNING}" == "yes" ]]; then
      warning_label="あり"
    fi
    printf '計測用インスタンス: 候補 %s 件（measure-isolated.sh。ログの上限到達の警告: %s）\n' \
      "${ISOLATED_CANDIDATES}" "${warning_label}"
  fi
  printf '計測時刻: %s\n' "$(now_iso8601)"
  printf '取得方法: %s\n' "${METHOD_LABEL}"
  printf 'phys_footprint 現在値: %s MB（%s バイト）\n' "$(bytes_to_mebibytes "${FOOTPRINT_BYTES}")" "${FOOTPRINT_BYTES}"
  if [[ -n "${PEAK_BYTES}" ]]; then
    printf 'phys_footprint ピーク: %s MB（起動後の最大値。候補の構築中の一時的な増加を含む）\n' \
      "$(bytes_to_mebibytes "${PEAK_BYTES}")"
  else
    printf 'phys_footprint ピーク: 取得できません（top では取れない）\n'
  fi
  if [[ -n "${rss}" ]]; then
    printf 'RSS（参考）: %s MB（共有ページを含み、圧縮・スワップされたページを含まないため判定には使わない）\n' \
      "$(bytes_to_mebibytes "${rss}")"
  fi
  printf '合格基準: phys_footprint 現在値 <= %s MB（1 MB = %s バイト）\n' "${threshold_mb}" "${BYTES_PER_MEBIBYTE}"
}

main() {
  local pid_option=""
  local candidates=""
  local settle_seconds=""
  local app_path=""
  local threshold_mb="${DEFAULT_THRESHOLD_MB}"
  local method="${METHOD_AUTO}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pid)
        require_option_value "$1" "$#"
        pid_option="$2"
        shift 2
        ;;
      --candidates)
        require_option_value "$1" "$#"
        candidates="$2"
        shift 2
        ;;
      --settle-seconds)
        require_option_value "$1" "$#"
        settle_seconds="$2"
        shift 2
        ;;
      --app)
        require_option_value "$1" "$#"
        app_path="$2"
        shift 2
        ;;
      --threshold-mb)
        require_option_value "$1" "$#"
        threshold_mb="$2"
        shift 2
        ;;
      --method)
        require_option_value "$1" "$#"
        method="$2"
        shift 2
        ;;
      -h | --help)
        print_usage "$0"
        exit 0
        ;;
      *)
        die_unmeasurable "不明な引数: $1（--help を参照）"
        ;;
    esac
  done

  is_non_negative_decimal "${threshold_mb}" || die_unmeasurable "--threshold-mb は 0 以上の数で指定してください: ${threshold_mb}"
  case "${method}" in
    "${METHOD_AUTO}" | "${METHOD_FOOTPRINT}" | "${METHOD_TOP}") ;;
    *) die_unmeasurable "--method は auto / footprint / top のいずれかを指定してください: ${method}" ;;
  esac
  if [[ -n "${candidates}" && -n "${pid_option}" ]]; then
    die_unmeasurable "--candidates と --pid は併用できません"
  fi
  if [[ -z "${candidates}" && ( -n "${settle_seconds}" || -n "${app_path}" ) ]]; then
    die_unmeasurable "--settle-seconds と --app は --candidates と一緒に指定してください"
  fi

  if [[ -n "${candidates}" ]]; then
    STARTED_PID=""
    trap stop_isolated_instance EXIT
    exit_on_signals
    start_isolated_instance "${candidates}" "${settle_seconds}" "${app_path}"
    pid_option="${STARTED_PID}"
  fi

  resolve_target_pid "${pid_option}"
  measure_footprint "${TARGET_PID}" "${method}"
  local rss
  rss="$(rss_bytes "${TARGET_PID}" || true)"
  is_target_still_running || die_unmeasurable "計測中に pid ${TARGET_PID} が終了しました"

  print_report "${threshold_mb}" "${rss}"
  local status="${EXIT_FAIL}"
  if awk -v bytes="${FOOTPRINT_BYTES}" -v limit="${threshold_mb}" -v unit="${BYTES_PER_MEBIBYTE}" \
    'BEGIN { exit !(bytes <= limit * unit) }'; then
    status="${EXIT_PASS}"
  fi
  print_verdict "${status}"
  exit "${status}"
}

main "$@"
