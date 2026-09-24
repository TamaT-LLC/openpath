#!/usr/bin/env bash
# 実ユーザーのファイル（設定・履歴・ログ）に触れない計測用の openpath を起動・停止する（非機能テスト TST-001 §5）。
#
# 使い方:
#   scripts/measure-isolated.sh start [--candidates N] [--app PATH] [--settle-seconds S]
#   scripts/measure-isolated.sh stop <measure-dir> [--keep]
#
# start: 一時ディレクトリ（$TMPDIR/openpath-measure-TASK-030.XXXXXX）の home/ を一時 HOME にして設定ファイルを置き、
#   `open -n -g --env CFFIXED_USER_HOME=<一時 HOME>` で起動する。CoreFoundation のホーム（NSHomeDirectory）は
#   HOME ではなく CFFIXED_USER_HOME で差し替わるため、設定・履歴・ログはすべて一時 HOME 配下になる。ghq は無効にする。
#   --candidates N      roots から読み込ませる候補の数（ルート自身を含む）。既定 0（roots は空）。
#                       depth 2 以内のディレクトリだけのツリーを作る。ルートあたりの上限（20000 件）以上を指定すると、
#                       上限を少し超えるツリーを作って上限まで読み込ませ、ログに上限到達の警告が出たかを確かめる
#                       （1 ルートでは上限を超える件数は読み込まれない）
#   --app PATH          起動する .app（既定: build/openpath.app）
#   --settle-seconds S  起動後、候補の構築が落ち着くまで待つ最大秒数（既定 60。0 なら待たない）。
#                       累積 CPU 時間の増分が 5 秒間 0.02 秒以下になったら落ち着いたとみなす
#   標準出力に KEY=VALUE を出す（進捗は標準エラー）:
#     OPENPATH_PID / OPENPATH_MEASURE_DIR / OPENPATH_LOG / OPENPATH_HOME /
#     OPENPATH_CANDIDATES（読み込ませた候補数）/ OPENPATH_LIMIT_WARNING（上限到達の警告がログにあれば yes）
#   例: eval "$(scripts/measure-isolated.sh start --candidates 20000)"
#
# stop: start で保存した pid が、同じ実行ファイルで同じ CFFIXED_USER_HOME を持つプロセスであることを確かめてから
#   TERM で止め（5 秒で終わらなければ KILL）、計測ディレクトリを消す。
#   --keep  計測ディレクトリ（ログを含む）を消さずに残す
#
# アクセシビリティ権限の無い状態で動くため、パネルの検知（PanelWatcher）は動かない。
# 止めるのは start で起動した pid だけで、pkill / killall は使わない（並行して動く他の openpath を巻き込まないため）。
# start が途中で失敗・中断したときは、起動したプロセスを止めて計測ディレクトリを消す。
# 終了コード: 0 = 成功、0 以外 = 失敗
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=scripts/measure-common.sh
source "$(dirname "$0")/measure-common.sh"

# 1 ルートあたりの候補数の上限。Sources/OpenPathCore/CandidateSources/Roots/RootScanOptions.swift の defaultItemLimit と揃える
readonly ROOT_ITEM_LIMIT=20000
# 上限到達の警告は上限を超える項目が見つかったときにだけ出るため、上限より多めにディレクトリを作る
readonly LIMIT_OVERFLOW_MARGIN=100
# RootDirectoryScanner が上限に達したときに出す warning ログの文言（先頭部分）
readonly LIMIT_WARNING_TEXT="候補がルートあたりの上限"
readonly CANDIDATE_DEPTH=2
# depth 1 のディレクトリ 1 つあたりに作る depth 2 のディレクトリの数（20100 件なら 101 グループ × 200 件ほど）
readonly CHILDREN_PER_DIRECTORY=199

readonly MARKER_FILE_NAME=".openpath-measure-dir"
readonly PID_FILE_NAME="openpath.pid"
readonly EXECUTABLE_FILE_NAME="executable-path"
readonly HOME_DIR_NAME="home"
readonly TREE_DIR_NAME="candidates"
readonly CONFIG_RELATIVE_PATH=".config/${APP_NAME}/config.toml"
readonly LOG_RELATIVE_PATH="Library/Logs/${APP_NAME}/${APP_NAME}.log"
readonly HOME_OVERRIDE_VARIABLE="CFFIXED_USER_HOME"

