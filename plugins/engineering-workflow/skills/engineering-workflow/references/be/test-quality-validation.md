# Test Quality Validation Reference

> Validation pipeline, quality assessment patterns, and gap analysis for the T4 (Quality Assessor) agent.

## 1. 5-Stage Validation Pipeline

### Stage 1: Compilation Check

```bash
# Kotlin projects
./gradlew compileTestKotlin

# Java projects
./gradlew compileTestJava

# Multi-module
./gradlew :module-name:compileTestKotlin
```

**Failure Classification and Auto-fix:**

| Error Type | Detection Pattern | Auto-fix Strategy |
|-----------|-------------------|-------------------|
| Missing import | `Unresolved reference: ClassName` | Search focal class imports, add matching import |
| Type mismatch | `Type mismatch: inferred type is X but Y was expected` | Check focal method signature, correct parameter/return type |
| Unresolved reference | `Unresolved reference: methodName` | Verify method exists in focal class, check visibility |
| Constructor mismatch | `No value passed for parameter` | Compare test constructor call with focal class constructor |
| Overload ambiguity | `Overload resolution ambiguity` | Add explicit type annotations to disambiguate |

**Auto-fix Procedure:**

1. Parse compiler output to extract error location (file, line, column)
2. Classify error using the table above
3. For missing imports: scan `src/main/` for the class, extract package, add import
4. For type mismatches: read focal method signature, compare expected vs actual types
5. For unresolved references: verify method/property exists and is accessible
6. Re-run compilation after fix to confirm resolution

**Retry Policy:** Max 3 auto-fix attempts per error. If unresolved, escalate to gap report.

### Stage 2: Test Execution

```bash
./gradlew test --tests "com.example.service.OrderServiceTest"          # class
./gradlew test --tests "com.example.service.OrderServiceTest.method"   # method
./gradlew test --tests "*OrderService*"                                 # pattern
./gradlew integrationTest --tests "com.example.adapter.OrderAdapterIT"  # integration
```

**Failure Classification:**

| Error Type | Category | Auto-fixable | Resolution Strategy |
|-----------|----------|-------------|---------------------|
| AssertionError | Logic | Partial | Re-read focal method; check if assertion operands are swapped |
| MockK `no answer found` | Setup | Yes | Add `every { } returns value` for missing stub |
| MockK `was not called` | Verification | Yes | Check argument matchers match actual args |
| Mockito `UnnecessaryStubbingException` | Setup | Yes | Remove unused `when().thenReturn()` |
| Mockito `WrongTypeOfReturnValue` | Setup | Yes | Match return type to mock method signature |
| NullPointerException | Null handling | Yes | Add null setup for missing dependency/field |
| Timeout | Async issue | Yes | Replace `Thread.sleep` with Awaitility |
| SpringBoot context failure | Config | Partial | Verify `@ActiveProfiles("test")` and datasource config |
| Testcontainers startup | Infra | No | Verify Docker running; check image and ports |
| StackOverflowError | Recursive mock | Yes | Break circular mock setup; use `relaxed = true` |

**Flaky Test Detection:** Run failed test 3 times in isolation. If results differ, mark as flaky. Common causes: time-dependent assertions, shared mutable state, port conflicts.

### Stage 3: Coverage Measurement

| Tool | Language | Command | Report Location |
|------|----------|---------|-----------------|
| JaCoCo | Java/Kotlin | `./gradlew jacocoTestReport` | `build/reports/jacoco/test/html/index.html` |
| Kover | Kotlin-first | `./gradlew koverReport` | `build/reports/kover/html/index.html` |

**Metrics:** line coverage (executable lines), branch coverage (conditional branches), method coverage (methods invoked).

**Graceful degradation:** If neither JaCoCo nor Kover is configured, skip Stage 3 with a warning. Do not fail the pipeline.

### Stage 4: Mutation Testing (STANDARD/THOROUGH tiers only)

**Tool:** PIT (PITest) -- `./gradlew pitest` -- Report: `build/reports/pitest/index.html`

**Common Mutators:**

