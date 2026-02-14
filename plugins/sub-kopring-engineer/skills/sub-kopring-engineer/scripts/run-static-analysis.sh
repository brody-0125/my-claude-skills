#!/bin/bash
# run-static-analysis.sh - Allow-list based static analysis tool runner
# Usage: ./run-static-analysis.sh [project-root] [LIGHT|STANDARD|THOROUGH]
#
# Only runs tools specified in .sub-kopring-engineer/static-analysis-tools.txt.
# Available tools are determined by the tier.

set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
TIER="${2:-STANDARD}"

# --- Convert tier to number ---
tier_to_num() {
  case "$1" in
    LIGHT)    echo 1 ;;
    STANDARD) echo 2 ;;
    THOROUGH) echo 3 ;;
    *)        echo 2 ;;
  esac
}

TIER_NUM=$(tier_to_num "$TIER")

# --- Read allow-list ---
TOOLS_FILE="$PROJECT_DIR/.sub-kopring-engineer/static-analysis-tools.txt"

if [ ! -f "$TOOLS_FILE" ]; then
  echo "[static-analysis] allow-list not configured — skipping"
  exit 0
fi

ALLOWED_TOOLS=$(grep -v '^#' "$TOOLS_FILE" 2>/dev/null | grep -v '^$' || true)

if [ -z "$ALLOWED_TOOLS" ]; then
  echo "[static-analysis] allow-list is empty (none) — skipping"
  exit 0
fi

# --- Gradle wrapper check ---
BUILD_CMD=""
if [ -f "$PROJECT_DIR/gradlew" ]; then
  BUILD_CMD="$PROJECT_DIR/gradlew -p $PROJECT_DIR"
elif command -v gradle &>/dev/null; then
  BUILD_CMD="gradle -p $PROJECT_DIR"
else
  echo "[static-analysis] gradlew not found — skipping"
  exit 0
fi

# --- Result counters ---
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# --- Tool execution function ---
run_tool() {
  local tool="$1"
  local min_tier="$2"
  local command="$3"
  local description="$4"

  # allow-list check
  if ! echo "$ALLOWED_TOOLS" | grep -qx "$tool"; then
    return
  fi

  # tier check
  if [ "$TIER_NUM" -lt "$min_tier" ]; then
    echo "  ⊘ $description — below Tier $TIER (minimum: $([ "$min_tier" -eq 2 ] && echo STANDARD || echo THOROUGH))"
    ((SKIP_COUNT++)) || true
    return
  fi

  echo -n "  ▶ $description ... "
  if eval "$command" > /tmp/sa-output-$$.txt 2>&1; then
    echo "PASS"
    ((PASS_COUNT++)) || true
  else
    echo "FAIL"
    # Output only the last 5 lines as summary
    tail -5 /tmp/sa-output-$$.txt 2>/dev/null | sed 's/^/    /'
    ((FAIL_COUNT++)) || true
  fi
  rm -f /tmp/sa-output-$$.txt
}

# --- Execution ---
echo "═══════════════════════════════════════"
echo "  Static Analysis (allow-list based)"
echo "═══════════════════════════════════════"
echo "  Project: $PROJECT_DIR"
echo "  Tier: $TIER"
echo "  Tools: $(echo "$ALLOWED_TOOLS" | tr '\n' ', ' | sed 's/, $//')"
echo ""

run_tool "spotless"    2 "$BUILD_CMD spotlessCheck --quiet"                   "Spotless format check"
run_tool "detekt"      2 "$BUILD_CMD detekt --quiet"                          "detekt Kotlin analysis"
run_tool "checkstyle"  2 "$BUILD_CMD checkstyleMain --quiet"                  "Checkstyle Java style"
run_tool "archunit"    3 "$BUILD_CMD test --tests '*ArchTest*' --quiet"       "ArchUnit architecture tests"
run_tool "error-prone" 3 "$BUILD_CMD compileJava --quiet"                     "Error Prone compile-time analysis"

# --- Results summary ---
echo ""
echo "───────────────────────────────────────"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
echo "  Results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  SKIP=$SKIP_COUNT  (total $TOTAL)"
echo "───────────────────────────────────────"

exit "$FAIL_COUNT"
