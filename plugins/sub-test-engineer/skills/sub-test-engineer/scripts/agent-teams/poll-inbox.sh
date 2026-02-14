#!/usr/bin/env bash
# poll-inbox.sh — Poll teammate inboxes for messages
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   poll-inbox.sh <team-name> [--wait] [--timeout <seconds>] [--teammate <name>]
#
# Arguments:
#   team-name      : Name of the team
#   --wait         : Block until all teammates report completion
#   --timeout      : Max seconds to wait (default: 300)
#   --teammate     : Filter to specific teammate inbox
#
# Output:
#   JSON array of messages from teammate inboxes
#   Exit codes:
#     0 = success (all teammates completed if --wait)
#     1 = error
#     2 = timeout
#     3 = teammate failure detected

set -euo pipefail

# --- Argument Parsing ---
TEAM_NAME=""
WAIT_MODE=false
TIMEOUT=300
SPECIFIC_TEAMMATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wait)
            WAIT_MODE=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --teammate)
            SPECIFIC_TEAMMATE="$2"
            shift 2
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
Usage: poll-inbox.sh <team-name> [--wait] [--timeout <seconds>] [--teammate <name>]

Arguments:
  team-name      : Name of the team
  --wait         : Block until all teammates report completion
  --timeout      : Max seconds to wait (default: 300)
  --teammate     : Filter to specific teammate inbox

Example:
  poll-inbox.sh sub-test-gen-20260206 --wait --timeout 600
  poll-inbox.sh sub-test-gen-20260206 --teammate unit-tester
USAGE
    exit 1
fi

# --- Team Directory ---
TEAM_DIR="$HOME/.claude/teams/$TEAM_NAME"
INBOX_DIR="$TEAM_DIR/inboxes"
CONFIG_FILE="$TEAM_DIR/config.json"

if [ ! -d "$TEAM_DIR" ]; then
    echo "ERROR: Team not found: $TEAM_NAME" >&2
    exit 1
fi

# --- Helper Functions ---

# Read all messages from an inbox file
read_inbox() {
    local inbox_file="$1"
    if [ -f "$inbox_file" ] && [ -s "$inbox_file" ]; then
        cat "$inbox_file"
    else
        echo "[]"
    fi
}

# Check if a message indicates completion
is_completion_message() {
    local msg="$1"
    echo "$msg" | grep -qE '"status"\s*:\s*"completed"'
}

# Check if a message indicates failure
is_failure_message() {
    local msg="$1"
    echo "$msg" | grep -qE '"status"\s*:\s*"failed"'
}

# Get list of teammate names (excluding team-lead)
get_teammates() {
    if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
        jq -r '.members[] | select(.name != "team-lead") | .name' "$CONFIG_FILE" 2>/dev/null || true
    else
        # Fallback: list inbox files
        for inbox in "$INBOX_DIR"/*.json; do
            if [ -f "$inbox" ]; then
                basename "$inbox" .json
            fi
        done
    fi
}

# --- Single Poll Mode ---
if [ "$WAIT_MODE" = false ]; then
    ALL_MESSAGES="[]"

    if [ -n "$SPECIFIC_TEAMMATE" ]; then
        # Poll specific teammate
        INBOX_FILE="$INBOX_DIR/${SPECIFIC_TEAMMATE}.json"
        if [ -f "$INBOX_FILE" ]; then
            ALL_MESSAGES=$(read_inbox "$INBOX_FILE")
        fi
    else
        # Poll all inboxes
        for inbox in "$INBOX_DIR"/*.json; do
            if [ -f "$inbox" ]; then
                TEAMMATE=$(basename "$inbox" .json)
                MESSAGES=$(read_inbox "$inbox")
                if command -v jq &>/dev/null; then
                    ALL_MESSAGES=$(echo "$ALL_MESSAGES" "$MESSAGES" | jq -s 'add')
                fi
            fi
        done
    fi

    echo "$ALL_MESSAGES"
    exit 0
fi

# --- Wait Mode ---
echo "Waiting for teammates to complete (timeout: ${TIMEOUT}s)..." >&2

START_TIME=$(date +%s)
TEAMMATES=$(get_teammates)
declare -A COMPLETED

# Initialize completion tracking
for teammate in $TEAMMATES; do
    COMPLETED[$teammate]=false
done

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: Timeout waiting for teammates" >&2
        # Output partial results
        echo "{"
        echo "  \"status\": \"timeout\","
        echo "  \"elapsed_seconds\": $ELAPSED,"
        echo "  \"completed\": ["
        FIRST=true
        for teammate in $TEAMMATES; do
            if [ "${COMPLETED[$teammate]}" = true ]; then
                if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
                echo -n "    \"$teammate\""
            fi
        done
        echo ""
        echo "  ],"
        echo "  \"pending\": ["
        FIRST=true
        for teammate in $TEAMMATES; do
            if [ "${COMPLETED[$teammate]}" = false ]; then
                if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
                echo -n "    \"$teammate\""
            fi
        done
        echo ""
        echo "  ]"
        echo "}"
        exit 2
    fi

    # Check each teammate's inbox
    ALL_DONE=true
    FAILURE_DETECTED=false
    FAILED_TEAMMATE=""

    for teammate in $TEAMMATES; do
        if [ "${COMPLETED[$teammate]}" = true ]; then
            continue
        fi

        INBOX_FILE="$INBOX_DIR/${teammate}.json"
        if [ -f "$INBOX_FILE" ] && [ -s "$INBOX_FILE" ]; then
            MESSAGES=$(cat "$INBOX_FILE")

            # Check for completion
            if echo "$MESSAGES" | grep -qE '"status"\s*:\s*"completed"'; then
                COMPLETED[$teammate]=true
                echo "  ✓ $teammate completed" >&2
            elif echo "$MESSAGES" | grep -qE '"status"\s*:\s*"failed"'; then
                FAILURE_DETECTED=true
                FAILED_TEAMMATE="$teammate"
                break
            else
                ALL_DONE=false
            fi
        else
            ALL_DONE=false
        fi
    done

    if [ "$FAILURE_DETECTED" = true ]; then
        echo "ERROR: Teammate failed: $FAILED_TEAMMATE" >&2
        cat "$INBOX_DIR/${FAILED_TEAMMATE}.json"
        exit 3
    fi

    if [ "$ALL_DONE" = true ]; then
        echo "All teammates completed successfully." >&2

        # Collect all results
        echo "{"
        echo "  \"status\": \"success\","
        echo "  \"elapsed_seconds\": $ELAPSED,"
        echo "  \"results\": {"

        FIRST=true
        for teammate in $TEAMMATES; do
            INBOX_FILE="$INBOX_DIR/${teammate}.json"
            if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
            echo "    \"$teammate\": $(cat "$INBOX_FILE")"
        done

        echo "  }"
        echo "}"
        exit 0
    fi

    # Wait before next poll
    sleep 5
done
