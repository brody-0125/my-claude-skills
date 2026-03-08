#!/usr/bin/env bash
# _common.sh — claude-autopilot 공유 유틸리티
# 다른 스크립트에서 source하여 사용. 직접 실행 불가.

set -euo pipefail

# ── 캐시 디렉토리 ──────────────────────────────────────────────────────
AUTOPILOT_CACHE_DIR="${HOME}/.claude/cache/claude-autopilot"
AUTOPILOT_STATE_FILE="${AUTOPILOT_CACHE_DIR}/session-state.json"
AUTOPILOT_HISTORY_DIR="${AUTOPILOT_CACHE_DIR}/history"
AUTOPILOT_STATS_FILE="${AUTOPILOT_CACHE_DIR}/estimation-stats.json"

ensure_cache_dir() {
  mkdir -p "$AUTOPILOT_CACHE_DIR"
  mkdir -p "$AUTOPILOT_HISTORY_DIR"
}

# ── 시간 유틸리티 ──────────────────────────────────────────────────────
now_epoch() {
  date +%s
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

epoch_to_display() {
  local epoch="$1"
  date -d "@${epoch}" +"%H:%M" 2>/dev/null || date -r "${epoch}" +"%H:%M" 2>/dev/null || echo "unknown"
}

minutes_between() {
  local from="$1" to="$2"
  echo $(( (to - from) / 60 ))
}

# ── JSON 유틸리티 ──────────────────────────────────────────────────────
json_read() {
  local file="$1" key="$2"
  jq -r "${key} // empty" "$file" 2>/dev/null || echo ""
}

json_write() {
  local file="$1" key="$2" value="$3"
  local tmp="${file}.tmp"
  jq --arg k "$key" --arg v "$value" '. + {($k): $v}' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file"
}

json_write_num() {
  local file="$1" key="$2" value="$3"
  local tmp="${file}.tmp"
  jq --arg k "$key" --argjson v "$value" '. + {($k): $v}' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file"
}

# ── 세션 상태 유틸리티 ──────────────────────────────────────────────────
read_state() {
  local key="$1"
  if [ -f "$AUTOPILOT_STATE_FILE" ]; then
    json_read "$AUTOPILOT_STATE_FILE" "$key"
  fi
}

write_state() {
  local key="$1" value="$2"
  if [ -f "$AUTOPILOT_STATE_FILE" ]; then
    json_write "$AUTOPILOT_STATE_FILE" "$key" "$value"
  fi
}

# ── 프로그레스 바 생성 ──────────────────────────────────────────────────
progress_bar() {
  local pct="$1" width="${2:-10}"
  if [ "$pct" -lt 0 ] 2>/dev/null; then pct=0; fi
  if [ "$pct" -gt 100 ] 2>/dev/null; then pct=100; fi
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  if [ "$filled" -gt 0 ]; then
    printf '%0.s▓' $(seq 1 $filled)
  fi
  if [ "$empty" -gt 0 ]; then
    printf '%0.s░' $(seq 1 $empty)
  fi
}

# ── 로그 ──────────────────────────────────────────────────────────────
log_info() {
  echo "[claude-autopilot] $*"
}

log_warn() {
  echo "[claude-autopilot] WARNING: $*"
}

log_error() {
  echo "[claude-autopilot] ERROR: $*"
}
