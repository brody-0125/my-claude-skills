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
  is_strict=$(echo "${scenario}" | jq -r '.strict // false')

  if [ "${has_raw}" = "true" ]; then
    input_data=$(echo "${scenario}" | jq -r '.input_raw')
  else
    input_data=$(echo "${scenario}" | jq -c '.input')
  fi

  # Build validator args
  validate_args=()
  if [ "${is_strict}" = "true" ]; then
    validate_args+=("--strict")
  fi
  validate_args+=("${agent_type}")

  # Run validator (pipe input via stdin) — capture output and exit code separately
  # to avoid double-JSON when script outputs to stdout AND exits non-zero
  set +e
  result=$(echo "${input_data}" | bash "${VALIDATE}" "${validate_args[@]}" 2>/dev/null)
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

  # Check max_quality_score if specified
  max_quality=$(echo "${scenario}" | jq -r '.expected.max_quality_score // "null"')
  if [ "${max_quality}" != "null" ]; then
    actual_quality=$(echo "${result}" | jq -r '.quality_score // 100' 2>/dev/null || echo "100")
    if [ "${actual_quality}" -gt "${max_quality}" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         quality_score: expected<=${max_quality} actual=${actual_quality}"
      test_ok=false
    fi
  fi

  # Check has_confidence_warning if specified
  expect_conf_warn=$(echo "${scenario}" | jq -r '.expected.has_confidence_warning // "null"')
  if [ "${expect_conf_warn}" = "true" ]; then
    has_conf_warn=$(echo "${result}" | jq '[.warnings[] | select(test("confidence.*1\\.0|1\\.0.*cache"))] | length > 0' 2>/dev/null || echo "false")
    if [ "${has_conf_warn}" != "true" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         expected confidence=1.0 warning but not found"
      test_ok=false
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
