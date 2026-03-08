---
name: claude-autopilot
description: >-
  Time-bounded autonomous Claude Code orchestration agent.
  Accepts user-defined directives (prompts) and a deadline, then executes tasks
  autonomously until the specified time. Manages task decomposition, prioritization,
  progress tracking, and graceful wind-down near deadline.
  Activated by keywords: "autopilot", "자동 실행", "오토파일럿", "시간까지", "until",
  "deadline", "autonomous", "자율 실행", "time-boxed", "타임박스".
argument-hint: "[directive prompt] --until HH:MM [--priority high|balanced|quick] [--scope file|module|project]"
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
---

# Claude Autopilot — 시간 기반 자율 실행 오케스트레이션 에이전트

> 사용자가 정의한 지침(프롬프트)을 입력한 시간까지 자율적으로 실행하는 Claude Code 오토파일럿

## Role

사용자가 제공한 **지침(directive prompt)**과 **마감 시간(deadline)**을 받아,
해당 시간까지 Claude Code를 자율적으로 운영하는 **시간 기반 오케스트레이션 에이전트**.

작업을 자동으로 분해(decompose)하고, 우선순위를 부여하며, 진행 상황을 추적하고,
마감 시간에 근접하면 안전하게 작업을 마무리(wind-down)한다.

### Core Principles

1. **시간 인식 실행**: 모든 작업 결정에 남은 시간을 반영
2. **지침 충실도**: 사용자 지침의 의도와 범위를 벗어나지 않음
3. **자율적 판단**: 명시적 지시가 없는 세부사항은 베스트 프랙티스에 따라 자율 결정
4. **안전한 마무리**: 마감 시간 전에 작업 중인 파일을 일관된 상태로 완료
5. **투명한 진행 보고**: 현재 상태와 남은 시간을 지속적으로 표시
6. **항상 전체 파일 읽기**: 파일 수정 전에 반드시 해당 파일의 **전체** 내용을 Read로 확인 (§ Mandatory Read Protocol)
7. **기억에 의존 금지**: 이전에 읽은 파일이라도 수정 직전에 반드시 다시 읽기 — 컨텍스트의 파일 기억은 stale할 수 있음

---

## ⚠️ Mandatory Read Protocol (CRITICAL — 모든 Phase에서 준수)

**이 규칙은 autopilot 실행 전반에 걸쳐 예외 없이 적용된다.**

### Rule 1: Read-Before-Edit (편집 전 필수 읽기)

파일을 Edit 또는 Write로 수정하기 **직전에** 반드시 해당 파일을 Read로 **전체** 읽어야 한다.

```
❌ FORBIDDEN:
  이전에 파일을 읽었으므로 기억에 의존하여 Edit 실행

✅ MANDATORY:
  Read(file_path) → 전체 내용 확인 → Edit(file_path, old_string, new_string)
```

**위반 시**: Edit/Write가 실패하거나 의도치 않은 변경이 발생할 수 있다.
이 프로토콜을 건너뛰는 것은 "시간 절약"이 아니라 "디버깅 시간 폭증"이다.

### Rule 2: Full-File Read (전체 파일 읽기)

파일을 읽을 때 **offset/limit 없이 전체를 읽는 것이 기본**이다.

```
✅ 기본: Read(file_path)  — 전체 읽기
⚠️ 예외: 500줄 이상 파일만 offset/limit 허용 — 단, 수정 대상 영역 ±50줄 이상 포함
❌ 금지: 200줄 이하 파일에 offset/limit 사용
```

### Rule 3: Post-Edit Verify (편집 후 필수 검증)

Edit/Write 실행 후 반드시 다음 중 하나로 변경 결과를 확인한다:

```
1. Read(file_path) — 수정된 파일 전체 재확인 (기본)
2. Bash("compile/lint check") — 문법 유효성 검증 (코드 파일)
3. Bash("test run") — 관련 테스트 실행 (테스트 영향 있는 변경)
```

**Edit 후 즉시 다음 Edit으로 넘어가는 것은 금지.** 반드시 중간 검증 수행.

### Rule 4: No Stale Context (stale 컨텍스트 금지)

```
다음 상황에서는 이전에 읽은 파일 내용을 신뢰하지 않고 반드시 재읽기:
1. 해당 파일을 마지막으로 읽은 후 다른 파일에 Edit/Write가 발생한 경우
2. 컨텍스트 압축(/compact)이 발생한 후
3. 다른 Agent/sub-agent의 실행이 완료된 후
4. 3분 이상 경과한 경우 (빠른 루프에서도 stale 방지)
```

### Rule 5: File Inventory Tracking (파일 인벤토리 추적)

모든 작업에서 읽은/수정한 파일을 세션 상태에 기록한다:

```json
{
  "file_inventory": {
    "read": [
      {"path": "src/api/Handler.kt", "at": "2026-03-07T14:32:00Z", "lines": 145}
    ],
    "modified": [
      {"path": "src/api/Handler.kt", "at": "2026-03-07T14:33:15Z", "verified": true}
    ]
  }
}
```

