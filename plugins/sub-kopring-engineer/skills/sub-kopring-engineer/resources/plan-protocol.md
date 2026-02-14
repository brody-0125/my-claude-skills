# Plan Protocol

> Phase 2 (Plan) detailed execution procedure

## Required Reads (skip if already loaded in this session)
> Base Set: see SKILL.md "Context Documents" section (profile, learned patterns, code-style-guide, architecture ref)

**Phase-specific additions:**
- `resources/directory-context-guide.md` (파일 배치 결정 시 필수 — 디렉토리↔레이어 매핑)
- `references/layering-principles.md` (when STANDARD/THOROUGH or multi-layer changes)
- `references/jooq-conventions.md` (when query-lib includes jooq)
- `references/unit-testing.md` (when language=kotlin/mixed)
- `references/integration-testing.md` (when language=kotlin/mixed)
- `references/java-unit-testing.md` (when language=java/mixed)
- `references/java-integration-testing.md` (when language=java/mixed)

---

### 0-R. Plan Readiness Check (v2.6)

Plan Phase 진입 전 아래 항목을 순차 확인한다. **하나라도 실패하면 Plan에 진입하지 않는다.**

```
1. □ ProjectProfile 존재 확인
     → 현재 컨텍스트에 "## Project Profile" 또는 profile 캐시 존재
     → 미존재 시: Phase 0 (Discovery) 먼저 실행

2. □ 요구사항 명확도 확인
     → CLEAR: 즉시 진행
     → MODERATE: 사용자가 진행 승인한 경우에만 진행
     → VAGUE: Plan 진입 불가 → Phase 1 (Brainstorm) 실행
     → (Level 1 Skip으로 Brainstorm이 스킵된 경우 CLEAR로 간주)

3. □ 코드베이스 접근 확인
     → Glob으로 프로젝트 소스 디렉토리(src/) 최소 1개 존재 확인
     → 미존재 시: 프로젝트 경로 재확인 요청
```

**미충족 시 동작:**
- 항목 1 실패 → `"ProjectProfile이 없습니다. Phase 0 (Discovery)를 먼저 실행합니다."` 출력 후 Discovery 실행
- 항목 2 실패 → `"요구사항이 명확하지 않습니다. Brainstorm을 진행합니다."` 출력 후 Brainstorm 실행
- 항목 3 실패 → `"프로젝트 소스를 찾을 수 없습니다. 프로젝트 경로를 확인해주세요."` 출력

---

### 1-0. Project Profile Check

Reference the profile and learned patterns cache generated in Phase 0.
If no profile exists, execute Phase 0 first.

**Using learned patterns in Plan:**
- base classes → Specify in Plan whether new classes should inherit from existing abstract classes
- naming patterns → Ensure new class names are consistent with existing naming patterns
- error hierarchy → Specify reuse of existing Exception classes in error handling strategy
- utility imports → Prevent duplicate utility creation
- custom annotations → Review whether existing project-specific annotations can be leveraged
- annotation combos → Consistently apply existing annotation combination patterns to new services
- test fixtures → Specify reuse of existing Fixture/Factory in test plans
- dependency patterns → Design new class dependency structures referencing existing dependency combination patterns in the same layer
- method/layer structure → Write Plan deliverables following existing method signature/file placement patterns per layer
- task-derived → Prioritize patterns approved by the user in previous tasks

### 1-1. Codebase Exploration

```
1. Glob: Identify affected module/package structures (based on profile's layer paths)
2. Grep: Search for related classes, interfaces, ports
3. Read: Review existing implementation patterns (existing code in the same domain)
```

### 1-1b. Exploration Confidence Scoring (v2.7)

§1-1 Codebase Exploration 완료 후, 탐색 결과의 충분성을 평가한다.

**평가 항목**:
| 항목 | 높음 | 중간 | 낮음 |
|------|------|------|------|
| 관련 파일 발견 수 | ≥5개 | 3-4개 | 1-2개 |
| 기존 패턴 참조 | 동일 도메인 구현 존재 | 유사 도메인만 존재 | 참조 패턴 없음 |
| Port/Interface 영향 범위 | 전체 파악 완료 | 부분 파악 | 불명확 |

