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
  echo "${CACHED}" | jq --arg query "${QUERY}" '. + {query: $query, confidence: 1.0, classifier: "pattern-cache"}'
  exit 0
fi

# ── System Detection (delegates to _common.sh) ───────────
# Keywords are defined once in _common.sh; detect_* functions are the single source of truth.

DETECTED_SYSTEMS=$(detect_system "${QUERY}")
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

# ── Confidence Calculation ────────────────────────────────

TOTAL_MATCHES=$(( DB_MATCH + BE_MATCH + IF_MATCH + SE_MATCH ))
DOMAIN_COUNT=${#DOMAINS[@]}
BE_CLUSTER_COUNT=${#BE_CLUSTERS[@]}

if [ "${TOTAL_MATCHES}" -eq 0 ]; then
  CONFIDENCE="0.0"
elif [ "${TOTAL_MATCHES}" -eq 1 ] && { [ "${DOMAIN_COUNT}" -ge 1 ] || [ "${BE_CLUSTER_COUNT}" -ge 1 ]; }; then
  CONFIDENCE="0.85"
elif [ "${TOTAL_MATCHES}" -eq 1 ]; then
  CONFIDENCE="0.70"
else
  # 2+ system matches → multi-system, lower confidence
  CONFIDENCE="0.60"
fi

# ── Output JSON ───────────────────────────────────────────

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

OUTPUT=$(jq -n \
  --argjson systems "${SYSTEMS_JSON}" \
  --argjson domains "${DOMAINS_JSON}" \
  --argjson be_clusters "${BE_CLUSTERS_JSON}" \
  --arg confidence "${CONFIDENCE}" \
  --arg query "${QUERY}" \
  '{
    query: $query,
    systems: $systems,
    domains: $domains,
    be_clusters: $be_clusters,
    confidence: ($confidence | tonumber),
    classifier: "keyword-fast-path"
  }')

echo "${OUTPUT}"

# ── Session Persistence ──────────────────────────────────

# Write to session history (non-blocking, errors suppressed)
CLASSIFICATION_JSON=$(echo "${OUTPUT}" | jq '{systems, domains, be_clusters, confidence}' 2>/dev/null || true)
if [ -n "${CLASSIFICATION_JSON}" ]; then
  write_session_history "${QUERY}" "${CLASSIFICATION_JSON}" 2>/dev/null || true
  promote_to_cache "${QUERY_SIG}" "${CLASSIFICATION_JSON}" 2>/dev/null || true
fi
