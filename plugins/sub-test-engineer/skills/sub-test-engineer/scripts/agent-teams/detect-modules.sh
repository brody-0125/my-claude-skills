#!/usr/bin/env bash
# detect-modules.sh — Detect multi-module project structure
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   detect-modules.sh [project-root] [--json] [--with-deps]
#
# Arguments:
#   project-root : Path to project root (default: current directory)
#   --json       : Output as JSON (default: human-readable)
#   --with-deps  : Include inter-module dependencies
#
# Supports:
#   - Gradle multi-project (settings.gradle, settings.gradle.kts)
#   - Maven multi-module (pom.xml with <modules>)
#   - npm/pnpm workspaces (package.json with workspaces)
#   - Lerna monorepo (lerna.json)
#
# Output:
#   List of modules with paths, build tools, and optional dependencies

set -euo pipefail

# --- Argument Parsing ---
PROJECT_ROOT="${1:-.}"
JSON_OUTPUT=false
WITH_DEPS=false

for arg in "$@"; do
    case "$arg" in
        --json) JSON_OUTPUT=true ;;
        --with-deps) WITH_DEPS=true ;;
    esac
done

# Resolve absolute path
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)

# --- Helper Functions ---

# Detect Gradle multi-project
detect_gradle_modules() {
    local settings_file=""

    if [ -f "$PROJECT_ROOT/settings.gradle.kts" ]; then
        settings_file="$PROJECT_ROOT/settings.gradle.kts"
    elif [ -f "$PROJECT_ROOT/settings.gradle" ]; then
        settings_file="$PROJECT_ROOT/settings.gradle"
    else
        return 1
    fi

    # Extract include statements
    # Patterns: include("module"), include(":module"), include ':module'
    grep -E "include\s*[\(\"']" "$settings_file" 2>/dev/null | \
        sed -E "s/.*include\s*[\(\"':]+([^\"')]+).*/\1/" | \
        sed 's/^://' | \
        tr ':' '/' | \
        sort -u
}

# Detect Maven multi-module
detect_maven_modules() {
    local pom_file="$PROJECT_ROOT/pom.xml"

    if [ ! -f "$pom_file" ]; then
        return 1
    fi

    # Check if it's a parent POM with modules
    if ! grep -q "<modules>" "$pom_file"; then
        return 1
    fi

    # Extract module names
    grep -oP '(?<=<module>)[^<]+(?=</module>)' "$pom_file" 2>/dev/null | \
        sort -u
}

# Detect npm/pnpm workspaces
detect_npm_workspaces() {
    local package_file="$PROJECT_ROOT/package.json"

    if [ ! -f "$package_file" ]; then
        return 1
    fi

    # Check for workspaces field
    if ! grep -q '"workspaces"' "$package_file"; then
        # Check for pnpm-workspace.yaml
        if [ -f "$PROJECT_ROOT/pnpm-workspace.yaml" ]; then
            grep -E "^\s*-\s*" "$PROJECT_ROOT/pnpm-workspace.yaml" | \
                sed 's/^\s*-\s*//' | \
                sed "s/['\"]//g" | \
                sort -u
            return 0
        fi
        return 1
    fi

    # Extract workspaces using simple parsing (works for common cases)
    if command -v jq &>/dev/null; then
        jq -r '.workspaces // .workspaces.packages // [] | .[]' "$package_file" 2>/dev/null | \
            sort -u
    else
        # Fallback: simple grep
        grep -oP '(?<="workspaces"\s*:\s*\[)[^\]]+' "$package_file" | \
            tr ',' '\n' | \
            sed 's/["\s]//g' | \
            grep -v '^$' | \
            sort -u
    fi
}

# Detect Lerna monorepo
detect_lerna_packages() {
    local lerna_file="$PROJECT_ROOT/lerna.json"

    if [ ! -f "$lerna_file" ]; then
        return 1
    fi

    if command -v jq &>/dev/null; then
        jq -r '.packages // ["packages/*"] | .[]' "$lerna_file" 2>/dev/null
    else
        grep -oP '(?<="packages"\s*:\s*\[)[^\]]+' "$lerna_file" | \
            tr ',' '\n' | \
            sed 's/["\s]//g' | \
            grep -v '^$'
    fi
}

# Expand glob patterns to actual directories
expand_globs() {
    local pattern
    while read -r pattern; do
        # Handle glob patterns
        if [[ "$pattern" == *"*"* ]]; then
            # shellcheck disable=SC2086
            for dir in $PROJECT_ROOT/$pattern; do
                if [ -d "$dir" ]; then
                    echo "${dir#$PROJECT_ROOT/}"
                fi
            done
        else
            if [ -d "$PROJECT_ROOT/$pattern" ]; then
                echo "$pattern"
            fi
        fi
    done
}

# Detect build tool for a module
detect_module_build_tool() {
    local module_path="$1"
    local full_path="$PROJECT_ROOT/$module_path"

    if [ -f "$full_path/build.gradle.kts" ] || [ -f "$full_path/build.gradle" ]; then
        echo "gradle"
    elif [ -f "$full_path/pom.xml" ]; then
        echo "maven"
    elif [ -f "$full_path/package.json" ]; then
        echo "npm"
    else
        echo "unknown"
    fi
}

