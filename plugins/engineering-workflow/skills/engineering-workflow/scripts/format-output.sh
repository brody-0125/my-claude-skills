#!/usr/bin/env bash
# Engineering Workflow — Output Formatter
#
# Formats agent/orchestrator/synthesizer results into user-readable markdown.
# Takes JSON result(s) and produces formatted markdown output.
#
# Usage: format-output.sh <output-type> [json-file-or-stdin]
# Output types: single-domain | multi-domain | cross-system | error
# Output: Markdown text to stdout
#
# Dependencies: bash + jq + awk (POSIX)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ── Flags ─────────────────────────────────────────────────

SUMMARY_MODE=false
if [ "${1:-}" = "--summary" ]; then
  SUMMARY_MODE=true
  shift
fi

# ── Input ─────────────────────────────────────────────────

OUTPUT_TYPE="${1:-single-domain}"
shift || true

INPUT=$(read_input "${1:-}")

if [ -z "${INPUT}" ]; then
  echo "**Error**: No input data to format."
  exit 1
fi

# ── Formatting Functions ──────────────────────────────────

format_confidence() {
  local conf="${1:-0}"
  local level
  level=$(awk -v c="${conf}" 'BEGIN { if (c >= 0.70) print "High"; else if (c >= 0.50) print "Medium"; else print "Low" }')
  echo "${level} (${conf})"
}

format_single_domain() {
  local json="${1}"

  echo "## Analysis Result"
  echo ""

  # Extract key fields
  local rationale
  rationale=$(echo "${json}" | jq -r '.rationale // "No rationale provided"' 2>/dev/null)
  local confidence
  confidence=$(echo "${json}" | jq -r '.confidence // 0' 2>/dev/null)

  echo "**Confidence**: $(format_confidence "${confidence}")"
  echo ""
  echo "### Recommendation"
  echo ""
  echo "${rationale}"
  echo ""

  # Print constraints if present
  local constraints_count
  constraints_count=$(echo "${json}" | jq '.constraints | length // 0' 2>/dev/null || echo "0")
  if [ "${constraints_count}" -gt 0 ]; then
    echo "### Constraints"
    echo ""
    echo "${json}" | jq -r '.constraints[] | "- **\(.target // "general")** (\(.priority // "soft")): \(.value // "N/A")"' 2>/dev/null
    echo ""
  fi
}

format_multi_domain() {
  local json="${1}"

  echo "## Multi-Domain Analysis"
  echo ""

  # Iterate over domain results
  echo "${json}" | jq -r '
    if type == "array" then
      .[] |
      "### Domain \(.domain // "Unknown")\n\n" +
      "**Confidence**: \(.confidence // "N/A")\n\n" +
      "\(.rationale // "No rationale")\n\n---\n"
    else
      "### Result\n\n\(.rationale // "No rationale")\n"
    end
  ' 2>/dev/null
}

format_cross_system() {
  local json="${1}"

  echo "## Cross-System Analysis"
  echo ""

  # Systems analyzed
  local systems
  systems=$(echo "${json}" | jq -r '.systems_analyzed // [] | join(", ")' 2>/dev/null)
  echo "**Systems Analyzed**: ${systems}"
  echo ""

  # Unified recommendation
  local recommendation
  recommendation=$(echo "${json}" | jq -r '.unified_recommendation // "No recommendation"' 2>/dev/null)
  echo "### Unified Recommendation"
  echo ""
  echo "${recommendation}"
  echo ""

  # Cross-dependencies
  local dep_count
  dep_count=$(echo "${json}" | jq '.cross_dependencies | length // 0' 2>/dev/null || echo "0")
  if [ "${dep_count}" -gt 0 ]; then
    echo "### Cross-System Dependencies"
    echo ""
    echo "${json}" | jq -r '.cross_dependencies[] | "- \(.from // "?") -> \(.to // "?"): \(.description // "")"' 2>/dev/null
    echo ""
  fi

  # Conflicts
  local conflict_count
  conflict_count=$(echo "${json}" | jq '.conflicts | length // 0' 2>/dev/null || echo "0")
  if [ "${conflict_count}" -gt 0 ]; then
    echo "### Resolved Conflicts"
    echo ""
    echo "${json}" | jq -r '.conflicts[] | "- **\(.type // "unknown")**: \(.rationale // "N/A")"' 2>/dev/null
    echo ""
  fi

  # Implementation order
  local order_count
  order_count=$(echo "${json}" | jq '.implementation_order | length // 0' 2>/dev/null || echo "0")
  if [ "${order_count}" -gt 0 ]; then
    echo "### Implementation Order"
    echo ""
    echo "${json}" | jq -r '.implementation_order | to_entries[] | "\(.key + 1). \(.value)"' 2>/dev/null
    echo ""
  fi
}

