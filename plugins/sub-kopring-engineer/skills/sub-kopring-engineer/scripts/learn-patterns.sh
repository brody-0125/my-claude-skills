#!/bin/bash
# learn-patterns.sh - Project code pattern auto-learning script
# Usage: ./learn-patterns.sh [project-root] [--refresh]
#
# Learns frequently used patterns from the codebase and saves them to a cache file.
# Uses the same hash-based cache strategy as discover-project.sh.

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
REFRESH=false

for arg in "$@"; do
  [ "$arg" = "--refresh" ] && REFRESH=true
done

CACHE_DIR="$HOME/.claude/cache"
mkdir -p "$CACHE_DIR"

# --- Cache key computation (extends _common.sh with source file count) ---
compute_patterns_hash() {
  local base_hash
  base_hash="$(compute_input_hash "$PROJECT_DIR")"
  local src_count
  src_count=$(find "$PROJECT_DIR" -path "*/src/main/*" \( -name "*.kt" -o -name "*.java" \) -type f 2>/dev/null | wc -l | tr -d ' ' || true)
  src_count="${src_count:-0}"
  echo -n "${base_hash}src_count:$src_count" | md5sum 2>/dev/null | cut -d' ' -f1 || echo -n "${base_hash}src_count:$src_count" | md5 -q 2>/dev/null
}

PROJECT_HASH="$(project_path_hash "$PROJECT_DIR")"
CACHE_FILE="$CACHE_DIR/sub-kopring-engineer-${PROJECT_HASH}-learned-patterns.md"
INPUT_HASH="$(compute_patterns_hash)"

# Profile hash cross-validation (M4: artifact consistency)
CURRENT_PROFILE_HASH="${SKE_PROFILE_HASH:-}"
if [ -z "$CURRENT_PROFILE_HASH" ]; then
  # Fallback: compute from project if not exported by discover-project.sh
  CURRENT_PROFILE_HASH="$(compute_input_hash "$PROJECT_DIR" 2>/dev/null || true)"
fi

# Cache validity check (pattern hash + profile hash)
if [ "$REFRESH" = false ] && [ -f "$CACHE_FILE" ]; then
  cached_hash=$(head -1 "$CACHE_FILE" 2>/dev/null | sed 's/^<!-- hash: //' | sed 's/ -->//')
  cached_profile_hash=$(sed -n '2p' "$CACHE_FILE" 2>/dev/null | sed 's/^<!-- profile-hash: //' | sed 's/ -->//')
  if [ "$cached_hash" = "$INPUT_HASH" ]; then
    # Check profile hash consistency
    if [ -n "$cached_profile_hash" ] && [ -n "$CURRENT_PROFILE_HASH" ] && [ "$cached_profile_hash" != "$CURRENT_PROFILE_HASH" ]; then
      echo "[learn-patterns] Profile changed since last pattern learning — re-learning..." >&2
    else
      exit 0
    fi
  fi
fi

# --- Language detection (use shared function) ---
detect_project_language "$PROJECT_DIR"

# Source root discovery
SRC_ROOT=""
if [ -d "$PROJECT_DIR/src/main/kotlin" ]; then
  SRC_ROOT="$PROJECT_DIR/src/main/kotlin"
elif [ -d "$PROJECT_DIR/src/main/java" ]; then
  SRC_ROOT="$PROJECT_DIR/src/main/java"
else
  SRC_ROOT=$(find "$PROJECT_DIR" -path "*/src/main/kotlin" -type d 2>/dev/null | head -1 || true)
  [ -z "$SRC_ROOT" ] && SRC_ROOT=$(find "$PROJECT_DIR" -path "*/src/main/java" -type d 2>/dev/null | head -1 || true)
fi

if [ -z "$SRC_ROOT" ] || [ ! -d "$SRC_ROOT" ]; then
  # No source root found — save empty cache
  {
    echo "<!-- hash: $INPUT_HASH -->"
    echo "<!-- profile-hash: $CURRENT_PROFILE_HASH -->"
    echo "## Learned Patterns"
    echo "(no source root found)"
  } > "$CACHE_FILE"
  exit 0
fi

TEST_ROOT=""
if [ -d "$PROJECT_DIR/src/test/kotlin" ]; then
  TEST_ROOT="$PROJECT_DIR/src/test/kotlin"
