#!/bin/bash
# capture-task-patterns.sh - Pattern detection/saving script after task completion (user confirmation based)
#
# Mode 1 (detect): ./capture-task-patterns.sh --detect [project-root] [--files "file1 file2 ..."]
#   Outputs pattern candidates from changed files to stdout. No cache modification.
#
# Mode 2 (save): ./capture-task-patterns.sh --save [project-root] [--patterns "pattern1||pattern2||..."]
#   Merges user-approved patterns into cache.

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

MODE=""
PROJECT_DIR="."
FILES=""
PATTERNS=""

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect) MODE="detect"; shift ;;
    --save) MODE="save"; shift ;;
    --files) FILES="$2"; shift 2 ;;
    --patterns) PATTERNS="$2"; shift 2 ;;
    *)
      if [ -d "$1" ]; then
        PROJECT_DIR="$1"
      fi
      shift
      ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [ -z "$MODE" ]; then
  log_error "Usage: capture-task-patterns.sh --detect|--save [project-root] [--files|--patterns ...]"
  exit 1
fi

# --- Cache path computation ---
PROJECT_HASH="$(project_path_hash "$PROJECT_DIR")"
CACHE_DIR="$HOME/.claude/cache"
CACHE_FILE="$CACHE_DIR/sub-kopring-engineer-${PROJECT_HASH}-learned-patterns.md"

# --- Language detection (use shared function) ---
detect_project_language "$PROJECT_DIR"

