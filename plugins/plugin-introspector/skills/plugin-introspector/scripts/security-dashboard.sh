#!/usr/bin/env bash
# Plugin Introspector — Security Dashboard
# Renders a security-focused view of the session with risk scores,
# DLP violations, command audit, and sensitive file access.
# Usage: security-dashboard.sh [session-id]

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
WHITE='\033[37m'
RESET='\033[0m'

risk_color() {
  case "$1" in
    CRITICAL) echo -e "${RED}" ;;
    HIGH)     echo -e "${RED}" ;;
    MEDIUM)   echo -e "${YELLOW}" ;;
    LOW)      echo -e "${GREEN}" ;;
    CLEAN)    echo -e "${GREEN}" ;;
    *)        echo -e "${WHITE}" ;;
  esac
}

risk_bar() {
  local score=$1
  local max=50
  local filled=$((score * 5))
  [ "$filled" -gt "$max" ] && filled=$max
  local empty=$((max - filled))

  local color
  if [ "$score" -ge 8 ]; then color="${RED}";
  elif [ "$score" -ge 4 ]; then color="${YELLOW}";
  else color="${GREEN}"; fi

  printf "${color}"
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf "${DIM}"
  printf '%*s' "$empty" '' | tr ' ' '-'
  printf "${RESET}"
}

