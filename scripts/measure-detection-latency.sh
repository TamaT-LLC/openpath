#!/usr/bin/env bash
# ログのタイムスタンプから、パネルの検知からパレット表示までのレイテンシを集計する
# （FR-DETECT-03「300ms 以下」、TST-001 §5「p95 300ms 以下」）。
# 始点の panel detected は PanelWatcher がパネルを検知した直後に出るため、パネルが生成されてから検知されるまで
# （AX 通知の遅れや 200ms ポーリングの待ち）の時間は含まれない。
#
# 使い方: scripts/measure-detection-latency.sh [--log FILE]... [--start-pattern TEXT] [--end-pattern TEXT] [--threshold-ms MS]
#   --log FILE           読むログ。繰り返し指定すると指定した順に続けて読む。省略時は ~/Library/Logs/openpath/ の
#                        openpath.log.1（あれば）と openpath.log をこの順に読む（ローテーションで古い方が .1 になるため）。
#                        CFFIXED_USER_HOME が設定されていれば ~ の代わりにそれを使う（measure-isolated.sh の一時 HOME）
#   --start-pattern TEXT 始点の行の目印。既定 "panel detected"（PanelWatcher が `panel detected (id: open-panel-N, …)` を出す）
#   --end-pattern TEXT   終点の行の目印。既定 "palette shown"（PalettePresenter がパレットを表示するたびに
#                        `palette shown (id: open-panel-N)` を info で出す。PR #69 より前のビルドは出さないため、
#                        そのログでは end の行が無く、終了コード 2 になる）
#   --threshold-ms MS    合格とする p95 の上限（ミリ秒、これ以下なら PASS）。既定 300
#
# 計測の手順: アクセシビリティ権限を付けた openpath を起動し、TextEdit の「ファイル > 開く…」（⌘O）→ パレットが
# 出たのを確かめてパネルを「キャンセル」で閉じる操作（TST-001 §3 の S-01。Finder の ⌘O では「開く」ダイアログが
# 出ない）を 20 回ほど繰り返してから、このスクリプトを実行する。

#
# ログ行の形式は `2026-09-23T12:34:56.789+09:00 [INFO] message`。目印は message に含まれるか（固定文字列）で判定する。
# タイムスタンプはオフセット（+09:00 / -05:00 / Z）込みでエポックミリ秒に直してから差を取るため、秒・分・日・年の
# 境目やオフセットの違いをまたいでも正しく計算する（awk で暦日を数える。perl には頼らない）。
# 組み方: message の "(id: X" の X（"," か ")" まで）をパネルの ID として読む。
#   - end に ID があれば、同じ ID のまだ組んでいない start と組にする（間に別の ID の start があってもよい）。
#   - end に ID が無ければ、直前の start がまだ組んでいなければそれと組にする（ID を出さない行を目印にしたとき）。
#   - 同じ ID の start が続いたら古い方は組めなかったものとして数える。
#   - "panel gone"（ID を持たない）と起動の行（"を起動します"）で、まだ組んでいない start をすべて打ち切る。
#     ID はプロセスごとの連番で再起動すると同じ値が使われるため、前の起動の start と組まないようにする。
#   - 組む相手の無い end（同じパネルの再表示・ホットキーでの再表示で出る）は件数だけ数えて除外する。
#   - 組めなかった start（パレットが出なかった検知）が 1 件でもあれば判定しない（終了コード 2）。除いて p95 を出すと
#     表示の失敗を見逃すため。
# 集計: p50 / p95 は nearest-rank 法（昇順に並べた ceil(p / 100 × n) 番目の値）。
#
# 終了コード: 0 = PASS、1 = FAIL、2 = 計測できなかった（ログが無い・end の行が 1 行も無い・組めなかった start がある等）
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=scripts/measure-common.sh
source "$(dirname "$0")/measure-common.sh"

