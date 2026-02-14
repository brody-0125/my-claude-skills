#!/usr/bin/env bash
# Plugin Introspector — Opt-in Anonymous Telemetry
#
# IMPORTANT: This script only runs when PI_TELEMETRY=1 is explicitly set.
# By default, NO telemetry is collected.
#
# What is collected (when enabled):
#   - Command execution counts (e.g., "status" called 5 times)
#   - Session counts
#   - Plugin version
#
# What is NEVER collected:
#   - File paths or content
#   - Command arguments or parameters
#   - Personal information
#   - Project names or code
#
# Data is stored locally in ${INTROSPECTOR_BASE}/telemetry.jsonl
# No data is transmitted externally.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# Return/exit immediately if telemetry is not enabled
# Use return in sourced context, exit in direct execution
[ "${PI_TELEMETRY:-0}" = "1" ] || { return 0 2>/dev/null || exit 0; }

TELEMETRY_FILE="${INTROSPECTOR_BASE}/telemetry.jsonl"
PI_VERSION="1.0.0"

# Record an anonymous telemetry event
# Usage: record_telemetry <event_type> [extra_field]
record_telemetry() {
  local event_type="$1"
  local extra="${2:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")

  # Sanitize for safe JSON embedding
  local safe_event
  safe_event=$(sanitize_json_value "$event_type" 50)
  local safe_extra
  safe_extra=$(sanitize_json_value "$extra" 200)

  # Ensure base directory exists
  mkdir -p "${INTROSPECTOR_BASE}" 2>/dev/null

  if [ -n "$safe_extra" ]; then
    append_jsonl "$TELEMETRY_FILE" "{\"ts\":\"$ts\",\"event\":\"$safe_event\",\"v\":\"$PI_VERSION\",\"d\":\"$safe_extra\"}"
  else
    append_jsonl "$TELEMETRY_FILE" "{\"ts\":\"$ts\",\"event\":\"$safe_event\",\"v\":\"$PI_VERSION\"}"
  fi
}

# Get telemetry summary for local display
# Usage: get_telemetry_summary
get_telemetry_summary() {
  if [ ! -f "$TELEMETRY_FILE" ]; then
    echo "{\"enabled\":true,\"events\":0}"
    return
  fi

  if command -v jq &>/dev/null; then
    jq -s '
      {
        enabled: true,
        events: length,
        by_type: group_by(.event) | map({key: .[0].event, value: length}) | from_entries,
        first_event: (sort_by(.ts) | first.ts // null),
        last_event: (sort_by(.ts) | last.ts // null)
      }
    ' "$TELEMETRY_FILE" 2>/dev/null || echo "{\"enabled\":true,\"events\":0,\"error\":\"parse_failed\"}"
  else
    local count
    count=$(wc -l < "$TELEMETRY_FILE" 2>/dev/null || echo "0")
    echo "{\"enabled\":true,\"events\":$count}"
  fi
}

# Clear telemetry data
# Usage: clear_telemetry
clear_telemetry() {
  if [ -f "$TELEMETRY_FILE" ]; then
    rm -f "$TELEMETRY_FILE"
    echo "Telemetry data cleared."
  else
    echo "No telemetry data to clear."
  fi
}

# Main entry point for command-line usage
main() {
  local cmd="${1:-}"

  case "$cmd" in
    record)
      shift
      record_telemetry "$@"
      ;;
    summary)
      get_telemetry_summary
      ;;
    clear)
      clear_telemetry
      ;;
    status)
      if [ "${PI_TELEMETRY:-0}" = "1" ]; then
        echo "Telemetry: ENABLED"
        echo "File: $TELEMETRY_FILE"
        get_telemetry_summary
      else
        echo "Telemetry: DISABLED (set PI_TELEMETRY=1 to enable)"
      fi
      ;;
    *)
      echo "Usage: telemetry.sh [record|summary|clear|status]"
      echo ""
      echo "Opt-in anonymous telemetry for Plugin Introspector."
      echo "Set PI_TELEMETRY=1 to enable."
      ;;
  esac
}

# Only run main if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
