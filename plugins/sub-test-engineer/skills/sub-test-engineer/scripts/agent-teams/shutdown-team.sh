#!/usr/bin/env bash
# shutdown-team.sh — Gracefully shutdown Agent Teams teammates and cleanup
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   shutdown-team.sh <team-name> [--force] [--keep-logs]
#
# Arguments:
#   team-name   : Name of the team to shutdown
#   --force     : Skip graceful shutdown, cleanup immediately
#   --keep-logs : Preserve team directory and logs after cleanup
#
# Process:
#   1. Request shutdown from each teammate
#   2. Wait for shutdown acknowledgments (30s timeout)
#   3. Cleanup team resources
#
# Output:
#   JSON with shutdown status and any collected results

set -euo pipefail

# --- Argument Parsing ---
TEAM_NAME=""
FORCE_MODE=false
KEEP_LOGS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [ -z "$TEAM_NAME" ]; then
                TEAM_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$TEAM_NAME" ]; then
    cat <<USAGE
Usage: shutdown-team.sh <team-name> [--force] [--keep-logs]

Arguments:
  team-name   : Name of the team to shutdown
  --force     : Skip graceful shutdown, cleanup immediately
  --keep-logs : Preserve team directory and logs after cleanup

Example:
  shutdown-team.sh sub-test-gen-20260206
  shutdown-team.sh sub-test-gen-20260206 --force --keep-logs
USAGE
    exit 1
fi

# --- Team Directory ---
TEAM_DIR="$HOME/.claude/teams/$TEAM_NAME"
INBOX_DIR="$TEAM_DIR/inboxes"
CONFIG_FILE="$TEAM_DIR/config.json"

if [ ! -d "$TEAM_DIR" ]; then
    echo "Team not found: $TEAM_NAME (already cleaned up?)" >&2
    exit 0
fi

# --- Helper Functions ---

get_teammates() {
    if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
        jq -r '.members[] | select(.name != "team-lead") | .name' "$CONFIG_FILE" 2>/dev/null || true
    else
        for inbox in "$INBOX_DIR"/*.json; do
            if [ -f "$inbox" ]; then
                basename "$inbox" .json
            fi
        done
    fi
}

# Collect final results from all teammates
collect_results() {
    local results_file="$TEAM_DIR/final-results.json"

    echo "{" > "$results_file"
    echo "  \"team\": \"$TEAM_NAME\"," >> "$results_file"
    echo "  \"shutdown_at\": \"$(date -Iseconds)\"," >> "$results_file"
    echo "  \"teammates\": {" >> "$results_file"

    local FIRST=true
    for teammate in $(get_teammates); do
        INBOX_FILE="$INBOX_DIR/${teammate}.json"
        if [ -f "$INBOX_FILE" ] && [ -s "$INBOX_FILE" ]; then
            if [ "$FIRST" = true ]; then FIRST=false; else echo "," >> "$results_file"; fi
            echo "    \"$teammate\": $(cat "$INBOX_FILE")" >> "$results_file"
        fi
    done

    echo "  }" >> "$results_file"
    echo "}" >> "$results_file"

    cat "$results_file"
}

# --- Force Mode ---
if [ "$FORCE_MODE" = true ]; then
    echo "Force shutdown initiated for team: $TEAM_NAME" >&2

    # Collect results before cleanup
    RESULTS=$(collect_results)

    if [ "$KEEP_LOGS" = false ]; then
        rm -rf "$TEAM_DIR"
        echo "Team directory removed: $TEAM_DIR" >&2
    else
        echo "Team directory preserved: $TEAM_DIR" >&2
    fi

    echo "$RESULTS"
    exit 0
fi

# --- Graceful Shutdown ---
echo "Initiating graceful shutdown for team: $TEAM_NAME" >&2

TEAMMATES=$(get_teammates)
SHUTDOWN_TIMEOUT=30
START_TIME=$(date +%s)

# Output shutdown request instructions
cat <<SHUTDOWN_INSTRUCTIONS

## Shutdown Instructions

Execute the following to request shutdown from each teammate:

SHUTDOWN_INSTRUCTIONS

for teammate in $TEAMMATES; do
    cat <<TEAMMATE_SHUTDOWN

### Shutdown: $teammate
\`\`\`
Teammate({
  operation: "requestShutdown",
  target_agent_id: "${teammate}@${TEAM_NAME}"
})
\`\`\`

TEAMMATE_SHUTDOWN
done

cat <<CLEANUP_INSTRUCTIONS

### After all teammates acknowledge, execute cleanup:
\`\`\`
Teammate({
  operation: "cleanup"
})
\`\`\`

CLEANUP_INSTRUCTIONS

# Update config to mark shutdown in progress
if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    TEMP_CONFIG=$(mktemp)
    jq '.status = "shutting_down" | .shutdown_initiated = "'"$(date -Iseconds)"'"' \
       "$CONFIG_FILE" > "$TEMP_CONFIG"
    mv "$TEMP_CONFIG" "$CONFIG_FILE"
fi

# Collect results
echo "" >&2
echo "Collecting final results..." >&2
RESULTS=$(collect_results)

# Archive results if keeping logs
if [ "$KEEP_LOGS" = true ]; then
    ARCHIVE_DIR="$HOME/.claude/teams-archive"
    mkdir -p "$ARCHIVE_DIR"
    ARCHIVE_FILE="$ARCHIVE_DIR/${TEAM_NAME}-$(date +%Y%m%d-%H%M%S).json"
    echo "$RESULTS" > "$ARCHIVE_FILE"
    echo "Results archived to: $ARCHIVE_FILE" >&2
fi

# Output final results
echo "$RESULTS"

# Summary
cat >&2 <<SUMMARY

## Shutdown Summary

Team: $TEAM_NAME
Teammates: $(echo "$TEAMMATES" | wc -w | tr -d ' ')
Status: Shutdown instructions generated

Next steps:
1. Execute the Teammate shutdown requests above
2. Wait for acknowledgments
3. Execute cleanup command
4. Verify team directory removed

SUMMARY

if [ "$KEEP_LOGS" = false ]; then
    echo "Note: Team directory will be removed by cleanup command." >&2
else
    echo "Note: Team directory will be preserved (--keep-logs)." >&2
fi