# ============================================================
# Mode 1: --detect
# ============================================================
if [ "$MODE" = "detect" ]; then

  # Obtain changed file list
  if [ -n "$FILES" ]; then
    CHANGED_FILES="$FILES"
  else
    CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --name-only HEAD~1 2>/dev/null || true)
  fi

  if [ -z "$CHANGED_FILES" ]; then
    echo "(no new patterns detected)"
    exit 0
  fi

  CANDIDATES=""
  CANDIDATE_COUNT=0

  # Absolute path conversion helper
  resolve_file() {
    local f="$1"
    if [[ "$f" = /* ]]; then
      echo "$f"
    else
      echo "$PROJECT_DIR/$f"
    fi
  }

  # --- 1. Naming patterns ---
  NAMING_RESULTS=""
  EXCLUDE_SUFFIXES=$(get_exclude_suffixes)

  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    basename_noext=$(basename_no_ext "$resolved")
    suffix=$(echo "$basename_noext" | grep -oE '[A-Z][a-z]+$' 2>/dev/null || true)
    [ -z "$suffix" ] && continue
    if ! echo "$suffix" | grep -qE "^($EXCLUDE_SUFFIXES)$"; then
      NAMING_RESULTS+="$basename_noext "
      if [ -z "$(echo "$CANDIDATES" | grep "\[naming\].*\*$suffix" || true)" ]; then
        # Collect classes with the same suffix
        local_matches=$(for ff in $CHANGED_FILES; do
          rr=$(resolve_file "$ff")
          [ ! -f "$rr" ] && continue
          bn=$(basename_no_ext "$rr")
          if echo "$bn" | grep -qE "${suffix}$" 2>/dev/null; then echo "$bn"; fi
        done | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
        if [ -n "$local_matches" ]; then
          CANDIDATES+="[naming] *${suffix} — ${local_matches}"$'\n'
          ((CANDIDATE_COUNT++)) || true
        fi
      fi
    fi
  done

  # --- 2. Base class usage [M8] ---
  _ag_lang=$(ast_grep_lang)
  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    local_class=$(basename_no_ext "$resolved")
    base_match=""

    if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
      # ast-grep: detect inheritance via AST structure rules
      local _rule_name
      if [ "$FILE_EXT" = "kt" ]; then
        _rule_name="structure/delegation"
      else
        _rule_name="structure/extends"
      fi
      _has_inheritance=$(ast_grep_files "$_rule_name" "$_ag_lang" "$resolved" 2>/dev/null || true)
      if [ -n "$_has_inheritance" ]; then
        # Extract parent class name (still grep for the name itself)
        if [ "$FILE_EXT" = "kt" ]; then
          base_match=$(grep -oE ':\s*[A-Z][A-Za-z0-9_]+\(' "$resolved" 2>/dev/null | sed 's/^:\s*//' | sed 's/($//' | head -1 || true)
          [ -z "$base_match" ] && base_match=$(grep -oE ':\s*[A-Z][A-Za-z0-9_]+\s*\{' "$resolved" 2>/dev/null | sed 's/^:\s*//' | sed 's/\s*{$//' | head -1 || true)
        else
          base_match=$(grep -oE 'extends\s+[A-Z][A-Za-z0-9_]+' "$resolved" 2>/dev/null | sed 's/^extends\s*//' | head -1 || true)
        fi
      fi
    else
      # Fallback: grep-based detection
      if [ "$FILE_EXT" = "kt" ]; then
        base_match=$(grep -oE ':\s*[A-Z][A-Za-z0-9_]+\(' "$resolved" 2>/dev/null | sed 's/^:\s*//' | sed 's/($//' | head -1 || true)
        [ -z "$base_match" ] && base_match=$(grep -oE ':\s*[A-Z][A-Za-z0-9_]+\s*\{' "$resolved" 2>/dev/null | sed 's/^:\s*//' | sed 's/\s*{$//' | head -1 || true)
      else
        base_match=$(grep -oE 'extends\s+[A-Z][A-Za-z0-9_]+' "$resolved" 2>/dev/null | sed 's/^extends\s*//' | head -1 || true)
      fi
    fi

    if [ -n "$base_match" ] && ! echo "$base_match" | grep -qE "^(Exception|Error|RuntimeException|Enum|Object|Any)$"; then
      CANDIDATES+="[base] ${base_match} → ${local_class}"$'\n'
      ((CANDIDATE_COUNT++)) || true
    fi
  done

  # --- 3. Test fixture usage ---
  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    fixture_imports=$(grep -oE 'import\s+\S+\.[A-Za-z0-9_]*(Fixture|Factory|TestHelper|TestSupport|TestData|Fake)[A-Za-z0-9_]*' "$resolved" 2>/dev/null | \
      grep -oE '[A-Z][A-Za-z0-9_]+$' 2>/dev/null | sort -u || true)
    for fix in $fixture_imports; do
      [ -z "$fix" ] && continue
      local_class=$(basename_no_ext "$resolved")
      if [ -z "$(echo "$CANDIDATES" | grep "\[fixture\] $fix" || true)" ]; then
        CANDIDATES+="[fixture] ${fix} — used in ${local_class}"$'\n'
        ((CANDIDATE_COUNT++)) || true
      fi
    done
  done

  # --- 4. Annotation combinations ---
  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    local_class=$(basename_no_ext "$resolved")
    annotations=$(grep -oE '@[A-Za-z0-9_]+' "$resolved" 2>/dev/null | sort -u | grep -vE '^@(Override|Test|BeforeEach|AfterEach|Nested|DisplayName|Suppress|param|get|field)$' || true)
    ann_count=$(echo "$annotations" | grep -c . || true)
    ann_count="${ann_count:-0}"
    if [ "$ann_count" -ge 2 ]; then
      ann_combo=$(echo "$annotations" | head -3 | tr '\n' ' + ' | sed 's/ + $//' | sed 's/^ + //')
      if [ -n "$ann_combo" ]; then
        CANDIDATES+="[combo] ${ann_combo} — ${local_class}"$'\n'
        ((CANDIDATE_COUNT++)) || true
      fi
    fi
  done

  # --- 5. Error classes ---
  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    local_class=$(basename_no_ext "$resolved")
    if echo "$local_class" | grep -qE "(Exception|Error)$"; then
      CANDIDATES+="[error] ${local_class} (new)"$'\n'
      ((CANDIDATE_COUNT++)) || true
    fi
    # Reuse of existing error imports
    error_imports=$(grep -oE 'import\s+\S+\.[A-Za-z0-9_]*(Exception|Error)' "$resolved" 2>/dev/null | \
      grep -oE '[A-Z][A-Za-z0-9_]+$' 2>/dev/null | sort -u || true)
    for ei in $error_imports; do
      [ -z "$ei" ] && continue
      if [ -z "$(echo "$CANDIDATES" | grep "\[error\] $ei" || true)" ]; then
        CANDIDATES+="[error] ${ei} (reused)"$'\n'
        ((CANDIDATE_COUNT++)) || true
      fi
    done
  done

  # --- 6. Dependency patterns [M9] ---
  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    # Exclude test files
    echo "$resolved" | grep -q "/test/" && continue
    local_class=$(basename_no_ext "$resolved")
    deps=""

    if has_ast_grep && [ -n "$AST_GREP_RULES_DIR" ]; then
      # ast-grep: detect DI parameters via AST
      if [ "$FILE_EXT" = "kt" ]; then
        _di_matches=$(ast_grep_files "structure/di-constructor" "kotlin" "$resolved" 2>/dev/null || true)
        if [ -n "$_di_matches" ]; then
          deps=$(grep -oE 'private val [a-zA-Z0-9_]+:\s*[A-Z][A-Za-z0-9_]+' "$resolved" 2>/dev/null | sed 's/^.*:\s*//' | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g' || true)
        fi
      else
        _di_matches=$(ast_grep_files "structure/di-field" "java" "$resolved" 2>/dev/null || true)
        if [ -n "$_di_matches" ]; then
          deps=$(grep -oE 'private final [A-Z][A-Za-z0-9_]+' "$resolved" 2>/dev/null | sed 's/^private final //' | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g' || true)
        fi
      fi
    else
      # Fallback: grep-based detection
      if [ "$FILE_EXT" = "kt" ]; then
        deps=$(grep -oE 'private val [a-zA-Z0-9_]+:\s*[A-Z][A-Za-z0-9_]+' "$resolved" 2>/dev/null | sed 's/^.*:\s*//' | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g' || true)
      else
        deps=$(grep -oE 'private final [A-Z][A-Za-z0-9_]+' "$resolved" 2>/dev/null | sed 's/^private final //' | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g' || true)
      fi
    fi

    if [ -n "$deps" ]; then
      CANDIDATES+="[dependency] ${local_class} ← ${deps}"$'\n'
      ((CANDIDATE_COUNT++)) || true
    fi
  done

  # --- 7. Method/layer structure ---
  for f in $CHANGED_FILES; do
    resolved=$(resolve_file "$f")
    [ ! -f "$resolved" ] && continue
    echo "$resolved" | grep -q "/test/" && continue
    # Layer identification
    layer=""
    echo "$resolved" | grep -q "/application/" && layer="application"
    echo "$resolved" | grep -q "/presentation/" && layer="presentation"
    echo "$resolved" | grep -q "/app/" && layer="presentation"
    echo "$resolved" | grep -q "/api/" && layer="presentation"
    echo "$resolved" | grep -q "/core/" && layer="core"
    echo "$resolved" | grep -q "/domain/" && layer="core"
    [ -z "$layer" ] && continue

    if [ "$layer" = "application" ]; then
      # execute(Command)->Result pattern detection
      if grep -qE 'fun execute\(' "$resolved" 2>/dev/null; then
        CANDIDATES+="[structure] application: execute(Command)->Result pattern"$'\n'
        ((CANDIDATE_COUNT++)) || true
      fi
    elif [ "$layer" = "core" ]; then
      # Port method naming
      port_methods=$(grep -oE 'fun (readBy|findBy|append|update|delete|save)[A-Za-z0-9_]*' "$resolved" 2>/dev/null | sed 's/^fun //' | head -3 | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g' || true)
      if [ -n "$port_methods" ]; then
        local_class=$(basename_no_ext "$resolved")
        CANDIDATES+="[structure] core: ${local_class} methods — ${port_methods}"$'\n'
        ((CANDIDATE_COUNT++)) || true
      fi
    fi
  done

  # Deduplicate
  CANDIDATES=$(echo "$CANDIDATES" | sort -u)
  CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c . || true)
  CANDIDATE_COUNT="${CANDIDATE_COUNT:-0}"

  if [ "$CANDIDATE_COUNT" -eq 0 ] || [ -z "$(echo "$CANDIDATES" | tr -d '[:space:]')" ]; then
    echo "(no new patterns detected)"
    exit 0
  fi

  echo "## Detected Patterns ($CANDIDATE_COUNT candidates)"
  echo "$CANDIDATES"
  exit 0
fi

# ============================================================
# Mode 2: --save
# ============================================================
if [ "$MODE" = "save" ]; then

  if [ -z "$PATTERNS" ]; then
    log_error "--patterns required for --save mode"
    exit 1
  fi

  mkdir -p "$CACHE_DIR"

  # Extract existing Task-Derived Patterns
  EXISTING_SECTION=""
  if [ -f "$CACHE_FILE" ]; then
    EXISTING_SECTION=$(sed -n '/^### Task-Derived Patterns$/,${/^### Task-Derived Patterns$/d;p}' "$CACHE_FILE" 2>/dev/null || true)
  fi

  # Convert new patterns to (task) format
  NEW_ENTRIES=""
  IFS='||' read -ra PATTERN_ARRAY <<< "$PATTERNS"
  for pat in "${PATTERN_ARRAY[@]}"; do
    pat=$(echo "$pat" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [ -z "$pat" ] && continue

    # Extract and convert category
    category=$(echo "$pat" | grep -oE '^\[[a-z]+' 2>/dev/null | sed 's/^\[//' || true)
    content=$(echo "$pat" | sed 's/^\[[a-z]*\] //')

    case "$category" in
      naming)    NEW_ENTRIES+="- (task) naming: $content"$'\n' ;;
      base)      NEW_ENTRIES+="- (task) base-extended: $content"$'\n' ;;
      fixture)   NEW_ENTRIES+="- (task) fixture: $content"$'\n' ;;
      combo)     NEW_ENTRIES+="- (task) combo: $content"$'\n' ;;
      error)     NEW_ENTRIES+="- (task) error: $content"$'\n' ;;
      dependency) NEW_ENTRIES+="- (task) dependency: $content"$'\n' ;;
      structure) NEW_ENTRIES+="- (task) structure: $content"$'\n' ;;
      *)         NEW_ENTRIES+="- (task) $content"$'\n' ;;
    esac
  done

  if [ -z "$NEW_ENTRIES" ]; then
    echo "No valid patterns to save."
    exit 0
  fi

  # Merge existing + new (deduplicate)
  MERGED=$(printf '%s\n%s' "$EXISTING_SECTION" "$NEW_ENTRIES" | grep -v '^$' | sort -u)

  if [ -f "$CACHE_FILE" ]; then
    # Remove Task-Derived Patterns section from existing cache and re-attach
    BEFORE_SECTION=$(sed '/^### Task-Derived Patterns$/,$d' "$CACHE_FILE" 2>/dev/null || cat "$CACHE_FILE")
    {
      echo "$BEFORE_SECTION"
      echo ""
      echo "### Task-Derived Patterns"
      echo "$MERGED"
    } > "$CACHE_FILE"
  else
    # Cache does not exist: create minimal cache
    {
      echo "## Learned Patterns"
      echo ""
      echo "### Task-Derived Patterns"
      echo "$MERGED"
    } > "$CACHE_FILE"
  fi

  saved_count=$(echo "$NEW_ENTRIES" | grep -c "^- (task)" || true)
  saved_count="${saved_count:-0}"
  echo "Saved $saved_count pattern(s) to cache."
  exit 0
fi