| Mutator | Description | Example |
|---------|-------------|---------|
| CONDITIONALS_BOUNDARY | `<` to `<=`, `>` to `>=` | `if (x < 10)` becomes `if (x <= 10)` |
| NEGATE_CONDITIONALS | Negates checks | `if (x == y)` becomes `if (x != y)` |
| MATH | Replaces operators | `a + b` becomes `a - b` |
| RETURN_VALS | Mutates returns | `return true` becomes `return false` |
| VOID_METHOD_CALLS | Removes void calls | `list.add(item)` removed |
| EMPTY_RETURNS | Empty collections | `return listOf(x)` becomes `return emptyList()` |

**Kill Rate:** `kill_rate = (killed_mutants / total_mutants) * 100`

### Stage 5: Quality Assessment

1. Run automated quality checklist (Section 5)
2. Aggregate results from Stages 1-4
3. Compute composite quality score
4. Produce gap report (Section 6) if targets not met

**Composite Score:**

```
score = (compilation_pass * 20) + (execution_pass_rate * 30)
      + (coverage_score * 25) + (mutation_score * 15)
      + (quality_checklist_score * 10)
```

Where `compilation_pass` = 1.0 if pass else 0.0; `execution_pass_rate` = passed/total; `coverage_score` = min(line_coverage/tier_target, 1.0); `mutation_score` = min(kill_rate/tier_target, 1.0) or 0 if skipped; `quality_checklist_score` = checks_passed/total_checks.

---

## 2. Validation Tiers

### Tier Definitions

| Tier | Trigger | Stages | Line Coverage | Branch Coverage | Mutation Kill Rate |
|------|---------|--------|--------------|-----------------|-------------------|
| LIGHT | 1-2 test classes | 1, 2, 3 | >= 60% | (not required) | (skipped) |
| STANDARD | 3-8 test classes | 1, 2, 3, 4 | >= 70% | >= 50% | >= 50% |
| THOROUGH | 9+ test classes | 1, 2, 3, 4, 5 | >= 80% | >= 60% | >= 60% |

### Tier Selection

```
if testClassCount <= 2: LIGHT
elif testClassCount <= 8: STANDARD
else: THOROUGH
```

### Auto-Escalation

**LIGHT -> STANDARD** (any one triggers):
- Line coverage < 60%
- More than 2 test execution failures
- 3+ ERROR-severity quality checklist violations

**STANDARD -> THOROUGH** (any one triggers):
- Mutation kill rate < 40%
- Same failure in 3 consecutive loops
- Branch coverage < 35%

**Escalation behavior:**
1. Log escalation reason in gap report
2. Continue with higher tier's stage list and targets
3. Do not re-run already-completed stages

### Tier Override

```yaml
# .claude/test-config.yml
validation:
  tier: THOROUGH  # Force regardless of test class count
```

---

## 3. Coverage Measurement Patterns

### JaCoCo Gradle Setup

```kotlin
plugins { id("jacoco") }

jacoco { toolVersion = "0.8.11" }

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required = true
        html.required = true
    }
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule { limit { minimum = "0.70".toBigDecimal() } }
    }
}
```

### Kover Gradle Setup

```kotlin
plugins { id("org.jetbrains.kotlinx.kover") version "0.9.0" }

kover {
    reports {
        total {
            xml { onCheck = true }
            html { onCheck = true }
        }
    }
}
```

### Coverage Interpretation

| Metric | Measures | Significance |
|--------|---------|-------------|
| Line coverage | % executable lines executed | Minimum baseline; easy to game |
| Branch coverage | % conditional branches taken | Primary quality indicator; reveals untested edge cases |
| Method coverage | % methods invoked | Spots completely untested methods |

Branch coverage is the primary quality indicator. 90% line coverage with 40% branch coverage signals missing edge cases.

### Exclusion Patterns

```kotlin
tasks.jacocoTestReport {
    classDirectories.setFrom(files(classDirectories.files.map {
        fileTree(it) {
            exclude(
                "**/config/**", "**/dto/**", "**/*Dto.*",
                "**/*Request.*", "**/*Response.*", "**/*Config.*",
                "**/*Application.*", "**/generated/**"
            )
        }
    }))
}
```

---

## 4. Mutation Testing Configuration

### PIT Gradle Configuration

