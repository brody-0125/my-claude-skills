#!/usr/bin/env bash
set -euo pipefail
# Plugin Introspector — Security Baseline Learning
#
# Builds a security baseline from historical session data.
# Used by anomaly-detector for improved precision in detecting unusual patterns.
#
# The baseline includes:
#   - Normal tool usage patterns
#   - Typical command frequency by tool type
#   - Expected severity distribution
#
# Usage:
#   security-baseline.sh build     # Build/update baseline from history
#   security-baseline.sh show      # Display current baseline
#   security-baseline.sh check     # Check current session against baseline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

BASELINE_FILE="${INTROSPECTOR_BASE}/security_baseline.json"
BASELINE_MAX_AGE_DAYS="${PI_BASELINE_MAX_AGE:-30}"

# Build baseline from historical security events
build_baseline() {
  local sessions_dir="${INTROSPECTOR_BASE}/sessions"

  if [ ! -d "$sessions_dir" ]; then
    echo "{\"error\":\"no_sessions\",\"message\":\"No session data found\"}"
    return 1
  fi

  # Ensure jq is available
  if ! command -v jq &>/dev/null; then
    echo "{\"error\":\"no_jq\",\"message\":\"jq required for baseline building\"}"
    return 1
  fi

  # Find security event files from last N days
  local event_files
  event_files=$(find "$sessions_dir" -name "security_events.jsonl" -mtime -"$BASELINE_MAX_AGE_DAYS" 2>/dev/null)

  if [ -z "$event_files" ]; then
    # No security events yet — create empty baseline
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"tools\":[],\"updated\":\"$now\",\"sessions_analyzed\":0,\"events_analyzed\":0}" > "$BASELINE_FILE"
    echo "Created empty baseline (no security events in last $BASELINE_MAX_AGE_DAYS days)"
    return 0
  fi

  # Aggregate all security events
  local baseline
  baseline=$(echo "$event_files" | xargs cat 2>/dev/null | jq -s '
    if length == 0 then
      {tools: [], updated: (now | strftime("%Y-%m-%dT%H:%M:%SZ")), sessions_analyzed: 0, events_analyzed: 0}
    else
      {
        tools: (
          group_by(.tool)
          | map({
              tool: .[0].tool,
              count: length,
              severities: ([.[] | (.risk_level // .severity // "UNKNOWN")] | group_by(.) | map({key: .[0], count: length}) | from_entries),
              actions: ([.[] | (.action // "unknown") | ascii_downcase] | group_by(.) | map({key: .[0], count: length}) | from_entries),
              avg_per_session: (length / ([.[] | (.session_id // "unknown")] | unique | length))
            })
        ),
        updated: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        events_analyzed: length,
        sessions_analyzed: ([.[] | (.session_id // "unknown")] | unique | length),
        severity_distribution: (
          group_by(.risk_level // .severity // "UNKNOWN")
          | map({key: (.[0].risk_level // .[0].severity // "UNKNOWN"), count: length})
          | from_entries
        ),
        top_patterns: (
          group_by(.pattern // "unknown")
          | map({pattern: .[0].pattern, count: length})
          | sort_by(-.count)
          | .[0:10]
        )
      }
    end
  ' 2>/dev/null)

  if [ -z "$baseline" ] || [ "$baseline" = "null" ]; then
    echo "{\"error\":\"aggregation_failed\",\"message\":\"Failed to aggregate security events\"}"
    return 1
  fi

  echo "$baseline" > "$BASELINE_FILE"
  echo "Baseline updated: $(echo "$baseline" | jq -r '.events_analyzed') events from $(echo "$baseline" | jq -r '.sessions_analyzed') sessions"
}

# Display current baseline
show_baseline() {
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "No baseline found. Run 'security-baseline.sh build' first."
    return 1
  fi

  if command -v jq &>/dev/null; then
    jq '.' "$BASELINE_FILE"
  else
    cat "$BASELINE_FILE"
  fi
}

# Check current session against baseline
check_against_baseline() {
  local session_dir
  session_dir=$(get_session_dir)
  local security_file="${session_dir}/security_events.jsonl"

  if [ ! -f "$BASELINE_FILE" ]; then
    echo "{\"status\":\"no_baseline\",\"message\":\"No baseline available for comparison\"}"
    return 0
  fi

  if [ ! -f "$security_file" ]; then
    echo "{\"status\":\"no_events\",\"message\":\"No security events in current session\"}"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    echo "{\"status\":\"no_jq\",\"message\":\"jq required for baseline comparison\"}"
    return 1
  fi

  # Compare current session to baseline
  local baseline
  baseline=$(cat "$BASELINE_FILE")

  local current
  current=$(jq -s '
    {
      tools: (group_by(.tool) | map({tool: .[0].tool, count: length})),
      total_events: length,
      critical_count: [.[] | select((.risk_level // .severity) == "CRITICAL")] | length,
      high_count: [.[] | select((.risk_level // .severity) == "HIGH")] | length
    }
  ' "$security_file" 2>/dev/null)

  # Calculate anomaly score (simplified)
  local result
  result=$(echo "{\"baseline\": $baseline, \"current\": $current}" | jq '
    {
      status: "compared",
      current_events: .current.total_events,
      baseline_avg: ((.baseline.events_analyzed // 1) / ((.baseline.sessions_analyzed // 1) | if . == 0 then 1 else . end)),
      critical_events: .current.critical_count,
      high_events: .current.high_count,
      anomaly_indicators: (
        if .current.critical_count > 0 then ["critical_events_present"] else [] end
        + if .current.total_events > ((.baseline.events_analyzed // 0) / ((.baseline.sessions_analyzed // 1) | if . == 0 then 1 else . end) * 2) then ["above_average_events"] else [] end
      )
    }
  ' 2>/dev/null)

  echo "$result"
}

# Main entry point
main() {
  local cmd="${1:-show}"

  case "$cmd" in
    build|update)
      build_baseline
      ;;
    show|display)
      show_baseline
      ;;
    check|compare)
      check_against_baseline
      ;;
    *)
      echo "Usage: security-baseline.sh [build|show|check]"
      echo ""
      echo "Commands:"
      echo "  build   Build/update baseline from historical sessions"
      echo "  show    Display current baseline"
      echo "  check   Check current session against baseline"
      echo ""
      echo "Environment:"
      echo "  PI_BASELINE_MAX_AGE  Days of history to analyze (default: 30)"
      ;;
  esac
}

main "$@"
