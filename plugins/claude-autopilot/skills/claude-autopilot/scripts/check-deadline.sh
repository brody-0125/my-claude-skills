#!/usr/bin/env bash
# check-deadline.sh — 남은 시간 확인 및 레벨 판정
# Usage: ./check-deadline.sh
# 출력: JSON { remaining_seconds, remaining_minutes, level, ... }

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

ensure_cache_dir

if [ ! -f "$AUTOPILOT_STATE_FILE" ]; then
  log_error "No active session found"
  echo '{"error":"no_session"}'
  exit 1
fi

deadline_epoch=$(json_read "$AUTOPILOT_STATE_FILE" ".deadline_epoch")
started_at_iso=$(json_read "$AUTOPILOT_STATE_FILE" ".started_at")
total_minutes_stored=$(json_read "$AUTOPILOT_STATE_FILE" ".time_budget.total_minutes")

if [ -z "$deadline_epoch" ] || [ "$deadline_epoch" = "null" ]; then
  log_error "No deadline set in session state"
  echo '{"error":"no_deadline"}'
  exit 1
fi

now=$(now_epoch)
remaining_seconds=$(( deadline_epoch - now ))
remaining_minutes=$(( remaining_seconds / 60 ))

# 총 시간 계산
total_minutes="${total_minutes_stored:-60}"
if [ "$total_minutes" -le 0 ]; then
  total_minutes=60
fi

# started_at 기반으로 경과 시간 계산 (deadline 역산보다 정확)
if [ -n "$started_at_iso" ] && [ "$started_at_iso" != "null" ]; then
  # ISO 8601 → epoch 변환
  started_at_epoch=$(date -d "$started_at_iso" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at_iso" +%s 2>/dev/null || echo "0")
  if [ "$started_at_epoch" -gt 0 ] 2>/dev/null; then
    elapsed_seconds=$(( now - started_at_epoch ))
  else
    elapsed_seconds=$(( now - (deadline_epoch - total_minutes * 60) ))
  fi
else
  elapsed_seconds=$(( now - (deadline_epoch - total_minutes * 60) ))
fi
elapsed_minutes=$(( elapsed_seconds / 60 ))

# 진행률
if [ "$total_minutes" -gt 0 ]; then
  progress_pct=$(( elapsed_minutes * 100 / total_minutes ))
else
  progress_pct=0
fi

# 남은 비율
if [ "$total_minutes" -gt 0 ]; then
  remaining_pct=$(( remaining_minutes * 100 / total_minutes ))
else
  remaining_pct=0
fi

# Level 판정
if [ "$remaining_seconds" -le 0 ]; then
  level="CRITICAL"
elif [ "$remaining_pct" -gt 50 ]; then
  level="NORMAL"
elif [ "$remaining_pct" -gt 30 ]; then
  level="AWARE"
elif [ "$remaining_pct" -gt 15 ]; then
  level="CAUTION"
elif [ "$remaining_pct" -gt 5 ]; then
  level="WIND_DOWN"
else
  level="CRITICAL"
fi

# Wind-down 시작 시점 (남은 시간 15% 지점)
wind_down_threshold=$(( total_minutes * 15 / 100 ))
wind_down_at=$(( deadline_epoch - wind_down_threshold * 60 ))

# JSON 출력
jq -n \
  --argjson remaining_seconds "$remaining_seconds" \
  --argjson remaining_minutes "$remaining_minutes" \
  --argjson total_minutes "$total_minutes" \
  --argjson elapsed_minutes "$elapsed_minutes" \
  --argjson progress_pct "$progress_pct" \
  --argjson remaining_pct "$remaining_pct" \
  --arg level "$level" \
  --argjson wind_down_at "$wind_down_at" \
  --argjson deadline_epoch "$deadline_epoch" \
  '{
    remaining_seconds: $remaining_seconds,
    remaining_minutes: $remaining_minutes,
    total_minutes: $total_minutes,
    elapsed_minutes: $elapsed_minutes,
    progress_pct: $progress_pct,
    remaining_pct: $remaining_pct,
    level: $level,
    wind_down_at: $wind_down_at,
    deadline_epoch: $deadline_epoch
  }'
