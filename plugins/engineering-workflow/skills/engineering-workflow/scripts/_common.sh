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

# ── File Logging ──────────────────────────────────────────

SESSION_LOG="${CACHE_DIR}/session.log"
MAX_LOG_LINES=1000
MAX_LOG_FILES=5

# Write a message to the session log file (no stderr output)
log_to_file() {
  local msg
  msg="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ") $*"
  echo "${msg}" >> "${SESSION_LOG}" 2>/dev/null || true
}

# Rotate session log if it exceeds MAX_LOG_LINES
rotate_session_log() {
  [ ! -f "${SESSION_LOG}" ] && return
  local line_count
  line_count=$(wc -l < "${SESSION_LOG}" 2>/dev/null | tr -d ' ')
  if [ "${line_count}" -gt "${MAX_LOG_LINES}" ]; then
    local ts
    ts=$(date -u +"%Y%m%dT%H%M%SZ")
    cp "${SESSION_LOG}" "${CACHE_DIR}/session-${ts}.log" 2>/dev/null || true
    tail -n $(( MAX_LOG_LINES * 80 / 100 )) "${SESSION_LOG}" > "${SESSION_LOG}.tmp" 2>/dev/null && \
      mv "${SESSION_LOG}.tmp" "${SESSION_LOG}" || true
    # Keep only MAX_LOG_FILES archived logs
    ls -1t "${CACHE_DIR}"/session-*.log 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null || true
  fi
}

# ── Logging ───────────────────────────────────────────────

log_info()  { printf '[EW] %s\n' "$*" >&2; log_to_file "[INFO] $*"; }
log_warn()  { printf '[EW][WARN] %s\n' "$*" >&2; log_to_file "[WARN] $*"; }
log_error() { printf '[EW][ERROR] %s\n' "$*" >&2; log_to_file "[ERROR] $*"; }
log_ok()    { printf '[EW][OK] %s\n' "$*" >&2; log_to_file "[OK] $*"; }

# Log only to file (no stderr output) — for verbose diagnostic info
log_detail() { log_to_file "[DETAIL] $*"; }

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
  local default="${2}"
  if [ -z "${default}" ]; then default='{}'; fi
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
DYNAMODB_VENDOR_KEYWORDS="dynamodb|다이나모디비"
DYNAMODB_THROUGHPUT_INTENT_KEYWORDS="rcu|wcu|hot partition|adaptive capacity|throttling|provisioned throughput|on-demand|ondemand|온디맨드|프로비저닝|처리량|tps|gsi|back pressure|백프레셔"

# BE cluster keyword lists for fine-grained BE sub-domain classification
BE_CLUSTER_S_KEYWORDS="dependency violation|import direction|runtimeonly|layer rule|port design|adapter injection|constructor injection|dependency injection|stub pattern|new module|naming convention|publisher vs producer|module layout|archunit|konsist|fitness function|checktest|ci automation|hexagonal|port.*adapter|gradle multi-module|convention|code style|naming rule|jpa pattern|entity model|dynamic update"
BE_CLUSTER_B_KEYWORDS="external system|acl|anti-corruption|conformist|semantic gap|context mapping|translator|feign|testfixtures|internal event|external event|sqs|event versioning|domain event|integration event|publisher vs producer|payment flow|compensation|saga|pivot step|compensable|retryable step|implementation guide|code pattern|feign client"
BE_CLUSTER_R_KEYWORDS="bulkhead|thread pool bulkhead|semaphore|circuit breaker|failurerate|slowcall|resilience4j|timeout|retry|fallback|idempotencykey|backoff|decorator chain|monitoring|dashboard|alert rule|tracing|grafana|prometheus|pagerduty|observability|micrometer"
BE_CLUSTER_T_KEYWORDS="fixture monkey|fakerepository|test name byte|integrationtestcontext|stub checklist|spyk|mockk|strikt|testcontainers|test architecture|test strategy|test generation|coverage|mutation|property.based|contract.test|test quality"

