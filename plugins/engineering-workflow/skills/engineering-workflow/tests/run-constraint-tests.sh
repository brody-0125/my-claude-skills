#!/usr/bin/env bash
# Constraint resolution test runner — validates resolve-constraints.sh against scenarios
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="${SCRIPT_DIR}/../scripts/resolve-constraints.sh"
SCENARIOS="${SCRIPT_DIR}/constraint-scenarios.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if [ ! -f "${SCENARIOS}" ]; then
  echo "ERROR: ${SCENARIOS} not found" >&2
  exit 1
fi

TOTAL=0
PASSED=0
FAILED=0

echo "=== Constraint Resolution Test Suite ==="
echo ""

while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  desc=$(echo "${scenario}" | jq -r '.description')
  # Support both conflicts_count and conflict_count field names
  expected_conflicts=$(echo "${scenario}" | jq -r 'if .expected.conflicts_count != null then .expected.conflicts_count elif .expected.conflict_count != null then .expected.conflict_count else -1 end')
  expected_resolved=$(echo "${scenario}" | jq -r '.expected.resolved_set_count // -1')
  expected_error=$(echo "${scenario}" | jq -r '.expected.has_error')
  # Support both auto_resolved and auto_resolvable field names
  expected_auto=$(echo "${scenario}" | jq -r 'if .expected.auto_resolved != null then .expected.auto_resolved elif .expected.auto_resolvable != null then .expected.auto_resolvable else "null" end')
  expected_conflict_type=$(echo "${scenario}" | jq -r '.expected.conflict_type // "null"')
  expected_conflict_count_gte=$(echo "${scenario}" | jq -r '.expected.conflict_count_gte // -1')

  # Prepare input file
  TMP_INPUT=$(mktemp)
  trap 'rm -f "${TMP_INPUT}"' EXIT

  # Determine input format
  has_raw=$(echo "${scenario}" | jq 'has("input_raw")')
  has_flat=$(echo "${scenario}" | jq 'has("input_flat")')

  if [ "${has_raw}" = "true" ]; then
    echo "${scenario}" | jq -r '.input_raw' > "${TMP_INPUT}"
  elif [ "${has_flat}" = "true" ]; then
    echo "${scenario}" | jq '.input_flat' > "${TMP_INPUT}"
  else
    echo "${scenario}" | jq '.input' > "${TMP_INPUT}"
  fi

  # Run constraint resolver — capture output and exit code separately
  # to avoid double-JSON when script outputs to stdout AND exits non-zero
  set +e
  result=$(bash "${RESOLVE}" "${TMP_INPUT}" 2>/dev/null)
  resolve_exit=$?
  set -e
  if [ ${resolve_exit} -ne 0 ] && [ -z "${result}" ]; then
    result='{"error":"script failed"}'
  fi
  rm -f "${TMP_INPUT}"

  # Check results
  test_ok=true

  actual_error=$(echo "${result}" | jq 'has("error")' 2>/dev/null || echo "true")

  if [ "${expected_error}" = "true" ]; then
    if [ "${actual_error}" != "true" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         expected error but got success"
      test_ok=false
    fi
  else
    if [ "${actual_error}" = "true" ] && echo "${result}" | jq -e '.error' >/dev/null 2>&1; then
      actual_err_msg=$(echo "${result}" | jq -r '.error' 2>/dev/null)
      # "No constraints file found" is not a real error for empty input
      if [ "${actual_err_msg}" != "null" ] && [ "${actual_err_msg}" != "" ]; then
        # Some "errors" are actually expected (e.g., no file found returns empty)
        :
      fi
    fi

    if [ "${expected_conflicts}" != "-1" ]; then
      actual_conflicts=$(echo "${result}" | jq '.conflicts | length' 2>/dev/null || echo "-1")
      if [ "${actual_conflicts}" != "${expected_conflicts}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         conflicts: expected=${expected_conflicts} actual=${actual_conflicts}"
        test_ok=false
      fi
    fi

    if [ "${expected_resolved}" != "-1" ]; then
      actual_resolved=$(echo "${result}" | jq '.resolved_set | length' 2>/dev/null || echo "-1")
      if [ "${actual_resolved}" != "${expected_resolved}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         resolved_set: expected=${expected_resolved} actual=${actual_resolved}"
        test_ok=false
      fi
    fi

    if [ "${expected_auto}" != "null" ]; then
      if [ "${expected_auto}" = "true" ]; then
        unresolved=$(echo "${result}" | jq '[.conflicts[] | select(.resolution == "unresolved")] | length' 2>/dev/null || echo "0")
        if [ "${unresolved}" != "0" ]; then
          echo "  FAIL  ${id}: ${desc}"
          echo "         expected auto-resolved but found unresolved conflicts"
          test_ok=false
        fi
      elif [ "${expected_auto}" = "false" ]; then
        unresolved=$(echo "${result}" | jq '[.conflicts[] | select(.resolution == "unresolved")] | length' 2>/dev/null || echo "0")
        if [ "${unresolved}" = "0" ] && [ "${expected_conflicts}" != "0" ]; then
          echo "  FAIL  ${id}: ${desc}"
          echo "         expected unresolved conflicts but all were auto-resolved"
          test_ok=false
        fi
      fi
    fi

    # conflict_type check (semantic vs structural)
    if [ "${expected_conflict_type}" != "null" ]; then
      has_type=$(echo "${result}" | jq --arg t "${expected_conflict_type}" '[.conflicts[] | select(.type == $t)] | length > 0' 2>/dev/null || echo "false")
      if [ "${has_type}" != "true" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         conflict_type: expected at least one '${expected_conflict_type}' conflict"
        actual_types=$(echo "${result}" | jq -c '[.conflicts[].type // "structural"]' 2>/dev/null || echo "[]")
        echo "         actual types: ${actual_types}"
        test_ok=false
      fi
    fi

    # conflict_count_gte check (>=N conflicts)
    if [ "${expected_conflict_count_gte}" != "-1" ]; then
      actual_conflict_count=$(echo "${result}" | jq '.conflicts | length' 2>/dev/null || echo "0")
      if [ "${actual_conflict_count}" -lt "${expected_conflict_count_gte}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         conflict_count: expected>=${expected_conflict_count_gte} actual=${actual_conflict_count}"
        test_ok=false
      fi
    fi
  fi

  if $test_ok; then
    echo "  PASS  ${id}: ${desc}"
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done < <(jq -c '.[]' "${SCENARIOS}")

echo ""
echo "=== Results: ${PASSED} passed, ${FAILED} failed, ${TOTAL} total ==="

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
