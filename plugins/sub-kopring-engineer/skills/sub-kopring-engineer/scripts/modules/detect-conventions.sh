#!/bin/bash
# Module: detect-conventions.sh
# Detects query library and code style configuration.
#
# Input globals:  PLUGINS, PROJECT_DIR
# Output globals: QUERY_LIB, STYLE_INFO

QUERY_LIB="none"
STYLE_INFO=""

detect_query_lib() {
  local has_querydsl=false
  local has_jooq=false

  echo "$PLUGINS" | grep -qi "querydsl" && has_querydsl=true
  echo "$PLUGINS" | grep -qi "jooq" && has_jooq=true

  if [ "$has_querydsl" = true ] && [ "$has_jooq" = true ]; then
    QUERY_LIB="querydsl+jooq"
  elif [ "$has_jooq" = true ]; then
    QUERY_LIB="jooq"
  elif [ "$has_querydsl" = true ]; then
    QUERY_LIB="querydsl"
  else
    QUERY_LIB="none"
  fi
}

detect_style() {
  local parts=""

  # .editorconfig
  if [ -f "$PROJECT_DIR/.editorconfig" ]; then
    local indent=""
    local max_line=""
    indent=$(grep -oE 'indent_size[[:space:]]*=[[:space:]]*[0-9]+' "$PROJECT_DIR/.editorconfig" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    max_line=$(grep -oE 'max_line_length[[:space:]]*=[[:space:]]*[0-9]+' "$PROJECT_DIR/.editorconfig" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    local ec_info="editorconfig"
    [ -n "$indent" ] && ec_info+=" (indent=$indent"
    [ -n "$max_line" ] && ec_info+=", max_line=$max_line)"
    [ -z "$max_line" ] && [ -n "$indent" ] && ec_info+=")"
    parts+="$ec_info, "
  fi

  # detekt
  if [ -f "$PROJECT_DIR/detekt.yml" ] || [ -f "$PROJECT_DIR/config/detekt/detekt.yml" ]; then
    parts+="detekt, "
  fi

  # ktlint
  local ktlint_detected=false
  if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    grep -qiE "ktlint" "$PROJECT_DIR/build.gradle.kts" 2>/dev/null && ktlint_detected=true
  fi
  if [ -f "$PROJECT_DIR/.editorconfig" ]; then
    grep -qiE "ktlint" "$PROJECT_DIR/.editorconfig" 2>/dev/null && ktlint_detected=true
  fi

  if [ "$ktlint_detected" = true ]; then
    # Count disabled ktlint rules
    local disabled_count=0
    if [ -f "$PROJECT_DIR/.editorconfig" ]; then
      disabled_count=$(grep -cE 'ktlint_.*=\s*disabled' "$PROJECT_DIR/.editorconfig" 2>/dev/null || true)
      disabled_count="${disabled_count:-0}"
    fi
    if [ "$disabled_count" -gt 0 ]; then
      parts+="ktlint ($disabled_count rules disabled), "
    else
      parts+="ktlint, "
    fi
  fi

  # checkstyle (Java)
  if [ -f "$PROJECT_DIR/config/checkstyle/checkstyle.xml" ] || [ -f "$PROJECT_DIR/checkstyle.xml" ]; then
    local cs_style=""
    local cs_file="$PROJECT_DIR/config/checkstyle/checkstyle.xml"
    [ ! -f "$cs_file" ] && cs_file="$PROJECT_DIR/checkstyle.xml"
    if [ -f "$cs_file" ]; then
      grep -qi "google" "$cs_file" 2>/dev/null && cs_style="google"
      grep -qi "sun" "$cs_file" 2>/dev/null && cs_style="sun"
    fi
    if [ -n "$cs_style" ]; then
      parts+="checkstyle ($cs_style), "
    else
      parts+="checkstyle, "
    fi
  fi

  STYLE_INFO="${parts%, }"
}
