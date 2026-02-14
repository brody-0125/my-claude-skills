#!/usr/bin/env bash
# Hook: Stop (session end quality gate)
# Runs tests for any changed test files before allowing session to end.
# Exits 2 if tests fail to block session end.

set -euo pipefail

# --- Detect project root ---
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$root" ]; then
    echo "[Hook] Not a git repository — skipping test gate"
    exit 0
fi

# --- Check for test file changes ---
changed=$(git -C "$root" diff --name-only HEAD -- \
    '*Test.kt' '*Test.java' '*Spec.kt' '*.test.ts' '*.spec.ts' 2>/dev/null || true)

if [ -z "$changed" ]; then
    echo "[Hook] No test file changes — skipping test gate"
    exit 0
fi

echo "[Hook] Test files changed:"
echo "$changed" | sed 's/^/  /'

cd "$root"

# --- Detect multi-module structure and extract module ---
MODULE_PREFIX=""
MOD_PATH=""
if [ -f settings.gradle.kts ] || [ -f settings.gradle ]; then
    SETTINGS_FILE=$([ -f settings.gradle.kts ] && echo settings.gradle.kts || echo settings.gradle)
    for f in $changed; do
        for mod_dir in $(grep -oP '(?<=include\("|include\s+\x27)[^"\x27]+' "$SETTINGS_FILE" 2>/dev/null | tr ':' '/'); do
            mod_dir=$(echo "$mod_dir" | sed 's|^/||')
            if echo "$f" | grep -q "^$mod_dir/"; then
                MODULE_PREFIX=":$(echo "$mod_dir" | tr '/' ':'):"
                MOD_PATH="$mod_dir"
                echo "[Hook] Detected module: $mod_dir"
                break 2
            fi
        done
    done
fi

# --- Run tests (capture exit code without triggering set -e) ---
test_result=0
if [ -f "gradlew" ]; then
    echo "[Hook] Running tests (Gradle)..."
    ./gradlew ${MODULE_PREFIX}test --quiet 2>&1 | tail -5 || test_result=$?
elif [ -f "pom.xml" ]; then
    echo "[Hook] Running tests (Maven)..."
    if [ -n "$MOD_PATH" ]; then
        mvn test -pl "$MOD_PATH" -q 2>&1 | tail -5 || test_result=$?
    else
        mvn test -q 2>&1 | tail -5 || test_result=$?
    fi
elif [ -f "package.json" ]; then
    echo "[Hook] Running tests (npm)..."
    npm test 2>&1 | tail -10 || test_result=$?
fi

if [ "$test_result" -ne 0 ]; then
    echo "[Hook] Generated tests failed. Fix before ending session."
    exit 2
fi

echo "[Hook] All tests passed."
