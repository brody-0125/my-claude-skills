#!/bin/bash
# _common.sh - Shared utility functions for sub-kopring-engineer scripts
# Source this file: source "$(dirname "$0")/_common.sh"

# Compute hash from project build config files (cache key for profile)
compute_input_hash() {
  local project_dir="${1:-.}"
  local hash_input=""
  for f in build.gradle.kts build.gradle settings.gradle.kts settings.gradle pom.xml .editorconfig; do
    local file_path="$project_dir/$f"
    [ -f "$file_path" ] && hash_input+="$(md5sum "$file_path" 2>/dev/null || md5 -q "$file_path" 2>/dev/null || echo "")"
  done
  echo -n "$hash_input" | md5sum 2>/dev/null | cut -d' ' -f1 || echo -n "$hash_input" | md5 -q 2>/dev/null
}

# Compute hash from project path (used as cache file name key)
project_path_hash() {
  local project_dir="${1:-.}"
  echo -n "$project_dir" | md5sum 2>/dev/null | cut -d' ' -f1 || echo -n "$project_dir" | md5 -q 2>/dev/null
}

# Clean up cache files older than N days (default: 30)
cleanup_stale_cache() {
  local cache_dir="$HOME/.claude/cache"
  local max_age_days="${1:-30}"
  [ -d "$cache_dir" ] || return 0
  find "$cache_dir" -name "sub-kopring-engineer-*" -type f -mtime +"$max_age_days" -delete 2>/dev/null || true
}

# =============================================
# ast-grep integration utilities
# =============================================

# ast-grep rules directory (relative to scripts/)
AST_GREP_RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ast-grep-rules" 2>/dev/null && pwd 2>/dev/null || echo "")"

# Check if ast-grep is available
has_ast_grep() {
  command -v ast-grep &>/dev/null || command -v sg &>/dev/null
}

# Run ast-grep (prefers ast-grep, falls back to sg)
run_ast_grep() {
  if command -v ast-grep &>/dev/null; then
    ast-grep "$@"
  elif command -v sg &>/dev/null; then
    sg "$@"
  else
    return 1
  fi
}

# Resolve ast-grep rule file path for the given language
# Usage: ast_grep_rule "annotations/entity" "kotlin" -> .../annotations/entity-kotlin.yml
ast_grep_rule() {
  local rule_base="$1"
  local lang="$2"
  local rule_file="${AST_GREP_RULES_DIR}/${rule_base}-${lang}.yml"
  if [ -f "$rule_file" ]; then
    echo "$rule_file"
  else
    return 1
  fi
}

# Run ast-grep scan with a rule and return matching file paths (one per line)
# Usage: ast_grep_files "annotations/entity" "java" "/path/to/scan"
ast_grep_files() {
  local rule_base="$1"
  local lang="$2"
  local scan_dir="$3"
  local rule_file
  rule_file=$(ast_grep_rule "$rule_base" "$lang") || return 1
  run_ast_grep scan --rule "$rule_file" --json=stream "$scan_dir" 2>/dev/null | \
    _ast_grep_extract_file | sort -u
}

# Run ast-grep scan with a rule and return file:line pairs (one per line)
# Usage: ast_grep_matches "annotations/transactional" "java" "/path/to/scan"
ast_grep_matches() {
  local rule_base="$1"
  local lang="$2"
  local scan_dir="$3"
  local rule_file
  rule_file=$(ast_grep_rule "$rule_base" "$lang") || return 1
  run_ast_grep scan --rule "$rule_file" --json=stream "$scan_dir" 2>/dev/null | \
    _ast_grep_extract_file_line
}

# Internal: extract .file from JSON stream (jq preferred, grep fallback)
_ast_grep_extract_file() {
  if command -v jq &>/dev/null; then
    jq -r '.file // empty'
  else
    grep -oE '"file"\s*:\s*"[^"]+"' | sed 's/"file"\s*:\s*"//' | sed 's/"$//'
  fi
}

# Internal: extract file:line from JSON stream
_ast_grep_extract_file_line() {
  if command -v jq &>/dev/null; then
    jq -r '(.file // "") + ":" + ((.range.start.line // 0) + 1 | tostring)'
  else
    # Fallback: best-effort extraction with grep/awk
    while IFS= read -r json_line; do
      local file line
      file=$(echo "$json_line" | grep -oE '"file"\s*:\s*"[^"]+"' | sed 's/"file"\s*:\s*"//' | sed 's/"$//')
      line=$(echo "$json_line" | grep -oE '"line"\s*:\s*[0-9]+' | head -1 | grep -oE '[0-9]+')
      line=$((${line:-0} + 1))
      [ -n "$file" ] && echo "${file}:${line}"
    done
  fi
}

# Determine ast-grep language suffix from FILE_EXT or LANGUAGE variable
# Returns "java" or "kotlin"
ast_grep_lang() {
  local file_ext="${1:-${FILE_EXT:-kt}}"
  case "$file_ext" in
    java) echo "java" ;;
    *)    echo "kotlin" ;;
  esac
}

# =============================================
# Shared utility functions (extracted from learn-patterns.sh, capture-task-patterns.sh)
# =============================================

# Detect project language based on directory structure
# Sets global FILE_EXT variable ("kt" or "java")
# Usage: detect_project_language "/path/to/project"
detect_project_language() {
  local project_dir="${1:-.}"
  FILE_EXT="kt"
  if [ -d "$project_dir/src/main/java" ] && [ ! -d "$project_dir/src/main/kotlin" ]; then
    FILE_EXT="java"
  fi
  export FILE_EXT
}

# Get standard exclude suffixes for naming pattern detection
# Usage: exclude_pattern=$(get_exclude_suffixes)
get_exclude_suffixes() {
  echo "Service|Repository|Controller|RestController|Entity|JpaEntity|Config|Configuration|Test|Spec|Adapter|Port|Reader|Appender|Updater|Dto|Request|Response|Exception|Error|Application|Factory|Fixture"
}

# Strip file extension from filename
# Usage: class_name=$(strip_file_extension "OrderService.kt")
strip_file_extension() {
  local filename="$1"
  echo "$filename" | sed 's/\.kt$//' | sed 's/\.java$//'
}

# Get basename without extension
# Usage: class_name=$(basename_no_ext "/path/to/OrderService.kt")
basename_no_ext() {
  local filepath="$1"
  strip_file_extension "$(basename "$filepath")"
}

# Log error with prefix (non-fatal)
# Usage: log_error "Something went wrong"
log_error() {
  local msg="$1"
  echo "[ERROR] $msg" >&2
}

# Log warning with prefix
# Usage: log_warn "Check this condition"
log_warn() {
  local msg="$1"
  echo "[WARN] $msg" >&2
}
