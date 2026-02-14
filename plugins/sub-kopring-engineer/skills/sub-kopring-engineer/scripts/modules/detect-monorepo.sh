#!/bin/bash
# Module: detect-monorepo.sh
# Detects monorepo structure and adjusts PROJECT_DIR accordingly.
#
# Input globals:  PROJECT_DIR
# Output globals: IS_MONOREPO, PROJECT_NAME, PROJECT_DIR (may be updated)

detect_monorepo() {
  local dir="$1"
  local has_settings=false
  local subproject_count=0
  local subprojects=""

  # Check if current directory has settings.gradle.kts
  if [ -f "$dir/settings.gradle.kts" ] || [ -f "$dir/settings.gradle" ]; then
    has_settings=true
  fi

  # Count subprojects with their own settings.gradle.kts (1-depth only)
  for subdir in "$dir"/*/; do
    [ -d "$subdir" ] || continue
    if [ -f "${subdir}settings.gradle.kts" ] || [ -f "${subdir}settings.gradle" ]; then
      subproject_count=$((subproject_count + 1))
      subprojects+="$(basename "$subdir") "
    fi
  done

  # Condition A: No settings at root + multiple subprojects → monorepo root
  if [ "$has_settings" = false ] && [ "$subproject_count" -ge 2 ]; then
    IS_MONOREPO=true
    echo "[discover] Monorepo detected: $subproject_count projects found (${subprojects% })" >&2

    # If no explicit project specified, use first subproject or warn
    if [ -z "$EXPLICIT_PROJECT" ]; then
      # Try to find a subproject that matches cwd
      local cwd_name
      cwd_name="$(basename "$(pwd)")"
      for subdir in "$dir"/*/; do
        [ -d "$subdir" ] || continue
        if [ -f "${subdir}settings.gradle.kts" ] || [ -f "${subdir}settings.gradle" ]; then
          if [ "$(basename "$subdir")" = "$cwd_name" ]; then
            EXPLICIT_PROJECT="$subdir"
            break
          fi
        fi
      done

      # If still no match, list available projects
      if [ -z "$EXPLICIT_PROJECT" ]; then
        echo "[discover] Available projects: ${subprojects% }" >&2
        echo "[discover] Use --project <name> to specify, or cd into a project directory" >&2
        # Default to first project
        for subdir in "$dir"/*/; do
          if [ -f "${subdir}settings.gradle.kts" ] || [ -f "${subdir}settings.gradle" ]; then
            EXPLICIT_PROJECT="$subdir"
            break
          fi
        done
      fi
    fi
    return 0
  fi

  # Condition B: Current dir != git root but has own settings → subproject
  local git_root
  git_root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")"
  if [ "$has_settings" = true ] && [ "$dir" != "$git_root" ]; then
    IS_MONOREPO=true
    PROJECT_NAME="$(basename "$dir")"
    echo "[discover] Subproject detected: $PROJECT_NAME (monorepo: $git_root)" >&2
    return 0
  fi

  # Condition C: Single project (default)
  IS_MONOREPO=false
  return 0
}