```kotlin
plugins { id("info.solidsoft.pitest") version "1.15.0" }

pitest {
    junit5PluginVersion = "1.2.1"
    targetClasses = setOf("com.example.domain.*", "com.example.service.*")
    targetTests = setOf("com.example.*Test")
    mutators = setOf("DEFAULTS")
    threads = 4
    outputFormats = setOf("HTML", "XML")
    timestampedReports = false
    timeoutConstant = 10000
    maxMutationsPerClass = 30
    avoidCallsTo = setOf("kotlin.jvm.internal", "org.slf4j", "mu.KotlinLogging")
}
```

### Mutator Sets

| Set | Content | Use Case |
|-----|---------|----------|
| DEFAULTS | CONDITIONALS_BOUNDARY, NEGATE_CONDITIONALS, MATH, INCREMENTS, INVERT_NEGS, RETURN_VALS, VOID_METHOD_CALLS | Standard; balanced speed vs thoroughness |
| STRONGER | DEFAULTS + REMOVE_CONDITIONALS, ARGUMENT_PROPAGATION, NAKED_RECEIVER | Deeper; slower but catches more |
| ALL | Every available mutator | THOROUGH tier only; significantly slower |

### Target Filtering

```kotlin
targetClasses = setOf("com.example.domain.*", "com.example.service.*", "com.example.usecase.*")
excludedClasses = setOf("com.example.config.*", "com.example.adapter.*", "com.example.dto.*")
```

### Surviving Mutant Analysis

| Classification | Description | Action |
|---------------|-------------|--------|
| Missing test | No test covers the mutated behavior | Generate new test for the specific condition |
| Weak assertion | Test runs but does not assert affected output | Strengthen assertion |
| Equivalent mutant | Mutation does not change observable behavior | Ignore; mark in gap report |

**Examples:**
```kotlin
// NOT equivalent: null vs emptyList() is observable
fun getItems(): List<Item> = emptyList()  // mutated to return null

// IS equivalent: removing logging has no behavioral impact
logger.info("Processing $orderId")  // mutated to remove call
```

### Performance Tuning

| Parameter | Default | Guidance |
|-----------|---------|---------|
| `threads` | 1 | CPU cores / 2; diminishing returns beyond 8 |
| `timeoutConstant` | 4000ms | Increase for I/O-heavy tests |
| `maxMutationsPerClass` | unlimited | Set 20-50 to cap time on large classes |
| JVM args | none | Add `-Xmx2g` for OOM: `jvmArgs = listOf("-Xmx2g")` |

---

## 5. Quality Checklist (Automated)

Checks performed via grep, AST analysis, or pattern matching -- no test execution required.

| # | Category | Check | Severity | Detection Pattern |
|---|----------|-------|----------|-------------------|
| 1 | Naming | Test describes behavior | WARNING | Method name contains verb (create, return, throw) |
| 2 | Assertion | No empty test body | ERROR | Test method with no assert/expect/verify/should |
| 3 | Assertion | No tautological assertion | ERROR | `assertTrue(true)`, `assertEquals(x, x)` |
| 4 | Assertion | Specific assertions used | WARNING | No `assertTrue(a == b)` pattern |
| 5 | Assertion | No caught-and-ignored exceptions | ERROR | `catch` with empty body or `assertTrue(true)` |
| 6 | Isolation | No shared mutable state | ERROR | `companion object` with `var` not reset in `@BeforeEach` |
| 7 | Isolation | Each test sets own data | ERROR | Missing `@BeforeEach` with mutable fields |
| 8 | Isolation | No static state leakage | ERROR | `object` singleton modified without reset |
| 9 | Determinism | No Thread.sleep | ERROR | `Thread.sleep(` in test source |
| 10 | Determinism | No raw time API | ERROR | `LocalDateTime.now()`, `Instant.now()` without Clock |
| 11 | Determinism | No unseeded randomness | ERROR | `Random()` without seed, `UUID.randomUUID()` in assertions |
| 12 | Structure | AAA/GWT separation | INFO | `// given`/`// when`/`// then` or blank line separation |
| 13 | Structure | Single act per test | WARNING | Multiple SUT calls between given and then |
| 14 | Mock | Do not mock the SUT | ERROR | `mockk<SUTClass>()` where SUT is class under test |
| 15 | Mock | No over-mocking | WARNING | More than 5 mock setups in single test |

