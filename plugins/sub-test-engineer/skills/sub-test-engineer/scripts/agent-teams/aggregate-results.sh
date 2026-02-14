#!/usr/bin/env bash
# aggregate-results.sh — Aggregate results from Agent Teams teammates
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   aggregate-results.sh <team-name> [--output <file>] [--format <json|markdown>]
#
# Arguments:
#   team-name       : Name of the team
#   --output        : Output file path (default: stdout)
#   --format        : Output format: json (default) or markdown
#
# Input:
#   Reads completion messages from teammate inboxes
#
# Output:
#   Aggregated results including:
#   - All generated files across teammates
#   - Combined compile success/failure counts
#   - Merged error list
#   - Per-teammate breakdown

set -euo pipefail

# --- Argument Parsing ---
TEAM_NAME=""
OUTPUT_FILE=""
OUTPUT_FORMAT="json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            [ -z "$TEAM_NAME" ] && TEAM_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$TEAM_NAME" ]; then
    cat <<USAGE
Usage: aggregate-results.sh <team-name> [--output <file>] [--format <json|markdown>]

Arguments:
  team-name       : Name of the team
  --output        : Output file path (default: stdout)
  --format        : Output format: json (default) or markdown

Example:
  aggregate-results.sh sub-test-gen-20260206 --format markdown --output results.md
USAGE
    exit 1
fi

# --- Team Directory ---
TEAM_DIR="$HOME/.claude/teams/$TEAM_NAME"
INBOX_DIR="$TEAM_DIR/inboxes"

if [ ! -d "$TEAM_DIR" ]; then
    echo "ERROR: Team not found: $TEAM_NAME" >&2
    exit 1
fi

# --- Aggregate Data ---
declare -a ALL_FILES=()
declare -a ALL_ERRORS=()
declare -a TEAMMATE_RESULTS=()
TOTAL_COMPILE_SUCCESS=0
TOTAL_COMPILE_FAILURE=0
TOTAL_TARGETS=0
PROPERTIES_DEFINED=0
GENERATORS_CREATED=0

