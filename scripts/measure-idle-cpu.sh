#!/usr/bin/env bash
# openpath のアイドル時の CPU 使用率を計測する（NFR-03「アイドル時の CPU 使用率 0.1% 未満」、TST-001 §5）。
#
# 使い方: scripts/measure-idle-cpu.sh [--pid PID] [--minutes M | --seconds S] [--interval S] [--threshold PCT]
#   --pid          計測するプロセス。省略時は openpath という名前のプロセスがちょうど 1 つならそれを使う
#   --minutes M    計測時間（分、整数）。既定 10
#   --seconds S    計測時間（秒、整数）。--minutes の代わりに指定する
#   --interval S   top で %CPU を採る間隔（秒、整数）。既定 5。計測時間はこの 2 倍以上にする
#   --threshold P  合格とする平均 CPU% の上限（これ未満なら PASS）。既定 0.1
#
# 主な値: 累積 CPU 時間（ps -o time。user + sys、1/100 秒単位）の開始と終了の差 ÷ 経過実時間 × 100 の平均 CPU%。
#   Activity Monitor と同じく 1 コア = 100%。ps -o time は Apple Silicon（macOS 26）でもプロセス自身の getrusage と
#   一致することを確かめてある（CPU 時間を mach 時間の単位で返す既知の不具合の影響は無い）。
# 補助: top -l <n> -s <interval> -pid PID -stats pid,cpu の %CPU の平均と最大。最初のサンプルは直前の計測が無く無効なため
#   捨てる。top の %CPU は小数 1 桁に丸められるため、アイドル時は主な値より粗い。両者の差が 0.1 ポイントを超え、かつ
#   大きい方の半分を超えるときは、単位の取り違え等を疑って警告する。
#   top は 1 サンプルごとに 1 秒弱かかるため、経過実時間は計測時間より 1 割ほど長くなることがある（10 分で 684 秒の例）。
#   主な値は実際の経過実時間で割るため、この差の影響は受けない。
#
# 候補の周期の再構築（既定 5 分ごと）の CPU 時間もアイドル時の値に含まれるため、再構築を 1 回以上含む長さ（既定の
# 10 分）で測る。
#
# 計測中はパネルを開く・ホットキーを押す等の操作をしないこと。
# 終了コード: 0 = PASS、1 = FAIL、2 = 計測できなかった（プロセスが無い・途中で終了した等）
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=scripts/measure-common.sh
source "$(dirname "$0")/measure-common.sh"

readonly DEFAULT_MINUTES=10
readonly SECONDS_PER_MINUTE=60
readonly DEFAULT_INTERVAL_SECONDS=5
readonly DEFAULT_THRESHOLD_PERCENT=0.1
# top の最初のサンプルは捨てるため、有効なサンプルを 1 件以上得るには 2 件以上採る
readonly MINIMUM_TOP_SAMPLES=2
readonly PERCENT=100
# 主な値と top の平均の食い違いを警告する条件（差がこのポイント数を超え、かつ大きい方のこの割合を超える）
readonly DISAGREEMENT_ABSOLUTE_POINTS=0.1
readonly DISAGREEMENT_RELATIVE_RATIO=0.5

# top -stats pid,cpu の出力から pid の行の %CPU を集計し、「有効サンプル数 平均 最大」を出力する（最初のサンプルは捨てる）
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly TOP_CPU_STATS_AWK='
$1 == pid && $2 ~ /^[0-9]+([.][0-9]+)?$/ {
  seen++
  if (seen == 1) {
    next
  }
  valid++
  sum += $2
  if (valid == 1 || $2 > max) {
    max = $2
  }
}
END {
  if (valid == 0) {
    exit 1
  }
  printf "%d %.3f %.1f\n", valid, sum / valid, max
}'

