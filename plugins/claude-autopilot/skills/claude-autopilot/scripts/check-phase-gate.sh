#!/usr/bin/env bash
# check-phase-gate.sh — Phase 전환 전 Gate Check 수행
# Usage: ./check-phase-gate.sh <from_phase> <to_phase>
# 출력: JSON { "pass": true/false, "failures": [...] }

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

from_phase="${1:-}"
to_phase="${2:-}"

if [ -z "$from_phase" ] || [ -z "$to_phase" ]; then
  log_error "Usage: check-phase-gate.sh <from_phase> <to_phase>"
  exit 1
fi

if [ ! -f "$AUTOPILOT_STATE_FILE" ]; then
  log_error "No active session found"
  echo '{"pass":false,"failures":["no_active_session"]}'
  exit 1
fi

failures=()

# ── Phase 0 → Phase 1 (Parse → Decompose) ────────────────────────────────
if [ "$from_phase" = "0" ] && [ "$to_phase" = "1" ]; then
  # session-state.json 존재 확인
  session_id=$(json_read "$AUTOPILOT_STATE_FILE" ".session_id")
  [ -z "$session_id" ] && failures+=("session_id_missing")

  # directive 존재 확인
  directive=$(json_read "$AUTOPILOT_STATE_FILE" ".directive")
  [ -z "$directive" ] && failures+=("directive_missing")

  # deadline 설정 확인
  deadline=$(json_read "$AUTOPILOT_STATE_FILE" ".deadline_epoch")
  if [ -z "$deadline" ] || [ "$deadline" = "null" ]; then
    failures+=("deadline_not_set")
  fi

  # time_budget 확인
  exec_avail=$(json_read "$AUTOPILOT_STATE_FILE" ".time_budget.execution_available")
  if [ -z "$exec_avail" ] || [ "$exec_avail" = "0" ]; then
    failures+=("no_execution_time")
  fi
fi

# ── Phase 1 → Phase 2 (Decompose → Execute) ──────────────────────────────
if [ "$from_phase" = "1" ] && [ "$to_phase" = "2" ]; then
  # tasks 배열이 비어있지 않은지 확인
  task_count=$(jq '.tasks | length' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "0")
  [ "$task_count" -eq 0 ] && failures+=("no_tasks_defined")

  # total_tasks 설정 확인
  total=$(jq '.total_tasks // 0' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "0")
  [ "$total" -eq 0 ] && failures+=("total_tasks_zero")

  # 모든 task에 id, size, status 필드 존재 확인
  invalid_tasks=$(jq '[.tasks[] | select(.id == null or .size == null or .status == null)] | length' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "0")
  [ "$invalid_tasks" -gt 0 ] && failures+=("tasks_missing_required_fields:${invalid_tasks}")

  # ready 상태 task가 하나 이상 존재
  ready_count=$(jq '[.tasks[] | select(.status == "ready")] | length' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "0")
  [ "$ready_count" -eq 0 ] && failures+=("no_ready_tasks")
fi

# ── Phase 2 → Phase 3 (Execute → Wind-down) ──────────────────────────────
if [ "$from_phase" = "2" ] && [ "$to_phase" = "3" ]; then
  # 최소 1개 작업이 완료/blocked/skip 상태 (루프가 실행되었음을 증명)
  processed=$(jq '[.tasks[] | select(.status == "completed" or .status == "blocked" or .status == "skip")] | length' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "0")
  [ "$processed" -eq 0 ] && failures+=("no_tasks_processed")

  # last_activity가 설정되어 있는지
  last_activity=$(json_read "$AUTOPILOT_STATE_FILE" ".last_activity")
  [ -z "$last_activity" ] && failures+=("no_last_activity")
fi

# ── Phase 3 → Phase 4 (Wind-down → Report) ───────────────────────────────
if [ "$from_phase" = "3" ] && [ "$to_phase" = "4" ]; then
  # in_progress 상태 task가 없어야 함 (wind-down이 정리해야 함)
  in_progress=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$AUTOPILOT_STATE_FILE" 2>/dev/null || echo "0")
  [ "$in_progress" -gt 0 ] && failures+=("tasks_still_in_progress:${in_progress}")
fi

# ── 결과 출력 ─────────────────────────────────────────────────────────────
if [ ${#failures[@]} -eq 0 ]; then
  jq -n --arg from "$from_phase" --arg to "$to_phase" \
    '{"pass": true, "from_phase": ($from|tonumber), "to_phase": ($to|tonumber), "failures": []}'
  log_info "Phase gate ${from_phase}→${to_phase}: PASS"
else
  failures_json=$(printf '%s\n' "${failures[@]}" | jq -R . | jq -s .)
  jq -n --arg from "$from_phase" --arg to "$to_phase" --argjson failures "$failures_json" \
    '{"pass": false, "from_phase": ($from|tonumber), "to_phase": ($to|tonumber), "failures": $failures}'
  log_warn "Phase gate ${from_phase}→${to_phase}: FAIL (${#failures[@]} issues)"
fi
