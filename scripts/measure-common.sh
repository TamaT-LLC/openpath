# 非機能テストの計測スクリプト（scripts/measure-*.sh）が source する共通処理。単体では実行しない。
# scripts/lib/common.sh を source した後に source する。macOS 標準の bash 3.2 で動くように書く。
# 定数は source した側のスクリプトで使うため、このファイル単体では未使用に見える（SC2034）。
# shellcheck shell=bash disable=SC2034

# 判定の終了コード。common.sh の die は終了コード 1 で FAIL と区別できないため、計測できないときは die_unmeasurable を使う
readonly EXIT_PASS=0
readonly EXIT_FAIL=1
readonly EXIT_UNMEASURABLE=2
# シグナルで中断されたときの終了コード（128 + シグナル番号の慣例に合わせる）
readonly EXIT_STATUS_INTERRUPTED=130
readonly EXIT_STATUS_TERMINATED=143

# 一時ファイル・一時ディレクトリの名前の接頭辞。計測タスク（PROJ-REQ-001-TASK-030）の作業物と分かるようにする
readonly MEASURE_TEMP_PREFIX="openpath-measure-TASK-030"

# Activity Monitor・footprint と同じく 1 MB = 1,048,576 バイトとする
readonly BYTES_PER_KIBIBYTE=1024
readonly BYTES_PER_MEBIBYTE=$((BYTES_PER_KIBIBYTE * BYTES_PER_KIBIBYTE))
readonly CENTISECONDS_PER_SECOND=100

readonly POSITIVE_INTEGER_PATTERN='^[1-9][0-9]*$'
readonly NON_NEGATIVE_INTEGER_PATTERN='^[0-9]+$'
readonly NON_NEGATIVE_DECIMAL_PATTERN='^[0-9]+([.][0-9]+)?$'

# ps -o time（[[dd-]hh:]mm:ss.ss、user + sys の累積 CPU 時間）を 1/100 秒単位の整数にする
# awk のプログラムなのでシェルでは展開しない
# shellcheck disable=SC2016
readonly CPU_TIME_TO_CENTISECONDS_AWK='
{
  value = $1
  days = 0
  dash = index(value, "-")
  if (dash > 0) {
    days = substr(value, 1, dash - 1)
    value = substr(value, dash + 1)
  }
  count = split(value, parts, ":")
  seconds = 0
  for (i = 1; i <= count; i++) {
    seconds = seconds * 60 + parts[i]
  }
  printf "%d\n", (days * 86400 + seconds) * centiseconds_per_second + 0.5
}'

# resolve_target_pid が設定する計測対象
TARGET_PID=""
TARGET_EXECUTABLE=""
TARGET_START_TIME=""

die_unmeasurable() {
  printf 'error: %s\n' "$*" >&2
  exit "${EXIT_UNMEASURABLE}"
}

is_positive_integer() {
  [[ "$1" =~ ${POSITIVE_INTEGER_PATTERN} ]]
}

is_non_negative_integer() {
  [[ "$1" =~ ${NON_NEGATIVE_INTEGER_PATTERN} ]]
}

is_non_negative_decimal() {
  [[ "$1" =~ ${NON_NEGATIVE_DECIMAL_PATTERN} ]]
}

# 値を取るオプションの値があるかを確かめる。引数: オプション名、残りの引数の数
require_option_value() {
  local option_name="$1"
  local remaining_count="$2"
  [[ "${remaining_count}" -ge 2 ]] || die_unmeasurable "${option_name} に値がありません（--help を参照）"
}

process_exists() {
  ps -p "$1" -o pid= >/dev/null 2>&1
}

# 起動時刻。計測の前後で比べ、pid が別のプロセスに再利用されていないことを確かめる
process_start_time() {
  ps -o lstart= -p "$1"
}

# 実行ファイルの絶対パス（macOS の ps -o comm は実行ファイルのパスを返す。長いパスが切れないよう -ww を付ける）
process_executable() {
  ps -ww -o comm= -p "$1"
}

