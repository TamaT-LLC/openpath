#!/usr/bin/env bash
# openpath がフォルダ選択のダイアログを検知するかを確かめるスモークテスト（TST-001 §4）。
#
# 使い方: scripts/smoke-open-panel.sh [--app PATH] [--log PATH] [--timeout SECONDS]
#   --app      起動中であることを確かめる openpath.app（既定: build/openpath.app）
#   --log      openpath のログファイル（既定: ~/Library/Logs/openpath/openpath.log）
#   --timeout  ダイアログを出してから panel detected を待つ秒数（既定: 15）
#
# 前提: アクセシビリティ権限を付与した openpath.app を起動しておくこと。このスクリプトはアプリを起動も終了もしない。
#
# 手順:
#   1. openpath が起動していて、ログの最新の起動以降で権限があり、パネルを監視中であることを確かめる
#   2. osascript の `choose folder` でフォルダ選択のダイアログを別プロセスで出す
#      （初回起動の案内の「試してみる」と同じ方式。キー操作の送出や他のアプリへの Apple Events は使わない）
#   3. 開始時点以降のログに panel detected が出るまで待つ。palette shown も出れば、検知からの時間を出す
#   4. osascript を終了してダイアログを閉じ、panel gone が出ることを確かめる
#
# openpath は最前面のアプリのパネルだけを検知する。端末から起動した osascript は最前面にならないことがあるため、
# ダイアログが最前面でなければクリックして前面に出すよう案内して待つ。
#
# 終了コード: 0 = OK / 1 = NG / 2 = 前提不足（アプリ未起動・ログ無し・権限なし・監視停止中・引数の誤り）
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

readonly EXIT_OK=0
readonly EXIT_NG=1
readonly EXIT_PRECONDITION=2

readonly DEFAULT_LOG_FILE="${HOME}/Library/Logs/${APP_NAME}/${APP_NAME}.log"
readonly DEFAULT_DETECT_TIMEOUT_SECONDS=15
readonly PALETTE_TIMEOUT_SECONDS=2
readonly GONE_TIMEOUT_SECONDS=5
readonly POLL_INTERVAL_SECONDS=0.1
readonly FRONTMOST_HINT_DELAY_SECONDS=2
# FR-DETECT-03（検知からパレット表示まで 300ms 以下）。1 回の計測なので判定には使わず、超えたら知らせるだけにする
readonly LATENCY_BUDGET_MS=300
readonly USER_CANCELED_ERROR_NUMBER="-128"
readonly DIALOG_PROMPT="openpath のスモークテストです。パレットが出ないときはこのダイアログをクリックしてください（自動で閉じます）"

# ログの文言（Sources の Log.info と一致させる）。起動の行は「[INFO] openpath 0.1.0 を起動します」
readonly LAUNCH_PREFIX="] ${APP_NAME} "
readonly LAUNCH_SUFFIX=" を起動します"
readonly TERMINATED_MESSAGE="] ${APP_NAME} を終了します"
readonly LAUNCHED_WITH_PERMISSION="起動処理を終えました（アクセシビリティ権限: あり）"
readonly LAUNCHED_WITHOUT_PERMISSION="起動処理を終えました（アクセシビリティ権限: なし）"
readonly PERMISSION_GRANTED="アクセシビリティ権限が付与されました"
readonly PERMISSION_REVOKED="アクセシビリティ権限が取り消されました"
readonly WATCH_STARTED="パネルの監視を始めました"
readonly WATCH_STOPPED="パネルの監視を止めました"
readonly PANEL_DETECTED="panel detected"
readonly PANEL_UPDATED="panel updated"
readonly PANEL_GONE="panel gone"
readonly PALETTE_SHOWN="palette shown"
readonly DIRECTORIES_ONLY_MARK="directoriesOnly: true"

app_path="${APP_BUNDLE}"
log_file="${DEFAULT_LOG_FILE}"
detect_timeout="${DEFAULT_DETECT_TIMEOUT_SECONDS}"
start_offset=0
dialog_pid=""
dialog_stderr=""
detected_entry=""

# 判定の結果は標準出力に 1 行で出す。経過は common.sh の log / warn で標準エラーに出す
finish_ok() {
  printf 'OK\n'
  exit "${EXIT_OK}"
}

