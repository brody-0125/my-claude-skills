#!/usr/bin/env bash
# Plugin Introspector — Security Check Hook (PreToolUse)
# Analyzes tool calls for security risks before execution.
# Activated by PI_ENABLE_SECURITY=1 environment variable.
#
# Hook event: PreToolUse
# Output: JSON with permissionDecision when risk is CRITICAL.
#   Exit 2 = block the tool call (Claude Code hook protocol)
#
# This script MUST complete within 50ms to avoid UX impact.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  # Only active when explicitly enabled
  [ "${PI_ENABLE_SECURITY:-0}" = "1" ] || return 0

  # Self-referential guard
  if is_introspector_call; then
    return 0
  fi

  local tool_name="${CLAUDE_TOOL_NAME:-unknown}"
  local safe_tool
  safe_tool=$(sanitize_json_value "$tool_name" 50)
  local tool_input="${CLAUDE_TOOL_INPUT:-}"

  # Only inspect Bash, Write, and Edit tools
  case "$tool_name" in
    Bash|Write|Edit) ;;
    *) return 0 ;;
  esac

  local session_dir
  session_dir=$(get_session_dir)
  local now
  now=$(timestamp_ms)

  # ── Bash command analysis ─────────────────────────────
  if [ "$tool_name" = "Bash" ]; then
    local cmd=""
    if command -v jq &>/dev/null && [ -n "$tool_input" ]; then
      cmd=$(echo "$tool_input" | jq -r '.command // empty' 2>/dev/null)
    fi
    [ -n "$cmd" ] || return 0

    local risk_level
    risk_level=$(classify_command_risk "$cmd")

    # Log all non-LOW risk commands
    if [ "$risk_level" != "LOW" ]; then
      local safe_cmd
      safe_cmd=$(sanitize_json_value "$cmd" 300)
      append_jsonl "${session_dir}/security_events.jsonl" \
        "{\"timestamp_ms\":${now},\"type\":\"pre_command_check\",\"risk_level\":\"${risk_level}\",\"command\":\"${safe_cmd}\",\"action\":\"$([ "$risk_level" = "CRITICAL" ] && [ "${PI_SECURITY_BLOCK:-0}" = "1" ] && echo "blocked" || echo "logged")\"}"
    fi

    # DLP check on command input (may contain embedded secrets)
    local dlp_findings
    dlp_findings=$(detect_sensitive_data "$cmd")
    if [ -n "$dlp_findings" ]; then
      local sid
      sid=$(get_session_id)
      local safe_sid
      safe_sid=$(sanitize_json_value "$sid" 100)
      local safe_dlp
      safe_dlp=$(sanitize_json_value "$dlp_findings" 200)
      append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
        "{\"timestamp\":\"$(timestamp_iso)\",\"session_id\":\"${safe_sid}\",\"severity\":\"HIGH\",\"type\":\"dlp_input\",\"message\":\"Sensitive data in Bash command: ${safe_dlp}\",\"tool\":\"Bash\"}"
    fi

    # Block CRITICAL commands (only when PI_SECURITY_BLOCK=1)
    if [ "$risk_level" = "CRITICAL" ] && [ "${PI_SECURITY_BLOCK:-0}" = "1" ]; then
      local sid
      sid=$(get_session_id)
      local safe_sid
      safe_sid=$(sanitize_json_value "$sid" 100)
      append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
        "{\"timestamp\":\"$(timestamp_iso)\",\"session_id\":\"${safe_sid}\",\"severity\":\"CRITICAL\",\"type\":\"command_blocked\",\"message\":\"Blocked CRITICAL risk command: $(sanitize_json_value "$cmd" 100)\",\"tool\":\"Bash\"}"

      # Output deny decision (Claude Code hook protocol)
      echo "{\"permissionDecision\":\"deny\",\"reason\":\"Plugin Introspector: CRITICAL risk command blocked. Set PI_SECURITY_BLOCK=0 to allow.\"}"
      exit 2
    fi
  fi

  # ── Write/Edit file path analysis ─────────────────────
  if [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ]; then
    local file_path=""
    if command -v jq &>/dev/null && [ -n "$tool_input" ]; then
      file_path=$(echo "$tool_input" | jq -r '.file_path // .path // empty' 2>/dev/null)
    fi
    [ -n "$file_path" ] || return 0

    # Check for writes to sensitive locations
    local write_risk="LOW"
    case "$file_path" in
      */.ssh/*|*/.aws/*|*/.gnupg/*) write_risk="CRITICAL" ;;
      */.env|*/.env.*) write_risk="HIGH" ;;
      */etc/passwd|*/etc/shadow) write_risk="CRITICAL" ;;
      */.github/*|*/Dockerfile*) write_risk="MEDIUM" ;;
      */auth/*|*/permission*/*|*/security/*) write_risk="MEDIUM" ;;
    esac

    if [ "$write_risk" != "LOW" ]; then
      local safe_path
      safe_path=$(sanitize_json_value "$file_path" 300)
      append_jsonl "${session_dir}/security_events.jsonl" \
        "{\"timestamp_ms\":${now},\"type\":\"sensitive_write\",\"risk_level\":\"${write_risk}\",\"file_path\":\"${safe_path}\",\"tool\":\"${safe_tool}\"}"

      # Block CRITICAL write targets
      if [ "$write_risk" = "CRITICAL" ] && [ "${PI_SECURITY_BLOCK:-0}" = "1" ]; then
        local sid
        sid=$(get_session_id)
        local safe_sid
        safe_sid=$(sanitize_json_value "$sid" 100)
        append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
          "{\"timestamp\":\"$(timestamp_iso)\",\"session_id\":\"${safe_sid}\",\"severity\":\"CRITICAL\",\"type\":\"write_blocked\",\"message\":\"Blocked write to sensitive path: ${safe_path}\",\"tool\":\"${safe_tool}\"}"

        echo "{\"permissionDecision\":\"deny\",\"reason\":\"Plugin Introspector: Write to sensitive path blocked.\"}"
        exit 2
      fi
    fi
  fi
}

main "$@" 2>/dev/null || true
