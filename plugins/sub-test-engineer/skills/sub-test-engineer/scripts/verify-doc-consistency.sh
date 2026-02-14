#!/usr/bin/env bash
# verify-doc-consistency.sh
# Verifies cross-reference consistency across sub-test-engineer plugin documents.
# Run from the plugin root or via this script (auto-detects plugin root).
#
# Modular design: Sources lib/validate-framework.sh for common functions.
# Individual validators can be added in scripts/validators/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source validation framework (provides pass, fail, skip, section, etc.)
source "$SCRIPT_DIR/lib/validate-framework.sh"

# Initialize validation counters
init_validation

# Legacy compatibility (ERRORS used in summary)
ERRORS=0
TOTAL=0

# Override pass/fail to track legacy counters too
pass() {
    TOTAL=$((TOTAL + 1))
    VALIDATE_TOTAL=$((VALIDATE_TOTAL + 1))
    VALIDATE_PASSED=$((VALIDATE_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    ERRORS=$((ERRORS + 1))
    VALIDATE_TOTAL=$((VALIDATE_TOTAL + 1))
    VALIDATE_FAILED=$((VALIDATE_FAILED + 1))
    echo "FAIL: $1"
}

# =============================================================================
echo "=== Rule 1: Build command consistency ==="
# =============================================================================

# measure-coverage.sh: Gradle support
if grep -q 'gradlew' "$PLUGIN_ROOT/scripts/measure-coverage.sh" 2>/dev/null; then
    pass "measure-coverage.sh supports Gradle"
else
    fail "measure-coverage.sh does not reference gradlew (missing Gradle support)"
fi

# measure-coverage.sh: Maven support
if grep -q 'pom\.xml' "$PLUGIN_ROOT/scripts/measure-coverage.sh" 2>/dev/null; then
    pass "measure-coverage.sh supports Maven"
else
    fail "measure-coverage.sh does not reference pom.xml (missing Maven support)"
fi

# measure-coverage.sh: MODULE_PATH parameter
if grep -q 'MODULE_PATH' "$PLUGIN_ROOT/scripts/measure-coverage.sh" 2>/dev/null; then
    pass "measure-coverage.sh accepts MODULE_PATH parameter"
else
    fail "measure-coverage.sh does not use MODULE_PATH variable"
fi

# run-mutation-test.sh: Gradle support
if grep -q 'gradlew' "$PLUGIN_ROOT/scripts/run-mutation-test.sh" 2>/dev/null; then
    pass "run-mutation-test.sh supports Gradle"
else
    fail "run-mutation-test.sh does not reference gradlew (missing Gradle support)"
fi

# run-mutation-test.sh: Maven support
if grep -q 'pom\.xml' "$PLUGIN_ROOT/scripts/run-mutation-test.sh" 2>/dev/null; then
    pass "run-mutation-test.sh supports Maven"
else
    fail "run-mutation-test.sh does not reference pom.xml (missing Maven support)"
fi

# run-mutation-test.sh: MODULE_PATH parameter
if grep -q 'MODULE_PATH' "$PLUGIN_ROOT/scripts/run-mutation-test.sh" 2>/dev/null; then
    pass "run-mutation-test.sh accepts MODULE_PATH parameter"
else
    fail "run-mutation-test.sh does not use MODULE_PATH variable"
fi

echo ""

# =============================================================================
echo "=== Rule 2: Tier threshold consistency ==="
# =============================================================================

# The authoritative source for tier boundaries is validation-tiers.md.
# strategize-protocol.md Section 5 may either duplicate the boundaries or reference validation-tiers.md.
# We extract boundaries from validation-tiers.md and verify strategize-protocol.md is consistent.

VALID_LIGHT_BOUND=""
VALID_STANDARD_LOWER=""
VALID_STANDARD_UPPER=""
VALID_THOROUGH_BOUND=""

if [ -f "$PLUGIN_ROOT/resources/validation-tiers.md" ]; then
    # LIGHT:     Count <= 2
    VALID_LIGHT_BOUND=$(grep -i 'LIGHT' "$PLUGIN_ROOT/resources/validation-tiers.md" | grep -oP '<=\s*\K[0-9]+' | head -1 || true)
    # STANDARD:  3 <= Count <= 8
    VALID_STANDARD_LOWER=$(grep -i 'STANDARD' "$PLUGIN_ROOT/resources/validation-tiers.md" | grep -oP '[0-9]+(?=\s*<=)' | head -1 || true)
    VALID_STANDARD_UPPER=$(grep -i 'STANDARD' "$PLUGIN_ROOT/resources/validation-tiers.md" | grep -oP '<=\s*\K[0-9]+' | tail -1 || true)
    # THOROUGH:  Count >= 9
    VALID_THOROUGH_BOUND=$(grep -i 'THOROUGH' "$PLUGIN_ROOT/resources/validation-tiers.md" | grep -oP '>=\s*\K[0-9]+' | head -1 || true)
fi

# Check LIGHT tier boundary in validation-tiers.md
if [ -n "$VALID_LIGHT_BOUND" ]; then
    pass "LIGHT tier boundary defined in validation-tiers.md (<=$VALID_LIGHT_BOUND)"
else
    fail "Could not extract LIGHT tier boundary from validation-tiers.md"
fi

# Check strategize-protocol.md references validation-tiers.md or has matching boundaries
STRAT_FILE="$PLUGIN_ROOT/resources/strategize-protocol.md"
if [ -f "$STRAT_FILE" ]; then
    # Check if strategize-protocol.md has explicit numeric LIGHT boundary
    STRAT_LIGHT_BOUND=$(grep -oP '<=\s*\K[0-9]+' "$STRAT_FILE" 2>/dev/null | head -1 || true)
    if [ -n "$STRAT_LIGHT_BOUND" ] && [ -n "$VALID_LIGHT_BOUND" ]; then
        if [ "$STRAT_LIGHT_BOUND" = "$VALID_LIGHT_BOUND" ]; then
            pass "LIGHT tier boundary matches between documents ($VALID_LIGHT_BOUND)"
        else
            fail "LIGHT tier boundary mismatch: strategize-protocol.md=$STRAT_LIGHT_BOUND vs validation-tiers.md=$VALID_LIGHT_BOUND"
        fi
    elif grep -q 'validation-tiers\.md' "$STRAT_FILE" 2>/dev/null; then
        pass "strategize-protocol.md delegates tier thresholds to validation-tiers.md"
    else
        fail "strategize-protocol.md has no tier boundaries and does not reference validation-tiers.md"
    fi
fi

# Check STANDARD range in validation-tiers.md
if [ -n "$VALID_STANDARD_LOWER" ] && [ -n "$VALID_STANDARD_UPPER" ]; then
    pass "STANDARD tier range defined in validation-tiers.md ($VALID_STANDARD_LOWER-$VALID_STANDARD_UPPER)"
else
    fail "Could not extract STANDARD tier range from validation-tiers.md"
fi

# Check THOROUGH boundary in validation-tiers.md
if [ -n "$VALID_THOROUGH_BOUND" ]; then
    pass "THOROUGH tier boundary defined in validation-tiers.md (>=$VALID_THOROUGH_BOUND)"
else
    fail "Could not extract THOROUGH tier boundary from validation-tiers.md"
fi

# Verify LIGHT upper + 1 == STANDARD lower (no gap between tiers)
if [ -n "$VALID_LIGHT_BOUND" ] && [ -n "$VALID_STANDARD_LOWER" ]; then
    EXPECTED_STD_LOWER=$((VALID_LIGHT_BOUND + 1))
    if [ "$VALID_STANDARD_LOWER" -eq "$EXPECTED_STD_LOWER" ]; then
        pass "No gap between LIGHT and STANDARD tiers ($VALID_LIGHT_BOUND -> $VALID_STANDARD_LOWER)"
    else
        fail "Gap between LIGHT (<=$VALID_LIGHT_BOUND) and STANDARD (>=$VALID_STANDARD_LOWER)"
    fi
fi

# Verify STANDARD upper + 1 == THOROUGH lower (no gap between tiers)
if [ -n "$VALID_STANDARD_UPPER" ] && [ -n "$VALID_THOROUGH_BOUND" ]; then
    EXPECTED_THOROUGH_LOWER=$((VALID_STANDARD_UPPER + 1))
    if [ "$VALID_THOROUGH_BOUND" -eq "$EXPECTED_THOROUGH_LOWER" ]; then
        pass "No gap between STANDARD and THOROUGH tiers ($VALID_STANDARD_UPPER -> $VALID_THOROUGH_BOUND)"
    else
        fail "Gap between STANDARD (<=$VALID_STANDARD_UPPER) and THOROUGH (>=$VALID_THOROUGH_BOUND)"
    fi
fi

echo ""

# =============================================================================
echo "=== Rule 3: Mutation kill rate consistency ==="
# =============================================================================

# Extract mutation rate for a given tier from a file.
# Handles formats like: "STANDARD=60%", "STANDARD → 60%", "STANDARD | 60% kill rate",
# and lines containing both tiers like "STANDARD=60%, THOROUGH=70%"
extract_mutation_rate() {
    local file="$1"
    local tier="$2"
    # Strategy: find the percentage that appears immediately after the tier name on the same line
    # Use grep -oP with lookbehind to capture the number right after TIER followed by optional separators
    local rate
    rate=$(grep -oP "${tier}\s*[=:→|]*\s*\K[0-9]+(?=\s*%)" "$file" 2>/dev/null | head -1 || true)
    if [ -z "$rate" ]; then
        # Fallback: find lines mentioning the tier, then extract the first percentage after the tier keyword
        rate=$(grep -iP "\b${tier}\b" "$file" 2>/dev/null | grep -oP "${tier}\b.*?\K[0-9]+(?=%)" | head -1 || true)
    fi
    echo "$rate"
}

SKILL_STANDARD=$(extract_mutation_rate "$PLUGIN_ROOT/SKILL.md" "STANDARD")
VALIDATE_STANDARD=$(extract_mutation_rate "$PLUGIN_ROOT/resources/validate-protocol.md" "STANDARD")
STRATEGIZE_STANDARD=$(extract_mutation_rate "$PLUGIN_ROOT/resources/strategize-protocol.md" "STANDARD")

if [ -n "$SKILL_STANDARD" ] && [ -n "$VALIDATE_STANDARD" ] && [ -n "$STRATEGIZE_STANDARD" ]; then
    if [ "$SKILL_STANDARD" = "$VALIDATE_STANDARD" ] && [ "$VALIDATE_STANDARD" = "$STRATEGIZE_STANDARD" ]; then
        pass "STANDARD mutation kill rate consistent across all docs (${SKILL_STANDARD}%)"
    else
        fail "STANDARD mutation kill rate mismatch: SKILL.md=${SKILL_STANDARD}% validate-protocol.md=${VALIDATE_STANDARD}% strategize-protocol.md=${STRATEGIZE_STANDARD}%"
    fi
else
    fail "Could not extract STANDARD mutation rate from all files (SKILL.md=${SKILL_STANDARD:-N/A} validate=${VALIDATE_STANDARD:-N/A} strategize=${STRATEGIZE_STANDARD:-N/A})"
fi

SKILL_THOROUGH=$(extract_mutation_rate "$PLUGIN_ROOT/SKILL.md" "THOROUGH")
VALIDATE_THOROUGH=$(extract_mutation_rate "$PLUGIN_ROOT/resources/validate-protocol.md" "THOROUGH")
STRATEGIZE_THOROUGH=$(extract_mutation_rate "$PLUGIN_ROOT/resources/strategize-protocol.md" "THOROUGH")

if [ -n "$SKILL_THOROUGH" ] && [ -n "$VALIDATE_THOROUGH" ] && [ -n "$STRATEGIZE_THOROUGH" ]; then
    if [ "$SKILL_THOROUGH" = "$VALIDATE_THOROUGH" ] && [ "$VALIDATE_THOROUGH" = "$STRATEGIZE_THOROUGH" ]; then
        pass "THOROUGH mutation kill rate consistent across all docs (${SKILL_THOROUGH}%)"
    else
        fail "THOROUGH mutation kill rate mismatch: SKILL.md=${SKILL_THOROUGH}% validate-protocol.md=${VALIDATE_THOROUGH}% strategize-protocol.md=${STRATEGIZE_THOROUGH}%"
    fi
else
    fail "Could not extract THOROUGH mutation rate from all files (SKILL.md=${SKILL_THOROUGH:-N/A} validate=${VALIDATE_THOROUGH:-N/A} strategize=${STRATEGIZE_THOROUGH:-N/A})"
fi

echo ""

# =============================================================================
echo "=== Rule 4: File reference validity ==="
# =============================================================================

# Parse all relative file references from SKILL.md
# Patterns: ./resources/..., ./references/..., ./scripts/..., ./rules/..., ./templates/...
REFS=$(grep -oP '\./(?:resources|references|scripts|rules|templates)/[^\s\)]+' "$PLUGIN_ROOT/SKILL.md" | sed 's/)$//' | sort -u)

if [ -z "$REFS" ]; then
    fail "No file references found in SKILL.md"
else
    while IFS= read -r ref; do
        # Strip trailing characters like ) or ]
        ref=$(echo "$ref" | sed 's/[)\]]*$//')
        full_path="$PLUGIN_ROOT/$ref"
        if [ -e "$full_path" ]; then
            pass "Reference exists: $ref"
        else
            fail "Reference not found: $ref (expected at $full_path)"
        fi
    done <<< "$REFS"
fi

echo ""

# =============================================================================
echo "=== Rule 5: Script parameter consistency ==="
# =============================================================================

# SKILL.md documents: measure-coverage.sh [project-root] [target-package] [module-path]
SKILL_COVERAGE_SIG=$(grep -oP 'measure-coverage\.sh\s+\[.*?\](?:\s+\[.*?\])*' "$PLUGIN_ROOT/SKILL.md" | head -1 || true)
SCRIPT_COVERAGE_SIG=$(grep -oP 'measure-coverage\.sh\s+\[.*?\](?:\s+\[.*?\])*' "$PLUGIN_ROOT/scripts/measure-coverage.sh" | head -1 || true)

if [ -n "$SKILL_COVERAGE_SIG" ] && [ -n "$SCRIPT_COVERAGE_SIG" ]; then
    if [ "$SKILL_COVERAGE_SIG" = "$SCRIPT_COVERAGE_SIG" ]; then
        pass "measure-coverage.sh signature matches between SKILL.md and script header"
    else
        fail "measure-coverage.sh signature mismatch: SKILL.md='$SKILL_COVERAGE_SIG' vs script='$SCRIPT_COVERAGE_SIG'"
    fi
elif [ -z "$SKILL_COVERAGE_SIG" ]; then
    fail "Could not extract measure-coverage.sh signature from SKILL.md"
elif [ -z "$SCRIPT_COVERAGE_SIG" ]; then
    fail "Could not extract measure-coverage.sh signature from script header"
fi

# SKILL.md documents: run-mutation-test.sh [project-root] [target-class-pattern] [tier] [module-path]
SKILL_MUTATION_SIG=$(grep -oP 'run-mutation-test\.sh\s+\[.*?\](?:\s+\[.*?\])*' "$PLUGIN_ROOT/SKILL.md" | head -1 || true)
SCRIPT_MUTATION_SIG=$(grep -oP 'run-mutation-test\.sh\s+\[.*?\](?:\s+\[.*?\])*' "$PLUGIN_ROOT/scripts/run-mutation-test.sh" | head -1 || true)

if [ -n "$SKILL_MUTATION_SIG" ] && [ -n "$SCRIPT_MUTATION_SIG" ]; then
    if [ "$SKILL_MUTATION_SIG" = "$SCRIPT_MUTATION_SIG" ]; then
        pass "run-mutation-test.sh signature matches between SKILL.md and script header"
    else
        fail "run-mutation-test.sh signature mismatch: SKILL.md='$SKILL_MUTATION_SIG' vs script='$SCRIPT_MUTATION_SIG'"
    fi
elif [ -z "$SKILL_MUTATION_SIG" ]; then
    fail "Could not extract run-mutation-test.sh signature from SKILL.md"
elif [ -z "$SCRIPT_MUTATION_SIG" ]; then
    fail "Could not extract run-mutation-test.sh signature from script header"
fi

echo ""

# =============================================================================
echo "=== Rule 6: Error playbook section numbering ==="
# =============================================================================

PLAYBOOK="$PLUGIN_ROOT/resources/error-playbook.md"
if [ -f "$PLAYBOOK" ]; then
    # Extract top-level section numbers (## N. pattern)
    SECTION_NUMS=$(grep -oP '^## \K[0-9]+' "$PLAYBOOK" | sort -n)

    if [ -z "$SECTION_NUMS" ]; then
        fail "No numbered sections found in error-playbook.md"
    else
        EXPECTED=1
        SEQUENTIAL=true
        while IFS= read -r num; do
            if [ "$num" -ne "$EXPECTED" ]; then
                fail "Section numbering gap in error-playbook.md: expected $EXPECTED, found $num"
                SEQUENTIAL=false
                break
            fi
            EXPECTED=$((EXPECTED + 1))
        done <<< "$SECTION_NUMS"

        if [ "$SEQUENTIAL" = true ]; then
            LAST_NUM=$(echo "$SECTION_NUMS" | tail -1)
            pass "Error playbook sections sequentially numbered (1-$LAST_NUM)"
        fi
    fi
else
    fail "error-playbook.md not found"
fi

echo ""

# =============================================================================
echo "=== Rule 7: ast-grep rule files exist ==="
# =============================================================================

# Check sgconfig.yml exists
if [ -f "$PLUGIN_ROOT/sgconfig.yml" ]; then
    pass "sgconfig.yml exists"
else
    fail "sgconfig.yml not found"
fi

# Check extract-*.yml files exist for each language
for LANG in java kotlin typescript go; do
    LANG_DIR="$PLUGIN_ROOT/rules/$LANG"
    if [ -d "$LANG_DIR" ]; then
        EXTRACT_FILES=$(find "$LANG_DIR" -maxdepth 1 -name 'extract-*.yml' -type f 2>/dev/null | sort)
        if [ -n "$EXTRACT_FILES" ]; then
            COUNT=$(echo "$EXTRACT_FILES" | wc -l)
            pass "rules/$LANG/ has $COUNT extract-*.yml files"
        else
            fail "rules/$LANG/ has no extract-*.yml files"
        fi
    else
        fail "rules/$LANG/ directory not found"
    fi
done

# Check test files exist for each language
for LANG in java kotlin typescript go; do
    TEST_DIR="$PLUGIN_ROOT/rules/__tests__/$LANG"
    if [ -d "$TEST_DIR" ]; then
        TEST_FILES=$(find "$TEST_DIR" -maxdepth 1 -name '*-test.yml' -type f 2>/dev/null | sort)
        if [ -n "$TEST_FILES" ]; then
            COUNT=$(echo "$TEST_FILES" | wc -l)
            pass "rules/__tests__/$LANG/ has $COUNT test files"
        else
            fail "rules/__tests__/$LANG/ has no test files"
        fi
    else
        fail "rules/__tests__/$LANG/ directory not found"
    fi
done

echo ""

# =============================================================================
echo "=== Rule 8: Optimization documents exist ==="
# =============================================================================

# Check consolidated reference documents exist
OPTIMIZATION_DOCS=(
    "resources/multi-module-context.md"
    "resources/error-handling-framework.md"
    "resources/phase-index.md"
)

for doc in "${OPTIMIZATION_DOCS[@]}"; do
    if [ -f "$PLUGIN_ROOT/$doc" ]; then
        pass "$doc exists"
    else
        fail "$doc not found (optimization document)"
    fi
done

# Check lib/ directory structure
if [ -d "$PLUGIN_ROOT/scripts/lib" ]; then
    pass "scripts/lib/ directory exists"

    # Check build-tool.sh library
    if [ -f "$PLUGIN_ROOT/scripts/lib/build-tool.sh" ]; then
        pass "scripts/lib/build-tool.sh exists"
    else
        fail "scripts/lib/build-tool.sh not found"
    fi

    # Check validate-framework.sh library
    if [ -f "$PLUGIN_ROOT/scripts/lib/validate-framework.sh" ]; then
        pass "scripts/lib/validate-framework.sh exists"
    else
        fail "scripts/lib/validate-framework.sh not found"
    fi
else
    fail "scripts/lib/ directory not found"
fi

# Check error-playbook.md has Level annotations (references error-handling-framework.md)
if grep -q 'error-handling-framework\.md' "$PLUGIN_ROOT/resources/error-playbook.md" 2>/dev/null; then
    pass "error-playbook.md references error-handling-framework.md"
else
    fail "error-playbook.md does not reference error-handling-framework.md"
fi

# Check protocols reference multi-module-context.md
if grep -q 'multi-module-context\.md' "$PLUGIN_ROOT/resources/test-discovery-protocol.md" 2>/dev/null; then
    pass "test-discovery-protocol.md references multi-module-context.md"
else
    fail "test-discovery-protocol.md does not reference multi-module-context.md"
fi

if grep -q 'multi-module-context\.md' "$PLUGIN_ROOT/resources/validate-protocol.md" 2>/dev/null; then
    pass "validate-protocol.md references multi-module-context.md"
else
    fail "validate-protocol.md does not reference multi-module-context.md"
fi

echo ""

# =============================================================================
echo "=== Summary ==="
# =============================================================================

PASSED=$((TOTAL - ERRORS))
echo "Total checks: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $ERRORS"

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi

exit 0