# Ctrl-C や TERM で中断されても EXIT の trap（後始末）が動くよう、シグナルを exit に置き換える
exit_on_signals() {
  # 定数なので trap を設定する時点で展開してよい
  # shellcheck disable=SC2064
  trap "exit ${EXIT_STATUS_INTERRUPTED}" INT
  # shellcheck disable=SC2064
  trap "exit ${EXIT_STATUS_TERMINATED}" TERM
}

# 1/100 秒単位の累積 CPU 時間（user + sys）。プロセスが無ければ失敗する
cpu_time_centiseconds() {
  local pid="$1"
  local cpu_time
  cpu_time="$(ps -o time= -p "${pid}")" || return 1
  printf '%s\n' "${cpu_time}" | awk -v centiseconds_per_second="${CENTISECONDS_PER_SECOND}" "${CPU_TIME_TO_CENTISECONDS_AWK}"
}

# --pid の値（空なら openpath という名前のプロセスがちょうど 1 つあるときにそれ）を計測対象にし、TARGET_* を設定する。
# 呼び出し側の変数を設定するため $(...) の中では呼ばない
resolve_target_pid() {
  local requested_pid="$1"
  if [[ -n "${requested_pid}" ]]; then
    is_positive_integer "${requested_pid}" || die_unmeasurable "--pid は正の整数で指定してください: ${requested_pid}"
    process_exists "${requested_pid}" || die_unmeasurable "pid ${requested_pid} のプロセスがありません"
    TARGET_PID="${requested_pid}"
  else
    TARGET_PID="$(find_single_app_pid)"
  fi

  TARGET_EXECUTABLE="$(process_executable "${TARGET_PID}")" \
    || die_unmeasurable "pid ${TARGET_PID} の実行ファイルを取得できません"
  TARGET_START_TIME="$(process_start_time "${TARGET_PID}")" \
    || die_unmeasurable "pid ${TARGET_PID} の起動時刻を取得できません"
  if [[ "$(basename "${TARGET_EXECUTABLE}")" != "${APP_NAME}" ]]; then
    warn "pid ${TARGET_PID} は ${APP_NAME} ではありません（${TARGET_EXECUTABLE}）。そのまま計測します"
  fi
}

# openpath という名前のプロセスがちょうど 1 つならその pid を出力する。0 個・複数ならエラーで終える
find_single_app_pid() {
  local pids
  pids="$(pgrep -x "${APP_NAME}" || true)"
  [[ -n "${pids}" ]] \
    || die_unmeasurable "${APP_NAME} のプロセスがありません（--pid で指定するか、scripts/measure-isolated.sh start で起動してください）"

  local count
  count="$(printf '%s\n' "${pids}" | wc -l | tr -d ' ')"
  if [[ "${count}" -ne 1 ]]; then
    printf '%s の候補（pid 実行ファイル）:\n' "${APP_NAME}" >&2
    ps -ww -o pid=,comm= -p "$(printf '%s\n' "${pids}" | paste -s -d , -)" >&2 || true
    die_unmeasurable "${APP_NAME} のプロセスが ${count} 個あります。--pid で指定してください"
  fi
  printf '%s\n' "${pids}"
}

# 計測を始めたときと同じプロセスがまだ動いているか
is_target_still_running() {
  process_exists "${TARGET_PID}" || return 1
  [[ "$(process_start_time "${TARGET_PID}")" == "${TARGET_START_TIME}" ]]
}

now_iso8601() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

# 1/100 秒単位の整数を秒（小数 2 桁）にする
format_centiseconds() {
  awk -v value="$1" -v unit="${CENTISECONDS_PER_SECOND}" 'BEGIN { printf "%.2f\n", value / unit }'
}

bytes_to_mebibytes() {
  awk -v bytes="$1" -v unit="${BYTES_PER_MEBIBYTE}" 'BEGIN { printf "%.2f\n", bytes / unit }'
}

# 判定を出力する。引数: EXIT_PASS か EXIT_FAIL。終了は呼び出し側で `exit "${status}"` として行う
print_verdict() {
  local status="$1"
  if [[ "${status}" -eq "${EXIT_PASS}" ]]; then
    printf '判定: PASS\n'
  else
    printf '判定: FAIL\n'
  fi
}
