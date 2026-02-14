#!/usr/bin/env bash
# run-benchmark.sh — Runs sub-test-engineer benchmark against a target project.
# Usage: run-benchmark.sh <project-config.yml> [output-dir]
#
# Requires: git, yq (or python3 for YAML parsing), claude CLI
# Workflow:
#   1. Clone target project at pinned commit
#   2. Measure baseline coverage (before)
#   3. Execute sub-test-engineer skill against specified targets
#   4. Measure final coverage (after)
#   5. Collect metrics → JSON output
#   6. Generate markdown report

# NOTE: Step 4 requires manual Claude Code session execution.
# Full automation requires claude CLI integration (future work).
# Run with: ./run-benchmark.sh projects/petclinic-kotlin.yml [output-dir]

set -euo pipefail

CONFIG="${1:?Usage: run-benchmark.sh <project-config.yml> [output-dir]}"
OUTPUT_DIR="${2:-results/$(date +%Y-%m-%d)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Parse config ---
parse_yaml() {
    # Use python3 for portable YAML parsing (yq not always available)
    python3 -c "
import sys, json
try:
    import yaml
except ImportError:
    print('ERROR: PyYAML not installed. Run: pip install pyyaml', file=sys.stderr)
    sys.exit(1)
with open('$1') as f:
    data = yaml.safe_load(f)
print(json.dumps(data))
" 2>/dev/null
}

CONFIG_JSON=$(parse_yaml "$CONFIG")
PROJECT_NAME=$(echo "$CONFIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['name'])")
REPO_URL=$(echo "$CONFIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['repo'])")
COMMIT=$(echo "$CONFIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['commit'])")
LANGUAGE=$(echo "$CONFIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['language'])")
BUILD_TOOL=$(echo "$CONFIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['build-tool'])")

echo "=== Benchmark: $PROJECT_NAME ==="
echo "Repo: $REPO_URL @ $COMMIT"
echo "Language: $LANGUAGE | Build: $BUILD_TOOL"
echo ""

# --- Setup ---
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/benchmark-${PROJECT_NAME}-XXXXXX")
cleanup() { rm -rf "$WORK_DIR" 2>/dev/null || true; }
trap cleanup EXIT
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

echo "[1/6] Cloning project..."
git clone --quiet "$REPO_URL" "$WORK_DIR/project" 2>/dev/null
cd "$WORK_DIR/project"
git checkout --quiet "$COMMIT"

echo "[2/6] Building project..."
if [ "$BUILD_TOOL" = "gradle" ] && [ -f "gradlew" ]; then
    ./gradlew classes testClasses --quiet 2>&1 | tail -3 || echo "WARN: Build had issues"
elif [ "$BUILD_TOOL" = "maven" ] && [ -f "pom.xml" ]; then
    mvn compile test-compile -q 2>&1 | tail -3 || echo "WARN: Build had issues"
elif [ "$BUILD_TOOL" = "npm" ] && [ -f "package.json" ]; then
    npm install --silent 2>&1 | tail -3 || echo "WARN: Install had issues"
fi

echo "[3/6] Measuring baseline coverage..."
BASELINE_REPORT="$OUTPUT_DIR/${PROJECT_NAME}-baseline.json"
"$SCRIPT_DIR/../measure-coverage.sh" "." "" > "$WORK_DIR/coverage-before.log" 2>&1 || true
# Capture baseline coverage percentage (parse from tool output)
BASELINE_COV=$(grep -oP '\d+\.?\d*%' "$WORK_DIR/coverage-before.log" | head -1 || echo "N/A")
echo "  Baseline coverage: $BASELINE_COV"

echo "[4/6] Running sub-test-engineer... (manual step)"
echo "  NOTE: This step requires manual execution of the Claude Code skill."
echo "  Run the following in a Claude Code session:"
echo ""
echo "    /sub-test-engineer {targets from config}. loop 3"
echo ""
echo "  After completion, press Enter to continue..."
# In automated mode, this would invoke claude CLI
# For now, we support manual execution
if [ -t 0 ]; then
    read -r
fi

echo "[5/6] Measuring final coverage..."
"$SCRIPT_DIR/../measure-coverage.sh" "." "" > "$WORK_DIR/coverage-after.log" 2>&1 || true
FINAL_COV=$(grep -oP '\d+\.?\d*%' "$WORK_DIR/coverage-after.log" | head -1 || echo "N/A")
echo "  Final coverage: $FINAL_COV"

echo "[6/6] Collecting metrics..."
"$SCRIPT_DIR/collect-metrics.sh" "$WORK_DIR/project" "$OUTPUT_DIR/${PROJECT_NAME}-metrics.json"

echo ""
echo "=== Benchmark Complete ==="
echo "Results: $OUTPUT_DIR/"
echo "  - ${PROJECT_NAME}-metrics.json"
echo "  - ${PROJECT_NAME}-baseline.json"

# Cleanup handled by trap
