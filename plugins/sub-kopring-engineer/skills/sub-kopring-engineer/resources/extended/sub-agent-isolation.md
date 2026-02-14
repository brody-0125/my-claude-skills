# Sub-agent Isolation Protocol

> Extracted from implement-protocol.md §2-2. Defines sub-agent separation, parallel execution, context scoping, and lifecycle management for complex tasks.

When changes span **10 or more files** or **3 or more layers**,
sub-agents are separated to prevent context pollution.

**Single module:**

| Agent | Responsibility | Input |
|-------|---------------|-------|
| **Domain Agent** | Write core + application code | Plan's per-layer changes + architecture documents |
| **Infrastructure Agent** | Write infrastructure + app code | Plan + Port interface definitions |
| **Test Agent** | Write test code | Implemented code + testing documents |

**Multi-module (when profile has modules):**

| Agent | Responsibility | Modules |
|-------|---------------|---------|
| **Domain Agent** | Domain model, ports, use cases | :core + :application (or :{domain}-core + :{domain}-application) |
| **Infrastructure Agent** | Adapters, repositories | :infrastructure (or :{domain}-infrastructure) |
| **API Agent** | Controllers, HTTP models | :api |
| **Test Agent** | All tests | All modules (test/integrationTest/testFixtures) |

Isolation principles:
- Each agent modifies only the files it is responsible for
- API contracts between agents are defined by Port interfaces
- Test Agent only reads implementation code; it does not modify it
- Multi-module: Module boundary = natural agent boundary

Changes under 5 files are executed sequentially in a single context.

---

## 1-1. Parallel Execution Protocol (v2.5)

멀티모듈 대규모 변경 시 병렬 서브에이전트 실행으로 성능을 최적화한다.

### 활성화 조건

다음 조건을 **모두** 만족할 때 병렬 실행 활성화:
- 프로젝트 모듈 수 ≥ 3
- 변경 대상 모듈 ≥ 2
- 변경 파일 수 ≥ 10

### 파일 소유권 규칙

```
┌─────────────────────────────────────────────────────────────┐
│                    Orchestrator (Main)                       │
│  - Plan 해석 및 에이전트 할당                                 │
│  - Port 인터페이스 수정 (공유 파일)                           │
│  - 최종 통합 검증                                             │
└─────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│Domain Agent │ │ Infra Agent │ │  API Agent  │ │ Test Agent  │
│:core        │ │:infra       │ │:api         │ │(읽기 전용)  │
│:application │ │             │ │             │ │전체 모듈    │
└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
```

| 에이전트 | 소유 모듈 | 수정 가능 | 읽기 가능 |
|---------|----------|----------|----------|
| **Orchestrator** | 없음 (조율 전용) | Port 인터페이스만 | 전체 |
| **Domain Agent** | :core, :application | 소유 모듈 내 파일만 | 전체 |
| **Infra Agent** | :infrastructure | 소유 모듈 내 파일만 | 전체 |
| **API Agent** | :api | 소유 모듈 내 파일만 | 전체 |
| **Test Agent** | 없음 | test/, integrationTest/ 전체 | 전체 (읽기 전용) |

### 공유 파일 처리

| 파일 유형 | 처리 방법 |
|----------|----------|
| **Port 인터페이스** | Orchestrator만 수정. 다른 에이전트는 읽기 전용 |
| **공통 DTO/VO** | 마지막 통합 단계에서 Orchestrator가 병합 |
| **build.gradle.kts** | 변경 필요 시 해당 모듈 에이전트가 수정 |
| **shared-kernel** | Domain Agent가 담당 (의존성 방향 상 최상위) |

### 실행 흐름

```
1. Orchestrator: Plan 분석 → 모듈별 작업 분배
2. Orchestrator: Port 인터페이스 먼저 정의 (병렬 실행 전)
3. 병렬 실행:
   - Task 도구로 Domain Agent spawn (allowed_tools: Read, Write, Edit)
   - Task 도구로 Infra Agent spawn (allowed_tools: Read, Write, Edit)
   - Task 도구로 API Agent spawn (allowed_tools: Read, Write, Edit)
4. 순차 실행:
   - 모든 구현 에이전트 완료 대기
   - Test Agent spawn (모든 구현 코드 읽기 가능)
5. Orchestrator: 통합 검증
   - 컴파일 확인: ./gradlew compileKotlin compileJava
   - 충돌 해결 (Port 시그니처 불일치 등)
```

### 에이전트 프롬프트 템플릿

