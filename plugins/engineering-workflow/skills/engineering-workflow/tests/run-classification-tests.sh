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

CACHE_DIR="${HOME}/.claude/cache/engineering-workflow"

echo "=== Classification Test Suite ==="
echo ""

# ── Setup helpers for progressive tests ───────────────────

# Write mock session history entries for progressive test setup
setup_progressive_history() {
  local entries_json="${1}"
  local age_minutes="${2:-0}"
  local history_file="${CACHE_DIR}/session-history.jsonl"

  # Clear existing history for clean test
  > "${history_file}" 2>/dev/null || true

  local entry_count
  entry_count=$(echo "${entries_json}" | jq 'length' 2>/dev/null || echo "0")

  for i in $(seq 0 $(( entry_count - 1 ))); do
    local entry
    entry=$(echo "${entries_json}" | jq ".[$i]")
    local sig="test-sig-${i}"
    local ts

    if [ "${age_minutes}" -gt 0 ]; then
      # Generate timestamp in the past
      ts=$(date -u -v-"${age_minutes}"M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
      ts=$(date -u -d "${age_minutes} minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
      ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    else
      ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    fi

    local prev_sig=""
    [ "${i}" -gt 0 ] && prev_sig="test-sig-$(( i - 1 ))"

    local history_entry
    history_entry=$(jq -cn \
      --arg sig "${sig}" \
      --arg query "test query ${i}" \
      --arg ts "${ts}" \
      --arg prev_sig "${prev_sig}" \
      --argjson classification "${entry}" \
      '{signature: $sig, query: $query, classification: $classification, timestamp: $ts, prev_signature: $prev_sig}')

    echo "${history_entry}" >> "${history_file}"
  done
}

cleanup_progressive_test() {
  local history_file="${CACHE_DIR}/session-history.jsonl"
  local cache_file="${CACHE_DIR}/pattern-cache.json"
  # Restore by clearing test entries (non-destructive: just truncate)
  > "${history_file}" 2>/dev/null || true
  # Remove __transitions__ from pattern cache (preserve other entries)
  if [ -f "${cache_file}" ]; then
    local cleaned
    cleaned=$(jq 'del(.__transitions__)' "${cache_file}" 2>/dev/null || cat "${cache_file}")
    echo "${cleaned}" > "${cache_file}" 2>/dev/null || true
  fi
}

# Save/restore pattern cache to isolate progressive tests from cache hits
save_pattern_cache() {
  local cache_file="${CACHE_DIR}/pattern-cache.json"
  if [ -f "${cache_file}" ]; then
    cp "${cache_file}" "${cache_file}.test-backup" 2>/dev/null || true
  fi
  # Use empty cache for progressive tests to avoid cache hits
  echo '{}' > "${cache_file}" 2>/dev/null || true
}

restore_pattern_cache() {
  local cache_file="${CACHE_DIR}/pattern-cache.json"
  if [ -f "${cache_file}.test-backup" ]; then
    mv "${cache_file}.test-backup" "${cache_file}" 2>/dev/null || true
  fi
}

# ── Main test loop ────────────────────────────────────────

# Use process substitution to avoid subshell counter loss
while IFS= read -r scenario; do
  TOTAL=$((TOTAL + 1))
  id=$(echo "${scenario}" | jq -r '.id')
  query=$(echo "${scenario}" | jq -r '.query')
  desc=$(echo "${scenario}" | jq -r '.description')
  test_type=$(echo "${scenario}" | jq -r '.type // "standard"')

  if [ "${test_type}" = "progressive" ]; then
    # ── Progressive Classification Test ─────────────────
    # Isolate progressive tests from pattern cache (avoid cache hits that skip progressive logic)
    save_pattern_cache
    cleanup_progressive_test

    setup_json=$(echo "${scenario}" | jq -c '.setup.prev_entries // []')
    age_minutes=$(echo "${scenario}" | jq -r '.setup.prev_entries_age_minutes // 0')
    env_vars=$(echo "${scenario}" | jq -c '.env // {}')

    # Setup session history
    setup_progressive_history "${setup_json}" "${age_minutes}"

    # Build env array for the command
    env_args=()
    while IFS= read -r key; do
      [ -z "${key}" ] && continue
      val=$(echo "${env_vars}" | jq -r ".\"${key}\"")
      env_args+=("${key}=${val}")
    done < <(echo "${env_vars}" | jq -r 'keys[]' 2>/dev/null || true)

    # Run classifier with env (use env command instead of eval for robustness)
    if [ ${#env_args[@]} -gt 0 ]; then
      result=$(env "${env_args[@]}" bash "${CLASSIFY}" "${query}" 2>/dev/null || echo '{"systems":[],"domains":[],"be_clusters":[],"se_clusters":[],"confidence":0,"prior_boost":0,"suggested_expansions":[]}')
    else
      result=$(bash "${CLASSIFY}" "${query}" 2>/dev/null || echo '{"systems":[],"domains":[],"be_clusters":[],"se_clusters":[],"confidence":0,"prior_boost":0,"suggested_expansions":[]}')
    fi

    # Validate progressive-specific expectations
    test_passed=true
    fail_details=""

    # Check systems if specified
    expected_systems=$(echo "${scenario}" | jq -c '.expected.systems // null')
    if [ "${expected_systems}" != "null" ]; then
      actual_systems=$(echo "${result}" | jq -c '.systems // []')
      if [ "${actual_systems}" != "${expected_systems}" ]; then
        test_passed=false
        fail_details="${fail_details}\n         systems: expected=${expected_systems} actual=${actual_systems}"
      fi
    fi

    # Check be_clusters if specified
    expected_clusters=$(echo "${scenario}" | jq -c '.expected.be_clusters // null')
    if [ "${expected_clusters}" != "null" ]; then
      actual_clusters=$(echo "${result}" | jq -c '.be_clusters // []')
      if [ "${actual_clusters}" != "${expected_clusters}" ]; then
        test_passed=false
        fail_details="${fail_details}\n         be_clusters: expected=${expected_clusters} actual=${actual_clusters}"
      fi
    fi

    # Check prior_boost > 0
    expected_boost_gt=$(echo "${scenario}" | jq -r '.expected.prior_boost_gt // "null"')
    if [ "${expected_boost_gt}" != "null" ]; then
      actual_boost=$(echo "${result}" | jq -r '.prior_boost // 0')
      if [ "$(awk "BEGIN { print (${actual_boost} <= ${expected_boost_gt}) }")" = "1" ]; then
        test_passed=false
        fail_details="${fail_details}\n         prior_boost: expected>${expected_boost_gt} actual=${actual_boost}"
      fi
    fi

    # Check prior_boost exact value
    expected_boost=$(echo "${scenario}" | jq -r '.expected.prior_boost // "null"')
    if [ "${expected_boost}" != "null" ]; then
      actual_boost=$(echo "${result}" | jq -r '.prior_boost // 0')
      if [ "$(awk "BEGIN { print (${actual_boost} != ${expected_boost}) }")" = "1" ]; then
        test_passed=false
        fail_details="${fail_details}\n         prior_boost: expected=${expected_boost} actual=${actual_boost}"
      fi
    fi

    # Check suggested_expansions
    expected_expansions=$(echo "${scenario}" | jq -c '.expected.suggested_expansions // null')
    if [ "${expected_expansions}" != "null" ]; then
      actual_expansions=$(echo "${result}" | jq -c '.suggested_expansions // []')
      if [ "${actual_expansions}" != "${expected_expansions}" ]; then
        test_passed=false
        fail_details="${fail_details}\n         suggested_expansions: expected=${expected_expansions} actual=${actual_expansions}"
      fi
    fi

    # Check transition recorded (verify pattern-cache has __transitions__)
    expected_transition=$(echo "${scenario}" | jq -r '.expected.transition_recorded // "null"')
    if [ "${expected_transition}" = "true" ]; then
      local_cache="${CACHE_DIR}/pattern-cache.json"
      has_transitions="false"
      if [ -f "${local_cache}" ]; then
        has_transitions=$(jq 'has("__transitions__")' "${local_cache}" 2>/dev/null || echo "false")
      fi
      if [ "${has_transitions}" != "true" ]; then
        test_passed=false
        fail_details="${fail_details}\n         transition_recorded: expected=true actual=false"
      fi
    fi

    cleanup_progressive_test
    restore_pattern_cache

    if $test_passed; then
      echo "  PASS  ${id}: ${desc}"
      PASSED=$((PASSED + 1))
    else
      echo "  FAIL  ${id}: ${desc}"
      FAILED=$((FAILED + 1))
      printf "%b\n" "${fail_details}"
    fi
  else
    # ── Standard Classification Test ─────────────────────
    expected_systems=$(echo "${scenario}" | jq -c '.expected.systems')
    expected_domains=$(echo "${scenario}" | jq -c '.expected.domains')
    expected_clusters=$(echo "${scenario}" | jq -c '.expected.be_clusters')
    expected_se_clusters=$(echo "${scenario}" | jq -c '.expected.se_clusters // []')
    expected_pattern=$(echo "${scenario}" | jq -r '.expected.pattern // ""')
    min_confidence=$(echo "${scenario}" | jq -r '.expected.min_confidence')

    # Run classifier
    result=$(bash "${CLASSIFY}" "${query}" 2>/dev/null || echo '{"systems":[],"domains":[],"be_clusters":[],"se_clusters":[],"confidence":0}')

    actual_systems=$(echo "${result}" | jq -c '.systems // []')
    actual_domains=$(echo "${result}" | jq -c '.domains // []')
    actual_clusters=$(echo "${result}" | jq -c '.be_clusters // []')
    actual_se_clusters=$(echo "${result}" | jq -c '.se_clusters // []')
    actual_pattern=$(echo "${result}" | jq -r '.pattern // ""')
    actual_confidence=$(echo "${result}" | jq -r '.confidence // 0')

    # Optional: classifier and needs_llm_verification checks
    expected_classifier=$(echo "${scenario}" | jq -r '.expected.classifier // ""')
    expected_needs_llm=$(echo "${scenario}" | jq -r '.expected.needs_llm_verification // "null"')
    actual_classifier=$(echo "${result}" | jq -r '.classifier // ""')
    actual_needs_llm=$(echo "${result}" | jq -r '.needs_llm_verification // "null"')

    # Compare
    systems_ok=true
    domains_ok=true
    clusters_ok=true
    se_clusters_ok=true
    pattern_ok=true
    confidence_ok=true
    classifier_ok=true
    needs_llm_ok=true

    if [ "${actual_systems}" != "${expected_systems}" ]; then systems_ok=false; fi
    if [ "${actual_domains}" != "${expected_domains}" ]; then domains_ok=false; fi
    if [ "${actual_clusters}" != "${expected_clusters}" ]; then clusters_ok=false; fi
    if [ "${expected_se_clusters}" != "[]" ] && [ "${actual_se_clusters}" != "${expected_se_clusters}" ]; then se_clusters_ok=false; fi
    if [ -n "${expected_pattern}" ] && [ "${actual_pattern}" != "${expected_pattern}" ]; then pattern_ok=false; fi
    if [ "${min_confidence}" != "0.0" ] && [ "${min_confidence}" != "0" ]; then
      if [ "$(awk "BEGIN { print (${actual_confidence} < ${min_confidence}) }")" = "1" ]; then
        confidence_ok=false
      fi
    fi
    if [ -n "${expected_classifier}" ] && [ "${actual_classifier}" != "${expected_classifier}" ]; then classifier_ok=false; fi
    if [ "${expected_needs_llm}" != "null" ] && [ "${actual_needs_llm}" != "${expected_needs_llm}" ]; then needs_llm_ok=false; fi

    # ── Extended field checks (optional) ─────────────────
    extended_ok=true
    extended_checks=$(echo "${scenario}" | jq -c '.extended_checks // null')
    if [ "${extended_checks}" != "null" ]; then
      # needs_llm_verification check (from extended_checks block)
      check_llm=$(echo "${extended_checks}" | jq -r '.needs_llm_verification // "null"')
      if [ "${check_llm}" != "null" ]; then
        actual_llm_ext=$(echo "${result}" | jq -r '.needs_llm_verification // "null"')
        if [ "${actual_llm_ext}" != "${check_llm}" ]; then
          extended_ok=false
        fi
      fi
      # archetype_contains check
      check_arch=$(echo "${extended_checks}" | jq -r '.archetype_contains // "null"')
      if [ "${check_arch}" != "null" ]; then
        arch_found=$(echo "${result}" | jq --arg a "${check_arch}" '[.archetype_matched[] | select(. == $a)] | length > 0' 2>/dev/null || echo "false")
        if [ "${arch_found}" != "true" ]; then
          extended_ok=false
        fi
      fi
      # archetype_empty check
      check_arch_empty=$(echo "${extended_checks}" | jq -r '.archetype_empty // "null"')
      if [ "${check_arch_empty}" = "true" ]; then
        arch_len=$(echo "${result}" | jq '.archetype_matched | length' 2>/dev/null || echo "0")
        if [ "${arch_len}" != "0" ]; then
          extended_ok=false
        fi
      fi
    fi

    if $systems_ok && $domains_ok && $clusters_ok && $se_clusters_ok && $pattern_ok && $confidence_ok && $classifier_ok && $needs_llm_ok && $extended_ok; then
      echo "  PASS  ${id}: ${desc}"
      PASSED=$((PASSED + 1))
    else
      echo "  FAIL  ${id}: ${desc}"
      FAILED=$((FAILED + 1))
      if ! $systems_ok; then echo "         systems: expected=${expected_systems} actual=${actual_systems}"; fi
      if ! $domains_ok; then echo "         domains: expected=${expected_domains} actual=${actual_domains}"; fi
      if ! $clusters_ok; then echo "         be_clusters: expected=${expected_clusters} actual=${actual_clusters}"; fi
      if ! $se_clusters_ok; then echo "         se_clusters: expected=${expected_se_clusters} actual=${actual_se_clusters}"; fi
      if ! $pattern_ok; then echo "         pattern: expected=${expected_pattern} actual=${actual_pattern}"; fi
      if ! $confidence_ok; then echo "         confidence: expected>=${min_confidence} actual=${actual_confidence}"; fi
      if ! $classifier_ok; then echo "         classifier: expected=${expected_classifier} actual=${actual_classifier}"; fi
      if ! $needs_llm_ok; then echo "         needs_llm_verification: expected=${expected_needs_llm} actual=${actual_needs_llm}"; fi
      if ! $extended_ok; then
        check_llm_v=$(echo "${extended_checks}" | jq -r '.needs_llm_verification // "null"' 2>/dev/null)
        if [ "${check_llm_v}" != "null" ]; then
          actual_llm_v=$(echo "${result}" | jq -r '.needs_llm_verification // "null"')
          if [ "${actual_llm_v}" != "${check_llm_v}" ]; then
            echo "         needs_llm_verification: expected=${check_llm_v} actual=${actual_llm_v}"
          fi
        fi
        check_arch_v=$(echo "${extended_checks}" | jq -r '.archetype_contains // "null"' 2>/dev/null)
        if [ "${check_arch_v}" != "null" ]; then
          arch_found_v=$(echo "${result}" | jq --arg a "${check_arch_v}" '[.archetype_matched[] | select(. == $a)] | length > 0' 2>/dev/null || echo "false")
          if [ "${arch_found_v}" != "true" ]; then
            actual_archetypes=$(echo "${result}" | jq -c '.archetype_matched // []' 2>/dev/null)
            echo "         archetype_matched: expected to contain '${check_arch_v}', actual=${actual_archetypes}"
          fi
        fi
        check_arch_empty_v=$(echo "${extended_checks}" | jq -r '.archetype_empty // "null"' 2>/dev/null)
        if [ "${check_arch_empty_v}" = "true" ]; then
          arch_len_v=$(echo "${result}" | jq '.archetype_matched | length' 2>/dev/null || echo "0")
          if [ "${arch_len_v}" != "0" ]; then
            echo "         archetype_matched: expected empty, got length=${arch_len_v}"
          fi
        fi
      fi
    fi
  fi
done < <(jq -c '.[]' "${SCENARIOS}")

echo ""
echo "=== Results: ${PASSED} passed, ${FAILED} failed, ${TOTAL} total ==="

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
