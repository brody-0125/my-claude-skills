# Phase 4: Validate Protocol

> Multi-stage validation pipeline that assesses test quality beyond "tests pass."

## 0. Entry Check

```
IF first validation (loop 1):
  → Run all 5 stages sequentially
  → Input: generated test file list from Phase 3

IF subsequent validation (loop 2+):
  → Run all 5 stages on newly generated gap tests
  → Compare metrics with previous loop
  → Input: updated test file list + previous validation report
```

### Multi-module Handling

> For comprehensive multi-module handling reference, see [multi-module-context.md](multi-module-context.md).

When `test-profile.json -> multi-module` is `true` and `target-module` is set:

```
Command prefix rule:
  Gradle: ./gradlew {task}  → ./gradlew {target-module.gradle-path}:{task}
  Maven:  mvn {goal}        → mvn {goal} -pl {target-module.path}

Report path rule:
  Gradle: build/reports/    → {target-module.path}/build/reports/
  Maven:  target/site/      → {target-module.path}/target/site/

IF target-module is NOT set but multi-module is true:
  → Run commands at root level (all modules)
  → Coverage report aggregation may be needed
```

## 1. Validation Pipeline

Execute stages sequentially. Each stage has **graceful degradation** for missing tools.

### Stage 1: Compilation Check

Detect build tool from `test-profile.json` or build config files:

```bash
# JVM (Gradle)
./gradlew compileTestKotlin  # or compileTestJava
# JVM (Maven)
mvn test-compile -q
# Node
npx tsc --noEmit  # TypeScript type check
```

**Multi-module:** When `test-profile.json -> target-module` is set:
```bash
# JVM (Gradle) — prefix module path
./gradlew {MODULE_GRADLE_PATH}:compileTestKotlin  # Stage 1
# JVM (Maven) — use -pl flag
mvn test-compile -pl {MODULE_PATH} -q  # Stage 1
```

**On success:** Proceed to Stage 2.

**On failure:** Parse error, fix in generated test file, re-compile.

**3-Strike Rule:** (See [error-handling-framework.md](error-handling-framework.md) Level 3)
```
IF same compilation error 3x consecutive:
  → Stop attempting manual fixes
  → Apply root-cause analysis:
    1. Re-read source file and test file fully
    2. Identify a fundamentally different approach (different mock strategy, import fix, etc.)
    3. Rewrite the failing section from scratch instead of incremental patches
  → If still failing → STOP loop, report to user with error details
```

### Stage 2: Execution Check

```bash
# JVM (Gradle) — run only generated test classes
./gradlew test --tests "{TestClassName}"
# JVM (Maven)
mvn test -Dtest="{TestClassName}" -q
# Node
npx jest --testPathPattern="{test-file-pattern}" --no-cache
```

**Multi-module:** When `test-profile.json -> target-module` is set:
```bash
# JVM (Gradle) — prefix module path
./gradlew {MODULE_GRADLE_PATH}:test --tests "{TestClassName}"  # Stage 2
# JVM (Maven) — use -pl flag
mvn test -pl {MODULE_PATH} -Dtest="{TestClassName}" -q  # Stage 2
```

**On failure:** Analyze failure output and classify:

| Failure Type | Diagnosis | Action |
|--------------|-----------|--------|
| **Assertion failure** | Expected value mismatch | Review assertion logic; fix assertion OR flag potential bug in code-under-test |
| **Mock setup error** | Mock not configured for called method | Add missing mock stub |
| **NullPointerException / undefined** | Missing null handling in test setup | Add null-safe setup or mock return |
| **Infrastructure error** | Testcontainers/DB unavailable | Check Docker availability; if unavailable → WARN, skip integration tests |
| **Timeout** | Missing async handling | Add `runBlocking`, `await`, or increase timeout |
| **ClassNotFoundException** | Wrong import or classpath issue | Fix import path |

**3-Strike Rule (same as Stage 1):** (See [error-handling-framework.md](error-handling-framework.md) Level 3)
```
IF same test failure 3x consecutive after fix attempts:
  → Stop attempting manual fixes
  → Apply root-cause analysis:
    1. Re-read source file, test file, and all 3 previous fix attempts
    2. Identify root cause pattern (wrong assumption about API, missing dependency, etc.)
    3. Attempt fundamentally different approach
  → If still failing → mark test as SKIPPED with reason, continue with remaining tests
  → Report skipped tests to user in Validation Report
```

### Stage 3: Coverage Measurement

Check `test-profile.json → coverage-tool` field to determine which tool to use:

