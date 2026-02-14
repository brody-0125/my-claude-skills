#!/usr/bin/env bash
# Plugin Introspector — Shared utilities for hook scripts
# All functions used by multiple hook scripts are defined here.
#
# Function prefix conventions:
#   get_*       — Pure getters, no I/O side effects
#   read_*      — Read from file/disk
#   write_*     — Write to file/disk
#   detect_*    — Classify or detect a condition, returns a value
#   record_*    — Append structured data to storage
#   extract_*   — Parse and return a subset of input
#
# Variable quoting: always use "${var}" (defensive quoting)

set -euo pipefail

# Base data directory
INTROSPECTOR_BASE="${HOME}/.claude/plugin-introspector"

# OTel Collector File Exporter output directory
OTEL_EXPORT_DIR="${INTROSPECTOR_BASE}/otel-export"

# ── Session helpers ──────────────────────────────────────

# Get or generate session ID
get_session_id() {
  if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    echo "${CLAUDE_SESSION_ID}"
  else
    echo "session-$(date +%Y%m%d-%H%M%S)"
  fi
}

# Get session directory, creating if needed
# Checks cached session first for faster resolution (~10ms savings/hook)
get_session_dir() {
  local cache_file="${INTROSPECTOR_BASE}/.current_session"
  if [ -f "$cache_file" ]; then
    local cached_dir
    cached_dir=$(cat "${cache_file}")
    if [ -d "${cached_dir}" ]; then
      echo "${cached_dir}"
      return
    fi
  fi
  # Fallback: compute from session ID
  local sid
  sid=$(get_session_id)
  local dir="${INTROSPECTOR_BASE}/sessions/${sid}"
  mkdir -p "${dir}"
  echo "${dir}"
}

# ── ID / timestamp helpers ───────────────────────────────

# Generate a unique trace/span ID (16 hex chars)
generate_id() {
  head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 16 \
    || printf '%08x%08x' "$$" "${RANDOM:-0}$(date +%s)"
}

# Current timestamp in ISO 8601
timestamp_iso() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null)
  case "$ts" in
    *%*) date -u +"%Y-%m-%dT%H:%M:%SZ" ;;
    *)   echo "$ts" ;;
  esac
}

# Current timestamp in epoch milliseconds
timestamp_ms() {
  local ms
  ms=$(date +%s%3N 2>/dev/null)
  case "$ms" in
    *[!0-9]*) echo "$(($(date +%s) * 1000))" ;;
    *)        echo "$ms" ;;
  esac
}

# ── Token estimation ─────────────────────────────────────

# Estimate token count from character count (chars/4 approximation)
estimate_tokens() {
  local chars="${1:-0}"
  echo $(( (chars + 3) / 4 ))
}

# ── Self-referential guard ───────────────────────────────

# Check if this is an introspector-related tool call
# Uses structured Skill tool name from CLAUDE_TOOL_INPUT (jq) to avoid
# false positives when file paths/content mention "plugin-introspector".
is_introspector_call() {
  local tool_name="${CLAUDE_TOOL_NAME:-}"
  # Direct skill invocation check
  if [ "$tool_name" = "Skill" ] && command -v jq &>/dev/null; then
    local skill_name
    skill_name=$(echo "${CLAUDE_TOOL_INPUT:-}" | jq -r '.skill // empty' 2>/dev/null)
    [ "$skill_name" = "plugin-introspector" ] && return 0
  fi
  return 1
}

# ── Correlation key ──────────────────────────────────────
# Generate a short hash from tool name + input for per-call correlation.
# Parallel tool calls produce different keys → separate .tid/.tstart files.
correlation_key() {
  local key="${CLAUDE_TOOL_NAME:-}${CLAUDE_TOOL_INPUT:-}"
  if command -v md5sum &>/dev/null; then
    printf '%s' "$key" | md5sum 2>/dev/null | head -c 8
  elif command -v cksum &>/dev/null; then
    printf '%s' "$key" | cksum 2>/dev/null | cut -d' ' -f1
  else
    printf '%s' "$$"
  fi
}

# ── JSON value sanitizer ────────────────────────────────
# Escape backslashes, double quotes, and remove control characters
# for safe embedding inside JSON string values.
# Usage: sanitize_json_value "raw_value" [max_length]
sanitize_json_value() {
  local max_len="${2:-200}"
  printf '%s' "${1:-}" | head -c "${max_len}" | awk '{gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/[[:cntrl:]]/,"")}1' ORS=''
}

# ── Tier detection ───────────────────────────────────────
# Tier 0: Pure hooks (no OTel Collector)
# Tier 1: Hooks + OTel Collector with File Exporter

detect_otel_tier() {
  # Tier 1: OTel Collector File Exporter has written data to our directory
  if [ -d "$OTEL_EXPORT_DIR" ]; then
    local pid_file="${INTROSPECTOR_BASE}/otel-collector.pid"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
      echo 1
      return
    fi
    # Collector not running but export dir has data — still Tier 1
    if [ -n "$(ls -A "$OTEL_EXPORT_DIR" 2>/dev/null)" ]; then
      echo 1
      return
    fi
  fi
  echo 0
}

