#!/usr/bin/env bash
# collect-metrics.sh — Collects benchmark metrics from a project after skill execution.
# Usage: collect-metrics.sh <project-root> <output-json>
#
# Scans for:
#   - Generated test files (new/modified since benchmark start)
#   - Compilation results
#   - Test execution results
#   - Coverage reports
#   - Mutation reports

set -euo pipefail

PROJECT_ROOT="${1:?Usage: collect-metrics.sh <project-root> <output-json>}"
OUTPUT_FILE="${2:?Usage: collect-metrics.sh <project-root> <output-json>}"

cd "$PROJECT_ROOT"

# --- Count generated test files ---
TEST_FILES_KT=$(find . -name '*Test.kt' -newer .git/HEAD 2>/dev/null | wc -l || echo 0)
TEST_FILES_JAVA=$(find . -name '*Test.java' -newer .git/HEAD 2>/dev/null | wc -l || echo 0)
TEST_FILES_TS=$(find . \( -name '*.test.ts' -o -name '*.spec.ts' \) -newer .git/HEAD 2>/dev/null | wc -l || echo 0)
TOTAL_TEST_FILES=$((TEST_FILES_KT + TEST_FILES_JAVA + TEST_FILES_TS))

# --- Compilation check ---
COMPILE_SUCCESS="null"
if [ -f "gradlew" ]; then
    if ./gradlew compileTestKotlin compileTestJava --quiet 2>/dev/null; then
        COMPILE_SUCCESS="true"
    else
        COMPILE_SUCCESS="false"
    fi
elif [ -f "pom.xml" ]; then
    if mvn test-compile -q 2>/dev/null; then
        COMPILE_SUCCESS="true"
    else
        COMPILE_SUCCESS="false"
    fi
elif [ -f "package.json" ]; then
    if npx tsc --noEmit 2>/dev/null; then
        COMPILE_SUCCESS="true"
    else
        COMPILE_SUCCESS="false"
    fi
fi

# --- Test execution ---
TEST_PASS_COUNT=0
TEST_FAIL_COUNT=0
TEST_TOTAL=0
if [ -f "gradlew" ]; then
    TEST_OUTPUT=$(./gradlew test --quiet 2>&1 || true)
    # Parse JUnit XML reports for pass/fail counts
    for xml in $(find . -name 'TEST-*.xml' -path '*/test-results/*' 2>/dev/null); do
        TESTS=$(grep -oP 'tests="\K\d+' "$xml" 2>/dev/null | head -1 || echo 0)
        FAILURES=$(grep -oP 'failures="\K\d+' "$xml" 2>/dev/null | head -1 || echo 0)
        ERRORS=$(grep -oP 'errors="\K\d+' "$xml" 2>/dev/null | head -1 || echo 0)
        TEST_TOTAL=$((TEST_TOTAL + TESTS))
        TEST_FAIL_COUNT=$((TEST_FAIL_COUNT + FAILURES + ERRORS))
    done
    TEST_PASS_COUNT=$((TEST_TOTAL - TEST_FAIL_COUNT))
elif [ -f "pom.xml" ]; then
    mvn test -q 2>&1 || true
    for xml in $(find . -name 'TEST-*.xml' -path '*/surefire-reports/*' 2>/dev/null); do
        TESTS=$(grep -oP 'tests="\K\d+' "$xml" 2>/dev/null | head -1 || echo 0)
        FAILURES=$(grep -oP 'failures="\K\d+' "$xml" 2>/dev/null | head -1 || echo 0)
        ERRORS=$(grep -oP 'errors="\K\d+' "$xml" 2>/dev/null | head -1 || echo 0)
        TEST_TOTAL=$((TEST_TOTAL + TESTS))
        TEST_FAIL_COUNT=$((TEST_FAIL_COUNT + FAILURES + ERRORS))
    done
    TEST_PASS_COUNT=$((TEST_TOTAL - TEST_FAIL_COUNT))
fi

