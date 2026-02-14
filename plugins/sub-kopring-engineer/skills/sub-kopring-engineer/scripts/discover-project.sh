#!/bin/bash
# discover-project.sh - Kotlin/Java Spring Boot project profile auto-discovery script
# Usage: ./discover-project.sh [project-root] [--refresh] [--project <path>]
#
# Detects build settings, code style, and architecture patterns, then outputs a compact summary to stdout.
# Results are cached in ~/.claude/cache/ and only re-scanned when the hash changes.
# Supports monorepo environments with multiple independent Gradle projects.
#
# Modular structure: detection logic is in scripts/modules/*.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
source "$SCRIPT_DIR/modules/detect-monorepo.sh"
source "$SCRIPT_DIR/modules/detect-build-system.sh"
source "$SCRIPT_DIR/modules/detect-language.sh"
source "$SCRIPT_DIR/modules/detect-conventions.sh"
source "$SCRIPT_DIR/modules/detect-architecture.sh"
source "$SCRIPT_DIR/modules/detect-multi-module.sh"
source "$SCRIPT_DIR/modules/generate-output.sh"

# --- Argument parsing ---
PROJECT_DIR="${1:-.}"
REFRESH=false
EXPLICIT_PROJECT=""
IS_MONOREPO=false
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh)
      REFRESH=true
      shift
      ;;
    --project)
      EXPLICIT_PROJECT="$2"
      shift 2
      ;;
    *)
      # First non-flag argument is PROJECT_DIR
      if [[ ! "$1" =~ ^-- ]]; then
        PROJECT_DIR="$1"
      fi
      shift
      ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# =============================================
# Phase 1: Monorepo detection + Cache check
# =============================================
detect_monorepo "$PROJECT_DIR"

# Apply explicit project override
if [ -n "$EXPLICIT_PROJECT" ]; then
  if [ -d "$EXPLICIT_PROJECT" ]; then
    PROJECT_DIR="$(cd "$EXPLICIT_PROJECT" && pwd)"
    PROJECT_NAME="$(basename "$PROJECT_DIR")"
    echo "[discover] Using project: $PROJECT_NAME ($PROJECT_DIR)" >&2
  elif [ -d "$PROJECT_DIR/$EXPLICIT_PROJECT" ]; then
    PROJECT_DIR="$(cd "$PROJECT_DIR/$EXPLICIT_PROJECT" && pwd)"
    PROJECT_NAME="$(basename "$PROJECT_DIR")"
    echo "[discover] Using project: $PROJECT_NAME ($PROJECT_DIR)" >&2
  else
    log_warn "Project not found: $EXPLICIT_PROJECT"
  fi
fi

# Set project name if not already set
if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
fi

CACHE_DIR="$HOME/.claude/cache"
mkdir -p "$CACHE_DIR"

# Clean up stale cache files (older than 30 days)
cleanup_stale_cache 30

PROJECT_HASH="$(project_path_hash "$PROJECT_DIR")"
# Include project name in cache key for monorepo support (v2.2)
if [ "$IS_MONOREPO" = true ]; then
  CACHE_FILE="$CACHE_DIR/sub-kopring-engineer-${PROJECT_HASH}-${PROJECT_NAME}-profile.md"
else
  CACHE_FILE="$CACHE_DIR/sub-kopring-engineer-${PROJECT_HASH}-profile.md"
fi
INPUT_HASH="$(compute_input_hash "$PROJECT_DIR")"

# Cache validity check — early return if valid
if [ "$REFRESH" = false ] && [ -f "$CACHE_FILE" ]; then
  cached_hash=$(head -1 "$CACHE_FILE" 2>/dev/null | sed 's/^<!-- hash: //' | sed 's/ -->//')
  if [ "$cached_hash" = "$INPUT_HASH" ]; then
    # Cache valid — output excluding hash line (only reflect latest allow-list)
    cached_content=$(tail -n +2 "$CACHE_FILE")
    tools_file="$PROJECT_DIR/.sub-kopring-engineer/static-analysis-tools.txt"
    if [ -f "$tools_file" ]; then
      sa_tools=$(grep -v '^#' "$tools_file" 2>/dev/null | grep -v '^$' | tr '\n' ',' | sed 's/,$//; s/,/, /g' || true)
      sa_line="- static-analysis: ${sa_tools:-none}"
    else
      sa_line="- static-analysis: not-configured"
    fi
    # Replace static-analysis line with latest value
    echo "$cached_content" | sed "s/^- static-analysis:.*/$sa_line/"

    # Invoke learn-patterns even on cache hit (source changes may need pattern re-learning)
    LEARN_SCRIPT="$SCRIPT_DIR/learn-patterns.sh"
    [ -f "$LEARN_SCRIPT" ] && bash "$LEARN_SCRIPT" "$PROJECT_DIR" 2>/dev/null || true

    exit 0
  fi
