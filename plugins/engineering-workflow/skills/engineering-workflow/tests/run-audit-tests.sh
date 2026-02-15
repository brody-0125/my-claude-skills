#!/usr/bin/env bash
# Audit analysis test runner — validates audit-analysis.sh against scenarios
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="${SCRIPT_DIR}/../scripts/audit-analysis.sh"
SCENARIOS="${SCRIPT_DIR}/audit-scenarios.json"

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

echo "=== Audit Analysis Test Suite ==="
echo ""

while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  desc=$(echo "${scenario}" | jq -r '.description')
  mode=$(echo "${scenario}" | jq -r '.mode')

  input_data=$(echo "${scenario}" | jq -c '.input')
  test_ok=true

  case "${mode}" in
    confidence)
      expected_action=$(echo "${scenario}" | jq -r '.expected.action')
      expected_calibration=$(echo "${scenario}" | jq -r '.expected.has_calibration')

      set +e
      result=$(echo "${input_data}" | bash "${AUDIT}" confidence 2>/dev/null)
      audit_exit=$?
      set -e

      if [ -z "${result}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         no output from audit script"
        test_ok=false
      else
        actual_action=$(echo "${result}" | jq -r '.action' 2>/dev/null || echo "UNKNOWN")
        if [ "${actual_action}" != "${expected_action}" ]; then
          echo "  FAIL  ${id}: ${desc}"
          echo "         action: expected=${expected_action} actual=${actual_action}"
          test_ok=false
        fi

        if [ "${expected_calibration}" = "true" ]; then
          has_cal=$(echo "${result}" | jq 'has("calibration")' 2>/dev/null || echo "false")
          if [ "${has_cal}" != "true" ]; then
            echo "  FAIL  ${id}: ${desc}"
            echo "         expected calibration flag but not found"
            test_ok=false
          fi
        elif [ "${expected_calibration}" = "false" ]; then
          has_cal=$(echo "${result}" | jq 'has("calibration")' 2>/dev/null || echo "false")
          if [ "${has_cal}" = "true" ]; then
            echo "  FAIL  ${id}: ${desc}"
            echo "         unexpected calibration flag present"
            test_ok=false
          fi
        fi
      fi
      ;;

    orchestrator)
      expected_overall=$(echo "${scenario}" | jq -r '.expected.overall')

      set +e
      result=$(echo "${input_data}" | bash "${AUDIT}" orchestrator 2>/dev/null)
      audit_exit=$?
      set -e

      if [ -z "${result}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         no output from audit script"
        test_ok=false
      else
        actual_overall=$(echo "${result}" | jq -r '.overall' 2>/dev/null || echo "UNKNOWN")
        if [ "${actual_overall}" != "${expected_overall}" ]; then
          echo "  FAIL  ${id}: ${desc}"
          echo "         overall: expected=${expected_overall} actual=${actual_overall}"
          test_ok=false
        fi
      fi
      ;;

    synthesis)
      expected_overall=$(echo "${scenario}" | jq -r '.expected.overall')

      set +e
      result=$(echo "${input_data}" | bash "${AUDIT}" synthesis 2>/dev/null)
      audit_exit=$?
      set -e

      if [ -z "${result}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         no output from audit script"
        test_ok=false
      else
        actual_overall=$(echo "${result}" | jq -r '.overall' 2>/dev/null || echo "UNKNOWN")
        if [ "${actual_overall}" != "${expected_overall}" ]; then
          echo "  FAIL  ${id}: ${desc}"
          echo "         overall: expected=${expected_overall} actual=${actual_overall}"
          test_ok=false
        fi
      fi
      ;;

    tier)
      expected_tier=$(echo "${scenario}" | jq -r '.expected.tier')
      agent_count=$(echo "${scenario}" | jq -r '.agent_count // 1')

      set +e
      result=$(echo "${input_data}" | bash "${AUDIT}" tier - "${agent_count}" 2>/dev/null)
      audit_exit=$?
      set -e

      # tier mode outputs plain text (tier name)
      actual_tier=$(echo "${result}" | tr -d '[:space:]')
      if [ "${actual_tier}" != "${expected_tier}" ]; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         tier: expected=${expected_tier} actual=${actual_tier}"
        test_ok=false
      fi
      ;;

    *)
      echo "  FAIL  ${id}: ${desc}"
      echo "         unknown mode: ${mode}"
      test_ok=false
      ;;
  esac

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
