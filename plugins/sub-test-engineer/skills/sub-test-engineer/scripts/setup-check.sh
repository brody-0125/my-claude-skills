#!/usr/bin/env bash
# setup-check.sh — Pre-flight dependency check for sub-test-engineer.
# Checks all required and optional dependencies, reports status, and provides
# installation instructions for missing components.
#
# Usage: setup-check.sh [project-root]
# Exit code: 0 if core dependencies met, 1 if blocking dependencies missing.
#
# Called automatically by Phase 0 (Discover) on first invocation.

set -euo pipefail

PROJECT_ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0
WARNINGS=0

echo "=== sub-test-engineer Setup Check ==="
echo ""

# --- 1. Core: ast-grep ---
echo "[1/7] ast-grep (Layer 1a Type Extraction)..."
if command -v ast-grep &>/dev/null || command -v sg &>/dev/null; then
    VERSION=$(ast-grep --version 2>/dev/null || sg --version 2>/dev/null || echo "unknown")
    echo "  READY: ast-grep installed ($VERSION)"
else
    echo "  MISSING: ast-grep not found"
    echo "  Install: npm install -g @ast-grep/cli"
    echo "  Or:      cargo install ast-grep --locked"
    echo "  Or:      brew install ast-grep"
    echo "  Impact:  Layer 1a skipped → ~3x higher token cost for type extraction"
    ((WARNINGS++))
fi

# --- 2. Core: ast-grep rules ---
echo "[2/7] ast-grep rules..."
RULES_DIR="$SKILL_DIR/rules"
if [ -d "$RULES_DIR/java" ] && [ -d "$RULES_DIR/kotlin" ] && [ -d "$RULES_DIR/typescript" ]; then
    RULE_COUNT=$(find "$RULES_DIR" -name "extract-*.yml" 2>/dev/null | wc -l)
    echo "  READY: $RULE_COUNT extraction rules found"
else
    echo "  MISSING: Rule directories not found at $RULES_DIR"
    echo "  Impact:  Layer 1a type extraction will not work"
    ((ERRORS++))
fi

# --- 3. Build tool detection ---
echo "[3/7] Build tools..."
cd "$PROJECT_ROOT"
if [ -f "gradlew" ] || [ -f "build.gradle.kts" ] || [ -f "build.gradle" ]; then
    echo "  READY: Gradle project detected"
    BUILD_TOOL="gradle"
elif [ -f "pom.xml" ]; then
    echo "  READY: Maven project detected"
    BUILD_TOOL="maven"
elif [ -f "package.json" ]; then
    echo "  READY: Node.js project detected"
    BUILD_TOOL="npm"
else
    echo "  WARNING: No build tool detected (no gradlew, pom.xml, or package.json)"
    echo "  Impact:  Compilation and test execution will fail"
    ((WARNINGS++))
    BUILD_TOOL="none"
fi

# --- 4. Coverage tool ---
echo "[4/7] Coverage tools..."
COVERAGE_FOUND=false
if [ "$BUILD_TOOL" = "gradle" ]; then
    if grep -rq "jacoco\|kover" build.gradle.kts build.gradle 2>/dev/null; then
        echo "  READY: JaCoCo/Kover coverage plugin detected"
        COVERAGE_FOUND=true
    fi
elif [ "$BUILD_TOOL" = "maven" ]; then
    if grep -q "jacoco-maven-plugin\|kover" pom.xml 2>/dev/null; then
        echo "  READY: JaCoCo/Kover coverage plugin detected"
        COVERAGE_FOUND=true
    fi
elif [ "$BUILD_TOOL" = "npm" ]; then
    if grep -q '"jest"\|"vitest"\|"c8"\|"istanbul"' package.json 2>/dev/null; then
        echo "  READY: Coverage-capable test runner detected"
        COVERAGE_FOUND=true
    fi
fi
if [ "$COVERAGE_FOUND" = "false" ]; then
    echo "  MISSING: No coverage tool detected"
    if [ "$BUILD_TOOL" = "gradle" ]; then
        echo "  Add to build.gradle.kts:"
        echo '    plugins { id("jacoco") }'
    elif [ "$BUILD_TOOL" = "maven" ]; then
        echo "  Add to pom.xml: org.jacoco:jacoco-maven-plugin"
    elif [ "$BUILD_TOOL" = "npm" ]; then
        echo "  Add to package.json: jest --coverage or vitest --coverage"
    fi
    echo "  Impact:  Coverage measurement skipped → coverage-target mode unavailable"
    ((WARNINGS++))