# SE cluster keyword lists for fine-grained SE sub-domain classification (A/Z/E/N/C/V)
SE_CLUSTER_A_KEYWORDS="authentication|oauth|oauth2|jwt|saml|oidc|openid|sso|mfa|login|session management|token management|passkey|webauthn|refresh token|access token|credential|passwordless|bcrypt|argon2|scrypt|authn|single sign-on|multi-factor|2fa|totp|fido|biometric|fingerprint"
SE_CLUSTER_Z_KEYWORDS="authorization|rbac|abac|rebac|permission|access control|policy engine|role|privilege|scope|grant|opa|cedar|casbin|authz|least privilege|role-based|attribute-based|relationship-based|acl"
SE_CLUSTER_E_KEYWORDS="encryption|tls|ssl|certificate|key management|pki|hashing|signing|hmac|vault|kms|cipher|aes|chacha20|rsa|ecdsa|at-rest|in-transit|field-level encryption|secret management|secrets manager|key rotation|mtls|mutual tls|ocsp|certificate pinning|hsm"
SE_CLUSTER_N_KEYWORDS="firewall|cors|csrf|waf|rate limiting|ip filtering|ddos|network policy|csp|hsts|security header|x-frame-options|referrer-policy|permissions-policy|content-security-policy|api gateway security|request signing|input validation|sql injection|xss|path traversal|sanitization|input sanitizer"
SE_CLUSTER_C_KEYWORDS="compliance|audit|zero-trust|soc2|iso27001|gdpr|pci-dss|audit logging|governance|privacy|dpia|data retention|data subject|consent management|pii|data masking|microsegmentation|beyondcorp|data protection|hipaa"
SE_CLUSTER_V_KEYWORDS="vulnerability|penetration|owasp|threat model|cve|security testing|sast|dast|sbom|software composition|supply chain|sca|stride|pasta|attack tree|attack surface|pentest|nuclei|burp|zap|exploit|security review|devsecops|secure development|sdl"

# System classification keywords
DB_KEYWORDS="database|db|sql|nosql|dynamodb|다이나모디비|table scan|join|foreign key|primary key|transaction|schema"
BE_KEYWORDS="api|apis|rest|restful|grpc|spring|controller|service layer|dto|repository pattern|dependency injection|middleware|hexagonal|archunit|konsist|resilience4j|saga|fixture monkey|acl|bulkhead|circuit breaker|convention|code style|naming rule|jpa pattern|entity model|dynamic update|implementation guide|code pattern|test strategy|test generation|coverage|mutation|property.based|contract.test|test quality|backend|server|endpoint|domain event|integration event|feign|port.*adapter|retry|retries"
IF_KEYWORDS="infrastructure|kubernetes|k8s|container|docker|ci/cd|pipeline|deployment|load balancer|cdn|dns|monitoring|observability|tracing|terraform|ansible|helm|scaling|auto-scaling|network topology|devops|github actions|jenkins|logging"
SE_KEYWORDS="authentication|oauth|jwt|authorization|rbac|abac|encryption|tls|ssl|key management|zero-trust|compliance|audit|vulnerability|penetration|security|token management|certificate|firewall|cors|csrf|xss|injection|passkey|webauthn|mfa|sso|saml|oidc|gdpr|pci-dss|soc2|iso27001|dpia|pii|owasp|sbom|sca|sast|dast|waf|threat model|cve|stride|devsecops|secret management|hsts|csp"

# ── Cross-system weighted scoring (Phase 2) ─────────────
# Global score variables set by detect_system(), read by compute_confidence()
# Source weights: routing-protocol.md § Keyword-to-System Matrix (weight × affinity)

_EW_DB_SCORE="0.00"
_EW_BE_SCORE="0.00"
_EW_IF_SCORE="0.00"
_EW_SE_SCORE="0.00"
_EW_SCORE_GAP="0.00"
_EW_SCORE_DOMINANCE="0.00"
_EW_PHASE2_ACTIVE="0"
_EW_SESSION_CONTEXT_APPLIED="0"
_EW_SESSION_BOOST="0.00"

