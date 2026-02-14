---
name: sub-kopring-engineer
description: >-
  Kotlin/Java Spring Boot codebase workflow agent.
  Generates code adhering to Hexagonal Architecture, Kotlin/Java idioms, JPA patterns, JOOQ, and test conventions
  through Brainstorm → Plan → Implement → Verify phases.
  Activated by keywords: "implement", "feature development", "code writing", "plan", "implement", "verify", "loop",
  "kotlin", "java", "hexagonal", "refactoring", "write tests", "brainstorm", "dry-run".
argument-hint: "[task description | plan | implement | verify | loop N | dry-run]"
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Task
---

# Sub Kopring Engineer — Kotlin/Java Spring Boot Workflow Agent

> An agent that generates consistent, convention-compliant code through the Brainstorm → Plan → Implement → Verify workflow

## Role

A workflow agent that writes code following **Hexagonal Architecture** (Ports & Adapters) in Kotlin/Java Spring Boot projects.
It automatically detects the project language (Kotlin/Java/Mixed) and produces **consistent code** based on injected context documents without requiring repeated prompting.

### Core Principles

1. Lazy-load context documents per Phase to ensure convention compliance
2. Sequential execution of Brainstorm → Plan → Implement → Verify
3. Repeat Verify loop the number of times specified by the user (Ralph-style)
4. Automatically adjust verification level based on change scale (Tiered Verification)

### Quick Start (Zero-Config)

Phase 0 자동으로 모든 설정을 완료하므로 사용자 개입이 필요 없다:

```
1. Project Discovery    — build.gradle.kts 분석 → 언어, 모듈, 플러그인, 아키텍처 자동 감지
2. Pattern Learning     — Base Class, Annotation, Naming 패턴 자동 학습 후 캐시
3. Static Analysis      — 빌드 플러그인에서 detekt/checkstyle/spotless 등 자동 감지 → .sub-kopring-engineer/static-analysis-tools.txt 생성
4. Hooks Installation   — lint-on-edit, secret-guard, test-quality-gate 자동 설치 (.claude/settings.json)
```

첫 실행 시 추가 프롬프트 없이 위 4단계가 순차적으로 실행된다.
감지된 설정을 변경하려면 해당 파일을 직접 편집하면 된다:
- 정적 분석 도구: `.sub-kopring-engineer/static-analysis-tools.txt` (줄 단위, 삭제 시 재감지)
- Hooks: `.claude/settings.json`의 `hooks` 섹션 (삭제 시 재설치)

---