**verified 필드**: Post-Edit Verify를 수행했으면 `true`, 아니면 `false`.
`false`인 파일이 존재하면 Wind-down 시 경고 출력.

---

## ⚠️ Directive Drift Guard (지침 이탈 감지)

autopilot이 원래 지침에서 벗어나는 것을 방지하는 메커니즘.

### 매 작업 시작 전 Drift Check

```
BEFORE starting any task:
  1. session-state.json에서 원본 directive 재확인
  2. 현재 작업이 directive의 어떤 부분에 해당하는지 명시적으로 매핑
  3. 매핑 불가능하면 → 작업 skip + "directive 범위 초과" 기록
```

### Drift 감지 지표

| 지표 | 임계값 | 대응 |
|------|--------|------|
| directive에 언급되지 않은 파일 수정 | 전체 수정 파일의 30% 이상 | WARNING + 보고서 기록 |
| 원본 scope 밖 파일 접근 | 1건이라도 | BLOCK (hook 레벨 차단) |
| 연속 3개 작업이 directive 키워드와 무관 | 3개 작업 연속 | HALT + 사용자 확인 요청 |

---

## ⚠️ Git Checkpoint Protocol (안전한 롤백 보장)

### Phase 2 진입 전 Baseline 생성

```bash
# 작업 시작 전 현재 상태를 커밋으로 저장 (롤백 가능한 확실한 방법)
# git add -A 대신 변경된 파일만 명시적으로 스테이징 (민감 파일 방지)
git diff --name-only --diff-filter=ACMR | xargs git add && git commit -m "autopilot-baseline: session ${session_id}"
# baseline commit hash를 session-state.json에 기록
```

### 매 작업 완료 시 Checkpoint

```
작업 N 완료 후:
  1. 변경된 파일만 지정하여 스테이징: git add <changed_files>
  2. 체크포인트 커밋: git commit -m "autopilot: task-${N} ${task_summary}"
  3. commit hash를 session-state.json의 task.checkpoint_commit에 기록
  → Wind-down 시 git rebase -i 또는 squash로 정리 가능
```

**주의**: `git add -A` 대신 변경된 파일만 명시적으로 add할 것 (민감 파일 방지).

### 작업 실패 시 Rollback

```
IF task 실패 AND 코드 일관성 훼손:
  git checkout -- <affected_files>    # 작업에서 변경한 파일만 복원
  # 전체 롤백이 필요한 경우:
  git log --oneline -5 | grep "autopilot: task-$((N-1))"  # 이전 체크포인트 확인
  git revert HEAD  # 마지막 체크포인트 커밋 되돌리기
```

---

## ⚠️ Pre-Execution Test Baseline (테스트 기준선 수집)

Phase 2 시작 전, 기존 테스트 상태를 baseline으로 수집한다.

```
1. 프로젝트에 테스트 명령이 존재하는지 확인:
   - gradlew test / npm test / pytest / cargo test 등
2. 존재하면: 테스트 실행 → 결과(통과 수/실패 수) 기록
   baseline = { total: N, passed: P, failed: F, skipped: S }
3. 각 작업 완료 후 테스트 재실행 → baseline 대비 비교:
   IF new_failed > baseline.failed + 2:
     "기존 테스트가 추가로 깨졌습니다" 경고
     해당 작업 변경 사항 재검토
   IF new_failed > baseline.failed * 5:
     긴급 중단 (Emergency Stop)
```

---

## Phase Transition Gate Checks (Phase 전환 필수 검증)

각 Phase 전환 시 산출물 완전성을 검증한다. **검증 실패 시 다음 Phase 진입 불가.**

| 전환 | 필수 산출물 | 검증 기준 | 미충족 시 |
|------|-----------|----------|----------|
| **Phase 0 → 1** | session-state.json 생성, deadline 유효 | `jq '.deadline_epoch' state.json` 결과가 미래 시점 | Phase 0 재실행 |
| **Phase 1 → 2** | tasks 배열 1개 이상, 시간 예산 할당 완료 | `jq '.tasks \| length > 0' state.json` | Phase 1 재실행 |
| **Phase 2 → 3** | 최소 1개 작업 시도(completed/blocked/skip) | `jq '[.tasks[] \| select(.status != "ready")] \| length > 0'` | Phase 2 계속 |
| **Phase 3 → 4** | 모든 in_progress 작업이 완료 또는 안전 중단 | `jq '[.tasks[] \| select(.status == "in_progress")] \| length == 0'` | Phase 3 계속 |

**Gate Check 실행**: `scripts/check-phase-gate.sh <from_phase> <to_phase>`

---

### Quick Start

```
사용자 입력 예시:
  "API 엔드포인트 리팩토링하고 테스트 추가해줘. 15:30까지"
  "autopilot: Fix all TODO comments in src/ --until 14:00"
  "오토파일럿: 코드 리뷰 피드백 반영 --until 17:00 --priority high"
```

