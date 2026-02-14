#!/usr/bin/env bash
# Engineering Workflow — Shared utilities for scripts
# All functions used by multiple scripts are defined here.
#
# Function prefix conventions:
#   get_*       — Pure getters, no I/O side effects
#   read_*      — Read from file/disk
#   write_*     — Write to file/disk
#   detect_*    — Classify or detect a condition, returns a value
#   format_*    — Transform data into a display format
#   validate_*  — Check data against rules, returns 0/1
#
# Variable quoting: always use "${var}" (defensive quoting)

set -euo pipefail

# ── Base directories ──────────────────────────────────────

CACHE_DIR="${HOME}/.claude/cache/engineering-workflow"
EW_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure cache directory exists
mkdir -p "${CACHE_DIR}" "${CACHE_DIR}/results" 2>/dev/null || true

# ── Logging ───────────────────────────────────────────────

log_info()  { printf '[EW] %s\n' "$*" >&2; }
log_warn()  { printf '[EW][WARN] %s\n' "$*" >&2; }
log_error() { printf '[EW][ERROR] %s\n' "$*" >&2; }
log_ok()    { printf '[EW][OK] %s\n' "$*" >&2; }

# ── Input helpers ─────────────────────────────────────

# Read JSON input from: file path, inline JSON string, or stdin
read_input() {
  if [ -n "${1:-}" ] && [ -f "${1}" ]; then
    cat "${1}"
  elif [ -n "${1:-}" ] && echo "${1}" | jq . >/dev/null 2>&1; then
    echo "${1}"
  else
    cat
  fi
}

# ── JSON helpers ──────────────────────────────────────────

# Check if jq is available
require_jq() {
  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed"
    exit 1
  fi
}

# Read a JSON file or return default
read_json() {
  local file="${1}"
  local default="${2:-{}}"
  if [ -f "${file}" ]; then
    cat "${file}"
  else
    echo "${default}"
  fi
}

# Write JSON with atomic replace
write_json() {
  local file="${1}"
  local json="${2}"
  local tmp_file="${file}.tmp.$$"
  echo "${json}" > "${tmp_file}" && mv "${tmp_file}" "${file}" || echo "${json}" > "${file}"
}

# ── Timestamp helpers ─────────────────────────────────────

timestamp_iso() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || true)
  case "$ts" in
    *%*|*N*) date -u +"%Y-%m-%dT%H:%M:%SZ" ;;  # macOS BSD date: %3N → literal ".3NZ"
    *)       echo "$ts" ;;
  esac
}

# ── Domain classification ─────────────────────────────────

# Domain keyword lists for fast-path classification
DOMAIN_A_KEYWORDS="storage engine|innodb|myisam|rocksdb|lsm|b-tree|write amplification|compaction|sstable|memtable|wiredtiger|indexed|indexing|reindex|paging|pagination"
DOMAIN_B_KEYWORDS="index|b\\+tree|hash index|gin|gist|brin|covering index|composite index|query plan|explain|table scan|index scan|join optimization|nested loop|hash join|merge join"
DOMAIN_C_KEYWORDS="isolation|read committed|repeatable read|serializable|snapshot isolation|mvcc|multiversion|lock|locking|deadlock|optimistic|pessimistic|two-phase lock|gap lock"
DOMAIN_D_KEYWORDS="normalization|1nf|2nf|3nf|bcnf|denormalization|schema design|schema|document model|embedding|referencing|access pattern"
DOMAIN_E_KEYWORDS="page|buffer pool|wal|write-ahead log|checkpoint|dirty page|flush|io optimization|direct io|sequential io|random io"
DOMAIN_F_KEYWORDS="replication|primary-replica|master-slave|consensus|raft|paxos|consistency|eventual consistency|strong consistency|cap theorem|shard|sharding|partition|partitioned|partitioning|hash partition|range partition"