elif [ -d "$PROJECT_DIR/src/test/java" ]; then
  TEST_ROOT="$PROJECT_DIR/src/test/java"
else
  TEST_ROOT=$(find "$PROJECT_DIR" -path "*/src/test/kotlin" -type d 2>/dev/null | head -1 || true)
  [ -z "$TEST_ROOT" ] && TEST_ROOT=$(find "$PROJECT_DIR" -path "*/src/test/java" -type d 2>/dev/null | head -1 || true)
fi

# --- Cached file lists (computed once, reused everywhere) ---
ALL_KT_FILES=$(find "$SRC_ROOT" -name "*.kt" -type f 2>/dev/null | sort | head -500 || true)
ALL_JAVA_FILES=$(find "$SRC_ROOT" -name "*.java" -type f 2>/dev/null | sort | head -500 || true)
if [ "$FILE_EXT" = "kt" ]; then
  ALL_SRC_FILES="$ALL_KT_FILES"
else
  ALL_SRC_FILES="$ALL_JAVA_FILES"
fi

ALL_TEST_FILES=""
if [ -n "$TEST_ROOT" ] && [ -d "$TEST_ROOT" ]; then
  ALL_TEST_FILES=$(find "$TEST_ROOT" -name "*.${FILE_EXT}" -type f 2>/dev/null | sort | head -500 || true)
fi

OUTPUT=""

append() {
  OUTPUT+="$1"$'\n'
}

append "## Learned Patterns"
append ""

# --- 1. Base Classes ---
learn_base_classes() {
  local results=""
  local _ag_lang
  _ag_lang=$(ast_grep_lang)

  if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ] && [ -n "$SRC_ROOT" ]; then
    # ast-grep: find abstract/open classes via AST [C1+C3]
    local base_classes
    base_classes=$(ast_grep_files "structure/abstract-class" "$_ag_lang" "$SRC_ROOT" 2>/dev/null | head -20 || true)

    for bc_file in $base_classes; do
      [ -z "$bc_file" ] || [ ! -f "$bc_file" ] && continue
      local class_name
      if [ "$FILE_EXT" = "kt" ]; then
        class_name=$(grep -oE '(abstract|open) class [A-Za-z0-9_]+' "$bc_file" 2>/dev/null | sed 's/.* class //' | head -1 || true)
      else
        class_name=$(grep -oE 'abstract class [A-Za-z0-9_]+' "$bc_file" 2>/dev/null | sed 's/abstract class //' | head -1 || true)
      fi
      [ -z "$class_name" ] && continue

      # ast-grep: count subclasses via delegation/extends rules [C2+C4]
      local sub_count=0
      if [ "$FILE_EXT" = "kt" ]; then
        sub_count=$(ast_grep_files "structure/delegation" "kotlin" "$SRC_ROOT" 2>/dev/null | \
          xargs grep -l ": $class_name\b\|: $class_name(" 2>/dev/null | wc -l | tr -d ' ' || true)
      else
        sub_count=$(ast_grep_files "structure/extends" "java" "$SRC_ROOT" 2>/dev/null | \
          xargs grep -l "extends $class_name\b" 2>/dev/null | wc -l | tr -d ' ' || true)
      fi
      sub_count="${sub_count:-0}"

      if [ "$sub_count" -ge 3 ]; then
        local pkg
        pkg=$(dirname "$bc_file" | sed "s|$SRC_ROOT/||" | tr '/' '.')
        results+="- base-class: $class_name ($sub_count subclasses) — $pkg"$'\n'
      fi
    done
  else
    # Fallback: grep-based detection
    if [ "$FILE_EXT" = "kt" ]; then
      local base_classes
      base_classes=$(echo "$ALL_KT_FILES" | xargs grep -l "^abstract class\|^open class" 2>/dev/null | head -20 || true)

      for bc_file in $base_classes; do
        local class_name
        class_name=$(grep -oE '(abstract|open) class [A-Za-z0-9_]+' "$bc_file" 2>/dev/null | sed 's/.* class //' | head -1 || true)
        [ -z "$class_name" ] && continue

        local sub_count
        sub_count=$(echo "$ALL_KT_FILES" | xargs grep -l ": $class_name\b\|: $class_name(" 2>/dev/null | wc -l | tr -d ' ' || true)
        sub_count="${sub_count:-0}"

        if [ "$sub_count" -ge 3 ]; then
          local pkg
          pkg=$(dirname "$bc_file" | sed "s|$SRC_ROOT/||" | tr '/' '.')
          results+="- base-class: $class_name ($sub_count subclasses) — $pkg"$'\n'
        fi
      done
    else
      local base_classes
      base_classes=$(echo "$ALL_JAVA_FILES" | xargs grep -l "^public abstract class\|^abstract class" 2>/dev/null | head -20 || true)

      for bc_file in $base_classes; do
        local class_name
        class_name=$(grep -oE 'abstract class [A-Za-z0-9_]+' "$bc_file" 2>/dev/null | sed 's/abstract class //' | head -1 || true)
        [ -z "$class_name" ] && continue

        local sub_count
        sub_count=$(echo "$ALL_JAVA_FILES" | xargs grep -l "extends $class_name\b" 2>/dev/null | wc -l | tr -d ' ' || true)
        sub_count="${sub_count:-0}"

        if [ "$sub_count" -ge 3 ]; then
          local pkg
          pkg=$(dirname "$bc_file" | sed "s|$SRC_ROOT/||" | tr '/' '.')
          results+="- base-class: $class_name ($sub_count subclasses) — $pkg"$'\n'
        fi
      done
    fi
  fi

  if [ -n "$results" ]; then
    append "### Base Classes"
    append "$results"
  fi
}

