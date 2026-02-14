#!/usr/bin/env bash
# Plugin Introspector — Session End Hook
# Aggregates session statistics, merges OTel data at Tier 1+,
# and appends summary to session_history.
# Hook event: SessionEnd

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  local session_dir
  session_dir=$(get_session_dir)
  local sid
  sid=$(get_session_id)

  local now
  now=$(timestamp_ms)
  local ts
  ts=$(timestamp_iso)

  # Tier 1+: merge native OTel data before finalizing stats
  local tier
  tier=$(detect_otel_tier)
  if [ "$tier" -ge 1 ] && [ -f "${SCRIPT_DIR}/merge-otel-data.sh" ]; then
    bash "${SCRIPT_DIR}/merge-otel-data.sh" "$sid" --security 2>/dev/null || true
  fi

  # Calculate session duration
  local start_ms=0
  if [ -f "${session_dir}/meta.json" ] && command -v jq &>/dev/null; then
    start_ms=$(jq -r '.start_time_ms // 0' "${session_dir}/meta.json" 2>/dev/null || echo "0")
  fi
  local duration_ms=$((now - start_ms))

  # Aggregate stats_deltas.jsonl into stats.json (batch update)
  local deltas_file="${session_dir}/stats_deltas.jsonl"
  if [ -f "${deltas_file}" ] && command -v jq &>/dev/null; then
    local base_stats
    base_stats=$(read_stats "${session_dir}")
    local aggregated
    aggregated=$(jq -s --argjson base "${base_stats}" '
      reduce .[] as $d ($base;
        .tool_calls += 1
        | .total_tokens_est += ($d.tok // 0)
        | .errors += ($d.err // 0)
        | .tools[$d.t] = ((.tools[$d.t] // {"calls":0,"tokens":0,"errors":0,"total_duration_ms":0})
            | .calls += 1 | .tokens += ($d.tok // 0) | .errors += ($d.err // 0) | .total_duration_ms += ($d.dur // 0))
      )
    ' "${deltas_file}" 2>/dev/null) || true
    if [ -n "${aggregated}" ]; then
      write_stats "${session_dir}" "${aggregated}"
    fi
    rm -f "${deltas_file}"
  fi

  # Read final stats
  local stats
  stats=$(read_stats "${session_dir}")

  # Count trace lines
  local tool_trace_count=0
  local api_trace_count=0
  local otel_span_count=0
  [ -f "${session_dir}/tool_traces.jsonl" ] && tool_trace_count=$(( $(wc -l < "${session_dir}/tool_traces.jsonl" 2>/dev/null || echo "0") + 0 ))
  [ -f "${session_dir}/api_traces.jsonl" ] && api_trace_count=$(( $(wc -l < "${session_dir}/api_traces.jsonl" 2>/dev/null || echo "0") + 0 ))
  [ -f "${session_dir}/otel_traces.jsonl" ] && otel_span_count=$(( $(wc -l < "${session_dir}/otel_traces.jsonl" 2>/dev/null || echo "0") + 0 ))

  # Aggregate security events if present
  local security_summary="{}"
  if [ -f "${session_dir}/security_events.jsonl" ] && command -v jq &>/dev/null; then
    security_summary=$(jq -s '
      if length == 0 then {}
      else {
        security_events_count: length,
        critical_count: [.[] | select((.risk_level // .severity) == "CRITICAL")] | length,
        high_count: [.[] | select((.risk_level // .severity) == "HIGH")] | length,
        blocked_count: [.[] | select((.action // "") | ascii_downcase == "blocked")] | length
      }
      end
    ' "${session_dir}/security_events.jsonl" 2>/dev/null || echo '{}')
  fi

  # Update stats with end info and calculate error rate
  if command -v jq &>/dev/null; then
    local tc
    tc=$(echo "$stats" | jq '.tool_calls // 0')
    local errs
    errs=$(echo "$stats" | jq '.errors // 0')
    local error_rate="0.0"
    if [ "$tc" -gt 0 ] 2>/dev/null; then
      error_rate=$(awk -v e="$errs" -v t="$tc" 'BEGIN {printf "%.1f", t > 0 ? e * 100 / t : 0}')
    fi

    stats=$(echo "$stats" | jq \
      --arg end_time "$ts" \
      --argjson end_ms "$now" \
      --argjson duration "$duration_ms" \
      --argjson traces "$tool_trace_count" \
      --argjson api_traces "$api_trace_count" \
      --argjson spans "$otel_span_count" \
      --arg er "$error_rate" \
      --argjson tier "$tier" \
      --argjson sec "$security_summary" \
      '.end_time=$end_time | .end_time_ms=$end_ms | .duration_ms=$duration
       | .tool_trace_count=$traces | .api_trace_count=$api_traces
       | .otel_span_count=$spans | .error_rate=$er | .collection_tier=$tier
       | . + $sec')
    write_stats "$session_dir" "$stats"

    # Append to session history
    local history_entry
    history_entry=$(echo "$stats" | jq \
      --arg sid "$sid" \
      '{session_id: $sid} + .')
    append_jsonl "${INTROSPECTOR_BASE}/session_history.jsonl" "$history_entry"
  fi

  # Cleanup temporary correlation files (glob handles per-call keyed files)
  rm -f "${session_dir}"/.tid.* "${session_dir}"/.tstart.* "${session_dir}/.parent_span"
}

main "$@" 2>/dev/null || true