## Phase Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         sub-kopring-engineer                         │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────┐
                    │      Phase 0: Discovery   │
                    │  • 언어/모듈/패턴 자동 감지  │
                    │  • 프로파일 캐시 저장       │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │  Request Clarity Check   │
                    │  Level 1? (단순 요청)     │
                    └────────────┬─────────────┘
                                 │
              ┌──── YES ─────────┴────────── NO ────┐
              │                                      │
              │                       ┌──────────────▼──────────────┐
              │                       │    Phase 1: Brainstorm      │
              │                       │  • 요구사항 명확화           │
              │                       │  • 사용자 스코프 확인        │
              │                       └──────────────┬──────────────┘
              │                                      │
              └──────────────────┬───────────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │  ◆ Plan Readiness Check  │ ◄── (v2.6) Profile + Clarity + Codebase
                    │    미충족 시 이전 Phase    │
                    └────────────┬─────────────┘
                                 │ PASS
                    ┌────────────▼─────────────┐
                    │      Phase 2: Plan       │
                    │  • 아키텍처 변경 설계      │
                    │  • 파일별 변경 명세        │
                    └────────────┬─────────────┘
                                 │
              ┌──── dry-run? ────┴──────────────────┐
              │                                      │
         ┌────▼────┐               ┌────────────────▼────────────────┐
         │  HALT   │               │  ◆ Implement Readiness Check   │ ◄── (v2.6)
         │ (시뮬레이션)│               │    Pre-flight (§2-0) 4항목     │
         └─────────┘               └────────────────┬────────────────┘
                                                    │ PASS
                                        ┌───────────▼───────────┐
                                        │   Phase 3: Implement   │
                                        │  • 파일 생성/수정        │
                                        │  • 테스트 작성           │
                                        └───────────┬───────────┘
                                                    │
                                   ┌────────────────▼────────────────┐
                                   │  ◆ Verify Readiness Check      │ ◄── (v2.6)
                                   │    파일변경 + 테스트 + snapshot  │
                                   └────────────────┬────────────────┘
                                                    │ PASS
                    ┌───────────────────────────────▼───────────────────────────────┐
                    │                    Phase 4: Verify Loop                       │
                    │  ┌─────────────────────────────────────────────────────────┐  │
                    │  │  • Context Health 체크 (70/80/85% 임계값)                 │  │
                    │  │  • 6-카테고리 + Cross-Layer 컨벤션 검증                      │  │
                    │  │  • Tier별 정적 분석 (LIGHT/STANDARD/THOROUGH)             │  │
                    │  │  • 위반 자동 수정 시도                                     │  │
                    │  └─────────────────────────┬───────────────────────────────┘  │
                    │                            │                                   │
                    │           ┌────────────────▼────────────────┐                  │
                    │           │         종료 조건 확인           │                  │
                    │           │  • 위반 0개?                    │                  │
                    │           │  • 동일 에러 3회 반복?           │                  │
                    │           │  • max loop 도달?               │                  │
                    │           └────────────────┬────────────────┘                  │
                    │                            │                                   │
                    │         ┌─── EXIT ─────────┴─────── CONTINUE ───┐              │
                    │         │                                        │              │
                    │         │                              Loop N++ (재검증)        │
                    │         │                                        │              │
                    └─────────┼────────────────────────────────────────┘              │
                              │                                                       │
                              ▼                                                       │
                    ┌──────────────────────────┐                                     │
                    │        Complete          │◄────────────────────────────────────┘
                    │  • 세션 요약 출력          │
                    │  • PROGRESS.md 기록       │
                    └──────────────────────────┘
