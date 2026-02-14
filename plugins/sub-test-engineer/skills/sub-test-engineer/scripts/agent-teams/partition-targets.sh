#!/usr/bin/env bash
# partition-targets.sh — Partition test targets for Agent Teams parallel processing
# Part of sub-test-engineer M4 Agent Teams Integration
#
# Usage:
#   partition-targets.sh <strategy-document> [--by-technique | --by-module] [--json]
#
# Arguments:
#   strategy-document : Path to strategy document (Phase 2 output)
#   --by-technique    : Partition by testing technique (default)
#   --by-module       : Partition by module (for multi-module projects)
#   --json            : Output as JSON
#
# Output:
#   Partitioned targets assigned to each Teammate type

set -euo pipefail

# --- Argument Parsing ---
STRATEGY_DOC=""
PARTITION_MODE="technique"
JSON_OUTPUT=false

for arg in "$@"; do
    case "$arg" in
        --by-technique) PARTITION_MODE="technique" ;;
        --by-module) PARTITION_MODE="module" ;;
        --json) JSON_OUTPUT=true ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) [ -z "$STRATEGY_DOC" ] && STRATEGY_DOC="$arg" ;;
    esac
done

if [ -z "$STRATEGY_DOC" ]; then
    cat <<USAGE
Usage: partition-targets.sh <strategy-document> [--by-technique | --by-module] [--json]

Arguments:
  strategy-document : Path to strategy document (Phase 2 output)
  --by-technique    : Partition by testing technique (default)
  --by-module       : Partition by module (for multi-module projects)
  --json            : Output as JSON

Example:
  partition-targets.sh ./strategy.md --by-technique --json
USAGE
    exit 1
fi

if [ ! -f "$STRATEGY_DOC" ]; then
    echo "ERROR: Strategy document not found: $STRATEGY_DOC" >&2
    exit 1
fi

# --- Technique Keywords ---
# Maps technique keywords to Teammate types
declare -A TECHNIQUE_TO_TEAMMATE=(
    # Unit tester
    ["unit test"]="unit-tester"
    ["unit-test"]="unit-tester"
    ["mock-based"]="unit-tester"
    ["bdd unit"]="unit-tester"
    ["mockk"]="unit-tester"
    ["mockito"]="unit-tester"
    ["jest.mock"]="unit-tester"

    # Integration tester
    ["integration test"]="integration-tester"
    ["integration-test"]="integration-tester"
    ["repository test"]="integration-tester"
    ["testcontainers"]="integration-tester"
    ["contract test"]="integration-tester"
    ["contract-test"]="integration-tester"
    ["pact"]="integration-tester"
    ["wiremock"]="integration-tester"
    ["@springboottest"]="integration-tester"
    ["@datajpatest"]="integration-tester"

    # Property tester
    ["property-based"]="property-tester"
    ["property test"]="property-tester"
    ["pbt"]="property-tester"
    ["kotest property"]="property-tester"
    ["jqwik"]="property-tester"
    ["fast-check"]="property-tester"
    ["quickcheck"]="property-tester"
    ["hypothesis"]="property-tester"
)

# --- Parse Strategy Document ---
# Expected format in strategy document:
#   | Target | Technique | Priority |
#   |--------|-----------|----------|
#   | OrderService | Unit Test (MockK) | HIGH |
#   | PaymentValidator | Property-Based (Kotest) | HIGH |

parse_strategy_table() {
    local doc="$1"

    # Find the technique allocation table
    # Skip header rows, extract Target and Technique columns
    awk '
    BEGIN { in_table = 0; header_seen = 0 }
    /^\|.*Target.*Technique/ { in_table = 1; header_seen = 0; next }
    /^\|[-:]+\|/ { if (in_table) header_seen = 1; next }
    /^\|/ && in_table && header_seen {
        gsub(/^\|[ \t]*/, "")
        gsub(/[ \t]*\|[ \t]*$/, "")
        n = split($0, cols, /[ \t]*\|[ \t]*/)
        if (n >= 2) {
            target = cols[1]
            technique = cols[2]
            gsub(/^[ \t]+|[ \t]+$/, "", target)
            gsub(/^[ \t]+|[ \t]+$/, "", technique)
            if (target != "" && technique != "") {
                print target "\t" technique
            }
        }
    }
    /^[^|]/ { in_table = 0 }
    ' "$doc"
}

# Determine teammate for a technique string
get_teammate_for_technique() {
    local technique="$1"
    local technique_lower=$(echo "$technique" | tr '[:upper:]' '[:lower:]')

    for pattern in "${!TECHNIQUE_TO_TEAMMATE[@]}"; do
        if [[ "$technique_lower" == *"$pattern"* ]]; then
            echo "${TECHNIQUE_TO_TEAMMATE[$pattern]}"
            return
        fi
    done

    # Default to unit-tester
    echo "unit-tester"
}