render_security_dashboard() {
  local session_dir="$1"

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for security dashboard." >&2
    return 1
  fi

  local stats_file="${session_dir}/stats.json"
  local sec_events="${session_dir}/security_events.jsonl"
  local tool_traces="${session_dir}/tool_traces.jsonl"
  local alerts_file="${INTROSPECTOR_BASE}/alerts.jsonl"

  if [ ! -f "$stats_file" ]; then
    echo "No session data available."
    return 1
  fi

  local stats
  stats=$(cat "$stats_file")
  local sid
  sid=$(basename "$(dirname "$stats_file")" 2>/dev/null || echo "unknown")
  # Correct: session dir is sessions/{sid}, so get basename of session_dir
  sid=$(basename "$session_dir")

  # ── Compute security metrics ───────────────────────────
  local tool_calls
  tool_calls=$(echo "$stats" | jq '.tool_calls // 0')
  local errors
  errors=$(echo "$stats" | jq '.errors // 0')

  # Count security events
  local dlp_violations=0
  local cmd_risks_critical=0
  local cmd_risks_high=0
  local cmd_risks_medium=0
  local sensitive_writes=0
  local blocked_count=0

  if [ -f "$sec_events" ]; then
    dlp_violations=$(grep -c '"dlp_output"' "$sec_events" 2>/dev/null || echo 0)
    cmd_risks_critical=$(grep -c '"CRITICAL"' "$sec_events" 2>/dev/null || echo 0)
    cmd_risks_high=$(grep -c '"HIGH"' "$sec_events" 2>/dev/null || echo 0)
    cmd_risks_medium=$(grep -c '"MEDIUM"' "$sec_events" 2>/dev/null || echo 0)
    sensitive_writes=$(grep -c '"sensitive_write"' "$sec_events" 2>/dev/null || echo 0)
    blocked_count=$(grep -c '"blocked"' "$sec_events" 2>/dev/null || echo 0)
  fi

  # Count session alerts
  local session_alerts=0
  if [ -f "$alerts_file" ]; then
    session_alerts=$(grep -c "\"$sid\"" "$alerts_file" 2>/dev/null || echo 0)
  fi

  # Bash command counts from tool_traces
  local bash_calls=0
  local network_cmds=0
  local sensitive_reads=0
  if [ -f "$tool_traces" ]; then
    bash_calls=$(grep -c '"tool":"Bash"' "$tool_traces" 2>/dev/null || echo 0)
    # Count sensitive reads by input_summary patterns
    sensitive_reads=$(grep -cE '"input_summary":"[^"]*\.(env|ssh|aws|secret|credential)' "$tool_traces" 2>/dev/null || echo 0)
  fi

  # Calculate risk score
  local risk_score=$((cmd_risks_critical * 10 + cmd_risks_high * 5 + cmd_risks_medium * 2 + dlp_violations * 10 + sensitive_writes * 3 + sensitive_reads * 2))

  local risk_level="CLEAN"
  if [ "$risk_score" -ge 31 ]; then risk_level="CRITICAL"
  elif [ "$risk_score" -ge 16 ]; then risk_level="HIGH"
  elif [ "$risk_score" -ge 6 ]; then risk_level="MEDIUM"
  elif [ "$risk_score" -ge 1 ]; then risk_level="LOW"
  fi

  local rc
  rc=$(risk_color "$risk_level")

  # ── Render dashboard ───────────────────────────────────
  echo -e "${BOLD}+==================================================================+${RESET}"
  echo -e "${BOLD}|  SECURITY DASHBOARD                  Risk: ${rc}${risk_level}${RESET}$(printf '%*s' $((8 - ${#risk_level})) '')Score: ${risk_score}${BOLD}  |${RESET}"
  echo -e "${BOLD}+==================================================================+${RESET}"
  echo -e "${BOLD}|${RESET}                                                                  ${BOLD}|${RESET}"

  # Risk bar
  printf "${BOLD}|${RESET}  Risk Score: ["
  risk_bar "$risk_score"
  printf "] %2d/50" "$risk_score"
  printf "%*s${BOLD}|${RESET}\n" 4 ""

  echo -e "${BOLD}|${RESET}                                                                  ${BOLD}|${RESET}"

  # Session summary
  echo -e "${BOLD}|${RESET}  Session: ${CYAN}${sid}${RESET}$(printf '%*s' $((40 - ${#sid})) '')${BOLD}|${RESET}"
  printf "${BOLD}|${RESET}  Tool Calls: %-4d  |  Bash: %-4d  |  Errors: %-4d            ${BOLD}|${RESET}\n" \
    "$tool_calls" "$bash_calls" "$errors"

  echo -e "${BOLD}+------------------------------------------------------------------+${RESET}"

  # Security findings
  echo -e "${BOLD}|${RESET}  ${BOLD}Security Findings:${RESET}                                            ${BOLD}|${RESET}"

  local dlp_c
  dlp_c=$([ "$dlp_violations" -gt 0 ] && echo "${RED}" || echo "${GREEN}")
  printf "${BOLD}|${RESET}  ${dlp_c}DLP Violations:     %3d${RESET}                                       ${BOLD}|${RESET}\n" "$dlp_violations"

  local sr_c
  sr_c=$([ "$sensitive_reads" -gt 0 ] && echo "${YELLOW}" || echo "${GREEN}")
  printf "${BOLD}|${RESET}  ${sr_c}Sensitive Reads:    %3d${RESET}                                       ${BOLD}|${RESET}\n" "$sensitive_reads"

  local sw_c
  sw_c=$([ "$sensitive_writes" -gt 0 ] && echo "${YELLOW}" || echo "${GREEN}")
  printf "${BOLD}|${RESET}  ${sw_c}Sensitive Writes:   %3d${RESET}                                       ${BOLD}|${RESET}\n" "$sensitive_writes"

  local cc_c
  cc_c=$([ "$cmd_risks_critical" -gt 0 ] && echo "${RED}" || echo "${GREEN}")
  printf "${BOLD}|${RESET}  ${cc_c}Critical Commands:  %3d${RESET}                                       ${BOLD}|${RESET}\n" "$cmd_risks_critical"

  local hc_c
  hc_c=$([ "$cmd_risks_high" -gt 0 ] && echo "${RED}" || echo "${GREEN}")
  printf "${BOLD}|${RESET}  ${hc_c}High-Risk Commands: %3d${RESET}                                       ${BOLD}|${RESET}\n" "$cmd_risks_high"

  local bl_c
  bl_c=$([ "$blocked_count" -gt 0 ] && echo "${RED}" || echo "${GREEN}")
  printf "${BOLD}|${RESET}  ${bl_c}Blocked Actions:    %3d${RESET}                                       ${BOLD}|${RESET}\n" "$blocked_count"

  printf "${BOLD}|${RESET}  Session Alerts:    %3d                                       ${BOLD}|${RESET}\n" "$session_alerts"

  echo -e "${BOLD}+------------------------------------------------------------------+${RESET}"

  # Recent security events (last 5)
  if [ -f "$sec_events" ]; then
    local event_count
    event_count=$(wc -l < "$sec_events" 2>/dev/null || echo 0)
    if [ "$event_count" -gt 0 ]; then
      echo -e "${BOLD}|${RESET}  ${BOLD}Recent Security Events:${RESET}                                        ${BOLD}|${RESET}"
      tail -5 "$sec_events" 2>/dev/null | while IFS= read -r line; do
        local etype rlevel
        etype=$(echo "$line" | jq -r '.type // "unknown"' 2>/dev/null)
        rlevel=$(echo "$line" | jq -r '.risk_level // .severity // "INFO"' 2>/dev/null)
        local ec
        ec=$(risk_color "$rlevel")
        local edesc=""
        case "$etype" in
          dlp_output)       edesc="DLP: sensitive data in output" ;;
          dlp_input)        edesc="DLP: sensitive data in command" ;;
          command_risk)     edesc="Risky command detected" ;;
          pre_command_check) edesc="Pre-exec risk check" ;;
          sensitive_write)  edesc="Sensitive file write" ;;
          *)                edesc="$etype" ;;
        esac
        printf "${BOLD}|${RESET}  ${ec}[%-8s]${RESET} %-48s${BOLD}|${RESET}\n" "$rlevel" "$edesc"
      done
      echo -e "${BOLD}+------------------------------------------------------------------+${RESET}"
    fi
  fi

  # Recent alerts for this session
  if [ -f "$alerts_file" ] && [ "$session_alerts" -gt 0 ]; then
    echo -e "${BOLD}|${RESET}  ${BOLD}Session Alerts:${RESET}                                                ${BOLD}|${RESET}"
    grep "\"$sid\"" "$alerts_file" 2>/dev/null | tail -5 | while IFS= read -r line; do
      local sev msg
      sev=$(echo "$line" | jq -r '.severity // "INFO"' 2>/dev/null)
      msg=$(echo "$line" | jq -r '.message // "Unknown"' 2>/dev/null | head -c 48)
      local ac
      ac=$(risk_color "$sev")
      printf "${BOLD}|${RESET}  ${ac}[%-8s]${RESET} %-48s${BOLD}|${RESET}\n" "$sev" "$msg"
    done
    echo -e "${BOLD}+------------------------------------------------------------------+${RESET}"
  fi

  # Configuration status
  echo -e "${BOLD}|${RESET}  ${BOLD}Security Config:${RESET}                                               ${BOLD}|${RESET}"
  local dlp_status="OFF"
  [ "${PI_ENABLE_DLP:-0}" = "1" ] && dlp_status="${GREEN}ON${RESET}" || dlp_status="${DIM}OFF${RESET}"
  local sec_status="OFF"
  [ "${PI_ENABLE_SECURITY:-0}" = "1" ] && sec_status="${GREEN}ON${RESET}" || sec_status="${DIM}OFF${RESET}"
  local block_status="OFF"
  [ "${PI_SECURITY_BLOCK:-0}" = "1" ] && block_status="${RED}ON (blocking)${RESET}" || block_status="${DIM}OFF (logging only)${RESET}"

  echo -e "${BOLD}|${RESET}  DLP:             ${dlp_status}$(printf '%*s' 38 '')${BOLD}|${RESET}"
  echo -e "${BOLD}|${RESET}  Security Check:  ${sec_status}$(printf '%*s' 38 '')${BOLD}|${RESET}"
  echo -e "${BOLD}|${RESET}  Command Block:   ${block_status}$(printf '%*s' 26 '')${BOLD}|${RESET}"

  echo -e "${BOLD}+==================================================================+${RESET}"
}

# Main
main() {
  local session_id="${1:-}"

  local session_dir
  if [ -n "$session_id" ]; then
    session_dir="${INTROSPECTOR_BASE}/sessions/${session_id}"
  else
    session_dir=$(get_session_dir)
  fi

  if [ ! -d "$session_dir" ]; then
    echo "Session directory not found: $session_dir" >&2
    return 1
  fi

  render_security_dashboard "$session_dir"
}

main "$@"