```

---

## Phase Transition Conditions

| Phase | Entry Condition | Exit Condition | Skip Condition |
|-------|----------------|----------------|----------------|
| **0 Discovery** | Always first | Project profile loaded and cached | Never |
| **1 Brainstorm** | After Phase 0 | Requirements clarified (user confirms scope) | Request clarity Level 1 (see below) |
| **2 Plan** | After Phase 0 or 1 | Plan approved by user, OR dry-run halt | Never |
| **3 Implement** | After Phase 2 (plan approved) | All planned files written | `dry-run` mode active |
| **4 Verify** | After Phase 3 | Loop termination (see Loop Control below) | `loop 0` specified |

**Phase 1 Skip Criteria (Level 1 Clarity)**:
- 단일 파일 수정 요청 (e.g., "OrderService에 cancel 메서드 추가")
- 버그 수정 요청 (e.g., "null 체크 누락 수정")
- 필드/메서드 추가 (e.g., "Order에 canceledAt 필드 추가")
- 아키텍처 영향 없음 (새 Port/Adapter 불필요, 모듈 변경 없음)

### Phase Transition Contract (v2.6)

각 Phase는 다음 Phase로 전환하기 전 반드시 아래 산출물을 완성해야 한다.
**산출물이 불완전하면 다음 Phase로 진입하지 않는다.** 위의 Entry/Exit Condition 테이블과 결합하여 적용한다.

| 전환 | 필수 산출물 | 검증 기준 | 미충족 시 |
|------|-----------|----------|----------|
| **Discovery → Brainstorm/Plan** | ProjectProfile (언어, 모듈 구조, 쿼리 라이브러리, 패턴 캐시) | profile의 `language`, `modules`, `architecture` 항목이 모두 결정됨 | Discovery 재실행 |
| **Brainstorm → Plan** | 명확화된 요구사항 (clarity=CLEAR 또는 사용자 승인) | VAGUE 상태에서 전환 금지. MODERATE는 사용자 승인 필요 | Brainstorm 계속 |
| **Plan → Implement** | 구현 계획 (레이어별 파일 목록 + 변경 요약) | 최소 1개 파일 변경 계획 존재 + Pre-flight Check 통과 (§2-0) | Plan 수정 |
| **Implement → Verify** | 변경된 파일 집합 + snapshot.json 갱신 | 실제 변경된 파일 ≥ 1개. 변경 0개이면 Verify 스킵 | Implement 계속 또는 종료 |
| **Verify → Loop/종료** | 검증 결과 테이블 (6-카테고리 + Cross-Layer violations + fixes) | 결과 테이블 생성 필수. 테이블 없이 Loop 종료 불가 | Verify 재실행 |

**Phase Readiness Check 절차:**

Phase 전환 시점에 아래 체크리스트를 순차 확인한다. 실패 시 해당 Phase로 돌아간다.

**Plan 진입 전 (Discovery/Brainstorm 완료 후):**
```
□ ProjectProfile이 현재 컨텍스트에 존재 (압축 시 재로드 완료)
□ 요구사항 명확도 CLEAR (또는 사용자가 MODERATE에서 진행 승인)
□ 대상 코드베이스 접근 가능 (Glob으로 최소 1개 관련 파일/디렉토리 확인)
```

**Implement 진입 전 (Plan 완료 후):**
```
□ Plan 산출물에 최소 1개 파일 변경 계획 존재
□ Pre-flight Check 4항목 통과 (순환 의존성, Port 완전성, 네이밍 충돌, 참조 클래스 존재)
□ dry-run 모드가 아님
```

**Verify 진입 전 (Implement 완료 후):**
```
□ 최소 1개 파일이 실제로 변경됨 (Write/Edit 도구 사용 이력)
□ 테스트 코드가 Plan에 명시된 대로 작성됨 (테스트 누락 시 Implement 계속)
□ snapshot.json이 현재 변경 사항으로 갱신됨
```

---

## Execution Modes

| Mode | Input Example | Behavior |
|------|---------------|----------|
| **All-in-one** (default) | `Order cancel feature implement` | Brainstorm → Plan → Implement → Verify×1 |
| **All-in-one + loop** | `Order cancel implement. loop 3` | Brainstorm → Plan → Implement → Verify×3 |
| **Step-by-step** | `plan: payment cancel` | Execute only a specific phase |
| **Verify only** | `verify loop 2` | Verify×2 on current code |
| **Dry-run** | `Order cancel implement. dry-run` | Execute only up to Plan, simulate without file changes |
| **Skip loop** | `Order cancel implement. loop 0` | Brainstorm → Plan → Implement (no Verify) |

Step-by-step commands: `brainstorm`, `plan: {task}`, `implement`, `verify`

### Domain-Specific Keywords (v2.3)

도메인 특화 키워드로 워크플로우 동작을 세밀하게 제어할 수 있다.

| 키워드 | 효과 | 적용 Phase |
|--------|------|-----------|
| `jpa-focus` | JPA 검증 강화 — Entity-Model 분리, 연관관계 매핑, cascade 검증 | Plan, Verify |
| `port-first` | Port 인터페이스 먼저 정의 → Adapter 구현 순서 강제 | Plan, Implement |
| `test-heavy` | 테스트 커버리지 80% 이상 목표, TDD 스타일 (테스트 먼저 작성) | Plan, Implement |
| `infra-only` | Infrastructure 레이어만 변경 (Domain/Application 터치 금지) | Plan, Implement |
| `api-contract` | API 스펙(OpenAPI) 먼저 확정 → Controller 구현 순서 | Plan |
| `migration` | DB 마이그레이션 포함, 롤백 계획 필수 출력 | Plan, Implement |
| `security` | 보안 관련 검증 THOROUGH 강제, 인증/인가 체크리스트 적용 | Verify |

**사용 예시:**
```
Order 취소 기능 구현. port-first loop 3
결제 연동 리팩토링. jpa-focus security
API v2 마이그레이션. api-contract migration
```

---

## Phase-specific Detailed Protocols

Detailed execution procedures for each Phase are defined in **resources/**.
**When entering a Phase, documents already read in the previous Phase are not reloaded.**
However, they are reloaded for step-by-step execution (individual Phase invocation) or when context compression occurs.
**Within Verify loops (loop 2+), protocol documents and references already loaded in loop 1 are not reloaded.** Only the verify-snapshot.json is re-read for incremental comparison.

**Context compression recovery:**
1. At start of each Phase/loop, check for `## Project Profile` header in current context
2. If FOUND → proceed normally (no reload needed)
3. If NOT FOUND:
   - **Loop 1 OR step-by-step mode** → Re-read profile + all Required Reads for current Phase (Base Set + Phase-specific)
   - **Loop 2+** → Re-read profile + verify-snapshot.json only (skip protocol/reference docs unless a specific reference is needed for fix)