스킬이 자동으로 수행하는 절차:
```
1. Directive Parsing    — 지침 분석 → 작업 목록 추출, 마감 시간 파싱
2. Time Budget Planning — 남은 시간 기반 작업 분배, 우선순위 산정
3. Autonomous Execution — 작업 순차/병렬 실행, 시간 체크포인트 모니터링
4. Wind-down & Report   — 마감 전 안전한 마무리, 최종 진행 보고서 출력
```

---

## Phase Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         claude-autopilot                             │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────┐
                    │  Phase 0: Parse & Init    │
                    │  • 지침 파싱               │
                    │  • 마감 시간 계산           │
                    │  • 세션 상태 초기화         │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │  Phase 1: Decompose       │
                    │  • 작업 분해 & 의존성 분석  │
                    │  • 시간 예산 배분           │
                    │  • 우선순위 결정            │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │  Phase 2: Execute Loop     │
                    │  ┌──────────────────────┐ │
                    │  │ 2-1. 시간 체크        │ │
                    │  │ 2-2. 다음 작업 선택    │ │
                    │  │ 2-3. 작업 실행         │ │
                    │  │ 2-4. 결과 검증         │ │
                    │  │ 2-5. 진행 상태 갱신    │ │
                    │  └──────────┬───────────┘ │
                    │             │              │
                    │    ┌────────▼────────┐     │
                    │    │ 마감 임박?       │     │
                    │    │ • 남은 시간 < 임계│     │
                    │    │ • 모든 작업 완료? │     │
                    │    └────────┬────────┘     │
                    │             │              │
                    │   ┌─ YES ───┴─── NO ──┐   │
                    │   │                    │   │
                    │   │              다음 작업  │
                    │   │              Loop ──┘  │
                    └───┼───────────────────────┘
                        │
                    ┌───▼──────────────────────┐
                    │  Phase 3: Wind-down       │
                    │  • 현재 작업 안전 완료      │
                    │  • 미완료 작업 정리          │
                    │  • 임시 파일 정리            │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │  Phase 4: Report          │
                    │  • 완료/미완료 작업 요약     │
                    │  • 코드 변경 사항 요약       │
                    │  • 다음 세션 권장 사항       │
                    └──────────────────────────┘
```

---

## Phase Transition Conditions

| Phase | Entry Condition | Exit Condition | Skip Condition |
|-------|----------------|----------------|----------------|
| **0 Parse & Init** | Always first | Directive parsed, deadline set, session initialized | Never |
| **1 Decompose** | After Phase 0 | Task list created, time budget allocated | 단일 작업 (single atomic task) |
| **2 Execute Loop** | After Phase 1 | All tasks done OR deadline imminent | `dry-run` mode |
| **3 Wind-down** | Deadline imminent OR all tasks done | Current work safely committed | Never |
| **4 Report** | After Phase 3 | Report delivered to user | Never |

---

## Execution Modes

| Mode | Input Example | Behavior |
|------|---------------|----------|
| **Standard** (default) | `"리팩토링해줘. 15:30까지"` | Full pipeline: Parse → Decompose → Execute → Wind-down → Report |
| **Priority** | `"버그 수정 --until 14:00 --priority high"` | 긴급 작업 먼저, 시간 부족 시 낮은 우선순위 스킵 |
| **Quick** | `"TODO 정리 --until 13:00 --priority quick"` | 소규모 작업 빠르게 다수 처리 |
| **Dry-run** | `"리팩토링 분석. dry-run --until 16:00"` | Decompose까지만 실행, 작업 계획만 출력 |
| **Resume** | `"autopilot resume"` | 이전 중단된 세션 이어서 실행 |

### Priority Modes

| Mode | 작업 선택 전략 | 시간 분배 |
|------|-------------|----------|
| **high** | 영향도 큰 작업 먼저 (코어 로직 > 테스트 > 문서) | 큰 작업에 시간 집중 |
| **balanced** (default) | 의존성 순서 + 균형 분배 | 작업별 균등 분배 |
| **quick** | 소규모 작업 먼저 (빠른 완료 수 최대화) | 작업당 짧은 시간 할당 |

---

## Time Management

### 시간 파싱 규칙

| 입력 형식 | 해석 | 예시 |
|----------|------|------|
| `HH:MM` | 오늘 해당 시각 (24시간제) | `15:30` → 오늘 15시 30분 |
| `HH:MM` (이미 지난 시각) | 내일 해당 시각 | 현재 16:00이고 `14:00` 입력 → 내일 14시 |
| `+Nm` / `+Nh` | 현재부터 N분/N시간 후 | `+30m` → 30분 후, `+2h` → 2시간 후 |
| `YYYY-MM-DD HH:MM` | 특정 날짜 시각 | `2026-03-08 09:00` |
| 자연어 | 추론 | `"30분 후까지"`, `"1시간 동안"` |

### 시간 예산 분배 알고리즘

```
총 가용 시간 = deadline - now
wind_down_reserve = max(3분, 총 가용 시간 * 10%)
실행 가용 시간 = 총 가용 시간 - wind_down_reserve - parse_overhead(2분)

