#!/usr/bin/env bash
# Engineering Workflow — Agent Output Validation
#
# Validates that an agent's JSON output contains required fields
# based on the agent type (domain agent, orchestrator, synthesizer).
#
# Usage: validate-agent-output.sh <agent-type> [json-file-or-stdin]
# Agent types: domain-agent | orchestrator | synthesizer
# Output: JSON with valid (bool), errors[], warnings[]
#
# Dependencies: bash + jq only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ── Input ─────────────────────────────────────────────────

AGENT_TYPE="${1:-domain-agent}"
shift || true

INPUT=$(read_input "${1:-}")

if [ -z "${INPUT}" ]; then
  echo '{"valid":false,"errors":["Empty input"],"warnings":[]}' | jq .
  exit 1
fi

# Validate JSON
if ! echo "${INPUT}" | jq . >/dev/null 2>&1; then
  echo '{"valid":false,"errors":["Invalid JSON"],"warnings":[]}' | jq .
  exit 1
fi

# ── Field Validation ──────────────────────────────────────

ERRORS=()
WARNINGS=()

# Common required field: confidence
if ! echo "${INPUT}" | jq -e 'has("confidence")' >/dev/null 2>&1; then
  WARNINGS+=("Missing 'confidence' field")
fi

case "${AGENT_TYPE}" in
  domain-agent)
    # Domain agents must have specific analysis output
    if ! echo "${INPUT}" | jq -e 'has("rationale")' >/dev/null 2>&1; then
      ERRORS+=("Missing required 'rationale' field")
    fi
    # Check confidence is a number between 0 and 1
    if echo "${INPUT}" | jq -e 'has("confidence")' >/dev/null 2>&1; then
      CONF=$(echo "${INPUT}" | jq '.confidence')
      if ! echo "${CONF}" | grep -qE '^[0-9]*\.?[0-9]+$'; then
        ERRORS+=("'confidence' must be a number")
      elif [ "$(awk -v c="${CONF}" 'BEGIN { print (c < 0 || c > 1) ? 1 : 0 }')" -eq 1 ]; then
        WARNINGS+=("'confidence' value ${CONF} is outside the expected 0.0-1.0 range")
      fi
    fi
    ;;

  orchestrator)
    # Orchestrator must have system and status
    if ! echo "${INPUT}" | jq -e 'has("system")' >/dev/null 2>&1; then
      ERRORS+=("Missing required 'system' field")
    fi
    if ! echo "${INPUT}" | jq -e 'has("status")' >/dev/null 2>&1; then
      ERRORS+=("Missing required 'status' field")
    fi
    # Status must be one of: completed, partial, stub, failed
    if echo "${INPUT}" | jq -e 'has("status")' >/dev/null 2>&1; then
      STATUS=$(echo "${INPUT}" | jq -r '.status')
      case "${STATUS}" in
        completed|partial|stub|failed) ;;
        *) ERRORS+=("Invalid status: ${STATUS}. Must be: completed, partial, stub, or failed") ;;
      esac
    fi
    ;;

  synthesizer)
    # Synthesizer must have unified recommendation
    if ! echo "${INPUT}" | jq -e 'has("systems_analyzed")' >/dev/null 2>&1; then
      ERRORS+=("Missing required 'systems_analyzed' field")
    fi
    if ! echo "${INPUT}" | jq -e 'has("unified_recommendation")' >/dev/null 2>&1; then
      ERRORS+=("Missing required 'unified_recommendation' field")
    fi
    if ! echo "${INPUT}" | jq -e 'has("implementation_order")' >/dev/null 2>&1; then
      WARNINGS+=("Missing 'implementation_order' field")
    fi
    # Check for cross-dependencies
    if ! echo "${INPUT}" | jq -e 'has("cross_dependencies")' >/dev/null 2>&1; then
      WARNINGS+=("Missing 'cross_dependencies' field")
    fi
    ;;

  *)
    ERRORS+=("Unknown agent type: ${AGENT_TYPE}")
    ;;
esac

# ── Quality Indicator Checks ─────────────────────────────

QUALITY_SCORE=100

