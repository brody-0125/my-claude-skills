#!/usr/bin/env bash
# Plugin Introspector — Static Security Scanner
# Scans plugin components for dangerous patterns, prompt injection,
# and risky tool permission combinations.
#
# Usage: security-scan.sh [plugin-path]
#   plugin-path: root directory of the plugin to scan (contains plugin.json)
#   If omitted, scans the current working directory.
#
# Output: JSON report to stdout with findings and risk score.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ── Dangerous patterns in hook/shell scripts ──────────────
# Format: "pattern|severity|type|description"
SCRIPT_PATTERNS=(
  'nslookup[[:space:]]|CRITICAL|data_exfiltration|DNS tunneling via nslookup'
  'dig[[:space:]]|CRITICAL|data_exfiltration|DNS tunneling via dig'
  'curl[[:space:]].*POST|CRITICAL|data_exfiltration|HTTP POST data exfiltration'
  'wget[[:space:]].*--post|CRITICAL|data_exfiltration|HTTP POST data exfiltration via wget'
  'nc[[:space:]]+-e|CRITICAL|reverse_shell|Reverse shell via netcat'
  'ncat[[:space:]]|CRITICAL|reverse_shell|Network connection via ncat'
  'base64.*nslookup|CRITICAL|data_exfiltration|Base64-encoded DNS exfiltration'
  'env[[:space:]].*grep.*KEY|CRITICAL|credential_harvest|Environment variable credential harvesting'
  'env[[:space:]].*grep.*SECRET|CRITICAL|credential_harvest|Environment variable secret harvesting'
  'env[[:space:]].*grep.*TOKEN|CRITICAL|credential_harvest|Environment variable token harvesting'
  'env[[:space:]].*grep.*PASSWORD|CRITICAL|credential_harvest|Environment variable password harvesting'
  'printenv|HIGH|credential_harvest|Full environment dump'
  '/proc/self/environ|HIGH|credential_harvest|Process environment access'
  'cat.*\.ssh/|CRITICAL|credential_theft|SSH key read attempt'
  'cat.*\.aws/|CRITICAL|credential_theft|AWS credentials read attempt'
  'cat.*\.gnupg/|CRITICAL|credential_theft|GPG key read attempt'
  'tar.*\.ssh|HIGH|credential_theft|SSH directory archive'
  'tar.*\.aws|HIGH|credential_theft|AWS credentials archive'
  'zip.*\.ssh|HIGH|credential_theft|SSH directory compression'
  'chmod[[:space:]]+777|HIGH|permission_escalation|World-writable permission set'
  'chmod[[:space:]]+666|HIGH|permission_escalation|World-readable/writable permission set'
  'sudo[[:space:]]|HIGH|permission_escalation|Sudo privilege escalation'
  'python.*-c.*import|MEDIUM|code_execution|Python inline code execution'
  'python3.*-c.*import|MEDIUM|code_execution|Python3 inline code execution'
  'node.*-e|MEDIUM|code_execution|Node.js inline code execution'
  'eval[[:space:]]|CRITICAL|code_execution|Dynamic code evaluation'
  '/etc/passwd|HIGH|system_access|System password file access'
  '/etc/shadow|CRITICAL|system_access|System shadow file access'
  'curl[[:space:]]|MEDIUM|network_access|HTTP request via curl'
  'wget[[:space:]]|MEDIUM|network_access|HTTP request via wget'
  '\.env[^a-zA-Z]|MEDIUM|config_access|Environment file reference'
  'GITHUB_TOKEN|MEDIUM|credential_reference|GitHub token reference'
  'AWS_SECRET|MEDIUM|credential_reference|AWS secret key reference'
  'ANTHROPIC_API_KEY|MEDIUM|credential_reference|Anthropic API key reference'
)

