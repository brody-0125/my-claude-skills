# Error Playbook — Test-Specific Error Resolution Protocols

> Resolution protocols for common errors encountered during test generation and validation.
> For the standard error response pattern, see [error-handling-framework.md](error-handling-framework.md).

---

## 1. MockK Errors

> **Default Level**: 2 (Alternative Approach) — Mock configuration errors typically have fallback solutions.

### `io.mockk.MockKException: no answer found`
**Cause:** Mock called with unexpected arguments.
**Resolution:**
1. Check mock setup: `every { mock.method(any()) } returns value`
2. Verify argument matchers match actual call
3. Use `every { mock.method(match { ... }) }` for complex matching

### `io.mockk.MockKException: Failed to transform class`
**Cause:** Mocking final class or inline function.
**Resolution:**
1. Mock the interface, not the implementation
2. If must mock concrete class: add `open` modifier or use `@MockKExtension`
3. For Spring beans: mock the interface type in constructor

## 2. Mockito Errors

> **Default Level**: 2 (Alternative Approach) — Mock configuration errors typically have fallback solutions.

### `org.mockito.exceptions.misusing.UnnecessaryStubbingException`
**Cause:** Stubbed method never called during test.
**Resolution:**
1. Remove unused stub
2. OR use `@MockitoSettings(strictness = Strictness.LENIENT)` if stub is for shared setup

### `org.mockito.exceptions.base.MockitoException: Cannot mock final class`
**Cause:** Java/Kotlin classes are final by default in Kotlin.
**Resolution:**
1. Mock the interface, not the implementation
2. For Kotlin: add `allOpen` Gradle plugin for test scope
3. Add `mockito-extensions/org.mockito.plugins.MockMaker` with `mock-maker-inline`

## 3. Testcontainers Errors

> **Default Level**: 2 (Alternative Approach) — Container issues can fall back to embedded alternatives.

### `org.testcontainers.containers.ContainerLaunchException: Could not create/start container`
**Cause:** Docker not running or resource limits.
**Resolution:**
1. Check Docker daemon: `docker info`
2. Check available resources: `docker system df`
3. Use singleton container pattern to reduce container count
4. Fall back to H2/embedded DB if Docker unavailable (with warning about dialect differences)

### Container startup timeout
**Cause:** Slow image pull or resource contention.
**Resolution:**
1. Increase startup timeout: `.withStartupTimeout(Duration.ofMinutes(3))`
2. Use `@Testcontainers(parallel = true)` for parallel startup
3. Use `@SharedContainerLifecycle` to reuse containers across test classes

## 4. Coverage Tool Errors

> **Default Level**: 2 (Alternative Approach) — Coverage tool issues can skip coverage stage gracefully.

### JaCoCo: `Execution data for class does not match`
**Cause:** Class was recompiled between coverage instrumentation and report generation.
**Resolution:**
1. Gradle: Run `./gradlew clean test jacocoTestReport` (clean first)
2. Maven: Run `mvn clean test jacoco:report`
3. Ensure no caching of instrumented classes

### PIT/Stryker: Out of memory
**Cause:** Too many mutants generated for large codebase.
**Resolution:**
1. Limit target: `--targetClasses` (PIT Gradle/Maven) or `--mutate` (Stryker) to specific packages
2. Increase memory: Gradle: `-Xmx2g` via `pitest { jvmArgs = ['-Xmx2g'] }`, Maven: `<jvmArgs><jvmArg>-Xmx2g</jvmArg></jvmArgs>`
3. For Stryker: `--maxConcurrentTestRunners 2` to reduce parallel load
4. Use incremental mode: `--withHistory` (PIT) or `--incremental` (Stryker)

## 5. Spring Test Context Errors

> **Default Level**: 2 (Alternative Approach) — Context issues can be resolved with configuration adjustments.

### `org.springframework.beans.factory.NoSuchBeanDefinitionException`
**Cause:** Test context does not include required bean.
**Resolution:**
1. Check `@DataJpaTest` vs `@SpringBootTest` — data test slices load only repository beans
2. Add `@Import(RequiredConfig.class)` for additional beans
3. Use `@MockBean` for dependencies not needed in integration test

