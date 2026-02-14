#!/bin/bash
# generate-ast-rules.sh — v3.0 Pattern Rule Generation
#
# 프로젝트 패턴 학습 결과를 기반으로 AST-grep 규칙을 자동 생성한다.
# 생성된 규칙은 사용자 승인 후 활성화된다.
#
# Usage:
#   ./generate-ast-rules.sh [project-dir] [--preview] [--apply]
#
# Options:
#   --preview   생성될 규칙 미리보기 (파일 생성 안 함)
#   --apply     사용자 승인 없이 바로 적용 (CI 환경용)

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
RULES_DIR="$SKILL_DIR/ast-grep-rules"
CUSTOM_DIR="$RULES_DIR/custom"

# --- Argument parsing ---
PROJECT_DIR="${1:-.}"
PREVIEW_ONLY=false
AUTO_APPLY=false

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW_ONLY=true
      shift
      ;;
    --apply)
      AUTO_APPLY=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# --- Pattern cache location ---
CACHE_DIR="${HOME}/.claude/cache"
PATTERN_CACHE="$CACHE_DIR/sub-kopring-engineer-patterns.md"

# --- Check prerequisites ---
if [ ! -f "$PATTERN_CACHE" ]; then
  log_error "Pattern cache not found. Run learn-patterns.sh first."
  exit 1
fi

# --- Create custom rules directory ---
if [ "$PREVIEW_ONLY" = false ]; then
  mkdir -p "$CUSTOM_DIR"
fi

# --- Parse pattern cache ---
echo "[generate-ast-rules] Reading pattern cache: $PATTERN_CACHE" >&2

# Extract custom annotations
extract_custom_annotations() {
  awk '/^## Custom Annotations/,/^## [A-Z]/' "$PATTERN_CACHE" | \
    grep -E '^\s*-\s*@' | \
    sed 's/.*@\([A-Za-z0-9_]*\).*/\1/' | \
    sort -u
}

# Extract naming patterns (non-standard suffixes)
extract_naming_patterns() {
  awk '/^## Naming Patterns/,/^## [A-Z]/' "$PATTERN_CACHE" | \
    grep -E '^\s*-\s*\*' | \
    sed 's/.*\*\([A-Za-z0-9_]*\).*/\1/' | \
    sort -u
}

# Extract base classes
extract_base_classes() {
  awk '/^## Base Classes/,/^## [A-Z]/' "$PATTERN_CACHE" | \
    grep -E '^\s*-\s*' | \
    sed 's/.*- \([A-Za-z0-9_]*\).*/\1/' | \
    sort -u
}

# --- Generic rule generator (refactored from 3 similar functions) ---
# Usage: generate_rule <type> <name> <pattern> <message> <severity> <note>
generate_rule() {
  local rule_type="$1"
  local name="$2"
  local pattern="$3"
  local message="$4"
  local severity="$5"
  local note="$6"
  local constraints="${7:-}"

  local rule_id="${rule_type}-${name,,}"
  local rule_file="$CUSTOM_DIR/${rule_id}.yml"

  local rule_content
  if [ -n "$constraints" ]; then
    rule_content="id: ${rule_id}
message: \"${message}\"
severity: ${severity}
language: kotlin
rule:
  pattern: \"${pattern}\"
constraints:
${constraints}
note: |
  ${note}"
  else
    rule_content="id: ${rule_id}
message: \"${message}\"
severity: ${severity}
language: kotlin
rule:
  pattern: \"${pattern}\"
note: |
  ${note}"
  fi

  if [ "$PREVIEW_ONLY" = true ]; then
    echo "--- Would create: $rule_file ---"
    echo "$rule_content"
    echo ""
    return
  fi

  echo "$rule_content" > "$rule_file"
  echo "[generate-ast-rules] Created: $rule_file" >&2
}

# --- Wrapper functions for backward compatibility ---
generate_annotation_rule() {
  local annotation="$1"
  generate_rule "custom-annotation" "$annotation" \
    "@${annotation}" \
    "Custom annotation @${annotation} detected - verify usage location" \
    "info" \
    "Project-specific annotation @${annotation}. Ensure it's used in appropriate locations per project conventions."
}

