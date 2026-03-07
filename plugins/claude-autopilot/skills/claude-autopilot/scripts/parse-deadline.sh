#!/usr/bin/env bash
# parse-deadline.sh — 마감 시간 파싱 → epoch timestamp 변환
# Usage: ./parse-deadline.sh "15:30"
#        ./parse-deadline.sh "+30m"
#        ./parse-deadline.sh "+2h"
#        ./parse-deadline.sh "2026-03-08 09:00"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

input="${1:-}"

if [ -z "$input" ]; then
  log_error "Usage: parse-deadline.sh <time-expression>"
  log_error "  Examples: 15:30, +30m, +2h, '2026-03-08 09:00'"
  exit 1
fi

now=$(now_epoch)

# ── Pattern 1: +Nm (분 단위 상대 시간) ─────────────────────────────────
if [[ "$input" =~ ^\+([0-9]+)m$ ]]; then
  minutes="${BASH_REMATCH[1]}"
  deadline=$(( now + minutes * 60 ))
  echo "$deadline"
  exit 0
fi

# ── Pattern 2: +Nh (시간 단위 상대 시간) ────────────────────────────────
if [[ "$input" =~ ^\+([0-9]+)h$ ]]; then
  hours="${BASH_REMATCH[1]}"
  deadline=$(( now + hours * 3600 ))
  echo "$deadline"
  exit 0
fi

# ── Pattern 3: HH:MM (오늘 또는 내일) ──────────────────────────────────
if [[ "$input" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
  hour="${BASH_REMATCH[1]}"
  minute="${BASH_REMATCH[2]}"

  # 오늘 날짜로 epoch 계산
  today=$(date +%Y-%m-%d)
  deadline=$(date -d "${today} ${hour}:${minute}:00" +%s 2>/dev/null) || \
    deadline=$(date -j -f "%Y-%m-%d %H:%M:%S" "${today} ${hour}:${minute}:00" +%s 2>/dev/null) || {
      log_error "Failed to parse time: ${input}"
      exit 1
    }

  # 이미 지난 시간이면 내일로
  if [ "$deadline" -le "$now" ]; then
    deadline=$(( deadline + 86400 ))
  fi

  echo "$deadline"
  exit 0
fi

# ── Pattern 4: YYYY-MM-DD HH:MM (절대 시간) ────────────────────────────
if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{1,2}:[0-9]{2}$ ]]; then
  deadline=$(date -d "${input}:00" +%s 2>/dev/null) || \
    deadline=$(date -j -f "%Y-%m-%d %H:%M:%S" "${input}:00" +%s 2>/dev/null) || {
      log_error "Failed to parse datetime: ${input}"
      exit 1
    }

  if [ "$deadline" -le "$now" ]; then
    log_error "Deadline is in the past: ${input}"
    exit 1
  fi

  echo "$deadline"
  exit 0
fi

# ── Pattern 5: 자연어 (분/시간 패턴) ───────────────────────────────────
# "30분", "1시간", "30분 후", "1시간 뒤"
if [[ "$input" =~ ([0-9]+)분 ]]; then
  minutes="${BASH_REMATCH[1]}"
  deadline=$(( now + minutes * 60 ))
  echo "$deadline"
  exit 0
fi

if [[ "$input" =~ ([0-9]+)시간 ]]; then
  hours="${BASH_REMATCH[1]}"
  deadline=$(( now + hours * 3600 ))
  echo "$deadline"
  exit 0
fi

# ── 파싱 실패 ──────────────────────────────────────────────────────────
log_error "Cannot parse deadline: '${input}'"
log_error "Supported formats: HH:MM, +Nm, +Nh, 'YYYY-MM-DD HH:MM', N분, N시간"
exit 1