# Score cross-system keywords and accumulate weighted scores into _EW_*_SCORE globals.
# Each keyword group is grepped once; matching adds the group's per-system weights.
# 14 groups × 1 grep + 1 awk = ~30ms total.
score_cross_keywords() {
  local query="${1}"
  local g1=0 g2=0 g3=0 g4=0 g5=0 g6=0 g7=0 g8=0 g9=0 g10=0 g11=0 g12=0 g13=0 g14=0

  echo "${query}" | grep -wqE "replication|failover" && g1=1                        # DB=0.80 IF=0.24
  echo "${query}" | grep -wqE "sharding" && g2=1                                    # DB=0.80 IF=0.16
  echo "${query}" | grep -wqE "isolation|mvcc|locking" && g3=1                      # DB=0.90 BE=0.18
  echo "${query}" | grep -wqE "consistency|cap theorem" && g4=1                     # DB=0.49 BE=0.21
  echo "${query}" | grep -wqE "concurrency|thread pool" && g5=1                     # DB=0.21 BE=0.70
  echo "${query}" | grep -wqE "connection pool|caching strategy" && g6=1            # DB=0.21 BE=0.70
  echo "${query}" | grep -wqE "cqrs|event sourcing|saga" && g7=1                    # DB=0.32 BE=0.80
  echo "${query}" | grep -wqE "scaling|auto-scaling" && g8=1                        # BE=0.21 IF=0.70
  echo "${query}" | grep -wqE "encryption|tls|key management" && g9=1              # IF=0.24 SE=0.80
  echo "${query}" | grep -wqE "zero-trust|compliance|audit" && g10=1               # IF=0.16 SE=0.80
  echo "${query}" | grep -wqE "firewall|certificate" && g11=1                       # IF=0.21 SE=0.70
  echo "${query}" | grep -wqE "monitoring|observability|tracing" && g12=1           # BE=0.21 IF=0.70
  echo "${query}" | grep -wqE "multi-tenant" && g13=1                               # DB=0.30 BE=0.30 IF=0.12 SE=0.24
  echo "${query}" | grep -wqE "architecture decision" && g14=1                      # DB=0.15 BE=0.15 IF=0.15 SE=0.15

  read _EW_DB_SCORE _EW_BE_SCORE _EW_IF_SCORE _EW_SE_SCORE <<< "$(awk \
    -v g1=$g1 -v g2=$g2 -v g3=$g3 -v g4=$g4 -v g5=$g5 -v g6=$g6 -v g7=$g7 \
    -v g8=$g8 -v g9=$g9 -v g10=$g10 -v g11=$g11 -v g12=$g12 -v g13=$g13 -v g14=$g14 '
    BEGIN {
      db=0; be=0; inf=0; se=0
      if (g1)  { db+=0.80; inf+=0.24 }
      if (g2)  { db+=0.80; inf+=0.16 }
      if (g3)  { db+=0.90; be+=0.18 }
      if (g4)  { db+=0.49; be+=0.21 }
      if (g5)  { db+=0.21; be+=0.70 }
      if (g6)  { db+=0.21; be+=0.70 }
      if (g7)  { db+=0.32; be+=0.80 }
      if (g8)  { be+=0.21; inf+=0.70 }
      if (g9)  { inf+=0.24; se+=0.80 }
      if (g10) { inf+=0.16; se+=0.80 }
      if (g11) { inf+=0.21; se+=0.70 }
      if (g12) { be+=0.21; inf+=0.70 }
      if (g13) { db+=0.30; be+=0.30; inf+=0.12; se+=0.24 }
      if (g14) { db+=0.15; be+=0.15; inf+=0.15; se+=0.15 }
      printf "%.2f %.2f %.2f %.2f\n", db, be, inf, se
    }')"
}

# Compute continuous confidence from Phase 1/2 scoring results.
# Args: total_matches (Phase 1 binary hit count), has_subdomain (0/1)
# Uses globals: _EW_PHASE2_ACTIVE, _EW_SCORE_GAP, _EW_SCORE_DOMINANCE, _EW_SESSION_CONTEXT_APPLIED
compute_confidence() {
  local total_matches="${1}"
  local has_subdomain="${2:-0}"

  if [ "${total_matches}" -eq 0 ]; then
    if [ "${_EW_SESSION_CONTEXT_APPLIED}" = "1" ]; then
      echo "0.15"
    else
      echo "0.0"
    fi
    return
  fi

  if [ "${_EW_PHASE2_ACTIVE}" != "1" ]; then
    # Fast path: no cross keywords, use fixed tiers (existing behavior)
    if [ "${total_matches}" -eq 1 ] && [ "${has_subdomain}" -eq 1 ]; then
      echo "0.85"
    elif [ "${total_matches}" -eq 1 ]; then
      echo "0.70"
    else
      echo "0.60"
    fi
    return
  fi

  # Phase 2 active: continuous confidence based on gap/dominance
  if [ "${total_matches}" -eq 1 ]; then
    # Single Phase 1 system with cross-keyword refinement
    awk -v dom="${_EW_SCORE_DOMINANCE}" -v has_sub="${has_subdomain}" '
      BEGIN {
        b = 0.70 + (dom - 0.5) * 0.40
        if (has_sub == 1) b += 0.10
        if (b > 1.0) b = 1.0
        printf "%.2f\n", b
      }'
  else
    # Multi-system: confidence capped at 0.69
    awk -v gap="${_EW_SCORE_GAP}" '
      BEGIN {
        c = 0.60 + gap * 0.30
        if (c > 0.69) c = 0.69
        printf "%.2f\n", c
      }'
  fi
}

