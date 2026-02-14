#!/bin/bash
# verify-conventions.sh - Kotlin/Java codebase convention verification script
# Usage: ./verify-conventions.sh [target-path] [output-format: summary|detailed] [--changed-only]
#
# If a project profile exists, layer paths and naming patterns are loaded dynamically.
# If no profile exists, falls back to hardcoded Hexagonal Architecture paths.
#
# Limitation: In multi-module projects, the profile is generated from the first module found.
# Modules with different layer structures may produce false positives/negatives.

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

TARGET_DIR="${1:-.}"
OUTPUT_FORMAT="${2:-summary}"

# --changed-only flag parsing
CHANGED_ONLY=false
for arg in "$@"; do
    [ "$arg" = "--changed-only" ] && CHANGED_ONLY=true
done

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================
# Load project profile
# =============================================
ARCH_PATTERN="hexagonal"
LAYER_APPLICATION="application"
LAYER_INFRASTRUCTURE="infrastructure"
LAYER_PRESENTATION="app"
ENTITY_SUFFIX="JpaEntity"
CONTROLLER_SUFFIX="RestController"
REPO_PATTERN="Reader/Appender/Updater"
TEST_STRUCTURE="flat"
LANGUAGE="kotlin"
FILE_EXT="kt"
SRC_LANG_DIR="kotlin"
DI_PATTERN="private val"
LINTER_CMD="ktlintCheck"
QUERY_LIB="none"
HAS_LOMBOK="false"

load_profile() {
    local project_dir
    project_dir="$(cd "$TARGET_DIR" && pwd)"
    local project_hash
    project_hash=$(project_path_hash "$project_dir")
    local cache_file="$HOME/.claude/cache/sub-kopring-engineer-${project_hash}-profile.md"

    if [ ! -f "$cache_file" ]; then
        echo -e "${YELLOW}No profile found — using default Hexagonal conventions${NC}"
        return
    fi

    echo -e "${CYAN}Loading profile: $cache_file${NC}"

    # Architecture pattern
    local arch
    arch=$(grep "^- architecture:" "$cache_file" 2>/dev/null | sed 's/^- architecture: //' | cut -d' ' -f1 || true)
    [ -n "$arch" ] && ARCH_PATTERN="$arch"

    # Language
    local lang
    lang=$(grep "^- language:" "$cache_file" 2>/dev/null | sed 's/^- language: //' || true)
    [ -n "$lang" ] && LANGUAGE="$lang"

    # Query library
    local qlib
    qlib=$(grep "^- query-lib:" "$cache_file" 2>/dev/null | sed 's/^- query-lib: //' || true)
    [ -n "$qlib" ] && QUERY_LIB="$qlib"

    # Lombok
    local lmb
    lmb=$(grep "^- lombok:" "$cache_file" 2>/dev/null | sed 's/^- lombok: //' || true)
    [ -n "$lmb" ] && HAS_LOMBOK="$lmb"

    # Language-specific variable settings
    case "$LANGUAGE" in
        java)
            FILE_EXT="java"
            SRC_LANG_DIR="java"
            DI_PATTERN="private final"
            LINTER_CMD="checkstyleMain"
            ;;
        mixed)
            FILE_EXT="kt"
            SRC_LANG_DIR="kotlin"
            DI_PATTERN="private val"
            LINTER_CMD="ktlintCheck"
            ;;
        *)
            FILE_EXT="kt"
            SRC_LANG_DIR="kotlin"
            DI_PATTERN="private val"
            LINTER_CMD="ktlintCheck"
            ;;
    esac

    # Layer paths (extract last path segment from Layer Paths section)
    local app_path infra_path pres_path
    app_path=$(grep "^- application:" "$cache_file" 2>/dev/null | sed 's/^- application: //' || true)
    infra_path=$(grep "^- infrastructure:" "$cache_file" 2>/dev/null | sed 's/^- infrastructure: //' || true)
    pres_path=$(grep "^- presentation:" "$cache_file" 2>/dev/null | sed 's/^- presentation: //' || true)

    # Use last segment from dot notation as directory name (e.g., com.example.application -> application)
    if [ -n "$app_path" ] && [ "$app_path" != "n/a" ]; then
        LAYER_APPLICATION="${app_path##*.}"
    fi
    if [ -n "$infra_path" ] && [ "$infra_path" != "n/a" ]; then
        LAYER_INFRASTRUCTURE="${infra_path##*.}"
    fi
    if [ -n "$pres_path" ] && [ "$pres_path" != "n/a" ]; then
        LAYER_PRESENTATION="${pres_path##*.}"
    fi

    # Naming patterns
    local entity_sfx ctrl_sfx repo_pat test_str
    entity_sfx=$(grep "^- entity-suffix:" "$cache_file" 2>/dev/null | sed 's/^- entity-suffix: //' || true)
    ctrl_sfx=$(grep "^- controller-suffix:" "$cache_file" 2>/dev/null | sed 's/^- controller-suffix: //' || true)
    repo_pat=$(grep "^- repository-pattern:" "$cache_file" 2>/dev/null | sed 's/^- repository-pattern: //' || true)
    test_str=$(grep "^- test-structure:" "$cache_file" 2>/dev/null | sed 's/^- test-structure: //' || true)

    [ -n "$entity_sfx" ] && ENTITY_SUFFIX="$entity_sfx"
    [ -n "$ctrl_sfx" ] && CONTROLLER_SUFFIX="$ctrl_sfx"
    [ -n "$repo_pat" ] && REPO_PATTERN="$repo_pat"
    [ -n "$test_str" ] && TEST_STRUCTURE="$test_str"
}