readonly DEFAULT_START_PATTERN="panel detected"
readonly DEFAULT_END_PATTERN="palette shown"
# PanelWatcher がパネルの消滅を記録する文言。これを挟んだ start と end は組にしない
readonly PANEL_GONE_PATTERN="panel gone"
# AppDelegate が起動時に出す `openpath <version> を起動します` の末尾。パネルの ID は再起動で振り直されるため区切りにする
readonly APP_LAUNCH_PATTERN="を起動します"
readonly DEFAULT_THRESHOLD_MS=300
readonly MEDIAN_PERCENTILE=50
readonly TAIL_PERCENTILE=95
readonly LOG_DIRECTORY="${CFFIXED_USER_HOME:-${HOME}}/Library/Logs/${APP_NAME}"
readonly CURRENT_LOG_FILE="${LOG_DIRECTORY}/${APP_NAME}.log"
readonly ROTATED_LOG_FILE="${CURRENT_LOG_FILE}.1"

# ログを先頭から読み、組にできた差を "latency <ms>" で、最後に
# "summary <start 行数> <end 行数> <組めなかった start> <組む相手の無い end> <負の差> <解釈できないタイムスタンプ>" を出力する。
# 目印は -v だとエスケープが解釈されるため環境変数（START_PATTERN / END_PATTERN / GONE_PATTERN / LAUNCH_PATTERN）で受け取る
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly PAIRING_AWK='
# 1970-01-01 からの日数（Howard Hinnant の days_from_civil。グレゴリオ暦）
function days_from_civil(year, month, day,    era, year_of_era, day_of_year, day_of_era) {
  year -= (month <= 2)
  era = int((year >= 0 ? year : year - 399) / 400)
  year_of_era = year - era * 400
  day_of_year = int((153 * (month + (month > 2 ? -3 : 9)) + 2) / 5) + day - 1
  day_of_era = year_of_era * 365 + int(year_of_era / 4) - int(year_of_era / 100) + day_of_year
  return era * 146097 + day_of_era - 719468
}

# ISO 8601（YYYY-MM-DDThh:mm:ss[.fff][Z|+hh:mm|-hh:mm|+hhmm]）をエポックミリ秒にする。解釈できなければ -1
function epoch_milliseconds(stamp,    year, month, day, hour, minute, second, rest, fraction, zone, sign, offset_minutes) {
  if (stamp !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) {
    return -1
  }
  year = substr(stamp, 1, 4) + 0
  month = substr(stamp, 6, 2) + 0
  day = substr(stamp, 9, 2) + 0
  hour = substr(stamp, 12, 2) + 0
  minute = substr(stamp, 15, 2) + 0
  second = substr(stamp, 18, 2) + 0
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
    return -1
  }
  rest = substr(stamp, 20)
  fraction = ""
  if (match(rest, /^[.][0-9]+/)) {
    fraction = substr(rest, 2, RLENGTH - 1)
    rest = substr(rest, RLENGTH + 1)
  }
  if (rest == "Z") {
    offset_minutes = 0
  } else if (rest ~ /^[+-][0-9][0-9]:?[0-9][0-9]$/) {
    sign = substr(rest, 1, 1) == "-" ? -1 : 1
    zone = substr(rest, 2)
    gsub(/:/, "", zone)
    offset_minutes = sign * (substr(zone, 1, 2) * 60 + substr(zone, 3, 2))
  } else {
    return -1
  }
  return ((days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second) - offset_minutes * 60) * 1000 \
    + substr(fraction "000", 1, 3)
}

# "<タイムスタンプ> [LEVEL] message" の message
function message_of(line,    rest, closing) {
  rest = substr(line, length($1) + 2)
  if (substr(rest, 1, 1) == "[") {
    closing = index(rest, "] ")
    if (closing > 0) {
      return substr(rest, closing + 2)
    }
  }
  return rest
}

# message の "(id: X, …)" / "(id: X)" の X。無ければ空文字列
function panel_id_of(message,    position, rest) {
  position = index(message, "(id: ")
  if (position == 0) {
    return ""
  }
  rest = substr(message, position + 5)
  if (!match(rest, /[,)]/)) {
    return ""
  }
  return substr(rest, 1, RSTART - 1)
}

# まだ組んでいない start をすべて、組めなかったものとして数えて捨てる
function abandon_pending(    key) {
  for (key in pending_time) {
    unpaired++
  }
  # for-in の途中で要素を消す振る舞いは awk の実装で異なるため、数え終えてからまとめて空にする
  split("", pending_time)
  last_start_key = ""
  has_last_start = 0
}

BEGIN {
  start_pattern = ENVIRON["START_PATTERN"]
  end_pattern = ENVIRON["END_PATTERN"]
  gone_pattern = ENVIRON["GONE_PATTERN"]
  launch_pattern = ENVIRON["LAUNCH_PATTERN"]
}

