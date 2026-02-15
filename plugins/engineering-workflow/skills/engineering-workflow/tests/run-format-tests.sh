#!/usr/bin/env bash
# Format output test runner — validates format-output.sh against scenarios
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT="${SCRIPT_DIR}/../scripts/format-output.sh"
SCENARIOS="${SCRIPT_DIR}/format-scenarios.json"

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

echo "=== Format Output Test Suite ==="
echo ""

while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  desc=$(echo "${scenario}" | jq -r '.description')
  output_type=$(echo "${scenario}" | jq -r '.output_type')
  expect_nonzero=$(echo "${scenario}" | jq -r '.expected.exit_nonzero // false')

  # Prepare input
  has_raw=$(echo "${scenario}" | jq 'has("input_raw")')

  if [ "${has_raw}" = "true" ]; then
    input_data=$(echo "${scenario}" | jq -r '.input_raw')
  else
    input_data=$(echo "${scenario}" | jq -c '.input')
  fi

  # Build format arguments
  use_summary=$(echo "${scenario}" | jq -r '.summary // false')
  format_args=()
  if [ "${use_summary}" = "true" ]; then
    format_args+=("--summary")
  fi
  format_args+=("${output_type}")

  # Run formatter — capture output and exit code
  set +e
  result=$(echo "${input_data}" | bash "${FORMAT}" "${format_args[@]}" 2>&1)
  format_exit=$?
  set -e

  test_ok=true

  # Check exit code expectation
  if [ "${expect_nonzero}" = "true" ]; then
    if [ ${format_exit} -eq 0 ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         expected non-zero exit but got 0"
      test_ok=false
    fi
  else
    if [ ${format_exit} -ne 0 ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         expected zero exit but got ${format_exit}"
      test_ok=false
    fi
  fi

  # Check not_empty
  not_empty=$(echo "${scenario}" | jq -r '.expected.not_empty // false')
  if [ "${not_empty}" = "true" ] && [ -z "${result}" ]; then
    echo "  FAIL  ${id}: ${desc}"
    echo "         output is empty"
    test_ok=false
  fi

  # Check contains strings
  contains_count=$(echo "${scenario}" | jq '.expected.contains | length' 2>/dev/null || echo "0")
  for (( i=0; i<contains_count; i++ )); do
    expected_str=$(echo "${scenario}" | jq -r ".expected.contains[$i]")
    if ! echo "${result}" | grep -qF "${expected_str}"; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         missing expected string: \"${expected_str}\""
      test_ok=false
      break
    fi
  done

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
