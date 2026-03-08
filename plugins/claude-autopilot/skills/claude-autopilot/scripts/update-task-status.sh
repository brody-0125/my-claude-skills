#!/usr/bin/env bash
# update-task-status.sh — 작업 상태 갱신
# Usage: ./update-task-status.sh <task_id> <status> [files_changed...]
# status: ready, in_progress, completed, blocked, skip

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

task_id="${1:-}"
new_status="${2:-}"
shift 2 2>/dev/null || true
files_changed=("${@+$@}")

if [ -z "$task_id" ] || [ -z "$new_status" ]; then
  log_error "Usage: update-task-status.sh <task_id> <status> [files...]"
  exit 1
fi

if [ ! -f "$AUTOPILOT_STATE_FILE" ]; then
  log_error "No active session found"
  exit 1
fi

now_ts=$(now_iso)

# 상태별 처리
case "$new_status" in
  in_progress)
    jq --argjson id "$task_id" --arg ts "$now_ts" \
      '(.tasks[] | select(.id == $id)) |= . + {status: "in_progress", started_at: $ts}' \
      "$AUTOPILOT_STATE_FILE" > "${AUTOPILOT_STATE_FILE}.tmp" && \
      mv "${AUTOPILOT_STATE_FILE}.tmp" "$AUTOPILOT_STATE_FILE"
    ;;
  completed)
    # 파일 변경 목록 구성
    files_json="[]"
    if [ ${#files_changed[@]} -gt 0 ]; then
      files_json=$(printf '%s\n' "${files_changed[@]}" | jq -R . | jq -s .)
    fi

    jq --argjson id "$task_id" --arg ts "$now_ts" --argjson files "$files_json" \
      '(.tasks[] | select(.id == $id)) |= . + {status: "completed", completed_at: $ts, files_changed: $files} |
       .completed_tasks = ([.tasks[] | select(.status == "completed")] | length) |
       .last_activity = $ts' \
      "$AUTOPILOT_STATE_FILE" > "${AUTOPILOT_STATE_FILE}.tmp" && \
      mv "${AUTOPILOT_STATE_FILE}.tmp" "$AUTOPILOT_STATE_FILE"

    completed=$(jq '.completed_tasks // 0' "$AUTOPILOT_STATE_FILE")
    total=$(jq '.total_tasks // 0' "$AUTOPILOT_STATE_FILE")
    log_info "✓ Task ${task_id} complete | ${completed}/${total} done"
    ;;
  blocked)
    jq --argjson id "$task_id" --arg ts "$now_ts" \
      '(.tasks[] | select(.id == $id)) |= . + {status: "blocked", blocked_at: $ts} |
       .last_activity = $ts' \
      "$AUTOPILOT_STATE_FILE" > "${AUTOPILOT_STATE_FILE}.tmp" && \
      mv "${AUTOPILOT_STATE_FILE}.tmp" "$AUTOPILOT_STATE_FILE"

    log_warn "Task ${task_id} blocked"
    ;;
  skip)
    jq --argjson id "$task_id" --arg ts "$now_ts" \
      '(.tasks[] | select(.id == $id)) |= . + {status: "skip", skipped_at: $ts} |
       .last_activity = $ts' \
      "$AUTOPILOT_STATE_FILE" > "${AUTOPILOT_STATE_FILE}.tmp" && \
      mv "${AUTOPILOT_STATE_FILE}.tmp" "$AUTOPILOT_STATE_FILE"

    log_info "Task ${task_id} skipped"
    ;;
  *)
    log_error "Unknown status: ${new_status}"
    exit 1
    ;;
esac