load_profile

# Changed file list (based on git diff)
CHANGED_FILES=""
if [ "$CHANGED_ONLY" = true ]; then
    if [ "$LANGUAGE" = "mixed" ]; then
        CHANGED_FILES=$(git -C "$TARGET_DIR" diff --name-only HEAD -- '*.kt' '*.java' 2>/dev/null || true)
    else
        CHANGED_FILES=$(git -C "$TARGET_DIR" diff --name-only HEAD -- "*.${FILE_EXT}" 2>/dev/null || true)
    fi
    if [ -z "$CHANGED_FILES" ]; then
        echo -e "${GREEN}No changed .${FILE_EXT} files — skipping verification${NC}"
        exit 0
    fi
    echo -e "${CYAN}Incremental verification mode: $(echo "$CHANGED_FILES" | wc -l | tr -d ' ') file(s)${NC}"
fi

# File filter: only pass changed files when --changed-only is set
filter_changed() {
    if [ "$CHANGED_ONLY" = false ]; then
        cat
    else
        while IFS= read -r file; do
            # Use relative path matching to avoid false positives with same-named files in different modules
            local rel_path
            rel_path=$(echo "$file" | sed "s|^$TARGET_DIR/||" | sed "s|^\./||")
            if echo "$CHANGED_FILES" | grep -qF "$rel_path"; then
                echo "$file"
            fi
        done
    fi
}

# File extension pattern (search both for mixed)
find_source_files() {
    local dir="$1"
    local name_pattern="$2"
    if [ "$LANGUAGE" = "mixed" ]; then
        find "$dir" \( -name "*.kt" -o -name "*.java" \) ${name_pattern:+-name "$name_pattern"} -type f 2>/dev/null | filter_changed
    else
        find "$dir" -name "*.${FILE_EXT}" ${name_pattern:+} -type f 2>/dev/null | filter_changed
    fi
}

echo "=========================================="
echo "  Kotlin/Java Codebase Convention Verifier"
echo "=========================================="
echo "Target: $TARGET_DIR"
echo "Language: $LANGUAGE (.$FILE_EXT) | Architecture: $ARCH_PATTERN"
echo "Layers: $LAYER_APPLICATION, $LAYER_INFRASTRUCTURE, $LAYER_PRESENTATION"
TOOLS_FILE_PATH="$(cd "$TARGET_DIR" && pwd)/.sub-kopring-engineer/static-analysis-tools.txt"
if [ -f "$TOOLS_FILE_PATH" ]; then
    SA_STATUS=$(grep -v '^#' "$TOOLS_FILE_PATH" 2>/dev/null | grep -v '^$' | tr '\n' ', ' | sed 's/, $//' || true)
    echo "Static analysis (allow-list): ${SA_STATUS:-none}"