{
  message = message_of($0)
  is_start = index(message, start_pattern) > 0
  is_end = index(message, end_pattern) > 0
  is_gone = index(message, gone_pattern) > 0
  is_launch = index(message, launch_pattern) > 0
  if (!is_start && !is_end && !is_gone && !is_launch) {
    next
  }
  if (is_launch) {
    abandon_pending()
    next
  }
  time = epoch_milliseconds($1)
  if (time < 0) {
    bad_timestamps++
    next
  }
  if (is_start) {
    starts++
    key = panel_id_of(message)
    if (key in pending_time) {
      unpaired++
    }
    pending_time[key] = time
    last_start_key = key
    has_last_start = 1
  } else if (is_end) {
    ends++
    key = panel_id_of(message)
    if (key == "" && has_last_start) {
      key = last_start_key
    }
    if (!(key in pending_time)) {
      orphan_ends++
      next
    }
    start_time = pending_time[key]
    delete pending_time[key]
    if (key == last_start_key) {
      has_last_start = 0
    }
    if (time < start_time) {
      negative++
      next
    }
    printf "latency %d\n", time - start_time
  } else {
    abandon_pending()
  }
}

END {
  abandon_pending()
  printf "summary %d %d %d %d %d %d\n", starts, ends, unpaired, orphan_ends, negative, bad_timestamps
}'

# 昇順に並んだ値から「件数 p50 p95 最大」を出力する（nearest-rank 法: ceil(p × n / 100) 番目）
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly PERCENTILE_AWK='
function nearest_rank(percentile, count) {
  return int((percentile * count + 99) / 100)
}
{
  values[++count] = $1
}
END {
  if (count == 0) {
    exit 1
  }
  printf "%d %d %d %d\n", count, values[nearest_rank(median, count)], values[nearest_rank(tail, count)], values[count]
}'

default_log_files() {
  if [[ -f "${ROTATED_LOG_FILE}" ]]; then
    printf '%s\n' "${ROTATED_LOG_FILE}"
  fi
  if [[ -f "${CURRENT_LOG_FILE}" ]]; then
    printf '%s\n' "${CURRENT_LOG_FILE}"
  fi
}