### Severity Levels

| Severity | Impact |
|----------|--------|
| ERROR | Fails quality gate; must fix |
| WARNING | Reported; recommended fix |
| INFO | Reported only; no gate impact |

### Detection Examples

```bash
# Empty test body
grep -n "@Test" TestFile.kt  # then check method body for assert/expect/verify

# Thread.sleep
grep -rn "Thread.sleep(" src/test/ --include="*.kt" --include="*.java"

# Raw time API
grep -rn "LocalDateTime.now()\|Instant.now()\|System.currentTimeMillis()" src/test/

# SUT mocking
grep -n "mockk<${SUT_CLASS}>()" TestFile.kt
```

**Quality Gate:** PASS = zero ERROR violations. Score = checks_passed / total_applicable_checks.

---

## 6. Gap Report Format

The gap report is T4's primary output, consumed by T3 for targeted regeneration.

```json
{
  "tier": "STANDARD",
  "loop_number": 1,
  "timestamp": "2025-01-15T10:30:00Z",
  "compilation": { "status": "pass", "errors": [] },
  "execution": {
    "total": 15, "passed": 14, "failed": 1, "skipped": 0,
    "failures": [{
      "test_class": "OrderServiceTest",
      "test_method": "should reject order when stock is insufficient",
      "error_type": "AssertionError",
      "message": "expected REJECTED but was PENDING",
      "auto_fixable": true,
      "suggested_fix": "Check OrderService.validate() return value"
    }]
  },
  "coverage": {
    "tool": "JaCoCo",
    "line": 72.5, "branch": 58.3, "method": 85.0,
    "uncovered_methods": [
      "com.example.service.OrderService.cancel",
      "com.example.service.OrderService.refund"
    ],
    "uncovered_branches": [{
      "class": "com.example.service.OrderService",
      "method": "validate", "line": 45,
      "description": "else branch of stock check"
    }]
  },
  "mutation": {
    "tool": "PITest",
    "total": 45, "killed": 28, "survived": 17, "kill_rate": 62.2,
    "surviving_mutants": [
      { "class": "OrderService", "method": "validate", "line": 45,
        "mutator": "NEGATE_CONDITIONALS", "classification": "missing_test" },
      { "class": "OrderService", "method": "calculateTotal", "line": 62,
        "mutator": "MATH", "classification": "weak_assertion" }
    ]
  },
  "quality_checklist": {
    "total_checks": 15, "passed": 13, "errors": 1, "warnings": 1,
    "violations": [
      { "check": "No Thread.sleep", "severity": "ERROR",
        "location": "OrderServiceTest.kt:78" },
      { "check": "Specific assertions", "severity": "WARNING",
        "location": "OrderServiceTest.kt:92" }
    ]
  },
  "gaps": [
    { "type": "uncovered_method", "target": "OrderService.cancel",
      "priority": "HIGH", "reason": "Zero coverage on cancellation logic" },
    { "type": "uncovered_method", "target": "OrderService.refund",
      "priority": "HIGH", "reason": "Zero coverage on refund flow" },
    { "type": "surviving_mutant", "target": "OrderService.validate",
      "mutator": "NEGATE_CONDITIONALS", "priority": "MEDIUM",
      "reason": "Stock check boundary not tested" },
    { "type": "quality_violation", "target": "OrderServiceTest.kt:78",
      "violation": "Thread.sleep", "priority": "HIGH",
      "reason": "Non-deterministic; replace with Awaitility" }
  ],
  "recommendation": "Generate tests for OrderService.cancel and refund. Add boundary tests for validate. Replace Thread.sleep with Awaitility.",
  "next_action": "CONTINUE"
}
```

### `next_action` Values

| Value | Meaning |
|-------|---------|
| `CONTINUE` | Targets not met; send to T3 for next loop |
| `SUCCESS` | All tier targets met; pipeline complete |
| `PARTIAL_SUCCESS` | Convergence plateau; report remaining gaps |
| `BLOCKED` | 3-strike rule; escalate to user |
| `TIMEOUT` | Max loops reached; report remaining gaps |

---

## 7. Error Resolution Playbook

### MockK Errors

