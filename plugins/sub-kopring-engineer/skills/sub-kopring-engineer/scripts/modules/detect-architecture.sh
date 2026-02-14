#!/bin/bash
# Module: detect-architecture.sh
# Detects architecture pattern, layer paths, and naming conventions.
# Contains 3 tightly-coupled functions sharing module-scope cached variables.
#
# Input globals:  PROJECT_DIR, LANGUAGE, FILE_EXT, SRC_LANG_DIR
# Output globals: ARCH_PATTERN, ARCH_CONFIDENCE, LAYER_PATHS, DETECTED_CONVENTIONS

ARCH_PATTERN=""
ARCH_CONFIDENCE=""
LAYER_PATHS=""
DETECTED_CONVENTIONS=""

# Module-scope cached variables (shared between sub-functions)
_ARCH_ALL_DIRS=""
_ARCH_ALL_DIRS_FULL=""
_ARCH_ALL_SOURCE_FILES=""
_ARCH_SRC_ROOT=""

detect_architecture() {
  local src_root=""
  # Find src/main/${SRC_LANG_DIR}
  if [ -d "$PROJECT_DIR/src/main/$SRC_LANG_DIR" ]; then
    src_root="$PROJECT_DIR/src/main/$SRC_LANG_DIR"
  else
    # Multi-module: first module's src/main/${SRC_LANG_DIR}
    src_root=$(find "$PROJECT_DIR" -path "*/src/main/$SRC_LANG_DIR" -type d 2>/dev/null | head -1 || true)
  fi

  # For mixed: prefer kotlin, fallback to java
  if [ -z "$src_root" ] || [ ! -d "$src_root" ]; then
    if [ "$LANGUAGE" = "mixed" ]; then
      src_root=$(find "$PROJECT_DIR" -path "*/src/main/java" -type d 2>/dev/null | head -1 || true)
    fi
  fi

  if [ -z "$src_root" ] || [ ! -d "$src_root" ]; then
    ARCH_PATTERN="unknown"
    ARCH_CONFIDENCE="low"
    return
  fi

  # Cache directory and file lists (computed once, reused by sub-functions)
  _ARCH_SRC_ROOT="$src_root"
  _ARCH_ALL_DIRS=$(find "$src_root" -type d 2>/dev/null | sed "s|$src_root/||" | grep -v "^$" || true)
  _ARCH_ALL_DIRS_FULL=$(find "$src_root" -type d 2>/dev/null | grep -v "^${src_root}$" || true)
  _ARCH_ALL_SOURCE_FILES=$(find "$src_root" -name "*.${FILE_EXT}" -type f 2>/dev/null || true)

  # Architecture score calculation (Hexagonal only)
  local hex_score=0

  # Hexagonal indicators
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)core(/|$)" && ((hex_score+=3)) || true
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)domain.model(/|$)" && ((hex_score+=2)) || true
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)infrastructure(/|$)" && ((hex_score+=3)) || true
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)application(/|$)" && ((hex_score+=2)) || true
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)app(/|$)" && ((hex_score+=1)) || true
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)port(s)?(/|$)" && ((hex_score+=2)) || true
  echo "$_ARCH_ALL_DIRS" | grep -qiE "(^|/)adapter(s)?(/|$)" && ((hex_score+=2)) || true

  # Determine confidence
  ARCH_PATTERN="hexagonal"
  if [ "$hex_score" -ge 6 ]; then
    ARCH_CONFIDENCE="high"
  elif [ "$hex_score" -ge 3 ]; then
    ARCH_CONFIDENCE="medium"
  else
    ARCH_CONFIDENCE="low"
  fi

  # Sub-function calls (use module-scope cached variables)
  _detect_layer_paths
  _detect_naming_conventions
}

