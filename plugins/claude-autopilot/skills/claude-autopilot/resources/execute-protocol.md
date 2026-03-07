# Phase 2: Execute Loop Protocol

> 작업을 자율적으로 실행하는 메인 루프. 시간 관리와 작업 실행을 교차한다.

## Required Reads

- session-state.json (작업 목록 및 상태)
- time-management.md (이미 로드된 경우 재로드 불필요)

## Execute Loop 구조

```
WHILE true:
  1. 시간 체크
  2. 다음 작업 선택
  3. 작업 실행
  4. 결과 검증
  5. 상태 갱신
  6. 체크포인트 판단
```

## Step 2-1: 시간 체크

매 작업 시작 전 남은 시간을 확인한다.

```bash
result=$(scripts/check-deadline.sh)
# 출력: {"remaining_seconds": N, "remaining_minutes": M, "level": "NORMAL|AWARE|CAUTION|WIND_DOWN|CRITICAL"}
```

| Level | 대응 |
|-------|------|
| NORMAL | 정상 진행 |
| AWARE | 현재 작업 크기 확인 — L/XL 시작 자제 |
| CAUTION | 새 작업 시작 금지, 현재 작업만 마무리 |
| WIND_DOWN | Phase 3으로 전환 |
| CRITICAL | 즉시 Phase 3으로 전환 |

## Step 2-2: 다음 작업 선택

작업 선택 알고리즘:

```
candidates = tasks WHERE status == "ready" AND all depends_on completed

IF priority == "quick":
  next = candidates.sort_by(size ASC).first
ELIF priority == "high":
  next = candidates.sort_by(impact DESC).first
ELSE (balanced):
  next = candidates.sort_by(dependency_order ASC).first

IF next.estimated_time > remaining_time * 0.7:
  IF next은 재분해 가능:
    next를 하위 작업으로 분해
    next = 분해된 하위 작업 중 첫 번째
  ELSE:
    next를 skip 처리
    다음 후보 선택
```

## Step 2-3: 작업 실행

선택된 작업을 실행한다. 작업 유형에 따라 실행 전략이 달라진다.

### 코드 수정 작업

```
1. 대상 파일 읽기 (Read)
2. 변경 사항 계획
3. 코드 수정 (Edit/Write)
4. 수정 결과 확인
```

### 테스트 작성 작업

```
1. 대상 소스 코드 읽기
2. 기존 테스트 패턴 파악
3. 테스트 코드 생성 (Write)
4. 테스트 실행 (Bash) → 결과 확인
```

### 리팩토링 작업

```
1. 대상 코드 분석
2. 리팩토링 계획 수립
3. 단계적 리팩토링 실행
4. 기존 테스트 통과 확인
```

### Gran-Maestro REQ 실행

```
1. REQ 상태 확인 (request.json)
2. spec.md 읽기
3. 미승인 시: Skill(skill: "mst:approve", args: "REQ-NNN --continue")
4. spec.md의 task 목록에 따라 구현
5. 구현 완료 후 REQ 상태 갱신
```

## Step 2-4: 결과 검증

작업 완료 후 결과를 검증한다.

### 검증 체크리스트

```
□ 수정된 파일이 문법적으로 유효한가
□ 기존 테스트가 깨지지 않았는가
□ 새로 추가된 테스트가 통과하는가
□ 작업 목표가 달성되었는가
```

### 검증 실패 시

```
IF 문법 에러:
  즉시 수정 시도 (1회)
IF 테스트 실패:
  실패 원인 분석 → 수정 시도 (최대 2회)
IF 3회 연속 실패:
  작업을 "blocked" 상태로 표시
  다음 작업으로 이동
  보고서에 blocked 사유 기록
```

## Step 2-5: 상태 갱신

```bash
scripts/update-task-status.sh $task_id "completed"
```

상태 표시:
```
[claude-autopilot] ✓ Task {n} complete ({duration}) | {completed}/{total} done | {remaining}m left
```

## Step 2-6: 체크포인트 판단

```
IF time_level in [WIND_DOWN, CRITICAL]:
  → Phase 3으로 전환
ELIF all tasks completed:
  → Phase 3으로 전환 (조기 완료)
ELIF no ready tasks (all blocked or skip):
  → Phase 3으로 전환 (작업 소진)
ELSE:
  → Step 2-1로 돌아가 다음 작업
```

## 병렬 실행 (선택적)

독립적인 작업 2개가 ready 상태이고 남은 시간이 충분한 경우:

```
1. Task Agent로 병렬 실행 가능
2. 단, 동일 파일을 수정하는 작업은 순차 실행
3. 병렬 실행 시 각 작업의 시간 예산을 별도 관리
```

## 에러 복구

| 에러 | 대응 |
|------|------|
| 파일 읽기 실패 | 경로 재탐색, 없으면 skip |
| 테스트 실행 실패 | 변경 사항 분석 후 수정 시도 |
| 동일 에러 3회 반복 | 작업 blocked, 다음으로 이동 |
| 컨텍스트 압축 발생 | session-state.json 재로드 후 루프 재개 |