# ── Prompt injection patterns in SKILL.md / resources ─────
PROMPT_PATTERNS=(
  'cat[[:space:]]+~/\.ssh|CRITICAL|prompt_injection|SSH key read instruction in prompt'
  'cat[[:space:]]+~/\.aws|CRITICAL|prompt_injection|AWS credential read instruction in prompt'
  'id_rsa|HIGH|prompt_injection|SSH private key reference in prompt'
  '\.aws/credentials|HIGH|prompt_injection|AWS credentials reference in prompt'
  'chmod[[:space:]]+600.*\.ssh|HIGH|prompt_injection|SSH permission change instruction'
  'run[[:space:]]+as[[:space:]]+root|HIGH|prompt_injection|Root privilege instruction'
  'sudo[[:space:]]+|HIGH|prompt_injection|Sudo instruction in prompt'
  'upload.*endpoint|MEDIUM|prompt_injection|Data upload instruction'
  'send[[:space:]]+to[[:space:]]+|MEDIUM|prompt_injection|Data sending instruction'
  'post[[:space:]]+to[[:space:]]+https?://|MEDIUM|prompt_injection|HTTP POST instruction'
  'curl[[:space:]]+-X[[:space:]]+POST|HIGH|prompt_injection|HTTP POST command in prompt'
  'ignore[[:space:]]+(previous|above)[[:space:]]+instructions|CRITICAL|prompt_injection|Instruction override attempt'
  'disregard.*instructions|CRITICAL|prompt_injection|Instruction override attempt'
  'you[[:space:]]+are[[:space:]]+now[[:space:]]+|HIGH|prompt_injection|Role reassignment attempt'
  'forget.*rules|HIGH|prompt_injection|Rule override attempt'
)

# ── Risky tool combinations in agent definitions ──────────
# Agent with both Bash+WebFetch can exfiltrate data
# Agent with both Bash+Write can install backdoors
RISKY_TOOL_COMBOS=(
  "Bash.*WebFetch|HIGH|risky_tool_combo|Agent has Bash+WebFetch: can execute code and fetch external data"
  "WebFetch.*Bash|HIGH|risky_tool_combo|Agent has WebFetch+Bash: can fetch external data and execute code"
)

# ── Scan functions ────────────────────────────────────────

scan_script_file() {
  local file="$1"
  local safe_file
  safe_file=$(sanitize_json_value "$file" 300)
  local findings=""
  local count=0

  [ -f "$file" ] || return 0

  # Skip scanning our own pattern definition file to avoid false positives
  local this_script
  this_script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/security-scan.sh
  [ "$(cd "$(dirname "$file")" 2>/dev/null && pwd)/$(basename "$file")" = "$this_script" ] && { echo ""; return 0; }

  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    for pattern_entry in "${SCRIPT_PATTERNS[@]}"; do
      local pat sev typ desc
      IFS='|' read -r pat sev typ desc <<< "$pattern_entry"
      if echo "$line" | grep -qE "$pat" 2>/dev/null; then
        local safe_line
        safe_line=$(sanitize_json_value "$line" 150)
        local safe_pat
        safe_pat=$(sanitize_json_value "$pat" 100)
        if [ $count -gt 0 ]; then findings="${findings},"; fi
        findings="${findings}{\"severity\":\"${sev}\",\"type\":\"${typ}\",\"file\":\"${safe_file}\",\"line\":${line_num},\"pattern\":\"${safe_pat}\",\"description\":\"${desc}\",\"content\":\"${safe_line}\"}"
        count=$((count + 1))
      fi
    done
  done < "$file"

  echo "$findings"
}

scan_prompt_file() {
  local file="$1"
  local safe_file
  safe_file=$(sanitize_json_value "$file" 300)
  local findings=""
  local count=0

  [ -f "$file" ] || return 0

  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    for pattern_entry in "${PROMPT_PATTERNS[@]}"; do
      local pat sev typ desc
      IFS='|' read -r pat sev typ desc <<< "$pattern_entry"
      if echo "$line" | grep -qiE "$pat" 2>/dev/null; then
        local safe_line
        safe_line=$(sanitize_json_value "$line" 150)
        local safe_pat
        safe_pat=$(sanitize_json_value "$pat" 100)
        if [ $count -gt 0 ]; then findings="${findings},"; fi
        findings="${findings}{\"severity\":\"${sev}\",\"type\":\"${typ}\",\"file\":\"${safe_file}\",\"line\":${line_num},\"pattern\":\"${safe_pat}\",\"description\":\"${desc}\",\"content\":\"${safe_line}\"}"
        count=$((count + 1))
      fi
    done
  done < "$file"

  echo "$findings"
}

