#!/usr/bin/env bash
# Plugin Introspector — Session Start Hook
# Creates session directory, records initial metadata, and detects collection tier.
# Hook event: SessionStart

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

show_reminder() {
  # Output reminder to stdout (injected into Claude context)
  # Disable with PI_SHOW_REMINDER=0
  if [ "${PI_SHOW_REMINDER:-1}" = "1" ]; then
    cat <<'REMINDER'

━━━ Plugin Introspector v1.0.0 ━━━
Commands: /plugin-introspector [status|dashboard|tokens|security-scan|quick-scan]
Tip: Use when analyzing plugin behavior or optimizing token usage.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REMINDER
  fi
}

main() {
  local session_dir
  session_dir=$(get_session_dir)

  # P2 Optimization: Cache session directory for faster resolution in subsequent hooks
  # Atomic write via tmp+mv to prevent partial reads by concurrent hooks
  echo "$session_dir" > "${INTROSPECTOR_BASE}/.current_session.tmp" && mv "${INTROSPECTOR_BASE}/.current_session.tmp" "${INTROSPECTOR_BASE}/.current_session"

  local sid
  sid=$(get_session_id)
  local working_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local start_ms
  start_ms=$(timestamp_ms)

  # Detect collection tier
  local tier
  tier=$(detect_otel_tier)

  # Collect git metadata
  local git_branch=""
  local git_commit=""
  if command -v git &>/dev/null; then
    git_branch=$(git -C "$working_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    git_commit=$(git -C "$working_dir" rev-parse --short HEAD 2>/dev/null || echo "")
  fi

  # Sanitize values for safe JSON interpolation
  local safe_dir
  safe_dir=$(sanitize_json_value "$working_dir" 500)
  local safe_branch
  safe_branch=$(sanitize_json_value "$git_branch" 200)
  local safe_commit
  safe_commit=$(sanitize_json_value "$git_commit" 40)

  # Sanitize session ID for safe JSON embedding
  local safe_sid
  safe_sid=$(sanitize_json_value "$sid" 100)

  # Write session metadata
  echo "{\"session_id\":\"${safe_sid}\",\"start_time\":\"$(timestamp_iso)\",\"start_time_ms\":${start_ms},\"working_dir\":\"${safe_dir}\",\"git_branch\":\"${safe_branch}\",\"git_commit\":\"${safe_commit}\",\"collection_tier\":${tier},\"platform\":\"$(uname -s)\"}" \
    > "${session_dir}/meta.json"

  # Initialize empty trace files
  touch "${session_dir}/tool_traces.jsonl"
  touch "${session_dir}/api_traces.jsonl"
  touch "${session_dir}/otel_traces.jsonl"

  # Initialize stats
  write_stats "$session_dir" "{\"tool_calls\":0,\"total_tokens_est\":0,\"errors\":0,\"start_time_ms\":${start_ms},\"tools\":{}}"

  # Show reminder (outputs to stdout for Claude context injection)
  show_reminder
}

main "$@" 2>/dev/null || true
