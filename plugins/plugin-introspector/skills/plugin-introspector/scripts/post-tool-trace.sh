#!/usr/bin/env bash
# Plugin Introspector — Post-Tool Trace Hook
# Records tool result (duration, tokens, status), updates stats,
# and generates OTel span at Tier 0.
# Hook event: PostToolUse

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

  # Estimate result size
  local _res="${CLAUDE_TOOL_RESULT:-}"
  local result_chars=${#_res}
  local result_tokens
  result_tokens=$(estimate_tokens "$result_chars")

  # Append tool trace
  local trace_file="${session_dir}/tool_traces.jsonl"
  append_jsonl "$trace_file" \
    "{\"type\":\"post\",\"trace_id\":\"${trace_id}\",\"tool\":\"${safe_tool}\",\"timestamp_ms\":${now},\"duration_ms\":${duration_ms},\"result_tokens_est\":${result_tokens},\"has_error\":false}"

  # P1 Optimization: In-session rotation to prevent unbounded growth
  # Uses PID-unique temp file to avoid TOCTOU race with parallel tool calls
  local line_count
  line_count=$(( $(wc -l < "$trace_file" 2>/dev/null || echo 0) + 0 ))
  if [ "$line_count" -gt 1000 ]; then
    local tmp_rot="${trace_file}.rot.$$"
    if tail -800 "${trace_file}" > "${tmp_rot}" 2>/dev/null; then
      mv "${tmp_rot}" "${trace_file}" 2>/dev/null || rm -f "${tmp_rot}"
    else
      rm -f "${tmp_rot}"
    fi
    append_jsonl "$trace_file" "{\"type\":\"rotation\",\"timestamp_ms\":${now},\"rotated_lines\":$((line_count - 800))}"
  fi

  # Generate OTel span (Tier 0 only — native OTel handles this at Tier 1+)
  local tier
  tier=$(detect_otel_tier)
  if [ "$tier" -eq 0 ]; then
    local _inp="${CLAUDE_TOOL_INPUT:-}"
    local input_chars=${#_inp}
    local input_tokens
    input_tokens=$(estimate_tokens "$input_chars")
    record_otel_span "$session_dir" "$tool_name" "$tstart" "$now" "$duration_ms" \
      "$input_tokens" "$result_tokens" "OK"
  fi

  # Update stats
  update_tool_stats "$session_dir" "$tool_name" "$result_tokens" "false" "$duration_ms"

  # DLP check on tool output (PI_ENABLE_DLP=1 activates)
  local dlp_findings
  dlp_findings=$(detect_sensitive_data "${CLAUDE_TOOL_RESULT:-}")
  if [ -n "$dlp_findings" ]; then
    local sid
    sid=$(get_session_id)
    local safe_sid
    safe_sid=$(sanitize_json_value "$sid" 100)
    local ts
    ts=$(timestamp_iso)
    local safe_dlp
    safe_dlp=$(sanitize_json_value "$dlp_findings" 200)
    append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
      "{\"timestamp\":\"${ts}\",\"session_id\":\"${safe_sid}\",\"severity\":\"CRITICAL\",\"type\":\"dlp_violation\",\"message\":\"Sensitive data in tool output: ${safe_dlp}\",\"tool\":\"${safe_tool}\",\"findings\":\"${safe_dlp}\"}"
    append_jsonl "${session_dir}/security_events.jsonl" \
      "{\"timestamp_ms\":${now},\"type\":\"dlp_output\",\"tool\":\"${safe_tool}\",\"findings\":\"${safe_dlp}\",\"trace_id\":\"${trace_id}\"}"
  fi

  # Note: Command risk classification is handled by security-check.sh (PreToolUse).
  # Removed duplicate classification here to avoid double-counting in security_events.jsonl.

  # Cleanup correlation files (per-call keyed)
  rm -f "${session_dir}/.tid.${ckey}" "${session_dir}/.tstart.${ckey}"
}

main "$@" 2>/dev/null || true