### `Failed to load ApplicationContext`
**Cause:** Configuration error in test context.
**Resolution:**
1. Check for circular dependencies in test configuration
2. Use `@ActiveProfiles("test")` to load test-specific config
3. Isolate test context: use `@ContextConfiguration(classes = [TestConfig::class])`

## 6. Test Flakiness Patterns

> **Default Level**: 3 (Root Cause Analysis) — Flaky tests require deeper investigation.

### Time-dependent tests
**Detection:** Test passes/fails based on time of day.
**Resolution:**
1. Inject `Clock` instead of `LocalDateTime.now()`
2. Use `Clock.fixed()` in tests
3. Freeze time: `MockK: mockkStatic(LocalDateTime::class)`, Mockito: `MockedStatic`

### Ordering-dependent tests
**Detection:** Test fails when run in different order.
**Resolution:**
1. Ensure `@BeforeEach` resets all state
2. Remove `companion object` shared state
3. Use unique test data per test (random with seed, or index-based)

### Async test failures
**Detection:** Test intermittently times out.
**Resolution:**
1. Replace `Thread.sleep` with `Awaitility.await().atMost(5, SECONDS).until { condition }`
2. For Kotlin coroutines: use `runTest {}` instead of `runBlocking {}`
3. For JS/TS: use `await expect(promise).resolves.toBe(value)`

## 7. ClassGraph / Layer 2 Errors

> **Default Level**: 2 (Alternative Approach) — Layer 2 is optional; falls back to Layer 1a+1b.

### `java: command not found` or Java version < 17
**Cause:** JDK not installed or outdated.
**Resolution:**
1. Layer 2 is optional — skip and use Layer 1a+1b results
2. To enable: install JDK 17+ from https://adoptium.net/

### `classgraph-extractor-all.jar` not found
**Cause:** Extractor JAR not built yet.
**Resolution:**
1. One-time build: `cd scripts/classgraph-extractor && ./gradlew shadowJar`
2. Or skip Layer 2 (Layer 1a+1b is sufficient for most cases)

### ClassGraph scan returns empty results
**Cause:** Classpath doesn't contain compiled classes for target pattern.
**Resolution:**
1. Ensure project is compiled: `./gradlew classes` or `mvn compile`
2. Verify classpath directory contains .class files
3. Check target pattern matches actual package structure

### `OutOfMemoryError` during ClassGraph scan
**Cause:** Large classpath with many classes.
**Resolution:**
1. Narrow target pattern: `com.example.order.**` instead of `com.example.**`
2. Increase JVM heap: modify extract-type-info.sh to add `-Xmx512m` to java command
3. If still failing, skip Layer 2

## 8. Convergence Failure (3-Strike Rule)

> **Level**: 3 (Root Cause Analysis) — Triggered after 3 consecutive identical failures.

If the same error appears in 3 consecutive fix attempts:

1. **Capture**: Record the error message, affected file, and all 3 attempted fixes
2. **Root-cause analysis**:
   - Re-read the source file and test file in full
   - List all 3 previous fixes and why each failed
   - Identify the underlying assumption that is wrong
   - Design a fundamentally different approach (not an incremental patch)
3. **Apply**: Implement the new approach from scratch
4. **If still failing**: Report as unresolvable with full context, suggest manual investigation, and continue with remaining targets

## 9. Test File Generated in Wrong Location

> **Default Level**: 2 (Alternative Approach) — Path issues can be corrected by re-analyzing module structure.

### Generated test class not found during compilation
**Symptom:** Compilation fails with "class not found" or test runner reports zero tests discovered, even though the test file was written successfully.
**Cause:** Test file placed in `src/main` instead of `src/test`, placed in the wrong module directory in a multi-module project, or package declaration does not match the directory path.
**Resolution:**
1. Check `test-profile.json` for the correct `test-root` path (e.g., `src/test/kotlin`, `src/test/java`, `src/__tests__`)
2. In multi-module projects, verify module detection: the test file must be under the same module as the source file it tests
3. Validate that the package declaration in the test file matches the directory structure relative to the test source root
4. For Gradle multi-module: check `settings.gradle.kts` for module paths; test root is `{module}/src/test/{lang}/`
5. For Maven multi-module: check `pom.xml` for module paths; test root is `{module}/src/test/{lang}/`
6. For TypeScript/Jest: verify `roots` or `testMatch` patterns in `jest.config.ts` include the target directory

