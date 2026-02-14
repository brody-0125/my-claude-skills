#!/usr/bin/env bash
# Plugin Introspector — Tool Failure Trace Hook
# Records tool failures with error details, updates stats,
# and generates OTel ERROR span at Tier 0.
# Hook event: PostToolUseFailure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  # Self-referential guard
  if is_introspector_call; then
    return 0
  fi

  local session_dir
  session_dir=$(get_session_dir)
  [ -d "$session_dir" ] || return 0

  local tool_name="${CLAUDE_TOOL_NAME:-unknown}"
  local safe_tool
  safe_tool=$(sanitize_json_value "$tool_name" 50)
  local now
  now=$(timestamp_ms)

  # Retrieve correlated trace_id and start time (per-call keyed)
  local ckey
  ckey=$(correlation_key)
  local trace_id="unknown"
  [ -f "${session_dir}/.tid.${ckey}" ] && trace_id=$(cat "${session_dir}/.tid.${ckey}")
  local tstart=0
  [ -f "${session_dir}/.tstart.${ckey}" ] && tstart=$(cat "${session_dir}/.tstart.${ckey}")
  local duration_ms=$((now - tstart))

  # Extract error info (sanitized for safe JSON interpolation)
  local _res="${CLAUDE_TOOL_RESULT:-}"
  local result_chars=${#_res}
  local result_tokens
  result_tokens=$(estimate_tokens "$result_chars")
  local error_snippet
  error_snippet=$(sanitize_json_value "${CLAUDE_TOOL_RESULT:-}" 200)

  # Append failure trace
  append_jsonl "${session_dir}/tool_traces.jsonl" \
    "{\"type\":\"failure\",\"trace_id\":\"${trace_id}\",\"tool\":\"${safe_tool}\",\"timestamp_ms\":${now},\"duration_ms\":${duration_ms},\"result_tokens_est\":${result_tokens},\"has_error\":true,\"error_snippet\":\"${error_snippet}\"}"

  # Generate OTel span with ERROR status (Tier 0 only)
  local tier
  tier=$(detect_otel_tier)
  if [ "$tier" -eq 0 ]; then
    local _inp="${CLAUDE_TOOL_INPUT:-}"
    local input_chars=${#_inp}
    local input_tokens
    input_tokens=$(estimate_tokens "$input_chars")
    record_otel_span "$session_dir" "$tool_name" "$tstart" "$now" "$duration_ms" \
      "$input_tokens" "$result_tokens" "ERROR"
  fi

  # Update stats with error flag
  update_tool_stats "$session_dir" "$tool_name" "$result_tokens" "true" "$duration_ms"

  # Cleanup correlation files (per-call keyed)
  rm -f "${session_dir}/.tid.${ckey}" "${session_dir}/.tstart.${ckey}"
}

main "$@" 2>/dev/null || true