fi

# =============================================
# Phase 2: Detection (Build first, then sequential)
# =============================================
detect_build
detect_language          # depends on PLUGINS
detect_query_lib         # depends on PLUGINS
detect_style             # depends on PROJECT_DIR
detect_architecture      # depends on LANGUAGE, FILE_EXT, SRC_LANG_DIR
detect_multi_module      # depends on MODULES

# =============================================
# Phase 3: Output
# =============================================
PROFILE="$(generate_profile)"

# Save cache
{
  echo "<!-- hash: $INPUT_HASH -->"
  echo "$PROFILE"
} > "$CACHE_FILE"

# Output
echo "$PROFILE"

# Export profile hash for cross-validation by downstream scripts (M4)
export SKE_PROFILE_HASH="$INPUT_HASH"

# =============================================
# Phase 4: Post-processing
# =============================================

# --- ast-grep status check (recommended) ---
if has_ast_grep; then
  AST_RULES_COUNT=0
  if [ -n "$AST_GREP_RULES_DIR" ] && [ -d "$AST_GREP_RULES_DIR" ]; then
    AST_RULES_COUNT=$(find "$AST_GREP_RULES_DIR" -name "*.yml" -o -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$AST_RULES_COUNT" -gt 0 ]; then
    echo "[discover] ast-grep: active ($AST_RULES_COUNT rules)" >&2
  else
    echo "[discover] ast-grep: installed, no rules yet" >&2
  fi
else
  echo "[discover] ast-grep: not found (recommended for ~98% verify accuracy vs ~75% grep-only)" >&2
fi

# --- Static analysis tools: auto-setup on first run, revalidate on subsequent runs ---
SA_TOOLS_FILE="$PROJECT_DIR/.sub-kopring-engineer/static-analysis-tools.txt"
SA_KNOWN_TOOLS="detekt checkstyle spotless spotbugs pmd error-prone archunit"

if [ ! -f "$SA_TOOLS_FILE" ]; then
  # First-run: auto-detect and save (no user prompt)
  detected_tools=""
  for tool in $SA_KNOWN_TOOLS; do
    if echo "$PLUGINS" | grep -qi "$tool"; then
      detected_tools+="$tool"$'\n'
    fi
  done
  if [ -n "$detected_tools" ]; then
    mkdir -p "$PROJECT_DIR/.sub-kopring-engineer"
    {
      echo "# Auto-detected static analysis tools"
      echo "# Edit this file to add/remove tools. One tool per line."
      echo "$detected_tools"
    } > "$SA_TOOLS_FILE"
    # Create .gitignore if needed
    local_gitignore="$PROJECT_DIR/.sub-kopring-engineer/.gitignore"
    if [ ! -f "$local_gitignore" ]; then
      echo "interaction-state.yaml" > "$local_gitignore"
    fi
    echo ""
    echo "[discover] Auto-configured static analysis tools: $(echo "$detected_tools" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  fi
else
  # Revalidation: detect new tools not in allow-list
  new_tools=""
  for tool in $SA_KNOWN_TOOLS; do
    if echo "$PLUGINS" | grep -qi "$tool"; then
      if ! grep -qx "$tool" "$SA_TOOLS_FILE" 2>/dev/null; then
        new_tools+="$tool "
      fi
    fi
  done
  if [ -n "$new_tools" ]; then
    # Auto-add newly detected tools
    for tool in $new_tools; do
      echo "$tool" >> "$SA_TOOLS_FILE"
    done
    echo ""
    echo "[discover] Auto-added new static analysis tool(s): ${new_tools% }"
  fi
fi

# --- Hooks auto-installation (first run only) ---
HOOKS_SCRIPT="$SCRIPT_DIR/setup-hooks.sh"
[ -f "$HOOKS_SCRIPT" ] && bash "$HOOKS_SCRIPT" "$PROJECT_DIR" --auto 2>/dev/null || true

# --- CLAUDE.md skill guidance injection ---
inject_skill_guidance

# --- Pattern learning invocation ---
LEARN_SCRIPT="$SCRIPT_DIR/learn-patterns.sh"
[ -f "$LEARN_SCRIPT" ] && bash "$LEARN_SCRIPT" "$PROJECT_DIR" 2>/dev/null || true