readonly LAUNCH_TIMEOUT_SECONDS=15
readonly LAUNCH_POLL_SECONDS=0.2
readonly DEFAULT_SETTLE_SECONDS=60
readonly SETTLE_POLL_SECONDS=1
readonly SETTLE_QUIET_SECONDS=5
readonly SETTLE_QUIET_CPU_CENTISECONDS=2
readonly STOP_TIMEOUT_SECONDS=5
readonly STOP_POLL_SECONDS=0.2
readonly FAILURE_LOG_TAIL_LINES=20

# パスを TOML の文字列や ps -E の出力との照合にそのまま使うため、空白・引用符・バックスラッシュを含むパスは扱わない
readonly UNSAFE_PATH_PATTERN='[[:space:]"\\]'

# depth 1 の dNNNNN と、その下の dNNNNN/eNNN を行きがけ順にちょうど total 件出力する
readonly TREE_PATHS_AWK='
BEGIN {
  made = 0
  for (group = 1; made < total; group++) {
    parent = sprintf("d%05d", group)
    print parent
    made++
    for (child = 1; child <= children && made < total; child++) {
      printf "%s/e%03d\n", parent, child
      made++
    }
  }
}'

# start の途中で失敗したときの後始末に使う
MEASURE_DIR=""
LAUNCH_EXECUTABLE=""
LAUNCH_HOME=""
LAUNCHED_PID=""
LAUNCHED_AT_SECONDS=0
LIMIT_WARNING_FOUND="no"

# ---------------------------------------------------------------------------
# プロセスの特定

is_listed() {
  local value="$1"
  local list="$2"
  case $'\n'"${list}"$'\n' in
    *$'\n'"${value}"$'\n'*) return 0 ;;
  esac
  return 1
}

# 実行ファイルのパスが一致する pid を 1 行ずつ出力する
pids_of_executable() {
  local executable="$1"
  local pid
  for pid in $(pgrep -x "$(basename "${executable}")" || true); do
    if [[ "$(process_executable "${pid}" 2>/dev/null || true)" == "${executable}" ]]; then
      printf '%s\n' "${pid}"
    fi
  done
}

# 環境変数に CFFIXED_USER_HOME=<home> を持つか（自ユーザーのプロセスなら ps -E で環境変数が見える）
process_has_home() {
  local pid="$1"
  local home="$2"
  local command_and_environment
  command_and_environment="$(ps -wwE -o command= -p "${pid}" 2>/dev/null)" || return 1
  case " ${command_and_environment} " in
    *" ${HOME_OVERRIDE_VARIABLE}=${home} "*) return 0 ;;
  esac
  return 1
}

# excluded_pids に無く、一時 HOME を持つ pid を 1 行ずつ出力する
pids_with_home() {
  local executable="$1"
  local home="$2"
  local excluded_pids="$3"
  local pid
  for pid in $(pids_of_executable "${executable}"); do
    if ! is_listed "${pid}" "${excluded_pids}" && process_has_home "${pid}" "${home}"; then
      printf '%s\n' "${pid}"
    fi
  done
}

# ---------------------------------------------------------------------------
# 計測ディレクトリ

create_measure_dir() {
  local created
  created="$(mktemp -d "${TMPDIR:-/tmp}/${MEASURE_TEMP_PREFIX}.XXXXXX")" || die "一時ディレクトリを作れません"
  # 設定の roots やプロセスの環境変数と表記を揃えるため、/var → /private/var のようなシンボリックリンクを解決しておく
  MEASURE_DIR="$(cd "${created}" && pwd -P)"
  printf '%s\n' "scripts/measure-isolated.sh start が作成した計測ディレクトリ" >"${MEASURE_DIR}/${MARKER_FILE_NAME}"
  if [[ "${MEASURE_DIR}" =~ ${UNSAFE_PATH_PATTERN} ]]; then
    die "一時ディレクトリのパスに空白や引用符が含まれるため扱えません（TMPDIR を変えてください）: ${MEASURE_DIR}"
  fi
}

