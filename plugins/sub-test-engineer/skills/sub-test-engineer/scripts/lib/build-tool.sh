#!/usr/bin/env bash
# build-tool.sh — Shared library for build tool detection and execution
#
# Usage: source "$(dirname "$0")/lib/build-tool.sh"
#
# Provides:
#   detect_build_tool <dir>           → gradle|maven|npm|pnpm|go|unknown
#   get_gradle_prefix <module-path>   → Gradle module prefix (e.g., :modules:order:)
#   get_maven_flag <module-path>      → Maven module flag (e.g., -pl modules/order)
#   get_build_config <module-path>    → Path to build config file
#   check_plugin <plugin-name> [module-path]  → 0 if plugin found, 1 otherwise
#   run_gradle <task> [module-path] [extra-args]
#   run_maven <goal> [module-path] [extra-args]
#   run_npm <script> [extra-args]
#   find_source_root <dir>            → Source root path
#   find_test_root <dir>              → Test root path
#   detect_language <target>          → java|kotlin|typescript|go|unknown

set -euo pipefail

# --- Build Tool Detection ---
detect_build_tool() {
    local dir="${1:-.}"

    if [ -f "$dir/gradlew" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
        echo "gradle"
    elif [ -f "$dir/pom.xml" ]; then
        echo "maven"
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
        echo "pnpm"
    elif [ -f "$dir/package.json" ]; then
        echo "npm"
    elif [ -f "$dir/go.mod" ]; then
        echo "go"
    else
        echo "unknown"
    fi
}

# --- Gradle Module Prefix ---
# Converts filesystem path (e.g., modules/order-domain) to Gradle path (e.g., :modules:order-domain:)
get_gradle_prefix() {
    local module_path="${1:-}"

    if [ -z "$module_path" ]; then
        echo ""
    else
        echo ":$(echo "$module_path" | tr '/' ':'):"
    fi
}

# --- Maven Module Flag ---
# Returns -pl flag for Maven module (e.g., -pl modules/order)
get_maven_flag() {
    local module_path="${1:-}"

    if [ -z "$module_path" ]; then
        echo ""
    else
        echo "-pl $module_path"
    fi
}

# --- Get Build Config File ---
# Returns the appropriate build config file path
get_build_config() {
    local module_path="${1:-}"
    local project_root="${2:-.}"

    # Check module-specific config first
    if [ -n "$module_path" ]; then
        if [ -f "$project_root/$module_path/build.gradle.kts" ]; then
            echo "$project_root/$module_path/build.gradle.kts"
            return
        elif [ -f "$project_root/$module_path/build.gradle" ]; then
            echo "$project_root/$module_path/build.gradle"
            return
        elif [ -f "$project_root/$module_path/pom.xml" ]; then
            echo "$project_root/$module_path/pom.xml"
            return
        fi
    fi

    # Fall back to root config
    if [ -f "$project_root/build.gradle.kts" ]; then
        echo "$project_root/build.gradle.kts"
    elif [ -f "$project_root/build.gradle" ]; then
        echo "$project_root/build.gradle"
    elif [ -f "$project_root/pom.xml" ]; then
        echo "$project_root/pom.xml"
    else
        echo ""
    fi
}

# --- Check Plugin Presence ---
# Returns 0 if plugin is found, 1 otherwise
check_plugin() {
    local plugin_name="$1"
    local module_path="${2:-}"
    local project_root="${3:-.}"

    local config_file
    config_file=$(get_build_config "$module_path" "$project_root")

    if [ -z "$config_file" ]; then
        return 1
    fi

    # Check module config and root config
    if grep -q "$plugin_name" "$config_file" 2>/dev/null; then
        return 0
    fi

    # Also check root configs as fallback
    local root_config
    root_config=$(get_build_config "" "$project_root")
    if [ -n "$root_config" ] && [ "$root_config" != "$config_file" ]; then
        if grep -q "$plugin_name" "$root_config" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# --- Run Gradle Task ---
run_gradle() {
    local task="$1"
    local module_path="${2:-}"
    local extra_args="${3:-}"
    local project_root="${4:-.}"

    local prefix
    prefix=$(get_gradle_prefix "$module_path")

    local gradle_cmd="./gradlew"
    if [ ! -x "$project_root/gradlew" ]; then
        gradle_cmd="gradle"
    fi

    (cd "$project_root" && eval "$gradle_cmd ${prefix}${task} $extra_args")
}

# --- Run Maven Goal ---
run_maven() {
    local goal="$1"
    local module_path="${2:-}"
    local extra_args="${3:-}"
    local project_root="${4:-.}"

    local module_flag
    module_flag=$(get_maven_flag "$module_path")

    (cd "$project_root" && eval "mvn $goal $module_flag $extra_args")
}

# --- Run npm Script ---
run_npm() {
    local script="$1"
    local extra_args="${2:-}"
    local project_root="${3:-.}"

    local pkg_manager="npm"
    if [ -f "$project_root/pnpm-lock.yaml" ]; then
        pkg_manager="pnpm"
    elif [ -f "$project_root/yarn.lock" ]; then
        pkg_manager="yarn"
    fi

    (cd "$project_root" && $pkg_manager run "$script" $extra_args)
}

# --- Find Source Root ---
find_source_root() {
    local dir="${1:-.}"

    # Common source root patterns
    local candidates=(
        "src/main/kotlin"
        "src/main/java"
        "src"
        "app"
        "lib"
    )

    for candidate in "${candidates[@]}"; do
        if [ -d "$dir/$candidate" ]; then
            echo "$dir/$candidate"
            return
        fi
    done

    echo "$dir"
}

# --- Find Test Root ---
find_test_root() {
    local dir="${1:-.}"

    # Common test root patterns
    local candidates=(
        "src/test/kotlin"
        "src/test/java"
        "test"
        "tests"
        "__tests__"
        "spec"
    )

    for candidate in "${candidates[@]}"; do
        if [ -d "$dir/$candidate" ]; then
            echo "$dir/$candidate"
            return
        fi
    done

    echo "$dir"
}

# --- Detect Language ---
detect_language() {
    local target="$1"

    if [ -f "$target" ]; then
        case "$target" in
            *.java) echo "java" ;;
            *.kt|*.kts) echo "kotlin" ;;
            *.ts|*.tsx) echo "typescript" ;;
            *.go) echo "go" ;;
            *) echo "unknown" ;;
        esac
    elif [ -d "$target" ]; then
        # Count files to detect dominant language
        local java_count kotlin_count ts_count go_count
        java_count=$(find "$target" -name '*.java' 2>/dev/null | head -200 | wc -l)
        kotlin_count=$(find "$target" -name '*.kt' -o -name '*.kts' 2>/dev/null | head -200 | wc -l)
        ts_count=$(find "$target" -name '*.ts' -o -name '*.tsx' 2>/dev/null | head -200 | wc -l)
        go_count=$(find "$target" -name '*.go' 2>/dev/null | head -200 | wc -l)

        local max=$java_count
        local lang="java"

        if [ "$kotlin_count" -gt "$max" ]; then
            max=$kotlin_count
            lang="kotlin"
        fi
        if [ "$ts_count" -gt "$max" ]; then
            max=$ts_count
            lang="typescript"
        fi
        if [ "$go_count" -gt "$max" ]; then
            max=$go_count
            lang="go"
        fi

        if [ "$max" -gt 0 ]; then
            echo "$lang"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# --- Find Report File ---
# Searches for report files in build output directories
find_report() {
    local report_name="$1"
    local report_path_pattern="$2"
    local module_path="${3:-}"
    local project_root="${4:-.}"

    local search_dir="$project_root"
    if [ -n "$module_path" ]; then
        search_dir="$project_root/$module_path"
    fi

    find "$search_dir" -name "$report_name" -path "*$report_path_pattern*" 2>/dev/null | head -1
}

# Export functions if being sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f detect_build_tool
    export -f get_gradle_prefix
    export -f get_maven_flag
    export -f get_build_config
    export -f check_plugin
    export -f run_gradle
    export -f run_maven
    export -f run_npm
    export -f find_source_root
    export -f find_test_root
    export -f detect_language
    export -f find_report
fi
