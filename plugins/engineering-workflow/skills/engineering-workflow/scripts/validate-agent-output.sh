#!/usr/bin/env bash
# Engineering Workflow — Agent Output Validation
#
# Validates that an agent's JSON output contains required fields
# based on the agent type (domain agent, orchestrator, synthesizer).
#
# Usage: validate-agent-output.sh [--strict] <agent-type> [json-file-or-stdin]
# Agent types: domain-agent | orchestrator | synthesizer
# Flags: --strict  Promote quality warnings to errors (STANDARD+ audit tier)
# Output: JSON with valid (bool), errors[], warnings[]
#
# Dependencies: bash + jq only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ── Flags ─────────────────────────────────────────────────

STRICT_MODE=false
if [ "${1:-}" = "--strict" ]; then
  STRICT_MODE=true
  shift
fi

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

# ── Strict mode enforcement (STANDARD+ audit tier) ──────

if [ "${STRICT_MODE}" = "true" ]; then
  case "${AGENT_TYPE}" in
    domain-agent)
      # constraints 0 → error (multi-domain context requires constraints)
      constraints_count=$(echo "${INPUT}" | jq '.constraints | length // 0' 2>/dev/null || echo "0")
      if [ "${constraints_count}" -eq 0 ]; then
        ERRORS+=("Strict: missing 'constraints' — required for multi-domain agent output")
      fi
      # recommendation < 50 chars → error
      if [ "${rec_len:-0}" -lt 50 ]; then
        ERRORS+=("Strict: 'recommendation' too short (${rec_len:-0} chars) — minimum 50 chars required")
      fi
      # trade_offs < 2 → error
      trade_off_count=$(echo "${INPUT}" | jq '.trade_offs | length // 0' 2>/dev/null || echo "0")
      if [ "${trade_off_count}" -lt 2 ]; then
        ERRORS+=("Strict: 'trade_offs' has fewer than 2 options (${trade_off_count}) — minimum 2 required")
      fi
      ;;
  esac
fi

# ── Degenerate content detection ─────────────────────────

# Repeated character detection: 20+ char text with < 10 unique chars
detect_degenerate() {
  local text="${1}"
  local text_len=${#text}
  if [ "${text_len}" -ge 20 ]; then
    local unique_chars
    unique_chars=$(printf '%s' "${text}" | fold -w1 2>/dev/null | sort -u | wc -l | tr -d ' ')
    if [ "${unique_chars}" -lt 10 ]; then
      return 0  # degenerate
    fi
  fi
  return 1  # ok
}

# Check rationale for degenerate content
rationale_text=$(echo "${INPUT}" | jq -r '.rationale // ""' 2>/dev/null || echo "")
if [ -n "${rationale_text}" ] && detect_degenerate "${rationale_text}"; then
  WARNINGS+=("Degenerate content detected in 'rationale' — low character diversity")
  QUALITY_SCORE=$(( QUALITY_SCORE - 25 ))
fi

# Check recommendation for degenerate content
rec_text=$(echo "${INPUT}" | jq -r '.recommendation // ""' 2>/dev/null || echo "")
if [ -n "${rec_text}" ] && detect_degenerate "${rec_text}"; then
  WARNINGS+=("Degenerate content detected in 'recommendation' — low character diversity")
  QUALITY_SCORE=$(( QUALITY_SCORE - 25 ))
fi

# Agent-type-specific degenerate detection
case "${AGENT_TYPE}" in
  synthesizer)
    unified_rec_text=$(echo "${INPUT}" | jq -r '.unified_recommendation // ""' 2>/dev/null || echo "")
    if [ -n "${unified_rec_text}" ] && detect_degenerate "${unified_rec_text}"; then
      WARNINGS+=("Degenerate content detected in 'unified_recommendation' — low character diversity")
      QUALITY_SCORE=$(( QUALITY_SCORE - 25 ))
    fi
    ;;
  orchestrator)
    guidance_text=$(echo "${INPUT}" | jq -r '.guidance // ""' 2>/dev/null || echo "")
    if [ -n "${guidance_text}" ] && detect_degenerate "${guidance_text}"; then
      WARNINGS+=("Degenerate content detected in 'guidance' — low character diversity")
      QUALITY_SCORE=$(( QUALITY_SCORE - 25 ))
    fi
    ;;
esac

# Field length limit: rationale > 8000 chars
rationale_len=${#rationale_text}
if [ "${rationale_len}" -gt 8000 ]; then
  WARNINGS+=("'rationale' exceeds 8000 chars (${rationale_len}) — consider trimming")
  QUALITY_SCORE=$(( QUALITY_SCORE - 10 ))
fi

# Confidence 1.0 warning: only appropriate for cached results
if echo "${INPUT}" | jq -e 'has("confidence")' >/dev/null 2>&1; then
  conf_val=$(echo "${INPUT}" | jq '.confidence' 2>/dev/null || echo "0")
  if [ "$(awk -v c="${conf_val}" 'BEGIN { print (c == 1.0) ? 1 : 0 }')" -eq 1 ]; then
    WARNINGS+=("confidence=1.0 is reserved for cache hits — inappropriate for agent-generated output")
    QUALITY_SCORE=$(( QUALITY_SCORE - 5 ))
  fi
fi

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
if [ "${QUALITY_SCORE}" -gt 100 ]; then
  QUALITY_SCORE=100
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