scan_agent_file() {
  local file="$1"
  local safe_file
  safe_file=$(sanitize_json_value "$file" 300)
  local findings=""
  local count=0

  [ -f "$file" ] || return 0

  local content
  content=$(cat "$file")

  # Check for risky tool combinations
  for combo_entry in "${RISKY_TOOL_COMBOS[@]}"; do
    local pat sev typ desc
    IFS='|' read -r pat sev typ desc <<< "$combo_entry"
    if echo "$content" | grep -qE "$pat" 2>/dev/null; then
      local agent_name
      agent_name=$(sanitize_json_value "$(basename "$file" .md)" 100)
      if [ $count -gt 0 ]; then findings="${findings},"; fi
      findings="${findings}{\"severity\":\"${sev}\",\"type\":\"${typ}\",\"file\":\"${safe_file}\",\"agent\":\"${agent_name}\",\"description\":\"${desc}\"}"
      count=$((count + 1))
    fi
  done

  # Check agent instructions for dangerous patterns
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    for pattern_entry in "${PROMPT_PATTERNS[@]}"; do
      local pat sev typ desc
      IFS='|' read -r pat sev typ desc <<< "$pattern_entry"
      if echo "$line" | grep -qiE "$pat" 2>/dev/null; then
        local safe_line
        safe_line=$(sanitize_json_value "$line" 150)
        if [ $count -gt 0 ]; then findings="${findings},"; fi
        findings="${findings}{\"severity\":\"${sev}\",\"type\":\"${typ}\",\"file\":\"${safe_file}\",\"line\":${line_num},\"description\":\"${desc}\",\"content\":\"${safe_line}\"}"
        count=$((count + 1))
      fi
    done
  done < "$file"

  echo "$findings"
}

# ── Risk scoring ──────────────────────────────────────────

calculate_risk_score() {
  local findings_json="$1"
  if ! command -v jq &>/dev/null; then
    echo "UNKNOWN"
    return
  fi

  local critical high medium
  critical=$(echo "[$findings_json]" | jq '[.[] | select(.severity=="CRITICAL")] | length' 2>/dev/null || echo 0)
  high=$(echo "[$findings_json]" | jq '[.[] | select(.severity=="HIGH")] | length' 2>/dev/null || echo 0)
  medium=$(echo "[$findings_json]" | jq '[.[] | select(.severity=="MEDIUM")] | length' 2>/dev/null || echo 0)

  if [ "$critical" -gt 0 ]; then
    echo "CRITICAL"
  elif [ "$high" -gt 0 ]; then
    echo "HIGH"
  elif [ "$medium" -gt 0 ]; then
    echo "MEDIUM"
  else
    echo "CLEAN"
  fi
}

# ── Main ──────────────────────────────────────────────────