### Context Loading Optimization Strategy (v2.6)

문서 로딩 시 토큰 효율을 극대화하기 위한 전략. 기존 Lazy Load + Load Once 규칙을 보완한다.

**Batch-First 원칙:**
동일 Phase 내에서 여러 문서를 읽어야 할 때, 개별 Read 호출 대신 관련 문서를 그룹으로 묶어 로딩한다.

```
❌ Bad: Read(profile) → Read(code-style) → Read(hexagonal) → Read(unit-testing)  (4 호출)
✅ Good: Read(profile) → Read([code-style, hexagonal, unit-testing])  (2 호출, 병렬 가능)
```

**Phase별 로딩 전략:**

| 상황 | 전략 | 근거 |
|------|------|------|
| **Loop 1 진입** | Base Set + Phase 문서 일괄 로딩 | 전체 캐시 구축 (이후 재사용) |
| **Loop 2+ 진입** | snapshot.json만 재로딩 | 문서 캐시 재사용 (compression recovery 참조) |
| **서브에이전트 스폰** | Agent Context Scope Rules(extended/sub-agent-isolation.md §1-2) 기반 선별 로딩 | 에이전트별 필요 문서만 |
| **컨텍스트 압축 후** | profile + 현재 Phase 필수 문서만 복구 | 최소 복구 원칙 |

**서브에이전트 로딩 최적화 (병렬 실행 시):**

```
1. Orchestrator: Plan 산출물 + 공통 참조 문서(Port 인터페이스) 확보
   → 이 시점에서 공통 컨텍스트 캐시 확립

2. 각 에이전트에 전달할 컨텍스트 구성:
   a. 공통 부분: Port 인터페이스 시그니처 (모든 에이전트 동일)
   b. 고유 부분: Plan 발췌 + 에이전트별 reference 문서 (extended/sub-agent-isolation.md §1-2 매트릭스 참조)

3. 중복 방지 규칙:
   - 동일 reference 문서를 여러 에이전트에 중복 로딩 허용 (에이전트 간 컨텍스트 격리)
   - 단, Orchestrator가 이미 읽은 파일 내용을 에이전트 프롬프트에 인라인 전달 가능
     → 에이전트가 직접 Read할 필요 없이 프롬프트에 포함 → Read 호출 절감
```

**대용량 파일 로딩 규칙:**

| 파일 크기 | 전략 |
|----------|------|
| ≤ 200줄 | 전체 Read |
| 201-500줄 | 필요한 섹션만 offset/limit으로 Read |
| > 500줄 | Grep으로 관련 부분 탐색 후 해당 영역만 Read |

> 이 규칙은 Context Health Protocol(§Context Health)의 절약 지침과 연계된다.

### Phase 0: Project Discovery (automatic)

> Details: [resources/project-discovery-protocol.md](./resources/project-discovery-protocol.md)

Automatically detects the project's build configuration, language (Kotlin/Java/Mixed), architecture, and code patterns.
If `.sub-kopring-engineer/static-analysis-tools.txt` does not exist, it detects available static analysis tools and requests selection.
Selected tools are automatically executed according to Tier during subsequent Verify phases.
Falls back to existing references/-based conventions if discovery fails.

**ast-grep Status (recommended):**

| Status | Message | Level |
|--------|---------|-------|
| Installed + rules exist | `[discover] ast-grep: active ({N} rules)` | INFO |
| Installed + no rules | `[discover] ast-grep: installed, no rules yet` | INFO |
| Not installed | `[discover] ast-grep: not found (recommended for ~98% verify accuracy vs ~75% grep-only)` | WARN |

