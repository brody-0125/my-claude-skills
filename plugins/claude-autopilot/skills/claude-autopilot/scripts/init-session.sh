#!/usr/bin/env bash
# init-session.sh — 세션 상태 파일 초기화
# Usage: ./init-session.sh <deadline_epoch> <directive> [priority] [scope]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

deadline_epoch="${1:-}"
directive="${2:-}"
priority="${3:-balanced}"
scope="${4:-project}"

if [ -z "$deadline_epoch" ] || [ -z "$directive" ]; then
  log_error "Usage: init-session.sh <deadline_epoch> <directive> [priority] [scope]"
  exit 1
fi

ensure_cache_dir

now=$(now_epoch)
session_id="ap-$(date +%Y%m%d-%H%M%S)"
deadline_display=$(epoch_to_display "$deadline_epoch")
total_minutes=$(minutes_between "$now" "$deadline_epoch")

# 시간 예산 계산
wind_down_reserve=$(( total_minutes * 10 / 100 ))
if [ "$wind_down_reserve" -lt 3 ]; then
  wind_down_reserve=3
fi
parse_overhead=2
execution_available=$(( total_minutes - wind_down_reserve - parse_overhead ))
if [ "$execution_available" -lt 1 ]; then
  execution_available=1
fi

# 이전 세션 아카이브 (있으면)
if [ -f "$AUTOPILOT_STATE_FILE" ]; then
  prev_session_id=$(json_read "$AUTOPILOT_STATE_FILE" ".session_id")
  if [ -n "$prev_session_id" ]; then
    cp "$AUTOPILOT_STATE_FILE" "${AUTOPILOT_HISTORY_DIR}/${prev_session_id}-state.json" 2>/dev/null || true
  fi
fi

# Gran-Maestro 감지
gran_maestro_detected="false"
project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ -d "${project_root}/.gran-maestro" ]; then
  gran_maestro_detected="true"
fi

# 세션 상태 생성
jq -n \
  --arg session_id "$session_id" \
  --arg status "in_progress" \
  --arg directive "$directive" \
  --argjson deadline_epoch "$deadline_epoch" \
  --arg deadline_display "$deadline_display" \
  --arg started_at "$(now_iso)" \
  --arg priority "$priority" \
  --arg scope "$scope" \
  --argjson total_minutes "$total_minutes" \
  --argjson wind_down_reserve "$wind_down_reserve" \
  --argjson execution_available "$execution_available" \
  --argjson parse_overhead "$parse_overhead" \
  --argjson gran_maestro "$gran_maestro_detected" \
  --arg project_root "$project_root" \
  '{
    session_id: $session_id,
    status: $status,
    directive: $directive,
    deadline_epoch: $deadline_epoch,
    deadline_display: $deadline_display,
    started_at: $started_at,
    priority: $priority,
    scope: $scope,
    time_budget: {
      total_minutes: $total_minutes,
      wind_down_reserve: $wind_down_reserve,
      execution_available: $execution_available,
      parse_overhead: $parse_overhead
    },
    gran_maestro: {
      detected: $gran_maestro,
      plans: [],
      reqs: []
    },
    project_root: $project_root,
    tasks: [],
    completed_tasks: 0,
    total_tasks: 0,
    errors: [],
    file_inventory: { read: [], modified: [] },
    last_activity: $started_at,
    time_level: "NORMAL"
  }' > "$AUTOPILOT_STATE_FILE"

log_info "Session initialized: ${session_id}"
log_info "  Directive: ${directive}"
log_info "  Deadline:  ${deadline_display} (${total_minutes}m remaining)"
log_info "  Priority:  ${priority}"
log_info "  Scope:     ${scope}"
log_info "  Gran-Maestro: ${gran_maestro_detected}"

echo "$session_id"