fail_ng() {
  printf 'NG: %s\n' "$*"
  exit "${EXIT_NG}"
}

fail_precondition() {
  printf '前提不足: %s\n' "$*"
  exit "${EXIT_PRECONDITION}"
}

usage_error() {
  printf 'error: %s（使い方は --help）\n' "$*" >&2
  exit "${EXIT_PRECONDITION}"
}

cleanup() {
  if [[ -n "${dialog_pid}" ]]; then
    kill "${dialog_pid}" 2>/dev/null || true
    wait "${dialog_pid}" 2>/dev/null || true
  fi
  if [[ -n "${dialog_stderr}" ]]; then
    rm -f "${dialog_stderr}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --app | --log | --timeout)
        [[ $# -ge 2 ]] || usage_error "$1 に値がありません"
        case "$1" in
          --app) app_path="$2" ;;
          --log) log_file="$2" ;;
          --timeout) detect_timeout="$2" ;;
        esac
        shift 2
        ;;
      -h | --help)
        print_usage "$0"
        exit "${EXIT_OK}"
        ;;
      *)
        usage_error "不明な引数: $1"
        ;;
    esac
  done
  [[ "${detect_timeout}" =~ ^[1-9][0-9]*$ ]] || usage_error "--timeout には 1 以上の整数（秒）を指定してください: ${detect_timeout}"
}

require_tools() {
  local tool
  for tool in osascript lsappinfo plutil; do
    command -v "${tool}" >/dev/null 2>&1 || fail_precondition "${tool} が見つかりません（macOS で実行してください）"
  done
}

# 指定の .app が起動していることを確かめる。同じ bundle id の別の場所の .app が起動していたら前提不足とする
check_app_running() {
  [[ -d "${app_path}" ]] || fail_precondition "${app_path} がありません。scripts/build.sh && scripts/sign.sh でビルドするか、--app で指定してください"
  local info_plist="${app_path}/Contents/Info.plist"
  local bundle_id executable version
  bundle_id="$(plist_value "${info_plist}" CFBundleIdentifier)" || fail_precondition "${info_plist} から bundle id を読めません"
  executable="$(plist_value "${info_plist}" CFBundleExecutable)" || fail_precondition "${info_plist} から実行ファイル名を読めません"
  version="$(plist_value "${info_plist}" CFBundleShortVersionString)" || version="不明"

  local pid
  pid="$(lsappinfo info -only pid -app "${bundle_id}" | sed -n 's/^"pid"=\([0-9][0-9]*\)$/\1/p')" || pid=""
  [[ -n "${pid}" ]] || fail_precondition "${app_path##*/} が起動していません。open ${app_path} で起動してから実行してください"

  local expected running
  expected="$(cd "${app_path}" && pwd -P)/Contents/MacOS/${executable}"
  running="$(lsappinfo info -only executablepath -app "${bundle_id}" | sed -n 's/^"CFBundleExecutablePath"="\(.*\)"$/\1/p')" || running=""
  if [[ -n "${running}" && "${running}" != "${expected}" ]]; then
    fail_precondition "起動中の ${APP_NAME} は別の場所のものです（${running%/Contents/MacOS/*}）。その .app を --app で指定してください"
  fi
  log "${app_path##*/} ${version}（pid ${pid}）が起動しています / macOS $(sw_vers -productVersion)"
}

