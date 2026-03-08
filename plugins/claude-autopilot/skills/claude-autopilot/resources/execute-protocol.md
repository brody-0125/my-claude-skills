# Phase 2: Execute Loop Protocol

> 작업을 자율적으로 실행하는 메인 루프. 시간 관리와 작업 실행을 교차한다.

## Required Reads

- session-state.json (작업 목록 및 상태)
- time-management.md (이미 로드된 경우 재로드 불필요)

## ⚠️ Execute Phase Read Rules (SKILL.md Mandatory Read Protocol 적용)

Execute Phase에서 모든 파일 작업은 다음 규칙을 **반드시** 준수한다:

1. **Read-Before-Edit**: Edit/Write 전 반드시 Read로 전체 파일 읽기. 이전 루프에서 읽은 캐시 사용 금지.
2. **Full-File Read**: offset/limit 없이 전체 파일 읽기. 부분 읽기로 판단 금지.
3. **Post-Edit Verify**: Edit/Write 후 반드시 Read로 결과 검증. 도구 성공 메시지만 신뢰 금지.
4. **No Stale Context**: 컨텍스트 압축 감지 시 session-state.json + 현재 작업 파일 전체 재로드.
5. **File Inventory**: 작업당 읽은 파일 / 수정한 파일 목록을 session-state.json에 기록.

**위반 시**: 작업을 "blocked"로 표시하고 사유 기록. Read 없이 Edit한 결과는 신뢰하지 않는다.

## Execute Loop 구조

```
WHILE true:
  1. 시간 체크
  2. Directive Drift 체크
  3. 다음 작업 선택
  4. 작업 실행 (Read-Execute-Verify 패턴)
  5. 결과 검증 (강화된 검증)
  6. 상태 갱신
  7. Git 체크포인트 판단
  8. 루프 계속 판단
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

## Step 2-1.5: Directive Drift 체크

3개 작업 완료마다 또는 AWARE 이상 시간 레벨에서 매 작업 후:

```
1. session-state.json에서 원본 directive 재읽기
2. 현재 수행 중인 작업이 directive 범위 내인지 확인
3. 드리프트 감지 시:
   - 즉시 현재 작업 중단
   - 남은 작업 재검토
   - directive 범위 외 작업을 skip 처리
   - session-state.json에 drift_detected 이벤트 기록
```

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

## Step 2-3: 작업 실행 (Read-Execute-Verify 패턴)

모든 작업 유형은 **Read → Execute → Verify** 3단계를 반드시 따른다.

### 코드 수정 작업

```
1. [READ] 대상 파일 전체 읽기 (Read, offset/limit 없이)
   - 읽은 파일 경로를 file_inventory에 기록
2. [PLAN] 변경 사항 계획 수립
   - 원본 directive와 대조하여 범위 확인
3. [EXECUTE] 코드 수정 (Edit/Write)
   - Edit 사용 시 old_string이 Step 1에서 읽은 내용과 정확히 일치하는지 확인
4. [VERIFY] 수정된 파일 전체 다시 읽기 (Read)
   - 의도한 변경만 적용되었는지 확인
   - 예상치 못한 변경 감지 시 → 즉시 롤백 후 재시도
5. [RECORD] 수정된 파일을 files_changed에 기록
```

### 테스트 작성 작업

```
1. [READ] 대상 소스 코드 전체 읽기
2. [READ] 기존 테스트 파일 전체 읽기 (있을 경우)
   - 테스트 패턴, 네이밍 컨벤션, import 스타일 파악
3. [EXECUTE] 테스트 코드 생성 (Write)
4. [VERIFY] 생성된 테스트 파일 전체 읽기
5. [RUN] 테스트 실행 (Bash) → 결과 확인
   - 실패 시: 에러 메시지 분석 → 테스트 파일 재읽기 → 수정 → 재실행
```

### 리팩토링 작업

```
1. [READ] 대상 코드 전체 읽기 + 관련 파일 전체 읽기
   - 리팩토링 영향 범위의 모든 파일을 사전 읽기