**`no answer found for: ClassName.methodName(args)`**
- Add missing stub: `every { mock.methodName(any()) } returns expectedValue`
- Prevention: `val mock = mockk<ClassName>(relaxed = true)`

**`was not called: ClassName.methodName(args)`**
- Check SUT actually calls the method under test conditions
- Verify argument matchers: `any()` vs specific values
- Check method overloads; use `confirmVerified(mock)` for diagnostics

**`clearMocks` behavior:**
```kotlin
clearMocks(mock, answers = false)  // Preserve stubs, clear verification only
clearMocks(mock)                    // Clear everything (answers = true default)
```

### Mockito Errors

**`UnnecessaryStubbingException`**
- Remove unused stubbing, or wrap with `lenient().when(...)`

**`WrongTypeOfReturnValue`**
- Match return type: e.g., `Optional.of(order)` not `order` for `Optional<Order>` method

**`InvalidUseOfMatchersException`**
- Wrap raw values with `eq()` when mixing with matchers:
  `when(service.process(eq("fixed"), any())).thenReturn(result)`

### Testcontainers Errors

**`Could not find a valid Docker environment`**
- Start Docker Desktop; verify with `docker info`

**`Container startup failed`**
- Verify image: `docker pull <image:tag>`; check port conflicts; increase memory
- Timeout: `MySQLContainer("mysql:8.0").withStartupTimeout(Duration.ofMinutes(3))`

**`Connection refused` after startup**
- Wait for readiness: `container.waitingFor(Wait.forLogMessage(".*ready.*", 1))`

### PIT Errors

**OutOfMemoryError**
```kotlin
pitest { threads = 2; maxMutationsPerClass = 20; jvmArgs = listOf("-Xmx2g") }
```

**Infinite loop / timeout**
```kotlin
pitest { timeoutConstant = 10000; timeoutFactor = 1.5 }
```

**`No mutations found`**
- Verify `targetClasses` pattern matches compiled class paths

---

## 8. Loop Termination Conditions

T3 (Generator) and T4 (Assessor) operate in a feedback loop until a termination condition is met.

### Conditions (loop exits when ANY is true)

**1. Targets Met (SUCCESS)**

All tier targets satisfied AND zero ERROR-severity quality violations.

| Tier | Line | Branch | Kill Rate |
|------|------|--------|-----------|
| LIGHT | >= 60% | -- | -- |
| STANDARD | >= 70% | >= 50% | >= 50% |
| THOROUGH | >= 80% | >= 60% | >= 60% |

**2. Convergence Plateau (PARTIAL_SUCCESS)**

Coverage improvement < 2 percentage points between consecutive loops: `abs(coverage[n] - coverage[n-1]) < 2.0`. Applies to line coverage and kill rate independently.

**3. 3-Strike Rule (BLOCKED)**

Same error (type + location) in 3 consecutive loops. Examples: same compilation error after 3 fixes, same assertion failure 3 times, same quality violation unremediated.

**4. Max Loops (TIMEOUT)**

Default: 3 loops. Override: `validation.max_loops: 5`

### Decision Tree

```
Loop complete
  +-- All targets met?       YES --> EXIT "SUCCESS"
  +-- Convergence plateau?   YES --> EXIT "PARTIAL_SUCCESS" (report gaps)
  +-- Same error 3x?         YES --> EXIT "BLOCKED" (escalate to user)
  +-- Loop >= max_loops?      YES --> EXIT "TIMEOUT" (report gaps)
  +-- None                        --> Gap report -> T3 -> next loop
```

### Loop State Tracking

```json
{
  "loop_history": [
    { "loop": 1, "line_coverage": 65.2, "branch_coverage": 42.1,
      "kill_rate": null, "errors": ["compilation failure"], "gaps": 4 },
    { "loop": 2, "line_coverage": 72.5, "branch_coverage": 58.3,
      "kill_rate": 62.2, "errors": [], "gaps": 2 }
  ],
  "strike_tracker": {
    "OrderServiceTest:45:AssertionError": 1,
    "Thread.sleep:OrderServiceTest:78": 0
  }
}
```

The `strike_tracker` maps unique error identifiers to consecutive occurrence counts. Resets to 0 when the error does not recur. Triggers 3-Strike condition when any count reaches 3.
