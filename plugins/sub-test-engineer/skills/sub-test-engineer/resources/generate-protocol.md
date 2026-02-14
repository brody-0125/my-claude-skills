# Phase 3: Generate Protocol

> Generates test code following the approved strategy, project patterns, and type-driven test case discovery.

## 0. Entry Decision

```
IF entry from Phase 2 (initial generation):
  → Full generation: create all planned test files from strategy document
  → Input: Strategy Document + Analysis Report + test-profile.json

IF entry from Phase 4 (gap-targeted loop back):
  → Gap-targeted generation ONLY
  → Input: Gap Report + existing test file paths
  → Do NOT regenerate passing tests
  → Append new test methods to existing test files where applicable
```

## 1. Pre-Generation Checklist

Before generating any test code:
- [ ] Test profile loaded (Phase 0 output)
- [ ] Learned test patterns available (naming, structure, assertion style)
- [ ] Strategy document approved (Phase 2 output)
- [ ] Code-under-test fully read (all target source files)
- [ ] Existing tests for targets identified (avoid duplication)

## 2. Existing Test Handling

**Before creating any test file, check for existing tests:**

```
glob "**/{TargetName}Test.{kt,java}" OR "**/{TargetName}.test.{ts,tsx}"

IF existing test file found:
  → READ existing test file completely
  → Catalog existing test methods (what is already tested?)
  → Generate ONLY missing test cases (new methods appended)
  → Preserve existing imports, setup, teardown, fixtures
  → Follow the same naming/structure patterns as existing tests

IF no existing test file:
  → Create new file following project naming convention
  → Place in correct test directory (mirror source directory structure)
```

## 3. Generation Order

```
1. Unit tests (domain → service → controller) — fastest feedback
2. Integration tests (repository → event handler) — slower, run after units pass
3. Property-based tests (domain objects) — complement unit tests
4. Architecture tests (cross-cutting) — run independently
5. Contract tests (API endpoints) — if multi-service context
```

## 4. Focal Context Injection

Instead of injecting entire source files into the generation context (~3,000 tokens/file), construct a **Focal Context** per target (~750 tokens/target):

### Token Budget per Target

| Component | Estimated Tokens | Required |
|-----------|-----------------|----------|
| Test Infrastructure + Learned Conventions | ~150 | YES |
| Target class declaration + signatures | ~200 | YES |
| Dependency interface signatures | ~200 | YES |
| Strategy allocation (technique + target) | ~50 | YES |
| Pattern example (one representative test) | ~150 | IF available |
| Gap-specific code (loop 2+ only) | ~100 | IF loop back |

### Focal Context Template