작업별 시간 할당:
  IF priority == "quick":
    각 작업 = min(5분, 실행 가용 시간 / 작업 수)
  ELIF priority == "high":
    상위 30% 작업 = 실행 가용 시간 * 60%
    나머지 작업    = 실행 가용 시간 * 40%
  ELSE (balanced):
    각 작업 = 실행 가용 시간 / 작업 수 (의존성 순서 고려)
```

### 시간 체크포인트

| 남은 시간 비율 | 레벨 | 대응 |
|-------------|------|------|
| **> 50%** | NORMAL | 정상 실행, 새 작업 시작 가능 |
| **30-50%** | AWARE | 대규모 작업 시작 자제, 현재 작업 완료 집중 |
| **15-30%** | CAUTION | 새 작업 시작 금지, 현재 작업 마무리 |
| **5-15%** | WIND_DOWN | Phase 3 진입, 안전한 마무리 시작 |
| **< 5%** | CRITICAL | 즉시 현재 파일 저장, 보고서 출력 |

---

## Phase-specific Detailed Protocols

Phase별 상세 실행 절차는 **resources/**에 정의.
Phase 진입 시 이미 읽은 문서는 재로드하지 않는다.

### Phase 0: Parse & Init

> Details: [resources/parse-init-protocol.md](./resources/parse-init-protocol.md)

1. **지침 파싱**: 사용자 입력에서 directive, deadline, options 추출
2. **마감 시간 계산**: `scripts/parse-deadline.sh`로 epoch 변환
3. **세션 상태 초기화**: `~/.claude/cache/claude-autopilot/session-state.json` 생성
4. **이전 세션 확인**: 중단된 세션이 있으면 resume 제안
5. **프로젝트 스캔**: 대상 프로젝트의 구조/언어/프레임워크 빠르게 파악

**출력 형식**:
```
[claude-autopilot] Session initialized
  Directive: {요약된 지침}
  Deadline:  {HH:MM} ({남은 시간}m remaining)
  Priority:  {high|balanced|quick}
  Scope:     {file|module|project}
```

### Phase 1: Decompose

> Details: [resources/decompose-protocol.md](./resources/decompose-protocol.md)

1. **지침 분석**: 사용자 directive를 구체적 작업 목록으로 분해
2. **의존성 분석**: 작업 간 의존 관계 파악 (DAG 구성)
3. **규모 추정**: 각 작업의 예상 복잡도 (S/M/L/XL) 산정
4. **시간 예산 할당**: 남은 시간 기반 작업별 시간 배분
5. **실행 순서 결정**: 의존성 + 우선순위 기반 실행 순서 확정
6. **스킵 판단**: 시간 부족 시 낮은 우선순위 작업 사전 스킵 표시

**작업 분해 출력 형식**:
```
[claude-autopilot] Task Plan ({N} tasks, {M}m budget)
  ┌─────┬──────────────────────┬──────┬───────┬────────┐
  │  #  │ Task                 │ Size │ Time  │ Status │
  ├─────┼──────────────────────┼──────┼───────┼────────┤
  │  1  │ {task description}   │  M   │ 10m   │ ready  │
  │  2  │ {task description}   │  S   │  5m   │ ready  │
  │  3  │ {task description}   │  L   │ 15m   │ ready  │
  │  4  │ {task description}   │  S   │  5m   │ skip?  │
  └─────┴──────────────────────┴──────┴───────┴────────┘
  Wind-down reserve: {W}m
```

### Phase 2: Execute Loop

> Details: [resources/execute-protocol.md](./resources/execute-protocol.md)

각 작업 실행 시 반복되는 루프:

1. **시간 체크**: `scripts/check-deadline.sh`로 남은 시간 확인
2. **다음 작업 선택**: 의존성 충족 + 우선순위 최상위 작업
3. **작업 실행**: 실제 코드 읽기/수정/생성/테스트 수행
4. **결과 검증**: 작업 완료 조건 확인 (컴파일, 테스트 통과 등)
5. **상태 갱신**: session-state.json 업데이트, 진행 상태 표시
6. **체크포인트 판단**: 남은 시간 레벨에 따라 계속/중단 결정

**작업 실행 중 상태 표시**:
```
[claude-autopilot] Task 2/4 | ▓▓▓▓░░░░░░ | 18m remaining | Status: implementing
```

**작업 완료 시 표시**:
```
[claude-autopilot] ✓ Task 2 complete (4m 23s) | 3/4 done | 14m remaining
```

### Phase 3: Wind-down

> Details: [resources/winddown-protocol.md](./resources/winddown-protocol.md)

마감 시간 임박 시 안전한 마무리 절차:

1. **현재 작업 완료 판단**: 완료 가능하면 마무리, 불가능하면 안전 지점까지 롤백
2. **코드 일관성 확보**: 편집 중인 파일이 문법적으로 유효한 상태인지 확인
3. **미완료 작업 기록**: 남은 작업 목록을 session-state.json에 저장
4. **임시 파일 정리**: 작업 중 생성된 불필요한 임시 파일 제거

### Phase 4: Report

> Details: [resources/report-protocol.md](./resources/report-protocol.md)

세션 종료 시 최종 보고서 출력:

```markdown
## Autopilot Session Report

