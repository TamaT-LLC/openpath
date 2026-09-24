#!/usr/bin/env bash
# openpath がネットワーク通信をしないことを確かめる（NFR-01「ネットワーク通信を一切行わないこと」、TST-001 §5）。
#
# 使い方: scripts/measure-network.sh [--pid PID] [--seconds S] [--interval S]
#   --pid         監視するプロセス。省略時は openpath という名前のプロセスがちょうど 1 つならそれを使う
#   --seconds S   監視する秒数（整数）。既定 60
#   --interval S  サンプリング間隔（秒、整数）。既定 5
#
# 監視中は nettop -P -x -n -p PID -L <n> -s <interval> -J bytes_in,bytes_out を 1 本通しで動かし、同じ間隔で
# lsof -nP -a -p PID -i でインターネットソケット（IPv4 / IPv6。loopback を含む）を数える。
# - nettop の値は、nettop を動かし始めてから観測したフロー（途中で閉じたものを含む）の送受信バイト数の累積。
#   監視を始める前に閉じたフローは数えられないため、起動直後からの通信も確かめたいときは
#   scripts/measure-isolated.sh start の直後に実行する
# - ソケットを 1 つも持たないプロセスは nettop の出力に行自体が出ないため、0 バイトとして扱う。
#   nettop は存在しない pid でもヘッダだけを出して正常終了するため、プロセスが動き続けていることは別に確かめる
# 全期間で送受信 0 バイトかつインターネットソケット 0 個なら PASS。
#
# 終了コード: 0 = PASS、1 = FAIL、2 = 計測できなかった
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=scripts/measure-common.sh
source "$(dirname "$0")/measure-common.sh"

readonly DEFAULT_SECONDS=60
readonly DEFAULT_INTERVAL_SECONDS=5
readonly NETTOP_COLUMNS="bytes_in,bytes_out"
readonly MAX_LISTED_SOCKETS=10

# nettop -L の CSV（",bytes_in,bytes_out," のヘッダと "<名前>.<pid>,<in>,<out>," の行の繰り返し）を集計し、
# 「サンプル数 pid の行数 bytes_in の最大 bytes_out の最大 解釈できない行数」を出力する。列の位置はヘッダから決める
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly NETTOP_STATS_AWK='
BEGIN {
  FS = ","
}
$1 == "" {
  samples++
  for (i = 2; i <= NF; i++) {
    if ($i == "bytes_in") {
      in_column = i
    } else if ($i == "bytes_out") {
      out_column = i
    }
  }
  next
}
$0 == "" {
  next
}
{
  suffix = "." pid
  is_target = length($1) > length(suffix) && substr($1, length($1) - length(suffix) + 1) == suffix
  if (!is_target || in_column == 0 || out_column == 0 || $in_column !~ /^[0-9]+$/ || $out_column !~ /^[0-9]+$/) {
    unknown++
    next
  }
  rows++
  if ($in_column + 0 > max_in) {
    max_in = $in_column + 0
  }
  if ($out_column + 0 > max_out) {
    max_out = $out_column + 0
  }
}
END {
  if (in_column == 0 || out_column == 0) {
    exit 1
  }
  printf "%d %d %.0f %.0f %d\n", samples, rows, max_in, max_out, unknown
}'

NETTOP_PID=""
NETTOP_OUTPUT_FILE=""

cleanup() {
  local status=$?
  trap - EXIT
  # 止めるのは自分が起動した nettop だけ
  if [[ -n "${NETTOP_PID}" ]] && process_exists "${NETTOP_PID}"; then
    kill "${NETTOP_PID}" 2>/dev/null || true
  fi
  if [[ -n "${NETTOP_OUTPUT_FILE}" ]]; then
    rm -f "${NETTOP_OUTPUT_FILE}"
  fi
  exit "${status}"
}

# lsof で pid のファイルを読めるか（読めないと「ソケット 0 個」と区別できないため、先に確かめる）
require_lsof_access() {
  local pid="$1"
  local output
  output="$(lsof -a -p "${pid}" -d cwd -F p 2>/dev/null || true)"
  [[ -n "${output}" ]] || die_unmeasurable "lsof で pid ${pid} を調べられません（権限が無い可能性があります）"
}

# lsof の所要時間の分だけ採取の時刻が遅れていき、nettop の監視期間からはみ出さないよう、決まった時刻まで待つ
sleep_until_epoch() {
  local target_epoch="$1"
  local remaining_seconds=$((target_epoch - $(date +%s)))
  if [[ "${remaining_seconds}" -gt 0 ]]; then
    sleep "${remaining_seconds}"
  fi
}

# インターネットソケットの一覧（lsof の見出し行を除く）。無ければ空
internet_sockets() {
  local pid="$1"
  lsof -nP -a -p "${pid}" -i 2>/dev/null | awk 'NR > 1' || true
}