# Process each teammate inbox
for inbox_file in "$INBOX_DIR"/*.json; do
    [ -f "$inbox_file" ] || continue

    teammate=$(basename "$inbox_file" .json)
    [ "$teammate" = "team-lead" ] && continue

    # Parse inbox messages
    if [ -s "$inbox_file" ] && command -v jq &>/dev/null; then
        # Find the task_completed message
        completed_msg=$(jq -r '
            if type == "array" then
                .[] | select(.type == "task_completed")
            else
                select(.type == "task_completed")
            end
        ' "$inbox_file" 2>/dev/null || echo "{}")

        if [ -n "$completed_msg" ] && [ "$completed_msg" != "{}" ]; then
            # Extract data from completed message
            status=$(echo "$completed_msg" | jq -r '.payload.status // "unknown"')
            targets=$(echo "$completed_msg" | jq -r '.payload.targets_processed // 0')
            files=$(echo "$completed_msg" | jq -r '.payload.generated_files // [] | .[]' 2>/dev/null)
            success=$(echo "$completed_msg" | jq -r '.payload.compile_results.success // 0')
            failure=$(echo "$completed_msg" | jq -r '.payload.compile_results.failure // 0')
            errors=$(echo "$completed_msg" | jq -r '.payload.errors // [] | .[]' 2>/dev/null)

            # Property tester specific
            props=$(echo "$completed_msg" | jq -r '.payload.properties_defined // 0')
            gens=$(echo "$completed_msg" | jq -r '.payload.generators_created // 0')

            # Accumulate
            TOTAL_TARGETS=$((TOTAL_TARGETS + targets))
            TOTAL_COMPILE_SUCCESS=$((TOTAL_COMPILE_SUCCESS + success))
            TOTAL_COMPILE_FAILURE=$((TOTAL_COMPILE_FAILURE + failure))
            PROPERTIES_DEFINED=$((PROPERTIES_DEFINED + props))
            GENERATORS_CREATED=$((GENERATORS_CREATED + gens))

            while IFS= read -r file; do
                [ -n "$file" ] && ALL_FILES+=("$file")
            done <<< "$files"

            while IFS= read -r error; do
                [ -n "$error" ] && ALL_ERRORS+=("$error")
            done <<< "$errors"

            TEAMMATE_RESULTS+=("$teammate:$status:$targets:$success:$failure")
        else
            # Check for error message
            error_msg=$(jq -r '
                if type == "array" then
                    .[] | select(.type == "error")
                else
                    select(.type == "error")
                end
            ' "$inbox_file" 2>/dev/null || echo "{}")

            if [ -n "$error_msg" ] && [ "$error_msg" != "{}" ]; then
                error_text=$(echo "$error_msg" | jq -r '.payload.error_message // "Unknown error"')
                ALL_ERRORS+=("$teammate: $error_text")
                TEAMMATE_RESULTS+=("$teammate:failed:0:0:0")
            else
                TEAMMATE_RESULTS+=("$teammate:pending:0:0:0")
            fi
        fi
    fi
done

# --- Calculate Summary ---
TOTAL_FILES=${#ALL_FILES[@]}
TOTAL_ERRORS=${#ALL_ERRORS[@]}
COMPILE_RATE=0
if [ $((TOTAL_COMPILE_SUCCESS + TOTAL_COMPILE_FAILURE)) -gt 0 ]; then
    COMPILE_RATE=$((100 * TOTAL_COMPILE_SUCCESS / (TOTAL_COMPILE_SUCCESS + TOTAL_COMPILE_FAILURE)))
fi

# --- Output ---
output_json() {
    cat <<JSON
{
  "team": "$TEAM_NAME",
  "aggregated_at": "$(date -Iseconds)",
  "summary": {
    "total_targets": $TOTAL_TARGETS,
    "total_files_generated": $TOTAL_FILES,
    "compile_success": $TOTAL_COMPILE_SUCCESS,
    "compile_failure": $TOTAL_COMPILE_FAILURE,
    "compile_success_rate": $COMPILE_RATE,
    "properties_defined": $PROPERTIES_DEFINED,
    "generators_created": $GENERATORS_CREATED,
    "total_errors": $TOTAL_ERRORS
  },
  "generated_files": [
$(printf '    "%s"' "${ALL_FILES[0]:-}" 2>/dev/null || true)
$(for ((i=1; i<${#ALL_FILES[@]}; i++)); do printf ',\n    "%s"' "${ALL_FILES[$i]}"; done)
  ],
  "errors": [
$(printf '    "%s"' "${ALL_ERRORS[0]:-}" 2>/dev/null | sed 's/"/\\"/g' || true)
$(for ((i=1; i<${#ALL_ERRORS[@]}; i++)); do printf ',\n    "%s"' "$(echo "${ALL_ERRORS[$i]}" | sed 's/"/\\"/g')"; done)
  ],
  "teammates": [
$(first=true; for result in "${TEAMMATE_RESULTS[@]}"; do
    IFS=':' read -r name status targets success failure <<< "$result"
    $first && first=false || printf ',\n'
    printf '    {"name": "%s", "status": "%s", "targets": %s, "compile_success": %s, "compile_failure": %s}' \
        "$name" "$status" "$targets" "$success" "$failure"
done)
  ]
}
JSON
}

output_markdown() {
    cat <<MARKDOWN
# Agent Teams Results: $TEAM_NAME

**Aggregated at:** $(date -Iseconds)

## Summary

| Metric | Value |
|--------|-------|
| Total Targets | $TOTAL_TARGETS |
| Generated Files | $TOTAL_FILES |
| Compile Success | $TOTAL_COMPILE_SUCCESS |
| Compile Failure | $TOTAL_COMPILE_FAILURE |
| **Compile Rate** | **${COMPILE_RATE}%** |
| Properties Defined | $PROPERTIES_DEFINED |
| Generators Created | $GENERATORS_CREATED |
| Errors | $TOTAL_ERRORS |

## Teammate Breakdown

| Teammate | Status | Targets | Success | Failure |
|----------|--------|---------|---------|---------|
$(for result in "${TEAMMATE_RESULTS[@]}"; do
    IFS=':' read -r name status targets success failure <<< "$result"
    printf '| %s | %s | %s | %s | %s |\n' "$name" "$status" "$targets" "$success" "$failure"
done)

## Generated Files

$(for file in "${ALL_FILES[@]}"; do echo "- \`$file\`"; done)

MARKDOWN

    if [ ${#ALL_ERRORS[@]} -gt 0 ]; then
        echo "## Errors"
        echo ""
        for error in "${ALL_ERRORS[@]}"; do
            echo "- $error"
        done
    fi
}

# Output to file or stdout
if [ -n "$OUTPUT_FILE" ]; then
    case "$OUTPUT_FORMAT" in
        json) output_json > "$OUTPUT_FILE" ;;
        markdown) output_markdown > "$OUTPUT_FILE" ;;
    esac
    echo "Results written to: $OUTPUT_FILE" >&2
else
    case "$OUTPUT_FORMAT" in
        json) output_json ;;
        markdown) output_markdown ;;
    esac
fi