# 累積 CPU 時間の増分（1/100 秒）と経過秒数から平均 CPU% を出す
average_cpu_percent() {
  local delta_centiseconds="$1"
  local elapsed_seconds="$2"
  awk -v delta="${delta_centiseconds}" -v elapsed="${elapsed_seconds}" \
    -v unit="${CENTISECONDS_PER_SECOND}" -v percent="${PERCENT}" \
    'BEGIN { printf "%.4f\n", delta / unit / elapsed * percent }'
}

# 表示用に丸める前の値で判定する（丸めで閾値ちょうどになって FAIL にならないように）
is_average_below() {
  local delta_centiseconds="$1"
  local elapsed_seconds="$2"
  local threshold_percent="$3"
  awk -v delta="${delta_centiseconds}" -v elapsed="${elapsed_seconds}" -v threshold="${threshold_percent}" \
    -v unit="${CENTISECONDS_PER_SECOND}" -v percent="${PERCENT}" \
    'BEGIN { exit !(delta / unit / elapsed * percent < threshold) }'
}

values_disagree() {
  awk -v left="$1" -v right="$2" \
    -v absolute="${DISAGREEMENT_ABSOLUTE_POINTS}" -v relative="${DISAGREEMENT_RELATIVE_RATIO}" \
    'BEGIN {
      difference = left - right
      if (difference < 0) difference = -difference
      larger = left > right ? left : right
      exit !(difference > absolute && difference > relative * larger)
    }'
}

