#!/usr/bin/env bash
# Plugin Introspector — API Trace Hook
# Records API request/response metrics from Notification events.
# At Tier 1+, native OTel captures API metrics more accurately;
# this hook still records for real-time stats compatibility.
# Hook event: Notification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  local session_dir
  session_dir=$(get_session_dir)

  local now
  now=$(timestamp_ms)

  # Extract available metrics from notification
  local notification="${CLAUDE_NOTIFICATION:-}"
  local input_tokens=0
  local output_tokens=0
  local model=""
  local latency_ms=0
  local stop_reason=""

  if [ -n "$notification" ] && command -v jq &>/dev/null; then
    input_tokens=$(echo "$notification" | jq -r '.input_tokens // .usage.input_tokens // 0' 2>/dev/null || echo "0")
    output_tokens=$(echo "$notification" | jq -r '.output_tokens // .usage.output_tokens // 0' 2>/dev/null || echo "0")
    model=$(echo "$notification" | jq -r '.model // ""' 2>/dev/null || echo "")
    latency_ms=$(echo "$notification" | jq -r '.latency_ms // .duration_ms // 0' 2>/dev/null || echo "0")
    stop_reason=$(echo "$notification" | jq -r '.stop_reason // ""' 2>/dev/null || echo "")
  fi

  # Sanitize string values for safe JSON interpolation
  model=$(sanitize_json_value "$model" 100)
  stop_reason=$(sanitize_json_value "$stop_reason" 50)

  # Append API trace record
  append_jsonl "${session_dir}/api_traces.jsonl" \
    "{\"type\":\"api\",\"timestamp_ms\":${now},\"model\":\"${model}\",\"input_tokens\":${input_tokens},\"output_tokens\":${output_tokens},\"latency_ms\":${latency_ms},\"stop_reason\":\"${stop_reason}\"}"
}

main "$@" 2>/dev/null || true
