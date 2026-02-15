#!/usr/bin/env bash
# Pipeline test runner — validates end-to-end flow: classify → audit tier → validate → format
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="${SCRIPT_DIR}/../scripts/classify-query.sh"
AUDIT="${SCRIPT_DIR}/../scripts/audit-analysis.sh"
VALIDATE="${SCRIPT_DIR}/../scripts/validate-agent-output.sh"
RESOLVE="${SCRIPT_DIR}/../scripts/resolve-constraints.sh"
FORMAT="${SCRIPT_DIR}/../scripts/format-output.sh"
SCENARIOS="${SCRIPT_DIR}/pipeline-scenarios.json"

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

echo "=== Pipeline E2E Test Suite ==="
echo ""

while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  desc=$(echo "${scenario}" | jq -r '.description')
  query=$(echo "${scenario}" | jq -r '.query')
  agent_output=$(echo "${scenario}" | jq -c '.agent_output')

  test_ok=true

  # ── Step 1: Classification ──────────────────────────────
  set +e
  classification=$(bash "${CLASSIFY}" "${query}" 2>/dev/null || echo '{"systems":[],"domains":[],"be_clusters":[],"confidence":0}')
  set -e

  expected_systems=$(echo "${scenario}" | jq -c '.expected.classification_systems')
  actual_systems=$(echo "${classification}" | jq -c '.systems // []')

  if [ "${actual_systems}" != "${expected_systems}" ]; then
    echo "  FAIL  ${id}: ${desc}"
    echo "         classify systems: expected=${expected_systems} actual=${actual_systems}"
    test_ok=false
  fi

  # Optional cluster check
  expected_clusters=$(echo "${scenario}" | jq -c '.expected.classification_clusters // null')
  if [ "${expected_clusters}" != "null" ]; then
    actual_clusters=$(echo "${classification}" | jq -c '.be_clusters // []')
    if [ "${actual_clusters}" != "${expected_clusters}" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         classify clusters: expected=${expected_clusters} actual=${actual_clusters}"
      test_ok=false
    fi
  fi

  # ── Step 2: Audit Tier Determination ────────────────────
  expected_tier=$(echo "${scenario}" | jq -r '.expected.tier // "null"')
  if [ "${expected_tier}" != "null" ]; then
    agent_count=$(echo "${classification}" | jq '[.domains[]?, .be_clusters[]?] | length' 2>/dev/null || echo "1")
    [ "${agent_count}" -eq 0 ] && agent_count=1

    set +e
    actual_tier=$(echo "${classification}" | bash "${AUDIT}" tier - "${agent_count}" 2>/dev/null | tr -d '[:space:]')
    set -e

    if [ "${actual_tier}" != "${expected_tier}" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         tier: expected=${expected_tier} actual=${actual_tier}"
      test_ok=false
    fi
  fi

  # ── Step 3: Validate Agent Output ───────────────────────
  expected_valid=$(echo "${scenario}" | jq -r '.expected.validation_valid // "null"')
  if [ "${expected_valid}" != "null" ]; then
    # Determine agent type from output structure
    has_systems_analyzed=$(echo "${agent_output}" | jq 'has("systems_analyzed")' 2>/dev/null || echo "false")
    has_system=$(echo "${agent_output}" | jq 'has("system")' 2>/dev/null || echo "false")

    if [ "${has_systems_analyzed}" = "true" ]; then
      agent_type="synthesizer"
    elif [ "${has_system}" = "true" ]; then
      agent_type="orchestrator"
    else
      agent_type="domain-agent"
    fi

    set +e
    validation=$(echo "${agent_output}" | bash "${VALIDATE}" "${agent_type}" 2>/dev/null)
    validate_exit=$?
    set -e

    if [ -z "${validation}" ]; then
      validation='{"valid":false,"errors":["validation script failed"]}'
    fi

    actual_valid=$(echo "${validation}" | jq -r '.valid' 2>/dev/null || echo "false")
    if [ "${actual_valid}" != "${expected_valid}" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         validation: expected=${expected_valid} actual=${actual_valid}"
      test_ok=false
    fi
  fi

  # ── Step 3.5: Resolve Constraints ─────────────────────
  expected_resolve_conflicts=$(echo "${scenario}" | jq -r '.expected.resolve_conflicts_count // "null"')
  if [ "${expected_resolve_conflicts}" != "null" ]; then
    # Write agent_output constraints to a temp file for resolve-constraints.sh
    constraints_json=$(echo "${agent_output}" | jq '{constraints: [.constraints[]? // empty]}' 2>/dev/null || echo '{"constraints":[]}')
    tmp_constraints=$(mktemp)
    echo "${constraints_json}" > "${tmp_constraints}"

    set +e
    resolve_result=$(bash "${RESOLVE}" "${tmp_constraints}" 2>/dev/null)
    resolve_exit=$?
    set -e
    rm -f "${tmp_constraints}"

    if [ -z "${resolve_result}" ]; then
      resolve_result='{"conflicts":[],"resolved_set":[]}'
    fi

    actual_conflicts=$(echo "${resolve_result}" | jq '.conflicts | length' 2>/dev/null || echo "0")
    if [ "${actual_conflicts}" != "${expected_resolve_conflicts}" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         resolve conflicts: expected=${expected_resolve_conflicts} actual=${actual_conflicts}"
      test_ok=false
    fi
  fi

  # ── Step 4: Format Output ──────────────────────────────
  expected_not_empty=$(echo "${scenario}" | jq -r '.expected.format_not_empty // "null"')
  expected_format_type=$(echo "${scenario}" | jq -r '.expected.format_type // "single-domain"')
  use_summary=$(echo "${scenario}" | jq -r '.expected.format_summary // false')

  if [ "${expected_not_empty}" != "null" ]; then
    format_args=()
    if [ "${use_summary}" = "true" ]; then
      format_args+=("--summary")
    fi
    format_args+=("${expected_format_type}")

    set +e
    format_result=$(echo "${agent_output}" | bash "${FORMAT}" "${format_args[@]}" 2>/dev/null)
    format_exit=$?
    set -e

    if [ "${expected_not_empty}" = "true" ] && [ -z "${format_result}" ]; then
      echo "  FAIL  ${id}: ${desc}"
      echo "         format output is empty"
      test_ok=false
    fi

    # Check contains if specified
    contains_count=$(echo "${scenario}" | jq '.expected.format_contains | length' 2>/dev/null || echo "0")
    for (( i=0; i<contains_count; i++ )); do
      expected_str=$(echo "${scenario}" | jq -r ".expected.format_contains[$i]")
      if ! echo "${format_result}" | grep -qF "${expected_str}"; then
        echo "  FAIL  ${id}: ${desc}"
        echo "         format missing expected string: \"${expected_str}\""
        test_ok=false
        break
      fi
    done
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
