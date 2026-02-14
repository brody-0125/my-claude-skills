#!/usr/bin/env bash
# Plugin Introspector — OTel Data Merge Script
# Reads native OTel data from OTel Collector File Exporter (OTLP JSON)
# and merges it into the session's otel_traces.jsonl.
#
# Supports multiple OTel backends:
#   - grafana/otel-lgtm (File Exporter)
#   - ClickStack/HyperDX (OTLP export)
#   - Standard OTel Collector
#
# Called by session-end.sh at Tier 1+ before stats finalization.
# Can also be run standalone: merge-otel-data.sh [session-id] [--security]
#
# Options:
#   --security   Also run security event mapping after merge
#
# OTLP JSON format (from File Exporter):
#   The file exporter writes nested OTLP JSON objects, NOT simple JSONL.
#   Each top-level object contains:
#   {
#     "resourceSpans": [{
#       "resource": { "attributes": [...] },
#       "scopeSpans": [{
#         "spans": [{
#           "traceId": "hex",
#           "spanId": "hex",
#           "parentSpanId": "hex",
#           "name": "...",
#           "kind": 1,
#           "startTimeUnixNano": "...",
#           "endTimeUnixNano": "...",
#           "attributes": [{"key":"...","value":{"stringValue":"..."}}],
#           "status": {"code": 0}
#         }]
#       }]
#     }]
#   }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

main() {
  local sid=""
  local run_security=false

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --security|-s)
        run_security=true
        shift
        ;;
      *)
        sid="$1"
        shift
        ;;
    esac
  done

  if [ -z "$sid" ]; then
    sid=$(get_session_id)
  fi
  local session_dir="${INTROSPECTOR_BASE}/sessions/${sid}"
  [ -d "$session_dir" ] || { echo "Session not found: $sid" >&2; return 1; }

  command -v jq &>/dev/null || { echo "jq required for OTel merge" >&2; return 1; }

  # Find OTLP JSON files from collector export
  local export_dir="$OTEL_EXPORT_DIR"
  [ -d "$export_dir" ] || return 0

  local merged_count=0
  local otel_file="${session_dir}/otel_traces.jsonl"

  # Read session start time to filter spans
  local session_start_ms=0
  if [ -f "${session_dir}/meta.json" ]; then
    session_start_ms=$(jq -r '.start_time_ms // 0' "${session_dir}/meta.json" 2>/dev/null || echo "0")
  fi

  # Process each OTLP JSON file with a single jq pipeline per file.
  # Replaces the previous O(N) jq-per-span approach with O(1) jq per file.
  for otlp_file in "$export_dir"/*.json "$export_dir"/*.jsonl; do
    [ -f "$otlp_file" ] || continue

    # Single jq pipeline: extract → convert ns→ms → filter by session time →
    # flatten attributes → map kind/status → output in our format
    # Extended with more GenAI Semconv attributes and tool_parameters
    local file_count
    file_count=$(jq -c --argjson session_start "$session_start_ms" '
      # Kind map: OTLP integer → string
      def map_kind: if . == 2 then "SERVER" elif . == 3 then "CLIENT"
        elif . == 4 then "PRODUCER" elif . == 5 then "CONSUMER" else "INTERNAL" end;
      # Status map: OTLP code → string
      def map_status: if . == 0 then "UNSET" elif . == 2 then "ERROR" else "OK" end;

      .resourceSpans[]?.scopeSpans[]?.spans[]? |
      # Convert nanosecond strings to millisecond numbers
      ((.startTimeUnixNano // "0") | tonumber / 1000000 | floor) as $start_ms |
      ((.endTimeUnixNano // "0") | tonumber / 1000000 | floor) as $end_ms |
      ($end_ms - $start_ms) as $dur |
      # Filter: only spans within session timeframe
      select($start_ms >= $session_start) |
      # Flatten OTLP attributes array to object
      ([ (.attributes // [])[] | {(.key): (.value.stringValue // .value.intValue // .value.doubleValue // .value.boolValue // "")} ] | add // {}) as $attrs |

      # Parse tool_parameters if present
      (
        if $attrs["tool_parameters"] then
          ($attrs["tool_parameters"] | if type == "string" then fromjson? // {} else . end)
        else {}
        end
      ) as $params |

      {
        trace_id: .traceId,
        span_id: .spanId,
        parent_span_id: (.parentSpanId // ""),
        name: .name,
        kind: ((.kind // 1) | map_kind),
        start_time_ms: $start_ms,
        end_time_ms: $end_ms,
        duration_ms: $dur,
        attributes: {
          # GenAI Semantic Conventions (core)
          "gen_ai.system": ($attrs["gen_ai.system"] // "anthropic"),
          "gen_ai.operation.name": ($attrs["gen_ai.operation.name"] // ""),
          "gen_ai.request.model": ($attrs["gen_ai.request.model"] // $attrs["model"] // ""),
          "gen_ai.response.id": ($attrs["gen_ai.response.id"] // ""),

          # Tool info
          "gen_ai.tool.name": ($attrs["gen_ai.tool.name"] // $attrs["tool_name"] // ""),
          "tool_parameters": $params,

          # Token tracking
          "gen_ai.usage.input_tokens": (($attrs["gen_ai.usage.input_tokens"] // $attrs["input_tokens"] // "0") | tonumber),
          "gen_ai.usage.output_tokens": (($attrs["gen_ai.usage.output_tokens"] // $attrs["output_tokens"] // "0") | tonumber),
          "gen_ai.usage.total_tokens": (
            (($attrs["gen_ai.usage.input_tokens"] // "0") | tonumber) +
            (($attrs["gen_ai.usage.output_tokens"] // "0") | tonumber)
          ),

          # Decision tracking (for security analysis)
          "decision": ($attrs["decision"] // ""),
          "decision_source": ($attrs["source"] // ""),

          # Cost tracking
          "cost_usd": (($attrs["cost_usd"] // "0") | tonumber),

          # Session context
          "session.id": ($attrs["session.id"] // "")
        },
        status: ((.status.code // 1) | map_status),
        _source: "native_otel"
      }
    ' "$otlp_file" 2>/dev/null | tee -a "$otel_file" | wc -l)

    merged_count=$((merged_count + ${file_count:-0}))
  done

  if [ "$merged_count" -gt 0 ]; then
    echo "Merged $merged_count native OTel spans into session $sid" >&2
  fi

  # Run security mapper if requested
  if [ "$run_security" = true ]; then
    local security_script="${SCRIPT_DIR}/otel-security-mapper.sh"
    if [ -x "$security_script" ]; then
      echo "Running security event mapping..." >&2
      "$security_script" "$sid"
    fi
  fi
}

main "$@"