main() {
  local pid_option=""
  local minutes=""
  local seconds=""
  local interval_seconds="${DEFAULT_INTERVAL_SECONDS}"
  local threshold_percent="${DEFAULT_THRESHOLD_PERCENT}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pid)
        require_option_value "$1" "$#"
        pid_option="$2"
        shift 2
        ;;
      --minutes)
        require_option_value "$1" "$#"
        minutes="$2"
        shift 2
        ;;
      --seconds)
        require_option_value "$1" "$#"
        seconds="$2"
        shift 2
        ;;
      --interval)
        require_option_value "$1" "$#"
        interval_seconds="$2"
        shift 2
        ;;
      --threshold)
        require_option_value "$1" "$#"
        threshold_percent="$2"
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

  [[ -z "${minutes}" || -z "${seconds}" ]] || die_unmeasurable "--minutes と --seconds はどちらか一方だけ指定してください"
  local duration_seconds
  if [[ -n "${seconds}" ]]; then
    is_positive_integer "${seconds}" || die_unmeasurable "--seconds は正の整数で指定してください: ${seconds}"
    duration_seconds="${seconds}"
  else
    minutes="${minutes:-${DEFAULT_MINUTES}}"
    is_positive_integer "${minutes}" || die_unmeasurable "--minutes は正の整数で指定してください: ${minutes}"
    duration_seconds=$((minutes * SECONDS_PER_MINUTE))
  fi
  is_positive_integer "${interval_seconds}" || die_unmeasurable "--interval は正の整数で指定してください: ${interval_seconds}"
  is_non_negative_decimal "${threshold_percent}" || die_unmeasurable "--threshold は 0 以上の数で指定してください: ${threshold_percent}"
  local top_samples=$((duration_seconds / interval_seconds))
  [[ "${top_samples}" -ge "${MINIMUM_TOP_SAMPLES}" ]] \
    || die_unmeasurable "計測時間（${duration_seconds} 秒）は --interval（${interval_seconds} 秒）の ${MINIMUM_TOP_SAMPLES} 倍以上にしてください"

  require_command top
  resolve_target_pid "${pid_option}"

  local start_label start_epoch start_cpu
  start_label="$(now_iso8601)"
  start_epoch="$(date +%s)"
  start_cpu="$(cpu_time_centiseconds "${TARGET_PID}")" || die_unmeasurable "pid ${TARGET_PID} の CPU 時間を取得できません"
  log "pid ${TARGET_PID} のアイドル CPU を ${duration_seconds} 秒計測します（top は ${interval_seconds} 秒間隔で ${top_samples} 回）"

  local top_output
  top_output="$(top -l "${top_samples}" -s "${interval_seconds}" -pid "${TARGET_PID}" -stats pid,cpu 2>&1)" \
    || die_unmeasurable "top が失敗しました"
  # top の所要時間は環境で前後するため、計測時間に満たなければ残りを待つ
  local now_epoch
  now_epoch="$(date +%s)"
  local remaining_seconds=$((start_epoch + duration_seconds - now_epoch))
  if [[ "${remaining_seconds}" -gt 0 ]]; then
    sleep "${remaining_seconds}"
  fi

  local end_cpu end_epoch end_label
  end_cpu="$(cpu_time_centiseconds "${TARGET_PID}")" || die_unmeasurable "計測中に pid ${TARGET_PID} が終了しました"
  end_epoch="$(date +%s)"
  end_label="$(now_iso8601)"
  is_target_still_running || die_unmeasurable "計測中に pid ${TARGET_PID} が終了しました（pid が再利用されています）"

  local top_stats
  top_stats="$(printf '%s\n' "${top_output}" | awk -v pid="${TARGET_PID}" "${TOP_CPU_STATS_AWK}")" \
    || die_unmeasurable "top の出力に pid ${TARGET_PID} の %CPU がありません"
  local top_valid_samples top_average top_max
  read -r top_valid_samples top_average top_max <<<"${top_stats}"
  if [[ "${top_valid_samples}" -lt $((top_samples - 1)) ]]; then
    die_unmeasurable "top のサンプルが欠けています（${top_valid_samples} / $((top_samples - 1)) 件）。計測中にプロセスが終了した可能性があります"
  fi

  local elapsed_seconds=$((end_epoch - start_epoch))
  [[ "${elapsed_seconds}" -gt 0 ]] || die_unmeasurable "経過時間が 0 秒です"
  local delta_centiseconds=$((end_cpu - start_cpu))
  local average_percent resolution_percent
  average_percent="$(average_cpu_percent "${delta_centiseconds}" "${elapsed_seconds}")"
  resolution_percent="$(average_cpu_percent 1 "${elapsed_seconds}")"

  printf '== アイドル CPU（NFR-03）==\n'
  printf 'pid: %s（%s）\n' "${TARGET_PID}" "${TARGET_EXECUTABLE}"
  printf '計測期間: %s 〜 %s（経過実時間 %s 秒）\n' "${start_label}" "${end_label}" "${elapsed_seconds}"
  printf '累積 CPU 時間（ps -o time、user + sys）: 開始 %s 秒 → 終了 %s 秒（増分 %s 秒）\n' \
    "$(format_centiseconds "${start_cpu}")" "$(format_centiseconds "${end_cpu}")" "$(format_centiseconds "${delta_centiseconds}")"
  printf '平均 CPU%%: %s%%（累積 CPU 時間の増分 ÷ 経過実時間 × 100。1 コア = 100%%。分解能 %s%%）\n' \
    "${average_percent}" "${resolution_percent}"
  printf 'top の %%CPU（参考）: %s サンプル（%s 秒間隔、最初の 1 件は除外）平均 %s%% / 最大 %s%%\n' \
    "${top_valid_samples}" "${interval_seconds}" "${top_average}" "${top_max}"
  if values_disagree "${average_percent}" "${top_average}"; then
    warn "累積 CPU 時間による平均（${average_percent}%）と top の平均（${top_average}%）が大きく食い違っています"
    printf '注意: 累積 CPU 時間による平均と top の平均が大きく食い違っています\n'
  fi
  printf '合格基準: 平均 CPU%% < %s%%\n' "${threshold_percent}"

  local status="${EXIT_FAIL}"
  if is_average_below "${delta_centiseconds}" "${elapsed_seconds}" "${threshold_percent}"; then
    status="${EXIT_PASS}"
  fi
  print_verdict "${status}"
  exit "${status}"
}

main "$@"
