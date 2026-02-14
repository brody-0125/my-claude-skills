#!/usr/bin/env bash
# verify-numeric.sh — Numerical computing convention verification
# Usage: ./verify-numeric.sh [path] [summary|detailed] [--changed-only]
#
# Checks 7 categories matching verify-protocol.md:
#   1. Floating-Point Correctness
#   2. Broadcasting Compliance
#   3. Shape Consistency
#   4. Test Case Integrity
#   5. Memory Safety
#   6. Special Value Handling
#   7. Performance Correctness (STANDARD/THOROUGH only)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Parse arguments ---
TARGET_PATH=""
OUTPUT_FORMAT="summary"
CHANGED_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-only) CHANGED_ONLY=true; shift ;;
    summary|detailed) OUTPUT_FORMAT="$1"; shift ;;
    *) TARGET_PATH="$1"; shift ;;
  esac
done

PROJECT_ROOT=$(find_project_root "${TARGET_PATH:-.}")
TARGET_PATH="${TARGET_PATH:-$PROJECT_ROOT}"
LANGUAGE=$(detect_language "$PROJECT_ROOT")

log_info "Verifying: $TARGET_PATH (language=$LANGUAGE, format=$OUTPUT_FORMAT)"

# --- Counters ---
PASS=0
FAIL=0
WARN=0
VIOLATIONS=""

add_violation() {
  local category="$1"
  local file="$2"
  local description="$3"
  local fix="$4"
  FAIL=$((FAIL + 1))
  VIOLATIONS="${VIOLATIONS}| $FAIL | $category | $file | $description | $fix |\n"
}

add_pass() {
  PASS=$((PASS + 1))
}

add_warn() {
  local msg="$1"
  WARN=$((WARN + 1))
  log_warn "$msg"
}

# --- Helper: resolve file path (handles both relative and absolute) ---
resolve_path() {
  local f="$1"
  if [ -f "$f" ]; then
    echo "$f"
  elif [ -f "$PROJECT_ROOT/$f" ]; then
    echo "$PROJECT_ROOT/$f"
  else
    echo ""
  fi
}

# --- Helper: grep files safely (no subshell `local` issue) ---
grep_in_files() {
  local pattern="$1"
  local exclude="${2:-}"
  local result=""

  while IFS= read -r f; do
    local full_path
    full_path=$(resolve_path "$f")
    [ -z "$full_path" ] && continue
    if [ -n "$exclude" ]; then
      result="${result}$(grep -n "$pattern" "$full_path" 2>/dev/null | grep -v "$exclude" | head -3 || true)"
    else
      result="${result}$(grep -n "$pattern" "$full_path" 2>/dev/null | head -3 || true)"
    fi
  done <<< "$FILES_TO_CHECK"

  echo "$result"
}

# --- Helper: count pattern in files ---
count_in_files() {
  local pattern="$1"
  local total=0

  while IFS= read -r f; do
    local full_path
    full_path=$(resolve_path "$f")
    [ -z "$full_path" ] && continue
    local c
    c=$(grep -c "$pattern" "$full_path" 2>/dev/null || echo 0)
    total=$((total + c))
  done <<< "$FILES_TO_CHECK"

  echo "$total"
}

# --- Determine files to check ---
FILES_TO_CHECK=""

if [ "$CHANGED_ONLY" = true ]; then
  case "$LANGUAGE" in
    python|mixed)
      FILES_TO_CHECK=$(get_changed_files "$PROJECT_ROOT" "py")
      ;;
    dart)
      FILES_TO_CHECK=$(get_changed_files "$PROJECT_ROOT" "dart")
      ;;
  esac
else
  case "$LANGUAGE" in
    python|mixed)
      FILES_TO_CHECK=$(find "$TARGET_PATH" -name "*.py" -not -path "*/\.*" -not -path "*/__pycache__/*" -not -path "*/venv/*" -not -path "*/.venv/*" 2>/dev/null | head -100)
      ;;
    dart)
      FILES_TO_CHECK=$(find "$TARGET_PATH" -name "*.dart" -not -path "*/\.*" -not -path "*/.dart_tool/*" 2>/dev/null | head -100)
      ;;
  esac
fi

if [ -z "$FILES_TO_CHECK" ]; then
  log_info "No files to check"
  exit 0
fi

FILE_COUNT=$(echo "$FILES_TO_CHECK" | wc -l)
log_info "Checking $FILE_COUNT files"

# ============================================================
# Category 1: Floating-Point Correctness
# ============================================================
log_info "Category 1: Floating-Point Correctness"

# Check 1.1: Direct float comparison with ==
BARE_COMPARE=$(grep_in_files "==" "test_\|#\|assert\|__eq__\|is None\|is not\|isinstance\|'=='\|\"==\"" | grep -i "float\|np\.\|array\|tensor" | head -10 || true)

if [ -n "$BARE_COMPARE" ]; then
  add_violation "Precision" "multiple" "Direct == comparison on float values" "Use np.allclose() or math.isclose()"
else
  add_pass
fi

# Check 1.2: Tests without tolerance (Python only)
if [ "$LANGUAGE" = "python" ] || [ "$LANGUAGE" = "mixed" ]; then
  NO_TOL=$(grep_in_files "assert.*==.*\." "allclose\|approx\|assert_array\|#\|shape\|dtype\|len(" | head -5 || true)

  if [ -n "$NO_TOL" ]; then
    add_violation "Precision" "test files" "Assertions without tolerance on float values" "Use assert_allclose(actual, expected, rtol=, atol=)"
  else
    add_pass
  fi
fi

