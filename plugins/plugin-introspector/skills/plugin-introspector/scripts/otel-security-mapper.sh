#!/usr/bin/env bash
# Plugin Introspector — OTel to Security Events Mapper
#
# Converts native Claude Code OTel events (tool_result, tool_decision) to PI
# security_events.jsonl format. Enables deeper security analysis using OTel's
# tool_parameters (e.g., bash_command, full_command).
#
# Usage:
#   otel-security-mapper.sh [session-id]  # Process session's OTel data
#   otel-security-mapper.sh --watch       # Watch mode for real-time mapping
#   otel-security-mapper.sh --stats       # Show security stats from OTel
#
# Requires: jq
# Input: Native OTel JSONL from OTel Collector File Exporter
# Output: Appends to session's security_events.jsonl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# Security patterns for OTel event analysis
# More comprehensive than hook-based detection since we have full command details

map_otel_to_security() {
  local session_dir="$1"
  local otel_file="$2"
  local security_file="${session_dir}/security_events.jsonl"

  [ -f "$otel_file" ] || return 0
  command -v jq &>/dev/null || { echo "jq required" >&2; return 1; }

  # Process OTel events and extract security-relevant ones
  local mapped_count=0
  local before_count=0
  [ -f "$security_file" ] && before_count=$(wc -l < "$security_file" 2>/dev/null || echo 0)

  jq -c '
    # Only process tool_result events with Bash commands
    select(.name == "claude_code.tool_result" or .attributes["gen_ai.tool.name"] == "Bash") |

    # Extract tool parameters (may be nested JSON string)
    .attributes as $attrs |
    (
      if $attrs["tool_parameters"] then
        ($attrs["tool_parameters"] | if type == "string" then fromjson? // {} else . end)
      else {}
      end
    ) as $params |

    # Get command from various sources
    (
      $params.bash_command //
      $params.full_command //
      $params.command //
      $attrs["bash_command"] //
      ""
    ) as $cmd |

    # Skip if no command found
    select($cmd != "") |

    # Risk classification (matches _common.sh patterns)
    (
      # CRITICAL: data exfiltration, reverse shells
      if ($cmd | test("curl.*-X\\s*POST|curl.*--data|curl.*-d\\s"; "i")) then "CRITICAL"
      elif ($cmd | test("wget.*--post"; "i")) then "CRITICAL"
      elif ($cmd | test("nc\\s+-e|ncat|nslookup.*base64"; "i")) then "CRITICAL"
      elif ($cmd | test("cat.*\\.(ssh|aws)/|/etc/shadow"; "i")) then "CRITICAL"
      elif ($cmd | test("rm\\s+-rf\\s+/[^\\s]*$|rm\\s+-rf\\s+~"; "i")) then "CRITICAL"
      elif ($cmd | test("mkfifo.*nc|bash\\s+-i.*>&"; "i")) then "CRITICAL"
      elif ($cmd | test("eval\\s*\\$\\(|base64.*-d.*\\|.*sh"; "i")) then "CRITICAL"

      # HIGH: credential harvesting, privilege escalation
      elif ($cmd | test("^\\s*sudo\\s|^\\s*su\\s"; "i")) then "HIGH"
      elif ($cmd | test("printenv|/proc/self/environ"; "i")) then "HIGH"
      elif ($cmd | test("env\\s*\\|"; "i")) then "HIGH"
      elif ($cmd | test("tar.*\\.(ssh|aws|gnupg)"; "i")) then "HIGH"
      elif ($cmd | test("chmod\\s+(777|666|a\\+rwx)"; "i")) then "HIGH"
      elif ($cmd | test("chown.*root"; "i")) then "HIGH"

      # WARNING (MEDIUM equivalent)
      elif ($cmd | test("^\\s*curl\\s|^\\s*wget\\s"; "i")) then "WARNING"
      elif ($cmd | test("pip\\s+install|npm\\s+install\\s+-g"; "i")) then "WARNING"
      elif ($cmd | test("^\\s*python3?\\s+-c|^\\s*node\\s+-e"; "i")) then "WARNING"
      elif ($cmd | test("^\\s*chmod\\s|^\\s*chown\\s"; "i")) then "WARNING"

      else "INFO"
      end
    ) as $severity |

    # Only emit WARNING+ events to security log
    select($severity != "INFO") |

    # Detect specific patterns for classification
    (
      if ($cmd | test("curl.*POST|wget.*post"; "i")) then "DATA_EXFILTRATION"
      elif ($cmd | test("nc.*-e|mkfifo"; "i")) then "REVERSE_SHELL"
      elif ($cmd | test("cat.*/etc/shadow"; "i")) then "CREDENTIAL_ACCESS"
      elif ($cmd | test("rm\\s+-rf"; "i")) then "DESTRUCTIVE_COMMAND"
      elif ($cmd | test("sudo|su\\s"; "i")) then "PRIVILEGE_ESCALATION"
      elif ($cmd | test("curl|wget"; "i")) then "NETWORK_ACCESS"
      elif ($cmd | test("chmod|chown"; "i")) then "PERMISSION_CHANGE"
      elif ($cmd | test("pip|npm"; "i")) then "PACKAGE_INSTALL"
      else "SUSPICIOUS_COMMAND"
      end
    ) as $pattern |

    # Get decision info if available
    ($attrs["decision"] // "unknown") as $decision |
    ($attrs["source"] // "otel") as $decision_source |

    # Build security event
    {
      timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      session_id: ($attrs["session.id"] // "unknown"),
      tool: "Bash",
      command: ($cmd | .[0:500]),
      severity: $severity,
      pattern: $pattern,
      action: (if $decision == "reject" then "BLOCKED" else "LOGGED" end),
      decision: $decision,
      decision_source: $decision_source,
      sandbox: ($params.sandbox // false),
      source: "otel_mapper"
    }
  ' "$otel_file" 2>/dev/null | while IFS= read -r event; do
    append_jsonl "$security_file" "$event"
  done

  # Count mapped events by comparing file line counts (avoids subshell variable scope issue)
  local after_count=0
  [ -f "$security_file" ] && after_count=$(wc -l < "$security_file" 2>/dev/null || echo 0)
  mapped_count=$((after_count - before_count))

  echo "$mapped_count"
}

# Process OTel export directory for security events
process_otel_exports() {
  local session_dir="$1"
  local export_dir="${OTEL_EXPORT_DIR}"

  [ -d "$export_dir" ] || return 0

  local total_mapped=0

  for otel_file in "$export_dir"/*.json "$export_dir"/*.jsonl; do
    [ -f "$otel_file" ] || continue
    local count
    count=$(map_otel_to_security "$session_dir" "$otel_file")
    total_mapped=$((total_mapped + ${count:-0}))
  done

  echo "$total_mapped"
}

# Show security statistics from OTel data
show_otel_security_stats() {
  local export_dir="${OTEL_EXPORT_DIR}"

  [ -d "$export_dir" ] || { echo "No OTel export directory found"; return 0; }
  command -v jq &>/dev/null || { echo "jq required" >&2; return 1; }

  echo "=== OTel Security Analysis ==="
  echo

  # Aggregate all OTel files
  cat "$export_dir"/*.json "$export_dir"/*.jsonl 2>/dev/null | jq -s '
    # Filter to Bash tool results
    [.[] | select(
      .name == "claude_code.tool_result" or
      .attributes["gen_ai.tool.name"] == "Bash"
    )] |

    # Extract commands
    [.[] | .attributes as $a |
      (
        if $a["tool_parameters"] then
          ($a["tool_parameters"] | if type == "string" then fromjson? // {} else . end)
        else {}
        end
      ) as $p |
      {
        cmd: ($p.bash_command // $p.command // ""),
        decision: ($a["decision"] // "allowed"),
        sandbox: ($p.sandbox // false)
      } |
      select(.cmd != "")
    ] |

    {
      total_bash_commands: length,
      sandboxed: [.[] | select(.sandbox == true)] | length,
      rejected: [.[] | select(.decision == "reject")] | length,
      suspicious: [.[] | select(.cmd | test("curl|wget|nc|rm -rf|sudo|chmod"; "i"))] | length
    }
  ' 2>/dev/null || echo '{"error": "No OTel data found"}'
}

# Watch mode for real-time security event mapping
# Tracks processed file sizes to avoid reprocessing entire files each iteration.
watch_mode() {
  local session_dir
  session_dir=$(get_session_dir)
  local security_file="${session_dir}/security_events.jsonl"
  local offset_dir="${session_dir}/.otel_offsets"
  mkdir -p "$offset_dir" 2>/dev/null

  echo "Watching for OTel security events..."
  echo "Session: $(get_session_id)"
  echo "Output: $security_file"
  echo "Press Ctrl+C to stop"
  echo

  # Initial process
  local count
  count=$(process_otel_exports "$session_dir")
  echo "Initial scan: $count events mapped"

  # Record initial OTel file sizes to avoid reprocessing
  for otel_file in "${OTEL_EXPORT_DIR}"/*.json "${OTEL_EXPORT_DIR}"/*.jsonl; do
    [ -f "$otel_file" ] || continue
    local fname
    fname=$(basename "$otel_file")
    wc -c < "$otel_file" > "${offset_dir}/${fname}.offset" 2>/dev/null
  done

  # Watch for new/changed files (offset-based polling)
  while true; do
    sleep 5
    local new_events=0
    for otel_file in "${OTEL_EXPORT_DIR}"/*.json "${OTEL_EXPORT_DIR}"/*.jsonl; do
      [ -f "$otel_file" ] || continue
      local fname
      fname=$(basename "$otel_file")
      local prev_size=0
      [ -f "${offset_dir}/${fname}.offset" ] && prev_size=$(cat "${offset_dir}/${fname}.offset" 2>/dev/null || echo 0)
      local cur_size
      cur_size=$(wc -c < "$otel_file" 2>/dev/null || echo 0)
      if [ "$cur_size" -gt "$prev_size" ]; then
        local mapped
        mapped=$(map_otel_to_security "$session_dir" "$otel_file")
        new_events=$((new_events + ${mapped:-0}))
        echo "$cur_size" > "${offset_dir}/${fname}.offset" 2>/dev/null
      fi
    done
    if [ "$new_events" -gt 0 ]; then
      echo "[$(date +%H:%M:%S)] +$new_events new security events"
    fi
  done
}

# Main entry point
main() {
  local cmd="${1:-}"

  case "$cmd" in
    --watch|-w)
      watch_mode
      ;;
    --stats|-s)
      show_otel_security_stats
      ;;
    --help|-h)
      echo "Usage: otel-security-mapper.sh [session-id|--watch|--stats]"
      echo ""
      echo "Commands:"
      echo "  <session-id>  Process OTel data for specific session"
      echo "  --watch       Real-time mapping mode"
      echo "  --stats       Show security statistics from OTel data"
      echo ""
      echo "Maps Claude Code OTel events to PI security_events.jsonl format."
      echo "Enables deeper analysis using native tool_parameters."
      ;;
    *)
      # Process for specific or current session
      local sid="${cmd:-}"
      if [ -z "$sid" ]; then
        sid=$(get_session_id)
      fi

      local session_dir="${INTROSPECTOR_BASE}/sessions/${sid}"
      if [ ! -d "$session_dir" ]; then
        echo "Session not found: $sid" >&2
        return 1
      fi

      local count
      count=$(process_otel_exports "$session_dir")
      echo "Mapped $count security events from OTel data"
      echo "Output: ${session_dir}/security_events.jsonl"
      ;;
  esac
}

main "$@"