# 削除・停止の対象にしてよい計測ディレクトリかを確かめる（mktemp で作った名前と start が置いた目印のファイル）
require_measure_dir() {
  local dir="$1"
  [[ "${dir}" == /* ]] || die "計測ディレクトリは絶対パスで扱います: ${dir}"
  case "$(basename "${dir}")" in
    "${MEASURE_TEMP_PREFIX}".??????) ;;
    *) die "計測ディレクトリ（${MEASURE_TEMP_PREFIX}.XXXXXX）ではありません: ${dir}" ;;
  esac
  [[ -f "${dir}/${MARKER_FILE_NAME}" ]] || die "measure-isolated.sh start が作った計測ディレクトリではありません: ${dir}"
}

remove_measure_dir() {
  local dir="$1"
  require_measure_dir "${dir}"
  rm -rf "${dir}"
  log "計測ディレクトリを削除しました: ${dir}"
}

write_config() {
  local home="$1"
  local root="$2"
  local config_file="${home}/${CONFIG_RELATIVE_PATH}"
  local roots_value="[]"
  if [[ -n "${root}" ]]; then
    roots_value="[\"${root}\"]"
  fi
  mkdir -p "$(dirname "${config_file}")"
  cat >"${config_file}" <<EOF
# scripts/measure-isolated.sh が生成した計測用の設定
roots = ${roots_value}
depth = ${CANDIDATE_DEPTH}
include_files = false

[ghq]
enabled = false
EOF
}

# ルート自身を含めてちょうど item_count 件のディレクトリを作る
create_candidate_tree() {
  local tree_dir="$1"
  local item_count="$2"
  mkdir "${tree_dir}"
  local descendant_count=$((item_count - 1))
  if [[ "${descendant_count}" -gt 0 ]]; then
    # mkdir を 1 件ずつ呼ぶと遅いため、xargs で多数のパスをまとめて渡す
    (cd "${tree_dir}" \
      && awk -v total="${descendant_count}" -v children="${CHILDREN_PER_DIRECTORY}" "${TREE_PATHS_AWK}" \
      | xargs mkdir -p)
  fi

  local actual_count
  actual_count="$(find "${tree_dir}" -type d | wc -l | tr -d ' ')"
  [[ "${actual_count}" -eq "${item_count}" ]] \
    || die "候補のツリーが ${item_count} 件になりません（${actual_count} 件）: ${tree_dir}"
}

# ---------------------------------------------------------------------------
# 起動・停止

launch_app() {
  local app_dir="$1"
  local executable="$2"
  local home="$3"
  local existing_pids
  existing_pids="$(pids_of_executable "${executable}")"

  # 後始末（cleanup_failed_start）が起動したプロセスを探せるよう、open の前に記録する
  LAUNCH_EXECUTABLE="${executable}"
  LAUNCH_HOME="${home}"
  LAUNCHED_AT_SECONDS=${SECONDS}
  log "open -n -g --env ${HOME_OVERRIDE_VARIABLE}=${home} ${app_dir}"
  open -n -g --env "${HOME_OVERRIDE_VARIABLE}=${home}" "${app_dir}" || die "open で起動できません: ${app_dir}"

  local deadline=$((SECONDS + LAUNCH_TIMEOUT_SECONDS))
  local new_pids=""
  while [[ -z "${new_pids}" && ${SECONDS} -lt ${deadline} ]]; do
    sleep "${LAUNCH_POLL_SECONDS}"
    new_pids="$(pids_with_home "${executable}" "${home}" "${existing_pids}")"
  done
  [[ -n "${new_pids}" ]] \
    || die "${LAUNCH_TIMEOUT_SECONDS} 秒以内に ${HOME_OVERRIDE_VARIABLE}=${home} を持つ ${executable} のプロセスが見つかりません"

  local count
  count="$(printf '%s\n' "${new_pids}" | wc -l | tr -d ' ')"
  [[ "${count}" -eq 1 ]] || die "一時 HOME を持つプロセスが ${count} 個見つかりました: $(printf '%s ' "${new_pids}")"
  LAUNCHED_PID="${new_pids}"
}

# ログファイルが一時 HOME 配下にできることで、CFFIXED_USER_HOME が効いていることを確かめる
wait_for_log_file() {
  local pid="$1"
  local log_file="$2"
  local deadline=$((LAUNCHED_AT_SECONDS + LAUNCH_TIMEOUT_SECONDS))
  while [[ ! -s "${log_file}" ]]; do
    process_exists "${pid}" || die "pid ${pid} が起動直後に終了しました"
    [[ ${SECONDS} -lt ${deadline} ]] \
      || die "${LAUNCH_TIMEOUT_SECONDS} 秒以内に一時 HOME 配下にログができません（${HOME_OVERRIDE_VARIABLE} が効いていない可能性）: ${log_file}"
    sleep "${LAUNCH_POLL_SECONDS}"
  done
  log "一時 HOME 配下のログを確認しました: ${log_file}"
}

log_contains() {
  local log_file="$1"
  local text="$2"
  grep -F -q "${text}" "${log_file}" 2>/dev/null
}

# 累積 CPU 時間の増分が SETTLE_QUIET_SECONDS の間 SETTLE_QUIET_CPU_CENTISECONDS 以下になるまで待つ
wait_until_settled() {
  local pid="$1"
  local log_file="$2"
  local max_seconds="$3"
  local expects_limit_warning="$4"
  if [[ "${max_seconds}" -eq 0 ]]; then
    log "--settle-seconds 0 のため、候補の構築を待たずに進みます"
    return 0
  fi

  log "候補の構築が落ち着くのを待ちます（最大 ${max_seconds} 秒）"
  local deadline=$((SECONDS + max_seconds))
  local baseline_cpu baseline_seconds current_cpu
  baseline_cpu="$(cpu_time_centiseconds "${pid}")" || die "pid ${pid} が終了しました"
  baseline_seconds=${SECONDS}
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    sleep "${SETTLE_POLL_SECONDS}"
    current_cpu="$(cpu_time_centiseconds "${pid}")" || die "候補の構築を待つ間に pid ${pid} が終了しました"
    if [[ $((current_cpu - baseline_cpu)) -gt ${SETTLE_QUIET_CPU_CENTISECONDS} ]]; then
      baseline_cpu=${current_cpu}
      baseline_seconds=${SECONDS}
      continue
    fi
    if [[ $((SECONDS - baseline_seconds)) -lt ${SETTLE_QUIET_SECONDS} ]]; then
      continue
    fi
    if [[ "${expects_limit_warning}" == true ]] && ! log_contains "${log_file}" "${LIMIT_WARNING_TEXT}"; then
      continue
    fi
    log "落ち着きました（起動から約 $((SECONDS - LAUNCHED_AT_SECONDS)) 秒、累積 CPU 時間 $(format_centiseconds "${current_cpu}") 秒）"
    return 0
  done
  warn "--settle-seconds（${max_seconds} 秒）以内に落ち着きませんでした。このまま進みます"
}

check_limit_warning() {
  local log_file="$1"
  local expects_limit_warning="$2"
  local line
  line="$(grep -F -m 1 "${LIMIT_WARNING_TEXT}" "${log_file}" 2>/dev/null || true)"
  if [[ -n "${line}" ]]; then
    LIMIT_WARNING_FOUND="yes"
  fi

  if [[ "${expects_limit_warning}" != true ]]; then
    if [[ -n "${line}" ]]; then
      warn "上限未満のはずが、上限到達の警告がログにあります: ${line}"
    fi
    return 0
  fi
  if [[ -n "${line}" ]]; then
    log "上限到達の警告を確認しました（候補はルートあたり ${ROOT_ITEM_LIMIT} 件）: ${line}"
  else
    warn "上限到達の警告がログにありません。候補が ${ROOT_ITEM_LIMIT} 件に達していない可能性があります: ${log_file}"
  fi
}

wait_for_exit() {
  local pid="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))
  while process_exists "${pid}"; do
    [[ ${SECONDS} -lt ${deadline} ]] || return 1
    sleep "${STOP_POLL_SECONDS}"
  done
}

# 呼び出し側で自分が起動したプロセスであることを確かめてから呼ぶ
terminate_process() {
  local pid="$1"
  kill -TERM "${pid}" 2>/dev/null || true
  if wait_for_exit "${pid}" "${STOP_TIMEOUT_SECONDS}"; then
    log "pid ${pid} を止めました（TERM）"
    return 0
  fi
  warn "pid ${pid} が ${STOP_TIMEOUT_SECONDS} 秒で終わらないため KILL します"
  kill -KILL "${pid}" 2>/dev/null || true
  wait_for_exit "${pid}" "${STOP_TIMEOUT_SECONDS}" || die "pid ${pid} を止められません"
  log "pid ${pid} を止めました（KILL）"
}

# open の直後に中断されるとプロセスがまだ見えないことがあるため、起動を待つ時間の範囲で一時 HOME を持つ pid を探す
launched_pids_for_cleanup() {
  local deadline=$((LAUNCHED_AT_SECONDS + LAUNCH_TIMEOUT_SECONDS))
  local pids
  pids="$(pids_with_home "${LAUNCH_EXECUTABLE}" "${LAUNCH_HOME}" "")"
  while [[ -z "${pids}" && ${SECONDS} -lt ${deadline} ]]; do
    sleep "${LAUNCH_POLL_SECONDS}"
    pids="$(pids_with_home "${LAUNCH_EXECUTABLE}" "${LAUNCH_HOME}" "")"
  done
  if [[ -n "${pids}" ]]; then
    printf '%s\n' "${pids}"
  fi
}

# start の途中で失敗したら、一時 HOME を持つプロセス（自分が起動したもの）を止めて計測ディレクトリを消す
cleanup_failed_start() {
  local status=$?
  trap - EXIT
  if [[ -n "${LAUNCH_EXECUTABLE}" && -n "${LAUNCH_HOME}" ]]; then
    local pid
    for pid in $(launched_pids_for_cleanup); do
      terminate_process "${pid}" || true
    done
  fi
  local log_file="${LAUNCH_HOME}/${LOG_RELATIVE_PATH}"
  if [[ -n "${LAUNCH_HOME}" && -s "${log_file}" ]]; then
    printf -- '--- 計測用インスタンスのログ（末尾 %s 行）---\n' "${FAILURE_LOG_TAIL_LINES}" >&2
    tail -n "${FAILURE_LOG_TAIL_LINES}" "${log_file}" >&2 || true
  fi
  if [[ -n "${MEASURE_DIR}" ]]; then
    remove_measure_dir "${MEASURE_DIR}" || true
  fi
  exit "${status}"
}

# ---------------------------------------------------------------------------
# サブコマンド

start_command() {
  local candidates=0
  local app_path="${APP_BUNDLE}"
  local settle_seconds="${DEFAULT_SETTLE_SECONDS}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --candidates)
        require_option_value "$1" "$#"
        candidates="$2"
        shift 2
        ;;
      --app)
        require_option_value "$1" "$#"
        app_path="$2"
        shift 2
        ;;
      --settle-seconds)
        require_option_value "$1" "$#"
        settle_seconds="$2"
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
  is_non_negative_integer "${candidates}" || die "--candidates は 0 以上の整数で指定してください: ${candidates}"
  is_non_negative_integer "${settle_seconds}" || die "--settle-seconds は 0 以上の整数で指定してください: ${settle_seconds}"

  require_command open
  require_command pgrep
  require_command plutil
  require_command xargs
  require_app_bundle "${app_path}"
  local app_dir executable_name executable
  app_dir="$(cd "${app_path}" && pwd -P)"
  executable_name="$(plist_value "${app_dir}/Contents/Info.plist" CFBundleExecutable)" \
    || die "${app_dir}/Contents/Info.plist から CFBundleExecutable を読めません"
  executable="${app_dir}/Contents/MacOS/${executable_name}"
  [[ -x "${executable}" ]] || die "実行ファイルがありません: ${executable}"

  local loaded_candidates="${candidates}"
  local tree_item_count="${candidates}"
  local expects_limit_warning=false
  if [[ "${candidates}" -ge "${ROOT_ITEM_LIMIT}" ]]; then
    if [[ "${candidates}" -gt "${ROOT_ITEM_LIMIT}" ]]; then
      warn "1 ルートあたりの上限 ${ROOT_ITEM_LIMIT} 件を超えては読み込まれないため、${ROOT_ITEM_LIMIT} 件として扱います"
    fi
    loaded_candidates="${ROOT_ITEM_LIMIT}"
    tree_item_count=$((ROOT_ITEM_LIMIT + LIMIT_OVERFLOW_MARGIN))
    expects_limit_warning=true
  fi

  trap cleanup_failed_start EXIT
  exit_on_signals
  create_measure_dir
  local home="${MEASURE_DIR}/${HOME_DIR_NAME}"
  mkdir "${home}"
  local root=""
  if [[ "${tree_item_count}" -gt 0 ]]; then
    root="${MEASURE_DIR}/${TREE_DIR_NAME}"
    log "候補のツリーを作成: ${root}（ルート自身を含めて ${tree_item_count} 件、depth ${CANDIDATE_DEPTH}）"
    create_candidate_tree "${root}" "${tree_item_count}"
  fi
  write_config "${home}" "${root}"

  launch_app "${app_dir}" "${executable}" "${home}"
  printf '%s\n' "${LAUNCHED_PID}" >"${MEASURE_DIR}/${PID_FILE_NAME}"
  printf '%s\n' "${executable}" >"${MEASURE_DIR}/${EXECUTABLE_FILE_NAME}"
  log "pid ${LAUNCHED_PID} で起動しました"

  local log_file="${home}/${LOG_RELATIVE_PATH}"
  wait_for_log_file "${LAUNCHED_PID}" "${log_file}"
  wait_until_settled "${LAUNCHED_PID}" "${log_file}" "${settle_seconds}" "${expects_limit_warning}"
  check_limit_warning "${log_file}" "${expects_limit_warning}"
  process_exists "${LAUNCHED_PID}" || die "pid ${LAUNCHED_PID} が終了しました"
  trap - EXIT

  log "止めるとき: scripts/measure-isolated.sh stop ${MEASURE_DIR}"
  printf 'OPENPATH_PID=%q\n' "${LAUNCHED_PID}"
  printf 'OPENPATH_MEASURE_DIR=%q\n' "${MEASURE_DIR}"
  printf 'OPENPATH_LOG=%q\n' "${log_file}"
  printf 'OPENPATH_HOME=%q\n' "${home}"
  printf 'OPENPATH_CANDIDATES=%q\n' "${loaded_candidates}"
  printf 'OPENPATH_LIMIT_WARNING=%q\n' "${LIMIT_WARNING_FOUND}"
}

stop_command() {
  local measure_dir=""
  local keep=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)
        keep=true
        shift
        ;;
      -h | --help)
        print_usage "$0"
        exit 0
        ;;
      -*)
        die "不明な引数: $1（--help を参照）"
        ;;
      *)
        [[ -z "${measure_dir}" ]] || die "計測ディレクトリは 1 つだけ指定してください"
        measure_dir="$1"
        shift
        ;;
    esac
  done
  [[ -n "${measure_dir}" ]] || die "stop には計測ディレクトリ（start が出力した OPENPATH_MEASURE_DIR）を指定してください"
  [[ -d "${measure_dir}" ]] || die "計測ディレクトリがありません: ${measure_dir}"
  measure_dir="$(cd "${measure_dir}" && pwd -P)"
  require_measure_dir "${measure_dir}"

  local pid_file="${measure_dir}/${PID_FILE_NAME}"
  local executable_file="${measure_dir}/${EXECUTABLE_FILE_NAME}"
  [[ -f "${pid_file}" && -f "${executable_file}" ]] || die "pid の記録がありません: ${measure_dir}"
  local pid executable
  pid="$(cat "${pid_file}")"
  executable="$(cat "${executable_file}")"
  is_positive_integer "${pid}" || die "pid の記録が不正です: ${pid}"

  stop_launched_process "${pid}" "${executable}" "${measure_dir}/${HOME_DIR_NAME}"
  if [[ "${keep}" == true ]]; then
    log "計測ディレクトリを残しました: ${measure_dir}"
  else
    remove_measure_dir "${measure_dir}"
  fi
}

stop_launched_process() {
  local pid="$1"
  local executable="$2"
  local home="$3"
  local current_executable
  current_executable="$(process_executable "${pid}" 2>/dev/null || true)"
  if [[ -z "${current_executable}" ]]; then
    log "pid ${pid} は既に終了しています"
    return 0
  fi
  if [[ "${current_executable}" != "${executable}" ]] || ! process_has_home "${pid}" "${home}"; then
    process_exists "${pid}" || {
      log "pid ${pid} は既に終了しています"
      return 0
    }
    die "pid ${pid} は計測用に起動した ${APP_NAME} ではありません（pid が再利用された可能性）。止めずに終了します"
  fi
  terminate_process "${pid}"
}

main() {
  if [[ $# -eq 0 ]]; then
    print_usage "$0" >&2
    exit 1
  fi
  local subcommand="$1"
  shift
  case "${subcommand}" in
    start) start_command "$@" ;;
    stop) stop_command "$@" ;;
    -h | --help) print_usage "$0" ;;
    *) die "不明なサブコマンド: ${subcommand}（start か stop。--help を参照）" ;;
  esac
}

main "$@"