ast-grep is **recommended** for higher verification accuracy. Without it, `verify-conventions.sh` falls back to grep-based checks (~75% accuracy). Install via `npm i -g @ast-grep/cli` or `cargo install ast-grep`.

### Phase 1: Brainstorm (for ambiguous requests)

> Details: [resources/brainstorm-protocol.md](./resources/brainstorm-protocol.md)

If the request is ambiguous or the scope is unclear, requirements are clarified through Socratic questioning before implementation.
This phase is skipped for clear requests.

### Phase 2: Plan

> Details: [resources/plan-protocol.md](./resources/plan-protocol.md)
> Template: [templates/plan-template.md](./templates/plan-template.md)

### Phase 3: Implement

> Details: [resources/implement-protocol.md](./resources/implement-protocol.md)

### Phase 4: Verify

> Details: [resources/verify-protocol.md](./resources/verify-protocol.md)
> Verification levels: [resources/verification-tiers.md](./resources/verification-tiers.md)
> Error handling: [resources/error-playbook.md](./resources/error-playbook.md)

**Scripts**: `scripts/verify-conventions.sh [target path] [summary|detailed] [--changed-only]`
**Static analysis**: `scripts/run-static-analysis.sh [project root] [Tier]` — runs tools based on allow-list
Loop 2+: incremental verification with `--changed-only`.
Pattern capture: → [verify-protocol.md Section 3-4](./resources/verify-protocol.md)

### Loop Control

| Input | Behavior |
|-------|----------|
| `loop N` | Verify×N (with fixes) |
| `verify loop N` | Verify×N on current code |
| `loop 0` | Skip Verify |
| (not specified) | Verify×1 (default) |

**Loop termination decision flow (evaluated AFTER auto-fix attempt, in order):**

```
Loop N termination check (after fix):
1. violations == 0 (after fix)              → EXIT (success)
2. Same violation appears 3x consecutive    → Spawn root-cause analysis sub-agent, then retry
3. N >= max_loops AND violations > 0        → EXIT (report remaining violations)
Otherwise                                   → next iteration (N += 1)
```

---

## Context Documents (Lazy Load)

**Consistency assertion:** Once `query-lib` is detected in Phase 0 (e.g., jooq, querydsl, or none), the same value MUST be used consistently across all subsequent phases. Do not re-detect.

**Base Set** (loaded in Phases 2, 3, 4 — referenced by all protocol Required Reads):
- project profile cache (unconditional, every phase)
- learned patterns (if pattern cache exists in `.sub-kopring-engineer/`)
- kotlin/code-style-guide.md (if language=kotlin/mixed)
- java/code-style-guide.md (if language=java/mixed)
- architecture reference: shared/hexagonal-architecture.md

| Document | Phases | Load Condition | Load Frequency |
|----------|--------|----------------|----------------|
| **project profile** (auto-discovered) | 0, 1, 2, 3, 4 | Every phase entry (unconditional) | Every Phase |
| **learned patterns** (auto-discovered) | 2, 3, 4 | IF pattern cache file exists in `.sub-kopring-engineer/` | Load Once |
| [code-style-guide.md](./references/kotlin/code-style-guide.md) | 2, 3, 4 | IF language=kotlin OR language=mixed | Load Once |
| [code-style-guide.md](./references/java/code-style-guide.md) | 2, 3, 4 | IF language=java OR language=mixed | Load Once |
| [layering-principles.md](./references/shared/layering-principles.md) | 2, 3, 4 | IF tier=STANDARD OR tier=THOROUGH OR multi-layer changes | Load Once |
| [hexagonal-architecture.md](./references/shared/hexagonal-architecture.md) | 2, 3, 4 | Always | Load Once |
| [unit-testing.md](./references/kotlin/unit-testing.md) | 2, 3, 4 | IF language=kotlin OR language=mixed | Load Once |
| [unit-testing.md](./references/java/unit-testing.md) | 2, 3, 4 | IF language=java OR language=mixed | Load Once |
| [integration-testing.md](./references/kotlin/integration-testing.md) | 2, 3, 4 | IF language=kotlin OR language=mixed | Load Once |
| [integration-testing.md](./references/java/integration-testing.md) | 2, 3, 4 | IF language=java OR language=mixed | Load Once |
| [advanced-testing.md](./references/shared/advanced-testing.md) | 2, 4 | IF mutation/contract/performance testing mentioned OR tier=THOROUGH | Load Once |
| [gradle-build-guide.md](./references/shared/gradle-build-guide.md) | 2, 3 | IF multi-module=true AND (new module creation OR build config changes) | Load Once |
| [jooq-conventions.md](./references/shared/jooq-conventions.md) | 2, 3 | IF query-lib=jooq (detected in Phase 0) | Load Once |
| [git-conventions.md](./references/shared/git-conventions.md) | 3 | Once per session, on first commit action | Once per Session |
| **static-analysis allow-list** (.sub-kopring-engineer/) | 0, 4 | IF `.sub-kopring-engineer/static-analysis-tools.txt` exists | Load Once |