# ── JSONL helpers ────────────────────────────────────────

# Append a JSON line to a JSONL file
append_jsonl() {
  local file="${1}"
  local json="${2}"
  echo "${json}" >> "${file}"
}

# ── Stats helpers ────────────────────────────────────────

# Read current stats or return default
read_stats() {
  local session_dir="$1"
  local stats_file="${session_dir}/stats.json"
  if [ -f "$stats_file" ]; then
    cat "$stats_file"
  else
    echo '{"tool_calls":0,"total_tokens_est":0,"errors":0,"tools":{}}'
  fi
}

# Write stats with atomic replace (temp file + mv)
write_stats() {
  local session_dir="$1"
  local stats_json="$2"
  local stats_file="${session_dir}/stats.json"
  local tmp_file="${stats_file}.tmp.$$"
  echo "$stats_json" > "$tmp_file" && mv "$tmp_file" "$stats_file" || echo "$stats_json" > "$stats_file"
}

# Record per-tool stats delta via append-only JSONL (lock-free, ~0ms overhead).
# Deltas are aggregated into stats.json by session-end.sh.
# Falls back to flock+jq if stats_deltas.jsonl is not writable.
update_tool_stats() {
  local session_dir="${1}"
  local tool_name="${2}"
  local tokens="${3}"
  local is_error="${4}"   # "true" or "false"
  local duration_ms="${5}"
  local deltas_file="${session_dir}/stats_deltas.jsonl"

  local err_inc=0
  [ "${is_error}" = "true" ] && err_inc=1

  # Sanitize tool name for safe JSON embedding
  local safe_t
  safe_t=$(sanitize_json_value "${tool_name}" 50)

  # Append delta record (lock-free, ~0ms)
  echo "{\"t\":\"${safe_t}\",\"tok\":${tokens},\"err\":${err_inc},\"dur\":${duration_ms}}" >> "${deltas_file}" 2>/dev/null || true
}

# ── input_summary extraction ─────────────────────────────

# Extract tool-specific context summary from CLAUDE_TOOL_INPUT
# Returns a sanitized string (max 200 chars, no quotes/newlines)
extract_input_summary() {
  local tool_name="$1"
  local tool_input="${CLAUDE_TOOL_INPUT:-}"
  local summary=""

  if [ -n "$tool_input" ] && command -v jq &>/dev/null; then
    case "$tool_name" in
      Read)       summary=$(echo "$tool_input" | jq -r '.file_path // .path // empty' 2>/dev/null) ;;
      Edit|Write) summary=$(echo "$tool_input" | jq -r '.file_path // .path // empty' 2>/dev/null) ;;
      Bash)       summary=$(echo "$tool_input" | jq -r '.command // empty' 2>/dev/null) ;;
      Glob)       summary=$(echo "$tool_input" | jq -r '.pattern // empty' 2>/dev/null) ;;
      Grep)       summary=$(echo "$tool_input" | jq -r '.pattern // empty' 2>/dev/null) ;;
      Task)       summary=$(echo "$tool_input" | jq -r '.description // .prompt // empty' 2>/dev/null) ;;
      Skill)      summary=$(echo "$tool_input" | jq -r '.skill // empty' 2>/dev/null) ;;
    esac
  fi

  # Sanitize for safe JSON embedding (handles backslashes, quotes, control chars)
  sanitize_json_value "$summary" 200
}

# ── DLP: Sensitive data detection ─────────────────────────
# Checks content for credential/secret patterns.
# Returns space-separated list of finding types, or empty string.
# Enabled only when PI_ENABLE_DLP=1.
detect_sensitive_data() {
  [ "${PI_ENABLE_DLP:-0}" = "1" ] || return 0
  local content="${1:-}"
  [ -n "$content" ] || return 0

  # Single grep with alternation for all DLP patterns (8→1 process)
  local matches
  matches=$(printf '%s' "${content}" | grep -oE 'AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|BEGIN.*PRIVATE KEY|ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82}|(password|passwd|pwd)[[:space:]]*[=:][[:space:]]*[^[:space:]]+|aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}|eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.' 2>/dev/null) || true
  [ -n "${matches}" ] || return 0

  local findings=""
  echo "${matches}" | grep -qE '^AKIA' 2>/dev/null && findings="${findings}AWS_KEY "
  echo "${matches}" | grep -qE '^sk-' 2>/dev/null && findings="${findings}API_KEY "
  echo "${matches}" | grep -qF 'PRIVATE KEY' 2>/dev/null && findings="${findings}PRIVATE_KEY "
  echo "${matches}" | grep -qE '^ghp_' 2>/dev/null && findings="${findings}GITHUB_TOKEN "
  echo "${matches}" | grep -qE '^github_pat_' 2>/dev/null && findings="${findings}GITHUB_PAT "
  echo "${matches}" | grep -qiE '^(password|passwd|pwd)' 2>/dev/null && findings="${findings}PASSWORD "
  echo "${matches}" | grep -qE '^aws_secret' 2>/dev/null && findings="${findings}AWS_SECRET "
  echo "${matches}" | grep -qE '^eyJ' 2>/dev/null && findings="${findings}JWT "

  printf '%s' "${findings% }"
}

