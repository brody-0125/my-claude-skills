#!/bin/bash
# setup-hooks.sh - Script to install Claude Code Hooks configuration into a project
# Usage: ./setup-hooks.sh [project-path] [--auto]
#
# --auto: Non-interactive mode. Skips if hooks already exist. Used by discover-project.sh.
#
# PostToolUse: Automatically runs ktlintCheck when .kt files are modified
# PreToolUse: Blocks production secret file modification
# Stop: Requires tests to pass on session end (Quality Gate)

set -euo pipefail

PROJECT_DIR="${1:-.}"
AUTO_MODE=false
for arg in "$@"; do
  [ "$arg" = "--auto" ] && AUTO_MODE=true
done

SETTINGS_DIR="$PROJECT_DIR/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
HOOKS_TEMPLATE="$(dirname "$0")/../templates/hooks-config.json"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Check required files
if [ ! -f "$HOOKS_TEMPLATE" ]; then
    [ "$AUTO_MODE" = true ] && exit 0
    echo -e "${RED}Error: hooks-config.json template not found.${NC}"
    echo "Path: $HOOKS_TEMPLATE"
    exit 1
fi

# Auto mode: skip if hooks already configured
if [ "$AUTO_MODE" = true ]; then
    if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1 && jq -e '.hooks' "$SETTINGS_FILE" >/dev/null 2>&1; then
        exit 0  # Hooks already exist, nothing to do
    fi
    # Auto-install: create or merge
    mkdir -p "$SETTINGS_DIR"
    if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        hooks_content=$(cat "$HOOKS_TEMPLATE")
        jq --argjson hooks "$hooks_content" '. * $hooks' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" 2>/dev/null
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        cp "$HOOKS_TEMPLATE" "$SETTINGS_FILE"
    fi
    echo "[discover] Hooks auto-installed: lint-on-edit, secret-guard, test-quality-gate"
    exit 0
fi

# Interactive mode
echo "=========================================="
echo "  Kopring Coder — Hooks Installation"
echo "=========================================="
echo ""

# 2. Create .claude directory
mkdir -p "$SETTINGS_DIR"

# 3. Check existing settings
if [ -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}Existing settings.json found.${NC}"
    echo ""

    # Check if hooks key exists
    if command -v jq >/dev/null 2>&1 && jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Existing hooks configuration found. Overwriting will lose current settings.${NC}"
        echo ""
        echo "Options:"
        echo "  1) Overwrite (replace existing hooks)"
        echo "  2) Backup and overwrite"
        echo "  3) Cancel"
        echo ""
        read -p "Choose (1/2/3): " choice

        case "$choice" in
            1)
                echo "Replacing existing hooks..."
                ;;
            2)
                backup_file="${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"
                cp "$SETTINGS_FILE" "$backup_file"
                echo -e "${GREEN}Backup complete: $backup_file${NC}"
                ;;
            3)
                echo "Cancelled."
                exit 0
                ;;
            *)
                echo "Invalid input. Cancelling."
                exit 1
                ;;
        esac
    fi

    # Merge hooks into existing settings
    hooks_content=$(cat "$HOOKS_TEMPLATE")
    if command -v jq >/dev/null 2>&1; then
        jq --argjson hooks "$hooks_content" '. * $hooks' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        cp "$HOOKS_TEMPLATE" "$SETTINGS_FILE"
    fi
else
    # Create new
    cp "$HOOKS_TEMPLATE" "$SETTINGS_FILE"
fi

echo ""
echo -e "${GREEN}Hooks installation complete${NC}"
echo ""
echo "Installed Hooks:"
echo "  [PostToolUse] Auto-runs lint on .kt/.java file modification (ktlintCheck/checkstyleMain)"
echo "  [PreToolUse]  Blocks production secret file modification"
echo "  [Stop]        Requires tests to pass on session end"
echo ""
echo "Settings file: $SETTINGS_FILE"
echo ""
echo "To disable, remove the hooks section from settings.json."
echo ""
