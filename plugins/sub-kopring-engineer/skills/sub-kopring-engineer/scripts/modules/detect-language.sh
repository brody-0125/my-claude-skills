#!/bin/bash
# Module: detect-language.sh
# Detects project language (Kotlin/Java/Mixed) and related settings.
#
# Input globals:  PROJECT_DIR, PLUGINS
# Output globals: LANGUAGE, FILE_EXT, SRC_LANG_DIR, JAVA_VERSION, HAS_LOMBOK, JAVA_STYLE_TOOLS

LANGUAGE="kotlin"
FILE_EXT="kt"
SRC_LANG_DIR="kotlin"
JAVA_VERSION=""
HAS_LOMBOK=false
JAVA_STYLE_TOOLS=""

detect_language() {
  local has_kotlin=false
  local has_java=false

  # Check source directory existence
  [ -d "$PROJECT_DIR/src/main/kotlin" ] && has_kotlin=true
  [ -d "$PROJECT_DIR/src/main/java" ] && has_java=true

  # Multi-module: also search in submodules
  if [ "$has_kotlin" = false ]; then
    find "$PROJECT_DIR" -path "*/src/main/kotlin" -type d 2>/dev/null | head -1 | grep -q . && has_kotlin=true
  fi
  if [ "$has_java" = false ]; then
    find "$PROJECT_DIR" -path "*/src/main/java" -type d 2>/dev/null | head -1 | grep -q . && has_java=true
  fi

  # Check kotlin plugin in build files
  for bf in "$PROJECT_DIR/build.gradle.kts" "$PROJECT_DIR/build.gradle"; do
    if [ -f "$bf" ]; then
      grep -qiE "kotlin|org\.jetbrains\.kotlin" "$bf" 2>/dev/null && has_kotlin=true
    fi
  done
  if [ -f "$PROJECT_DIR/pom.xml" ]; then
    grep -qiE "kotlin" "$PROJECT_DIR/pom.xml" 2>/dev/null && has_kotlin=true
  fi

  # Determine language
  if [ "$has_kotlin" = true ] && [ "$has_java" = true ]; then
    LANGUAGE="mixed"
    FILE_EXT="kt"
    SRC_LANG_DIR="kotlin"
  elif [ "$has_java" = true ] && [ "$has_kotlin" = false ]; then
    LANGUAGE="java"
    FILE_EXT="java"
    SRC_LANG_DIR="java"
  else
    LANGUAGE="kotlin"
    FILE_EXT="kt"
    SRC_LANG_DIR="kotlin"
  fi

  # Java-specific additional detection
  if [ "$LANGUAGE" = "java" ] || [ "$LANGUAGE" = "mixed" ]; then
    # Java version (when JDK_VERSION is not already set)
    if [ -z "$JDK_VERSION" ]; then
      for bf in "$PROJECT_DIR/build.gradle.kts" "$PROJECT_DIR/build.gradle"; do
        [ -f "$bf" ] || continue
        JDK_VERSION=$(grep -oE "sourceCompatibility[[:space:]]*=[[:space:]]*['\"]?[0-9.]+" "$bf" 2>/dev/null | grep -oE '[0-9]+[0-9.]*' | head -1 || true)
        [ -z "$JDK_VERSION" ] && JDK_VERSION=$(grep -oE "JavaVersion\.VERSION_[0-9]+" "$bf" 2>/dev/null | sed 's/JavaVersion\.VERSION_//' | head -1 || true)
        [ -n "$JDK_VERSION" ] && break
      done
    fi
    JAVA_VERSION="$JDK_VERSION"

    # Lombok usage check
    echo "$PLUGINS" | grep -qi "lombok" && HAS_LOMBOK=true

    # Java style tool detection
    local style_parts=""
    echo "$PLUGINS" | grep -qi "checkstyle" && style_parts+="checkstyle, "
    echo "$PLUGINS" | grep -qi "spotless" && style_parts+="spotless, "
    echo "$PLUGINS" | grep -qi "spotbugs" && style_parts+="spotbugs, "
    echo "$PLUGINS" | grep -qi "pmd" && style_parts+="pmd, "
    JAVA_STYLE_TOOLS="${style_parts%, }"
  fi
}