# --- Partition by Technique ---
partition_by_technique() {
    declare -a unit_targets=()
    declare -a integration_targets=()
    declare -a property_targets=()

    while IFS=$'\t' read -r target technique; do
        teammate=$(get_teammate_for_technique "$technique")
        case "$teammate" in
            unit-tester) unit_targets+=("$target") ;;
            integration-tester) integration_targets+=("$target") ;;
            property-tester) property_targets+=("$target") ;;
        esac
    done < <(parse_strategy_table "$STRATEGY_DOC")

    if $JSON_OUTPUT; then
        echo "{"
        echo "  \"partition_mode\": \"technique\","
        echo "  \"teammates\": {"

        # Unit tester
        echo "    \"unit-tester\": {"
        echo "      \"target_count\": ${#unit_targets[@]},"
        echo -n "      \"targets\": ["
        first=true
        for t in "${unit_targets[@]}"; do
            $first && first=false || echo -n ", "
            echo -n "\"$t\""
        done
        echo "]"
        echo "    },"

        # Integration tester
        echo "    \"integration-tester\": {"
        echo "      \"target_count\": ${#integration_targets[@]},"
        echo -n "      \"targets\": ["
        first=true
        for t in "${integration_targets[@]}"; do
            $first && first=false || echo -n ", "
            echo -n "\"$t\""
        done
        echo "]"
        echo "    },"

        # Property tester
        echo "    \"property-tester\": {"
        echo "      \"target_count\": ${#property_targets[@]},"
        echo -n "      \"targets\": ["
        first=true
        for t in "${property_targets[@]}"; do
            $first && first=false || echo -n ", "
            echo -n "\"$t\""
        done
        echo "]"
        echo "    }"

        echo "  },"
        echo "  \"total_targets\": $((${#unit_targets[@]} + ${#integration_targets[@]} + ${#property_targets[@]}))"
        echo "}"
    else
        echo "Partition by Technique"
        echo "======================"
        echo ""
        echo "unit-tester (${#unit_targets[@]} targets):"
        for t in "${unit_targets[@]}"; do echo "  - $t"; done
        echo ""
        echo "integration-tester (${#integration_targets[@]} targets):"
        for t in "${integration_targets[@]}"; do echo "  - $t"; done
        echo ""
        echo "property-tester (${#property_targets[@]} targets):"
        for t in "${property_targets[@]}"; do echo "  - $t"; done
        echo ""
        echo "Total: $((${#unit_targets[@]} + ${#integration_targets[@]} + ${#property_targets[@]})) targets"
    fi
}

# --- Partition by Module ---
partition_by_module() {
    # For module-based partitioning, we need module detection
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT=$(dirname "$(dirname "$(dirname "$STRATEGY_DOC")")")

    # Get module list
    modules_json=$("$SCRIPT_DIR/detect-modules.sh" "$PROJECT_ROOT" --json 2>/dev/null || echo '{"modules":[]}')

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq required for module-based partitioning" >&2
        exit 1
    fi

    module_count=$(echo "$modules_json" | jq '.module_count // 0')

    if [ "$module_count" -eq 0 ]; then
        echo "No modules detected. Falling back to technique-based partitioning." >&2
        partition_by_technique
        return
    fi

    # Parse targets and assign to modules based on path
    declare -A module_targets

    while IFS=$'\t' read -r target technique; do
        # Try to determine module from target path
        # Assume target might include package path like "com.example.order.OrderService"
        assigned_module=""

        for module in $(echo "$modules_json" | jq -r '.modules[].path'); do
            module_name=$(basename "$module")
            if [[ "$target" == *"$module_name"* ]] || [[ "$target" == *"$(echo "$module" | tr '/' '.')"* ]]; then
                assigned_module="$module"
                break
            fi
        done

        if [ -z "$assigned_module" ]; then
            assigned_module="root"
        fi

        module_targets["$assigned_module"]+="$target,"
    done < <(parse_strategy_table "$STRATEGY_DOC")

    if $JSON_OUTPUT; then
        echo "{"
        echo "  \"partition_mode\": \"module\","
        echo "  \"teammates\": {"

        first=true
        for module in "${!module_targets[@]}"; do
            $first && first=false || echo ","
            targets="${module_targets[$module]}"
            targets="${targets%,}"  # Remove trailing comma

            target_array=$(echo "$targets" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -s .)
            target_count=$(echo "$target_array" | jq 'length')

            echo "    \"module-$(basename "$module")\": {"
            echo "      \"module_path\": \"$module\","
            echo "      \"target_count\": $target_count,"
            echo "      \"targets\": $target_array"
            echo -n "    }"
        done

        echo ""
        echo "  },"
        echo "  \"total_modules\": ${#module_targets[@]}"
        echo "}"
    else
        echo "Partition by Module"
        echo "==================="
        echo ""
        for module in "${!module_targets[@]}"; do
            targets="${module_targets[$module]}"
            targets="${targets%,}"
            count=$(echo "$targets" | tr ',' '\n' | grep -v '^$' | wc -l | tr -d ' ')
            echo "module-$(basename "$module") ($count targets):"
            echo "$targets" | tr ',' '\n' | grep -v '^$' | while read -r t; do
                echo "  - $t"
            done
            echo ""
        done
    fi
}

# --- Main ---
case "$PARTITION_MODE" in
    technique) partition_by_technique ;;
    module) partition_by_module ;;
esac
