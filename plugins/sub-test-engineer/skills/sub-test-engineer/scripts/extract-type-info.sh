#!/usr/bin/env bash
# extract-type-info.sh — Layer 2: ClassGraph bytecode enrichment for type extraction.
# Extracts cross-file class hierarchy, resolved generics, and sealed class subtypes
# from compiled JVM bytecode.
#
# Usage:
#   extract-type-info.sh <classpath> <target-pattern> [output-format]
#
# Arguments:
#   classpath       Path to compiled classes (e.g., build/classes/kotlin/main, target/classes)
#   target-pattern  Package pattern to scan (e.g., "com.example.order.**")
#   output-format   json (default) | yaml
#
# Prerequisites:
#   - java 17+ on PATH
#   - Project must be compiled (classes directory must exist)
#   - classgraph-extractor-all.jar must exist (see build instructions below)
#
# Build instructions (one-time):
#   cd scripts/classgraph-extractor && ./gradlew shadowJar
#
# Output:
#   JSON to stdout with extracted type information
#
# Examples:
#   extract-type-info.sh build/classes/kotlin/main "com.example.order.**"
#   extract-type-info.sh target/classes "com.example.order.**" json

set -euo pipefail

CLASSPATH_DIR="${1:?Usage: extract-type-info.sh <classpath> <target-pattern> [output-format]}"
TARGET_PATTERN="${2:?Usage: extract-type-info.sh <classpath> <target-pattern> [output-format]}"
OUTPUT_FORMAT="${3:-json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR_PATH="$SCRIPT_DIR/classgraph-extractor/build/libs/classgraph-extractor-all.jar"

# --- Prerequisite checks ---

# Check java
if ! command -v java &>/dev/null; then
    echo "[Layer2] ERROR: java not found on PATH" >&2
    echo "[Layer2] Install JDK 17+: https://adoptium.net/" >&2
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -1 | grep -oP '"(\d+)' | grep -oP '\d+' || echo "0")
if [ "$JAVA_VERSION" -lt 17 ]; then
    echo "[Layer2] ERROR: Java 17+ required (found: $JAVA_VERSION)" >&2
    exit 1
fi

# Check classpath directory
if [ ! -d "$CLASSPATH_DIR" ]; then
    echo "[Layer2] ERROR: Classpath directory not found: $CLASSPATH_DIR" >&2
    echo "[Layer2] Ensure the project is compiled first:" >&2
    echo "[Layer2]   Gradle: ./gradlew classes" >&2
    echo "[Layer2]   Maven:  mvn compile" >&2
    exit 1
fi

# Auto-build ClassGraph extractor JAR if missing and Gradle is available
EXTRACTOR_DIR="$SCRIPT_DIR/classgraph-extractor"
if [ ! -f "$JAR_PATH" ] && [ -f "$EXTRACTOR_DIR/build.gradle.kts" ]; then
    echo "[Layer 2] ClassGraph JAR not found. Building automatically..."
    if [ -f "$EXTRACTOR_DIR/gradlew" ]; then
        (cd "$EXTRACTOR_DIR" && ./gradlew shadowJar --quiet 2>&1) || true
    elif command -v gradle &>/dev/null; then
        (cd "$EXTRACTOR_DIR" && gradle shadowJar --quiet 2>&1) || true
    else
        echo "[Layer 2] WARNING: Cannot auto-build — no Gradle found. Run manually:"
        echo "  cd $EXTRACTOR_DIR && gradle shadowJar"
    fi
fi

# Check extractor JAR
if [ ! -f "$JAR_PATH" ]; then
    echo "[Layer2] WARNING: Extractor JAR not found: $JAR_PATH" >&2
    echo "[Layer2] Build it with: cd $SCRIPT_DIR/classgraph-extractor && ./gradlew shadowJar" >&2
    echo "[Layer2] Skipping Layer 2 enrichment (falling back to Layer 1a+1b)" >&2
    exit 1
fi

echo "[Layer2] Scanning: $CLASSPATH_DIR" >&2
echo "[Layer2] Pattern: $TARGET_PATTERN" >&2

# --- Execute ClassGraph extractor ---
java -jar "$JAR_PATH" \
    --classpath "$CLASSPATH_DIR" \
    --pattern "$TARGET_PATTERN" \
    --format "$OUTPUT_FORMAT" \
    2>/dev/null

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "[Layer2] ERROR: Extractor failed with exit code $EXIT_CODE" >&2
    echo "[Layer2] Falling back to Layer 1a+1b results" >&2
    exit 1
fi
