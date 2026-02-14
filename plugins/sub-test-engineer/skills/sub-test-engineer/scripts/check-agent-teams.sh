#!/usr/bin/env bash
# check-agent-teams.sh — Checks if Agent Teams experimental feature is enabled.
# Usage: check-agent-teams.sh [--quiet]
#
# Exit codes:
#   0: Agent Teams is enabled and ready
#   1: Agent Teams is not enabled
#   2: Agent Teams is enabled but spawn backend unavailable
#
# Output (unless --quiet):
#   enabled|disabled
#   backend: tmux|iterm2|in-process|none

set -euo pipefail

QUIET="${1:-}"

# --- Check environment variable ---
AGENT_TEAMS_ENABLED="${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"

if [ "$AGENT_TEAMS_ENABLED" != "1" ] && [ "$AGENT_TEAMS_ENABLED" != "true" ]; then
    [ "$QUIET" != "--quiet" ] && echo "disabled"
    exit 1
fi

# --- Detect spawn backend ---
detect_backend() {
    # Check for tmux session
    if [ -n "${TMUX:-}" ]; then
        echo "tmux"
        return 0
    fi

    # Check for iTerm2
    if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
        if command -v it2check &>/dev/null; then
            echo "iterm2"
            return 0
        fi
    fi

    # Check for tmux availability (can spawn new session)
    if command -v tmux &>/dev/null; then
        echo "tmux"
        return 0
    fi

    # Fallback: in-process (dies with leader)
    echo "in-process"
    return 0
}

BACKEND=$(detect_backend)

if [ "$QUIET" != "--quiet" ]; then
    echo "enabled"
    echo "backend: $BACKEND"
fi

# Warn if only in-process is available (teammates die with leader)
if [ "$BACKEND" = "in-process" ]; then
    [ "$QUIET" != "--quiet" ] && echo "WARN: Only in-process backend available. Teammates will not survive leader exit."
fi

exit 0