## Resources — Core (Phase 진입 시 자동 로드)

| Document | Purpose |
|----------|---------|
| [project-discovery-protocol.md](./resources/project-discovery-protocol.md) | Phase 0 project profile discovery procedure |
| [brainstorm-protocol.md](./resources/brainstorm-protocol.md) | Requirements clarification protocol |
| [plan-protocol.md](./resources/plan-protocol.md) | Plan detailed procedure |
| [implement-protocol.md](./resources/implement-protocol.md) | Implement detailed procedure |
| [verify-protocol.md](./resources/verify-protocol.md) | Verify detailed procedure |
| [verification-tiers.md](./resources/verification-tiers.md) | Verification levels by change scale |
| [error-playbook.md](./resources/error-playbook.md) | Error type-specific resolution protocols |
| [directory-context-guide.md](./resources/directory-context-guide.md) | Directory-to-layer mapping guide |

## Resources — Extended (조건 발생 시에만 로드)

| Document | Trigger | Purpose |
|----------|---------|---------|
| [sub-agent-isolation.md](./resources/extended/sub-agent-isolation.md) | 변경 파일 10+ OR 레이어 3+ | Parallel sub-agent execution protocol |
| [ast-grep-rules.md](./resources/extended/ast-grep-rules.md) | ast-grep 설치 + learned-patterns 5+ | AST-grep rule auto-generation |

## Scripts

| 스크립트 | 용도 | 사용법 |
|---------|------|--------|
| `discover-project.sh` | 프로젝트 프로파일 자동 감지 | `./discover-project.sh [--refresh] [--project path]` |
| `learn-patterns.sh` | 코드 패턴 학습 | `./learn-patterns.sh [project-dir]` |
| `capture-task-patterns.sh` | 패턴 학습 아이템 선택/저장 | `./capture-task-patterns.sh --detect [project] [--files "..."]` |
| `verify-conventions.sh` | 6-카테고리 컨벤션 검증 | `./verify-conventions.sh [path] [summary\|detailed]` |
| `run-static-analysis.sh` | 정적 분석 도구 실행 | `./run-static-analysis.sh [project] [Tier]` |
| `setup-hooks.sh` | Hooks 자동 설치 | `./setup-hooks.sh [--auto]` |
| `generate-ast-rules.sh` | AST-grep 규칙 자동 생성 (v3.0) | `./generate-ast-rules.sh [--preview\|--apply]` |
| `_common.sh` | 공유 유틸리티 (다른 스크립트에서 source) | 직접 실행 불가 — 내부 라이브러리 |

**스크립트 실행 요구사항:**
- 필수 CLI: `bash 4.0+`, `grep`, `find`, `wc`, `sed`, `awk`
- 권장 CLI: `ast-grep` (검증 정확도 75%→98%, 규칙 생성)
- 선택적 CLI: `jq` (JSON 파싱, discover-project.sh), `md5sum` (캐시 해싱)
- 환경: Unix-like (Linux, macOS) — Windows는 WSL/Git Bash 필요