# Check 1.3: Accumulation without stable algorithm
NAIVE_SUM=$(grep_in_files "for.*in.*:.*+=" "np\.sum\|math\.fsum\|torch\.\|#" | head -5 || true)

if [ -n "$NAIVE_SUM" ]; then
  add_warn "Potential naive accumulation detected (may lose precision for large sums)"
else
  add_pass
fi

# ============================================================
# Category 2: Broadcasting Compliance
# ============================================================
log_info "Category 2: Broadcasting Compliance"

SHAPE_ASSERT_COUNT=$(count_in_files "assert.*shape\|\.shape ==")
BROADCAST_COUNT=$(count_in_files "broadcast_to\|expand_dims\|np\.newaxis\|unsqueeze")

if [ "${BROADCAST_COUNT:-0}" -gt 0 ] && [ "${SHAPE_ASSERT_COUNT:-0}" -eq 0 ]; then
  add_violation "Broadcasting" "multiple" "Broadcasting operations without shape assertions" "Add assert statements to verify shapes before broadcast"
else
  add_pass
fi

# ============================================================
# Category 3: Shape Consistency
# ============================================================
log_info "Category 3: Shape Consistency"

UNSAFE_RESHAPE=$(grep_in_files "reshape(-1)\|\.flatten()\|\.ravel()" "#" | head -5 || true)

if [ -n "$UNSAFE_RESHAPE" ]; then
  add_warn "reshape(-1)/flatten() found — verify intent is correct"
else
  add_pass
fi

# ============================================================
# Category 4: Test Case Integrity
# ============================================================
log_info "Category 4: Test Case Integrity"

# Check for numeric test assertions
NUMERIC_ASSERT_COUNT=$(count_in_files "assert_allclose\|assert_array_equal\|assert_array_less\|pytest\.approx\|closeTo")

if [ "${NUMERIC_ASSERT_COUNT:-0}" -eq 0 ]; then
  add_warn "No numeric test assertions found (assert_allclose, pytest.approx, closeTo)"
else
  # Check for hardcoded expected values without comments
  MAGIC_EXPECTED=$(grep_in_files "assert_allclose.*\[.*\]\|expected.*=.*\[" "#.*reference\|#.*computed\|#.*from" | head -5 || true)
  if [ -n "$MAGIC_EXPECTED" ]; then
    add_warn "Hardcoded expected values found without reference comments — verify mathematical correctness"
  fi
  add_pass
fi

# Check for edge case tests
EDGE_TESTS=$(count_in_files "empty.*array\|NaN\|nan.*input\|inf.*input\|single.*element\|edge.*case\|boundary")
if [ "${EDGE_TESTS:-0}" -eq 0 ]; then
  add_warn "No edge case tests detected (empty array, NaN input, Inf input, boundary conditions)"
fi

# ============================================================
# Category 5: Memory Safety
# ============================================================
log_info "Category 5: Memory Safety"

# Check for view vs copy awareness
VIEW_MUTATION=$(grep_in_files "\[.*\].*=" "==" | grep -v "def \|#\|class \|import " | head -5 || true)
# This is mostly an LLM-verified category, so we just check basics
add_pass

# ============================================================
# Category 6: Special Value Handling
# ============================================================
log_info "Category 6: Special Value Handling"

# Check for NaN/Inf handling
NAN_GUARD_COUNT=$(count_in_files "isnan\|isinf\|nan_to_num\|nanmean\|nansum\|isFinite\|isNaN")

if [ "${NAN_GUARD_COUNT:-0}" -eq 0 ]; then
  add_warn "No NaN/Inf guard code detected — verify special values are handled"
fi

# Check for division without zero guard
DIV_OPS_COUNT=$(count_in_files "/ \|/=")
ZERO_GUARD_COUNT=$(count_in_files "!= 0\|> 0\|epsilon\|np\.divide\|np\.where.*denom\|safe_div")

if [ "${DIV_OPS_COUNT:-0}" -gt 5 ] && [ "${ZERO_GUARD_COUNT:-0}" -eq 0 ]; then
  add_violation "Special Value" "multiple" "Division operations without zero-guard code" "Add zero-checks or use np.divide with where parameter"
else
  add_pass
fi

# ============================================================
# Category 7: Performance Correctness (STANDARD/THOROUGH only)
# ============================================================
log_info "Category 7: Performance Correctness"

# Check for unnecessary host-device transfers in loops
GPU_IN_LOOP=$(grep_in_files "for.*:.*\.to(\|for.*:.*asarray\|for.*:.*\.cuda()" "" | head -5 || true)

if [ -n "$GPU_IN_LOOP" ]; then
  add_violation "Performance" "multiple" "Host-device transfer inside loop" "Move transfer outside loop, batch transfers"
else
  add_pass
fi

# ============================================================
# Output
# ============================================================
echo ""
TOTAL=$((PASS + FAIL))

if [ "$OUTPUT_FORMAT" = "detailed" ]; then
  echo "## Verify Results — $(date -Iseconds 2>/dev/null || date)"
  echo ""
  echo "### Passed: $PASS/$TOTAL items"
  echo "### Violations: $FAIL items"
  echo "### Warnings: $WARN items"

  if [ $FAIL -gt 0 ]; then
    echo ""
    echo "| # | Category | File | Description | Fix |"
    echo "|---|----------|------|-------------|-----|"
    echo -e "$VIOLATIONS"
  fi
else
  echo "Passed: $PASS/$TOTAL | Violations: $FAIL | Warnings: $WARN"
  if [ $FAIL -gt 0 ]; then
    echo -e "$VIOLATIONS"
  fi
fi

if [ $FAIL -gt 0 ]; then
  exit 1
else
  exit 0
fi
