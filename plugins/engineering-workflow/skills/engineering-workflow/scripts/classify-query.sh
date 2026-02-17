#!/usr/bin/env bash
# Engineering Workflow — Query Classification (Fast Path)
#
# Classifies a user query into system(s) and DB domain(s) using keyword matching.
# This is the fast-path classifier; ambiguous queries should fall through to LLM.
#
# Usage: classify-query.sh "query text"
# Output: JSON with systems[], domains[], confidence
#
# Dependencies: bash + jq only (no python, no node)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# Run session cleanup (non-blocking, at most once per hour)
CLEANUP_MARKER="${CACHE_DIR}/.last-cleanup"
if [ ! -f "${CLEANUP_MARKER}" ] || [ "$(find "${CLEANUP_MARKER}" -mmin +60 2>/dev/null)" ]; then
  run_session_cleanup 2>/dev/null || true
  touch "${CLEANUP_MARKER}" 2>/dev/null || true
fi

# ── Input ─────────────────────────────────────────────────

QUERY="${1:-}"
if [ -z "${QUERY}" ]; then
  echo '{"error":"No query provided","systems":[],"domains":[],"confidence":0}' | jq .
  exit 1
fi

QUERY_LOWER=$(printf '%s' "${QUERY}" | tr '[:upper:]' '[:lower:]')

# ── Pattern Cache Lookup ─────────────────────────────────

QUERY_SIG=$(get_query_signature "${QUERY}")
CACHED=$(read_pattern_cache "${QUERY_SIG}")
if [ -n "${CACHED}" ]; then
  # Cache hit — return cached classification with confidence 1.0
  # Compute pattern from cached systems array for backward compatibility
  echo "${CACHED}" | jq --arg query "${QUERY}" '. + {query: $query, confidence: 1.0, classifier: "pattern-cache", pattern: (if (.systems | length) == 0 then "none" elif (.systems | length) == 1 then "single" elif (.systems | length) == 2 then "multi" else "cross" end)}'
  exit 0
fi

# ── Archetype Matching ────────────────────────────────────
# Match query against archetype library and inject preset constraints

ARCHETYPE_CONSTRAINTS=$(match_archetype "${QUERY}" 2>/dev/null || echo "[]")
ARCHETYPE_NAMES=$(get_matched_archetypes "${QUERY}" 2>/dev/null || echo "[]")
if [ "$(echo "${ARCHETYPE_CONSTRAINTS}" | jq 'length')" -gt 0 ]; then
  # Inject archetype preset constraints into constraints.json
  echo "${ARCHETYPE_CONSTRAINTS}" | jq -c '.[]' 2>/dev/null | while IFS= read -r c; do
    write_constraint "${c}" 2>/dev/null || true
  done || true  # while-read returns 1 on EOF; prevent set -e exit
fi

# ── System Detection (delegates to _common.sh) ───────────
# Keywords are defined once in _common.sh; detect_* functions are the single source of truth.

detect_system "${QUERY}" > /dev/null
DETECTED_SYSTEMS="${_EW_DETECTED_SYSTEMS}"
SYSTEMS=()
DB_MATCH=0; BE_MATCH=0; IF_MATCH=0; SE_MATCH=0

if [[ "${DETECTED_SYSTEMS}" == *"DB"* ]]; then SYSTEMS+=("DB"); DB_MATCH=1; fi
if [[ "${DETECTED_SYSTEMS}" == *"BE"* ]]; then SYSTEMS+=("BE"); BE_MATCH=1; fi
if [[ "${DETECTED_SYSTEMS}" == *"IF"* ]]; then SYSTEMS+=("IF"); IF_MATCH=1; fi
if [[ "${DETECTED_SYSTEMS}" == *"SE"* ]]; then SYSTEMS+=("SE"); SE_MATCH=1; fi

# ── DB Domain Detection (only if DB matched) ─────────────

DOMAINS=()
if [ "${DB_MATCH}" -eq 1 ]; then
  DETECTED_DOMAINS=$(detect_db_domain "${QUERY}")
  if [ "${DETECTED_DOMAINS}" != "UNKNOWN" ]; then
    for d in ${DETECTED_DOMAINS}; do
      DOMAINS+=("${d}")
    done
  fi
fi

# ── BE Cluster Detection (only if BE matched) ────────────