# 最新の起動以降の行から「権限 監視」を求める（例: "granted watching"）。起動の記録が無ければ "missing"、
# 最新の起動の後に終了が記録されていれば "terminated"（起動中のインスタンスがこのログに書いていない）。
# ローテーションで起動の行が .1 に移っていることがあるため、.1 から続けて読む
read_log_state() {
  {
    if [[ -f "${log_file}.1" ]]; then
      cat "${log_file}.1"
    fi
    cat "${log_file}"
  } | awk \
    -v launch_prefix="${LAUNCH_PREFIX}" -v launch_suffix="${LAUNCH_SUFFIX}" \
    -v launched_yes="${LAUNCHED_WITH_PERMISSION}" -v launched_no="${LAUNCHED_WITHOUT_PERMISSION}" \
    -v granted="${PERMISSION_GRANTED}" -v revoked="${PERMISSION_REVOKED}" \
    -v started="${WATCH_STARTED}" -v stopped="${WATCH_STOPPED}" -v terminated_message="${TERMINATED_MESSAGE}" '
    index($0, launch_prefix) && substr($0, length($0) - length(launch_suffix) + 1) == launch_suffix {
      found = 1; terminated = 0; permission = "unknown"; watching = "stopped"; next
    }
    !found { next }
    index($0, terminated_message) { terminated = 1 }
    index($0, launched_yes) || index($0, granted) { permission = "granted" }
    index($0, launched_no) { permission = "denied" }
    index($0, revoked) { permission = "revoked" }
    index($0, started) { watching = "watching" }
    index($0, stopped) { watching = "stopped" }
    END { if (!found) print "missing"; else if (terminated) print "terminated"; else print permission, watching }
  '
}

check_log_state() {
  [[ -f "${log_file}" ]] || fail_precondition "ログファイル ${log_file} がありません。${APP_NAME}.app を起動してから実行してください"
  local state
  state="$(read_log_state)"
  case "${state}" in
    missing)
      fail_precondition "ログに ${APP_NAME} の起動の記録がありません（${log_file}）"
      ;;
    terminated)
      fail_precondition "ログの最新の記録が ${APP_NAME} の終了です。起動中の ${APP_NAME} がこのログに書いていません（--log を確かめるか、${APP_NAME} を起動し直してください）"
      ;;
    "unknown "*)
      fail_precondition "ログに起動処理の完了が記録されていません。起動を終えてから実行してください"
      ;;
    "denied "*)
      fail_precondition "アクセシビリティ権限がありません（ログ: 「${LAUNCHED_WITHOUT_PERMISSION}」）。システム設定で ${APP_NAME} を許可してから実行してください"
      ;;
    "revoked "*)
      fail_precondition "アクセシビリティ権限が取り消されています（ログ: 「${PERMISSION_REVOKED}」）。システム設定で ${APP_NAME} を許可し直してから実行してください"
      ;;
    "granted stopped")
      fail_precondition "パネルの監視が止まっています（ログ: 「${WATCH_STOPPED}」）。メニューの「有効」にチェックを入れてから実行してください"
      ;;
    "granted watching")
      log "ログ: 最新の起動以降でアクセシビリティ権限あり・パネルの監視中"
      ;;
    *)
      fail_precondition "ログの状態を判別できません: ${state}"
      ;;
  esac
}

file_size() {
  stat -f %z "$1"
}

# 開始時点のオフセット以降に追記された行を出す。途中でローテーションされたら .1 の残りから続けて出す
new_log_lines() {
  local size
  size="$(file_size "${log_file}" 2>/dev/null)" || size=0
  if [[ "${size}" -lt "${start_offset}" ]]; then
    if [[ -f "${log_file}.1" ]]; then
      tail -c "+$((start_offset + 1))" "${log_file}.1" || true
    fi
    cat "${log_file}" 2>/dev/null || true
  else
    tail -c "+$((start_offset + 1))" "${log_file}" || true
  fi
}

# 開始以降の after 行目より後で、message を含む最初の行を「行番号<TAB>行」で出す。無ければ何も出さない。
# awk を途中で終えると書き込み側が SIGPIPE で失敗し得るため、最後まで読む。
# 呼び出し側は $(...) の代入で使うため、読めなくても失敗扱い（set -e での終了）にしない
find_line_after() {
  local message="$1"
  local after="$2"
  new_log_lines | awk -v message="${message}" -v after="${after}" '
    !printed && NR > after && index($0, message) { print NR "\t" $0; printed = 1 }
  ' || true
}

line_number_of() {
  printf '%s\n' "${1%%$'\t'*}"
}

line_text_of() {
  printf '%s\n' "${1#*$'\t'}"
}

timestamp_of() {
  local text
  text="$(line_text_of "$1")"
  printf '%s\n' "${text%% *}"
}

