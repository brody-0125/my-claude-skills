#!/usr/bin/env bash
# Plugin Introspector — htop-style Dashboard
# Renders real-time token/tool usage in a terminal UI.
# Usage: dashboard.sh [session-id] [--compact|--full]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# Terminal colors
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
RESET='\033[0m'

# Bar chart renderer
render_bar() {
  local value=$1
  local max=$2
  local width=${3:-20}

  if [ "$max" -eq 0 ]; then
    printf '%*s' "$width" '' | tr ' ' '░'
    return
  fi

  local filled=$(( value * width / max ))
  if [ "$filled" -gt "$width" ]; then
    filled=$width
  fi
  local empty=$(( width - filled ))

  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
}

# Status indicator
status_icon() {
  local error_rate=$1
  if awk -v e="$error_rate" 'BEGIN {exit !(e > 10)}' 2>/dev/null; then
    echo -e "${RED}✗${RESET}"
  elif awk -v e="$error_rate" 'BEGIN {exit !(e > 5)}' 2>/dev/null; then
    echo -e "${YELLOW}⚠${RESET}"
  else
    echo -e "${GREEN}✓${RESET}"
  fi
}

render_dashboard() {
  local session_dir="$1"
  local mode="${2:-compact}"

  if [ ! -f "${session_dir}/stats.json" ]; then
    echo "No data available for this session."
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for dashboard rendering."
    return 1
  fi

  local stats
  stats=$(cat "${session_dir}/stats.json")

  # Extract top-level metrics
  local tool_calls
  tool_calls=$(echo "$stats" | jq '.tool_calls // 0')
  local total_tokens
  total_tokens=$(echo "$stats" | jq '.total_tokens_est // 0')
  local errors
  errors=$(echo "$stats" | jq '.errors // 0')
  local error_rate
  error_rate=$(echo "$stats" | jq -r '.error_rate // "0.0"')

  # Token budget (default 200k context window)
  local token_budget=200000
  local token_pct=$(( total_tokens * 100 / token_budget ))
  if [ "$token_pct" -gt 100 ]; then
    token_pct=100
  fi

  # Calculate duration (guard against zero/invalid start_ms)
  local start_ms
  start_ms=$(echo "$stats" | jq '.start_time_ms // 0')
  local now_ms
  now_ms=$(timestamp_ms)
  local duration_s=0
  if [ "${start_ms:-0}" -gt 0 ] && [ "$now_ms" -gt "$start_ms" ] 2>/dev/null; then
    duration_s=$(( (now_ms - start_ms) / 1000 ))
  fi
  local duration_fmt="${duration_s}s"
  if [ "$duration_s" -gt 60 ]; then
    duration_fmt="$(( duration_s / 60 ))m $(( duration_s % 60 ))s"
  fi

  # Header (clamp padding to avoid negative width in printf)
  local pad_width=$((10 - ${#duration_fmt}))
  [ "$pad_width" -lt 0 ] && pad_width=0
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  PLUGIN INTROSPECTOR DASHBOARD              Duration: ${duration_fmt}$(printf '%*s' "$pad_width" '')║${RESET}"
  echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${RESET}"

  # Token usage bar
  local token_bar
  token_bar=$(render_bar "$total_tokens" "$token_budget" 10)
  local token_pad=$((25 - ${#total_tokens} - ${#token_pct}))
  [ "$token_pad" -lt 0 ] && token_pad=0
  printf "${BOLD}║${RESET}  TOKENS:  [${token_bar}] %6d/%dk (%d%%)%*s${BOLD}║${RESET}\n" \
    "$total_tokens" "$((token_budget / 1000))" "$token_pct" \
    "$token_pad" ""

  # Summary line
  printf "${BOLD}║${RESET}  TOOLS:   %-4d calls  │  ERRORS: %d (%.1f%%)  │  ELAPSED: %-8s   ${BOLD}║${RESET}\n" \
    "$tool_calls" "$errors" "${error_rate}" "${duration_fmt}"

  echo -e "${BOLD}╠──────────────────────────────────────────────────────────────────╣${RESET}"

  # Per-tool breakdown
  local max_tool_tokens
  max_tool_tokens=$(echo "$stats" | jq '[.tools[].tokens] | max // 1')

  echo "$stats" | jq -r '.tools | to_entries | sort_by(-.value.tokens) | .[] | "\(.key) \(.value.calls) \(.value.tokens) \(.value.errors)"' | while read -r name calls tokens tool_errors; do
    local bar
    bar=$(render_bar "$tokens" "$max_tool_tokens" 16)
    local tool_err_rate="0.0"
    if [ "$calls" -gt 0 ]; then
      tool_err_rate=$(awk -v e="$tool_errors" -v c="$calls" 'BEGIN {printf "%.1f", c > 0 ? e * 100 / c : 0}')
    fi
    local icon
    icon=$(status_icon "$tool_err_rate")

    local tool_pad=$((6 - ${#tokens}))
    [ "$tool_pad" -lt 0 ] && tool_pad=0
    printf "${BOLD}║${RESET}  %-8s %3d  %6d tokens  [${bar}] %s%*s${BOLD}║${RESET}\n" \
      "$name" "$calls" "$tokens" "$icon" \
      "$tool_pad" ""
  done

  echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"

  # Full mode: show recent alerts
  if [ "$mode" = "full" ] && [ -f "${INTROSPECTOR_BASE}/alerts.jsonl" ]; then
    local alert_count
    alert_count=$(wc -l < "${INTROSPECTOR_BASE}/alerts.jsonl" 2>/dev/null || echo "0")
    if [ "$alert_count" -gt 0 ]; then
      echo ""
      echo -e "${BOLD}Recent Alerts:${RESET}"
      tail -5 "${INTROSPECTOR_BASE}/alerts.jsonl" | while IFS= read -r line; do
        local severity
        severity=$(echo "$line" | jq -r '.severity // "INFO"')
        local message
        message=$(echo "$line" | jq -r '.message // "Unknown alert"')
        local color="$RESET"
        case "$severity" in
          HIGH) color="$RED" ;;
          MEDIUM) color="$YELLOW" ;;
          LOW) color="$CYAN" ;;
        esac
        echo -e "  ${color}[${severity}]${RESET} ${message}"
      done
    fi
  fi
}

# Main
main() {
  local session_id="${1:-}"
  local mode="compact"

  # Parse args
  for arg in "$@"; do
    case "$arg" in
      --full) mode="full" ;;
      --compact) mode="compact" ;;
      *) session_id="$arg" ;;
    esac
  done

  local session_dir
  if [ -n "$session_id" ]; then
    session_dir="${INTROSPECTOR_BASE}/sessions/${session_id}"
  else
    session_dir=$(get_session_dir)
  fi

  if [ ! -d "$session_dir" ]; then
    echo "Session directory not found: $session_dir"
    echo "Available sessions:"
    ls "${INTROSPECTOR_BASE}/sessions/" 2>/dev/null || echo "  (none)"
    return 1
  fi

  render_dashboard "$session_dir" "$mode"
}

main "$@"