### Test discovered but wrong source set
**Symptom:** Test compiles but is not picked up by the test task (Gradle) or surefire plugin (Maven).
**Cause:** Test file placed in `src/main` source set or in an integration test source set not included in the default test run.
**Resolution:**
1. Move file to `src/test/{lang}/` source root
2. For integration tests in a separate source set: run with `-PintegrationTest` or the appropriate task
3. Verify file naming: JUnit 5 requires no specific suffix by default, but Surefire defaults to `*Test.java` / `*Tests.java`

## 10. Flaky Test — Passes Individually but Fails in Suite

> **Default Level**: 3 (Root Cause Analysis) — Isolation issues require deeper investigation.

### Test passes alone, fails when run with other tests
**Symptom:** A test passes when executed in isolation (`--tests ClassName.methodName`) but fails when the full test suite runs. Failures may be intermittent.
**Cause:** Shared mutable state between test classes, port conflicts from parallel test execution, database pollution from prior tests, or static/companion object state leaking across tests.
**Resolution:**
1. **Shared state isolation:** Add `@TestInstance(TestInstance.Lifecycle.PER_CLASS)` with proper `@BeforeEach` cleanup, or use `PER_METHOD` (default) and ensure no `companion object` / `static` mutable state
2. **Port conflicts:** Use random ports — Spring: `@SpringBootTest(webEnvironment = RANDOM_PORT)`, Testcontainers: let the container assign a random host port
3. **Database pollution:** Add `@Transactional` to roll back after each test, or use `@Sql` / `@DirtiesContext` to reset state
4. **Parallel execution conflicts:** If using JUnit 5 parallel execution (`junit.jupiter.execution.parallel.enabled=true`), mark conflicting tests with `@Isolated` or `@ResourceLock`
5. **Static mock leakage:** Ensure `MockedStatic` / `mockkStatic` are closed in `@AfterEach` — use try-with-resources or `unmockkAll()`
6. **For TypeScript/Jest:** Check for missing `afterEach(() => jest.restoreAllMocks())` or shared module-level variables

### Detection heuristic
When a test fails only in suite context, the Validate phase should:
1. Re-run the failing test in isolation to confirm it passes alone
2. If it passes alone, flag as `FLAKY:SHARED_STATE` in the Gap Report
3. Apply the isolation fixes above before the next Generate loop

## 11. Coverage Report Not Found After Test Execution

> **Default Level**: 2 (Alternative Approach) — Coverage issues can skip stage gracefully.

### measure-coverage.sh reports N/A despite tests passing
**Symptom:** Tests execute and pass (green), but `measure-coverage.sh` outputs `N/A` or `0%` for coverage, or reports that no coverage data file was found.
**Cause:** Coverage tool (JaCoCo, Kover, Istanbul/c8) not configured in the build system, coverage report generated in an unexpected path, or the coverage task was not executed as part of the test run.

**Resolution (JVM — JaCoCo):**
1. Verify `build.gradle(.kts)` applies the JaCoCo plugin:
   ```kotlin
   plugins {
       jacoco
   }
   ```
2. Ensure `jacocoTestReport` task runs after `test`: `./gradlew test jacocoTestReport`
3. Check report output path — default is `build/reports/jacoco/test/jacocoTestReport.xml`; `measure-coverage.sh` expects this path
4. For Maven: verify `jacoco-maven-plugin` is in `pom.xml` with `prepare-agent` and `report` goals

**Resolution (JVM — Kover):**
1. Verify `build.gradle.kts` applies Kover:
   ```kotlin
   plugins {
       id("org.jetbrains.kotlinx.kover")
   }
   ```
2. Run `./gradlew koverXmlReport` and check `build/reports/kover/report.xml`

**Resolution (TypeScript — Istanbul/c8):**
1. Ensure `jest.config.ts` has `collectCoverage: true` or run with `--coverage` flag
2. Check `coverageDirectory` in Jest config — default is `coverage/`
3. For c8: run with `npx c8 npm test` and check `coverage/lcov.info`
4. Verify `.nycrc` or `c8` config if using a custom reporter — `measure-coverage.sh` expects `lcov` or `clover` format

