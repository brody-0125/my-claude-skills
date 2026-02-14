#!/usr/bin/env bash
# Engineering Workflow — Constraint Resolution
#
# Reads constraints.json and detects/reports conflicts between agent constraints.
# Conflicts are detected when two constraints have opposing values for the same target.
#
# Usage: resolve-constraints.sh [constraints-file]
# Default: ~/.claude/cache/engineering-workflow/constraints.json
# Output: JSON with conflicts[] and resolved_set[]
#
# Dependencies: bash + jq only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ── Input ─────────────────────────────────────────────────

CONSTRAINTS_FILE="${1:-${CACHE_DIR}/constraints.json}"

if [ ! -f "${CONSTRAINTS_FILE}" ]; then
  echo '{"error":"No constraints file found","conflicts":[],"resolved_set":[]}' | jq .
  exit 0
fi

CONSTRAINTS=$(cat "${CONSTRAINTS_FILE}")

# Validate JSON
if ! echo "${CONSTRAINTS}" | jq . >/dev/null 2>&1; then
  echo '{"error":"Invalid JSON in constraints file","conflicts":[],"resolved_set":[]}' | jq .
  exit 1
fi

# ── Extract constraints array ─────────────────────────────

# Support both nested format ({constraints: [...]}) and legacy flat array ([...])
IS_ARRAY=$(echo "${CONSTRAINTS}" | jq 'type == "array"' 2>/dev/null || echo "false")
if [ "${IS_ARRAY}" = "true" ]; then
  CONSTRAINT_ARRAY="${CONSTRAINTS}"
else
  CONSTRAINT_ARRAY=$(echo "${CONSTRAINTS}" | jq -r '.constraints // []')
fi
CONSTRAINT_COUNT=$(echo "${CONSTRAINT_ARRAY}" | jq 'length')

if [ "${CONSTRAINT_COUNT}" -le 1 ]; then
  # No conflicts possible with 0 or 1 constraint
  echo "${CONSTRAINT_ARRAY}" | jq '{
    conflicts: [],
    resolved_set: .,
    metadata: {
      total_declared: length,
      total_accepted: length,
      total_rejected: 0,
      total_conflicts: 0,
      total_resolved: 0,
      resolved_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
    }
  }'
  exit 0
fi

# ── Conflict Detection ────────────────────────────────────
# Two constraints conflict when:
# 1. They target the same domain/aspect
# 2. Their values are different
# 3. At least one is a "hard" constraint

CONFLICTS=$(echo "${CONSTRAINT_ARRAY}" | jq '
  [
    . as $all |
    range(length) as $i |
    range($i + 1; length) as $j |
    select(
      ($all[$i].target == $all[$j].target) and
      ($all[$i].value != $all[$j].value)
    ) |
    {
      conflict_id: ("cf-" + ($i | tostring) + "-" + ($j | tostring)),
      constraint_a: $all[$i],
      constraint_b: $all[$j],
      type: (
        if ($all[$i].priority == "hard" and $all[$j].priority == "hard") then "hard_vs_hard"
        elif ($all[$i].priority == "hard" or $all[$j].priority == "hard") then "hard_vs_soft"
        else "soft_vs_soft"
        end
      ),
      auto_resolvable: (
        ($all[$i].priority == "hard" and $all[$j].priority != "hard") or
        ($all[$j].priority == "hard" and $all[$i].priority != "hard")
      )
    }
  ]
')

CONFLICT_COUNT=$(echo "${CONFLICTS}" | jq 'length')

# ── Auto-Resolution ──────────────────────────────────────
# hard vs soft → accept hard, reject soft
# hard vs hard → cannot auto-resolve (needs orchestrator/synthesizer)
# soft vs soft → cannot auto-resolve (needs trade-off analysis)

RESOLVED_CONFLICTS=$(echo "${CONFLICTS}" | jq '
  [.[] | if .auto_resolvable then
    if .constraint_a.priority == "hard" then
      . + {resolution: "accept_a", rationale: "Hard constraint takes precedence over soft constraint"}
    else
      . + {resolution: "accept_b", rationale: "Hard constraint takes precedence over soft constraint"}
    end
  else
    . + {resolution: "unresolved", rationale: "Requires orchestrator or user input"}
  end]
')

# ── Build resolved set ────────────────────────────────────
# Start with all constraints, then mark rejected ones

REJECTED_IDS=$(echo "${RESOLVED_CONFLICTS}" | jq -r '
  [.[] | select(.resolution != "unresolved") |
    if .resolution == "accept_a" then .constraint_b.id
    elif .resolution == "accept_b" then .constraint_a.id
    else empty end
  ] | unique | .[]
' 2>/dev/null || true)

RESOLVED_SET=$(echo "${CONSTRAINT_ARRAY}" | jq --arg rejected "${REJECTED_IDS}" '
  . as $all |
  ($rejected | split("\n") | map(select(. != ""))) as $rej |
  [.[] | select(.id as $id | ($rej | index($id)) == null)]
')

ACCEPTED_COUNT=$(echo "${RESOLVED_SET}" | jq 'length')
if [ -z "${REJECTED_IDS}" ]; then
  REJECTED_COUNT=0
else
  REJECTED_COUNT=$(printf '%s\n' "${REJECTED_IDS}" | grep -c . || true)
fi
UNRESOLVED_COUNT=$(echo "${RESOLVED_CONFLICTS}" | jq '[.[] | select(.resolution == "unresolved")] | length')

# ── Output ────────────────────────────────────────────────

jq -n \
  --argjson conflicts "${RESOLVED_CONFLICTS}" \
  --argjson resolved_set "${RESOLVED_SET}" \
  --argjson total_declared "${CONSTRAINT_COUNT}" \
  --argjson total_accepted "${ACCEPTED_COUNT}" \
  --arg total_rejected "${REJECTED_COUNT}" \
  --argjson total_conflicts "${CONFLICT_COUNT}" \
  --argjson total_unresolved "${UNRESOLVED_COUNT}" \
  '{
    conflicts: $conflicts,
    resolved_set: $resolved_set,
    metadata: {
      total_declared: $total_declared,
      total_accepted: $total_accepted,
      total_rejected: ($total_rejected | tonumber),
      total_conflicts: $total_conflicts,
      total_unresolved: $total_unresolved,
      resolved_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }
  }'