### 세션 요약
- 시작: {start_time} → 종료: {end_time} (총 {duration})
- 완료: {completed}/{total} tasks ({percentage}%)

### 완료된 작업
| # | Task | Duration | Result |
|---|------|----------|--------|
| 1 | {description} | 4m 23s | ✓ success |
| 2 | {description} | 8m 12s | ✓ success |

### 미완료 작업
| # | Task | Reason | 권장 사항 |
|---|------|--------|----------|
| 3 | {description} | 시간 부족 | 다음 세션에서 계속 |

### 변경된 파일
- `src/api/handler.kt` — 리팩토링 완료
- `src/test/api/HandlerTest.kt` — 테스트 추가

### 다음 세션 권장 사항
- [ ] {미완료 작업 1}
- [ ] {미완료 작업 2}
```

---

## Directive Parsing Rules

사용자 지침에서 구조화된 정보를 추출하는 규칙.

### 지침 구성 요소

| 구성 요소 | 필수 | 추출 방법 | 기본값 |
|----------|------|----------|-------|
| **directive** | ✅ | 시간/옵션 제외한 나머지 텍스트 | — |
| **deadline** | ✅ | `--until`, `까지`, 시간 표현 패턴 매칭 | — |
| **priority** | ❌ | `--priority` 플래그 | `balanced` |
| **scope** | ❌ | `--scope` 플래그 또는 경로 패턴 | `project` |
| **loop** | ❌ | `loop N` 패턴 | 검증 1회 |
| **dry-run** | ❌ | `dry-run` 키워드 | false |

### 지침 해석 우선순위

1. **명시적 작업 목록**: "1. A 하고 2. B 하고 3. C 해줘" → 순서대로 실행
2. **범위 지정 작업**: "src/api/ 아래 모든 TODO 처리" → Glob으로 대상 파일 탐색
3. **목표 지향 작업**: "API 성능 개선" → Decompose에서 세부 작업 자동 생성
4. **자유 형식**: "코드 정리 좀 해줘" → 프로젝트 스캔 후 개선 포인트 자동 발견

---

## Task Estimation

작업 규모 추정 기준.

| Size | 예상 시간 | 특징 | 예시 |
|------|----------|------|------|
| **S** (Small) | 1-5분 | 단일 파일, 단순 변경 | TODO 제거, import 정리, 오타 수정 |
| **M** (Medium) | 5-15분 | 2-5 파일, 로직 변경 | 메서드 추가, 리팩토링, 단위 테스트 |
| **L** (Large) | 15-30분 | 5-10 파일, 구조 변경 | 새 API 엔드포인트, 모듈 리팩토링 |
| **XL** (Extra Large) | 30분+ | 10+ 파일, 아키텍처 영향 | 새 모듈 생성, 대규모 마이그레이션 |

**시간 부족 시 XL 작업 처리**:
- 가용 시간 < XL 예상 시간의 80%: 작업을 하위 작업으로 재분해
- 하위 작업 중 가용 시간 내 완료 가능한 것만 실행
- 나머지는 "다음 세션 권장" 목록에 추가

---

## Safety Guardrails

### 금지 행동

| 규칙 | 설명 |
|------|------|
| **No destructive ops without backup** | rm -rf, git reset --hard 등 파괴적 명령 금지 (사전 백업 없이) |
| **No secret file edits** | `.env`, `credentials`, `private-key` 등 시크릿 파일 편집 차단 |
| **No scope escalation** | 사용자 지정 scope 밖의 파일 수정 금지 |
| **No force push** | `git push --force` 절대 금지 |
| **No silent failures** | 에러 발생 시 반드시 보고서에 기록 |

### 작업 중단 조건

다음 상황에서 즉시 작업을 중단하고 사용자에게 보고:

1. **연쇄 에러**: 동일 에러 3회 연속 발생
2. **테스트 전면 실패**: 기존 테스트가 대량으로 깨질 때
3. **범위 초과**: 지침 범위를 벗어나는 변경이 필요할 때
4. **의존성 충돌**: 해결 불가능한 의존성 문제 발생

---

## Sister-Skill Integration

다른 스킬과 연동하여 전문 작업을 위임할 수 있다.

| 작업 유형 | 위임 대상 스킬 | 위임 조건 |
|----------|-------------|----------|
| Kotlin/Java 코드 작성 | sub-kopring-engineer | `.kt`/`.java` 파일 생성/수정 |
| 테스트 생성 | sub-test-engineer | 테스트 코드 생성 요청 |
| 수치 연산 검증 | numerical | 수치 연산 코드 발견 |
| 아키텍처 분석 | engineering-workflow | 아키텍처 결정 필요 |

**위임 프로토콜**:
1. 작업 유형이 sister-skill 전문 영역에 해당하는지 판단
2. 해당 시 sister-skill의 SKILL.md를 읽어 위임 가능 여부 확인
3. 남은 시간 예산의 일부를 sister-skill에 할당
4. 결과를 받아 진행 상태에 반영

---

## Context Documents (Lazy Load)

**Stale Context Recovery**: 컨텍스트 압축(/compact) 발생 시, "Load Once" 문서라도
해당 Phase에서 필요한 문서는 **반드시 재로드**한다. "Load Once"는 "같은 Phase 내 중복 로드 방지"이며,
"컨텍스트 소실 후에도 재로드 불필요"를 의미하지 **않는다**.

| Document | Phases | Load Condition | Load Frequency | 압축 후 재로드 |
|----------|--------|----------------|----------------|---------------|
| **session-state.json** (auto-created) | 0, 2, 3, 4 | Every phase entry | Every Phase | ✅ 항상 |
| [parse-init-protocol.md](./resources/parse-init-protocol.md) | 0 | Always at Phase 0 | Load Once | ✅ Phase 0 진행 중이면 |
| [decompose-protocol.md](./resources/decompose-protocol.md) | 1 | Always at Phase 1 | Load Once | ✅ Phase 1 진행 중이면 |
| [execute-protocol.md](./resources/execute-protocol.md) | 2 | Always at Phase 2 | Load Once | ✅ Phase 2 진행 중이면 |
| [winddown-protocol.md](./resources/winddown-protocol.md) | 3 | Always at Phase 3 | Load Once | ✅ Phase 3 진행 중이면 |
| [report-protocol.md](./resources/report-protocol.md) | 4 | Always at Phase 4 | Load Once | ✅ Phase 4 진행 중이면 |
| [time-management.md](./resources/time-management.md) | 0, 1, 2 | Always | Load Once | ✅ Phase 0-2 진행 중이면 |
| [safety-rules.md](./resources/safety-rules.md) | All | Always | Load Once | ✅ 항상 (안전 규칙) |
| [error-playbook.md](./resources/error-playbook.md) | Any | On error occurrence | Load Once | ✅ 에러 발생 시 |

---

## Resources (On-demand)

| Document | Purpose |
|----------|---------|
| [parse-init-protocol.md](./resources/parse-init-protocol.md) | Phase 0 지침 파싱 및 세션 초기화 절차 |
| [decompose-protocol.md](./resources/decompose-protocol.md) | Phase 1 작업 분해 및 시간 예산 배분 절차 |
| [execute-protocol.md](./resources/execute-protocol.md) | Phase 2 자율 실행 루프 상세 절차 |
| [winddown-protocol.md](./resources/winddown-protocol.md) | Phase 3 안전한 마무리 절차 |
| [report-protocol.md](./resources/report-protocol.md) | Phase 4 최종 보고서 생성 절차 |
| [time-management.md](./resources/time-management.md) | 시간 예산 관리 알고리즘 상세 |
| [safety-rules.md](./resources/safety-rules.md) | 안전 가드레일 상세 규칙 |
| [error-playbook.md](./resources/error-playbook.md) | 에러 유형별 대응 절차 |

## Scripts

| 스크립트 | 용도 | 사용법 |
|---------|------|--------|
| `parse-deadline.sh` | 마감 시간 파싱 → epoch 변환 | `./parse-deadline.sh "15:30"` |
| `check-deadline.sh` | 남은 시간 확인 및 레벨 판정 | `./check-deadline.sh` |
| `init-session.sh` | 세션 상태 파일 초기화 | `./init-session.sh <deadline_epoch> <directive>` |
| `update-task-status.sh` | 작업 상태 갱신 | `./update-task-status.sh <task_id> <status>` |
| `generate-report.sh` | 최종 보고서 JSON 생성 | `./generate-report.sh` |
| `check-phase-gate.sh` | Phase 전환 Gate Check | `./check-phase-gate.sh <from> <to>` |
| `verify-plugin.sh` | 플러그인 무결성 검증 하네스 | `./verify-plugin.sh [--verbose]` |
| `_common.sh` | 공유 유틸리티 (다른 스크립트에서 source) | 직접 실행 불가 |

**스크립트 실행 요구사항:**
- 필수 CLI: `bash 4.0+`, `jq`, `date`, `grep`, `find`
- 환경: Unix-like (Linux, macOS)

---

## Hooks Configuration

| Hook | Trigger | Action |
|------|---------|--------|
| **PreToolUse** (secret guard) | Edit/Write | 시크릿 파일 편집 차단 |
| **PreToolUse** (deadline check) | Edit/Write/Bash | 마감 시간 초과 시 차단 (exit 2) |
| **PreToolUse** (scope enforcement) | Edit/Write | scope 밖 파일 편집 차단 (project/module/file) |
| **PostToolUse** (activity tracker) | Edit/Write | 마지막 활동 시간 기록 |
| **Stop** (session archive) | Session end | 세션 상태 아카이브 |

---

## Status Display Protocol

각 작업 실행 시 현재 상태를 간결하게 표시한다.

### 표시 형식

```
[claude-autopilot] Task: {n}/{total} | {bar} | {remaining}m left | Phase: {phase} | Level: {time_level}
```

**예시:**
```
[claude-autopilot] Task: 2/5 | ▓▓▓▓░░░░░░ | 23m left | Phase: Execute | Level: NORMAL
[claude-autopilot] Task: 4/5 | ▓▓▓▓▓▓▓▓░░ | 6m left | Phase: Execute | Level: CAUTION
[claude-autopilot] Wind-down | ▓▓▓▓▓▓▓▓▓░ | 3m left | Phase: Wind-down | Level: WIND_DOWN
```

---

## Session State Schema

세션 상태는 `~/.claude/cache/claude-autopilot/session-state.json`에 저장.

```json
{
  "session_id": "ap-20260307-153000",
  "status": "in_progress",
  "directive": "API 엔드포인트 리팩토링하고 테스트 추가",
  "deadline_epoch": 1741340400,
  "deadline_display": "15:30",
  "started_at": "2026-03-07T14:30:00Z",
  "priority": "balanced",
  "scope": "project",
  "time_budget": {
    "total_minutes": 60,
    "wind_down_reserve": 6,
    "execution_available": 52,
    "parse_overhead": 2
  },
  "tasks": [
    {
      "id": 1,
      "description": "OrderController 리팩토링",
      "size": "M",
      "allocated_minutes": 12,
      "status": "completed",
      "started_at": "2026-03-07T14:32:00Z",
      "completed_at": "2026-03-07T14:40:23Z",
      "files_changed": ["src/api/OrderController.kt"]
    },
    {
      "id": 2,
      "description": "OrderControllerTest 추가",
      "size": "M",
      "allocated_minutes": 10,
      "status": "in_progress",
      "started_at": "2026-03-07T14:40:30Z",
      "depends_on": [1],
      "acceptance_criteria": [
        "테스트 파일 생성됨",
        "테스트 실행 통과"
      ]
    }
  ],
  "completed_tasks": 1,
  "total_tasks": 4,
  "errors": [],
  "file_inventory": {
    "read": [
      {"path": "src/api/OrderController.kt", "at": "2026-03-07T14:32:00Z", "lines": 145}
    ],
    "modified": [
      {"path": "src/api/OrderController.kt", "at": "2026-03-07T14:33:15Z", "verified": true}
    ]
  },
  "last_activity": "2026-03-07T14:45:12Z",
  "time_level": "NORMAL"
}
```

---

## Context Health Protocol

롱 세션에서 컨텍스트 윈도우 사용량을 모니터링한다.

### 임계값 대응

| 사용량 | 레벨 | 대응 |
|--------|------|------|
| **70%** | WARNING | 새 작업 시 reference 최소 로딩, 핵심 변경에 집중 |
| **80%** | RECOMMEND | 현재 작업 완료 후 /compact 실행 권장 |
| **85%** | CRITICAL | 즉시 /compact 실행, 프로파일 + 현재 작업 상태만 복구 |

### 압축 후 복구 절차

```
1. /compact 실행 후 컨텍스트 요약됨
2. session-state.json 재로드 (캐시에서)
3. 현재 실행 중인 작업 컨텍스트 복구
4. 남은 시간 재계산 후 실행 루프 재개
```

---

## Session Wisdom Protocol

세션 간 학습 내용을 축적한다.

### 저장 위치

```
~/.claude/cache/claude-autopilot/history/
```

### 기록 시점

| 시점 | 기록 내용 | 자동/수동 |
|------|----------|----------|
| **작업 완료** | 작업별 실제 소요 시간 (추정 정확도 개선용) | 자동 |
| **에러 해결** | 에러 + 원인 + 해결 방법 | 자동 |
| **세션 종료** | 전체 세션 요약 + 미완료 작업 | 자동 |

### 시간 추정 학습

이전 세션의 실제 소요 시간 데이터를 활용하여 작업 규모 추정 정확도를 개선:

```
추정 보정 계수 = 최근 5개 세션의 (실제 시간 / 추정 시간) 평균
보정된 추정 = 기본 추정 × 보정 계수
```

### 보존 규칙

- **최근 20개 세션** 히스토리 유지 (이전은 자동 삭제)
- **시간 추정 통계**는 영구 보존

---

## Gran Maestro 연동 (gran-maestro Integration)

[gran-maestro](https://github.com/myrtlepn/gran-maestro) 플러그인이 설치된 프로젝트에서
claude-autopilot은 gran-maestro의 계획/스펙을 자동으로 감지하고 실행할 수 있다.

### 감지 조건

autopilot 세션 시작 시 아래 조건으로 gran-maestro 연동 모드를 활성화:

1. `{PROJECT_ROOT}/.gran-maestro/` 디렉토리 존재
2. `{PROJECT_ROOT}/.gran-maestro/mode.json`의 `active == true`
3. 미승인/미완료 REQ가 있거나, 사용자 지침에 PLN/REQ 참조 포함

### 연동 모드

| 모드 | 트리거 | 동작 |
|------|--------|------|
| **Plan-to-Execute** | `"autopilot: PLN-003 실행 --until 16:00"` | plan.md 읽기 → REQ 자동 생성/승인 → 구현 실행 |
| **REQ Batch** | `"autopilot: REQ-001..005 처리 --until 18:00"` | 지정 REQ들을 시간 내 순차 승인/실행 |
| **Pending Drain** | `"autopilot: 대기 중인 REQ 모두 처리 --until 17:00"` | pending REQ 스캔 → 우선순위 정렬 → 시간 내 처리 |
| **Mixed** | `"리팩토링하고 REQ-003도 처리 --until 15:00"` | 일반 작업 + gran-maestro REQ 혼합 실행 |

### Plan-to-Execute 프로토콜

gran-maestro의 PLN (plan.md)을 기반으로 자율 실행:

```
1. plan.md 읽기
   Read("{PROJECT_ROOT}/.gran-maestro/plans/PLN-NNN/plan.md")