# --- 2. Custom Annotations ---
learn_custom_annotations() {
  local results=""
  local _ag_lang
  _ag_lang=$(ast_grep_lang)

  if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ] && [ -n "$SRC_ROOT" ]; then
    # ast-grep: find annotation classes/types via AST [M4+M5]
    local ann_files
    if [ "$FILE_EXT" = "kt" ]; then
      ann_files=$(ast_grep_files "structure/annotation-class" "kotlin" "$SRC_ROOT" 2>/dev/null | head -10 || true)
    else
      ann_files=$(ast_grep_files "structure/annotation-type" "java" "$SRC_ROOT" 2>/dev/null | head -10 || true)
    fi

    for af in $ann_files; do
      [ -z "$af" ] || [ ! -f "$af" ] && continue
      local ann_name
      if [ "$FILE_EXT" = "kt" ]; then
        ann_name=$(grep -oE 'annotation class [A-Za-z0-9_]+' "$af" 2>/dev/null | sed 's/annotation class //' | head -1 || true)
      else
        ann_name=$(grep -oE '@interface [A-Za-z0-9_]+' "$af" 2>/dev/null | sed 's/@interface //' | head -1 || true)
      fi
      [ -z "$ann_name" ] && continue
      local fname
      fname=$(basename "$af")
      results+="- custom-annotation: @$ann_name ($fname)"$'\n'
    done
  else
    # Fallback: grep-based detection
    if [ "$FILE_EXT" = "kt" ]; then
      local ann_files
      ann_files=$(echo "$ALL_KT_FILES" | xargs grep -l "^annotation class\|^@Target" 2>/dev/null | head -10 || true)

      for af in $ann_files; do
        local ann_name
        ann_name=$(grep -oE 'annotation class [A-Za-z0-9_]+' "$af" 2>/dev/null | sed 's/annotation class //' | head -1 || true)
        [ -z "$ann_name" ] && continue
        local fname
        fname=$(basename "$af")
        results+="- custom-annotation: @$ann_name ($fname)"$'\n'
      done
    else
      local ann_files
      ann_files=$(echo "$ALL_JAVA_FILES" | xargs grep -l "^public @interface\|^@interface\|@Target\|@Retention" 2>/dev/null | head -10 || true)

      for af in $ann_files; do
        local ann_name
        ann_name=$(grep -oE '@interface [A-Za-z0-9_]+' "$af" 2>/dev/null | sed 's/@interface //' | head -1 || true)
        [ -z "$ann_name" ] && continue
        local fname
        fname=$(basename "$af")
        results+="- custom-annotation: @$ann_name ($fname)"$'\n'
      done
    fi
  fi

  if [ -n "$results" ]; then
    append "### Custom Annotations"
    append "$results"
  fi
}