**Domain Agent:**
```
You are Domain Agent for {project-name}.
Your responsibility: :core and :application modules only.

Files you can modify:
{list of files in :core and :application from Plan}

Port interfaces (READ-ONLY):
{list of Port files - do not modify}

Task: Implement the domain logic and use cases as specified in the Plan.
Follow references/hexagonal-architecture.md and references/code-style-guide.md.
```

**Infra Agent:**
```
You are Infrastructure Agent for {project-name}.
Your responsibility: :infrastructure module only.

Files you can modify:
{list of files in :infrastructure from Plan}

Port interfaces to implement (READ-ONLY definitions):
{Port interface signatures}

Task: Implement Adapters and Repositories as specified in the Plan.
```

### 충돌 방지 규칙

1. **파일 잠금**: 각 에이전트는 할당된 파일만 수정
2. **Port 우선**: Port 인터페이스는 병렬 실행 전에 확정
3. **순서 보장**: Test Agent는 구현 완료 후 실행
4. **충돌 시**: Orchestrator가 merge conflict 해결

### 비활성화 조건

다음 중 하나라도 해당되면 순차 실행으로 fallback:
- 모듈 간 순환 의존성 감지
- Port 인터페이스가 Plan에서 미확정
- 변경 파일 10개 미만 (오버헤드 > 이득)

---

## 1-2. Agent Context Scope Rules (v2.6)

서브에이전트 스폰 시, 프롬프트에 포함할 컨텍스트를 에이전트 역할에 따라 필터링한다.
**파일 소유권(§1-1)이 "어떤 파일을 수정할 수 있는가"를 제어한다면, Context Scope는 "어떤 정보를 프롬프트에 전달하는가"를 제어한다.**

### Context Scope 매트릭스

| 에이전트 | 포함 컨텍스트 | 제외 컨텍스트 |
|---------|-------------|-------------|
| **Domain Agent** | 요구사항, 도메인 모델, Port 인터페이스, 비즈니스 규칙, code-style-guide | Infrastructure 구현 세부사항, API 설정, 테스트 코드, DB 스키마 DDL |
| **Infra Agent** | Port 인터페이스, DB 스키마, 외부 API 스펙, 설정 파일, jooq-conventions (해당 시) | 도메인 비즈니스 규칙, UseCase 구현 세부사항, 테스트 코드 |
| **API Agent** | Port 인터페이스, DTO 정의, API 스펙, 인증/인가 규칙 | 도메인 내부 로직, Infrastructure 구현, 테스트 코드 |
| **Test Agent** | Port 인터페이스, 비즈니스 규칙 요약, 기존 테스트 패턴, unit/integration-testing refs | Infrastructure 구현 세부사항, DB 스키마 DDL |

### 적용 규칙

```
1. Plan 산출물 분할: 전체 Plan을 에이전트에게 전달하지 않는다
   → Plan에서 해당 에이전트 담당 레이어의 변경 사항만 발췌하여 전달
   → 다른 레이어 변경 사항은 "Port 인터페이스 시그니처" 수준으로만 요약

2. Reference 문서 선별: 에이전트 역할에 필요한 reference만 로딩 지시
   → Domain Agent: hexagonal-architecture.md, code-style-guide.md
   → Infra Agent: hexagonal-architecture.md, code-style-guide.md, jooq-conventions.md (해당 시)
   → API Agent: hexagonal-architecture.md, code-style-guide.md
   → Test Agent: unit-testing.md, integration-testing.md (언어별)

3. 기존 코드 참조: 에이전트가 읽어야 할 기존 파일을 명시적으로 지정
   → 자신의 레이어 + Port 인터페이스만 Read 대상으로 제한
   → "전체 코드를 읽어라" 지시 금지
```

**명시적 지정 메커니즘:**

| 항목 | 정의 |
|------|------|
| **지정 주체** | Orchestrator (Main Agent). 서브에이전트 스폰 전에 결정 |
| **지정 시점** | §1-1 병렬 실행 조건 확인 → YES → 에이전트 할당 직후, 스폰 직전 |
| **지정 방식** | 프롬프트 템플릿(§1-1)의 `{owned_files}` + `{reference_docs}` 필드에 직접 기입 |
| **검증** | 서브에이전트가 소유권 외 파일 수정 시도 → Orchestrator가 Result Merge(§1-3)에서 거부 |

