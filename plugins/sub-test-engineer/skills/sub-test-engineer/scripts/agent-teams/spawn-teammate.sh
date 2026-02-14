#!/usr/bin/env bash
# spawn-teammate.sh — Utility for spawning Agent Teams teammates
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   spawn-teammate.sh <team-name> <teammate-name> <prompt-file> [subagent-type]
#
# Arguments:
#   team-name      : Name of the team (e.g., "sub-test-gen-20260206")
#   teammate-name  : Name for this teammate (e.g., "unit-tester")
#   prompt-file    : Path to prompt template file
#   subagent-type  : Agent type (default: "general-purpose")
#
# Environment:
#   CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 must be set
#
# Output:
#   Prints teammate spawn instructions for Claude to execute
#   Returns JSON with team_name, teammate_name, status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Argument Parsing ---
if [ $# -lt 3 ]; then
    cat <<USAGE
Usage: spawn-teammate.sh <team-name> <teammate-name> <prompt-file> [subagent-type]

Arguments:
  team-name      : Name of the team (e.g., "sub-test-gen-20260206")
  teammate-name  : Name for this teammate (e.g., "unit-tester")
  prompt-file    : Path to prompt template file
  subagent-type  : Agent type (default: "general-purpose")

Example:
  spawn-teammate.sh sub-test-gen-20260206 unit-tester templates/prompts/unit-tester.md
USAGE
    exit 1
fi

TEAM_NAME="$1"
TEAMMATE_NAME="$2"
PROMPT_FILE="$3"
SUBAGENT_TYPE="${4:-general-purpose}"

# --- Pre-flight Checks ---

# Check Agent Teams enabled
if ! "$SCRIPT_DIR/../check-agent-teams.sh" --quiet 2>/dev/null; then
    echo "ERROR: Agent Teams not enabled. Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" >&2
    exit 1
fi

# Check prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    # Try relative to SKILLS_ROOT
    if [ -f "$SKILLS_ROOT/$PROMPT_FILE" ]; then
        PROMPT_FILE="$SKILLS_ROOT/$PROMPT_FILE"
    else
        echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
        exit 1
    fi
fi

# Read prompt content
PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# --- Team Directory Setup ---
TEAM_DIR="$HOME/.claude/teams/$TEAM_NAME"
INBOX_DIR="$TEAM_DIR/inboxes"

# Create team directories if they don't exist
mkdir -p "$TEAM_DIR" "$INBOX_DIR"

# Initialize team config if not exists
CONFIG_FILE="$TEAM_DIR/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<CONFIG_EOF
{
  "name": "$TEAM_NAME",
  "created_at": "$(date -Iseconds)",
  "lead_agent_id": "team-lead@$TEAM_NAME",
  "members": [
    {
      "agent_id": "team-lead@$TEAM_NAME",
      "name": "team-lead",
      "agent_type": "team-lead",
      "status": "active"
    }
  ]
}
CONFIG_EOF
fi

# --- Add Teammate to Config ---
# Use jq if available, otherwise use simple append
if command -v jq &>/dev/null; then
    TEMP_CONFIG=$(mktemp)
    jq --arg name "$TEAMMATE_NAME" \
       --arg id "${TEAMMATE_NAME}@${TEAM_NAME}" \
       --arg type "$SUBAGENT_TYPE" \
       '.members += [{"agent_id": $id, "name": $name, "agent_type": $type, "status": "spawning"}]' \
       "$CONFIG_FILE" > "$TEMP_CONFIG"
    mv "$TEMP_CONFIG" "$CONFIG_FILE"
fi

# Create teammate inbox file
TEAMMATE_INBOX="$INBOX_DIR/${TEAMMATE_NAME}.json"
echo "[]" > "$TEAMMATE_INBOX"

# --- Output Spawn Instructions ---
# This output is meant to be used by the Lead agent to spawn the teammate

cat <<SPAWN_INSTRUCTIONS

## Teammate Spawn Instructions

Execute the following to spawn teammate "$TEAMMATE_NAME":

\`\`\`
Task({
  team_name: "$TEAM_NAME",
  name: "$TEAMMATE_NAME",
  subagent_type: "$SUBAGENT_TYPE",
  prompt: $(echo "$PROMPT_CONTENT" | jq -Rs .),
  run_in_background: true
})
\`\`\`

Teammate info:
- Agent ID: ${TEAMMATE_NAME}@${TEAM_NAME}
- Inbox: $TEAMMATE_INBOX
- Status: ready to spawn

SPAWN_INSTRUCTIONS

# --- Output JSON for programmatic use ---
cat <<JSON_OUTPUT

{"team_name":"$TEAM_NAME","teammate_name":"$TEAMMATE_NAME","agent_id":"${TEAMMATE_NAME}@${TEAM_NAME}","inbox":"$TEAMMATE_INBOX","status":"ready","subagent_type":"$SUBAGENT_TYPE"}
JSON_OUTPUT
