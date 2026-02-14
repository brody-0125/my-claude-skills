# Phase 2: Strategize Protocol

> Determines the optimal testing technique for each target based on analysis results.

## 0. Entry Validation

```
Required input: Analysis Report (from Phase 1)
  → Must contain: target list with layer classification, complexity, edge case catalog

IF Analysis Report missing or incomplete:
  → STOP: "Phase 1 Analysis required before strategizing. Run analyze: {target} first."

IF user specified explicit technique (e.g., "property-test: OrderValidator"):
  → Skip decision tree for that target
  → Use specified technique directly
  → Still apply coverage target and test count estimation
```

## 1. Technique Selection Matrix

Based on Phase 1 analysis, apply the following decision tree per target:

```
Is target a Domain object (Entity, Value Object, sealed class)?
  ├── YES → Property-based testing (primary) + Parameterized boundary tests (secondary)
  │         Framework: jqwik/Kotest PBT/fast-check
  └── NO
      Is target a Domain Service (pure business logic)?
        ├── YES → BDD-style unit test (primary) + Snapshot/Approval test for complex output (secondary)
        │         Framework: Kotest BehaviorSpec / JUnit5 @Nested / Jest describe
        └── NO
            Is target an Application Service (orchestration)?
              ├── YES → Mock-based unit test (primary)
              │         Framework: MockK/Mockito/jest.mock
              │         Coverage: happy path + each error branch
              └── NO
                  Is target a Repository/DAO?
                    ├── YES → Integration test with real DB (primary)
                    │         Framework: Testcontainers + @DataJpaTest
                    │         Never mock the database
                    └── NO
                        Is target an API Controller?
                          ├── YES → API test (primary) + Contract test (secondary)
                          │         Framework: MockMvc/supertest + Pact/SCC
                          └── NO
                              Is target an Event Handler?
                                ├── YES → Embedded broker test (primary)
                                │         Framework: @EmbeddedKafka/Testcontainers
                                └── NO → Default: mock-based unit test
```

### Mixed-Concern Class Handling

When a class spans multiple layers (e.g., a service that directly accesses the database):

```
IF target has characteristics of 2+ layers:
  → Split test strategy:
    - Business logic methods → test with mocks (unit)
    - Data access methods → test with Testcontainers (integration)
    - API endpoint methods → test with MockMvc (API)
  → Create separate test classes per concern:
    - {TargetName}UnitTest — mock-based business logic tests
    - {TargetName}IntegrationTest — Testcontainers-based data access tests
  → Document the split rationale in the strategy document
```

## 2. Architecture Test Decision

**Always include architecture tests if:**
- Project uses hexagonal/clean/layered architecture (detected in Phase 0)
- AND ArchUnit/Konsist/dependency-cruiser is available or installable
- AND no existing architecture tests found

**Architecture test targets:**
- Layer dependency rules (domain must not depend on infrastructure)
- Naming conventions (Repository suffix, UseCase suffix)
- Annotation placement (@Transactional only on service layer)

## 3. Coverage Target Calculation

```
Base target: 80% line coverage for changed/new code

Adjustments:
  + Domain layer: target 90% (high value, easy to test)
  + Application service: target 80% (standard)
  - Infrastructure: target 60% (integration tests are expensive)
  - Generated code: target 0% (exclude from coverage)

Mutation testing target (if tool available):
  - STANDARD tier: 60% mutation kill rate
  - THOROUGH tier: 70% mutation kill rate
```

## 4. Test Count Estimation

| Technique | Estimation Formula |
|-----------|-------------------|
| Unit test | 1 happy path + 1 per error branch + 1 per enum variant |
| Property test | 1 property per invariant (typically 2-5 per domain object) |
| Boundary test | 2 per validation annotation (just-in, just-out) |
| Integration test | 1 per CRUD operation + 1 per complex query |
| Contract test | 1 per API endpoint × (success + error responses) |
| Architecture test | 1 per layer rule + 1 per naming convention |

## 5. Validation Tier Selection

Based on **number of test classes generated** (see [validation-tiers.md](./validation-tiers.md) for detailed thresholds):

- **LIGHT**: Few test classes → compile + run + ERROR-only quality check
- **STANDARD**: Moderate test classes → + coverage + mutation on top-priority targets
- **THOROUGH**: Many test classes OR user explicitly requests → + full mutation + quality re-review

**Override:** User can force tier via `validate --tier THOROUGH`

### Graceful Degradation

IF coverage tool not detected in test-profile.json:
  → coverage-target mode: UNAVAILABLE (warn user, suggest adding JaCoCo/Kover/Istanbul)
  → coverage measurement: SKIPPED in Phase 4
  → loop termination: use test-pass-rate only (no coverage-based termination)

IF mutation tool not detected:
  → LIGHT tier: unaffected (mutation not used)
  → STANDARD tier: mutation kill rate check SKIPPED (coverage-only validation)
  → THOROUGH tier: auto-downgrade to STANDARD (warn user)

## 6. User Confirmation Gate

### All-in-one Mode

Present strategy summary and proceed unless user objects:

```markdown
## 전략 요약

| Target | Technique | Est. Tests | Coverage |
|--------|-----------|------------|----------|
| OrderValidator | Property-based | 5 | 90% |
| OrderService | BDD unit + mock | 12 | 80% |
| OrderRepository | Integration | 6 | 60% |

총 예상 테스트: 23건 / 검증 수준: STANDARD
진행합니다. 변경이 필요하면 말씀해주세요.
```

→ Present strategy and proceed to Phase 3 in the same turn. If user interrupts with modifications → adjust and re-present.

### Step-by-step Mode

Present strategy and explicitly wait for approval:

```markdown
## 전략 요약

{same table as above}

이 전략으로 진행할까요? (수정사항이 있으면 알려주세요)
```

→ Wait for explicit user confirmation before proceeding to Phase 3.

### Dry-run Mode

Present full strategy details and HALT:

```markdown
## 전략 시뮬레이션 (dry-run)

{detailed strategy with test count estimation per target}
{technique rationale per target}
{coverage targets}
{validation tier selection rationale}

ℹ dry-run 모드: 실제 테스트 파일은 생성하지 않습니다.
generate 명령으로 실행할 수 있습니다.
```

→ Stop. Do not proceed to Phase 3.

## 7. Output: Test Strategy Document

```markdown
## Test Strategy: {Feature/Package}

### Technique Allocation
| Target | Layer | Technique | Framework | Est. Tests | Coverage Target |
|--------|-------|-----------|-----------|------------|-----------------|
| OrderValidator | Domain | Property-based | jqwik | 5 properties | 90% |
| OrderService | Application | BDD unit + mock | Kotest BehaviorSpec + MockK | 12 cases | 80% |
| OrderRepository | Infrastructure | Integration | Testcontainers + @DataJpaTest | 6 cases | 60% |
| OrderController | API | API test | MockMvc | 8 cases | 80% |

### Priority Order
1. OrderValidator (CRITICAL - 0% coverage, domain logic)
2. OrderService (HIGH - 45% coverage, business rules)
3. OrderController (MEDIUM - has some existing tests)
4. OrderRepository (LOW - simple CRUD, less risk)

### Architecture Tests
- [ ] Domain layer independence rule
- [ ] UseCase interface naming convention
- [ ] @Transactional placement rule

### Validation Tier
- Selected: {LIGHT|STANDARD|THOROUGH}
- Rationale: {estimated test count and complexity justification}

### Excluded from Strategy
- Generated JOOQ classes (auto-generated)
- DTO classes (data-only, no logic)
- Existing passing tests (will not be regenerated)
```
