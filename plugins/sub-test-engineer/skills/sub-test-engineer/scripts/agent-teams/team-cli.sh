#!/usr/bin/env bash
# team-cli.sh — Unified CLI for Agent Teams operations
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   team-cli.sh <command> [options]
#
# Commands:
#   spawn   <team-name> <teammate-name> <prompt-file> [subagent-type]
#   poll    <team-name> [--wait] [--timeout <seconds>] [--teammate <name>]
#   status  <team-name>
#   aggregate <team-name> [--format json|md]
#   shutdown  <team-name> [--force] [--keep-logs]
#   detect    [project-root]
#   partition <team-name> <targets-file> [--by-technique|--by-module]
#
# This is a unified interface that delegates to individual scripts.
# Backward compatibility is maintained via symlinks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Help ---
show_help() {
    cat <<HELP
team-cli.sh — Unified CLI for Agent Teams operations

Usage:
  team-cli.sh <command> [options]

Commands:
  spawn     <team-name> <teammate-name> <prompt-file> [subagent-type]
            Spawn a new teammate in the team

  poll      <team-name> [--wait] [--timeout <seconds>] [--teammate <name>]
            Poll teammate inboxes for messages

  status    <team-name>
            Show team status and member states

  aggregate <team-name> [--format json|md]
            Aggregate results from all teammates

  shutdown  <team-name> [--force] [--keep-logs]
            Shutdown team and cleanup resources

  detect    [project-root]
            Detect multi-module structure

  partition <team-name> <targets-file> [--by-technique|--by-module]
            Partition targets for parallel processing

Examples:
  team-cli.sh spawn my-team unit-tester templates/prompts/unit-tester.md
  team-cli.sh poll my-team --wait --timeout 300
  team-cli.sh status my-team
  team-cli.sh aggregate my-team --format md
  team-cli.sh shutdown my-team --force

Environment:
  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 must be set to enable Agent Teams
HELP
}

# --- Status Command ---
show_status() {
    local team_name="$1"
    local team_dir="$HOME/.claude/teams/$team_name"
    local config_file="$team_dir/config.json"

    if [ ! -d "$team_dir" ]; then
        echo "Team not found: $team_name" >&2
        exit 1
    fi

    echo "=== Team Status: $team_name ==="
    echo ""

    if [ -f "$config_file" ] && command -v jq &>/dev/null; then
        echo "Created: $(jq -r '.created_at // "unknown"' "$config_file")"
        echo "Status: $(jq -r '.status // "active"' "$config_file")"
        echo ""
        echo "Members:"
        jq -r '.members[] | "  - \(.name) (\(.agent_type)): \(.status)"' "$config_file"
    else
        echo "Config: $config_file"
        echo ""
        echo "Inboxes:"
        for inbox in "$team_dir/inboxes"/*.json; do
            if [ -f "$inbox" ]; then
                local name
                name=$(basename "$inbox" .json)
                local msg_count
                msg_count=$(wc -l < "$inbox" 2>/dev/null || echo "0")
                echo "  - $name: $msg_count lines"
            fi
        done
    fi

    echo ""
    echo "Directory: $team_dir"
}

# --- Aggregate Command ---
aggregate_results() {
    local team_name="$1"
    shift
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Delegate to aggregate-results.sh if it exists
    if [ -f "$SCRIPT_DIR/aggregate-results.sh" ]; then
        "$SCRIPT_DIR/aggregate-results.sh" "$team_name" --format "$format"
    else
        # Fallback: simple aggregation
        local team_dir="$HOME/.claude/teams/$team_name"
        local inbox_dir="$team_dir/inboxes"

        if [ ! -d "$team_dir" ]; then
            echo "Team not found: $team_name" >&2
            exit 1
        fi

        if [ "$format" = "md" ]; then
            echo "# Team Results: $team_name"
            echo ""
            for inbox in "$inbox_dir"/*.json; do
                if [ -f "$inbox" ]; then
                    local name
                    name=$(basename "$inbox" .json)
                    echo "## $name"
                    echo ""
                    echo '```json'
                    cat "$inbox"
                    echo '```'
                    echo ""
                fi
            done
        else
            # JSON format
            echo "{"
            echo "  \"team\": \"$team_name\","
            echo "  \"aggregated_at\": \"$(date -Iseconds)\","
            echo "  \"results\": {"

            local first=true
            for inbox in "$inbox_dir"/*.json; do
                if [ -f "$inbox" ]; then
                    local name
                    name=$(basename "$inbox" .json)
                    if [ "$first" = true ]; then first=false; else echo ","; fi
                    echo "    \"$name\": $(cat "$inbox")"
                fi
            done

            echo "  }"
            echo "}"
        fi
    fi
}

# --- Main Command Dispatch ---
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    spawn)
        exec "$SCRIPT_DIR/spawn-teammate.sh" "$@"
        ;;
    poll)
        exec "$SCRIPT_DIR/poll-inbox.sh" "$@"
        ;;
    status)
        if [ $# -lt 1 ]; then
            echo "Usage: team-cli.sh status <team-name>" >&2
            exit 1
        fi
        show_status "$1"
        ;;
    aggregate)
        if [ $# -lt 1 ]; then
            echo "Usage: team-cli.sh aggregate <team-name> [--format json|md]" >&2
            exit 1
        fi
        aggregate_results "$@"
        ;;
    shutdown)
        exec "$SCRIPT_DIR/shutdown-team.sh" "$@"
        ;;
    detect)
        exec "$SCRIPT_DIR/detect-modules.sh" "$@"
        ;;
    partition)
        if [ $# -lt 2 ]; then
            echo "Usage: team-cli.sh partition <team-name> <targets-file> [--by-technique|--by-module]" >&2
            exit 1
        fi
        exec "$SCRIPT_DIR/partition-targets.sh" "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        echo "Run 'team-cli.sh help' for usage information." >&2
        exit 1
        ;;
esac