BE_CLUSTERS=()
if [ "${BE_MATCH}" -eq 1 ]; then
  DETECTED_CLUSTERS=$(detect_be_cluster "${QUERY}")
  if [ "${DETECTED_CLUSTERS}" != "UNKNOWN" ]; then
    for c in ${DETECTED_CLUSTERS}; do
      BE_CLUSTERS+=("${c}")
    done
  fi
fi

# ── SE Cluster Detection (only if SE matched) ────────────

SE_CLUSTERS=()
if [ "${SE_MATCH}" -eq 1 ]; then
  DETECTED_SE_CLUSTERS=$(detect_se_cluster "${QUERY}")
  if [ "${DETECTED_SE_CLUSTERS}" != "UNKNOWN" ]; then
    for c in ${DETECTED_SE_CLUSTERS}; do
      SE_CLUSTERS+=("${c}")
    done
  fi
fi

# ── Pattern Determination ─────────────────────────────────

SYSTEM_COUNT=${#SYSTEMS[@]}
if [ "${SYSTEM_COUNT}" -eq 0 ]; then
  PATTERN="none"
elif [ "${SYSTEM_COUNT}" -eq 1 ]; then
  PATTERN="single"
elif [ "${SYSTEM_COUNT}" -eq 2 ]; then
  PATTERN="multi"
else
  PATTERN="cross"
fi

# ── Build JSON arrays ─────────────────────────────────────

if [ ${#SYSTEMS[@]} -eq 0 ]; then
  SYSTEMS_JSON='[]'
else
  SYSTEMS_JSON=$(printf '%s\n' "${SYSTEMS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi

if [ ${#DOMAINS[@]} -eq 0 ]; then
  DOMAINS_JSON='[]'
else
  DOMAINS_JSON=$(printf '%s\n' "${DOMAINS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi

if [ ${#BE_CLUSTERS[@]} -eq 0 ]; then
  BE_CLUSTERS_JSON='[]'
else
  BE_CLUSTERS_JSON=$(printf '%s\n' "${BE_CLUSTERS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi

if [ ${#SE_CLUSTERS[@]} -eq 0 ]; then
  SE_CLUSTERS_JSON='[]'
else
  SE_CLUSTERS_JSON=$(printf '%s\n' "${SE_CLUSTERS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi

# ── Session Context (Enhancement 1-2) ───────────────────────
# Apply session history decay weights to cross-keyword scores before confidence calc.
# EW_PROGRESSIVE_CLASSIFICATION=0 to disable (rollback support)
CLASSIFIER="keyword-fast-path"
if [ "${EW_PROGRESSIVE_CLASSIFICATION:-1}" != "0" ]; then
  apply_session_context 2>/dev/null || true
  if [ "${_EW_SESSION_CONTEXT_APPLIED}" = "1" ]; then
    CLASSIFIER="keyword-weighted+context"
  fi
fi

if [ "${_EW_PHASE2_ACTIVE}" = "1" ] && [ "${CLASSIFIER}" = "keyword-fast-path" ]; then
  CLASSIFIER="keyword-weighted"
fi

# ── Confidence Calculation (Enhancement 1-1) ────────────────
# Uses compute_confidence() with Phase 2 weighted scores + session context

TOTAL_MATCHES=$(( DB_MATCH + BE_MATCH + IF_MATCH + SE_MATCH ))
DOMAIN_COUNT=${#DOMAINS[@]}
BE_CLUSTER_COUNT=${#BE_CLUSTERS[@]}
SE_CLUSTER_COUNT=${#SE_CLUSTERS[@]}

HAS_SUBDOMAIN=0
if [ "${DOMAIN_COUNT}" -ge 1 ] || [ "${BE_CLUSTER_COUNT}" -ge 1 ] || [ "${SE_CLUSTER_COUNT}" -ge 1 ]; then
  HAS_SUBDOMAIN=1
fi

CONFIDENCE=$(compute_confidence "${TOTAL_MATCHES}" "${HAS_SUBDOMAIN}")

# ── Progressive Classification ──────────────────────────────
if [ "${EW_PROGRESSIVE_CLASSIFICATION:-1}" != "0" ]; then
  PRIOR_BOOST="${_EW_SESSION_BOOST}"
  SUGGESTED_EXPANSIONS=$(lookup_transitions "${SYSTEMS[0]:-}" "${DOMAINS[0]:-${BE_CLUSTERS[0]:-${SE_CLUSTERS[0]:-}}}" 2>/dev/null || echo "[]")
  PREV_SIG=$([ -f "${SESSION_HISTORY}" ] && tail -1 "${SESSION_HISTORY}" 2>/dev/null | jq -r '.signature // empty' 2>/dev/null || echo "")
else
  PRIOR_BOOST="0"; SUGGESTED_EXPANSIONS="[]"; PREV_SIG=""
fi

# ── LLM Verification Flag (Enhancement 1-3) ────────────────
# Flag queries that have a classification but need LLM confirmation
NEEDS_LLM="false"
VERIFICATION_PROMPT="null"

if [ "$(awk "BEGIN{print (${CONFIDENCE} > 0.0 && ${CONFIDENCE} < 0.85)}")" = "1" ]; then
  NEEDS_LLM="true"
  if [ "${SYSTEM_COUNT}" -ge 2 ]; then
    VERIFICATION_PROMPT="\"Classify: '${QUERY}'. Detected systems: [${SYSTEMS[*]}] (confidence=${CONFIDENCE}). Confirm primary system(s) and relevance. Return JSON: {systems:[], confidence:float}\""
  elif [ "${SYSTEM_COUNT}" -eq 1 ]; then
    VERIFICATION_PROMPT="\"Classify: '${QUERY}'. Detected: ${SYSTEMS[0]} (confidence=${CONFIDENCE}). Verify classification and suggest if other systems apply. Return JSON: {systems:[], confidence:float}\""
  else
    VERIFICATION_PROMPT="\"Classify: '${QUERY}'. No system detected by keywords. Classify into [DB,BE,IF,SE]. Return JSON: {systems:[], domains:[], confidence:float}\""
  fi
fi

# ── Output JSON ───────────────────────────────────────────

OUTPUT=$(jq -n \
  --argjson systems "${SYSTEMS_JSON}" \
  --argjson domains "${DOMAINS_JSON}" \
  --argjson be_clusters "${BE_CLUSTERS_JSON}" \
  --argjson se_clusters "${SE_CLUSTERS_JSON}" \
  --arg confidence "${CONFIDENCE}" \
  --arg query "${QUERY}" \
  --arg pattern "${PATTERN}" \
  --arg classifier "${CLASSIFIER}" \
  --arg prior_boost "${PRIOR_BOOST}" \
  --argjson suggested_expansions "${SUGGESTED_EXPANSIONS}" \
  --argjson archetype_matched "${ARCHETYPE_NAMES}" \
  --argjson needs_llm_verification "${NEEDS_LLM}" \
  --argjson verification_prompt "${VERIFICATION_PROMPT}" \
  '{
    query: $query,
    systems: $systems,
    domains: $domains,
    be_clusters: $be_clusters,
    se_clusters: $se_clusters,
    pattern: $pattern,
    confidence: ($confidence | tonumber),
    classifier: $classifier,
    prior_boost: ($prior_boost | tonumber),
    suggested_expansions: $suggested_expansions,
    archetype_matched: $archetype_matched,
    needs_llm_verification: $needs_llm_verification,
    verification_prompt: $verification_prompt
  }')

echo "${OUTPUT}"

# ── Session Persistence ──────────────────────────────────

# Write to session history (non-blocking, errors suppressed)
CLASSIFICATION_JSON=$(echo "${OUTPUT}" | jq '{systems, domains, be_clusters, se_clusters, pattern, confidence}' 2>/dev/null || true)
if [ -n "${CLASSIFICATION_JSON}" ]; then
  write_session_history "${QUERY}" "${CLASSIFICATION_JSON}" "${PREV_SIG}" 2>/dev/null || true
  promote_to_cache "${QUERY_SIG}" "${CLASSIFICATION_JSON}" 2>/dev/null || true
  # Record transition for progressive classification
  if [ "${EW_PROGRESSIVE_CLASSIFICATION:-1}" != "0" ] && [ -n "${PREV_SIG}" ]; then
    record_transition "${PREV_SIG}" "${SYSTEMS[0]:-}" "${DOMAINS[0]:-${BE_CLUSTERS[0]:-}}" 2>/dev/null || true
  fi
fi
