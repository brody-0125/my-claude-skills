#!/usr/bin/env bash
# Engineering Workflow — Token Budget Enforcement
#
# Enforces SKILL.md token budget table by estimating output tokens.
# Exit 1 if estimated tokens exceed 120% of budget for the given pattern/phase.
#
# Usage: enforce-budget.sh <pattern> <phase> [json-output-or-stdin]
# Patterns: shallow | analysis | implementation | test | full | cross-system | cross-pruning
# Phases: agent | audit | total
#
# Exit codes:
#   0 — within budget
#   1 — exceeds 120% of budget
#
# Dependencies: bash + jq only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ── Budget Table (from SKILL.md:358-366) ─────────────────

get_budget() {
  local pattern="${1}"
  local phase="${2}"

  # Budget values in tokens: agent, audit, total
  case "${pattern}" in
    shallow)          local agent=3500  audit=300  total=3800  ;;
    analysis)         local agent=6000  audit=1500 total=7500  ;;
    implementation)   local agent=8000  audit=1500 total=9500  ;;
    test)             local agent=10000 audit=1500 total=11500 ;;
    full)             local agent=12000 audit=1500 total=13500 ;;
    cross-system)     local agent=15000 audit=3500 total=18500 ;;
    cross-pruning)    local agent=10000 audit=3500 total=13500 ;;
    *)
      echo '{"error":"Unknown pattern: '"${pattern}"'. Use: shallow, analysis, implementation, test, full, cross-system, cross-pruning"}' | jq .
      exit 1
      ;;
  esac

  case "${phase}" in
    agent) echo "${agent}" ;;
    audit) echo "${audit}" ;;
    total) echo "${total}" ;;
    test-loop) echo $(( agent / 2 )) ;;
    *)
      echo '{"error":"Unknown phase: '"${phase}"'. Use: agent, audit, total, test-loop"}' | jq .
      exit 1
      ;;
  esac
}

# ── Input ─────────────────────────────────────────────────

PATTERN="${1:-}"
PHASE="${2:-}"
shift 2 || true

if [ -z "${PATTERN}" ] || [ -z "${PHASE}" ]; then
  echo '{"error":"Usage: enforce-budget.sh <pattern> <phase> [json-output]"}' | jq .
  exit 1
fi

INPUT=$(read_input "${1:-}")

if [ -z "${INPUT}" ]; then
  echo '{"error":"Empty input"}' | jq .
  exit 1
fi

# ── Token Estimation ─────────────────────────────────────

OUTPUT_SIZE=${#INPUT}
TOKEN_EST=$(( OUTPUT_SIZE / 4 ))
BUDGET=$(get_budget "${PATTERN}" "${PHASE}")
THRESHOLD=$(( BUDGET * 120 / 100 ))

WITHIN_BUDGET=true
if [ "${TOKEN_EST}" -gt "${THRESHOLD}" ]; then
  WITHIN_BUDGET=false
fi

USAGE_PCT=$(( TOKEN_EST * 100 / BUDGET ))

jq -n \
  --arg pattern "${PATTERN}" \
  --arg phase "${PHASE}" \
  --argjson budget "${BUDGET}" \
  --argjson threshold "${THRESHOLD}" \
  --argjson token_estimate "${TOKEN_EST}" \
  --argjson usage_pct "${USAGE_PCT}" \
  --argjson within_budget "${WITHIN_BUDGET}" \
  '{
    pattern: $pattern,
    phase: $phase,
    budget: $budget,
    threshold_120pct: $threshold,
    token_estimate: $token_estimate,
    usage_percent: $usage_pct,
    within_budget: $within_budget
  }'

if [ "${WITHIN_BUDGET}" = "false" ]; then
  log_warn "Budget exceeded: ${TOKEN_EST} tokens > ${THRESHOLD} (120% of ${BUDGET}) for ${PATTERN}/${PHASE}"
  exit 1
fi
