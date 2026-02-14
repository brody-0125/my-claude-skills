#!/usr/bin/env bash
# Agent output validation test runner — validates validate-agent-output.sh against scenarios
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${SCRIPT_DIR}/../scripts/validate-agent-output.sh"
SCENARIOS="${SCRIPT_DIR}/validation-scenarios.json"

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

echo "=== Agent Output Validation Test Suite ==="
echo ""

while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  desc=$(echo "${scenario}" | jq -r '.description')
  agent_type=$(echo "${scenario}" | jq -r '.agent_type')
  expected_valid=$(echo "${scenario}" | jq -r '.expected.valid')
  expected_errors=$(echo "${scenario}" | jq -r '.expected.error_count')

  # Prepare input
  has_raw=$(echo "${scenario}" | jq 'has("input_raw")')

  if [ "${has_raw}" = "true" ]; then
    input_data=$(echo "${scenario}" | jq -r '.input_raw')
  else
    input_data=$(echo "${scenario}" | jq -c '.input')
  fi

  # Run validator (pipe input via stdin) — capture output and exit code separately
  # to avoid double-JSON when script outputs to stdout AND exits non-zero
  set +e
  result=$(echo "${input_data}" | bash "${VALIDATE}" "${agent_type}" 2>/dev/null)
  validate_exit=$?
  set -e
  if [ ${validate_exit} -ne 0 ] && [ -z "${result}" ]; then
    result='{"valid":false,"errors":["Script execution failed"],"warnings":[]}'
  fi

  # Check results
  test_ok=true

  actual_valid=$(echo "${result}" | jq -r '.valid' 2>/dev/null || echo "false")
  actual_error_count=$(echo "${result}" | jq '.errors | length' 2>/dev/null || echo "0")

  if [ "${actual_valid}" != "${expected_valid}" ]; then
    echo "  FAIL  ${id}: ${desc}"
    echo "         valid: expected=${expected_valid} actual=${actual_valid}"
    test_ok=false
  fi

  if [ "${expected_errors}" != "-1" ] && [ "${actual_error_count}" != "${expected_errors}" ]; then
    echo "  FAIL  ${id}: ${desc}"
    echo "         error_count: expected=${expected_errors} actual=${actual_error_count}"
    test_ok=false
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