else
    echo "Static analysis (allow-list): not configured"
fi
echo ""

VIOLATIONS=0
PASS=0
TOTAL=0
WARNINGS=0

report() {
    local status="$1"
    local category="$2"
    local message="$3"
    local file="$4"
    ((TOTAL++)) || true
    if [ "$status" = "PASS" ]; then
        ((PASS++)) || true
        [ "$OUTPUT_FORMAT" = "detailed" ] && echo -e "  ${GREEN}✓${NC} [$category] $message" || true
    elif [ "$status" = "WARN" ]; then
        ((WARNINGS++)) || true
        if [ -n "$file" ]; then
            echo -e "  ${YELLOW}△${NC} [$category] $message → $file"
        else
            echo -e "  ${YELLOW}△${NC} [$category] $message"
        fi
    else
        ((VIOLATIONS++)) || true
        if [ -n "$file" ]; then
            echo -e "  ${RED}✗${NC} [$category] $message → $file"
        else
            echo -e "  ${RED}✗${NC} [$category] $message"
        fi
    fi
}

# =============================================
# 1. Architecture layer verification
# =============================================
echo -e "${CYAN}[1/6] Architecture layer verification${NC}"

# UseCase cross-reference (Service→Service injection) — LLM 직접 검토 항목 (verify-protocol.md §3-1a #1)

