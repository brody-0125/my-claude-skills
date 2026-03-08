# Phase 1: Decompose Protocol

> 사용자 지침을 구체적 작업 목록으로 분해하고 시간 예산을 배분한다.

## Required Reads

- session-state.json (Phase 0에서 생성)
- time-management.md (시간 예산 알고리즘 참조)

## Step 1: 지침 분석

사용자 directive를 분석하여 작업 후보를 식별한다.

### 분석 전략 (지침 유형별)

| 유형 | 판별 기준 | 분해 방법 |
|------|----------|----------|
| **명시적 목록** | 번호 매기기, "그리고", 콤마 구분 | 각 항목 → 독립 task |
| **범위 지정** | "모든 TODO", "src/ 아래", 파일 패턴 | Glob/Grep으로 대상 탐색 → 파일별 task |
| **목표 지향** | "성능 개선", "코드 품질" | 코드 분석 → 개선 포인트 자동 발견 |
| **gran-maestro PLN** | PLN-NNN 참조 | plan.md의 요구사항 → task 매핑 |
| **gran-maestro REQ** | REQ-NNN 참조 | spec.md의 task 목록 → 그대로 사용 |

### 코드 분석 기반 작업 발견 (목표 지향 시)

```
1. Grep으로 패턴 탐색 (TODO, FIXME, deprecated, 미사용 import 등)
2. 파일 크기/복잡도 기반 리팩토링 후보 식별
3. 테스트 커버리지 갭 탐색 (테스트 없는 소스 파일)
4. 발견된 항목을 priority 기준으로 정렬
```

## Step 2: 의존성 분석

작업 간 의존 관계를 파악하여 DAG를 구성한다.

```
의존성 규칙:
1. 인터페이스/타입 정의 → 구현 코드 (정의 먼저)
2. 소스 코드 변경 → 해당 테스트 (소스 먼저)
3. 기반 모듈 → 의존 모듈 (기반 먼저)
4. 데이터 모델 → API/서비스 (모델 먼저)
5. 독립적 작업 → 병렬 실행 가능 표시
```

## Step 3: 규모 추정

각 작업의 예상 규모를 산정한다.

| Size | 기준 | 기본 시간 |
|------|------|----------|
| **S** | 파일 1개, 변경 < 20줄 | 3분 |
| **M** | 파일 2-5개, 변경 20-100줄 | 10분 |
| **L** | 파일 5-10개, 변경 100-300줄 | 20분 |
| **XL** | 파일 10+개, 변경 300줄+ | 40분 |

### 이전 세션 학습 반영

```
IF 히스토리 통계 존재 (~/.claude/cache/claude-autopilot/estimation-stats.json):
  보정 계수 = 최근 5세션의 평균(실제/추정)
  보정된 시간 = 기본 시간 × 보정 계수
ELSE:
  기본 시간 사용 (첫 세션)
```

## Step 4: 시간 예산 배분

`resources/time-management.md`의 알고리즘에 따라 시간을 배분한다.

```
1. 총 실행 가용 시간 계산
2. 작업 목록을 의존성 순서로 정렬
3. priority 모드에 따라 시간 배분:
   - balanced: 균등 분배
   - high: 상위 작업에 집중
   - quick: 소규모 작업 우선
4. 시간 초과 작업 식별 → skip 표시
```

## Step 5: 실행 계획 출력

작업 목록을 테이블 형태로 출력한다.

```
[claude-autopilot] Task Plan ({N} tasks, {M}m budget)
  ┌─────┬──────────────────────┬──────┬───────┬────────┬──────────┐
  │  #  │ Task                 │ Size │ Time  │ Status │ Depends  │
  ├─────┼──────────────────────┼──────┼───────┼────────┼──────────┤
  │  1  │ {description}        │  S   │  3m   │ ready  │ -        │
  │  2  │ {description}        │  M   │ 10m   │ ready  │ #1       │
  │  3  │ {description}        │  M   │ 10m   │ ready  │ -        │
  │  4  │ {description}        │  L   │ 20m   │ skip?  │ #2       │
  └─────┴──────────────────────┴──────┴───────┴────────┴──────────┘
  Wind-down reserve: {W}m
  Estimated completion: {pct}% within deadline
```

## Step 5.5: 작업 완료 기준 정의 (Acceptance Criteria)

각 task에 **반드시** 완료 기준을 명시한다. 기준 없이 task를 "completed"로 표시할 수 없다.

```json
{
  "id": 1,
  "description": "OrderController 리팩토링",
  "acceptance_criteria": [
    "메서드 추출 완료 (3개 이상 private method)",
    "기존 테스트 전부 통과",
    "lint 에러 없음"
  ],
  "size": "M",
  "status": "ready"
}
```

### 자동 완료 기준 (기본값)

작업 유형에 따라 자동으로 부여되는 기본 기준:

| 작업 유형 | 자동 완료 기준 |
|----------|-------------|
| 코드 수정 | 수정된 파일이 문법적으로 유효 + 기존 테스트 통과 |
| 테스트 작성 | 테스트 파일 생성됨 + 테스트 실행 통과 |
| 리팩토링 | 기존 테스트 전부 통과 + 코드 구조 개선 확인 |
| TODO 제거 | 대상 TODO 주석 삭제됨 + 해당 코드 기능 구현됨 |
| Gran-Maestro REQ | spec.md의 모든 task 완료 |

### 완료 판정 절차

```
FOR each criterion in task.acceptance_criteria:
  IF criterion is verifiable by test/lint/compile:
    자동 검증 실행
  ELSE:
    git diff로 변경 사항 확인 → 기준 충족 여부 판단
  IF any criterion not met:
    task는 completed가 아닌 in_progress 유지
```

## Step 6: 작업 목록 저장

session-state.json의 `tasks` 배열에 작업 목록을 기록한다.

## XL 작업 재분해

가용 시간 < XL 작업 예상 시간의 80%인 경우:

```
1. XL 작업을 하위 단계로 재분해:
   - 단계 1: 기본 구조 생성 (S-M)
   - 단계 2: 핵심 로직 구현 (M-L)
   - 단계 3: 테스트 작성 (M)
   - 단계 4: 통합/리팩토링 (S-M)
2. 가용 시간 내 완료 가능한 단계만 실행 대상에 포함
3. 나머지는 "다음 세션 권장" 목록에 추가
```

## Gran-Maestro PLN 분해

PLN 기반 실행 시 추가 절차:

```
1. plan.md에서 "요구사항" / "결정사항" 섹션 추출
2. 각 요구사항 → autopilot task로 매핑
3. plan.md의 "제약 조건" → safety guardrail로 주입
4. plan.json에서 연결된 REQ 확인
   - 기존 REQ 있으면 해당 spec.md 우선 사용
   - 없으면 새 REQ 생성 예정 표시
```
