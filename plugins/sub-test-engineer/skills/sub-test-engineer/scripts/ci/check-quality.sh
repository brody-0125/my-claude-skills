#!/usr/bin/env bash
# check-quality.sh — CI quality gate for sub-test-engineer plugin.
# Runs document consistency checks and optional benchmark regression detection.
#
# Usage: check-quality.sh [--with-regression <current-dir> [baseline-dir]]
# Exit code 0 if all pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS=0

echo "=== sub-test-engineer CI Quality Gate ==="
echo ""

# --- 1. Document consistency ---
echo "[1/2] Running document consistency checks..."
if bash "$SKILL_DIR/scripts/verify-doc-consistency.sh"; then
    echo "  PASS: Document consistency"
else
    echo "  FAIL: Document consistency"
    ((ERRORS++))
fi
echo ""

# --- 2. Benchmark regression (optional) ---
if [ "${1:-}" = "--with-regression" ]; then
    CURRENT_DIR="${2:?Usage: --with-regression <current-dir> [baseline-dir]}"
    BASELINE_DIR="${3:-}"

    echo "[2/2] Running benchmark regression checks..."
    if bash "$SKILL_DIR/scripts/benchmark/check-regression.sh" "$CURRENT_DIR" "$BASELINE_DIR"; then
        echo "  PASS: Regression checks"
    else
        echo "  FAIL: Regression checks"
        ((ERRORS++))
    fi
else
    echo "[2/2] Skipping regression checks (no --with-regression flag)"
fi

echo ""
echo "=== Quality Gate: $([ $ERRORS -eq 0 ] && echo 'PASSED' || echo 'FAILED') ==="

exit $ERRORS