# Check trade_offs presence (domain-agent and orchestrator)
case "${AGENT_TYPE}" in
  domain-agent)
    if ! echo "${INPUT}" | jq -e 'has("trade_offs")' >/dev/null 2>&1; then
      WARNINGS+=("Missing 'trade_offs' field — completeness reduced")
      QUALITY_SCORE=$(( QUALITY_SCORE - 15 ))
    elif [ "$(echo "${INPUT}" | jq '.trade_offs | length' 2>/dev/null || echo 0)" -lt 2 ]; then
      WARNINGS+=("'trade_offs' has fewer than 2 options — consider adding alternatives")
      QUALITY_SCORE=$(( QUALITY_SCORE - 10 ))
    fi
    # Check recommendation length (actionable check)
    rec_len=$(echo "${INPUT}" | jq -r '.recommendation // "" | length' 2>/dev/null || echo "0")
    if [ "${rec_len}" -lt 50 ]; then
      WARNINGS+=("'recommendation' is very short (${rec_len} chars) — may not be actionable")
      QUALITY_SCORE=$(( QUALITY_SCORE - 10 ))
    fi
    # Check constraints presence for multi-domain contexts
    if ! echo "${INPUT}" | jq -e 'has("constraints")' >/dev/null 2>&1; then
      WARNINGS+=("Missing 'constraints' field — inter-agent communication limited")
      QUALITY_SCORE=$(( QUALITY_SCORE - 5 ))
    fi
    ;;
  orchestrator)
    # Check agent_results presence
    if ! echo "${INPUT}" | jq -e 'has("agent_results")' >/dev/null 2>&1; then
      WARNINGS+=("Missing 'agent_results' field")
      QUALITY_SCORE=$(( QUALITY_SCORE - 15 ))
    fi
    # Check guidance length
    guid_len=$(echo "${INPUT}" | jq -r '.guidance // "" | length' 2>/dev/null || echo "0")
    if [ "${guid_len}" -lt 20 ]; then
      WARNINGS+=("'guidance' is very short (${guid_len} chars) — may lack specificity")
      QUALITY_SCORE=$(( QUALITY_SCORE - 10 ))
    fi
    # Check recommendations array
    if echo "${INPUT}" | jq -e 'has("recommendations")' >/dev/null 2>&1; then
      rec_count=$(echo "${INPUT}" | jq '.recommendations | length' 2>/dev/null || echo "0")
      if [ "${rec_count}" -eq 0 ]; then
        WARNINGS+=("'recommendations' array is empty")
        QUALITY_SCORE=$(( QUALITY_SCORE - 10 ))
      fi
    fi
    ;;
esac

# ── Token estimate check ─────────────────────────────────

OUTPUT_SIZE=${#INPUT}
TOKEN_EST=$(( OUTPUT_SIZE / 4 ))

if [ "${TOKEN_EST}" -gt 5000 ]; then
  WARNINGS+=("Agent output is large (~${TOKEN_EST} tokens). Consider trimming verbose fields.")
fi

# ── Output ────────────────────────────────────────────────

VALID=true
if [ ${#ERRORS[@]} -gt 0 ]; then
  VALID=false
fi

# bash 3.2 (macOS default) treats empty arrays as unbound with set -u
# Use ${arr[@]+"${arr[@]}"} pattern to safely expand potentially empty arrays
if [ ${#ERRORS[@]} -gt 0 ]; then
  ERRORS_JSON=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
else
  ERRORS_JSON='[]'
fi
if [ ${#WARNINGS[@]} -gt 0 ]; then
  WARNINGS_JSON=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
else
  WARNINGS_JSON='[]'
fi

# Clamp quality score to 0-100
if [ "${QUALITY_SCORE}" -lt 0 ]; then
  QUALITY_SCORE=0
fi

jq -n \
  --argjson valid "${VALID}" \
  --argjson errors "${ERRORS_JSON}" \
  --argjson warnings "${WARNINGS_JSON}" \
  --argjson token_estimate "${TOKEN_EST}" \
  --argjson quality_score "${QUALITY_SCORE}" \
  --arg agent_type "${AGENT_TYPE}" \
  '{
    valid: $valid,
    agent_type: $agent_type,
    errors: $errors,
    warnings: $warnings,
    token_estimate: $token_estimate,
    quality_score: $quality_score
  }'
