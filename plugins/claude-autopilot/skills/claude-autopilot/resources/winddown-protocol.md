# Phase 3: Wind-down Protocol

> 마감 시간 임박 시 안전하게 작업을 마무리하는 절차.

## Required Reads

- session-state.json (현재 작업 상태)

## 진입 조건

다음 중 하나라도 충족 시 Phase 3에 진입:

1. `time_level == WIND_DOWN` (남은 시간 5-15%)
2. `time_level == CRITICAL` (남은 시간 < 5%)
3. 모든 작업 완료 (조기 종료)
4. 모든 남은 작업이 blocked/skip (작업 소진)

## Step 3-1: 현재 작업 완료 판단

```
IF 현재 작업 진행 중:
  남은 예상 시간 = 작업 시작 후 경과 시간 기반 추정
  IF 남은 예상 시간 < wind_down_reserve * 0.5:
    → 작업 완료까지 진행
  ELSE:
    → 안전 지점까지만 진행 후 중단
```

### 안전 지점 정의

| 작업 유형 | 안전 지점 |
|----------|----------|
| 파일 수정 | 현재 파일의 수정을 완료 (문법적으로 유효한 상태) |
| 테스트 작성 | 현재 테스트 메서드 완료 (컴파일 가능 상태) |
| 리팩토링 | 현재 단계 완료 (기존 테스트 통과 상태) |
| Gran-Maestro REQ | 현재 task 완료 (REQ 상태를 partial로 기록) |

## Step 3-2: 코드 일관성 확보

**⚠️ Wind-down 중에도 Mandatory Read Protocol을 준수한다.**
시간이 부족하더라도 Edit 전 Read, Edit 후 Verify는 생략 불가.

```
1. 편집 중인 모든 파일을 Read로 전체 재읽기
2. 문법적으로 유효한지 확인 (lint/compile)
3. 불완전한 수정이 있으면:
   a. 완성 가능하면: Read → Edit → Read(Verify) 수행
   b. 완성 불가능하면 변경 전 상태로 되돌림 (git checkout -- <file>)
4. import 문, 중괄호, 들여쓰기 등 기본 문법 확인
5. file_inventory에서 verified=false인 파일이 있으면 경고 출력
```

## Step 3-3: 미완료 작업 기록

session-state.json에 미완료 작업 정보를 상세히 기록:

```json
{
  "incomplete_tasks": [
    {
      "id": 3,
      "description": "PaymentService 리팩토링",
      "reason": "시간 부족",
      "progress": "40% — 인터페이스 분리 완료, 구현 미완료",
      "next_steps": ["PaymentAdapter 구현", "PaymentServiceTest 업데이트"],
      "files_partially_changed": ["src/payment/PaymentService.kt"]
    }
  ]
}
```

## Step 3-4: 임시 파일 정리

```
1. 작업 중 생성된 임시 파일 탐색 (.tmp, .bak, .swp 등)
2. 불필요한 파일 삭제
3. 단, 사용자가 의도적으로 생성한 파일은 보존
```

## Step 3-5: Gran-Maestro 상태 정리

gran-maestro 연동 모드에서 Wind-down 시:

```
1. 진행 중인 REQ의 상태를 적절히 업데이트
   - 완료된 task는 completed 표시
   - 미완료 task는 in_progress 유지
2. REQ를 force-complete하지 않음
3. 다음 autopilot 세션에서 이어서 처리 가능하도록 상태 보존
```

## Step 3-6: Wind-down 완료 알림

```
[claude-autopilot] Wind-down complete
  Completed: {n}/{total} tasks
  In-progress: {m} (safely paused)
  Remaining: {k} (not started)
  Proceeding to report...
```