2. [PLAN] 리팩토링 계획 수립 (단계별)
3. [EXECUTE] 단계적 리팩토링 실행
   - 각 단계마다: Read → Edit → Read(Verify) 반복
4. [VERIFY] 기존 테스트 통과 확인
   - 실패 시: 변경된 파일 전체 재읽기 후 수정
```

### Gran-Maestro REQ 실행

```
1. [READ] REQ 디렉터리의 request.json 전체 읽기
2. [READ] spec.md 전체 읽기
3. [CHECK] REQ 상태 확인
   - 미승인 시: Skill(skill: "mst:approve", args: "REQ-NNN --continue")
4. [EXECUTE] spec.md의 task 목록에 따라 구현
   - 각 task마다 Read-Execute-Verify 패턴 적용
5. [VERIFY] 모든 task 완료 확인
6. [UPDATE] REQ 상태 갱신
```

## Step 2-4: 결과 검증 (강화)

작업 완료 후 **반드시** 다음을 모두 검증한다. 검증 단계를 건너뛸 수 없다.

### 필수 검증 체크리스트

```
■ 수정된 모든 파일을 Read로 전체 재읽기 완료
■ 수정된 파일이 문법적으로 유효한가 (lint/compile 확인)
■ Pre-Execution Baseline 대비 기존 테스트가 깨지지 않았는가
■ 새로 추가된 테스트가 통과하는가
■ 작업 목표가 directive 범위 내에서 달성되었는가
■ 의도하지 않은 파일 변경이 없는가 (git diff --stat 확인)
```

### 검증 실패 시

```
IF 문법 에러:
  수정 대상 파일 전체 재읽기 → 수정 시도 (1회)
IF 테스트 실패:
  실패한 테스트 파일 + 수정된 소스 파일 전체 재읽기
  실패 원인 분석 → 수정 시도 (최대 2회)
IF 의도하지 않은 파일 변경:
  git diff로 변경 내용 확인 → 불필요한 변경 롤백
IF 3회 연속 실패:
  작업을 "blocked" 상태로 표시
  구체적인 실패 사유를 session-state.json errors에 기록
  다음 작업으로 이동
```

## Step 2-5: 상태 갱신

```bash
scripts/update-task-status.sh $task_id "completed" [files...]
```

상태 표시:
```
[claude-autopilot] ✓ Task {n} complete ({duration}) | {completed}/{total} done | {remaining}m left
```

## Step 2-6: Git 체크포인트

작업 완료 후 Git 체크포인트를 생성한다 (SKILL.md Git Checkpoint Protocol 참조):

```
IF task.status == "completed":
  git add <task.files_changed 파일 목록>  # 변경된 파일만 명시적으로 지정 (git add -A 금지)
  git commit -m "autopilot: task-{id} {summary}"
  → 실패해도 다음 작업 진행 (커밋 실패는 non-blocking)
```

체크포인트는 작업 단위 롤백 가능성을 보장한다. 이후 작업에서 문제 발생 시:
```
git log --oneline -5  # 체크포인트 확인
git revert HEAD       # 마지막 작업 롤백
```

## Step 2-7: 루프 계속 판단

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
4. 각 Agent도 Mandatory Read Protocol을 준수해야 함
```

## 에러 복구

| 에러 | 대응 |
|------|------|
| 파일 읽기 실패 | 경로 재탐색 (Glob/Grep), 없으면 skip |
| 테스트 실행 실패 | 변경된 파일 + 테스트 파일 전체 재읽기 후 수정 시도 |
| 동일 에러 3회 반복 | 작업 blocked, errors에 상세 사유 기록, 다음으로 이동 |
| 컨텍스트 압축 발생 | session-state.json 전체 재로드 + 현재 작업 파일 전체 재읽기 후 루프 재개 |
| Edit old_string 불일치 | 대상 파일 전체 재읽기 → 올바른 old_string으로 재시도 |
| Directive drift 감지 | 현재 작업 중단, 남은 작업 재검토, 범위 외 작업 skip |