format_error() {
  local json="${1}"

  echo "## Analysis Error"
  echo ""

  local error_msg
  error_msg=$(echo "${json}" | jq -r '.error // "Unknown error"' 2>/dev/null)
  local error_type
  error_type=$(echo "${json}" | jq -r '.error_type // "unknown"' 2>/dev/null)

  echo "**Error Type**: ${error_type}"
  echo ""
  echo "${error_msg}"
  echo ""
  echo "> See resources/error-playbook.md for resolution guidance."
}

# ── Summary Format ────────────────────────────────────────

format_summary() {
  local json="${1}"
  local type="${2}"

  # Classification line
  local confidence
  confidence=$(echo "${json}" | jq -r '.confidence // 0' 2>/dev/null)

  case "${type}" in
    single-domain)
      local rationale
      rationale=$(echo "${json}" | jq -r '.rationale // "No rationale"' 2>/dev/null)
      local rec
      rec=$(echo "${json}" | jq -r '.recommendation // ""' 2>/dev/null)
      local rec_short="${rec:0:200}"
      [ ${#rec} -gt 200 ] && rec_short="${rec_short}..."
      local c_count
      c_count=$(echo "${json}" | jq '.constraints | length // 0' 2>/dev/null || echo "0")
      local t_count
      t_count=$(echo "${json}" | jq '.trade_offs | length // 0' 2>/dev/null || echo "0")

      echo "**Single-Domain** | Confidence: ${confidence} | Constraints: ${c_count} | Trade-offs: ${t_count}"
      echo ""
      echo "**Recommendation**: ${rec_short}"
      ;;
    multi-domain)
      local domain_count
      domain_count=$(echo "${json}" | jq 'if type == "array" then length else 1 end' 2>/dev/null || echo "1")
      echo "**Multi-Domain** (${domain_count} domains) | Confidence: ${confidence}"
      echo ""
      echo "${json}" | jq -r 'if type == "array" then .[] | "- Domain \(.domain // "?"): \(.rationale // "N/A" | .[0:100])" else "- \(.rationale // "N/A" | .[0:100])" end' 2>/dev/null
      ;;
    cross-system)
      local systems
      systems=$(echo "${json}" | jq -r '.systems_analyzed // [] | join(", ")' 2>/dev/null)
      local rec
      rec=$(echo "${json}" | jq -r '.unified_recommendation // ""' 2>/dev/null)
      local rec_short="${rec:0:200}"
      [ ${#rec} -gt 200 ] && rec_short="${rec_short}..."
      local dep_count
      dep_count=$(echo "${json}" | jq '.cross_dependencies | length // 0' 2>/dev/null || echo "0")
      local order_count
      order_count=$(echo "${json}" | jq '.implementation_order | length // 0' 2>/dev/null || echo "0")

      echo "**Cross-System** [${systems}] | Dependencies: ${dep_count} | Phases: ${order_count}"
      echo ""
      echo "**Recommendation**: ${rec_short}"
      ;;
    error)
      local error_msg
      error_msg=$(echo "${json}" | jq -r '.error // "Unknown error"' 2>/dev/null)
      echo "**Error**: ${error_msg}"
      ;;
  esac

  echo ""
  echo "> Run without --summary for full analysis"
}

# ── Dispatch ──────────────────────────────────────────────

if [ "${SUMMARY_MODE}" = "true" ]; then
  format_summary "${INPUT}" "${OUTPUT_TYPE}"
else
  case "${OUTPUT_TYPE}" in
    single-domain)  format_single_domain "${INPUT}" ;;
    multi-domain)   format_multi_domain "${INPUT}" ;;
    cross-system)   format_cross_system "${INPUT}" ;;
    error)          format_error "${INPUT}" ;;
    *)
      echo "Unknown output type: ${OUTPUT_TYPE}"
      echo "Valid types: single-domain, multi-domain, cross-system, error"
      exit 1
      ;;
  esac
fi
