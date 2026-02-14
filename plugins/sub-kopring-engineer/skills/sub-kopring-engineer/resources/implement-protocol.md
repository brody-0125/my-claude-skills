# Implement Protocol

> Phase 3 (Implement) detailed execution procedure

## Required Reads (skip if already loaded in this session)
> Base Set: see SKILL.md "Context Documents" section (profile, learned patterns, code-style-guide, architecture ref)

**Phase-specific additions:**
- `resources/directory-context-guide.md` (파일 생성/이동 시 필수 — 디렉토리↔레이어 매핑)
- `references/shared/layering-principles.md` (when STANDARD/THOROUGH or multi-layer changes)
- `references/kotlin/unit-testing.md` (when language=kotlin/mixed)
- `references/java/unit-testing.md` (when language=java/mixed)
- `references/kotlin/integration-testing.md` (when language=kotlin/mixed)
- `references/java/integration-testing.md` (when language=java/mixed)
- `references/shared/jooq-conventions.md` (when query-lib includes jooq)
- `resources/error-playbook.md` (always)
- `resources/extended/sub-agent-isolation.md` (when sub-agent isolation is needed — 10+ files or 3+ layers)

---

### 2-0. Pre-flight Check (before entering Implement)

Perform pre-validation of structural conflicts before implementation based on the Plan deliverables.
If violations are found, do not enter Implement and modify the Plan instead.

```
1. Circular dependency risk: Grep to verify new dependencies in Plan don't form cycles with existing modules
2. Port interface completeness: Verify that Ports referenced by new Use Cases are included in the Plan
3. Naming conflict: Glob to verify new class names in Plan don't already exist in the codebase
4. Reference existence: Glob/Grep to verify classes/interfaces referenced in Plan actually exist in codebase
5. On violation → Return to Plan, fix, and re-enter
```

**Reference Existence Check (항목 4) 상세 (v2.6):**
Plan에서 "기존 클래스를 수정" 또는 "기존 인터페이스를 구현"으로 명시된 대상이 실제로 존재하는지 확인한다.
```
- Plan에 명시된 기존 파일 경로 → Glob으로 존재 확인
- Plan에 명시된 상속/구현 대상 클래스 → Grep으로 class/interface 선언 확인
- 미존재 시: Plan에 해당 파일 생성 계획 추가 또는 참조 대상 수정
```

**Reference Existence 위반 대응 Decision Tree:**

| 참조 유형 | 탐색 결과 | 대응 |
|----------|----------|------|
| 상속/구현 대상 Base | 프로젝트에 없음 + learned-patterns에도 없음 | Plan 수정: 참조 대상 변경 또는 생성 계획 추가 |
| 상속/구현 대상 Base | 다른 모듈에 존재 | Plan 수정: 모듈 경로 정정 |
| 외부 의존 Port/Interface | 유사 클래스 존재 (예: `OrderReader` vs `OrderReaderPort`) | 사용자 확인: 기존 사용 vs 신규 생성 |
| 외부 의존 Port/Interface | 존재하지 않음 | Plan 수정: (a) 의존 클래스 생성 계획 추가 또는 (b) 의존 제거 후 범위 조정 |

**절차:**
1. 미존재 참조 **전수 수집** (첫 번째에서 중단하지 않음)
2. 유형별 분류 후 사용자에게 매트릭스 형태로 제시
3. 사용자 승인 후 Plan 수정 → Pre-flight 재수행

### 2-1. Code Writing Order

Dynamically determine code writing order based on the profile's layer paths.

**Learned Patterns Application Guide:**
- If base class found → Review inheritance when creating new classes
- If error hierarchy found → Reuse existing Exception classes
- If test fixture found → Reuse existing Factory/Fixture classes
- If utility imports found → Use existing utility classes (prevent duplication)
- If naming patterns found → Follow the same suffix patterns
- If custom annotations found → Reuse existing custom annotations instead of creating new ones for the same purpose. When creating new ones, follow the same @Target/@Retention patterns
- If annotation combos found → Apply the same annotation combinations to classes of the same nature. Do not introduce combinations not used in the project
- If dependency patterns found → Follow the same dependency combination patterns for classes in the same layer/role. e.g., If Service classes use Reader+Updater+Port combination, new Services should follow the same structure
- If method/layer structure found → Maintain consistency in method signature patterns per layer. e.g., If UseCase follows execute(Command)->Result pattern, new UseCases should follow the same. File placement should also follow existing structure

**Single module:**
```
1. core/domain-model → Definition, business rules
2. core → Port interfaces (add Reader/Appender/Updater methods)
3. application → Use Case Service implementation
4. infrastructure → Adapter/Repository implementation
   - When query-lib includes jooq: Implement JOOQ Adapter (see references/shared/jooq-conventions.md)
5. app → Controller, HTTP models
6. test → Unit tests → Integration tests
```