```markdown
## Test Generation Context

### Test Infrastructure
- Framework: {kotest|junit5|jest|vitest}
- Mock: {mockk|mockito|jest.mock|ts-mockito}
- Assertions: {strikt|assertj|kotest-matchers|jest-expect|chai}
- Base test class: {if exists, e.g., AbstractIntegrationTest}

### Learned Conventions (from Phase 0)
- Naming: {backtick-descriptive|@DisplayName|it-should|describe-it}
- Structure: {AAA|Given-When-Then|SUT pattern}
- Fixture: {builder|factory method|beforeEach|companion object}
- Mock style: {every-returns|when-thenReturn|jest.fn}
- Test data: {inline|fixture file|test data builder}

### Target: {ClassName}
```{language}
{class declaration with constructor parameters}
{public/internal method signatures with parameter types and return types}
{NO method bodies — signatures only}
```

### Dependencies to Mock
```{language}
{interface/abstract class signatures of each constructor dependency}
{include only method signatures that the target class actually calls}
```

### Strategy
- Layer: {Domain|Service|Infrastructure|API|Event}
- Technique: {technique from strategy document}
- Coverage target: {N%}
- Edge cases: {list from analysis report}

### Pattern Example
```{language}
{one representative test from the project's existing test suite}
{chosen to match the target's technique and layer}
```

### Gap Targets (loop 2+ only)
```
{uncovered lines/branches from Gap Report}
{survived mutants from Gap Report}
```
```

## 5. Type-Driven Test Case Derivation

### 5.1 From Sealed Classes / Union Types
```
sealed class PaymentResult {
  data class Success(val transactionId: String) : PaymentResult()
  data class Failed(val reason: FailReason) : PaymentResult()
  data class Pending(val retryAfter: Duration) : PaymentResult()
}
```
→ Generate: 1 test per subclass (Success, Failed, Pending)
→ Generate: exhaustive `when` coverage assertion

### 5.2 From Enums
```
enum class OrderStatus { CREATED, CONFIRMED, SHIPPED, DELIVERED, CANCELLED }
```
→ Generate: `@EnumSource(OrderStatus::class)` parameterized test
→ Generate: state transition tests (valid transitions + invalid transition rejection)

### 5.3 From Validation Annotations
```
@field:Min(1) @field:Max(1000) val quantity: Int
```
→ Generate: boundary tests for {0, 1, 1000, 1001}

### 5.4 From Nullable Types
```
fun process(input: String?): Result
```
→ Generate: null input test + non-null input test

### 5.5 From Generic Constraints
```
fun <T : Comparable<T>> findMax(items: List<T>): T
```
→ Generate: empty list (error), single element, multiple elements with known ordering

## 6. Test Structure Templates

### Unit Test — Kotlin (Kotest BehaviorSpec)
```kotlin
class {TargetName}Test : BehaviorSpec({
    val {dep1} = mockk<{Dep1Type}>()
    val {dep2} = mockk<{Dep2Type}>()
    val sut = {TargetName}({dep1}, {dep2})

    Given("{precondition description}") {
        every { {dep1}.{method}(any()) } returns {stub}

        When("{action description}") {
            val result = sut.{method}({params})

            Then("{expected outcome}") {
                result shouldBe {expected}
                verify(exactly = 1) { {dep1}.{method}(any()) }
            }
        }
    }
})
```

### Unit Test — Java (JUnit5)
```java
@ExtendWith(MockitoExtension.class)
class {TargetName}Test {
    @Mock private {Dep1Type} {dep1};
    @Mock private {Dep2Type} {dep2};
    @InjectMocks private {TargetName} sut;

    @Nested
    @DisplayName("{precondition description}")
    class {PreconditionName} {
        @BeforeEach
        void setUp() {
            when({dep1}.{method}(any())).thenReturn({stub});
        }

        @Test
        @DisplayName("{expected outcome}")
        void {testMethodName}() {
            // Act
            var result = sut.{method}({params});
            // Assert
            assertThat(result).isEqualTo({expected});
            verify({dep1}, times(1)).{method}(any());
        }
    }
}
```

### Unit Test — TypeScript (Jest)
```typescript
describe('{TargetName}', () => {
    let sut: {TargetName};
    let {dep1}: jest.Mocked<{Dep1Type}>;

    beforeEach(() => {
        {dep1} = { {method}: jest.fn() } as any;
        sut = new {TargetName}({dep1});
    });

    describe('{method}', () => {
        describe('when {precondition}', () => {
            beforeEach(() => {
                {dep1}.{method}.mockResolvedValue({stub});
            });

            it('should {expected outcome}', async () => {
                const result = await sut.{method}({params});
                expect(result).toEqual({expected});
                expect({dep1}.{method}).toHaveBeenCalledWith({args});
            });
        });
    });
});
```

### Property Test (Kotlin/jqwik)
```kotlin
@Property
fun `{invariant description}`(@ForAll {param}: {Type}) {
    val sut = {TargetName}()
    val result = sut.{method}({param})
    assertThat(result).satisfies { /* invariant check */ }
}
```

### Integration Test (Kotlin/Spring)
```kotlin
@DataJpaTest
@Testcontainers
class {TargetName}IntegrationTest {
    @Container
    val postgres = PostgreSQLContainer("postgres:15")

    @Autowired
    lateinit var sut: {TargetName}

    @Test
    fun `{scenario description}`() {
        // Arrange: seed test data
        // Act: call repository method
        // Assert: verify database state
    }
}
```

Adapt all templates to project's detected patterns (from Phase 0 learned patterns). When the project uses different conventions (e.g., `@DisplayName` instead of backtick names), follow the project convention.

## 7. Large Scope Processing (5+ test classes)

For large scopes (5+ targets), two strategies are available:

### 7.1 Sequential Target Processing (Default)

For large scopes, process targets one-by-one instead of all at once:

1. Sort targets by priority (highest uncovered first)
2. For each target:
   a. Generate tests for this target only
   b. Run compilation check
   c. If compilation fails → apply 3-Strike recovery for this target
   d. Move to next target
3. After all targets processed → run full validation (Phase 4)

Rationale: Sequential processing avoids context window pressure and ensures
each target gets full attention. For 5+ targets, consider splitting into
multiple `/sub-test-engineer` invocations (e.g., 3 targets per invocation).

### 7.2 Agent Teams Parallel Processing (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set AND targets ≥ 5:

```
Entry Check:
  scripts/agent-teams/check-agent-teams.sh --quiet
  IF exit code = 0 → use Agent Teams
  IF exit code ≠ 0 → fallback to Sequential (7.1)

Multi-Module Check:
  scripts/agent-teams/detect-modules.sh --json
  IF module_count >= 3 AND partition_mode = "module"
    → Partition by module instead of technique
```

#### Full Agent Teams Workflow

```
Phase 3a: Team Initialization
─────────────────────────────
1. Generate team name: "sub-test-gen-$(date +%Y%m%d-%H%M%S)"

2. Partition targets:
   scripts/agent-teams/partition-targets.sh strategy.md --by-technique --json
   → Outputs: {"unit-tester": [...], "integration-tester": [...], "property-tester": [...]}

3. Spawn team:
   Teammate({operation: "spawnTeam", team_name: "{team-name}"})

Phase 3b: Parallel Generation
─────────────────────────────
4. Spawn Teammates with prompt templates:
   FOR each technique in [unit, integration, property]:
     IF technique has assigned targets:
       Task({
         team_name: "{team-name}",
         name: "{technique}-tester",
         subagent_type: "general-purpose",
         prompt: templates/prompts/{technique}-tester.md with:
           {{TEAM_NAME}} = {team-name}
           {{STRATEGY_DOCUMENT_PATH}} = {path}
           {{ASSIGNED_TARGETS}} = {targets}
         run_in_background: true
       })

5. Poll for completion:
   scripts/agent-teams/poll-inbox.sh {team-name} --wait --timeout 300
   → Blocks until all Teammates complete or timeout

Phase 3c: Result Collection
─────────────────────────────
6. Aggregate results:
   scripts/agent-teams/aggregate-results.sh {team-name} --format json
   → Outputs: generated_files[], compile_results, errors[]

7. Graceful shutdown:
   scripts/agent-teams/shutdown-team.sh {team-name} --keep-logs
   → Collects final results and cleans up

Phase 3d: Handoff to Phase 4
─────────────────────────────
8. IF all Teammates completed successfully:
     → Pass combined generated_files to Phase 4
   ELSE IF partial success:
     → Pass successful files to Phase 4
     → Sequential fallback for failed targets
   ELSE:
     → Log failure, fallback to full Sequential processing
```

**When to use Agent Teams:**
- Targets ≥ 5 AND time is critical
- Multi-module project AND modules ≥ 3
- THOROUGH tier with mutation testing

**When to prefer Sequential:**
- Targets < 5 (overhead > benefit)
- Token cost minimization required
- Agent Teams not enabled

**Graceful Degradation:**
If Teammate spawn fails or times out (5 minutes):
1. Log failure reason
2. Reclaim failed Teammate's targets: `aggregate-results.sh {team} --format json`
3. Clean up: `shutdown-team.sh {team} --force`
4. Process reclaimed targets sequentially
5. Continue with successful Teammates' results

**Error Handling:**
See [Error Playbook § Agent Teams](./error-playbook.md#12-agent-teams-errors-experimental) for common issues and resolutions.

## 8. Gap-Targeted Generation (Loop 2+)

When entering from Phase 4 via Gap Report:

```
1. Read Gap Report from Phase 4
2. For each uncovered code path:
   → Read the specific source lines
   → Determine what input would exercise that path
   → Generate a targeted test method
3. For each survived mutant:
   → Understand the mutation (what operator/call was changed)
   → Generate a test that distinguishes original from mutant
4. For quality violations:
   → Fix the specific issue in existing test
   → Use Edit tool (not Write) to modify in-place
5. Append new tests to existing test files
   → Do NOT create new test classes for gap tests
   → Follow existing test file structure (if @Nested classes used → add under appropriate @Nested; if flat → append)
   → If no clear grouping convention exists, add under a @Nested/describe block for the method being tested
```

## 9. Anti-Patterns to Avoid

| Anti-Pattern | Correct Pattern |
|--------------|-----------------|
| Testing implementation details (private methods) | Test through public API |
| Mocking everything (including value objects) | Only mock interface dependencies |
| Single assertion per test dogma | Group related assertions logically |
| Copy-paste setup across tests | Extract to fixtures/builders/beforeEach |
| Thread.sleep in async tests | Use awaitility/eventually/waitFor |
| Random data without seed | Use deterministic fixtures or seeded random |
| Testing generated code (DTOs, equals/hashCode) | Trust compiler/framework, skip these |
| Full source file in context | Use Focal Context Template (~750 tokens) |
| Regenerating all tests on loop 2+ | Generate ONLY gap-targeted tests |
| Creating new test file for gap tests | Append to existing test file |
| Ignoring existing test patterns | Learn and follow project conventions |