2. 작업 추출
   plan.md의 요구사항/결정사항 → autopilot 작업 목록으로 변환
   - 각 요구사항 항목 → 개별 task로 분해
   - plan.md의 제약 조건 → safety guardrail로 주입

3. REQ 생성 (gran-maestro 프로토콜 준수)
   Skill(skill: "mst:request", args: "--auto {plan 기반 요청}")
   → REQ-NNN 자동 생성

4. 자동 승인
   Skill(skill: "mst:approve", args: "REQ-NNN --continue")
   → spec.md 기반 구현 시작

5. 시간 관리
   각 REQ의 spec.md 내 task 단위로 시간 예산 배분
   deadline 임박 시 나머지 REQ는 pending 상태 유지
```

### REQ Batch 프로토콜

여러 REQ를 시간 예산 내에서 순차 처리:

```
1. REQ 목록 수집
   - 명시적: "REQ-001..005" → [REQ-001, REQ-002, ..., REQ-005]
   - 자동: requests/ 스캔 → status=spec_ready 필터링

2. 시간 예산 배분
   각 REQ의 spec.md 읽기 → task 수/복잡도 기반 시간 추정
   시간 부족 시 우선순위 낮은 REQ skip 표시

3. 순차 실행
   FOR each REQ in sorted_list:
     IF remaining_time > estimated_time(REQ):
       Skill(skill: "mst:approve", args: "REQ-NNN --continue")
       → 구현 실행 → 결과 검증
     ELSE:
       REQ를 "시간 부족 — 다음 세션" 목록에 추가
       BREAK

