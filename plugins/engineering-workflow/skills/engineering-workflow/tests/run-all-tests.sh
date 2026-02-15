#!/usr/bin/env bash
# Unified test runner — runs all engineering-workflow test suites
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_suite() {
  local name="${1}"
  local script="${2}"
  TOTAL_SUITES=$((TOTAL_SUITES + 1))

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Running: ${name}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  set +e
  suite_output=$(bash "${script}" 2>/dev/null)
  exit_code=$?
  set -e

  echo "${suite_output}"

  # Parse individual test counts from "=== Results: N passed, M failed, T total ==="
  results_line=$(echo "${suite_output}" | grep -E '^=== Results:' | tail -1)
  if [ -n "${results_line}" ]; then
    suite_passed=$(echo "${results_line}" | sed -E 's/.*Results: ([0-9]+) passed.*/\1/')
    suite_failed=$(echo "${results_line}" | sed -E 's/.*, ([0-9]+) failed.*/\1/')
    suite_total=$(echo "${results_line}" | sed -E 's/.*, ([0-9]+) total.*/\1/')
    PASSED_TESTS=$((PASSED_TESTS + suite_passed))
    FAILED_TESTS=$((FAILED_TESTS + suite_failed))
    TOTAL_TESTS=$((TOTAL_TESTS + suite_total))
  fi

  if [ ${exit_code} -eq 0 ]; then
    PASSED_SUITES=$((PASSED_SUITES + 1))
  else
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_NAMES+=("${name}")
  fi
  echo ""
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Engineering Workflow — Full Test Suite      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

run_suite "Classification Tests" "${SCRIPT_DIR}/run-classification-tests.sh"
run_suite "Constraint Resolution Tests" "${SCRIPT_DIR}/run-constraint-tests.sh"
run_suite "Agent Output Validation Tests" "${SCRIPT_DIR}/run-validation-tests.sh"
run_suite "Format Output Tests" "${SCRIPT_DIR}/run-format-tests.sh"
run_suite "Audit Analysis Tests" "${SCRIPT_DIR}/run-audit-tests.sh"
run_suite "Pipeline E2E Tests" "${SCRIPT_DIR}/run-pipeline-tests.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "=== Overall: ${PASSED_SUITES} suites passed, ${FAILED_SUITES} suites failed, ${TOTAL_SUITES} total ==="
echo "=== Tests:   ${PASSED_TESTS} passed, ${FAILED_TESTS} failed, ${TOTAL_TESTS} total ==="

if [ ${FAILED_SUITES} -gt 0 ]; then
  echo ""
  echo "Failed suites:"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  - ${name}"
  done
  exit 1
fi
