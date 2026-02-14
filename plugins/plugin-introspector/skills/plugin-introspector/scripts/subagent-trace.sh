#!/usr/bin/env bash
# Plugin Introspector — Sub-agent Trace Hook
# Records sub-agent execution traces. Generates OTel span at Tier 0 only.
# Hook event: SubagentStop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  local session_dir
  session_dir=$(get_session_dir)
  [ -d "$session_dir" ] || return 0

  local now
  now=$(timestamp_ms)

  # Extract sub-agent info from environment (sanitized for JSON safety)
  local agent_name
  agent_name=$(sanitize_json_value "${CLAUDE_AGENT_NAME:-unknown}" 100)
  local agent_type
  agent_type=$(sanitize_json_value "${CLAUDE_AGENT_TYPE:-unknown}" 50)

  # Estimate result tokens
  local _res="${CLAUDE_TOOL_RESULT:-}"
  local result_chars=${#_res}
  local result_tokens
  result_tokens=$(estimate_tokens "$result_chars")

  # Append sub-agent trace record
  append_jsonl "${session_dir}/tool_traces.jsonl" \
    "{\"type\":\"subagent\",\"timestamp_ms\":${now},\"agent_name\":\"${agent_name}\",\"agent_type\":\"${agent_type}\",\"result_tokens_est\":${result_tokens}}"

  # Generate OTel span (Tier 0 only)
  # Note: SubagentStart hook doesn't exist, so start_time is unavailable
  local tier
  tier=$(detect_otel_tier)
  if [ "$tier" -eq 0 ]; then
    local sid
    sid=$(get_session_id)
    local trace_id
    if command -v md5sum &>/dev/null; then
      trace_id=$(printf '%s' "$sid" | md5sum 2>/dev/null | head -c 32)
    elif command -v md5 &>/dev/null; then
      trace_id=$(printf '%s' "$sid" | md5 2>/dev/null | head -c 32)
    else
      trace_id=$(printf '%s' "$sid" | cksum 2>/dev/null | cut -d' ' -f1 | head -c 32)
    fi
    local span_id
    span_id=$(generate_id)
    local parent_span_id=""
    [ -f "${session_dir}/.parent_span" ] && parent_span_id=$(cat "${session_dir}/.parent_span")

    append_jsonl "${session_dir}/otel_traces.jsonl" \
      "{\"trace_id\":\"${trace_id}\",\"span_id\":\"${span_id}\",\"parent_span_id\":\"${parent_span_id}\",\"name\":\"gen_ai.invoke_agent ${agent_name}\",\"kind\":\"INTERNAL\",\"start_time_ms\":0,\"end_time_ms\":${now},\"duration_ms\":0,\"attributes\":{\"gen_ai.operation.name\":\"gen_ai.invoke_agent\",\"gen_ai.agent.name\":\"${agent_name}\",\"gen_ai.agent.type\":\"${agent_type}\",\"gen_ai.usage.output_tokens\":${result_tokens}},\"status\":\"OK\",\"_incomplete\":true,\"_note\":\"start_time/duration unavailable - SubagentStart hook does not exist in Claude Code\"}"
  fi

  # Update stats (duration 0 since SubagentStart hook does not exist)
  update_tool_stats "$session_dir" "Subagent:${agent_name}" "$result_tokens" "false" "0"
}

main "$@" 2>/dev/null || true