main() {
  local log_files=()
  local start_pattern="${DEFAULT_START_PATTERN}"
  local end_pattern="${DEFAULT_END_PATTERN}"
  local threshold_ms="${DEFAULT_THRESHOLD_MS}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log)
        require_option_value "$1" "$#"
        log_files+=("$2")
        shift 2
        ;;
      --start-pattern)
        require_option_value "$1" "$#"
        start_pattern="$2"
        shift 2
        ;;
      --end-pattern)
        require_option_value "$1" "$#"
        end_pattern="$2"
        shift 2
        ;;
      --threshold-ms)
        require_option_value "$1" "$#"
        threshold_ms="$2"
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
  [[ -n "${start_pattern}" ]] || die_unmeasurable "--start-pattern が空です"
  [[ -n "${end_pattern}" ]] || die_unmeasurable "--end-pattern が空です"
  is_non_negative_decimal "${threshold_ms}" || die_unmeasurable "--threshold-ms は 0 以上の数で指定してください: ${threshold_ms}"

  if [[ ${#log_files[@]} -eq 0 ]]; then
    local default_file
    while IFS= read -r default_file; do
      log_files+=("${default_file}")
    done < <(default_log_files)
    [[ ${#log_files[@]} -gt 0 ]] || die_unmeasurable "ログがありません: ${CURRENT_LOG_FILE}（--log で指定してください）"
  fi
  local log_file
  for log_file in "${log_files[@]}"; do
    [[ -f "${log_file}" && -r "${log_file}" ]] || die_unmeasurable "ログを読めません: ${log_file}"
  done

  local pairing
  pairing="$(START_PATTERN="${start_pattern}" END_PATTERN="${end_pattern}" GONE_PATTERN="${PANEL_GONE_PATTERN}" \
    LAUNCH_PATTERN="${APP_LAUNCH_PATTERN}" awk "${PAIRING_AWK}" "${log_files[@]}")" || die_unmeasurable "ログを集計できません"
  local summary
  summary="$(printf '%s\n' "${pairing}" | awk '$1 == "summary"')"
  # 集計の awk が最後まで動かなかったとき（summary の行が無い）に、0 件として先へ進まない
  [[ -n "${summary}" ]] || die_unmeasurable "ログを集計できません（集計結果がありません）"
  local starts ends unpaired orphan_ends negative bad_timestamps
  read -r _ starts ends unpaired orphan_ends negative bad_timestamps <<<"${summary}"

  printf '== 検知レイテンシ（FR-DETECT-03）==\n'
  printf '対象ログ: %s\n' "$(printf '%s, ' "${log_files[@]}" | sed 's/, $//')"
  printf '始点: "%s" / 終点: "%s"（パネルの ID で組にする。間に "%s" か "%s" があれば組にしない）\n' \
    "${start_pattern}" "${end_pattern}" "${PANEL_GONE_PATTERN}" "${APP_LAUNCH_PATTERN}"
  printf 'start の行: %s 件、end の行: %s 件\n' "${starts}" "${ends}"
  if [[ "${bad_timestamps}" -gt 0 ]]; then
    warn "タイムスタンプを解釈できない行を ${bad_timestamps} 行飛ばしました"
  fi
  if [[ "${negative}" -gt 0 ]]; then
    warn "end の時刻が start より前になる組が ${negative} 件ありました（時計の変更等。集計から除きます）"
  fi

  # 終点のログを出さない古いビルドでも計測しようとしがちなため、始点も無いときもこちらを先に伝える
  if [[ "${ends}" -eq 0 ]]; then
    die_unmeasurable "終点の行（\"${end_pattern}\"）がログに 1 行も無いため計測できません。パレット表示時に \"${DEFAULT_END_PATTERN}\" を info で出すビルド（PR #69 以降）で計測し直すか、終点の文言が違う場合は --end-pattern で指定してください"
  fi
  [[ "${starts}" -gt 0 ]] || die_unmeasurable "始点の行（\"${start_pattern}\"）がログに 1 行もありません"

  local stats
  stats="$(printf '%s\n' "${pairing}" | awk '$1 == "latency" { print $2 }' | sort -n \
    | awk -v median="${MEDIAN_PERCENTILE}" -v tail="${TAIL_PERCENTILE}" "${PERCENTILE_AWK}")" \
    || die_unmeasurable "start と end を 1 組も組にできませんでした（組めなかった start: ${unpaired} 件）"
  local count p50 p95 maximum
  read -r count p50 p95 maximum <<<"${stats}"

  printf '組にできた件数: %s 件\n' "${count}"
  printf 'p50: %s ms\n' "${p50}"
  printf 'p95: %s ms（nearest-rank 法: 昇順に並べた ceil(0.95 × n) 番目の値）\n' "${p95}"
  printf '最大: %s ms\n' "${maximum}"
  printf '組めなかった start: %s 件（同じ ID の end より先に、同じ ID の start・"%s"・起動の行・ログの末尾が来た）\n' \
    "${unpaired}" "${PANEL_GONE_PATTERN}"
  # 同じパネルの再表示・ホットキーでの再表示でも end は出るため、警告にはしない
  printf '組にしなかった end: %s 件（組む start が無い。同じパネルの再表示・ホットキーでの再表示等）\n' "${orphan_ends}"
  printf '合格基準: p95 <= %s ms（組めなかった start が 0 件であること）\n' "${threshold_ms}"

  # パレットが出なかった検知を除いて p95 を出すと、表示の失敗を見逃して PASS にしてしまうため判定しない。
  # panel detected はイベントを渡す前にログに出るため、正常な操作では palette shown より後になることは無い
  if [[ "${unpaired}" -gt 0 ]]; then
    die_unmeasurable "パレットが出なかった検知（組めなかった start）が ${unpaired} 件あるため判定できません（上の p50 / p95 は組めた分だけの値）。パネルを開いたまま集計していないか、パレットが出ずに閉じたパネルが無いかを確かめ、S-01 だけを繰り返したログで測り直してください"
  fi

  local status="${EXIT_FAIL}"
  if awk -v value="${p95}" -v limit="${threshold_ms}" 'BEGIN { exit !(value <= limit) }'; then
    status="${EXIT_PASS}"
  fi
  print_verdict "${status}"
  exit "${status}"
}

main "$@"