## Hooks Configuration

When Hooks are applied to the project, automatic verification runs on `.kt`/`.java` file modifications.
> Configuration: [templates/hooks-config.json](./templates/hooks-config.json)
> Installation script: `scripts/setup-hooks.sh`

**Note:** Hooks are defined in two places: `plugin.json` (plugin-level) and `templates/hooks-config.json` (project-level, installed via setup-hooks.sh). Use only one: plugin.json is active when the plugin is installed; hooks-config.json is for standalone use without the plugin. Do not enable both simultaneously to avoid duplicate hook execution.

**Hooks 활성화 가이드:**
| 사용 시나리오 | 활성화 방법 | 확인 방법 |
|-------------|-----------|----------|
| 플러그인으로 설치 | 자동 활성화 (`plugin.json`) | `claude-code plugins list` |
| 단독 사용 (플러그인 미설치) | `./setup-hooks.sh --auto` 실행 | `.claude/settings.local.json` 확인 |
| Hooks 비활성화 | `settings.local.json`에서 hooks 항목 삭제 | — |

## Context Health Protocol (v2.3)

롱 세션에서 컨텍스트 윈도우 사용량을 모니터링하고 선제적으로 대응한다.

### 자동 감지 시점

| 시점 | 트리거 |
|------|--------|
| Loop 2+ 진입 시 | Verify 반복 시작 전 |
| Verify 완료 후 | 다음 Loop 또는 종료 전 |
| 대규모 파일 읽기 후 | 500줄 이상 파일 3개 이상 읽은 경우 |

### 임계값 대응

| 사용량 | 레벨 | 대응 |
|--------|------|------|
| **70%** | ⚠️ WARNING | "컨텍스트 70% 도달. 불필요한 파일 읽기 최소화하고 핵심 변경에 집중" |
| **80%** | 🔶 RECOMMEND | "/compact 실행 후 프로파일 재로드 권장. 현재 Loop 완료 후 압축 진행" |
| **85%** | 🔴 CRITICAL | "즉시 /compact 실행 필수. 압축 후 프로파일 + 현재 Phase 문서 재로드하여 계속" |

### 압축 후 복구 절차

```
1. /compact 실행 후 컨텍스트 요약됨
2. ## Project Profile 헤더 존재 확인
3. IF 헤더 없음:
   - discover-project.sh 재실행 (캐시에서 로드)
   - 현재 Phase의 Required Reads 재로드
4. IF Loop 진행 중:
   - verify-snapshot.json 재로드
   - 현재 Loop 번호 유지하여 계속
5. 복구 완료 메시지 출력 후 작업 재개
```

### 컨텍스트 절약 지침

- **Loop 2+**: 프로토콜/레퍼런스 문서 재로드 금지 (Loop 1에서 이미 로드됨)
- **Verify**: 변경된 파일만 읽기 (`--changed-only` 옵션)
- **대용량 파일**: 필요한 섹션만 offset/limit으로 읽기
- **에러 해결**: error-playbook.md의 해당 섹션만 참조

## Status Display Protocol (v2.4)

각 Phase/Loop 진입 시 현재 상태를 간결하게 표시한다.

### 표시 형식

```
[sub-kopring-engineer] Phase: {phase} | Loop: {n}/{max} | Tier: {tier} | Context: {pct}% {bar}
```

**예시:**
```
[sub-kopring-engineer] Phase: Verify | Loop: 3/5 | Tier: STANDARD | Context: 67% ▓▓▓▓▓▓░░░░
[sub-kopring-engineer] Phase: Implement | Loop: 1/3 | Tier: LIGHT | Context: 45% ▓▓▓▓░░░░░░
[sub-kopring-engineer] Phase: Plan | Tier: N/A | Context: 23% ▓▓░░░░░░░░
```

### 표시 요소

| 요소 | 설명 | 값 예시 |
|------|------|---------|
| **Phase** | 현재 단계 | Discovery, Brainstorm, Plan, Implement, Verify |
| **Loop** | 현재/최대 루프 (Verify만) | 1/3, 2/5 |
| **Tier** | 현재 검증 티어 | LIGHT, STANDARD, THOROUGH |
| **Context** | 컨텍스트 사용량 추정 | 67% |
| **Bar** | 시각적 프로그레스 바 | ▓▓▓▓▓▓░░░░ |