# ログの時刻（例: 2026-09-24T01:32:19.977+09:00）をエポックからのミリ秒にする
to_epoch_ms() {
  local timestamp="$1"
  [[ "${timestamp}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}(Z|[+-][0-9]{2}:[0-9]{2})$ ]] || return 1
  local seconds_part="${timestamp%%.*}"
  local fraction="${timestamp#*.}"
  local millis="${fraction:0:3}"
  local zone="${fraction:3}"
  if [[ "${zone}" == "Z" ]]; then
    zone="+0000"
  else
    zone="${zone/:/}"
  fi
  local epoch
  epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${seconds_part}${zone}" +%s 2>/dev/null)" || return 1
  printf '%d\n' "$((epoch * 1000 + 10#${millis}))"
}

is_dialog_frontmost() {
  local front_asn front_pid
  front_asn="$(lsappinfo front)" || return 1
  front_pid="$(lsappinfo info -only pid "${front_asn}" | sed -n 's/^"pid"=\([0-9][0-9]*\)$/\1/p')" || return 1
  [[ -n "${front_pid}" && "${front_pid}" == "${dialog_pid}" ]]
}

open_dialog() {
  start_offset="$(file_size "${log_file}")"
  dialog_stderr="$(mktemp "${TMPDIR:-/tmp}/openpath-smoke-TASK-029.XXXXXX")"
  osascript -e "choose folder with prompt \"${DIALOG_PROMPT}\"" >/dev/null 2>"${dialog_stderr}" &
  dialog_pid=$!
  log "フォルダ選択のダイアログを出しました（osascript pid ${dialog_pid}）。panel detected を最大 ${detect_timeout} 秒待ちます"
}

# 検知より先にダイアログが閉じた。キャンセル・選択は NG、ダイアログを出せなかったのは前提不足とする
dialog_exited_early() {
  local status=0
  wait "${dialog_pid}" || status=$?
  dialog_pid=""
  local detail
  detail="$(tr '\n' ' ' <"${dialog_stderr}")"
  if [[ "${status}" -eq 0 ]]; then
    fail_ng "panel detected が出る前にダイアログでフォルダが選ばれ、ダイアログが閉じました"
  fi
  if grep -q -- "${USER_CANCELED_ERROR_NUMBER}" "${dialog_stderr}"; then
    fail_ng "panel detected が出る前にダイアログがキャンセルされました"
  fi
  fail_precondition "フォルダ選択のダイアログが ${PANEL_DETECTED} の前に終了しました（osascript の終了コード ${status}${detail:+: ${detail}}）。GUI にログインしているユーザーで実行しているか確かめてください"
}

# 終了した子プロセスは親が回収するまでゾンビとして残り kill -0 が成功するため、状態を見る
is_dialog_running() {
  local state
  state="$(ps -o stat= -p "${dialog_pid}" 2>/dev/null)" || return 1
  [[ -n "${state}" && "${state}" != *Z* ]]
}

# 締め切り（SECONDS の値）。SECONDS は整数秒で進むため 1 秒足し、少なくとも seconds 秒は待つようにする
deadline_after() {
  printf '%d\n' "$((SECONDS + $1 + 1))"
}

# panel detected の行を detected_entry に入れる。時間内に出なければ空のまま。
# 検知より先にダイアログが閉じたら dialog_exited_early で終える（子プロセスを wait するため、$(...) で呼ばない）
wait_for_detection() {
  local deadline hint_at
  deadline="$(deadline_after "${detect_timeout}")"
  hint_at="$(deadline_after "${FRONTMOST_HINT_DELAY_SECONDS}")"
  local is_hinted=0
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    detected_entry="$(find_line_after "${PANEL_DETECTED}" 0)"
    if [[ -n "${detected_entry}" ]]; then
      return 0
    fi
    if ! is_dialog_running; then
      dialog_exited_early
    fi
    if [[ "${is_hinted}" -eq 0 && "${SECONDS}" -ge "${hint_at}" ]] && ! is_dialog_frontmost; then
      warn "ダイアログが最前面ではないようです。${APP_NAME} は最前面のアプリのパネルだけを検知するため、ダイアログをクリックしてください"
      is_hinted=1
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

# after 行目より後で message を含む行を、timeout 秒まで待って出す。出なければ何も出さない
wait_for_line_after() {
  local message="$1"
  local after="$2"
  local deadline entry
  deadline="$(deadline_after "$3")"
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    entry="$(find_line_after "${message}" "${after}")"
    if [[ -n "${entry}" ]]; then
      printf '%s\n' "${entry}"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

report_palette_latency() {
  local detection="$1"
  local palette_entry
  palette_entry="$(wait_for_line_after "${PALETTE_SHOWN}" "$(line_number_of "${detection}")" "${PALETTE_TIMEOUT_SECONDS}")"
  if [[ -z "${palette_entry}" ]]; then
    warn "${PALETTE_TIMEOUT_SECONDS} 秒以内に ${PALETTE_SHOWN} がログに出ませんでした（このビルドが出力しないか、パレットが出ていません）。検知だけで判定します"
    return 0
  fi
  local detected_ms shown_ms
  if ! detected_ms="$(to_epoch_ms "$(timestamp_of "${detection}")")" \
    || ! shown_ms="$(to_epoch_ms "$(timestamp_of "${palette_entry}")")"; then
    warn "ログの時刻を読めないため、レイテンシを計算できません"
    return 0
  fi
  local latency_ms=$((shown_ms - detected_ms))
  log "${PALETTE_SHOWN}: $(timestamp_of "${palette_entry}")（${PANEL_DETECTED} から ${latency_ms}ms）"
  if [[ "${latency_ms}" -gt "${LATENCY_BUDGET_MS}" ]]; then
    warn "検知からパレット表示まで ${LATENCY_BUDGET_MS}ms を超えました（1 回の計測。p95 は TST-001 §5 の方法で確かめてください）"
  fi
}

# choose folder はフォルダのみのパネル。選択モードは後から推定し直されることがある（panel updated）ため、判定には使わない
report_selection_mode() {
  local detection="$1"
  if [[ "$(line_text_of "${detection}")" == *"${DIRECTORIES_ONLY_MARK}"* ]]; then
    return 0
  fi
  local updated_entry
  updated_entry="$(find_line_after "${PANEL_UPDATED}" "$(line_number_of "${detection}")")"
  if [[ "$(line_text_of "${updated_entry}")" == *"${DIRECTORIES_ONLY_MARK}"* ]]; then
    log "選択モードはフォルダのみに推定し直されました: $(timestamp_of "${updated_entry}")"
    return 0
  fi
  warn "フォルダのみのパネルと判定されていません（${DIRECTORIES_ONLY_MARK} ではない）。パレットの候補にファイルが混ざっていないか確かめてください"
}

close_dialog() {
  kill "${dialog_pid}" 2>/dev/null || true
  wait "${dialog_pid}" 2>/dev/null || true
  dialog_pid=""
  log "osascript を終了してダイアログを閉じました。${PANEL_GONE} を最大 ${GONE_TIMEOUT_SECONDS} 秒待ちます"
}

main() {
  parse_args "$@"
  require_tools
  check_app_running
  check_log_state

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  open_dialog

  wait_for_detection
  if [[ -z "${detected_entry}" ]]; then
    fail_ng "${detect_timeout} 秒以内に ${PANEL_DETECTED} がログに出ませんでした（ダイアログを最前面にしたか、disabled_apps・ログのレベルを確かめてください）"
  fi
  local detected_text
  detected_text="$(line_text_of "${detected_entry}")"
  log "${PANEL_DETECTED}: $(timestamp_of "${detected_entry}")${detected_text#*"${PANEL_DETECTED}"}"
  report_selection_mode "${detected_entry}"
  report_palette_latency "${detected_entry}"

  close_dialog
  local gone_entry
  gone_entry="$(wait_for_line_after "${PANEL_GONE}" "$(line_number_of "${detected_entry}")" "${GONE_TIMEOUT_SECONDS}")"
  if [[ -z "${gone_entry}" ]]; then
    fail_ng "ダイアログを閉じてから ${GONE_TIMEOUT_SECONDS} 秒以内に ${PANEL_GONE} がログに出ませんでした"
  fi
  log "${PANEL_GONE}: $(timestamp_of "${gone_entry}")"
  finish_ok
}

main "$@"
