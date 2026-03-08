# Phase 4: Report Protocol

> 세션 종료 시 최종 보고서를 생성하고 출력한다.

## Required Reads

- session-state.json (전체 세션 상태)

## Step 4-1: 세션 통계 집계

```
completed_count = tasks WHERE status == "completed"
partial_count = tasks WHERE status == "in_progress"
blocked_count = tasks WHERE status == "blocked"
skipped_count = tasks WHERE status == "skip"
total_duration = completed_at - started_at
```

## Step 4-2: 변경 파일 목록 수집

```
1. 완료된 작업의 files_changed 합산
2. git diff --name-only로 실제 변경 파일 교차 확인
3. 파일별 변경 라인 수 집계
```

## Step 4-3: 보고서 생성

### 보고서 형식

```markdown
## Autopilot Session Report

### 세션 요약
- **시작**: {start_time} → **종료**: {end_time} (총 {duration})
- **마감**: {deadline_display}
- **완료율**: {completed}/{total} tasks ({percentage}%)
- **우선순위 모드**: {priority}

### 완료된 작업
| # | Task | Size | Duration | Result |
|---|------|------|----------|--------|
| 1 | {description} | M | 4m 23s | ✓ success |
| 2 | {description} | S | 2m 10s | ✓ success |

### 미완료 작업
| # | Task | Size | Status | 사유 |
|---|------|------|--------|------|
| 3 | {description} | L | partial (40%) | 시간 부족 |
| 4 | {description} | M | blocked | 연쇄 에러 |

### 변경된 파일
| 파일 | 변경 | Task |
|------|------|------|
| `src/api/OrderController.kt` | +32 -8 | #1 |
| `test/api/OrderControllerTest.kt` | +45 -0 | #2 |

### 다음 세션 권장 사항
- [ ] {미완료 작업 1 — 구체적 다음 단계 포함}
- [ ] {blocked 작업 — 원인과 해결 방향 포함}
```

### Gran-Maestro 연동 보고서 (해당 시)

```markdown
### Gran-Maestro 처리 현황
| REQ | Status | Tasks | 완료율 |
|-----|--------|-------|--------|
| REQ-001 | completed | 3/3 | 100% |
| REQ-003 | partial | 2/5 | 40% |
| REQ-005 | pending | 0/4 | 0% (시간 부족) |
```

## Step 4-4: 세션 상태 아카이브

```
1. session-state.json의 status를 "completed"로 갱신
2. 히스토리 디렉토리에 복사
3. 시간 추정 통계 업데이트 (estimation-stats.json)
```

### 시간 추정 통계 업데이트

```json
{
  "sessions": [
    {
      "session_id": "ap-20260307-153000",
      "tasks": [
        {"size": "M", "estimated_minutes": 10, "actual_minutes": 8},
        {"size": "S", "estimated_minutes": 3, "actual_minutes": 4}
      ]
    }
  ],
  "calibration": {
    "S": {"avg_ratio": 1.1, "samples": 12},
    "M": {"avg_ratio": 0.85, "samples": 8},
    "L": {"avg_ratio": 1.3, "samples": 4},
    "XL": {"avg_ratio": 1.5, "samples": 2}
  }
}
```

## Step 4-5: 보고서 출력

보고서를 사용자에게 직접 출력한다 (파일로 저장하지 않음).
단, `--save-report` 옵션이 있으면 `.claude-autopilot/reports/` 디렉토리에 저장.