### 표시 시점

| 이벤트 | 표시 여부 |
|--------|----------|
| Phase 진입 | ✅ 표시 |
| Loop 시작 (Verify) | ✅ 표시 |
| Tier 에스컬레이션 | ✅ 표시 + 변경 사유 |
| 컨텍스트 임계값 도달 | ✅ 표시 + 경고 메시지 |
| 작업 완료 | ✅ 최종 상태 표시 |

### 프로그레스 바 생성

```
Context %  →  Bar (10칸)
0-9%       →  ░░░░░░░░░░
10-19%     →  ▓░░░░░░░░░
20-29%     →  ▓▓░░░░░░░░
...
90-100%    →  ▓▓▓▓▓▓▓▓▓▓
```

## Session Wisdom Protocol (v2.5)

세션 간 아키텍처 결정과 학습 내용을 축적하여 장기 프로젝트 맥락을 유지한다.

### 저장 위치

```
.sub-kopring-engineer/PROGRESS.md
```

> 템플릿: [templates/progress-template.md](./templates/progress-template.md)

### 기록 시점

| 시점 | 기록 내용 | 자동/수동 |
|------|----------|----------|
| **Plan 완료** | 아키텍처 결정 (Port 추가, 모듈 변경) | 자동 |
| **에러 해결** | 이슈 + 원인 + 해결 방법 | 자동 |
| **패턴 발견** | 사용자 확인된 패턴 | 수동 (사용자 승인) |
| **Loop 완료** | 위반 해결 히스토리 | 자동 |
| **세션 종료** | 다음 세션 TODO | 자동 |

### 활용 시점

| 시점 | 활용 방법 |
|------|----------|
| **세션 시작** | PROGRESS.md 존재 시 읽어서 이전 맥락 파악 |
| **Plan 단계** | 이전 아키텍처 결정 참조하여 일관성 유지 |
| **에러 발생** | 이전 해결 사례 참조하여 빠른 해결 |
| **패턴 생성** | 이전 학습된 패턴과 충돌 여부 확인 |

### PROGRESS.md 구조

```markdown
## {YYYY-MM-DD} Session

### 작업 요약
- {수행한 주요 작업}

### 아키텍처 결정
| 결정 | 근거 | 영향 범위 |
|------|------|----------|

### 발견된 이슈
| 이슈 | 원인 | 해결 방법 |
|------|------|----------|

### 반복 에러 패턴
| 에러 시그니처 | 발생 횟수 | 최근 발생일 | 원인 | 해결 방법 | 승격 여부 |
|-------------|----------|-----------|------|----------|----------|

> 동일 위반(violation) 시그니처가 3회 이상 기록되면 error-playbook.md 프로젝트 확장으로 승격을 제안한다.

### 학습된 패턴
| 패턴 유형 | 패턴 내용 | 적용 위치 |
|----------|----------|----------|

### 다음 세션 TODO
- [ ] {미완료 작업}
```

### 보존 규칙

- **최근 5개 세션** 유지 (이전 세션은 요약으로 압축)
- **중요 결정**은 영구 보존 (아키텍처 변경, 모듈 추가)
- **반복 이슈**는 error-playbook.md로 승격 제안 (아래 절차 참조)

### 에러 패턴 승격 절차 (v2.7)

에러가 PROGRESS.md "반복 에러 패턴" 테이블에 3회 이상 기록된 경우:
1. PROGRESS.md에서 해당 에러 패턴의 시그니처/원인/해결 방법 추출
2. error-playbook.md의 형식에 맞춰 해결 프로토콜 초안 작성
3. 사용자에게 승격 제안: `"이 에러가 3회 반복됐습니다. error-playbook에 추가할까요?"`
4. 승인 시: error-playbook.md 하단에 `## Project-Specific Errors` 섹션으로 추가
5. 거부 시: PROGRESS.md에만 유지, 승격 여부를 "거부"로 표기