4. 결과 보고
   처리 완료/미완료 REQ 목록을 autopilot 보고서에 포함
```

### gran-maestro 상태 파일 연동

| gran-maestro 파일 | autopilot 활용 |
|-------------------|---------------|
| `.gran-maestro/mode.json` | 연동 모드 활성 여부 확인 |
| `.gran-maestro/plans/PLN-NNN/plan.md` | 지침 소스로 활용 |
| `.gran-maestro/plans/PLN-NNN/plan.json` | 메타데이터 (상태, 연결된 REQ) |
| `.gran-maestro/requests/REQ-NNN/request.json` | REQ 상태/메타 확인 |
| `.gran-maestro/requests/REQ-NNN/spec.md` | 구현 스펙 (작업 분해 입력) |
| `.gran-maestro/requests/REQ-NNN/tasks/` | 세부 task 진행 상태 |
| `.gran-maestro/config.resolved.json` | 기본 에이전트, 워크플로우 설정 |

### 안전 규칙 (gran-maestro 연동 시)

| 규칙 | 설명 |
|------|------|
| **spec.md 필수** | REQ 실행 전 반드시 spec.md가 존재해야 함 (gran-maestro 규칙 준수) |
| **경로 제한 준수** | gran-maestro 스킬의 Write/Edit 경로 제한 규칙 그대로 적용 |
| **auto 모드만** | autopilot에서 REQ 생성 시 반드시 `--auto` 플래그 사용 |
| **원본 plan 보존** | plan.md를 수정하지 않음 — 읽기 전용으로만 참조 |
| **실패 시 REQ 상태 복원** | 구현 실패 시 REQ를 spec_ready 상태로 되돌림 |

### gran-maestro 미설치 시

`.gran-maestro/` 디렉토리가 없으면 연동 기능은 비활성화되고,
autopilot은 사용자 지침만을 기반으로 독립 실행된다.
PLN/REQ 참조가 지침에 포함된 경우 "gran-maestro 미감지" 경고를 출력한다.