# --- Coverage parsing ---
COVERAGE_LINE="N/A"
COVERAGE_BRANCH="N/A"
JACOCO_XML=$(find . -name "jacocoTestReport.xml" -o -name "jacoco.xml" 2>/dev/null | head -1)
if [ -n "$JACOCO_XML" ] && [ -f "$JACOCO_XML" ]; then
    # Parse JaCoCo XML for overall counters
    LINE_MISSED=$(grep -oP 'type="LINE" missed="\K\d+' "$JACOCO_XML" 2>/dev/null | tail -1 || echo 0)
    LINE_COVERED=$(grep -oP 'type="LINE"[^/]*covered="\K\d+' "$JACOCO_XML" 2>/dev/null | tail -1 || echo 0)
    if [ "$((LINE_MISSED + LINE_COVERED))" -gt 0 ]; then
        COVERAGE_LINE=$(python3 -c "print(f'{$LINE_COVERED / ($LINE_MISSED + $LINE_COVERED) * 100:.1f}%')" 2>/dev/null || echo "N/A")
    fi
    BRANCH_MISSED=$(grep -oP 'type="BRANCH" missed="\K\d+' "$JACOCO_XML" 2>/dev/null | tail -1 || echo 0)
    BRANCH_COVERED=$(grep -oP 'type="BRANCH"[^/]*covered="\K\d+' "$JACOCO_XML" 2>/dev/null | tail -1 || echo 0)
    if [ "$((BRANCH_MISSED + BRANCH_COVERED))" -gt 0 ]; then
        COVERAGE_BRANCH=$(python3 -c "print(f'{$BRANCH_COVERED / ($BRANCH_MISSED + $BRANCH_COVERED) * 100:.1f}%')" 2>/dev/null || echo "N/A")
    fi
fi

# --- Mutation score ---
MUTATION_SCORE="N/A"
MUTATION_XML=$(find . -name "mutations.xml" -path "*/pitest/*" -o -name "mutations.xml" -path "*/pit-reports/*" 2>/dev/null | head -1)
if [ -n "$MUTATION_XML" ] && [ -f "$MUTATION_XML" ]; then
    KILLED=$(grep -c 'status="KILLED"' "$MUTATION_XML" 2>/dev/null || echo 0)
    SURVIVED=$(grep -c 'status="SURVIVED"' "$MUTATION_XML" 2>/dev/null || echo 0)
    M_TOTAL=$((KILLED + SURVIVED))
    if [ "$M_TOTAL" -gt 0 ]; then
        MUTATION_SCORE=$(python3 -c "print(f'{$KILLED / $M_TOTAL * 100:.1f}%')" 2>/dev/null || echo "N/A")
    fi
fi

# --- Normalize values for flat JSON output ---
# Convert percentage strings to numeric values (e.g., "75.3%" → 75.3), "N/A" → null
to_num_or_null() {
    local val="$1"
    if [ "$val" = "N/A" ] || [ -z "$val" ]; then
        echo "null"
    else
        echo "$val" | tr -d '%'
    fi
}

COVERAGE_LINE_NUM=$(to_num_or_null "$COVERAGE_LINE")
COVERAGE_BRANCH_NUM=$(to_num_or_null "$COVERAGE_BRANCH")
MUTATION_SCORE_NUM=$(to_num_or_null "$MUTATION_SCORE")

# Compute pass rate as numeric
PASS_RATE_NUM="null"
if [ "$TEST_TOTAL" -gt 0 ]; then
    PASS_RATE_NUM=$(python3 -c "print(round($TEST_PASS_COUNT/$TEST_TOTAL*100, 1))" 2>/dev/null || echo "null")
fi

# Derive project name from directory
PROJECT_NAME_DERIVED=$(basename "$PROJECT_ROOT" | sed 's/-[0-9]*$//')

# --- Write flat JSON output (matches check-regression.sh / compare-runs.sh schema) ---
cat > "$OUTPUT_FILE" <<METRICS_EOF
{
  "collected_at": "$(date -Iseconds)",
  "project_name": "$PROJECT_NAME_DERIVED",
  "compile_success": $COMPILE_SUCCESS,
  "tests_total": $TEST_TOTAL,
  "tests_passed": $TEST_PASS_COUNT,
  "tests_failed": $TEST_FAIL_COUNT,
  "pass_rate": $PASS_RATE_NUM,
  "coverage_line_pct": $COVERAGE_LINE_NUM,
  "coverage_branch_pct": $COVERAGE_BRANCH_NUM,
  "mutation_kill_pct": $MUTATION_SCORE_NUM,
  "generated_test_files": $TOTAL_TEST_FILES
}
METRICS_EOF

echo "[Metrics] Written to: $OUTPUT_FILE"