_detect_layer_paths() {
  local src_root="$_ARCH_SRC_ROOT"
  local all_dirs_full="$_ARCH_ALL_DIRS_FULL"
  local all_source_files="$_ARCH_ALL_SOURCE_FILES"
  local base_pkg=""

  # Extract base package path (deepest common path)
  base_pkg=$(echo "$all_source_files" | head -20 | \
    sed "s|$src_root/||" | sed "s|/[^/]*\.${FILE_EXT}\$||" | sort | head -1 || true)

  # Convert package to dot notation
  local base_pkg_dot
  base_pkg_dot=$(echo "$base_pkg" | tr '/' '.')

  LAYER_PATHS=""

  # Helper: grep cached dir list for a pattern, strip src_root, convert to dot notation
  _dir_lookup() {
    echo "$all_dirs_full" | grep -iE "$1" | head -1 | sed "s|$src_root/||" | tr '/' '.' || true
  }

  # Detect each layer path using cached directory list
  local domain_path
  domain_path=$(_dir_lookup "/domain.*/model(/|$)")
  [ -z "$domain_path" ] && domain_path=$(_dir_lookup "/domain(/|$)")

  local ports_path
  ports_path=$(_dir_lookup "/ports?(/|$)")
  [ -z "$ports_path" ] && ports_path=$(_dir_lookup "/core(/|$)")

  local app_layer_path
  app_layer_path=$(_dir_lookup "/application(/|$)")
  [ -z "$app_layer_path" ] && app_layer_path=$(_dir_lookup "/services?(/|$)")

  local infra_path
  infra_path=$(_dir_lookup "/infrastructure(/|$)")
  [ -z "$infra_path" ] && infra_path=$(_dir_lookup "/repository(/|$)")

  local pres_path
  pres_path=$(echo "$all_dirs_full" | grep -iE "/app(/|$)" | grep -v "application" | head -1 | sed "s|$src_root/||" | tr '/' '.' || true)
  [ -z "$pres_path" ] && pres_path=$(_dir_lookup "/(controllers?|web|api)(/|$)")

  LAYER_PATHS="domain:${domain_path:-n/a}|ports:${ports_path:-n/a}|application:${app_layer_path:-n/a}|infrastructure:${infra_path:-n/a}|presentation:${pres_path:-n/a}"
}