```bash
# JVM (JaCoCo) — Gradle
./gradlew jacocoTestReport
# Parse: build/reports/jacoco/test/jacocoTestReport.xml

# JVM (JaCoCo) — Maven
mvn jacoco:report -q
# Parse: target/site/jacoco/jacoco.xml

# JVM (Kover) — Gradle only
./gradlew koverXmlReport
# Parse: build/reports/kover/xml/report.xml

# Node (c8/Istanbul)
npx jest --coverage --coverageReporters=json
# Parse: coverage/coverage-final.json
```

**Multi-module:** When `test-profile.json -> target-module` is set:
```bash
# JVM (Gradle) — prefix module path
./gradlew {MODULE_GRADLE_PATH}:jacocoTestReport  # Stage 3
# JVM (Maven) — use -pl flag
mvn jacoco:report -pl {MODULE_PATH} -q  # Stage 3
# Coverage report path: {MODULE_PATH}/build/reports/jacoco/ (Gradle)
#                        {MODULE_PATH}/target/site/jacoco/ (Maven)
```

> Script: `scripts/measure-coverage.sh [project-root] [target-package] [module-path]`

**Graceful Degradation:**
```
IF test-profile.json → coverage-tool is null OR coverage tool not configured in build:
  → Log: "⚠ Coverage tool not configured. Skipping coverage measurement."
  → Log: "   To enable: add JaCoCo/Kover plugin (JVM) or --coverage flag (Node)."
  → Skip Stage 3 entirely
  → Do NOT fail the validation — proceed to Stage 4
  → Coverage-related fields in Validation Report → "N/A (tool not configured)"
```

**Coverage gap analysis (when tool available):**
1. Parse coverage report for target classes only
2. Identify uncovered lines/branches
3. Classify gaps:
   - **Trivial** (getter/setter, toString) → skip
   - **Error path** (catch block, error branch) → generate targeted test
   - **Business logic** (conditional branch) → generate targeted test
4. Feed gaps to Gap Report for next loop iteration

### Stage 4: Mutation Testing (STANDARD/THOROUGH tiers only)

Check `test-profile.json → mutation-tool` field:

```bash
# JVM (PIT) — Gradle
./gradlew pitest --targetClasses="{package.ClassName}" --targetTests="{package.ClassNameTest}"
# JVM (PIT) — Maven
mvn org.pitest:pitest-maven:mutationCoverage -DtargetClasses="{package.ClassName}" -DtargetTests="{package.ClassNameTest}" -q

# Node (Stryker)
npx stryker run --mutate="{source-glob}" --files="{test-glob}"
```

**Multi-module:** When `test-profile.json -> target-module` is set:
```bash
# JVM (Gradle) — prefix module path
./gradlew {MODULE_GRADLE_PATH}:pitest  # Stage 4
# JVM (Maven) — use -pl flag
mvn org.pitest:pitest-maven:mutationCoverage -pl {MODULE_PATH} -q  # Stage 4
```

> Script: `scripts/run-mutation-test.sh [project-root] [target-class-pattern] [tier] [module-path]`

**Graceful Degradation:**
```
IF test-profile.json → mutation-tool is null OR mutation testing tool not configured:
  → Log: "⚠ Mutation testing tool not configured. Skipping mutation analysis."
  → Log: "   To enable: add PIT plugin (JVM) or Stryker (Node)."
  → Skip Stage 4 entirely
  → Do NOT fail the validation — proceed to Stage 5
  → Mutation-related fields in Validation Report → "N/A (tool not configured)"

IF tier = LIGHT:
  → Skip Stage 4 (by design)
```

**Mutation result analysis (when tool available):**
- **Killed mutants**: Test suite detected the change (good)
- **Survived mutants**: Test suite missed the change (gap found)
  → Analyze survived mutant: what mutation was made? Which test should have caught it?
  → Add to Gap Report for targeted test generation
- **Equivalent mutants**: Mutation doesn't change behavior (ignore)
- **Timed-out mutants**: Mutation caused infinite loop (count as killed)

**Mutation kill rate targets:**
| Tier | Target | Action if below |
|------|--------|-----------------|
| LIGHT | Skip mutation testing | — |
| STANDARD | 60% kill rate | Generate tests for top-5 survived mutants |
| THOROUGH | 70% kill rate | Generate tests for all survived mutants |

### Stage 5: Quality Assessment

Checklist applied to generated tests:

| Category | Check | Severity |
|----------|-------|----------|
| **Naming** | Test names describe behavior, not method name | WARNING |
| **Assertions** | No empty test bodies, no `assertTrue(true)` | ERROR |
| **Assertion quality** | Uses specific assertions (assertEquals, not assertTrue(a==b)) | WARNING |
| **Isolation** | No shared mutable state between tests | ERROR |
| **Determinism** | No Thread.sleep, System.currentTimeMillis, Random() without seed | ERROR |
| **Mock scope** | Mocks only interfaces, not concrete classes | WARNING |
| **Readability** | AAA/GWT structure clearly separated | INFO |
| **Completeness** | All enum variants covered in parameterized tests | WARNING |
| **Error paths** | Exception scenarios have dedicated tests | WARNING |

