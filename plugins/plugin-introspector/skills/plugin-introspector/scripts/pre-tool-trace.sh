#!/usr/bin/env bash
# Plugin Introspector — Pre-Tool Trace Hook
# Records tool invocation start with trace ID, input_summary, and timestamp.
# Hook event: PreToolUse

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  # Self-referential guard
  if is_introspector_call; then
    return 0
  fi

  local session_dir
  session_dir=$(get_session_dir)

  local tool_name="${CLAUDE_TOOL_NAME:-unknown}"
  local safe_tool
  safe_tool=$(sanitize_json_value "$tool_name" 50)
  local trace_id
  trace_id=$(generate_id)
  local ts_ms
  ts_ms=$(timestamp_ms)

  # Estimate input size
  local _inp="${CLAUDE_TOOL_INPUT:-}"
  local input_chars=${#_inp}
  local input_tokens
  input_tokens=$(estimate_tokens "$input_chars")

  # Extract tool-specific context summary
  local input_summary
  input_summary=$(extract_input_summary "$tool_name")

  # Create trace record
  append_jsonl "${session_dir}/tool_traces.jsonl" \
    "{\"type\":\"pre\",\"trace_id\":\"${trace_id}\",\"tool\":\"${safe_tool}\",\"timestamp_ms\":${ts_ms},\"input_tokens_est\":${input_tokens},\"input_summary\":\"${input_summary}\"}"

  # Store correlation data for post-tool hook (per-call keyed to avoid parallel race)
  local ckey
  ckey=$(correlation_key)
  echo "$trace_id" > "${session_dir}/.tid.${ckey}"
  echo "$ts_ms" > "${session_dir}/.tstart.${ckey}"
}

main "$@" 2>/dev/null || true