_detect_naming_conventions() {
  local src_root="$_ARCH_SRC_ROOT"
  local all_source_files="$_ARCH_ALL_SOURCE_FILES"

  local entity_suffix="JpaEntity"
  local controller_suffix="RestController"
  local repo_pattern="Reader/Appender/Updater"
  local test_structure="flat"
  local assertion_lib=""

  # Entity suffix detection — use ast-grep or cached source file list
  local entity_files
  local _ag_lang
  _ag_lang=$(ast_grep_lang)
  if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ] && [ -n "$src_root" ]; then
    entity_files=$(ast_grep_files "annotations/entity" "$_ag_lang" "$src_root" 2>/dev/null | head -5 || true)
  elif [ -n "$all_source_files" ]; then
    entity_files=$(echo "$all_source_files" | xargs grep -l "@Entity" 2>/dev/null | head -5 || true)
  fi
  if [ -n "$entity_files" ]; then
    local sample_entity
    sample_entity=$(echo "$entity_files" | head -1 | xargs basename 2>/dev/null | sed "s/\.${FILE_EXT}\$//" || true)
    if echo "$sample_entity" | grep -q "JpaEntity$"; then
      entity_suffix="JpaEntity"
    elif echo "$sample_entity" | grep -q "Entity$"; then
      entity_suffix="Entity"
    fi
  fi

  # Controller suffix detection — use ast-grep or cached source file list
  local ctrl_files
  if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ] && [ -n "$src_root" ]; then
    ctrl_files=$(ast_grep_files "annotations/rest-controller" "$_ag_lang" "$src_root" 2>/dev/null | head -5 || true)
  elif [ -n "$all_source_files" ]; then
    ctrl_files=$(echo "$all_source_files" | xargs grep -l "@RestController" 2>/dev/null | head -5 || true)
  fi
  if [ -n "$ctrl_files" ]; then
    local sample_ctrl
    sample_ctrl=$(echo "$ctrl_files" | head -1 | xargs basename 2>/dev/null | sed "s/\.${FILE_EXT}\$//" || true)
    if echo "$sample_ctrl" | grep -q "RestController$"; then
      controller_suffix="RestController"
    elif echo "$sample_ctrl" | grep -q "Controller$"; then
      controller_suffix="Controller"
    fi
  fi

  # Repository pattern detection — grep cached source file list by filename
  local has_reader=false has_repo=false
  echo "$all_source_files" | grep -q "Reader\.${FILE_EXT}$" && has_reader=true || true
  echo "$all_source_files" | grep -q "Repository\.${FILE_EXT}$" && has_repo=true || true
  if [ "$has_reader" = true ]; then
    repo_pattern="Reader/Appender/Updater"
  elif [ "$has_repo" = true ]; then
    repo_pattern="Repository"
  fi

  # Test structure detection (@Nested usage)
  local test_root="$PROJECT_DIR/src/test/$SRC_LANG_DIR"
  [ ! -d "$test_root" ] && test_root=$(find "$PROJECT_DIR" -path "*/src/test/$SRC_LANG_DIR" -type d 2>/dev/null | head -1 || true)
  # For mixed: also check kotlin tests
  if [ -z "$test_root" ] || [ ! -d "$test_root" ]; then
    if [ "$LANGUAGE" = "mixed" ]; then
      test_root=$(find "$PROJECT_DIR" -path "*/src/test/kotlin" -type d 2>/dev/null | head -1 || true)
      [ -z "$test_root" ] && test_root=$(find "$PROJECT_DIR" -path "*/src/test/java" -type d 2>/dev/null | head -1 || true)
    fi
  fi

  # Cache all test files once for both @Nested and assertion detection
  local all_test_files=""
  if [ -n "$test_root" ] && [ -d "$test_root" ]; then
    all_test_files=$(find "$test_root" -name "*Test.${FILE_EXT}" -type f 2>/dev/null || true)
  fi

  if [ -n "$all_test_files" ]; then
    local nested_count=0
    if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ] && [ -n "$test_root" ]; then
      nested_count=$(ast_grep_files "annotations/nested" "$_ag_lang" "$test_root" 2>/dev/null | wc -l | tr -d ' ' || true)
    else
      nested_count=$(echo "$all_test_files" | xargs grep -l "@Nested" 2>/dev/null | wc -l | tr -d ' ' || true)
    fi
    nested_count="${nested_count:-0}"
    if [ "$nested_count" -gt 0 ]; then
      test_structure="nested (@Nested)"
    fi
  fi

  # Assertion library detection — use cached test file list
  if [ -n "$all_test_files" ]; then
    local sample_tests
    sample_tests=$(echo "$all_test_files" | head -10)
    if [ -n "$sample_tests" ]; then
      echo "$sample_tests" | xargs grep -lq "expectThat\|expectThrows" 2>/dev/null && assertion_lib="strikt (expectThat, expectThrows)"
      [ -z "$assertion_lib" ] && echo "$sample_tests" | xargs grep -lq "shouldBe\|shouldThrow" 2>/dev/null && assertion_lib="kotest (shouldBe, shouldThrow)"
      [ -z "$assertion_lib" ] && echo "$sample_tests" | xargs grep -lq "assertThat" 2>/dev/null && assertion_lib="assertj (assertThat)"
      [ -z "$assertion_lib" ] && assertion_lib="junit (assertEquals)"
    fi
  fi

  DETECTED_CONVENTIONS="entity-suffix:$entity_suffix|controller-suffix:$controller_suffix|repository-pattern:$repo_pattern|test-structure:$test_structure|assertion:${assertion_lib:-unknown}"
}
