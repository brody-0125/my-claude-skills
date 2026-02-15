#!/usr/bin/env bash
# Engineering Workflow — Analysis Audit Script
#
# Deterministic (jq-based) quality checks for agent and orchestrator outputs.
# No LLM calls — pure JSON validation and metric extraction.
#
# Usage:
#   audit-analysis.sh confidence <agent-output-json>
#   audit-analysis.sh orchestrator <orchestrator-output-json>
#   audit-analysis.sh synthesis <synthesizer-output-json>
#   audit-analysis.sh tier <classification-json> <agent-count>
#
# Dependencies: bash + jq only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ── Input ─────────────────────────────────────────────────

MODE="${1:-}"
shift || true

if [ -z "${MODE}" ]; then
  echo '{"error":"Usage: audit-analysis.sh <confidence|orchestrator|synthesis|tier> [input]"}' | jq .
  exit 1
fi

# read_input() is provided by _common.sh

# ── Tier Determination ────────────────────────────────────

determine_tier() {
  local classification="${1}"
  local agent_count="${2:-1}"

  local system_count domain_count has_security depth
  system_count=$(echo "${classification}" | jq '[.systems[]? // empty] | length' 2>/dev/null || echo "1")
  domain_count=$(echo "${classification}" | jq '[.domains[]? // empty] | length' 2>/dev/null || echo "1")
  has_security=$(echo "${classification}" | jq '[.systems[]? // empty] | map(select(. == "SE")) | length > 0' 2>/dev/null || echo "false")
  depth=$(echo "${classification}" | jq -r '.depth // "deep"' 2>/dev/null || echo "deep")

  local tier="LIGHT"

  # Multi-domain or 2+ agents → STANDARD
  if [ "${domain_count}" -gt 1 ] || [ "${agent_count}" -gt 1 ]; then
    tier="STANDARD"
  fi

  # Cross-system or security → THOROUGH
  if [ "${system_count}" -gt 1 ]; then
    tier="THOROUGH"
  fi
  # Deep with many agents → THOROUGH
  if [ "${depth}" = "deep" ] && [ "${agent_count}" -gt 3 ]; then
    tier="THOROUGH"
  fi
  if [ "${has_security}" = "true" ]; then
    tier="THOROUGH"
  fi

  echo "${tier}"
}

# ── Confidence Gating ─────────────────────────────────────

audit_confidence() {
  local input
  input=$(read_input "${1:-}")

  local confidence action
  confidence=$(echo "${input}" | jq -r '.confidence // 0' 2>/dev/null || echo "0")

  # Pre-validate confidence range [0, 1]
  local out_of_range
  out_of_range=$(awk -v c="${confidence}" 'BEGIN { print (c < 0 || c > 1) ? 1 : 0 }')
  if [ "${out_of_range}" -eq 1 ]; then
    jq -n \
      --arg action "WARN" \
      --arg confidence "${confidence}" \
      --arg detail "Confidence ${confidence} is outside valid range [0.0, 1.0] — treating as unreliable" \
      --arg calibration "OUT_OF_RANGE" \
      --arg calibration_detail "Confidence value ${confidence} is outside the valid [0.0, 1.0] range" \
      '{action: $action, confidence: ($confidence | tonumber), detail: $detail, calibration: $calibration, calibration_detail: $calibration_detail}'
    return
  fi

  # Use awk for floating-point comparison
  action=$(awk -v c="${confidence}" 'BEGIN {
    if (c >= 0.70) print "PASS"
    else if (c >= 0.50) print "WARN"
    else if (c >= 0.30) print "RETRY"
    else print "REJECT"
  }')

  local detail=""
  case "${action}" in
    PASS) detail="Confidence ${confidence} >= 0.70 — normal processing" ;;
    WARN) detail="Confidence ${confidence} in [0.50, 0.70) — moderate confidence warning added" ;;
    RETRY) detail="Confidence ${confidence} in [0.30, 0.50) — simplified re-dispatch recommended" ;;
    REJECT) detail="Confidence ${confidence} < 0.30 — reject, use orchestrator fallback" ;;
  esac

  # Calibration check: high confidence with low quality signals
  local calibration_flag=""
  local calibration_detail=""
  if echo "${input}" | jq -e '.' >/dev/null 2>&1; then
    local trade_offs_count rec_length constraints_count
    trade_offs_count=$(echo "${input}" | jq '.trade_offs | length // 0' 2>/dev/null || echo "0")
    rec_length=$(echo "${input}" | jq -r '.recommendation // "" | length' 2>/dev/null || echo "0")
    constraints_count=$(echo "${input}" | jq '.constraints | length // 0' 2>/dev/null || echo "0")

    # confidence == 1.0 → unconditional WARN
    if [ "$(awk -v c="${confidence}" 'BEGIN { print (c == 1.0) ? 1 : 0 }')" -eq 1 ]; then
      action="WARN"
      calibration_flag="CALIBRATION"
      calibration_detail="confidence=1.0 is reserved for cache hits — agent output should not report 1.0"
    # confidence >= 0.90 with low quality signals → WARN + CALIBRATION
    elif [ "$(awk -v c="${confidence}" 'BEGIN { print (c >= 0.90) ? 1 : 0 }')" -eq 1 ]; then
      local low_signals=0
      [ "${trade_offs_count}" -lt 2 ] && low_signals=$((low_signals + 1))
      [ "${rec_length}" -lt 100 ] && low_signals=$((low_signals + 1))
      [ "${constraints_count}" -lt 1 ] && low_signals=$((low_signals + 1))
      if [ "${low_signals}" -ge 2 ]; then
        calibration_flag="CALIBRATION"
        calibration_detail="High confidence (${confidence}) with ${low_signals} low-quality signals — may be miscalibrated"
        if [ "${action}" = "PASS" ]; then
          action="WARN"
          detail="Confidence ${confidence} >= 0.90 but quality signals are low — calibration warning"
        fi
      fi
    fi
  fi

  if [ -n "${calibration_flag}" ]; then
    jq -n \
      --arg action "${action}" \
      --arg confidence "${confidence}" \
      --arg detail "${detail}" \
      --arg calibration "${calibration_flag}" \
      --arg calibration_detail "${calibration_detail}" \
      '{action: $action, confidence: ($confidence | tonumber), detail: $detail, calibration: $calibration, calibration_detail: $calibration_detail}'
  else
    jq -n \
      --arg action "${action}" \
      --arg confidence "${confidence}" \
      --arg detail "${detail}" \
      '{action: $action, confidence: ($confidence | tonumber), detail: $detail}'
  fi
}