# Infrastructure referencing Port check (hexagonal only)
if [ "$ARCH_PATTERN" = "hexagonal" ]; then
    while IFS= read -r file; do
        while IFS= read -r match; do
            line_num=$(echo "$match" | cut -d: -f1)
            report "FAIL" "Architecture" "Infrastructure references Port (Reader/Appender/Updater)" "$file:$line_num"
        done < <(grep -n "${DI_PATTERN}.*\(Reader\|Appender\|Updater\)" "$file" 2>/dev/null | grep -v "JpaRepository\|//\|/\*" || true)
    done < <(find "$TARGET_DIR" -path "*/${LAYER_INFRASTRUCTURE}/*" -name "*.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# Controller directly referencing Reader/Port check (hexagonal only)
if [ "$ARCH_PATTERN" = "hexagonal" ]; then
    while IFS= read -r file; do
        while IFS= read -r match; do
            line_num=$(echo "$match" | cut -d: -f1)
            report "FAIL" "Architecture" "Controller directly references Reader/Appender/Updater" "$file:$line_num"
        done < <(grep -n "${DI_PATTERN}.*\(Reader\|Appender\|Updater\|Port\)" "$file" 2>/dev/null | grep -v "//\|/\*" || true)
    done < <(find "$TARGET_DIR" -path "*/${LAYER_PRESENTATION}/*" -name "*Controller.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# General: @Transactional usage in Controller check (Fowler: no business logic in Presentation)
_ag_lang=$(ast_grep_lang)
if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
    while IFS= read -r match; do
        [ -z "$match" ] && continue
        _file="${match%%:*}"
        _line="${match#*:}"
        echo "$_file" | grep -q "/${LAYER_PRESENTATION}/" || continue
        basename "$_file" | grep -q "Controller\." || continue
        report "FAIL" "Architecture" "@Transactional in Controller (business logic should be in Service)" "$_file:$_line"
    done < <(ast_grep_matches "annotations/transactional" "$_ag_lang" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
else
    while IFS= read -r file; do
        while IFS= read -r match; do
            line_num=$(echo "$match" | cut -d: -f1)
            report "FAIL" "Architecture" "@Transactional in Controller (business logic should be in Service)" "$file:$line_num"
        done < <(grep -n "@Transactional" "$file" 2>/dev/null | grep -v "//\|/\*" || true)
    done < <(find "$TARGET_DIR" -path "*/${LAYER_PRESENTATION}/*" -name "*Controller.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# Module dependency direction verification (multi-module only)
# Checks build.gradle.kts for prohibited inter-module dependencies
check_module_deps() {
    local project_dir
    project_dir="$(cd "$TARGET_DIR" && pwd)"
    local settings_file=""
    for sf in "$project_dir/settings.gradle.kts" "$project_dir/settings.gradle"; do
        [ -f "$sf" ] && settings_file="$sf" && break
    done
    [ -z "$settings_file" ] && return

    # Classify module role by name suffix: *-core → core, *-application → application, etc.
    classify_module_role() {
        local mod="$1"
        case "$mod" in
            *-core|core)              echo "core" ;;
            *-application|application) echo "application" ;;
            *-infrastructure|infrastructure) echo "infrastructure" ;;
            *-api|api)                echo "api" ;;
            bootstrap|*-bootstrap)    echo "bootstrap" ;;
            shared-kernel)            echo "shared-kernel" ;;
            *)                        echo "unknown" ;;
        esac
    }

    # Check if dep_role is forbidden for source_role
    is_forbidden_dep() {
        local source_role="$1" dep_role="$2"
        case "$source_role" in
            core|shared-kernel)
                [[ "$dep_role" =~ ^(application|infrastructure|api|bootstrap)$ ]] && return 0 ;;
            application)
                [[ "$dep_role" =~ ^(infrastructure|api|bootstrap)$ ]] && return 0 ;;
            infrastructure)
                [[ "$dep_role" =~ ^(application|api|bootstrap)$ ]] && return 0 ;;
            api)
                [[ "$dep_role" =~ ^(infrastructure|bootstrap)$ ]] && return 0 ;;
        esac
        return 1
    }

    # Scan all module build files for dependency violations
    local mod_name mod_build dep_name line_num
    for mod_dir in "$project_dir"/*/; do
        [ ! -d "$mod_dir" ] && continue
        mod_name=$(basename "$mod_dir")
        local source_role
        source_role=$(classify_module_role "$mod_name")
        [ "$source_role" = "unknown" ] || [ "$source_role" = "bootstrap" ] && continue

        mod_build=""
        for candidate in "$mod_dir/build.gradle.kts" "$mod_dir/build.gradle"; do
            [ -f "$candidate" ] && mod_build="$candidate" && break
        done
        [ -z "$mod_build" ] && continue

        local deps
        deps=$(grep -oE 'project\(":([^"]+)"\)' "$mod_build" 2>/dev/null | sed 's/project("://;s/")//' || true)
        [ -z "$deps" ] && deps=$(grep -oE "project\(':([^']+)'\)" "$mod_build" 2>/dev/null | sed "s/project('://;s/')//" || true)

        for dep_name in $deps; do
            local dep_role
            dep_role=$(classify_module_role "$dep_name")
            [ "$dep_role" = "unknown" ] && continue

            if is_forbidden_dep "$source_role" "$dep_role"; then
                line_num=$(grep -n "project.*:${dep_name}" "$mod_build" 2>/dev/null | head -1 | cut -d: -f1 || echo "?")
                report "FAIL" "Architecture" "Module :${mod_name} (${source_role}) must not depend on :${dep_name} (${dep_role}) — hexagonal dependency violation" "$mod_build:${line_num}"
            fi
        done
    done
}
check_module_deps

[ "$VIOLATIONS" -eq 0 ] && report "PASS" "Architecture" "Layer dependency rules compliant"

echo ""

# =============================================
# 2. Code style verification (common — architecture-independent)
# =============================================
echo -e "${CYAN}[2/6] Code style verification${NC}"

# Domain model copy() — LLM 직접 검토 항목 (verify-protocol.md §3-1a #2)

# @Autowired usage check (only Constructor injection allowed) [A2]
_ag_lang=$(ast_grep_lang)
if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ] && [ "$_ag_lang" = "java" ]; then
    while IFS= read -r match; do
        [ -z "$match" ] && continue
        _file="${match%%:*}"
        _line="${match#*:}"
        echo "$_file" | grep -q "/test/\|/testFixtures/" && continue
        report "FAIL" "Style" "@Autowired usage (only Constructor injection allowed)" "$_file:$_line"
    done < <(ast_grep_matches "annotations/autowired" "java" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
else
    while IFS= read -r file; do
        while IFS= read -r match; do
            line_num=$(echo "$match" | cut -d: -f1)
            report "FAIL" "Style" "@Autowired usage (only Constructor injection allowed)" "$file:$line_num"
        done < <(grep -n "@Autowired" "$file" 2>/dev/null || true)
    done < <(find "$TARGET_DIR" -name "*.${FILE_EXT}" -not -path "*/test/*" -not -path "*/testFixtures/*" -type f 2>/dev/null | filter_changed)
fi

# Star import check [M2]
_ag_lang=$(ast_grep_lang)
if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
    while IFS= read -r match; do
        [ -z "$match" ] && continue
        _file="${match%%:*}"
        _line="${match#*:}"
        echo "$_file" | grep -q "/test/\|/.gradle/\|/build/" && continue
        report "FAIL" "Style" "Star import usage prohibited" "$_file:$_line"
    done < <(ast_grep_matches "style/star-import" "$_ag_lang" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
else
    while IFS= read -r file; do
        while IFS= read -r match; do
            line_num=$(echo "$match" | cut -d: -f1)
            report "FAIL" "Style" "Star import usage prohibited" "$file:$line_num"
        done < <(grep -n "^import .*\.\*$\|^import .*\.\*;" "$file" 2>/dev/null | grep -v "//\|/\*" || true)
    done < <(find "$TARGET_DIR" -name "*.${FILE_EXT}" -not -path "*/test/*" -not -path "*/.gradle/*" -not -path "*/build/*" -type f 2>/dev/null | filter_changed)
fi

# Java only: @Data usage check (anti-pattern) [A3]
if [ "$LANGUAGE" = "java" ] || [ "$LANGUAGE" = "mixed" ]; then
    if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
        while IFS= read -r match; do
            [ -z "$match" ] && continue
            _file="${match%%:*}"
            _line="${match#*:}"
            echo "$_file" | grep -q "/test/\|/build/" && continue
            report "FAIL" "Style" "@Data usage prohibited (use individual @Getter/@Setter instead)" "$_file:$_line"
        done < <(ast_grep_matches "annotations/data" "java" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
    else
        while IFS= read -r file; do
            while IFS= read -r match; do
                line_num=$(echo "$match" | cut -d: -f1)
                report "FAIL" "Style" "@Data usage prohibited (use individual @Getter/@Setter instead)" "$file:$line_num"
            done < <(grep -n "^@Data$\|^@Data " "$file" 2>/dev/null | grep -v "//\|/\*" || true)
        done < <(find "$TARGET_DIR" -name "*.java" -not -path "*/test/*" -not -path "*/build/*" -type f 2>/dev/null | filter_changed)
    fi
fi

# Java only: @Setter on Entity check [A4+A5]
if [ "$LANGUAGE" = "java" ] || [ "$LANGUAGE" = "mixed" ]; then
    if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
        # Step 1: find @Entity files via ast-grep
        _entity_files=$(ast_grep_files "annotations/entity" "java" "$TARGET_DIR" 2>/dev/null || true)
        # Step 2: find @Setter in those files
        for _ef in $_entity_files; do
            echo "$_ef" | grep -q "/${LAYER_INFRASTRUCTURE}/" || continue
            while IFS= read -r match; do
                [ -z "$match" ] && continue
                _line="${match#*:}"
                report "FAIL" "Style" "@Setter on JPA Entity prohibited" "$_ef:$_line"
            done < <(ast_grep_matches "annotations/setter" "java" "$_ef" 2>/dev/null || true)
        done
    else
        while IFS= read -r file; do
            if grep -q "@Entity" "$file" 2>/dev/null; then
                while IFS= read -r match; do
                    line_num=$(echo "$match" | cut -d: -f1)
                    report "FAIL" "Style" "@Setter on JPA Entity prohibited" "$file:$line_num"
                done < <(grep -n "@Setter" "$file" 2>/dev/null | grep -v "//\|/\*" || true)
            fi
        done < <(find "$TARGET_DIR" -path "*/${LAYER_INFRASTRUCTURE}/*" -name "*.java" -type f 2>/dev/null | filter_changed)
    fi
fi

echo ""

# =============================================
# 3. Naming verification
# =============================================
echo -e "${CYAN}[3/6] Naming verification${NC}"

# JPA Entity naming check (uses entity-suffix from profile) [A6+A10]
_ag_lang=$(ast_grep_lang)
if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        echo "$file" | grep -q "/${LAYER_INFRASTRUCTURE}/" || continue
        filename=$(basename "$file" ".${FILE_EXT}")
        if ! echo "$filename" | grep -q "${ENTITY_SUFFIX}$"; then
            report "FAIL" "Naming" "@Entity class requires *${ENTITY_SUFFIX} naming" "$file"
        fi
    done < <(ast_grep_files "annotations/entity" "$_ag_lang" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
else
    while IFS= read -r file; do
        filename=$(basename "$file" ".${FILE_EXT}")
        if grep -q "@Entity" "$file" 2>/dev/null; then
            if ! echo "$filename" | grep -q "${ENTITY_SUFFIX}$"; then
                report "FAIL" "Naming" "@Entity class requires *${ENTITY_SUFFIX} naming" "$file"
            fi
        fi
    done < <(find "$TARGET_DIR" -path "*/${LAYER_INFRASTRUCTURE}/*" -name "*.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# Controller naming check (uses controller-suffix from profile) [A7+A11]
if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        echo "$file" | grep -q "/${LAYER_PRESENTATION}/" || continue
        filename=$(basename "$file" ".${FILE_EXT}")
        if ! echo "$filename" | grep -q "${CONTROLLER_SUFFIX}$"; then
            report "FAIL" "Naming" "@RestController requires *${CONTROLLER_SUFFIX} naming" "$file"
        fi
    done < <(ast_grep_files "annotations/rest-controller" "$_ag_lang" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
else
    while IFS= read -r file; do
        filename=$(basename "$file" ".${FILE_EXT}")
        if grep -q "@RestController" "$file" 2>/dev/null; then
            if ! echo "$filename" | grep -q "${CONTROLLER_SUFFIX}$"; then
                report "FAIL" "Naming" "@RestController requires *${CONTROLLER_SUFFIX} naming" "$file"
            fi
        fi
    done < <(find "$TARGET_DIR" -path "*/${LAYER_PRESENTATION}/*" -name "*.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# QueryDSL CustomImpl naming check (only when query-lib includes querydsl)
if [ "$QUERY_LIB" = "querydsl" ] || [ "$QUERY_LIB" = "querydsl+jooq" ]; then
    while IFS= read -r file; do
        filename=$(basename "$file" ".${FILE_EXT}")
        if echo "$filename" | grep -q "Custom$"; then
            impl_file="${file%Custom.${FILE_EXT}}CustomImpl.${FILE_EXT}"
            if [ ! -f "$impl_file" ]; then
                report "FAIL" "Naming" "No matching *CustomImpl for Custom interface" "$file"
            fi
        fi
    done < <(find "$TARGET_DIR" -path "*/${LAYER_INFRASTRUCTURE}/*" -name "*Custom.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# Learned naming pattern cross-validation — verify-protocol.md §3-0b (STANDARD/THOROUGH only)

# JOOQ: generated code manual modification check (when query-lib includes jooq)
if [ "$QUERY_LIB" = "jooq" ] || [ "$QUERY_LIB" = "querydsl+jooq" ]; then
    local_jooq_gen=$(find "$TARGET_DIR" -path "*/generated-sources/jooq/*" -name "*.${FILE_EXT}" -type f 2>/dev/null | head -1 || true)
    if [ -n "$local_jooq_gen" ]; then
        local jooq_gen_dir
        jooq_gen_dir=$(dirname "$local_jooq_gen")
        # Check git tracked modifications
        local jooq_modified
        jooq_modified=$(git -C "$TARGET_DIR" diff --name-only -- "$jooq_gen_dir" 2>/dev/null || true)
        if [ -n "$jooq_modified" ]; then
            report "FAIL" "JOOQ" "Manual modification of JOOQ generated code detected (auto-generated code must not be modified)" "$jooq_gen_dir"
        fi
    fi
fi

echo ""

# =============================================
# 4. Test verification
# =============================================
echo -e "${CYAN}[4/6] Test verification${NC}"

# @Nested inner class usage check (Kotlin only, only when profile test-structure is flat) [A8]
# @Nested is allowed in Java (idiomatic)
if [ "$LANGUAGE" = "kotlin" ] || [ "$LANGUAGE" = "mixed" ]; then
    if [ "$TEST_STRUCTURE" = "flat" ] || [ "$TEST_STRUCTURE" = "flat (no @Nested)" ]; then
        if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
            while IFS= read -r match; do
                [ -z "$match" ] && continue
                _file="${match%%:*}"
                _line="${match#*:}"
                echo "$_file" | grep -q "/test/\|/integrationTest/" || continue
                basename "$_file" | grep -q "Test\.kt$" || continue
                report "FAIL" "Test" "@Nested inner class prohibited (use flat structure)" "$_file:$_line"
            done < <(ast_grep_matches "annotations/nested" "kotlin" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
        else
            while IFS= read -r file; do
                while IFS= read -r match; do
                    line_num=$(echo "$match" | cut -d: -f1)
                    report "FAIL" "Test" "@Nested inner class prohibited (use flat structure)" "$file:$line_num"
                done < <(grep -n "@Nested" "$file" 2>/dev/null || true)
            done < <(find "$TARGET_DIR" \( -path "*/test/*" -o -path "*/integrationTest/*" \) -name "*Test.kt" -type f 2>/dev/null | filter_changed)
        fi
    fi
fi

# Test method name 120-byte check (Kotlin backtick method names)
if [ "$LANGUAGE" = "kotlin" ] || [ "$LANGUAGE" = "mixed" ]; then
    while IFS= read -r file; do
        while IFS= read -r match; do
            line_num=$(echo "$match" | cut -d: -f1)
            method_name=$(echo "$match" | grep -oE '`[^`]+`' | head -1)
            if [ -n "$method_name" ]; then
                byte_len=$(echo -n "$method_name" | wc -c)
                if [ "$byte_len" -gt 120 ]; then
                    report "FAIL" "Test" "Method name ${byte_len} bytes (exceeds 120-byte limit)" "$file:$line_num"
                fi
            fi
        done < <(grep -n "fun \`" "$file" 2>/dev/null || true)
    done < <(find "$TARGET_DIR" \( -path "*/test/*" -o -path "*/integrationTest/*" \) -name "*Test.kt" -type f 2>/dev/null | filter_changed)
fi

echo ""

# =============================================
# 5. JPA pattern verification
# =============================================
echo -e "${CYAN}[5/6] JPA pattern verification${NC}"

# @DynamicUpdate missing check [A9]
_ag_lang=$(ast_grep_lang)
if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
    # Find all @Entity files, then check if @DynamicUpdate is present
    while IFS= read -r entity_file; do
        [ -z "$entity_file" ] && continue
        echo "$entity_file" | grep -q "/${LAYER_INFRASTRUCTURE}/" || continue
        _has_du=$(ast_grep_files "annotations/dynamic-update" "$_ag_lang" "$entity_file" 2>/dev/null || true)
        if [ -z "$_has_du" ]; then
            report "FAIL" "JPA" "@DynamicUpdate missing on @Entity" "$entity_file"
        fi
    done < <(ast_grep_files "annotations/entity" "$_ag_lang" "$TARGET_DIR" 2>/dev/null | filter_changed || true)
else
    while IFS= read -r file; do
        if grep -q "@Entity" "$file" 2>/dev/null; then
            if ! grep -q "@DynamicUpdate" "$file" 2>/dev/null; then
                report "FAIL" "JPA" "@DynamicUpdate missing on @Entity" "$file"
            fi
        fi
    done < <(find "$TARGET_DIR" -path "*/${LAYER_INFRASTRUCTURE}/*" -name "*${ENTITY_SUFFIX}.${FILE_EXT}" -type f 2>/dev/null | filter_changed)
fi

# toModel() missing — LLM 직접 검토 항목 (verify-protocol.md §3-1a #3)

echo ""

# =============================================
# 6. Git convention verification (common — architecture-independent)
# =============================================
echo -e "${CYAN}[6/6] Git convention verification${NC}"

# Current branch naming
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$current_branch" != "unknown" ] && [ "$current_branch" != "main" ] && [ "$current_branch" != "develop" ] && [ "$current_branch" != "sandbox" ]; then
    if ! echo "$current_branch" | grep -qE "^(feature|fix|refactor|chore|migration|test|hotfix|release)/"; then
        report "FAIL" "Git" "Branch naming rule violation: $current_branch (requires feature/*, fix/*, etc.)"
    else
        report "PASS" "Git" "Branch naming rule compliant: $current_branch"
    fi
fi

# Recent commit message format check
last_commit=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")
if [ -n "$last_commit" ]; then
    if echo "$last_commit" | grep -qE "^\[(NONE-ISSUE|HOTFIX|RELEASE|[A-Z]+-[0-9]+)\] (feat|fix|refactor|chore|docs|test):"; then
        report "PASS" "Git" "Commit message format compliant"
    else
        report "FAIL" "Git" "Commit message format violation: $last_commit"
    fi
fi

echo ""

# =============================================
# Results summary
# =============================================
echo "=========================================="
echo "  Verification Results"
echo "=========================================="
echo ""
echo -e "  Total checks: $TOTAL"
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "  ${RED}Violations: $VIOLATIONS${NC}"
echo ""

if [ "$VIOLATIONS" -eq 0 ]; then
    echo -e "${GREEN}All convention checks passed!${NC}"
else
    echo -e "${RED}${VIOLATIONS} convention violation(s) found.${NC}"
fi

# ast-grep accuracy note
if ! has_ast_grep 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}[verify] Note: Running with grep fallback (~75% accuracy). Install ast-grep for ~98% accuracy.${NC}"
fi
# =============================================
# Save verify snapshot
# =============================================
save_verify_snapshot() {
    local project_dir
    project_dir="$(cd "$TARGET_DIR" && pwd)"
    local project_hash
    project_hash=$(project_path_hash "$project_dir")
    local snapshot_file="$HOME/.claude/cache/sub-kopring-engineer-${project_hash}-verify-snapshot.json"

    mkdir -p "$HOME/.claude/cache"

    local new_entry
    new_entry=$(cat << ENTRY_EOF
{
    "timestamp": "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)",
    "target": "$project_dir",
    "language": "$LANGUAGE",
    "architecture": "$ARCH_PATTERN",
    "mode": "$([ "$CHANGED_ONLY" = true ] && echo 'incremental' || echo 'full')",
    "total": $TOTAL,
    "passed": $PASS,
    "violations": $VIOLATIONS,
    "warnings": $WARNINGS
  }
ENTRY_EOF
)

    # Accumulate results: append to existing array, or create new one
    if [ -f "$snapshot_file" ] && command -v jq &>/dev/null; then
        # Append new entry to existing array
        local updated
        updated=$(jq --argjson entry "$new_entry" '. + [$entry]' "$snapshot_file" 2>/dev/null || echo "[$new_entry]")
        echo "$updated" > "$snapshot_file"
    elif [ -f "$snapshot_file" ]; then
        # No jq: simple JSON array concat (best effort)
        local existing
        existing=$(cat "$snapshot_file")
        if echo "$existing" | grep -q '^\['; then
            # Remove trailing ] and append
            echo "${existing%]}, $new_entry]" > "$snapshot_file"
        else
            # Legacy single-object format: wrap in array
            echo "[$existing, $new_entry]" > "$snapshot_file"
        fi
    else
        echo "[$new_entry]" > "$snapshot_file"
    fi

    echo -e "${CYAN}Snapshot saved: $snapshot_file${NC}"
}

save_verify_snapshot
echo ""

[ "$VIOLATIONS" -gt 0 ] && exit 1 || exit 0