main() {
  local pid_option=""
  local duration_seconds="${DEFAULT_SECONDS}"
  local interval_seconds="${DEFAULT_INTERVAL_SECONDS}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pid)
        require_option_value "$1" "$#"
        pid_option="$2"
        shift 2
        ;;
      --seconds)
        require_option_value "$1" "$#"
        duration_seconds="$2"
        shift 2
        ;;
      --interval)
        require_option_value "$1" "$#"
        interval_seconds="$2"
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
  is_positive_integer "${duration_seconds}" || die_unmeasurable "--seconds は正の整数で指定してください: ${duration_seconds}"
  is_positive_integer "${interval_seconds}" || die_unmeasurable "--interval は正の整数で指定してください: ${interval_seconds}"
  [[ "${interval_seconds}" -le "${duration_seconds}" ]] \
    || die_unmeasurable "--interval（${interval_seconds} 秒）は --seconds（${duration_seconds} 秒）以下にしてください"

  require_command nettop
  require_command lsof
  resolve_target_pid "${pid_option}"
  require_lsof_access "${TARGET_PID}"

  # 開始時点も含めて数えるため、間隔の数より 1 回多く採る
  local samples=$((duration_seconds / interval_seconds + 1))
  trap cleanup EXIT
  exit_on_signals
  NETTOP_OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/${MEASURE_TEMP_PREFIX}-nettop.XXXXXX")"

  local start_label start_epoch
  start_label="$(now_iso8601)"
  start_epoch="$(date +%s)"
  log "pid ${TARGET_PID} の通信を ${duration_seconds} 秒監視します（${interval_seconds} 秒間隔で ${samples} 回）"
  nettop -P -x -n -p "${TARGET_PID}" -L "${samples}" -s "${interval_seconds}" -J "${NETTOP_COLUMNS}" \
    >"${NETTOP_OUTPUT_FILE}" 2>&1 &
  NETTOP_PID=$!

  local max_sockets=0
  local seen_sockets=""
  local sample sockets socket_count
  for ((sample = 1; sample <= samples; sample++)); do
    is_target_still_running || die_unmeasurable "監視中に pid ${TARGET_PID} が終了しました"
    sockets="$(internet_sockets "${TARGET_PID}")"
    socket_count=0
    if [[ -n "${sockets}" ]]; then
      socket_count="$(printf '%s\n' "${sockets}" | wc -l | tr -d ' ')"
      seen_sockets="$(printf '%s\n%s\n' "${seen_sockets}" "${sockets}" | awk 'NF > 0 && !seen[$0]++')"
    fi
    if [[ "${socket_count}" -gt "${max_sockets}" ]]; then
      max_sockets="${socket_count}"
    fi
    if [[ "${sample}" -lt "${samples}" ]]; then
      sleep_until_epoch "$((start_epoch + sample * interval_seconds))"
    fi
  done

  wait "${NETTOP_PID}" || die_unmeasurable "nettop が失敗しました: $(head -n 3 "${NETTOP_OUTPUT_FILE}" | tr '\n' ' ')"
  NETTOP_PID=""
  is_target_still_running || die_unmeasurable "監視中に pid ${TARGET_PID} が終了しました"
  local end_label end_epoch
  end_label="$(now_iso8601)"
  end_epoch="$(date +%s)"

  local nettop_stats
  nettop_stats="$(awk -v pid="${TARGET_PID}" "${NETTOP_STATS_AWK}" "${NETTOP_OUTPUT_FILE}")" \
    || die_unmeasurable "nettop の出力に ${NETTOP_COLUMNS} の見出しがありません: $(head -n 3 "${NETTOP_OUTPUT_FILE}" | tr '\n' ' ')"
  local nettop_samples nettop_rows bytes_in bytes_out unknown_lines
  read -r nettop_samples nettop_rows bytes_in bytes_out unknown_lines <<<"${nettop_stats}"
  [[ "${nettop_samples}" -gt 0 ]] || die_unmeasurable "nettop のサンプルがありません"
  if [[ "${nettop_samples}" -lt "${samples}" ]]; then
    warn "nettop のサンプルが ${nettop_samples} / ${samples} 件しかありません"
  fi
  if [[ "${unknown_lines}" -gt 0 ]]; then
    warn "nettop の出力に解釈できない行が ${unknown_lines} 行あります"
  fi

  printf '== ネットワーク（NFR-01）==\n'
  printf 'pid: %s（%s）\n' "${TARGET_PID}" "${TARGET_EXECUTABLE}"
  printf '監視期間: %s 〜 %s（経過実時間 %s 秒）\n' "${start_label}" "${end_label}" "$((end_epoch - start_epoch))"
  printf 'nettop: %s サンプル（%s 秒間隔）、pid の行 %s 件、送受信 bytes_in %s / bytes_out %s バイト（監視中に観測したフローの累積。行が無ければ 0）\n' \
    "${nettop_samples}" "${interval_seconds}" "${nettop_rows}" "${bytes_in}" "${bytes_out}"
  printf 'lsof -i: %s 回、インターネットソケット最大 %s 個\n' "${samples}" "${max_sockets}"
  if [[ -n "${seen_sockets}" ]]; then
    printf '観測したソケット（最大 %s 件）:\n' "${MAX_LISTED_SOCKETS}"
    printf '%s\n' "${seen_sockets}" | head -n "${MAX_LISTED_SOCKETS}" | sed 's/^/  /'
  fi
  printf '合格基準: 送受信 0 バイトかつインターネットソケット 0 個\n'

  local status="${EXIT_FAIL}"
  if [[ "${bytes_in}" == "0" && "${bytes_out}" == "0" && "${max_sockets}" -eq 0 ]]; then
    status="${EXIT_PASS}"
  fi
  print_verdict "${status}"
  exit "${status}"
}

main "$@"