**Multi-module Hexagonal (when profile has modules):**
```
1. :shared-kernel → Shared Value Objects, Domain Events (if needed)
2. :core (or :{domain}-core) → Domain Model, Port interfaces
3. :application (or :{domain}-application) → Use Case Service
4. :infrastructure (or :{domain}-infrastructure) → Adapter/Repository
   - When query-lib includes jooq: JOOQ Adapter (see references/shared/jooq-conventions.md)
5. :api → Controller, HTTP models
6. :bootstrap → Configuration (if needed)
7. test → Module-specific Unit/Integration tests
```

> Multi-module 상세 규칙: `references/shared/hexagonal-architecture.md` § Multi-Module Hexagonal Architecture

### 2-2. Sub-agent Isolation (complex tasks)

> 상세: [resources/extended/sub-agent-isolation.md](./extended/sub-agent-isolation.md)

변경 대상이 **10개 파일 이상** 또는 **3개 레이어 이상**에 걸칠 때,
Sub-agent Isolation 문서의 Parallel Execution (§1-1), Context Scope (§1-2),
Agent Lifecycle (§1-3) 프로토콜을 참조한다.

### 2-3. Architecture Constraints (mandatory)

> General principles: `references/shared/layering-principles.md`
> Architecture: `references/shared/hexagonal-architecture.md` (layer constraints section)

**Common (Kotlin + Java):**
```
❌ No extracting single-use methods
❌ No ignoring return values
❌ No @Autowired → Use constructor injection
❌ No star imports
```

**Language-specific constraints:**
> Kotlin: `references/kotlin/code-style-guide.md`
> Java: `references/java/code-style-guide.md`

**When using JOOQ:**
> `references/shared/jooq-conventions.md`

### 2-4. Naming Conventions

> Details: language=kotlin/mixed see `references/kotlin/code-style-guide.md`, language=java/mixed see `references/java/code-style-guide.md`

### 2-5. Test Writing Rules (MANDATORY)

> Kotlin: `references/kotlin/unit-testing.md`, `references/kotlin/integration-testing.md`
> Java: `references/java/unit-testing.md`, `references/java/integration-testing.md`

**Tests are NOT optional.** Every implementation MUST include tests. Skipping tests is a blocking violation.

#### Mandatory Test Coverage

For every Service/UseCase method implemented or modified:

1. **Unit Tests** (using Stub/Fake, no Spring context):
   - **Happy path**: At least one test per public method with valid input → expected output
   - **Unhappy path**: At least one test per known error condition → expected exception/error
   - **Boundary cases**: Edge cases for business rules (e.g., exactly at limit, empty collection, null/zero values)
   - **Acceptance criteria**: Each business requirement MUST have a corresponding test

2. **Integration Tests** (Spring context, Testcontainers):
   - **API endpoints**: Every new/modified Controller endpoint must have MockMvc/WebTestClient test
   - **Repository queries**: Custom queries (non-CRUD) must have integration tests with real DB
   - **Cross-layer flows**: At least one end-to-end flow test per feature (Controller → Service → Repository)

#### Test Writing Checklist (verify before marking Implement complete)

```
□ Every new Service/UseCase method has unit tests
□ Happy path covered for each method
□ At least one unhappy path per method (invalid input, business rule violation)
□ Boundary conditions tested (edge values, empty collections, null handling)
□ New API endpoints have integration tests
□ Custom Repository queries have integration tests
□ Test follows Stub > Mock philosophy (use Fake/Stub by default, Mock only when necessary)
□ Each business requirement has at least one corresponding test
```

#### Test Placement

| Test Type | Location | Dependencies |
|-----------|----------|-------------|
| Unit Test (Service/UseCase) | `src/test/` | Stub/Fake only (no Spring) |
| Integration Test (Controller) | `src/integrationTest/` or `src/test/` | Spring context + Testcontainers |
| Integration Test (Repository) | `src/integrationTest/` or `src/test/` | Spring context + Testcontainers |

**If test writing is blocked** (e.g., missing test infrastructure), document the gap in Verify output and create a follow-up task. Never silently skip tests.

### 2-6. Layer-Complete Build Verification (v2.6)

Implement Phase에서 각 레이어 완료 시점에 빌드를 실행하여 컴파일 에러를 조기에 발견한다.
Verify Phase까지 에러를 미루지 않고, 작성 직후 피드백 루프를 돌린다.

#### 실행 조건

- **STANDARD/THOROUGH** tier일 때만 적용
- **LIGHT** tier에서는 스킵 (오버헤드 > 이득)
- **단일 파일 변경** 또는 **테스트만 변경** 시에도 스킵

