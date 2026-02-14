#!/usr/bin/env bash
# setup-hooks.sh — Install numerical hooks into project settings
# Usage: ./setup-hooks.sh [--auto]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

AUTO=false
[ "${1:-}" = "--auto" ] && AUTO=true

PROJECT_ROOT=$(find_project_root)
SETTINGS_DIR="$PROJECT_ROOT/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"

# --- Check if hooks already installed ---
if [ -f "$SETTINGS_FILE" ]; then
  if grep -q "numerical" "$SETTINGS_FILE" 2>/dev/null; then
    log_info "Hooks already installed in $SETTINGS_FILE"
    exit 0
  fi
fi

log_info "Installing numerical hooks"

# --- Detect language for appropriate hooks ---
LANGUAGE=$(detect_language "$PROJECT_ROOT")
log_info "Detected language: $LANGUAGE"

# --- Create settings directory ---
mkdir -p "$SETTINGS_DIR"

# --- Build hooks config ---
HOOKS_TEMPLATE="$SCRIPT_DIR/../templates/hooks-config.json"

if [ -f "$HOOKS_TEMPLATE" ]; then
  if [ ! -f "$SETTINGS_FILE" ]; then
    cp "$HOOKS_TEMPLATE" "$SETTINGS_FILE"
    log_ok "Hooks installed from template: $SETTINGS_FILE"
  else
    log_warn "Settings file exists. Please manually merge hooks from: $HOOKS_TEMPLATE"
  fi
else
  log_warn "Hooks template not found at $HOOKS_TEMPLATE"
fi

# --- Create .numerical directory ---
DATA_DIR="$PROJECT_ROOT/.numerical"
if [ ! -d "$DATA_DIR" ]; then
  mkdir -p "$DATA_DIR"

  # Create .gitignore
  cat > "$DATA_DIR/.gitignore" << 'GITIGNORE'
# Execution state files (local only)
**/interaction-state.yaml
# Cache files
*.cache
GITIGNORE

  log_ok "Created $DATA_DIR with .gitignore"
fi

log_ok "Setup complete"