# Detect language for a module
detect_module_language() {
    local module_path="$1"
    local full_path="$PROJECT_ROOT/$module_path"

    local has_kotlin=false
    local has_java=false
    local has_ts=false

    # Check src directories
    if [ -d "$full_path/src" ]; then
        if find "$full_path/src" -name "*.kt" -type f 2>/dev/null | head -1 | grep -q .; then
            has_kotlin=true
        fi
        if find "$full_path/src" -name "*.java" -type f 2>/dev/null | head -1 | grep -q .; then
            has_java=true
        fi
        if find "$full_path/src" -name "*.ts" -type f 2>/dev/null | head -1 | grep -q .; then
            has_ts=true
        fi
    fi

    # Check root for TypeScript projects
    if [ -f "$full_path/tsconfig.json" ]; then
        has_ts=true
    fi

    if $has_kotlin && $has_java; then
        echo "kotlin+java"
    elif $has_kotlin; then
        echo "kotlin"
    elif $has_java; then
        echo "java"
    elif $has_ts; then
        echo "typescript"
    else
        echo "unknown"
    fi
}

# Get Gradle module dependencies
get_gradle_dependencies() {
    local module_path="$1"
    local build_file=""

    if [ -f "$PROJECT_ROOT/$module_path/build.gradle.kts" ]; then
        build_file="$PROJECT_ROOT/$module_path/build.gradle.kts"
    elif [ -f "$PROJECT_ROOT/$module_path/build.gradle" ]; then
        build_file="$PROJECT_ROOT/$module_path/build.gradle"
    else
        return
    fi

    # Extract project dependencies
    grep -oE 'project\s*\(\s*[":][^")]+' "$build_file" 2>/dev/null | \
        sed -E 's/project\s*\(\s*[":]*//' | \
        tr ':' '/' | \
        sort -u
}

# --- Main Detection ---

BUILD_SYSTEM=""
MODULES=()

# Try each detection method
if modules=$(detect_gradle_modules 2>/dev/null) && [ -n "$modules" ]; then
    BUILD_SYSTEM="gradle"
    while IFS= read -r module; do
        [ -n "$module" ] && MODULES+=("$module")
    done <<< "$modules"
elif modules=$(detect_maven_modules 2>/dev/null) && [ -n "$modules" ]; then
    BUILD_SYSTEM="maven"
    while IFS= read -r module; do
        [ -n "$module" ] && MODULES+=("$module")
    done <<< "$modules"
elif modules=$(detect_npm_workspaces 2>/dev/null) && [ -n "$modules" ]; then
    BUILD_SYSTEM="npm"
    while IFS= read -r module; do
        [ -n "$module" ] && MODULES+=("$module")
    done < <(echo "$modules" | expand_globs)
elif modules=$(detect_lerna_packages 2>/dev/null) && [ -n "$modules" ]; then
    BUILD_SYSTEM="lerna"
    while IFS= read -r module; do
        [ -n "$module" ] && MODULES+=("$module")
    done < <(echo "$modules" | expand_globs)
fi

# --- Output ---

MODULE_COUNT=${#MODULES[@]}

if [ "$MODULE_COUNT" -eq 0 ]; then
    if $JSON_OUTPUT; then
        echo '{"is_multi_module": false, "modules": [], "build_system": null}'
    else
        echo "Not a multi-module project (or single module)"
    fi
    exit 0
fi

if $JSON_OUTPUT; then
    echo "{"
    echo "  \"is_multi_module\": true,"
    echo "  \"build_system\": \"$BUILD_SYSTEM\","
    echo "  \"project_root\": \"$PROJECT_ROOT\","
    echo "  \"module_count\": $MODULE_COUNT,"
    echo "  \"modules\": ["

    first=true
    for module in "${MODULES[@]}"; do
        build_tool=$(detect_module_build_tool "$module")
        language=$(detect_module_language "$module")

        if $first; then first=false; else echo ","; fi

        echo -n "    {"
        echo -n "\"name\": \"$(basename "$module")\", "
        echo -n "\"path\": \"$module\", "
        echo -n "\"build_tool\": \"$build_tool\", "
        echo -n "\"language\": \"$language\""

        if $WITH_DEPS && [ "$BUILD_SYSTEM" = "gradle" ]; then
            deps=$(get_gradle_dependencies "$module" | tr '\n' ',' | sed 's/,$//')
            echo -n ", \"depends_on\": [$(echo "$deps" | sed 's/\([^,]*\)/"\1"/g')]"
        fi

        echo -n "}"
    done

    echo ""
    echo "  ],"
    echo "  \"agent_teams_recommended\": $([ "$MODULE_COUNT" -ge 3 ] && echo "true" || echo "false")"
    echo "}"
else
    echo "Multi-module project detected"
    echo "Build system: $BUILD_SYSTEM"
    echo "Module count: $MODULE_COUNT"
    echo ""
    echo "Modules:"
    for module in "${MODULES[@]}"; do
        build_tool=$(detect_module_build_tool "$module")
        language=$(detect_module_language "$module")
        echo "  - $module ($language, $build_tool)"

        if $WITH_DEPS && [ "$BUILD_SYSTEM" = "gradle" ]; then
            deps=$(get_gradle_dependencies "$module")
            if [ -n "$deps" ]; then
                echo "    depends on: $(echo "$deps" | tr '\n' ', ' | sed 's/,$//')"
            fi
        fi
    done

    echo ""
    if [ "$MODULE_COUNT" -ge 3 ]; then
        echo "Agent Teams recommended: Yes (≥3 modules)"
    else
        echo "Agent Teams recommended: No (<3 modules)"
    fi
fi