Orchestrator는 Plan 산출물의 파일 목록 + §1-1 소유권 매트릭스를 교차하여,
각 에이전트의 Read/Write 허용 범위를 프롬프트에 명시한다.
별도 manifest 파일은 생성하지 않는다 — 프롬프트 내 인라인 지정으로 충분.

### 프롬프트 템플릿 확장 (§1-1 템플릿에 추가)

기존 에이전트 프롬프트 템플릿(§1-1)에 아래 Context Scope 블록을 추가한다:

**Domain Agent (확장):**
```
Context Scope:
- Plan (Domain section only): {Plan에서 core/application 레이어 발췌}
- Port interfaces: {Port 인터페이스 파일 목록 — READ-ONLY}
- Business rules: {요구사항에서 도메인 규칙 발췌}
- References: hexagonal-architecture.md, code-style-guide.md
- DO NOT read or reference: infrastructure/, api/, test/ directories
```

**Infra Agent (확장):**
```
Context Scope:
- Plan (Infrastructure section only): {Plan에서 infrastructure 레이어 발췌}
- Port interfaces to implement: {Port 인터페이스 시그니처}
- DB schema context: {관련 Entity/테이블 정보}
- References: hexagonal-architecture.md, code-style-guide.md, jooq-conventions.md
- DO NOT read or reference: application/ UseCase internals, test/ directories
```

**API Agent (확장):**
```
Context Scope:
- Plan (API section only): {Plan에서 api 레이어 발췌}
- Port interfaces (UseCase signatures): {UseCase 메서드 시그니처만}
- DTO definitions: {Request/Response DTO 명세}
- References: hexagonal-architecture.md, code-style-guide.md
- DO NOT read or reference: core/ domain internals, infrastructure/ internals
```

**Test Agent (확장):**
```
Context Scope:
- Plan (Test section only): {Plan에서 test 관련 사항 발췌}
- Port interfaces: {Port 인터페이스 — 테스트 대상 계약}
- Business rules summary: {비즈니스 규칙 요약 — Stub/Fake 설계 근거}
- Existing test patterns: {기존 테스트 패턴 샘플}
- References: unit-testing.md, integration-testing.md
- DO NOT read or reference: infrastructure/ implementation details
```

### 기대 효과

- 에이전트당 프롬프트 토큰 30-50% 절감 (불필요한 레이어 정보 제거)
- 에이전트 집중도 향상 (관련 없는 컨텍스트로 인한 혼동 방지)
- 레이어 격리 원칙 강화 (프롬프트 수준에서 아키텍처 경계 강제)

---

## 1-3. Scoped Agent Lifecycle Protocol (v2.6)

서브에이전트는 아래 3단계 생명주기를 따른다. 에이전트 간 컨텍스트 누수를 방지하고, 부분 실패 시 성공 결과를 보존한다.

### 1단계: Scope Declaration (시작)

에이전트 스폰 시 Task 도구 프롬프트에 다음을 명시한다:
```
- 담당 파일 목록 (소유권 범위) — §1-1 파일 소유권 규칙 참조
- 참조 가능한 읽기 전용 파일 (Plan 산출물, Port 인터페이스)
- 참조 불가 파일 (다른 에이전트 소유 파일 — Context Scope §1-2 참조)
- 로딩할 reference 문서 목록
```

### 2단계: Isolated Execution (실행)

- 소유권 범위 밖 파일 수정 시도 → 즉시 중단, 에이전트 결과에 violation으로 기록
- 읽기 전용 파일 변경 시도 → 금지 (Port 인터페이스는 Orchestrator만 수정)
- 에이전트는 자신의 작업 완료 시 변경 파일 목록을 정리하여 반환

### 3단계: Result Merge (종료)

```
1. 각 에이전트 완료 시 반환 정보:
   - 변경된 파일 목록 (경로 + 작업 유형: new/modified)
   - 성공/실패 상태
   - 실패 시: 에러 메시지 + 실패 파일 목록

2. Orchestrator 병합 절차:
   a. 모든 에이전트 결과 수집
   b. 파일 충돌 확인 (동일 파일을 여러 에이전트가 수정한 경우)
   c. 충돌 없음 → 그대로 채택
   d. 충돌 발생 → 충돌 파일만 Orchestrator가 직접 해결

3. 부분 실패 처리 (Partial Success Preservation):
   - 에이전트 A 성공 + 에이전트 B 실패 → A의 결과는 보존
   - 실패한 에이전트의 담당 파일만 Orchestrator가 순차 재구현
   - 성공한 결과를 롤백하지 않음
```