fi

# --- 5. Mutation testing tool ---
echo "[5/7] Mutation testing tools..."
MUTATION_FOUND=false
if [ "$BUILD_TOOL" = "gradle" ]; then
    if grep -rq "pitest\|info.solidsoft.pitest" build.gradle.kts build.gradle 2>/dev/null; then
        echo "  READY: PIT mutation testing plugin detected"
        MUTATION_FOUND=true
    fi
elif [ "$BUILD_TOOL" = "maven" ]; then
    if grep -q "pitest-maven" pom.xml 2>/dev/null; then
        echo "  READY: PIT mutation testing plugin detected"
        MUTATION_FOUND=true
    fi
elif [ "$BUILD_TOOL" = "npm" ]; then
    if grep -q "stryker\|@stryker-mutator" package.json 2>/dev/null; then
        echo "  READY: Stryker mutation testing detected"
        MUTATION_FOUND=true
    fi
fi
if [ "$MUTATION_FOUND" = "false" ]; then
    echo "  OPTIONAL: No mutation testing tool detected"
    if [ "$BUILD_TOOL" = "gradle" ]; then
        echo '  Add to build.gradle.kts: id("info.solidsoft.pitest") version "1.15.0"'
    elif [ "$BUILD_TOOL" = "maven" ]; then
        echo "  Add to pom.xml: org.pitest:pitest-maven:1.15.0"
    elif [ "$BUILD_TOOL" = "npm" ]; then
        echo "  Run: npm install --save-dev @stryker-mutator/core"
    fi
    echo "  Impact:  Mutation kill rate not measured → STANDARD/THOROUGH validation degraded"
    ((WARNINGS++))
fi

# --- 6. Java 17+ (for Layer 2 ClassGraph) ---
echo "[6/7] Java 17+ (Layer 2 ClassGraph)..."
if command -v java &>/dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1 | grep -oP '\d+' | head -1)
    if [ "${JAVA_VERSION:-0}" -ge 17 ]; then
        echo "  READY: Java $JAVA_VERSION detected"

        # Check ClassGraph JAR
        JAR_PATH="$SKILL_DIR/scripts/classgraph-extractor/build/libs/classgraph-extractor-all.jar"
        if [ -f "$JAR_PATH" ]; then
            echo "  READY: ClassGraph extractor JAR found"
        else
            echo "  NOTE: ClassGraph JAR not built yet (will auto-build on first use)"
        fi
    else
        echo "  WARNING: Java $JAVA_VERSION detected (need 17+)"
        echo "  Impact:  Layer 2 (ClassGraph bytecode enrichment) unavailable"
        ((WARNINGS++))
    fi
else
    echo "  OPTIONAL: Java not found"
    echo "  Install: https://adoptium.net/ (Temurin JDK 17+)"
    echo "  Impact:  Layer 2 skipped → sealed class/cross-file generic resolution unavailable"
    ((WARNINGS++))
fi

# --- 7. .gitignore check ---
echo "[7/7] Cache directory (.sub-test-engineer/)..."
if [ -d "$PROJECT_ROOT/.sub-test-engineer" ]; then
    if [ -f "$PROJECT_ROOT/.gitignore" ] && grep -q ".sub-test-engineer" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        echo "  READY: Cache directory exists, .gitignore entry present"
    else
        echo "  NOTE: Cache directory exists but not in .gitignore"
        echo "  Will auto-add .sub-test-engineer/ to .gitignore"
        # Auto-add to .gitignore
        if [ -f "$PROJECT_ROOT/.gitignore" ]; then
            echo "" >> "$PROJECT_ROOT/.gitignore"
            echo "# sub-test-engineer cache" >> "$PROJECT_ROOT/.gitignore"
            echo ".sub-test-engineer/" >> "$PROJECT_ROOT/.gitignore"
            echo "  FIXED: Added .sub-test-engineer/ to .gitignore"
        fi
    fi
else
    echo "  OK: Cache directory will be created on first run"
fi

# --- Summary ---
echo ""
echo "=== Setup Check Summary ==="
echo "Blocking errors: $ERRORS"
echo "Warnings:        $WARNINGS"
echo ""

if [ "$ERRORS" -gt 0 ]; then
    echo "STATUS: BLOCKED — Fix $ERRORS error(s) before using /sub-test-engineer"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo "STATUS: READY (with $WARNINGS optional component(s) missing)"
    echo "The plugin will use graceful degradation for missing optional components."
    exit 0
else
    echo "STATUS: FULLY READY — All components available"
    exit 0
fi
