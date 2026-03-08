## Autopilot Session Report

### 세션 요약
- **시작**: {started_at} → **종료**: {completed_at} (총 {duration})
- **마감**: {deadline_display}
- **완료율**: {completed}/{total} tasks ({completion_pct}%)
- **우선순위 모드**: {priority}

### 완료된 작업
| # | Task | Size | Duration | Result |
|---|------|------|----------|--------|
{completed_tasks_rows}

### 미완료 작업
| # | Task | Size | Status | 사유 |
|---|------|------|--------|------|
{incomplete_tasks_rows}

### 변경된 파일
| 파일 | Task |
|------|------|
{files_changed_rows}

### 에러 요약
{errors_section}

### 다음 세션 권장 사항
{next_session_todos}
