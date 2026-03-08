#!/usr/bin/env bash
# generate-report.sh — 최종 보고서 JSON 생성
# Usage: ./generate-report.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

if [ ! -f "$AUTOPILOT_STATE_FILE" ]; then
  log_error "No active session found"
  exit 1
fi

now_ts=$(now_iso)

# 통계 집계
completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "$AUTOPILOT_STATE_FILE")
blocked=$(jq '[.tasks[] | select(.status == "blocked")] | length' "$AUTOPILOT_STATE_FILE")
skipped=$(jq '[.tasks[] | select(.status == "skip")] | length' "$AUTOPILOT_STATE_FILE")
in_progress=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$AUTOPILOT_STATE_FILE")
total=$(jq '.total_tasks // 0' "$AUTOPILOT_STATE_FILE")

if [ "$total" -gt 0 ]; then
  completion_pct=$(( completed * 100 / total ))
else
  completion_pct=0
fi

# 세션 정보
session_id=$(json_read "$AUTOPILOT_STATE_FILE" ".session_id")
directive=$(json_read "$AUTOPILOT_STATE_FILE" ".directive")
started_at=$(json_read "$AUTOPILOT_STATE_FILE" ".started_at")
deadline_display=$(json_read "$AUTOPILOT_STATE_FILE" ".deadline_display")
priority=$(json_read "$AUTOPILOT_STATE_FILE" ".priority")

# 변경된 파일 목록
files_changed=$(jq '[.tasks[] | select(.status == "completed") | .files_changed[]? // empty] | unique' "$AUTOPILOT_STATE_FILE")

# 보고서 JSON 생성
jq -n \
  --arg session_id "$session_id" \
  --arg directive "$directive" \
  --arg started_at "$started_at" \
  --arg completed_at "$now_ts" \
  --arg deadline "$deadline_display" \
  --arg priority "$priority" \
  --argjson completed "$completed" \
  --argjson blocked "$blocked" \
  --argjson skipped "$skipped" \
  --argjson in_progress "$in_progress" \
  --argjson total "$total" \
  --argjson completion_pct "$completion_pct" \
  --argjson files_changed "$files_changed" \
  --argjson completed_tasks "$(jq '[.tasks[] | select(.status == "completed")]' "$AUTOPILOT_STATE_FILE")" \
  --argjson incomplete_tasks "$(jq '[.tasks[] | select(.status != "completed" and .status != "skip")]' "$AUTOPILOT_STATE_FILE")" \
  --argjson errors "$(jq '.errors // []' "$AUTOPILOT_STATE_FILE")" \
  '{
    report: {
      session_id: $session_id,
      directive: $directive,
      started_at: $started_at,
      completed_at: $completed_at,
      deadline: $deadline,
      priority: $priority,
      summary: {
        completed: $completed,
        blocked: $blocked,
        skipped: $skipped,
        in_progress: $in_progress,
        total: $total,
        completion_pct: $completion_pct
      },
      completed_tasks: $completed_tasks,
      incomplete_tasks: $incomplete_tasks,
      files_changed: $files_changed,
      errors: $errors
    }
  }'

# 시간 추정 통계 업데이트
if [ -f "$AUTOPILOT_STATS_FILE" ]; then
  # 기존 통계에 현재 세션 추가
  # strptime은 이식성 문제가 있으므로 date 명령으로 epoch 변환 후 계산
  session_stats="[]"
  while IFS= read -r tid; do
    [ -z "$tid" ] && continue
    t_start=$(jq -r --argjson id "$tid" '.tasks[] | select(.id == $id) | .started_at' "$AUTOPILOT_STATE_FILE")
    t_end=$(jq -r --argjson id "$tid" '.tasks[] | select(.id == $id) | .completed_at' "$AUTOPILOT_STATE_FILE")
    t_size=$(jq -r --argjson id "$tid" '.tasks[] | select(.id == $id) | .size' "$AUTOPILOT_STATE_FILE")
    t_est=$(jq -r --argjson id "$tid" '.tasks[] | select(.id == $id) | .allocated_minutes // 0' "$AUTOPILOT_STATE_FILE")
    start_epoch=$(date -d "$t_start" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$t_start" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -d "$t_end" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$t_end" +%s 2>/dev/null || echo "0")
    if [ "$start_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
      actual_min=$(( (end_epoch - start_epoch) / 60 ))
    else
      actual_min=0
    fi
    session_stats=$(echo "$session_stats" | jq --arg s "$t_size" --argjson e "$t_est" --argjson a "$actual_min" \
      '. + [{size: $s, estimated_minutes: $e, actual_minutes: $a}]')
  done <<< "$(jq -r '.tasks[] | select(.status == "completed" and .started_at != null and .completed_at != null) | .id' "$AUTOPILOT_STATE_FILE" 2>/dev/null)"

  jq --argjson new_session "$session_stats" --arg sid "$session_id" \
    '.sessions += [{session_id: $sid, tasks: $new_session}] | .sessions = .sessions[-5:]' \
    "$AUTOPILOT_STATS_FILE" > "${AUTOPILOT_STATS_FILE}.tmp" 2>/dev/null && \
    mv "${AUTOPILOT_STATS_FILE}.tmp" "$AUTOPILOT_STATS_FILE" || true
else
  # 통계 파일 신규 생성
  session_stats=$(jq '[.tasks[] | select(.status == "completed") | {
    size: .size,
    estimated_minutes: (.allocated_minutes // 0),
    actual_minutes: 0
  }]' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "[]")

  jq -n --argjson tasks "$session_stats" --arg sid "$session_id" \
    '{sessions: [{session_id: $sid, tasks: $tasks}], calibration: {S: {avg_ratio: 1.0, samples: 0}, M: {avg_ratio: 1.0, samples: 0}, L: {avg_ratio: 1.0, samples: 0}, XL: {avg_ratio: 1.0, samples: 0}}}' \
    > "$AUTOPILOT_STATS_FILE" 2>/dev/null || true
fi

log_info "Report generated for session ${session_id}"