# --- 3. Naming Patterns ---
learn_naming_patterns() {
  local results=""

  # Standard suffix exclusion list
  local exclude_pattern="Service|Repository|Controller|RestController|Entity|JpaEntity|Config|Configuration|Test|Spec|Adapter|Port|Reader|Appender|Updater|Dto|Request|Response|Exception|Error|Application|Factory|Fixture"

  local suffix_counts
  suffix_counts=$(echo "$ALL_SRC_FILES" | \
    xargs -I{} basename {} ".${FILE_EXT}" 2>/dev/null | \
    grep -oE '[A-Z][a-z]+$' 2>/dev/null | \
    grep -vE "^($exclude_pattern)$" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10 || true)

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local count suffix
    count=$(echo "$line" | awk '{print $1}')
    suffix=$(echo "$line" | awk '{print $2}')
    if [ "$count" -ge 3 ]; then
      results+="- naming-pattern: *$suffix ($count files)"$'\n'
    fi
  done <<< "$suffix_counts"

  if [ -n "$results" ]; then
    append "### Naming Patterns"
    append "$results"
  fi
}

# --- 4. Test Fixtures ---
learn_test_fixtures() {
  local results=""

  if [ -n "$TEST_ROOT" ] && [ -d "$TEST_ROOT" ]; then
    local fixture_files
    fixture_files=$(echo "$ALL_TEST_FILES" | \
      xargs -I{} basename {} ".${FILE_EXT}" 2>/dev/null | \
      grep -iE "Factory|Fixture|TestHelper|TestSupport|TestData|Fake" 2>/dev/null | \
      sort -u || true)

    for ff in $fixture_files; do
      [ -z "$ff" ] && continue
      results+="- test-fixture: $ff"$'\n'
    done
  fi

  # Also check testFixtures source set
  local test_fixtures_root=""
  test_fixtures_root=$(find "$PROJECT_DIR" -path "*/src/testFixtures/*" -name "*.${FILE_EXT}" -type f 2>/dev/null | head -1 || true)
  if [ -n "$test_fixtures_root" ]; then
    local tf_dir
    tf_dir=$(dirname "$test_fixtures_root")
    local tf_files
    tf_files=$(find "$tf_dir" -name "*.${FILE_EXT}" -type f 2>/dev/null | head -20 | \
      xargs -I{} basename {} ".${FILE_EXT}" 2>/dev/null | sort -u || true)
    for tf in $tf_files; do
      [ -z "$tf" ] && continue
      results+="- test-fixture (testFixtures): $tf"$'\n'
    done
  fi

  if [ -n "$results" ]; then
    append "### Test Fixtures"
    append "$results"
  fi
}

# --- 5. Error Hierarchy ---
learn_error_hierarchy() {
  local results=""

  local exception_files
  exception_files=$(echo "$ALL_SRC_FILES" | grep -E "(Exception|Error)\.${FILE_EXT}$" 2>/dev/null | head -30 || true)

  for ef in $exception_files; do
    [ -z "$ef" ] && continue
    local class_name
    class_name=$(basename "$ef" ".${FILE_EXT}")
    local pkg
    pkg=$(dirname "$ef" | sed "s|$SRC_ROOT/||" | tr '/' '.')
    results+="- error: $class_name — $pkg"$'\n'
  done

  if [ -n "$results" ]; then
    append "### Error Hierarchy"
    append "$results"
  fi
}

# --- Main execution ---
learn_base_classes || true
learn_custom_annotations || true
learn_naming_patterns || true
learn_test_fixtures || true
learn_error_hierarchy || true

# Preserve Task-Derived Patterns from existing cache
TASK_DERIVED_SECTION=""
if [ -f "$CACHE_FILE" ]; then
  TASK_DERIVED_SECTION=$(sed -n '/^### Task-Derived Patterns$/,$p' "$CACHE_FILE" 2>/dev/null || true)
fi

# Save cache
{
  echo "<!-- hash: $INPUT_HASH -->"
  echo "<!-- profile-hash: $CURRENT_PROFILE_HASH -->"
  echo "$OUTPUT"
  if [ -n "$TASK_DERIVED_SECTION" ]; then
    echo ""
    echo "$TASK_DERIVED_SECTION"
  fi
} > "$CACHE_FILE"