## 2. Validation Report Output

```markdown
## Validation Report: Loop {N}

### Pipeline Results
| Stage | Status | Details |
|-------|--------|---------|
| Compilation | {PASS/FAIL} | {N}/{N} test classes compile |
| Execution | {PASS/FAIL} | {N}/{N} tests green |
| Coverage | {PASS/WARN/N/A} | {N}% line / {N}% branch (target: {N}%) |
| Mutation | {PASS/WARN/N/A/SKIP} | {N}% kill rate (target: {N}%) |
| Quality | {PASS/WARN} | {N} errors, {N} warnings |

### Coverage Delta (from baseline)
| Package | Before | After | Delta |
|---------|--------|-------|-------|
| com.example.order.domain | 85.0% | 95.2% | +10.2% |
| com.example.order.application | 45.0% | 83.1% | +38.1% |

### Uncovered Gaps (top 5)
| File | Line(s) | Type | Priority |
|------|---------|------|----------|
| OrderService.kt | 42-48 | error-path | HIGH |
| OrderService.kt | 67 | branch | MEDIUM |

### Survived Mutants (top 5)
| File:Line | Mutation | Missing Test |
|-----------|----------|-------------|
| OrderService:42 | `>` mutated to `>=` | Boundary test for discount=0 |
| OrderValidator:18 | `&&` mutated to `||` | Independent condition test |
| CancelHandler:55 | removed method call | verify() for event publishing |

### Quality Violations
| Severity | File | Rule | Details |
|----------|------|------|---------|
| ERROR | OrderServiceTest.kt:25 | Assertions | Empty assertion body |

### Recommendations
- Add boundary test for OrderService.calculateDiscount (line 42)
- Add independent condition tests for OrderValidator.isValid (line 18)
- Add verify() assertion for EventPublisher.publish in CancelHandler test

### Loop Decision
- **Action**: {EXIT (success) / EXIT (convergence) / CONTINUE / ESCALATE}
- **Reason**: {reason}
```

## 3. Gap Report Generation (Phase 4 → Phase 3 handoff)

When loop continues (coverage gaps or survived mutants found), produce a **Gap Report**:

```markdown
## Gap Report: Loop {N}

### Uncovered Code Paths (from coverage)
| File | Line(s) | Branch | Description | Source Snippet |
|------|---------|--------|-------------|----------------|
| OrderService.kt:42-48 | 42-48 | else branch | discount < 0 case | `if (discount < 0) { throw InvalidDiscountException(...) }` |
| OrderService.kt:67 | 67 | catch block | PaymentException handler | `catch (e: PaymentException) { log.error(...); rollback() }` |

### Survived Mutants (from mutation testing)
| File:Line | Mutation | Original | Mutated | Source Context | Required Test |
|-----------|----------|----------|---------|----------------|---------------|
| OrderService.kt:42 | RelationalOperator | `>` | `>=` | `if (discount > 0)` | Boundary test for discount=0 |

### Quality Violations
| File | Issue | Severity |
|------|-------|----------|
| OrderServiceTest.kt:25 | Empty assertion body | ERROR |

### Generation Instructions
Generate ONLY tests targeting the above gaps. Do NOT regenerate existing passing tests.
Append new test methods to existing test files where applicable.
```

**Gap Report rules:**
- Include ONLY actionable items (skip trivial coverage gaps like getters/setters)
- Each item must include a **Source Snippet** (3-5 lines of code context) so Phase 3 can generate targeted tests without re-reading the entire source file
- Maximum 20 items per Gap Report (prioritize by severity: ERROR > WARNING > INFO)
- If coverage tool was skipped (N/A), the Uncovered Code Paths section is empty
- If mutation tool was skipped (N/A), the Survived Mutants section is empty

## 4. Loop Termination Decision

**max_loops defaults:**
- `loop N` → max_loops = N
- `coverage-target N%` → max_loops = 5
- (not specified) → max_loops = 1

**Mutation target by tier** (used in condition 1):
- LIGHT → skip mutation check
- STANDARD → 60% kill rate
- THOROUGH → 70% kill rate

After producing the Validation Report, decide whether to continue:

```
1. All targets met (coverage >= target AND mutation >= tier-specific target AND 0 quality errors)
   → EXIT: Report success

2. Coverage delta < 2% from previous loop (convergence plateau)
   → EXIT: Report "convergence plateau — diminishing returns"

3. Same compilation error 3x consecutive across loops
   → EXIT: Report error with details for user

4. loop_count >= max_loops
   → EXIT: Report final metrics

5. Otherwise
   → Generate Gap Report → feed to Phase 3 → next loop
```