### Coverage file exists but measure-coverage.sh cannot parse it
**Symptom:** Coverage file exists at the expected path but the script reports a parse error or unexpected format.
**Resolution:**
1. Verify the report format is XML (JaCoCo/Kover) or LCOV (Istanbul/c8) — `measure-coverage.sh` does not support HTML-only reports
2. Regenerate with explicit format: JaCoCo XML (`jacocoTestReport { reports { xml.required = true } }`), Jest LCOV (`coverageReporters: ['lcov']`)
3. If using a non-standard output directory, pass the explicit path to `measure-coverage.sh` via the third argument

## 12. Agent Teams Errors (Experimental)

> **Default Level**: 2 (Alternative Approach) — Agent Teams falls back to sequential processing.

### Teammate spawn fails: "Agent Teams not enabled"
**Symptom:** `spawn-teammate.sh` exits with error "Agent Teams not enabled".
**Cause:** The experimental feature flag is not set.
**Resolution:**
1. Set environment variable: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
2. Or add to `~/.claude/settings.json`:
   ```json
   { "experimental": { "agentTeams": true } }
   ```
3. Restart Claude Code session after enabling

### Teammate inbox never receives completion message
**Symptom:** `poll-inbox.sh --wait` times out, but teammate appeared to be working.
**Cause:** Teammate crashed, got stuck, or completed without sending message.
**Resolution:**
1. Check team directory for partial results: `ls ~/.claude/teams/{team-name}/inboxes/`
2. Use `--timeout` with longer value if teammate is still processing: `poll-inbox.sh {team} --wait --timeout 600`
3. If teammate crashed:
   - Check logs in teammate's output (if using tmux/iterm2 backend)
   - Reclaim targets with `shutdown-team.sh {team} --force --keep-logs`
   - Fall back to sequential processing for failed targets

### Teammates modify same file causing conflicts
**Symptom:** Generated tests have merge conflicts or overwrites.
**Cause:** Multiple teammates assigned overlapping targets.
**Resolution:**
1. Use `partition-targets.sh --by-technique` to ensure disjoint target sets
2. For module-based partitioning, ensure each target belongs to exactly one module
3. Review `team-config.json` to verify no duplicate targets across teammates
4. If conflict detected:
   - Run `aggregate-results.sh {team} --format json` to see all generated files
   - Manually merge or re-run conflicting target with single teammate

### Session resume loses teammates
**Symptom:** After `/resume`, team lead cannot communicate with teammates.
**Cause:** Agent Teams does not support session resumption — teammates are terminated on leader exit.
**Resolution:**
1. This is an expected limitation of Agent Teams (experimental)
2. After resume, the team lead should:
   - Check team directory: `ls ~/.claude/teams/`
   - If team exists, call `shutdown-team.sh {team} --force` to collect partial results
   - Spawn new teammates if continuing parallel work
3. For critical work, prefer sequential processing to avoid resume issues

### Teammate hangs with "waiting for approval"
**Symptom:** Teammate sends `plan_approval_request` message but no response is received.
**Cause:** Teammate is in plan mode requiring approval, but lead is not polling inbox.
**Resolution:**
1. Ensure lead polls inbox frequently: `poll-inbox.sh {team} --wait`
2. When `plan_approval_request` received, lead should respond with approval message
3. To avoid approval requirements, set in teammate spawn:
   ```
   CLAUDE_CODE_PLAN_MODE_REQUIRED=false
   ```

### High token cost from Agent Teams
**Symptom:** Session consumes 2-3x expected tokens.
**Cause:** Each teammate has independent context window, multiplying token usage.
**Resolution:**
1. This is expected behavior — see trade-off analysis in [Agent Teams Analysis](../../../docs/sub-test-engineer-agent-teams-analysis.md)
2. To reduce cost:
   - Only use Agent Teams when targets ≥ 5 (time savings outweigh cost)
   - Prefer `--by-technique` partitioning (3 teammates) over `--by-module` (N teammates)
   - Set lower timeouts to fail fast: `poll-inbox.sh {team} --wait --timeout 180`