generate_naming_rule() {
  local suffix="$1"
  generate_rule "naming-pattern" "$suffix" \
    "class \$NAME${suffix}" \
    "Class with *${suffix} suffix should follow project naming conventions" \
    "warning" \
    "Project uses *${suffix} naming pattern. Ensure new classes with this suffix follow existing conventions." \
    "  NAME:
    regex: \"[A-Z][a-zA-Z0-9]*\""
}

generate_inheritance_rule() {
  local base_class="$1"
  generate_rule "inheritance" "$base_class" \
    "class \$NAME : ${base_class}" \
    "Class extends ${base_class} - verify inheritance hierarchy" \
    "info" \
    "Project has base class ${base_class}. Subclasses should follow established patterns."
}

# --- Main execution ---
echo "" >&2
echo "=== AST-grep Rule Generation (v3.0) ===" >&2
echo "" >&2

# Generate annotation rules
ANNOTATIONS=$(extract_custom_annotations)
ANNOTATION_COUNT=0
if [ -n "$ANNOTATIONS" ]; then
  echo "[generate-ast-rules] Found custom annotations:" >&2
  while IFS= read -r annotation; do
    if [ -n "$annotation" ]; then
      echo "  - @$annotation" >&2
      generate_annotation_rule "$annotation"
      ANNOTATION_COUNT=$((ANNOTATION_COUNT + 1))
    fi
  done <<< "$ANNOTATIONS"
fi

# Generate naming rules
PATTERNS=$(extract_naming_patterns)
PATTERN_COUNT=0
if [ -n "$PATTERNS" ]; then
  echo "[generate-ast-rules] Found naming patterns:" >&2
  while IFS= read -r pattern; do
    if [ -n "$pattern" ]; then
      echo "  - *$pattern" >&2
      generate_naming_rule "$pattern"
      PATTERN_COUNT=$((PATTERN_COUNT + 1))
    fi
  done <<< "$PATTERNS"
fi

# Generate inheritance rules
CLASSES=$(extract_base_classes)
CLASS_COUNT=0
if [ -n "$CLASSES" ]; then
  echo "[generate-ast-rules] Found base classes:" >&2
  while IFS= read -r class; do
    if [ -n "$class" ]; then
      echo "  - $class" >&2
      generate_inheritance_rule "$class"
      CLASS_COUNT=$((CLASS_COUNT + 1))
    fi
  done <<< "$CLASSES"
fi

# --- Summary ---
TOTAL=$((ANNOTATION_COUNT + PATTERN_COUNT + CLASS_COUNT))

echo "" >&2
echo "=== Summary ===" >&2
echo "  Annotation rules: $ANNOTATION_COUNT" >&2
echo "  Naming rules:     $PATTERN_COUNT" >&2
echo "  Inheritance rules: $CLASS_COUNT" >&2
echo "  Total:            $TOTAL" >&2
echo "" >&2

if [ "$PREVIEW_ONLY" = true ]; then
  echo "[generate-ast-rules] Preview mode - no files created" >&2
  exit 0
fi

if [ "$TOTAL" -eq 0 ]; then
  echo "[generate-ast-rules] No patterns found. No rules generated." >&2
  exit 0
fi

# --- User confirmation (unless --apply) ---
if [ "$AUTO_APPLY" = false ]; then
  echo "[generate-ast-rules] Rules created in: $CUSTOM_DIR" >&2
  echo "" >&2
  echo "To activate these rules, add to sgconfig.yml:" >&2
  echo "  ruleDirs:" >&2
  echo "    - custom" >&2
  echo "" >&2
  echo "Run with --apply to auto-activate (CI mode)" >&2
else
  # Auto-update sgconfig.yml
  SGCONFIG="$RULES_DIR/sgconfig.yml"
  if [ -f "$SGCONFIG" ]; then
    if ! grep -q "custom" "$SGCONFIG"; then
      echo "    - custom" >> "$SGCONFIG"
      echo "[generate-ast-rules] Added 'custom' to sgconfig.yml ruleDirs" >&2
    fi
  fi
fi

echo "[generate-ast-rules] Done." >&2