> architecture가 hexagonal이 아닌 경우 "Port/Interface 영향 범위" 항목은 "해당 없음"으로 처리하고, 나머지 2항목으로 신뢰도를 판정한다.

**신뢰도 → 행동 매핑**:
| 종합 | 행동 |
|------|------|
| 높음 (3항목 모두 높음/중간) | 즉시 §1-2 Context Loading 진행 |
| 중간 (1항목 낮음) | 부족한 영역 추가 탐색 수행 후 진행 — 추가 Glob/Grep 대상 명시 |
| 낮음 (2항목 이상 낮음) | 사용자에게 추가 정보 요청 |

**출력 형식**:
```
Exploration Confidence: 높음
  - 관련 파일: 7개 | 패턴 참조: 동일 도메인 | Port 범위: 전체 파악
  → §1-2 Context Loading 진행
```

### 1-2. Context Loading

Load references/ documents according to the SKILL.md context document table (skip documents already loaded in previous Phases).
For profile override rules, see [project-discovery-protocol.md](./project-discovery-protocol.md) "Profile vs references/ conflict resolution rules".

### 1-3. Plan Deliverables

Output in the [templates/plan-template.md](../templates/plan-template.md) format.

Organize changes by layer:

**Single module:**
1. `core/domain-model` — Definition, business rules, Value Object
2. `core (ports)` — Reader/Appender/Updater interfaces
3. `application` — Use Case Service
4. `infrastructure` — Adapter/Repository implementation
5. `app` — Controller, HTTP models

**Multi-module Hexagonal (when profile has modules):**
1. `:shared-kernel` — Shared Value Objects, Domain Events (if applicable)
2. `:core` (or `:{domain}-core`) — Domain Model, Port interfaces
3. `:application` (or `:{domain}-application`) — Use Case Service
4. `:infrastructure` (or `:{domain}-infrastructure`) — Adapter/Repository
5. `:api` — Controller, HTTP models
6. Module dependency changes (if new module added or dependency changed)

### 1-4. Dry-run Mode

When the `dry-run` keyword is included, execute only up to Plan and halt.
No files are created/modified; expected changes are output as a simulation.

```markdown
## Dry-run Simulation

### Files to be created
- `core/domain-model/.../OrderCancelDefinition.kt` (new)
- `core/.../OrderUpdater.kt` (modified: add cancel method)
...

### Change Preview
Display expected code snippets for each file.

⚠️ This result is a simulation. No actual files have been changed.
```

### 1-4a. Dry-run → Implement 전환 프로토콜

Dry-run 시뮬레이션 표시 후:

| 사용자 응답 | 전환 경로 |
|------------|----------|
| "진행" / "Proceed" | Plan 산출물 확정 → Phase Handoff 조건 충족 → Implement 진입 |
| "수정" / "Revise" | §1-0~§1-3 재진입 → Plan 재생성 → Dry-run 재실행 |
| 무응답 | HALT 상태 유지. 자동 전환 없음 — 명시적 사용자 지시 대기 |

**제약**: Dry-run 후 Implement 자동 진입은 금지. 반드시 사용자 명시적 승인 필요.

---

## Phase Handoff

**Entry Condition**: Plan Readiness Check (§0-R) 통과 AND Phase 0 complete (profile cached) AND (Brainstorm complete OR request clarity Level 1)

**Exit → Implement Transition Contract (v2.6):**
Plan 완료 후 Implement로 전환하기 전 아래를 확인한다:
```
□ Plan 산출물에 최소 1개 파일 변경 계획이 존재
□ 각 변경 파일에 레이어 지정이 되어 있음 (core/application/infrastructure/app/test)
□ dry-run 모드가 아님 (dry-run이면 여기서 HALT)
```
미충족 시 Plan을 보완한 후 재확인한다.

**Exit Condition**: Plan approved by user OR dry-run simulation displayed

**Next Phase**: → [implement-protocol.md](./implement-protocol.md) (Phase 3 Implement)

**Domain Keyword Effects**:
- `port-first`: Port 인터페이스 먼저 정의 → Adapter 구현 순서 강제
- `api-contract`: API 스펙 먼저 확정 → Controller 구현 순서
- `migration`: DB 마이그레이션 포함, 롤백 계획 필수 출력
