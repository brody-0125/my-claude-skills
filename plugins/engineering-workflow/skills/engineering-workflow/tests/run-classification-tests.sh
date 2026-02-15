#!/usr/bin/env bash
# Classification test runner — validates classify-query.sh against expected scenarios
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="${SCRIPT_DIR}/../scripts/classify-query.sh"
SCENARIOS="${SCRIPT_DIR}/classification-scenarios.json"

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

echo "=== Classification Test Suite ==="
echo ""

# Use process substitution to avoid subshell counter loss
while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  query=$(echo "${scenario}" | jq -r '.query')
  desc=$(echo "${scenario}" | jq -r '.description')
  expected_systems=$(echo "${scenario}" | jq -c '.expected.systems')
  expected_domains=$(echo "${scenario}" | jq -c '.expected.domains')
  expected_clusters=$(echo "${scenario}" | jq -c '.expected.be_clusters')
  min_confidence=$(echo "${scenario}" | jq -r '.expected.min_confidence')

  # Run classifier
  result=$(bash "${CLASSIFY}" "${query}" 2>/dev/null || echo '{"systems":[],"domains":[],"be_clusters":[],"confidence":0}')

  actual_systems=$(echo "${result}" | jq -c '.systems // []')
  actual_domains=$(echo "${result}" | jq -c '.domains // []')
  actual_clusters=$(echo "${result}" | jq -c '.be_clusters // []')
  actual_confidence=$(echo "${result}" | jq -r '.confidence // 0')

  # Compare
  systems_ok=true
  domains_ok=true
  clusters_ok=true
  confidence_ok=true

  if [ "${actual_systems}" != "${expected_systems}" ]; then systems_ok=false; fi
  if [ "${actual_domains}" != "${expected_domains}" ]; then domains_ok=false; fi
  if [ "${actual_clusters}" != "${expected_clusters}" ]; then clusters_ok=false; fi
  if [ "${min_confidence}" != "0.0" ] && [ "${min_confidence}" != "0" ]; then
    if [ "$(awk "BEGIN { print (${actual_confidence} < ${min_confidence}) }")" = "1" ]; then
      confidence_ok=false
    fi
  fi

  if $systems_ok && $domains_ok && $clusters_ok && $confidence_ok; then
    echo "  PASS  ${id}: ${desc}"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL  ${id}: ${desc}"
    FAILED=$((FAILED + 1))
    if ! $systems_ok; then echo "         systems: expected=${expected_systems} actual=${actual_systems}"; fi
    if ! $domains_ok; then echo "         domains: expected=${expected_domains} actual=${actual_domains}"; fi
    if ! $clusters_ok; then echo "         clusters: expected=${expected_clusters} actual=${actual_clusters}"; fi
    if ! $confidence_ok; then echo "         confidence: expected>=${min_confidence} actual=${actual_confidence}"; fi
  fi
done < <(jq -c '.[]' "${SCENARIOS}")

echo ""
echo "=== Results: ${PASSED} passed, ${FAILED} failed, ${TOTAL} total ==="

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
