#!/bin/bash
# Module: detect-multi-module.sh
# Analyzes multi-module project structure (dependencies, source sets, build logic).
#
# Input globals:  PROJECT_DIR, MODULES
# Output globals: MODULE_DEPS, SOURCE_SETS, BUILD_LOGIC, VERSION_CATALOG

MODULE_DEPS=""
SOURCE_SETS=""
BUILD_LOGIC=""
VERSION_CATALOG=""

detect_multi_module() {
  [ -z "$MODULES" ] && return

  local project_dir="$PROJECT_DIR"

  # C-1a. Module dependency analysis
  local deps_output=""
  local IFS_ORIG="$IFS"
  IFS=',' read -ra mod_arr <<< "$MODULES"
  IFS="$IFS_ORIG"
  for mod in "${mod_arr[@]}"; do
    mod=$(echo "$mod" | tr -d ' ' | sed 's/^://')
    local mod_build=""
    # Try common module build file locations
    for candidate in \
      "$project_dir/$mod/build.gradle.kts" \
      "$project_dir/$mod/build.gradle" \
      "$project_dir/${mod/://\/}/build.gradle.kts" \
      "$project_dir/${mod/://\/}/build.gradle"; do
      if [ -f "$candidate" ]; then
        mod_build="$candidate"
        break
      fi
    done
    [ -z "$mod_build" ] && continue

    local mod_deps
    mod_deps=$(grep -oE 'project\(":([^"]+)"\)' "$mod_build" 2>/dev/null | sed 's/project("://;s/")//' | sort -u | tr '\n' '+' | sed 's/+$//' || true)
    [ -z "$mod_deps" ] && mod_deps=$(grep -oE "project\(':([^']+)'\)" "$mod_build" 2>/dev/null | sed "s/project('://;s/')//" | sort -u | tr '\n' '+' | sed 's/+$//' || true)

    if [ -n "$mod_deps" ]; then
      deps_output+="${mod}→${mod_deps}, "
    else
      deps_output+="${mod}→(none), "
    fi
  done
  MODULE_DEPS="${deps_output%, }"

  # C-1b. Source set detection
  local sets_found="main, test"
  find "$project_dir" -path "*/src/testFixtures" -type d 2>/dev/null | head -1 | grep -q . && sets_found+=", testFixtures"
  find "$project_dir" -path "*/src/integrationTest" -type d 2>/dev/null | head -1 | grep -q . && sets_found+=", integrationTest"
  SOURCE_SETS="$sets_found"

  # C-1c. Convention Plugin / Version Catalog detection
  if [ -d "$project_dir/build-logic" ]; then
    BUILD_LOGIC="build-logic/ (convention plugins)"
  elif [ -d "$project_dir/buildSrc" ]; then
    BUILD_LOGIC="buildSrc/"
  fi

  if [ -f "$project_dir/gradle/libs.versions.toml" ]; then
    VERSION_CATALOG="gradle/libs.versions.toml"
  fi
}
