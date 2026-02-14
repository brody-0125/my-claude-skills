#!/bin/bash
# Module: generate-output.sh
# Generates the project profile output and injects skill guidance into CLAUDE.md.
#
# Input globals:  All detection results (BUILD_TOOL, LANGUAGE, KOTLIN_VERSION, etc.)
# Output:         Profile text to stdout

generate_profile() {
  echo "## Project Profile"
  # Monorepo info (v2.2)
  if [ "$IS_MONOREPO" = true ]; then
    echo "- **monorepo**: true"
    echo "- **project-name**: $PROJECT_NAME"
    echo "- **project-path**: $PROJECT_DIR"
  fi
  echo "- build: $BUILD_TOOL"
  echo "- language: $LANGUAGE"
  if [ "$LANGUAGE" = "kotlin" ] || [ "$LANGUAGE" = "mixed" ]; then
    [ -n "$KOTLIN_VERSION" ] && printf '%s' "- kotlin: $KOTLIN_VERSION"
    [ -n "$JDK_VERSION" ] && printf '%s' " | jdk: $JDK_VERSION"
    [ -n "$KOTLIN_VERSION" ] || [ -n "$JDK_VERSION" ] && echo ""
  fi
  if [ "$LANGUAGE" = "java" ] || [ "$LANGUAGE" = "mixed" ]; then
    [ -n "$JAVA_VERSION" ] && echo "- java: $JAVA_VERSION"
    [ "$LANGUAGE" = "java" ] && [ -n "$JDK_VERSION" ] && [ -z "$JAVA_VERSION" ] && echo "- jdk: $JDK_VERSION"
    echo "- lombok: $HAS_LOMBOK"
    [ -n "$JAVA_STYLE_TOOLS" ] && echo "- java-style: $JAVA_STYLE_TOOLS"
  fi
  [ -n "$SPRING_BOOT_VERSION" ] && echo "- spring-boot: $SPRING_BOOT_VERSION"
  [ -n "$MODULES" ] && echo "- modules: $MODULES"
  [ -n "$MODULE_DEPS" ] && echo "- module-deps: $MODULE_DEPS"
  [ -n "$BUILD_LOGIC" ] && echo "- build-logic: $BUILD_LOGIC"
  [ -n "$VERSION_CATALOG" ] && echo "- version-catalog: $VERSION_CATALOG"
  [ -n "$SOURCE_SETS" ] && echo "- source-sets: $SOURCE_SETS"
  [ -n "$PLUGINS" ] && echo "- plugins: $PLUGINS"
  echo "- architecture: $ARCH_PATTERN ($ARCH_CONFIDENCE confidence)"
  echo "- query-lib: $QUERY_LIB"
  [ -n "$TEST_FRAMEWORKS" ] && echo "- test: $TEST_FRAMEWORKS"
  [ -n "$STYLE_INFO" ] && echo "- style: $STYLE_INFO"
  echo ""

  # Layer Paths
  echo "## Layer Paths"
  IFS='|' read -ra LP <<< "$LAYER_PATHS"
  for entry in "${LP[@]}"; do
    local key="${entry%%:*}"
    local val="${entry#*:}"
    echo "- $key: $val"
  done
  echo ""

  # Static Analysis Allow-list
  local tools_file="$PROJECT_DIR/.sub-kopring-engineer/static-analysis-tools.txt"
  if [ -f "$tools_file" ]; then
    local sa_tools
    sa_tools=$(grep -v '^#' "$tools_file" 2>/dev/null | grep -v '^$' | tr '\n' ',' | sed 's/,$//; s/,/, /g' || true)
    echo "- static-analysis: ${sa_tools:-none}"
  else
    echo "- static-analysis: not-configured"
  fi
  echo ""

  # Detected Conventions
  echo "## Detected Conventions"
  IFS='|' read -ra DC <<< "$DETECTED_CONVENTIONS"
  for entry in "${DC[@]}"; do
    local key="${entry%%:*}"
    local val="${entry#*:}"
    echo "- $key: $val"
  done
}

inject_skill_guidance() {
  local claude_md="$PROJECT_DIR/CLAUDE.md"
  local skill_marker="sub-kopring-engineer"

  # Only inject if architecture is hexagonal-like
  # Bug fix: was $ARCHITECTURE, corrected to $ARCH_PATTERN
  if ! echo "$ARCH_PATTERN" | grep -qiE "hexagonal|ports.*adapters|clean.*hex"; then
    return 0
  fi

  local guidance
  guidance=$(cat <<'GUIDANCE_EOF'

## AI Coding Guidance (sub-kopring-engineer)

This project uses Hexagonal Architecture (Ports & Adapters).
For architectural convention enforcement, use `/sub-kopring-engineer`:

- **Workflow**: Brainstorm → Plan → Implement → Verify
- **Validation**: Layer boundary, module dependency direction
- **Testing**: Port stub patterns, testFixtures conventions

Usage: `/sub-kopring-engineer [your request]`
GUIDANCE_EOF
)

  if [ ! -f "$claude_md" ]; then
    # Create new CLAUDE.md with guidance
    echo "$guidance" > "$claude_md"
    echo ""
    echo "[discover] Created CLAUDE.md with skill guidance"
  elif ! grep -q "$skill_marker" "$claude_md" 2>/dev/null; then
    # Append to existing CLAUDE.md
    echo "$guidance" >> "$claude_md"
    echo ""
    echo "[discover] Added skill guidance to existing CLAUDE.md"
  fi
}
