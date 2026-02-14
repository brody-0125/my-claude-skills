#!/usr/bin/env bash
# extract-types.sh — Extracts type information from source files using ast-grep.
# This is Layer 1a of the 3-Layer Type Extraction Pipeline.
#
# Usage:
#   extract-types.sh <target-path> [language] [rule-category]
#
# Arguments:
#   target-path     File or directory to analyze (required)
#   language        java|kotlin|typescript (auto-detected if omitted)
#   rule-category   methods|annotations|constructors|class-hierarchy|validation|all (default: all)
#
# Output:
#   JSON to stdout (NDJSON format, one match per line)
#   Summary to stderr
#
# Examples:
#   extract-types.sh src/main/java/com/example/OrderService.java
#   extract-types.sh src/main/kotlin/ kotlin all
#   extract-types.sh src/services/ typescript constructors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$(cd "$SCRIPT_DIR/../rules" && pwd)"

TARGET="${1:?Usage: extract-types.sh <target-path> [language] [rule-category]}"
LANG_HINT="${2:-}"
CATEGORY="${3:-all}"

# --- Locate ast-grep binary ---
SG_BIN=""
if command -v ast-grep &>/dev/null; then
    SG_BIN="ast-grep"
elif command -v sg &>/dev/null && sg --version 2>/dev/null | grep -q "ast-grep"; then
    SG_BIN="sg"
else
    echo "[extract-types] ast-grep not found. Falling back to LLM-only analysis." >&2
    echo "[extract-types] Install: npm install -g @ast-grep/cli" >&2
    exit 1
fi

# --- Detect language ---
detect_language() {
    local target="$1"

    if [ -n "$LANG_HINT" ]; then
        echo "$LANG_HINT"
        return
    fi

    if [ -f "$target" ]; then
        case "$target" in
            *.java) echo "java" ;;
            *.kt|*.kts) echo "kotlin" ;;
            *.ts|*.tsx) echo "typescript" ;;
            *) echo "unknown" ;;
        esac
    elif [ -d "$target" ]; then
        # Detect dominant language in directory
        local java_count kotlin_count ts_count
        java_count=$(find "$target" -name '*.java' 2>/dev/null | head -200 | wc -l)
        kotlin_count=$(find "$target" -name '*.kt' -o -name '*.kts' 2>/dev/null | head -200 | wc -l)
        ts_count=$(find "$target" -name '*.ts' -o -name '*.tsx' 2>/dev/null | head -200 | wc -l)

        if [ "$java_count" -ge "$kotlin_count" ] && [ "$java_count" -ge "$ts_count" ] && [ "$java_count" -gt 0 ]; then
            echo "java"
        elif [ "$kotlin_count" -ge "$java_count" ] && [ "$kotlin_count" -ge "$ts_count" ] && [ "$kotlin_count" -gt 0 ]; then
            echo "kotlin"
        elif [ "$ts_count" -gt 0 ]; then
            echo "typescript"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

LANGUAGE=$(detect_language "$TARGET")

if [ "$LANGUAGE" = "unknown" ]; then
    echo "[extract-types] Could not detect language for: $TARGET" >&2
    exit 1
fi

echo "[extract-types] Language: $LANGUAGE | Target: $TARGET | Category: $CATEGORY" >&2

# --- Map language to ast-grep lang flag and rule directory ---
case "$LANGUAGE" in
    java)       SG_LANG="java";       LANG_RULES_DIR="$RULES_DIR/java" ;;
    kotlin)     SG_LANG="kotlin";     LANG_RULES_DIR="$RULES_DIR/kotlin" ;;
    typescript) SG_LANG="typescript"; LANG_RULES_DIR="$RULES_DIR/typescript" ;;
    *)
        echo "[extract-types] Unsupported language: $LANGUAGE" >&2
        exit 1
        ;;
esac

# --- Map category to rule file(s) ---
get_rule_files() {
    local category="$1"
    local lang_dir="$2"

    case "$category" in
        methods|functions)
            find "$lang_dir" -name 'extract-methods.yml' -o -name 'extract-functions.yml' 2>/dev/null
            ;;
        annotations|decorators)
            find "$lang_dir" -name 'extract-annotations.yml' -o -name 'extract-decorators.yml' 2>/dev/null
            ;;
        constructors)
            find "$lang_dir" -name 'extract-constructors.yml' 2>/dev/null
            ;;
        class-hierarchy|classes)
            find "$lang_dir" -name 'extract-class-hierarchy.yml' 2>/dev/null
            ;;
        validation)
            find "$lang_dir" -name 'extract-validation.yml' 2>/dev/null
            ;;
        all)
            find "$lang_dir" -name '*.yml' 2>/dev/null
            ;;
        *)
            echo "[extract-types] Unknown category: $category" >&2
            echo "[extract-types] Valid: methods|annotations|constructors|class-hierarchy|validation|all" >&2
            exit 1
            ;;
    esac
}

RULE_FILES=$(get_rule_files "$CATEGORY" "$LANG_RULES_DIR")

if [ -z "$RULE_FILES" ]; then
    echo "[extract-types] No rules found for $LANGUAGE/$CATEGORY in $LANG_RULES_DIR" >&2
    exit 1
fi

# --- Execute ast-grep per rule and stream JSON ---
TOTAL_MATCHES=0

while IFS= read -r rule_file; do
    rule_id=$(basename "$rule_file" .yml)
    echo "[extract-types] Scanning with rule: $rule_id" >&2

    matches=$($SG_BIN scan --rule "$rule_file" "$TARGET" --json=stream 2>/dev/null || true)

    if [ -n "$matches" ]; then
        count=$(echo "$matches" | wc -l)
        TOTAL_MATCHES=$((TOTAL_MATCHES + count))
        echo "$matches"
        echo "[extract-types]   $rule_id: $count matches" >&2
    else
        echo "[extract-types]   $rule_id: 0 matches" >&2
    fi
done <<< "$RULE_FILES"

echo "[extract-types] Total: $TOTAL_MATCHES matches across $(echo "$RULE_FILES" | wc -l) rules" >&2