#### 빌드 검증 시점 및 명령

**Single module:**

| 시점 | Kotlin | Java |
|------|--------|------|
| Domain + Port 완료 | `./gradlew compileKotlin` | `./gradlew compileJava` |
| 전체 구현 완료 (테스트 제외) | `./gradlew compileKotlin` | `./gradlew compileJava` |

→ 총 2회 빌드 (Domain+Port 후 1회, API/Infra 후 1회)

**Multi-module:**

| 시점 | Kotlin | Java |
|------|--------|------|
| :core 완료 | `./gradlew :core:compileKotlin` | `./gradlew :core:compileJava` |
| :application 완료 | `./gradlew :application:compileKotlin` | `./gradlew :application:compileJava` |
| :infrastructure 완료 | `./gradlew :infrastructure:compileKotlin` | `./gradlew :infrastructure:compileJava` |
| :api 완료 | `./gradlew :api:compileKotlin` | `./gradlew :api:compileJava` |
| 전체 완료 (테스트 제외) | `./gradlew compileKotlin` | `./gradlew compileJava` |

→ 모듈별 점진 검증. 병렬 에이전트 사용 시 §2-2-1 실행 흐름의 "5. 통합 검증"과 통합.
→ `./gradlew` 실행 실패 시 (wrapper 미존재 등): 빌드 검증 스킵하고 Verify Phase에서 처리.

**Mixed language:**
- `./gradlew compileKotlin compileJava` (양쪽 모두 실행)

#### 에러 피드백 루프

```
1. 빌드 실행 → 에러 발생
2. 에러 메시지에서 파일:라인 + 에러 유형 추출
3. error-playbook.md 참조하여 해결 방법 결정
4. 해당 레이어 코드 수정
5. 재빌드로 확인
6. 최대 3회 반복
7. 3회 실패 시:
   → 해당 이슈를 snapshot.json에 기록
   → 다음 레이어로 진행 (Verify Phase에서 최종 해결)
   → 사용자에게 중간 빌드 실패 알림: "[Build] {module} 컴파일 실패 3회 — Verify에서 재시도"
```

#### 에러 피드백 루프 적용 예시

```
[Implement] :core compileKotlin 실행...
  → BUILD FAILED: OrderCancelService.kt:25 — Type mismatch: Required OrderStatus, found String
  → error-playbook §2 (Type Mismatch) 참조
  → Fix: toModel() 변환 추가
  → 재빌드: BUILD SUCCESS ✅
  → 다음 레이어 진행: :infrastructure
```

#### 병렬 에이전트와의 통합

병렬 실행(§2-2-1) 시 레이어 빌드 검증은 다음과 같이 통합된다:

```
1. Orchestrator: Port 인터페이스 정의 → :core compileKotlin (Port 정합성 확인)
2. 병렬 에이전트: 각 에이전트는 자신의 모듈 빌드만 실행
   → Domain Agent: :core:compileKotlin, :application:compileKotlin
   → Infra Agent: :infrastructure:compileKotlin
   → API Agent: :api:compileKotlin
3. Orchestrator: 통합 검증 → ./gradlew compileKotlin (전체)
```

---

## Phase Handoff

**Entry Condition**: Plan approved in Phase 2 (NOT dry-run mode) AND Pre-flight Check (§2-0) 전 항목 통과

**Exit → Verify Transition Contract (v2.6):**
Implement 완료 후 Verify로 전환하기 전 아래를 확인한다:
```
□ 최소 1개 파일이 실제로 변경됨 (Write/Edit 도구 사용 이력)
  → 변경 0개이면 Verify 스킵하고 종료
□ 테스트 코드가 Plan에 명시된 대로 작성됨
  → 테스트 누락 시: 테스트 작성 후 재확인 (Implement 계속)
  → 테스트 인프라 부재로 불가 시: verify 결과에 gap 기록 후 진행
□ snapshot.json이 현재 변경 사항을 반영하여 갱신됨
  → 미갱신 시: 변경 파일 목록으로 snapshot.json 생성/갱신
```
미충족 시 Implement를 계속하거나, 변경 사항이 없으면 종료한다.

**Exit Condition**: All planned files written AND tests created

**Next Phase**: → [verify-protocol.md](./verify-protocol.md) (Phase 4 Verify)

**Domain Keyword Effects**:
- `port-first`: Port 인터페이스 먼저 구현 → Adapter 구현 순서 강제
- `test-heavy`: 테스트 커버리지 80% 이상 목표, TDD 스타일
- `infra-only`: Infrastructure 레이어만 변경 (Domain 터치 금지)
