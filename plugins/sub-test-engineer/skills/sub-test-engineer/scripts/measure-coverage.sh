#!/usr/bin/env bash
# Usage: measure-coverage.sh [project-root] [target-package] [module-path]
# Detects coverage tool and runs coverage report for the specified target.
# When module-path is provided, commands are scoped to that module (multi-module project support).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-tool.sh"

PROJECT_ROOT="${1:-.}"
TARGET_PACKAGE="${2:-}"
MODULE_PATH="${3:-}"

cd "$PROJECT_ROOT"

# Build Gradle module prefix if MODULE_PATH is set
GRADLE_MODULE_PREFIX=$(get_gradle_prefix "$MODULE_PATH")
if [ -n "$MODULE_PATH" ]; then
    echo "[Coverage] Module path: $MODULE_PATH (Gradle prefix: $GRADLE_MODULE_PREFIX)"
fi

# --- JVM Coverage ---
if [ -f "gradlew" ]; then
    # Detect coverage tool
    # Build test filter from TARGET_PACKAGE
    TEST_FILTER=""
    if [ -n "$TARGET_PACKAGE" ]; then
        # Convert package to test filter pattern (e.g., com.example.order → --tests "com.example.order.*")
        TEST_FILTER="--tests \"${TARGET_PACKAGE}.*\""
        echo "[Coverage] Filtering to package: $TARGET_PACKAGE"
    fi

    # Determine which build config to check for plugins
    BUILD_CONFIG_CHECK="build.gradle.kts"
    if [ -n "$MODULE_PATH" ] && [ -f "$MODULE_PATH/build.gradle.kts" ]; then
        BUILD_CONFIG_CHECK="$MODULE_PATH/build.gradle.kts"
    elif [ -n "$MODULE_PATH" ] && [ -f "$MODULE_PATH/build.gradle" ]; then
        BUILD_CONFIG_CHECK="$MODULE_PATH/build.gradle"
    fi

    if grep -q "jacoco" "$BUILD_CONFIG_CHECK" 2>/dev/null || grep -q "jacoco" build.gradle.kts 2>/dev/null || grep -q "jacoco" build.gradle 2>/dev/null; then
        echo "[Coverage] Running JaCoCo..."
        eval "./gradlew ${GRADLE_MODULE_PREFIX}test $TEST_FILTER ${GRADLE_MODULE_PREFIX}jacocoTestReport --quiet" 2>&1 | tail -5
        if [ -n "$MODULE_PATH" ]; then
            REPORT=$(find "$MODULE_PATH" -name "jacocoTestReport.xml" -path "*/build/*" | head -1)
        else
            REPORT=$(find . -name "jacocoTestReport.xml" -path "*/build/*" | head -1)
        fi
        if [ -n "$REPORT" ]; then
            echo "[Coverage] Report: $REPORT"
            if [ -n "$TARGET_PACKAGE" ]; then
                echo "[Coverage] Filter report to package: $TARGET_PACKAGE"
            fi
            echo "[Coverage] Parse this XML for line/branch coverage per class"
        fi
    elif grep -q "kover" "$BUILD_CONFIG_CHECK" 2>/dev/null || grep -q "kover" build.gradle.kts 2>/dev/null; then
        echo "[Coverage] Running Kover..."
        eval "./gradlew ${GRADLE_MODULE_PREFIX}test $TEST_FILTER ${GRADLE_MODULE_PREFIX}koverXmlReport --quiet" 2>&1 | tail -5
        if [ -n "$MODULE_PATH" ]; then
            REPORT=$(find "$MODULE_PATH" -name "report.xml" -path "*/kover/*" | head -1)
        else
            REPORT=$(find . -name "report.xml" -path "*/kover/*" | head -1)
        fi
        if [ -n "$REPORT" ]; then
            echo "[Coverage] Report: $REPORT"
        fi
    else
        echo "[Coverage] No coverage tool detected in Gradle config"
        echo "[Coverage] Consider adding JaCoCo or Kover plugin"
        exit 0
    fi

# --- JVM (Maven) ---
elif [ -f "pom.xml" ]; then
    # Check module-specific or root pom.xml for JaCoCo plugin
    MVN_POM_CHECK="pom.xml"
    if [ -n "$MODULE_PATH" ] && [ -f "$MODULE_PATH/pom.xml" ]; then
        MVN_POM_CHECK="$MODULE_PATH/pom.xml"
    fi

    MVN_MODULE_FLAG=""
    if [ -n "$MODULE_PATH" ]; then
        MVN_MODULE_FLAG="-pl $MODULE_PATH"
        echo "[Coverage] Maven module flag: $MVN_MODULE_FLAG"
    fi

    if grep -q "jacoco-maven-plugin" "$MVN_POM_CHECK" 2>/dev/null || grep -q "jacoco-maven-plugin" pom.xml 2>/dev/null; then
        echo "[Coverage] Running JaCoCo (Maven)..."
        MVN_TEST_FILTER=""
        if [ -n "$TARGET_PACKAGE" ]; then
            MVN_TEST_FILTER="-Dtest=\"${TARGET_PACKAGE}.*\""
            echo "[Coverage] Filtering to package: $TARGET_PACKAGE"
        fi
        eval "mvn test $MVN_TEST_FILTER jacoco:report $MVN_MODULE_FLAG -q" 2>&1 | tail -5
        if [ -n "$MODULE_PATH" ]; then
            REPORT=$(find "$MODULE_PATH" -name "jacoco.xml" -path "*/site/jacoco/*" | head -1)
        else
            REPORT=$(find . -name "jacoco.xml" -path "*/site/jacoco/*" | head -1)
        fi
        if [ -n "$REPORT" ]; then
            echo "[Coverage] Report: $REPORT"
            echo "[Coverage] Parse this XML for line/branch coverage per class"
        fi
    else
        echo "[Coverage] No coverage tool detected in Maven config"
        echo "[Coverage] Consider adding jacoco-maven-plugin"
        exit 0
    fi

# --- Node Coverage ---
elif [ -f "package.json" ]; then
    if grep -q "\"jest\"" package.json 2>/dev/null; then
        echo "[Coverage] Running Jest with coverage..."
        npx jest --coverage --coverageReporters=json --silent 2>&1 | tail -10
        REPORT="coverage/coverage-final.json"
        if [ -f "$REPORT" ]; then
            echo "[Coverage] Report: $REPORT"
        fi
    elif grep -q "\"vitest\"" package.json 2>/dev/null; then
        echo "[Coverage] Running Vitest with coverage..."
        npx vitest run --coverage --reporter=json --silent 2>&1 | tail -10
    else
        echo "[Coverage] No test runner detected in package.json"
        exit 0
    fi
else
    echo "[Coverage] No build system detected"
    exit 1
fi
