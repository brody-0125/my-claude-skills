#!/usr/bin/env bash
# validate-framework.sh — Shared validation framework for verify-doc-consistency.sh
#
# Usage: source "$(dirname "$0")/lib/validate-framework.sh"
#
# Provides:
#   init_validation       → Initialize counters
#   pass <message>        → Record passed check
#   fail <message>        → Record failed check
#   skip <message>        → Record skipped check
#   run_validator <name>  → Run a validator script
#   print_summary         → Print validation summary
#   get_exit_code         → Get exit code (0 = all pass, 1 = failures)

# --- Global Counters ---
VALIDATE_TOTAL=0
VALIDATE_PASSED=0
VALIDATE_FAILED=0
VALIDATE_SKIPPED=0

# --- Color Output (if terminal) ---
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# --- Initialize Validation ---
init_validation() {
    VALIDATE_TOTAL=0
    VALIDATE_PASSED=0
    VALIDATE_FAILED=0
    VALIDATE_SKIPPED=0
}

# --- Record Passed Check ---
pass() {
    VALIDATE_TOTAL=$((VALIDATE_TOTAL + 1))
    VALIDATE_PASSED=$((VALIDATE_PASSED + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

# --- Record Failed Check ---
fail() {
    VALIDATE_TOTAL=$((VALIDATE_TOTAL + 1))
    VALIDATE_FAILED=$((VALIDATE_FAILED + 1))
    echo -e "${RED}FAIL${NC}: $1"
}

# --- Record Skipped Check ---
skip() {
    VALIDATE_TOTAL=$((VALIDATE_TOTAL + 1))
    VALIDATE_SKIPPED=$((VALIDATE_SKIPPED + 1))
    echo -e "${YELLOW}SKIP${NC}: $1"
}

# --- Run Validator Script ---
# Usage: run_validator "check-build-consistency.sh" "$PLUGIN_ROOT"
run_validator() {
    local validator_name="$1"
    local plugin_root="$2"
    local validator_path

    # Find validator script
    validator_path="$(dirname "${BASH_SOURCE[0]}")/../validators/$validator_name"

    if [ -f "$validator_path" ]; then
        # Source the validator to share counters
        source "$validator_path" "$plugin_root"
    else
        skip "Validator not found: $validator_name"
    fi
}

# --- Print Section Header ---
section() {
    echo ""
    echo "=== $1 ==="
}

# --- Print Summary ---
print_summary() {
    echo ""
    echo "=== Summary ==="
    echo "Total checks: $VALIDATE_TOTAL"
    echo -e "Passed: ${GREEN}$VALIDATE_PASSED${NC}"
    if [ "$VALIDATE_FAILED" -gt 0 ]; then
        echo -e "Failed: ${RED}$VALIDATE_FAILED${NC}"
    else
        echo "Failed: $VALIDATE_FAILED"
    fi
    if [ "$VALIDATE_SKIPPED" -gt 0 ]; then
        echo -e "Skipped: ${YELLOW}$VALIDATE_SKIPPED${NC}"
    fi
}

# --- Get Exit Code ---
get_exit_code() {
    if [ "$VALIDATE_FAILED" -gt 0 ]; then
        echo 1
    else
        echo 0
    fi
}

# --- Extract Mutation Rate Helper ---
# Usage: extract_mutation_rate "file.md" "STANDARD"
extract_mutation_rate() {
    local file="$1"
    local tier="$2"
    local rate

    # Strategy: find the percentage that appears immediately after the tier name
    rate=$(grep -oP "${tier}\s*[=:→|]*\s*\K[0-9]+(?=\s*%)" "$file" 2>/dev/null | head -1 || true)
    if [ -z "$rate" ]; then
        # Fallback: find lines mentioning the tier, then extract the first percentage
        rate=$(grep -iP "\b${tier}\b" "$file" 2>/dev/null | grep -oP "${tier}\b.*?\K[0-9]+(?=%)" | head -1 || true)
    fi
    echo "$rate"
}

# Export functions if being sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f init_validation
    export -f pass
    export -f fail
    export -f skip
    export -f run_validator
    export -f section
    export -f print_summary
    export -f get_exit_code
    export -f extract_mutation_rate
    export VALIDATE_TOTAL VALIDATE_PASSED VALIDATE_FAILED VALIDATE_SKIPPED
fi