3. For cost-sensitive environments, disable Agent Teams and use sequential processing:
   - Remove or unset `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`

### Fallback to sequential processing
When Agent Teams fails (any of the above errors):
1. Log the failure reason
2. Collect any partial results from teammates: `aggregate-results.sh {team} --format json`
3. Clean up team resources: `shutdown-team.sh {team} --force`
4. Process remaining targets sequentially using the standard Generate protocol
5. Mark in the final report that Agent Teams was attempted but fell back to sequential

## 13. Go Testing Errors

> **Default Level**: 2 (Alternative Approach) — Go test errors typically have straightforward fixes.

### `undefined: mock.On` or `undefined: assert.Equal`
**Cause:** testify not imported or wrong import path.
**Resolution:**
1. Add import: `import "github.com/stretchr/testify/mock"` and `"github.com/stretchr/testify/assert"`
2. Ensure testify is in go.mod: `go get github.com/stretchr/testify`
3. Run `go mod tidy` to clean up dependencies

### `cannot use mockRepo (type *MockRepo) as type Repository`
**Cause:** Mock struct does not implement the interface.
**Resolution:**
1. Ensure all interface methods are implemented on the mock
2. Use `mockgen` to generate interface mocks: `//go:generate mockgen -source=repo.go -destination=mock_repo.go -package=order`
3. Run `go generate ./...` to regenerate mocks

### `race detected during execution of test`
**Cause:** Data race in test or code under test.
**Resolution:**
1. Run with race detector to identify: `go test -race ./...`
2. Use proper synchronization (mutex, channels) in shared state
3. For test-only races: use `sync.WaitGroup` or `t.Parallel()` correctly
4. Ensure `t.Parallel()` subtests capture range variables: `tt := tt`

### `context deadline exceeded` in tests
**Cause:** Test timeout or slow external dependency.
**Resolution:**
1. Increase test timeout: `go test -timeout 60s ./...`
2. Use context with timeout in test: `ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)`
3. Mock external dependencies instead of calling real services
4. For Testcontainers: increase container startup timeout

### `panic: runtime error: invalid memory address or nil pointer dereference`
**Cause:** Nil pointer access, often from uninitialized mock or missing setup.
**Resolution:**
1. Check mock setup — ensure `On()` returns non-nil value
2. Verify fixture/builder creates all required fields
3. Add nil checks in test assertions: `require.NotNil(t, result)`
4. For `testify/mock`: use `mock.Anything` for args that might be nil

### Go coverage reports 0% despite tests passing
**Cause:** Coverage not enabled or wrong package path.
**Resolution:**
1. Run with coverage: `go test -cover ./...`
2. For detailed report: `go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out`
3. Ensure test package imports the correct package (not `_test` suffix package for internal tests)
4. For multi-module: run from each module directory or use `-coverpkg=./...`

### `no test files` warning
**Cause:** Test files not following Go convention.
**Resolution:**
1. Ensure test file ends with `_test.go` (e.g., `order_service_test.go`)
2. Ensure test functions start with `Test` prefix (e.g., `TestOrderService_Create`)
3. Ensure test file is in the same package or `{package}_test` for black-box testing
4. Check file is not excluded by build tags

### Ginkgo `Describe` not found
**Cause:** Ginkgo not properly set up.
**Resolution:**
1. Install Ginkgo: `go install github.com/onsi/ginkgo/v2/ginkgo@latest`
2. Add imports:
   ```go
   import (
       . "github.com/onsi/ginkgo/v2"
       . "github.com/onsi/gomega"
   )
   ```
3. Bootstrap suite: `ginkgo bootstrap` in test directory
4. Run with Ginkgo: `ginkgo -r ./...` (not `go test`)

### Table-driven test subtests not running
**Cause:** Missing `t.Run()` or incorrect loop variable capture.
**Resolution:**
1. Use `t.Run(tt.name, func(t *testing.T) { ... })` for each case
2. Capture loop variable: `tt := tt` before `t.Run()` for parallel subtests
3. Example:
   ```go
   for _, tt := range tests {
       tt := tt // capture
       t.Run(tt.name, func(t *testing.T) {
           t.Parallel() // optional
           // test logic using tt
       })
   }
   ```
