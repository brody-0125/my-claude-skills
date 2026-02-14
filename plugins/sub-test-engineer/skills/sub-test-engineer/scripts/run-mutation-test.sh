#!/usr/bin/env bash
# Usage: run-mutation-test.sh [project-root] [target-class-pattern] [tier] [module-path]
# Runs mutation testing based on detected tool and specified tier.
# When module-path is provided, commands are scoped to that module (multi-module project support).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-tool.sh"

PROJECT_ROOT="${1:-.}"
TARGET="${2:-}"
TIER="${3:-STANDARD}"
MODULE_PATH="${4:-}"

cd "$PROJECT_ROOT"

# Build Gradle module prefix if MODULE_PATH is set
GRADLE_MODULE_PREFIX=$(get_gradle_prefix "$MODULE_PATH")
if [ -n "$MODULE_PATH" ]; then
    echo "[Mutation] Module path: $MODULE_PATH (Gradle prefix: $GRADLE_MODULE_PREFIX)"
fi

# Skip for LIGHT tier
if [ "$TIER" = "LIGHT" ]; then
    echo "[Mutation] Tier=LIGHT — skipping mutation testing"
    exit 0
fi

# --- JVM: PIT ---
if [ -f "gradlew" ]; then
    # Determine which build config to check for pitest plugin
    GRADLE_CONFIG_CHECK="build.gradle.kts"
    if [ -n "$MODULE_PATH" ] && [ -f "$MODULE_PATH/build.gradle.kts" ]; then
        GRADLE_CONFIG_CHECK="$MODULE_PATH/build.gradle.kts"
    elif [ -n "$MODULE_PATH" ] && [ -f "$MODULE_PATH/build.gradle" ]; then
        GRADLE_CONFIG_CHECK="$MODULE_PATH/build.gradle"
    fi

    if grep -q "pitest" "$GRADLE_CONFIG_CHECK" 2>/dev/null || grep -q "pitest" build.gradle.kts 2>/dev/null || grep -q "pitest" build.gradle 2>/dev/null; then
        echo "[Mutation] Running PIT mutation testing..."
        PIT_ARGS=""
        if [ -n "$TARGET" ]; then
            PIT_ARGS="--targetClasses=$TARGET"
        fi
        ./gradlew ${GRADLE_MODULE_PREFIX}pitest $PIT_ARGS --quiet 2>&1 | tail -20
        if [ -n "$MODULE_PATH" ]; then
            REPORT=$(find "$MODULE_PATH" -name "index.html" -path "*/pitest/*" | head -1)
        else
            REPORT=$(find . -name "index.html" -path "*/pitest/*" | head -1)
        fi
        if [ -n "$REPORT" ]; then
            echo "[Mutation] HTML Report: $REPORT"
            # Parse XML report for mutation score
            if [ -n "$MODULE_PATH" ]; then
                XML_REPORT=$(find "$MODULE_PATH" -name "mutations.xml" -path "*/pitest/*" | head -1)
            else
                XML_REPORT=$(find . -name "mutations.xml" -path "*/pitest/*" | head -1)
            fi
            if [ -n "$XML_REPORT" ]; then
                KILLED=$(grep -c 'status="KILLED"' "$XML_REPORT" 2>/dev/null || echo 0)
                SURVIVED=$(grep -c 'status="SURVIVED"' "$XML_REPORT" 2>/dev/null || echo 0)
                TOTAL=$((KILLED + SURVIVED))
                if [ "$TOTAL" -gt 0 ]; then
                    SCORE=$((KILLED * 100 / TOTAL))
                    echo "[Mutation] Score: ${SCORE}% (${KILLED} killed / ${TOTAL} total)"
                fi
            fi
        fi
    else
        echo "[Mutation] PIT plugin not found in Gradle config"
        echo "[Mutation] Add: id(\"info.solidsoft.pitest\") to plugins block"
        exit 0
    fi

# --- JVM (Maven): PIT ---
elif [ -f "pom.xml" ]; then
    # Check module-specific or root pom.xml for pitest plugin
    MVN_POM_CHECK="pom.xml"
    if [ -n "$MODULE_PATH" ] && [ -f "$MODULE_PATH/pom.xml" ]; then
        MVN_POM_CHECK="$MODULE_PATH/pom.xml"
    fi

    MVN_MODULE_FLAG=""
    if [ -n "$MODULE_PATH" ]; then
        MVN_MODULE_FLAG="-pl $MODULE_PATH"
        echo "[Mutation] Maven module flag: $MVN_MODULE_FLAG"
    fi

    if grep -q "pitest-maven" "$MVN_POM_CHECK" 2>/dev/null || grep -q "pitest-maven" pom.xml 2>/dev/null; then
        echo "[Mutation] Running PIT mutation testing (Maven)..."
        PIT_ARGS=""
        if [ -n "$TARGET" ]; then
            PIT_ARGS="-DtargetClasses=$TARGET -DtargetTests=${TARGET}Test"
        fi
        mvn org.pitest:pitest-maven:mutationCoverage $PIT_ARGS $MVN_MODULE_FLAG -q 2>&1 | tail -20
        if [ -n "$MODULE_PATH" ]; then
            REPORT=$(find "$MODULE_PATH" -name "index.html" -path "*/pit-reports/*" | head -1)
        else
            REPORT=$(find . -name "index.html" -path "*/pit-reports/*" | head -1)
        fi
        if [ -n "$REPORT" ]; then
            echo "[Mutation] HTML Report: $REPORT"
            if [ -n "$MODULE_PATH" ]; then
                XML_REPORT=$(find "$MODULE_PATH" -name "mutations.xml" -path "*/pit-reports/*" | head -1)
            else
                XML_REPORT=$(find . -name "mutations.xml" -path "*/pit-reports/*" | head -1)
            fi
            if [ -n "$XML_REPORT" ]; then
                KILLED=$(grep -c 'status="KILLED"' "$XML_REPORT" 2>/dev/null || echo 0)
                SURVIVED=$(grep -c 'status="SURVIVED"' "$XML_REPORT" 2>/dev/null || echo 0)
                TOTAL=$((KILLED + SURVIVED))
                if [ "$TOTAL" -gt 0 ]; then
                    SCORE=$((KILLED * 100 / TOTAL))
                    echo "[Mutation] Score: ${SCORE}% (${KILLED} killed / ${TOTAL} total)"
                fi
            fi
        fi
    else
        echo "[Mutation] PIT plugin not found in Maven config"
        echo "[Mutation] Add: org.pitest:pitest-maven plugin to pom.xml"
        exit 0
    fi

# --- Node: Stryker ---
elif [ -f "package.json" ]; then
    if [ -f "stryker.config.mjs" ] || [ -f "stryker.conf.js" ] || grep -q "stryker" package.json 2>/dev/null; then
        echo "[Mutation] Running Stryker mutation testing..."
        STRYKER_ARGS=""
        if [ -n "$TARGET" ]; then
            STRYKER_ARGS="--mutate=$TARGET"
        fi
        npx stryker run $STRYKER_ARGS 2>&1 | tail -30
    else
        echo "[Mutation] Stryker not configured"
        echo "[Mutation] Run: npm install --save-dev @stryker-mutator/core && npx stryker init"
        exit 0
    fi
else
    echo "[Mutation] No build system detected"
    exit 1
fi
