#!/usr/bin/env bash
# Plugin Introspector — Session Stop Hook
# Final anomaly detection and stats update.
# Hook event: Stop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  local session_dir
  session_dir=$(get_session_dir)
  [ -d "$session_dir" ] || return 0
  local sid
  sid=$(get_session_id)
  local safe_sid
  safe_sid=$(sanitize_json_value "$sid" 100)

  local ts
  ts=$(timestamp_iso)
  local now
  now=$(timestamp_ms)

  # Read current stats
  local stats
  stats=$(read_stats "$session_dir")

  command -v jq &>/dev/null || return 0

  # Calculate final metrics
  local tool_calls
  tool_calls=$(echo "$stats" | jq '.tool_calls // 0')
  local total_tokens
  total_tokens=$(echo "$stats" | jq '.total_tokens_est // 0')
  local errors
  errors=$(echo "$stats" | jq '.errors // 0')

  # Calculate error rate
  local error_rate="0.0"
  if [ "$tool_calls" -gt 0 ]; then
    error_rate=$(awk -v e="$errors" -v t="$tool_calls" 'BEGIN {printf "%.1f", e * 100 / t}')
  fi

  # Anomaly check: high error rate (>20%)
  if [ "$tool_calls" -gt 5 ]; then
    local error_pct
    error_pct=$(awk -v e="$errors" -v t="$tool_calls" 'BEGIN {printf "%d", e * 100 / t}')
    if [ "${error_pct:-0}" -gt 20 ]; then
      append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
        "{\"timestamp\":\"${ts}\",\"session_id\":\"${safe_sid}\",\"severity\":\"HIGH\",\"type\":\"high_error_rate\",\"message\":\"Error rate ${error_rate}% exceeds threshold (20%)\",\"tool_calls\":${tool_calls},\"errors\":${errors}}"
    fi
  fi

  # Anomaly check: excessive token usage (>100k)
  if [ "$total_tokens" -gt 100000 ] 2>/dev/null; then
    append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
      "{\"timestamp\":\"${ts}\",\"session_id\":\"${safe_sid}\",\"severity\":\"MEDIUM\",\"type\":\"high_token_usage\",\"message\":\"Token usage ~${total_tokens} exceeds threshold (100k)\",\"total_tokens_est\":${total_tokens}}"
  fi

  # Update stats with stop info
  stats=$(echo "$stats" | jq \
    --arg stop_time "$ts" \
    --argjson stop_ms "$now" \
    --arg error_rate "$error_rate" \
    '.stop_time=$stop_time | .stop_time_ms=$stop_ms | .error_rate=$error_rate')
  write_stats "$session_dir" "$stats"

  # P0 Optimization: Generate pre-computed aggregates from session history
  local history_file="${INTROSPECTOR_BASE}/session_history.jsonl"
  local aggregates_file="${INTROSPECTOR_BASE}/aggregates.json"
  if [ -f "$history_file" ] && [ -s "$history_file" ]; then
    jq -s '{
      sessions_count: length,
      avg_tool_calls: (map(.tool_calls // 0) | add / length | floor),
      avg_tokens: (map(.total_tokens_est // 0) | add / length | floor),
      avg_errors: (map(.errors // 0) | add / length * 10 | floor / 10),
      avg_duration_ms: (map(.duration_ms // 0) | add / length | floor),
      last_updated_ms: now * 1000 | floor,
      tool_usage: (reduce .[] as $s ({};
        reduce ($s.tools // {} | to_entries[]) as $t (.;
          .[$t.key] = ((.[$t.key] // 0) + ($t.value.calls // 0))))),
      error_rate_avg: (map(.error_rate | tonumber? // 0) | add / length * 10 | floor / 10)
    }' "$history_file" > "${aggregates_file}.tmp" 2>/dev/null && \
    mv "${aggregates_file}.tmp" "$aggregates_file" || true
  fi

  # Note: Cleanup of .tid.*, .tstart.*, .parent_span files is handled by session-end.sh
  # to avoid duplicate cleanup. Only session-end.sh performs cleanup.

  # P3 Optimization: Auto-rotate old session data (enabled by PI_AUTO_ROTATE=1)
  if [ "${PI_AUTO_ROTATE:-0}" = "1" ]; then
    bash "${SCRIPT_DIR}/rotate-data.sh" 2>/dev/null || true
  fi
}

main "$@" 2>/dev/null || true
