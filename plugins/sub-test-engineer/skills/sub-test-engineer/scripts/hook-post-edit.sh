#!/usr/bin/env bash
# Hook: PostToolUse (Edit|Write)
# Compiles test files after modification to catch errors early.
# Receives tool input via $CLAUDE_TOOL_INPUT environment variable.

set -euo pipefail

# --- Extract file path from tool input ---
file=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null)

# Only proceed for test files
if [ -z "$file" ] || ! echo "$file" | grep -qE '(Test|Spec)\.(kt|java|ts|tsx)$'; then
    exit 0
fi

echo "[Hook] Test file modified: $file"

# --- Detect project root ---
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
cd "$PROJECT_ROOT"

# --- Detect multi-module structure and extract module prefix ---
MODULE_PREFIX=""
if [ -f settings.gradle.kts ] || [ -f settings.gradle ]; then
    SETTINGS_FILE=$([ -f settings.gradle.kts ] && echo settings.gradle.kts || echo settings.gradle)
    for mod_dir in $(grep -oP '(?<=include\("|include\s+\x27)[^"\x27]+' "$SETTINGS_FILE" 2>/dev/null | tr ':' '/'); do
        mod_dir=$(echo "$mod_dir" | sed 's|^/||')
        if echo "$file" | grep -q "^$mod_dir/"; then
            MODULE_PREFIX=":$(echo "$mod_dir" | tr '/' ':'):"
            echo "[Hook] Detected module: $mod_dir (prefix: $MODULE_PREFIX)"
            break
        fi
    done
fi

# --- Run compilation based on file type and build system ---
if echo "$file" | grep -qE '\.(kt|java)$'; then
    if [ -f gradlew ]; then
        echo "[Hook] Compiling test sources (Gradle)..."
        ./gradlew ${MODULE_PREFIX}compileTestKotlin ${MODULE_PREFIX}compileTestJava --quiet 2>&1 | tail -10 || true
    elif [ -f pom.xml ]; then
        MOD_PATH=""
        if [ -n "$MODULE_PREFIX" ]; then
            MOD_PATH=$(echo "$MODULE_PREFIX" | tr ':' '/' | sed 's|^/||;s|/$||')
        fi
        echo "[Hook] Compiling test sources (Maven)..."
        if [ -n "$MOD_PATH" ]; then
            mvn test-compile -pl "$MOD_PATH" -q 2>&1 | tail -10 || true
        else
            mvn test-compile -q 2>&1 | tail -10 || true
        fi
    fi
elif echo "$file" | grep -qE '\.(ts|tsx)$'; then
    echo "[Hook] Type-checking (tsc)..."
    npx tsc --noEmit 2>&1 | tail -10 || true
fi