# ── Command risk classification ───────────────────────────
# Classifies a Bash command string by risk level.
# Uses a single grep per tier (3 processes max) instead of 17 sequential echo|grep.
# Returns: CRITICAL, HIGH, MEDIUM, or LOW
classify_command_risk() {
  local cmd="${1:-}"
  [ -n "$cmd" ] || { echo "LOW"; return; }

  # CRITICAL: data exfiltration, reverse shells, credential theft
  if printf '%s' "$cmd" | grep -qE 'curl[[:space:]].*(-X[[:space:]]*POST|--data|-d[[:space:]])|wget[[:space:]].*--post|nc[[:space:]]+-e|ncat[[:space:]]|nslookup.*base64|cat[[:space:]]+~/?\.?ssh/|cat[[:space:]]+~/?\.?aws/|/etc/shadow|eval[[:space:]]' 2>/dev/null; then
    echo "CRITICAL"; return
  fi

  # HIGH: credential harvesting, privilege escalation
  if printf '%s' "$cmd" | grep -qE '^[[:space:]]*(sudo|su)[[:space:]]|printenv|/proc/self/environ|env[[:space:]]*\||tar[[:space:]].*\.(ssh|aws|gnupg)|chmod[[:space:]]+(777|666|a\+rwx)|pip[[:space:]]+install[[:space:]]+-g|npm[[:space:]]+install[[:space:]]+-g' 2>/dev/null; then
    echo "HIGH"; return
  fi

  # MEDIUM: network, package install, system info
  if printf '%s' "$cmd" | grep -qE '^[[:space:]]*(curl|wget)[[:space:]]|nslookup[[:space:]]|^[[:space:]]*dig[[:space:]]|pip[[:space:]]+install|npm[[:space:]]+install|^[[:space:]]*python3?[[:space:]]+-c|^[[:space:]]*node[[:space:]]+-e|^[[:space:]]*(chmod|chown)[[:space:]]' 2>/dev/null; then
    echo "MEDIUM"; return
  fi

  # LOW: everything else (git, build, test, etc.)
  echo "LOW"
}

# ── OTel span recording ─────────────────────────────────

# Record an OTel-compatible span to otel_traces.jsonl
# Only called at Tier 0 (at Tier 1+, native OTel handles span generation)
record_otel_span() {
  local session_dir="$1"
  local tool_name
  tool_name=$(sanitize_json_value "$2" 100)
  local start_ms="$3"
  local end_ms="$4"
  local duration_ms="$5"
  local input_tokens="$6"
  local output_tokens="$7"
  local status="${8:-OK}"

  local span_id
  span_id=$(generate_id)
  local sid
  sid=$(get_session_id)
  local trace_id
  if command -v md5sum &>/dev/null; then
    trace_id=$(printf '%s' "$sid" | md5sum 2>/dev/null | head -c 32)
  elif command -v md5 &>/dev/null; then
    trace_id=$(printf '%s' "$sid" | md5 2>/dev/null | head -c 32)
  else
    trace_id=$(printf '%s' "$sid" | cksum 2>/dev/null | cut -d' ' -f1 | head -c 32)
  fi

  # Read parent span
  local parent_span_id=""
  [ -f "${session_dir}/.parent_span" ] && parent_span_id=$(cat "${session_dir}/.parent_span")

  # Determine span kind and name
  local span_kind="INTERNAL"
  local span_name="execute_tool ${tool_name}"
  local otel_type="gen_ai.execute_tool"
  case "$tool_name" in
    chat|Chat) span_kind="CLIENT"; span_name="gen_ai.chat"; otel_type="gen_ai.chat" ;;
    Task)      span_name="gen_ai.invoke_agent"; otel_type="gen_ai.invoke_agent" ;;
  esac

  append_jsonl "${session_dir}/otel_traces.jsonl" \
    "{\"trace_id\":\"${trace_id}\",\"span_id\":\"${span_id}\",\"parent_span_id\":\"${parent_span_id}\",\"name\":\"${span_name}\",\"kind\":\"${span_kind}\",\"start_time_ms\":${start_ms},\"end_time_ms\":${end_ms},\"duration_ms\":${duration_ms},\"attributes\":{\"gen_ai.operation.name\":\"${otel_type}\",\"gen_ai.tool.name\":\"${tool_name}\",\"gen_ai.usage.input_tokens\":${input_tokens},\"gen_ai.usage.output_tokens\":${output_tokens}},\"status\":\"${status}\"}"

  # Update parent span for nested operations
  echo "${span_id}" > "${session_dir}/.parent_span"
}