# ── Orchestrator Schema Validation ────────────────────────

audit_orchestrator() {
  local input
  input=$(read_input "${1:-}")

  local findings=()
  local has_critical=false

  # CRITICAL fields
  if ! echo "${input}" | jq -e 'has("system")' >/dev/null 2>&1; then
    findings+=('{"field":"system","severity":"CRITICAL","status":"FAIL","action":"reject result"}')
    has_critical=true
  fi

  if ! echo "${input}" | jq -e 'has("status")' >/dev/null 2>&1; then
    findings+=('{"field":"status","severity":"CRITICAL","status":"FAIL","action":"default to partial + warning"}')
  fi

  # Required fields with defaults
  if ! echo "${input}" | jq -e 'has("guidance")' >/dev/null 2>&1; then
    findings+=('{"field":"guidance","severity":"WARN","status":"MISSING","action":"substitute from first recommendation title"}')
  fi

  if ! echo "${input}" | jq -e 'has("recommendations")' >/dev/null 2>&1; then
    findings+=('{"field":"recommendations","severity":"WARN","status":"MISSING","action":"default to empty array + warning"}')
  fi

  if ! echo "${input}" | jq -e 'has("resolved_constraints")' >/dev/null 2>&1; then
    findings+=('{"field":"resolved_constraints","severity":"WARN","status":"MISSING","action":"default to empty array"}')
  fi

  if ! echo "${input}" | jq -e 'has("unresolved_constraints")' >/dev/null 2>&1; then
    findings+=('{"field":"unresolved_constraints","severity":"WARN","status":"MISSING","action":"default to empty array"}')
  fi

  if ! echo "${input}" | jq -e '.metadata.confidence' >/dev/null 2>&1; then
    findings+=('{"field":"metadata.confidence","severity":"WARN","status":"MISSING","action":"default to 0.5 + warning"}')
  fi

  # Constraint forwarding: check impacts → unresolved alignment
  local forwarding_gaps
  forwarding_gaps=$(echo "${input}" | jq '
    . as $root |
    [.resolved_constraints[]? |
      select(.impacts != null and (.impacts | length) > 0) |
      .source as $src | .description as $desc |
      select(
        [$root.unresolved_constraints[]? | select(.description == $desc)] | length == 0
      ) |
      {source: $src, description: $desc, impacts: .impacts}
    ] // []
  ' 2>/dev/null || echo '[]')

  local gap_count
  gap_count=$(echo "${forwarding_gaps}" | jq 'length' 2>/dev/null || echo "0")
  if [ "${gap_count}" -gt 0 ]; then
    findings+=("{\"field\":\"constraint_forwarding\",\"severity\":\"WARN\",\"status\":\"GAP\",\"action\":\"${gap_count} cross-system constraints not forwarded to unresolved_constraints\"}")
  fi

  # Build output
  local overall="PASS"
  if [ "${has_critical}" = "true" ]; then
    overall="FAIL"
  elif [ ${#findings[@]} -gt 0 ]; then
    overall="WARN"
  fi

  local findings_json='[]'
  if [ ${#findings[@]} -gt 0 ]; then
    findings_json=$(printf '%s\n' "${findings[@]}" | jq -s '.' 2>/dev/null || echo '[]')
  fi

  jq -n \
    --arg overall "${overall}" \
    --argjson findings "${findings_json}" \
    --argjson forwarding_gaps "${forwarding_gaps}" \
    '{overall: $overall, findings: $findings, forwarding_gaps: $forwarding_gaps}'
}

# ── Synthesis Validation ──────────────────────────────────

audit_synthesis() {
  local input
  input=$(read_input "${1:-}")

  local findings=()

  # Coverage: check all systems are referenced in unified_recommendation
  local systems_analyzed rec_text
  systems_analyzed=$(echo "${input}" | jq -r '[.systems_analyzed[]?] | join(",")' 2>/dev/null || echo "")
  rec_text=$(echo "${input}" | jq -r '.unified_recommendation // ""' 2>/dev/null || echo "")

  if [ -n "${systems_analyzed}" ]; then
    IFS=',' read -ra sys_arr <<< "${systems_analyzed}"
    for sys in "${sys_arr[@]}"; do
      if ! echo "${rec_text}" | grep -qi "${sys}" 2>/dev/null; then
        findings+=("{\"check\":\"coverage\",\"status\":\"WARN\",\"code\":\"EW-AUD-007\",\"detail\":\"System ${sys} not referenced in unified_recommendation\"}")
      fi
    done
  fi

  # Ordering: check depends_on references exist
  local order_issues
  order_issues=$(echo "${input}" | jq '
    .implementation_order // [] |
    . as $order |
    [.[] |
      .depends_on // [] |
      .[] |
      . as $dep |
      if ($order | map(.phase) | index($dep)) == null then
        {check: "ordering", status: "FAIL", code: "EW-AUD-008", detail: ("depends_on references non-existent phase: " + ($dep | tostring))}
      else empty end
    ]
  ' 2>/dev/null || echo '[]')

  local order_issue_count
  order_issue_count=$(echo "${order_issues}" | jq 'length' 2>/dev/null || echo "0")

  # Risk-Rollback: high-risk phases must have rollback
  local missing_rollback
  missing_rollback=$(echo "${input}" | jq '
    [.implementation_order // [] | .[] |
      select(.risk == "high" and (.rollback == null or .rollback == ""))
    | {check: "risk_rollback", status: "WARN", code: "EW-AUD-009", detail: ("Phase " + (.phase | tostring) + ": high risk without rollback strategy")}]
  ' 2>/dev/null || echo '[]')

  # Confidence floor
  local overall_confidence
  overall_confidence=$(echo "${input}" | jq -r '.confidence_assessment.overall // "unknown"' 2>/dev/null || echo "unknown")

  local confidence_finding='[]'
  if [ "${overall_confidence}" = "low" ]; then
    confidence_finding='[{"check":"confidence_floor","status":"WARN","code":"EW-AUD-006","detail":"Overall confidence is low — explicit caveat required in output"}]'
  fi

  # Merge all findings
  local all_findings
  if [ ${#findings[@]} -gt 0 ]; then
    local shell_findings
    shell_findings=$(printf '%s\n' "${findings[@]}" | jq -s '.' 2>/dev/null || echo '[]')
    all_findings=$(jq -n \
      --argjson a "${shell_findings}" \
      --argjson b "${order_issues}" \
      --argjson c "${missing_rollback}" \
      --argjson d "${confidence_finding}" \
      '$a + $b + $c + $d')
  else
    all_findings=$(jq -n \
      --argjson b "${order_issues}" \
      --argjson c "${missing_rollback}" \
      --argjson d "${confidence_finding}" \
      '$b + $c + $d')
  fi

  local fail_count
  fail_count=$(echo "${all_findings}" | jq '[.[] | select(.status == "FAIL")] | length' 2>/dev/null || echo "0")

  local overall="PASS"
  if [ "${fail_count}" -gt 0 ]; then
    overall="FAIL"
  elif [ "$(echo "${all_findings}" | jq 'length')" -gt 0 ]; then
    overall="WARN"
  fi

  jq -n \
    --arg overall "${overall}" \
    --argjson findings "${all_findings}" \
    '{overall: $overall, findings: $findings}'
}

# ── Main dispatch ─────────────────────────────────────────

case "${MODE}" in
  confidence)
    audit_confidence "${1:-}"
    ;;
  orchestrator)
    audit_orchestrator "${1:-}"
    ;;
  synthesis)
    audit_synthesis "${1:-}"
    ;;
  tier)
    INPUT_1=$(read_input "${1:-}")
    AGENT_COUNT="${2:-1}"
    determine_tier "${INPUT_1}" "${AGENT_COUNT}"
    ;;
  *)
    echo "{\"error\":\"Unknown mode: ${MODE}. Use: confidence, orchestrator, synthesis, tier\"}" | jq .
    exit 1
    ;;
esac