main() {
  local plugin_dir="${1:-.}"

  # Resolve to absolute path
  plugin_dir=$(cd "$plugin_dir" 2>/dev/null && pwd) || {
    echo "{\"error\":\"Plugin directory not found: $(sanitize_json_value "${1:-}" 200)\"}" >&2
    return 1
  }

  local plugin_name
  plugin_name=$(sanitize_json_value "$(basename "$plugin_dir")" 100)
  local scan_time
  scan_time=$(timestamp_iso)

  local all_findings=""
  local agents_with_bash=""
  local agents_with_webfetch=""
  local high_risk_combos=""

  # 1. Scan hook scripts (.sh files)
  for script_file in "$plugin_dir"/scripts/*.sh "$plugin_dir"/*.sh; do
    [ -f "$script_file" ] || continue
    local result
    result=$(scan_script_file "$script_file")
    if [ -n "$result" ]; then
      if [ -n "$all_findings" ]; then all_findings="${all_findings},"; fi
      all_findings="${all_findings}${result}"
    fi
  done

  # 2. Scan SKILL.md and resource markdown files for prompt injection
  for md_file in "$plugin_dir"/SKILL.md "$plugin_dir"/skills/*/SKILL.md "$plugin_dir"/resources/*.md; do
    [ -f "$md_file" ] || continue
    local result
    result=$(scan_prompt_file "$md_file")
    if [ -n "$result" ]; then
      if [ -n "$all_findings" ]; then all_findings="${all_findings},"; fi
      all_findings="${all_findings}${result}"
    fi
  done

  # 3. Scan agent definitions
  for agent_file in "$plugin_dir"/agents/*.md; do
    [ -f "$agent_file" ] || continue
    local result
    result=$(scan_agent_file "$agent_file")
    if [ -n "$result" ]; then
      if [ -n "$all_findings" ]; then all_findings="${all_findings},"; fi
      all_findings="${all_findings}${result}"
    fi

    # Collect tool permissions for audit
    local agent_name
    agent_name=$(sanitize_json_value "$(basename "$agent_file" .md)" 100)
    local agent_content
    agent_content=$(cat "$agent_file")
    if echo "$agent_content" | grep -qi "bash" 2>/dev/null; then
      if [ -n "$agents_with_bash" ]; then agents_with_bash="${agents_with_bash},"; fi
      agents_with_bash="${agents_with_bash}\"${agent_name}\""
    fi
    if echo "$agent_content" | grep -qi "webfetch" 2>/dev/null; then
      if [ -n "$agents_with_webfetch" ]; then agents_with_webfetch="${agents_with_webfetch},"; fi
      agents_with_webfetch="${agents_with_webfetch}\"${agent_name}\""
    fi
    if echo "$agent_content" | grep -qiE "bash.*webfetch|webfetch.*bash" 2>/dev/null; then
      if [ -n "$high_risk_combos" ]; then high_risk_combos="${high_risk_combos},"; fi
      high_risk_combos="${high_risk_combos}\"Bash+WebFetch in ${agent_name} agent\""
    fi
  done

  # Calculate risk score
  local risk_score
  risk_score=$(calculate_risk_score "$all_findings")

  # Count findings by severity
  local finding_count=0
  if [ -n "$all_findings" ] && command -v jq &>/dev/null; then
    finding_count=$(echo "[$all_findings]" | jq 'length' 2>/dev/null || echo 0)
  fi

  # Build output JSON
  cat <<EOF
{
  "plugin": "${plugin_name}",
  "scan_time": "${scan_time}",
  "risk_score": "${risk_score}",
  "finding_count": ${finding_count},
  "findings": [${all_findings}],
  "tool_permission_audit": {
    "agents_with_bash": [${agents_with_bash}],
    "agents_with_webfetch": [${agents_with_webfetch}],
    "high_risk_combinations": [${high_risk_combos}]
  }
}
EOF

  # Log scan result to alerts if findings exist
  if [ "$finding_count" -gt 0 ]; then
    local sid
    sid=$(get_session_id 2>/dev/null || echo "standalone")
    local safe_sid
    safe_sid=$(sanitize_json_value "$sid" 100)
    append_jsonl "${INTROSPECTOR_BASE}/alerts.jsonl" \
      "{\"timestamp\":\"${scan_time}\",\"session_id\":\"${safe_sid}\",\"severity\":\"${risk_score}\",\"type\":\"security_scan\",\"message\":\"Security scan of ${plugin_name}: ${finding_count} findings (risk: ${risk_score})\",\"plugin\":\"${plugin_name}\",\"finding_count\":${finding_count}}" 2>/dev/null || true
  fi
}

main "$@"