# BE cluster keyword lists for fine-grained BE sub-domain classification
BE_CLUSTER_S_KEYWORDS="dependency violation|import direction|runtimeonly|layer rule|port design|adapter injection|constructor injection|dependency injection|stub pattern|new module|naming convention|publisher vs producer|module layout|archunit|konsist|fitness function|checktest|ci automation|hexagonal|port.*adapter|gradle multi-module|convention|code style|naming rule|jpa pattern|entity model|dynamic update"
BE_CLUSTER_B_KEYWORDS="external system|acl|anti-corruption|conformist|semantic gap|context mapping|translator|feign|testfixtures|internal event|external event|sqs|event versioning|domain event|integration event|publisher vs producer|payment flow|compensation|saga|pivot step|compensable|retryable step|implementation guide|code pattern|feign client"
BE_CLUSTER_R_KEYWORDS="bulkhead|thread pool bulkhead|semaphore|circuit breaker|failurerate|slowcall|resilience4j|timeout|retry|fallback|idempotencykey|backoff|decorator chain|monitoring|dashboard|alert rule|tracing|grafana|prometheus|pagerduty|observability|micrometer"
BE_CLUSTER_T_KEYWORDS="fixture monkey|fakerepository|test name byte|integrationtestcontext|stub checklist|spyk|mockk|strikt|testcontainers|test architecture|test strategy|test generation|coverage|mutation|property.based|contract.test|test quality"

# System classification keywords
DB_KEYWORDS="database|db|sql|nosql|table scan|join|foreign key|primary key|transaction|schema"
BE_KEYWORDS="api|apis|rest|restful|grpc|spring|controller|service layer|dto|repository pattern|dependency injection|middleware|hexagonal|archunit|konsist|resilience4j|saga|fixture monkey|acl|bulkhead|circuit breaker|convention|code style|naming rule|jpa pattern|entity model|dynamic update|implementation guide|code pattern|test strategy|test generation|coverage|mutation|property.based|contract.test|test quality|backend|server|endpoint|domain event|integration event|feign|port.*adapter|retry|retries"
IF_KEYWORDS="infrastructure|kubernetes|k8s|container|docker|ci/cd|pipeline|deployment|load balancer|cdn|dns|monitoring|observability|tracing|terraform|ansible|helm|scaling|auto-scaling|network topology|devops|github actions|jenkins|logging"
SE_KEYWORDS="authentication|oauth|jwt|authorization|rbac|abac|encryption|tls|ssl|key management|zero-trust|compliance|audit|vulnerability|penetration|security|token management|certificate|firewall|cors|csrf|xss|injection"

# Detect primary system from query text
detect_system() {
  local query
  query=$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')

  local db_score=0 be_score=0 if_score=0 se_score=0

  echo "${query}" | grep -wqE "${DB_KEYWORDS}|${DOMAIN_A_KEYWORDS}|${DOMAIN_B_KEYWORDS}|${DOMAIN_C_KEYWORDS}|${DOMAIN_D_KEYWORDS}|${DOMAIN_E_KEYWORDS}|${DOMAIN_F_KEYWORDS}" && db_score=1
  echo "${query}" | grep -wqE "${BE_KEYWORDS}" && be_score=1
  echo "${query}" | grep -wqE "${IF_KEYWORDS}" && if_score=1
  echo "${query}" | grep -wqE "${SE_KEYWORDS}" && se_score=1

  # Return all matching systems
  local systems=""
  [ "${db_score}" -eq 1 ] && systems="${systems}DB "
  [ "${be_score}" -eq 1 ] && systems="${systems}BE "
  [ "${if_score}" -eq 1 ] && systems="${systems}IF "
  [ "${se_score}" -eq 1 ] && systems="${systems}SE "

  if [ -z "${systems}" ]; then
    echo "UNKNOWN"
  else
    echo "${systems% }"
  fi
}

# Detect DB domain (A-F) from query text
detect_db_domain() {
  local query
  query=$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')
  local domains=""

  echo "${query}" | grep -wqE "${DOMAIN_A_KEYWORDS}" && domains="${domains}A "
  echo "${query}" | grep -wqE "${DOMAIN_B_KEYWORDS}" && domains="${domains}B "
  echo "${query}" | grep -wqE "${DOMAIN_C_KEYWORDS}" && domains="${domains}C "
  echo "${query}" | grep -wqE "${DOMAIN_D_KEYWORDS}" && domains="${domains}D "
  echo "${query}" | grep -wqE "${DOMAIN_E_KEYWORDS}" && domains="${domains}E "
  echo "${query}" | grep -wqE "${DOMAIN_F_KEYWORDS}" && domains="${domains}F "

  if [ -z "${domains}" ]; then
    echo "UNKNOWN"
  else
    echo "${domains% }"
  fi
}

# Detect BE cluster (S/B/R/T) from query text
detect_be_cluster() {
  local query
  query=$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')
  local clusters=""

  echo "${query}" | grep -wqE "${BE_CLUSTER_S_KEYWORDS}" && clusters="${clusters}S "
  echo "${query}" | grep -wqE "${BE_CLUSTER_B_KEYWORDS}" && clusters="${clusters}B "
  echo "${query}" | grep -wqE "${BE_CLUSTER_R_KEYWORDS}" && clusters="${clusters}R "
  echo "${query}" | grep -wqE "${BE_CLUSTER_T_KEYWORDS}" && clusters="${clusters}T "

  if [ -z "${clusters}" ]; then
    echo "UNKNOWN"
  else
    echo "${clusters% }"
  fi
}

