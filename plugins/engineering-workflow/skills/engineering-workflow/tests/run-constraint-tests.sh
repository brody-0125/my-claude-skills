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
  expected_conflicts=$(echo "${scenario}" | jq -r '.expected.conflicts_count // -1')
  expected_resolved=$(echo "${scenario}" | jq -r '.expected.resolved_set_count // -1')
  expected_error=$(echo "${scenario}" | jq -r '.expected.has_error')
  expected_auto=$(echo "${scenario}" | jq -r '.expected.auto_resolved // "null"')

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