# Apply session context decay weights to _EW_*_SCORE globals.
# Reads last 3 entries from session-history.jsonl within 30-minute window.
# Decay: most recent +0.15, n-1 +0.10, n-2 +0.05
# Max total boost +0.30 (3 entries × max weight), well below gap threshold (0.3)
apply_session_context() {
  [ ! -f "${SESSION_HISTORY}" ] && return
  _EW_SESSION_CONTEXT_APPLIED="0"
  _EW_SESSION_BOOST="0.00"

  local cutoff_ts
  cutoff_ts=$(date -u -v-30M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
  cutoff_ts=$(date -u -d "30 minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || return

  local lines=()
  while IFS= read -r line; do
    [ -n "${line}" ] && lines+=("${line}")
  done < <(tail -n 3 "${SESSION_HISTORY}" 2>/dev/null)
  local count=${#lines[@]}
  [ "${count}" -eq 0 ] && return

  # Build "SYS:weight" operations: most recent (last line) gets 0.15
  local weights=("0.15" "0.10" "0.05")
  local add_ops=""
  local wi=0
  local i
  for (( i = count - 1; i >= 0 && wi < 3; i-- )); do
    local entry="${lines[$i]}"
    local ts
    ts=$(echo "${entry}" | jq -r '.timestamp // ""' 2>/dev/null || true)
    [ -z "${ts}" ] && { wi=$((wi + 1)); continue; }

    if [[ "${ts}" < "${cutoff_ts}" ]]; then
      wi=$((wi + 1))
      continue
    fi

    local weight="${weights[$wi]}"
    local sys_list
    sys_list=$(echo "${entry}" | jq -r '.classification.systems[]?' 2>/dev/null || true)
    for sys in ${sys_list}; do
      add_ops="${add_ops}${sys}:${weight} "
      _EW_SESSION_CONTEXT_APPLIED="1"
    done
    wi=$((wi + 1))
  done

  [ "${_EW_SESSION_CONTEXT_APPLIED}" != "1" ] && return

  # Apply all additions in one awk call
  read _EW_DB_SCORE _EW_BE_SCORE _EW_IF_SCORE _EW_SE_SCORE _EW_SESSION_BOOST <<< "$(awk \
    -v base_db="${_EW_DB_SCORE}" -v base_be="${_EW_BE_SCORE}" \
    -v base_if="${_EW_IF_SCORE}" -v base_se="${_EW_SE_SCORE}" \
    -v ops="${add_ops}" '
    BEGIN {
      db=base_db+0; be=base_be+0; inf=base_if+0; se=base_se+0; total=0
      n=split(ops, arr, " ")
      for(i=1;i<=n;i++) {
        if(arr[i]=="") continue
        split(arr[i], kv, ":")
        w=kv[2]+0
        if(kv[1]=="DB") db+=w
        else if(kv[1]=="BE") be+=w
        else if(kv[1]=="IF") inf+=w
        else if(kv[1]=="SE") se+=w
        total+=w
      }
      printf "%.2f %.2f %.2f %.2f %.2f\n", db, be, inf, se, total
    }')"

  # Recompute gap and dominance with updated scores
  _EW_PHASE2_ACTIVE="1"
  read _EW_SCORE_GAP _EW_SCORE_DOMINANCE <<< "$(awk \
    -v db="${_EW_DB_SCORE}" -v be="${_EW_BE_SCORE}" -v inf="${_EW_IF_SCORE}" -v se="${_EW_SE_SCORE}" '
    BEGIN {
      s[1]=db; s[2]=be; s[3]=inf; s[4]=se
      max1=0; max2=0
      for(i=1;i<=4;i++) {
        if(s[i]>max1) { max2=max1; max1=s[i] }
        else if(s[i]>max2) max2=s[i]
      }
      gap=max1-max2
      dom=(max1+max2>0)?max1/(max1+max2):0
      printf "%.2f %.2f\n",gap,dom
    }')"
}

# Detect primary system from query text.
# IMPORTANT: Must NOT be called in a $() subshell — sets global _EW_* variables.
# Result is stored in _EW_DETECTED_SYSTEMS global instead of stdout.
# Sets: _EW_DETECTED_SYSTEMS, _EW_*_SCORE, _EW_SCORE_GAP, _EW_SCORE_DOMINANCE, _EW_PHASE2_ACTIVE
detect_system() {
  local query
  query=$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')

  local db_score=0 be_score=0 if_score=0 se_score=0

  # Phase 1: Binary keyword grep (fast path)
  echo "${query}" | grep -wqE "${DB_KEYWORDS}|${DOMAIN_A_KEYWORDS}|${DOMAIN_B_KEYWORDS}|${DOMAIN_C_KEYWORDS}|${DOMAIN_D_KEYWORDS}|${DOMAIN_E_KEYWORDS}|${DOMAIN_F_KEYWORDS}" && db_score=1
  # DynamoDB vendor anchors should match even with non-Latin suffixes (e.g., "dynamodb에서")
  echo "${query}" | grep -qE "${DYNAMODB_VENDOR_KEYWORDS}" && db_score=1
  echo "${query}" | grep -wqE "${BE_KEYWORDS}" && be_score=1
  echo "${query}" | grep -wqE "${IF_KEYWORDS}" && if_score=1
  echo "${query}" | grep -wqE "${SE_KEYWORDS}" && se_score=1

  local total_hits=$((db_score + be_score + if_score + se_score))

  # Phase 2: Cross-keyword weighted scoring for disambiguation
  score_cross_keywords "${query}"

  local cross_total
  cross_total=$(awk "BEGIN{printf \"%.2f\", ${_EW_DB_SCORE} + ${_EW_BE_SCORE} + ${_EW_IF_SCORE} + ${_EW_SE_SCORE}}")

  if [ "${cross_total}" != "0.00" ]; then
    _EW_PHASE2_ACTIVE="1"
    # Compute gap and dominance from cross-keyword scores
    read _EW_SCORE_GAP _EW_SCORE_DOMINANCE <<< "$(awk \
      -v db="${_EW_DB_SCORE}" -v be="${_EW_BE_SCORE}" -v inf="${_EW_IF_SCORE}" -v se="${_EW_SE_SCORE}" '
      BEGIN {
        s[1]=db; s[2]=be; s[3]=inf; s[4]=se
        max1=0; max2=0
        for(i=1;i<=4;i++) {
          if(s[i]>max1) { max2=max1; max1=s[i] }
          else if(s[i]>max2) max2=s[i]
        }
        gap=max1-max2
        dom=(max1+max2>0)?max1/(max1+max2):0
        printf "%.2f %.2f\n",gap,dom
      }')"
  else
    _EW_PHASE2_ACTIVE="0"
    # Fast path: set scores from binary hits
    _EW_DB_SCORE=$([ "${db_score}" -eq 1 ] && echo "1.00" || echo "0.00")
    _EW_BE_SCORE=$([ "${be_score}" -eq 1 ] && echo "1.00" || echo "0.00")
    _EW_IF_SCORE=$([ "${if_score}" -eq 1 ] && echo "1.00" || echo "0.00")
    _EW_SE_SCORE=$([ "${se_score}" -eq 1 ] && echo "1.00" || echo "0.00")
    if [ "${total_hits}" -eq 0 ]; then
      _EW_SCORE_GAP="0.00"; _EW_SCORE_DOMINANCE="0.00"
    elif [ "${total_hits}" -eq 1 ]; then
      _EW_SCORE_GAP="1.00"; _EW_SCORE_DOMINANCE="1.00"
    else
      _EW_SCORE_GAP="0.00"
      _EW_SCORE_DOMINANCE=$(awk "BEGIN{printf \"%.2f\", 1.0 / ${total_hits}}")
    fi
  fi

  # Build system list: Phase 1 hits preserved; if Phase 1 had 0 hits
  # but Phase 2 found cross-keywords, use dominant cross-keyword system(s)
  local systems=""
  [ "${db_score}" -eq 1 ] && systems="${systems}DB "
  [ "${be_score}" -eq 1 ] && systems="${systems}BE "
  [ "${if_score}" -eq 1 ] && systems="${systems}IF "
  [ "${se_score}" -eq 1 ] && systems="${systems}SE "

  if [ -z "${systems}" ] && [ "${_EW_PHASE2_ACTIVE}" = "1" ]; then
    # Phase 1 had 0 hits but cross-keywords found — use dominant system(s)
    if [ "$(awk "BEGIN{print (${_EW_SCORE_GAP} >= 0.3)}")" = "1" ]; then
      # Gap >= 0.3: dominant system only
      systems=$(awk -v db="${_EW_DB_SCORE}" -v be="${_EW_BE_SCORE}" -v inf="${_EW_IF_SCORE}" -v se="${_EW_SE_SCORE}" '
        BEGIN {
          max=db; name="DB"
          if(be>max){max=be;name="BE"}
          if(inf>max){max=inf;name="IF"}
          if(se>max){max=se;name="SE"}
          print name
        }')
    else
      # Gap < 0.3: include all systems with score > 0
      [ "$(awk "BEGIN{print (${_EW_DB_SCORE} > 0)}")" = "1" ] && systems="${systems}DB "
      [ "$(awk "BEGIN{print (${_EW_BE_SCORE} > 0)}")" = "1" ] && systems="${systems}BE "
      [ "$(awk "BEGIN{print (${_EW_IF_SCORE} > 0)}")" = "1" ] && systems="${systems}IF "
      [ "$(awk "BEGIN{print (${_EW_SE_SCORE} > 0)}")" = "1" ] && systems="${systems}SE "
    fi
  fi

  if [ -z "${systems}" ]; then
    _EW_DETECTED_SYSTEMS="UNKNOWN"
  else
    _EW_DETECTED_SYSTEMS="${systems% }"
  fi

  # Also echo for backward compatibility (callers using $() only get stdout, not globals)
  echo "${_EW_DETECTED_SYSTEMS}"
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

  # Domain F: distributed keywords OR DynamoDB vendor anchor + throughput intent keywords
  local f_match=0
  if echo "${query}" | grep -wqE "${DOMAIN_F_KEYWORDS}"; then
    f_match=1
  fi

  if echo "${query}" | grep -qE "${DYNAMODB_VENDOR_KEYWORDS}" && \
     echo "${query}" | grep -qE "${DYNAMODB_THROUGHPUT_INTENT_KEYWORDS}"; then
    f_match=1
  fi

  [ "${f_match}" -eq 1 ] && domains="${domains}F "

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

# Detect SE cluster (A/Z/E/N/C/V) from query text
detect_se_cluster() {
  local query
  query=$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')
  local clusters=""

  echo "${query}" | grep -wqE "${SE_CLUSTER_A_KEYWORDS}" && clusters="${clusters}A "
  echo "${query}" | grep -wqE "${SE_CLUSTER_Z_KEYWORDS}" && clusters="${clusters}Z "
  echo "${query}" | grep -wqE "${SE_CLUSTER_E_KEYWORDS}" && clusters="${clusters}E "
  echo "${query}" | grep -wqE "${SE_CLUSTER_N_KEYWORDS}" && clusters="${clusters}N "
  echo "${query}" | grep -wqE "${SE_CLUSTER_C_KEYWORDS}" && clusters="${clusters}C "
  echo "${query}" | grep -wqE "${SE_CLUSTER_V_KEYWORDS}" && clusters="${clusters}V "

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
# Args: query, classification_json, [prev_signature]
write_session_history() {
  local query="${1}"
  local classification_json="${2}"
  local prev_sig="${3:-}"
  local sig
  sig=$(get_query_signature "${query}")
  local ts
  ts=$(timestamp_iso)

  local entry
  entry=$(jq -cn \
    --arg sig "${sig}" \
    --arg query "${query}" \
    --arg ts "${ts}" \
    --arg prev_sig "${prev_sig}" \
    --argjson classification "${classification_json}" \
    '{signature: $sig, query: $query, classification: $classification, timestamp: $ts, prev_signature: $prev_sig}')

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

# ── Progressive Classification ─────────────────────────────

# Read recent session context entries within a time window
# Args: n (max entries, default 5), window_minutes (default 30)
# Returns: JSON array of recent session history entries
read_session_context() {
  local n="${1:-5}"
  local window_minutes="${2:-30}"
  [ ! -f "${SESSION_HISTORY}" ] && echo "[]" && return

  local cutoff_ts
  # macOS date -v syntax, fallback to GNU date -d
  cutoff_ts=$(date -u -v-"${window_minutes}"M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
  cutoff_ts=$(date -u -d "${window_minutes} minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
  { echo "[]"; return; }

  tail -n "${n}" "${SESSION_HISTORY}" 2>/dev/null | \
    jq -s --arg cutoff "${cutoff_ts}" \
    '[.[] | select(.timestamp >= $cutoff)]' 2>/dev/null || echo "[]"
}

# Compute prior boost from session context overlap with current classification
# Args: current_systems_json, context_entries_json
# Returns: float string (max 0.10)
# Invariant: if TOTAL_MATCHES == 0, caller must not apply the boost
compute_prior_boost() {
  local current_systems="${1}"
  local context_entries="${2}"

  echo "${current_systems}" "${context_entries}" | jq -s '
    .[0] as $current |
    .[1] as $entries |
    if ($entries | length) == 0 then 0
    else
      ([$entries | to_entries[] |
        .key as $idx |
        .value.classification.systems as $prev_sys |
        ($current | map(. as $s | if ($prev_sys | index($s)) != null then 1 else 0 end) | add // 0) as $overlap |
        ($current | length) as $total |
        (if $total > 0 then ($overlap / $total) else 0 end) as $ratio |
        # Time decay: most recent = 1.0, each older entry *= 0.7
        (pow(0.7; $idx)) as $decay |
        ($ratio * $decay * 0.04)
      ] | add // 0) |
      if . > 0.10 then 0.10 else . end |
      . * 100 | round / 100
    end
  ' 2>/dev/null || echo "0"
}

# Lookup transition patterns from pattern cache
# Args: current_system, current_domain_or_cluster
# Returns: suggested_expansions JSON array
lookup_transitions() {
  local current_system="${1:-}"
  local current_dc="${2:-}"
  [ ! -f "${PATTERN_CACHE}" ] && echo "[]" && return
  [ -z "${current_system}" ] && echo "[]" && return

  jq --arg sys "${current_system}" --arg dc "${current_dc}" '
    .__transitions__ // {} |
    to_entries |
    map(select(.value.to_system == $sys and .value.to_cluster == $dc)) |
    # Compute total transitions from each source
    group_by(.value.from_system + "-" + .value.from_domain) |
    [.[] |
      . as $group |
      ($group | map(.value.count) | add) as $total_from |
      $group[] |
      (.value.count / (if $total_from > 0 then $total_from else 1 end)) as $tc |
      select($tc >= 0.20) |
      {
        add_system: .value.from_system,
        add_cluster_or_domain: .value.from_domain,
        reason: "\(.value.from_system)-\(.value.from_domain) → \($sys)-\($dc) 전환 \(.value.count)회 관측 (transition_confidence=\($tc | . * 100 | round / 100))",
        transition_confidence: ($tc | . * 100 | round / 100)
      }
    ] | unique_by(.add_system + "-" + .add_cluster_or_domain)
  ' "${PATTERN_CACHE}" 2>/dev/null || echo "[]"
}

# Record a transition between consecutive queries in pattern cache
# Args: prev_signature, current_system, current_domain_or_cluster
record_transition() {
  local prev_sig="${1:-}"
  local current_system="${2:-}"
  local current_dc="${3:-}"
  [ -z "${prev_sig}" ] && return
  [ -z "${current_system}" ] && return

  # Lookup the previous classification from session history
  # Match only the "signature" field, not "prev_signature"
  [ ! -f "${SESSION_HISTORY}" ] && return
  local prev_entry
  prev_entry=$(grep "\"signature\":\"${prev_sig}\"" "${SESSION_HISTORY}" 2>/dev/null | tail -1 || true)
  [ -z "${prev_entry}" ] && return

  local from_system from_dc
  from_system=$(echo "${prev_entry}" | jq -r '.classification.systems[0] // empty' 2>/dev/null || true)
  [ -z "${from_system}" ] && return
  from_dc=$(echo "${prev_entry}" | jq -r '(.classification.domains[0] // .classification.be_clusters[0] // .classification.se_clusters[0] // "") // ""' 2>/dev/null || true)

  local transition_key="${from_system}-${from_dc}|${current_system}-${current_dc}"

  # Read existing cache or initialize
  local cache
  cache=$(read_json "${PATTERN_CACHE}" '{}')

  local ts
  ts=$(timestamp_iso)

  # Update __transitions__
  local updated
  updated=$(echo "${cache}" | jq \
    --arg key "${transition_key}" \
    --arg from_sys "${from_system}" \
    --arg from_dc "${from_dc}" \
    --arg to_sys "${current_system}" \
    --arg to_dc "${current_dc}" \
    --arg ts "${ts}" \
    '
    .__transitions__ //= {} |
    if .__transitions__[$key] then
      .__transitions__[$key].count += 1 |
      .__transitions__[$key].last_seen = $ts
    else
      .__transitions__[$key] = {
        from_system: $from_sys,
        from_domain: $from_dc,
        to_system: $to_sys,
        to_cluster: $to_dc,
        count: 1,
        last_seen: $ts
      }
    end
    ')

  write_json "${PATTERN_CACHE}" "${updated}"
}

# ── Known semantic conflict pairs ─────────────────────────
# Semantically known incompatible constraint pairs (target:value|target:value format)
# Each pair declares two constraints whose co-existence signals an architectural trade-off.
# Used by resolve-constraints.sh Tier 2 detection.
KNOWN_CONFLICT_PAIRS=(
  # Original 6 pairs
  "storage-engine:lsm|read-latency:low"           # LSM read amplification vs low read latency
  "consistency:strong|write-latency:low"           # Strong consistency adds write synchronization overhead
  "replication:sync|cross-region:true"             # Sync replication causes latency explosion cross-region
  "sharding:hash|range-query:frequent"             # Hash sharding requires cross-shard scatter for range queries
  "encryption:field-level|query-performance:high"  # Field-level encryption prevents index usage
  "saga:orchestration|coupling:loose"              # Orchestration saga depends on central coordinator
  # Extended 9 pairs (deterministic alternative to LLM Tier 3)
  "deployment:zero-downtime|schema:schema-lock"           # Zero-downtime deploy conflicts with DDL locks
  "replication:single-leader|write-region:multi-region"   # Single-leader replication can't serve multi-region writes
  "storage:in-memory|dataset-size:large"                  # In-memory storage impractical for large datasets
  "database:nosql|transaction:acid"                       # NoSQL engines typically lack full ACID transactions
  "consistency:eventual|data-type:financial"               # Financial data requires strong consistency guarantees
  "architecture:microservices|database:shared"             # Microservices with shared DB undermines service autonomy
  "compute:serverless|execution:long-running"              # Serverless platforms impose execution time limits
  "caching:cache-first|consistency:strong"                 # Cache-first reads conflict with strong consistency
  "schema:denormalized|query-type:complex-join"            # Denormalized schema makes complex joins costly or impractical
)

# ── Archetype matching ────────────────────────────────────

ARCHETYPES_FILE="${EW_BASE}/resources/constraints-archetypes.json"

# Match query against archetype trigger keywords; return preset_constraints JSON array
match_archetype() {
  local query="${1}"
  [ ! -f "${ARCHETYPES_FILE}" ] && echo "[]" && return
  local query_lower
  query_lower=$(printf '%s' "${query}" | tr '[:upper:]' '[:lower:]')
  jq -r --arg q "${query_lower}" '
    [to_entries[] |
     select(.value.trigger_keywords[] | . as $kw | $q | test($kw;"i")) |
     .value.preset_constraints[]] | unique_by(.id)
  ' "${ARCHETYPES_FILE}" 2>/dev/null || echo "[]"
}

# Return matched archetype names as JSON array
get_matched_archetypes() {
  local query="${1}"
  [ ! -f "${ARCHETYPES_FILE}" ] && echo "[]" && return
  local query_lower
  query_lower=$(printf '%s' "${query}" | tr '[:upper:]' '[:lower:]')
  jq -r --arg q "${query_lower}" '
    [to_entries[] |
     select(.value.trigger_keywords[] | . as $kw | $q | test($kw;"i")) |
     .key] | unique
  ' "${ARCHETYPES_FILE}" 2>/dev/null || echo "[]"
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
  rotate_session_log
}

# ── Progress tracking ────────────────────────────────────

PROGRESS_FILE="${CACHE_DIR}/progress.json"

# Write current phase/status to progress file
write_progress() {
  local phase="${1}"
  local status="${2}"
  local ts
  ts=$(timestamp_iso)

  local existing
  existing=$(read_json "${PROGRESS_FILE}" '{}')

  local updated
  updated=$(echo "${existing}" | jq \
    --arg phase "${phase}" \
    --arg status "${status}" \
    --arg ts "${ts}" \
    '.phase = $phase | .status = $status | .updated_at = $ts | if .started_at == null then .started_at = $ts else . end')

  write_json "${PROGRESS_FILE}" "${updated}"
  log_detail "Progress: phase=${phase} status=${status}"
}

# Read current progress (returns JSON object or empty object)
read_progress() {
  read_json "${PROGRESS_FILE}" '{}'
}

# Archive progress file (mark as completed or archive interrupted session)
archive_progress() {
  local final_status="${1:-completed}"
  if [ ! -f "${PROGRESS_FILE}" ]; then
    return
  fi

  local ts
  ts=$(timestamp_iso)
  local updated
  updated=$(jq --arg status "${final_status}" --arg ts "${ts}" \
    '.status = $status | .completed_at = $ts' "${PROGRESS_FILE}" 2>/dev/null)

  if [ -n "${updated}" ]; then
    write_json "${PROGRESS_FILE}" "${updated}"
  fi

  # Archive to history
  local archive_ts
  archive_ts=$(date -u +"%Y%m%dT%H%M%SZ")
  mkdir -p "${CACHE_DIR}/history" 2>/dev/null || true
  cp "${PROGRESS_FILE}" "${CACHE_DIR}/history/progress-${archive_ts}.json" 2>/dev/null || true
  log_detail "Archived progress as ${final_status}: progress-${archive_ts}.json"
}

# ── Session summary ──────────────────────────────────────

SESSION_SUMMARY="${CACHE_DIR}/session-summary.json"

# Write session summary after query completion
write_session_summary() {
  local query="${1:-}"
  local classification_json="${2}"
  if [ -z "${classification_json}" ]; then classification_json='{}'; fi
  local tier="${3:-LIGHT}"
  local agents_dispatched="${4:-0}"
  local constraint_summary="${5}"
  if [ -z "${constraint_summary}" ]; then constraint_summary='{}'; fi

  local ts
  ts=$(timestamp_iso)

  local summary
  summary=$(jq -n \
    --arg query "${query}" \
    --argjson classification "${classification_json}" \
    --arg tier "${tier}" \
    --argjson agents "${agents_dispatched}" \
    --argjson constraints "${constraint_summary}" \
    --arg ts "${ts}" \
    '{
      last_query: $query,
      last_classification: $classification,
      last_tier: $tier,
      agents_dispatched: $agents,
      constraint_summary: $constraints,
      completed_at: $ts
    }')

  write_json "${SESSION_SUMMARY}" "${summary}"
  log_detail "Session summary written for query: ${query}"
}

# Read session summary (returns JSON object or empty object)
read_session_summary() {
  read_json "${SESSION_SUMMARY}" '{}'
}