# ── Session persistence ─────────────────────────────────

SESSION_HISTORY="${CACHE_DIR}/session-history.jsonl"
PATTERN_CACHE="${CACHE_DIR}/pattern-cache.json"

# Compute a normalized query signature: lowercase, strip punctuation, sort words
get_query_signature() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:] ' ' ' | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# Write a classification result to session history (append-only JSONL)
write_session_history() {
  local query="${1}"
  local classification_json="${2}"
  local sig
  sig=$(get_query_signature "${query}")
  local ts
  ts=$(timestamp_iso)

  local entry
  entry=$(jq -n \
    --arg sig "${sig}" \
    --arg query "${query}" \
    --arg ts "${ts}" \
    --argjson classification "${classification_json}" \
    '{signature: $sig, query: $query, classification: $classification, timestamp: $ts}')

  echo "${entry}" >> "${SESSION_HISTORY}" 2>/dev/null || true
}

# Read pattern cache and lookup by signature. Outputs cached classification JSON or empty string.
read_pattern_cache() {
  local sig="${1}"
  if [ ! -f "${PATTERN_CACHE}" ]; then
    echo ""
    return
  fi

  local result
  result=$(jq -r --arg sig "${sig}" '.[$sig] // empty' "${PATTERN_CACHE}" 2>/dev/null || true)
  if [ -n "${result}" ]; then
    local count
    count=$(echo "${result}" | jq -r '.hit_count // 0' 2>/dev/null || echo "0")
    if [ "${count}" -ge 3 ]; then
      echo "${result}" | jq -r '.classification'
      return
    fi
  fi
  echo ""
}

# Promote a query signature to pattern cache if it appears 3+ times in history
promote_to_cache() {
  local sig="${1}"
  local classification_json="${2}"

  if [ ! -f "${SESSION_HISTORY}" ]; then
    return
  fi

  local count
  count=$(grep -c "\"${sig}\"" "${SESSION_HISTORY}" 2>/dev/null || echo "0")

  if [ "${count}" -ge 3 ]; then
    local ts
    ts=$(timestamp_iso)

    # Read existing cache or initialize
    local cache
    cache=$(read_json "${PATTERN_CACHE}" '{}')

    # Add/update entry
    local updated
    updated=$(echo "${cache}" | jq \
      --arg sig "${sig}" \
      --argjson classification "${classification_json}" \
      --arg ts "${ts}" \
      --argjson count "${count}" \
      '.[$sig] = {classification: $classification, hit_count: $count, last_used: $ts}')

    write_json "${PATTERN_CACHE}" "${updated}"
    log_info "Promoted query signature to pattern cache (${count} hits): ${sig}"
  fi
}

# ── Constraint lifecycle ────────────────────────────────

CONSTRAINTS_FILE="${CACHE_DIR}/constraints.json"
CONSTRAINTS_ARCHIVE="${CACHE_DIR}/history"

# Default empty constraints document (nested format matching constraint-propagation.md)
EMPTY_CONSTRAINTS='{"constraints":[],"conflicts":[],"resolved_set":[],"metadata":{"created_at":"","total_declared":0}}'

# Initialize a new constraints session
init_constraints() {
  local query="${1:-}"
  local session_id="${2:-}"
  local ts
  ts=$(timestamp_iso)

  local doc
  doc=$(jq -n \
    --arg sid "${session_id}" \
    --arg query "${query}" \
    --arg ts "${ts}" \
    '{session_id: $sid, query: $query, constraints: [], conflicts: [], resolved_set: [], metadata: {created_at: $ts, total_declared: 0}}')

  write_json "${CONSTRAINTS_FILE}" "${doc}"
}

