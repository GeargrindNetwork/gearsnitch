#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-summary}"
WINDOW="${2:-10m}"
LINES="${LINES:-200}"
LOG_DIR="${LOG_DIR:-/tmp/gearsnitch-logs}"
IOS_PREDICATE='subsystem == "com.gearsnitch"'

latest_log_file() {
  local pattern="$1"
  local matches=()
  shopt -s nullglob
  matches=("${LOG_DIR}"/${pattern})
  shopt -u nullglob

  if [[ ${#matches[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${matches[@]}" | xargs ls -1t 2>/dev/null | head -n 1
}

print_header() {
  printf '\n=== %s ===\n' "$1"
}

show_ios_logs() {
  /usr/bin/log show --style compact --last "${WINDOW}" --predicate "${IOS_PREDICATE}" || true
}

stream_ios_logs() {
  /usr/bin/log stream --style compact --level debug --predicate "${IOS_PREDICATE}"
}

show_api_errors() {
  local file
  file="$(latest_log_file 'error-*.log' || true)"
  if [[ -z "${file:-}" ]]; then
    echo "No API error log file found in ${LOG_DIR}"
    return 0
  fi

  tail -n "${LINES}" "${file}"
}

follow_api_errors() {
  local file
  file="$(latest_log_file 'error-*.log' || true)"
  if [[ -z "${file:-}" ]]; then
    echo "No API error log file found in ${LOG_DIR}"
    return 0
  fi

  tail -F "${file}"
}

case "${MODE}" in
  ios-stream)
    stream_ios_logs
    ;;
  ios-last)
    show_ios_logs
    ;;
  api-errors)
    show_api_errors
    ;;
  api-follow)
    follow_api_errors
    ;;
  summary)
    print_header "iOS unified logs (${WINDOW})"
    show_ios_logs
    print_header "API error logs"
    show_api_errors
    ;;
  *)
    echo "Usage: bash scripts/feed-error-logs.sh [summary|ios-stream|ios-last|api-errors|api-follow] [window]"
    exit 1
    ;;
esac