# Write (append) a constraint to the current constraints.json
write_constraint() {
  local constraint_json="${1}"

  # Read existing or initialize with nested format
  local current
  current=$(read_json "${CONSTRAINTS_FILE}" "${EMPTY_CONSTRAINTS}")

  # Ensure nested format: if top-level is array (legacy), wrap it
  local is_array
  is_array=$(echo "${current}" | jq 'type == "array"' 2>/dev/null || echo "false")
  if [ "${is_array}" = "true" ]; then
    current=$(jq -n --argjson arr "${current}" '{constraints: $arr, conflicts: [], resolved_set: [], metadata: {total_declared: ($arr | length)}}')
  fi

  # Append new constraint and update count
  local updated
  updated=$(echo "${current}" | jq --argjson c "${constraint_json}" '
    .constraints += [$c] |
    .metadata.total_declared = (.constraints | length)')

  write_json "${CONSTRAINTS_FILE}" "${updated}"
}

# Read current constraints (returns JSON array from nested .constraints key)
read_constraints() {
  local doc
  doc=$(read_json "${CONSTRAINTS_FILE}" "${EMPTY_CONSTRAINTS}")

  # Handle both nested and legacy flat-array formats
  local is_array
  is_array=$(echo "${doc}" | jq 'type == "array"' 2>/dev/null || echo "false")
  if [ "${is_array}" = "true" ]; then
    echo "${doc}"
  else
    echo "${doc}" | jq '.constraints // []'
  fi
}

# Archive completed constraints and reset for new session
archive_constraints() {
  if [ ! -f "${CONSTRAINTS_FILE}" ]; then
    return
  fi

  mkdir -p "${CONSTRAINTS_ARCHIVE}" 2>/dev/null || true
  local ts
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  cp "${CONSTRAINTS_FILE}" "${CONSTRAINTS_ARCHIVE}/constraints-${ts}.json" 2>/dev/null || true
  echo "${EMPTY_CONSTRAINTS}" > "${CONSTRAINTS_FILE}"
  log_info "Archived constraints to constraints-${ts}.json"
}

# ── Session cleanup ──────────────────────────────────────

# Trim session history to max_entries (keeps most recent 80%)
cleanup_session_history() {
  local max_entries="${1:-1000}"
  [ ! -f "${SESSION_HISTORY}" ] && return
  local count
  count=$(wc -l < "${SESSION_HISTORY}" 2>/dev/null | tr -d ' ')
  if [ "${count}" -gt "${max_entries}" ]; then
    local keep=$(( max_entries * 80 / 100 ))
    local tmp="${SESSION_HISTORY}.tmp.$$"
    tail -n "${keep}" "${SESSION_HISTORY}" > "${tmp}" 2>/dev/null && mv "${tmp}" "${SESSION_HISTORY}"
    log_info "Trimmed session history: ${count} → ${keep} entries"
  fi
}

# Evict pattern cache entries older than max_age_days
evict_pattern_cache() {
  local max_age_days="${1:-90}"
  [ ! -f "${PATTERN_CACHE}" ] && return
  require_jq

  local cutoff
  # macOS date -v syntax, fallback to GNU date -d
  cutoff=$(date -u -v-"${max_age_days}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
  cutoff=$(date -u -d "${max_age_days} days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || return

  local before_count after_count
  before_count=$(jq 'length' "${PATTERN_CACHE}" 2>/dev/null || echo "0")

  local updated
  updated=$(jq --arg cutoff "${cutoff}" \
    'to_entries | map(select(.value.last_used > $cutoff)) | from_entries' \
    "${PATTERN_CACHE}" 2>/dev/null)

  if [ -n "${updated}" ]; then
    write_json "${PATTERN_CACHE}" "${updated}"
    after_count=$(echo "${updated}" | jq 'length' 2>/dev/null || echo "0")
    if [ "${before_count}" != "${after_count}" ]; then
      log_info "Evicted pattern cache: ${before_count} → ${after_count} entries (cutoff: ${cutoff})"
    fi
  fi
}

# Keep only the most recent N constraint archives
cleanup_constraints_archive() {
  local keep="${1:-20}"
  [ ! -d "${CONSTRAINTS_ARCHIVE}" ] && return

  local archive_count
  archive_count=$(ls -1 "${CONSTRAINTS_ARCHIVE}"/constraints-*.json 2>/dev/null | wc -l | tr -d ' ')

  if [ "${archive_count}" -gt "${keep}" ]; then
    local to_remove=$(( archive_count - keep ))
    ls -1t "${CONSTRAINTS_ARCHIVE}"/constraints-*.json 2>/dev/null \
      | tail -n "${to_remove}" \
      | xargs rm -f 2>/dev/null || true
    log_info "Cleaned constraint archives: removed ${to_remove} old files (kept ${keep})"
  fi
}

# Run all cleanup operations (call at session start)
run_session_cleanup() {
  cleanup_session_history 1000
  evict_pattern_cache 90
  cleanup_constraints_archive 20
}
