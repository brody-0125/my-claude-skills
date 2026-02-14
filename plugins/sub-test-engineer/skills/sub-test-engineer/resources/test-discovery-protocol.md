# Phase 0: Test Discovery Protocol

> Automatically detects the project's test infrastructure, existing patterns, and coverage baseline.

---

## 0. Multi-module Detection

> For comprehensive multi-module handling reference, see [multi-module-context.md](multi-module-context.md).

**Gradle:**
```
IF settings.gradle.kts OR settings.gradle exists:
  → Parse include(...) or include '...' declarations
  → For each submodule: verify build.gradle.kts or build.gradle exists
  → Map: module-name → { path, gradle-path, source-root, test-root }
  → Example: include(":modules:order-domain")
    → { name: "order-domain", path: "modules/order-domain",
        gradle-path: ":modules:order-domain",
        source-root: "modules/order-domain/src/main/{java,kotlin}",
        test-root: "modules/order-domain/src/test/{java,kotlin}" }
```

**Maven:**
```
IF root pom.xml contains <modules> section:
  → Parse <module> elements
  → For each submodule: verify pom.xml exists at module path
  → Map: module-name → { path, maven-path, source-root, test-root }
```

**Node (monorepo):**
```
IF root package.json has "workspaces" field:
  → Parse workspace glob patterns
  → For each workspace: verify package.json exists
IF NOT a monorepo → single-module project (skip)
```

**Output:** Add to test-profile.json:
```json
{
  "multi-module": false,
  "modules": [],
  "target-module": null
}
```
When multi-module is detected:
```json
{
  "multi-module": true,
  "modules": [
    { "name": "order-domain", "path": "modules/order-domain",
      "gradle-path": ":modules:order-domain", "has-tests": true }
  ],
  "target-module": null
}
```

## 2. Test Framework Detection

**Scan order:**
1. Build config files: `build.gradle.kts`, `build.gradle`, `pom.xml`, `package.json`, `tsconfig.json`
2. Test source directories: `src/test/`, `__tests__/`, `*.test.ts`, `*.spec.ts`
3. Configuration files: `jest.config.*`, `vitest.config.*`, `kotest.config.*`

**Detection matrix:**

| Signal | Framework | Mock | Assertion |
|--------|-----------|------|-----------|
| `io.kotest` in deps | Kotest | MockK | Kotest matchers / Strikt |
| `org.junit.jupiter` in deps | JUnit 5 | Mockito or MockK | AssertJ or JUnit assertions |
| `jest` in package.json | Jest | jest.mock | Jest expect |
| `vitest` in package.json | Vitest | vi.mock | Vitest expect / Chai |

## 3. Coverage Tool Detection

| Signal | Coverage Tool | Mutation Tool |
|--------|---------------|---------------|
| `jacoco` plugin in build config | JaCoCo | PIT (if `pitest` plugin found) |
| `kover` plugin in build config | Kover | PIT |
| `istanbul` / `c8` in package.json | c8/Istanbul | Stryker (if `@stryker-mutator/*` found) |

## 4. Existing Test Pattern Learning

Scan existing test files (max 10 representative files) to extract.

**File selection criteria (select 10 from test sources):**
1. 3 most recently modified test files (`git log --diff-filter=M -3 --name-only -- '*Test.*' '*.test.*'`)
2. 3 largest test files by line count (likely most representative of project patterns)
3. 4 random test files from different packages/directories (for diversity)
4. If fewer than 10 test files exist, scan all

**Scan and extract:**

```yaml
test-patterns:
  naming: "should_verb_when_condition"  # or "test + methodName", BDD given/when/then
  structure: "AAA"                       # Arrange-Act-Assert, Given-When-Then, SUT pattern
  fixture-strategy: "builder"            # builder, factory method, companion object, beforeEach
  base-class: "IntegrationTestBase"      # if common base test class exists
  assertion-style: "strikt"              # strikt, assertj, kotest-matchers, jest-expect
  mock-style: "every-returns"            # every{} returns, when().thenReturn(), jest.fn()
  test-data: "fixture-file"             # inline, fixture file, test data builder, @Sql
```

## 5. Coverage Baseline (Lazy)

Coverage baseline is **not collected eagerly** in Phase 0. It is deferred to Phase 4 (Validate) when coverage measurement is actually needed.

In Phase 0, only detect whether a coverage tool is **configured** (check build config for plugin declarations):

```
IF JaCoCo/Kover plugin found in build config → coverage-tool = "jacoco" or "kover"
IF istanbul/c8 in package.json devDependencies → coverage-tool = "c8"
ELSE → coverage-tool = null
```

**Exception:** If `coverage-target N%` mode is used OR `test-debt:` mode is used, run coverage baseline eagerly:
- JVM (Gradle): `./gradlew jacocoTestReport` or `./gradlew koverReport`
- JVM (Maven): `mvn jacoco:report -q`
- Node: `npx c8 report` or `npx jest --coverage --json`

Parse and cache:
```json
{
  "overall": { "line": 62.3, "branch": 48.1 },
  "by-package": {
    "com.example.order.domain": { "line": 85.0, "branch": 72.0 },
    "com.example.order.application": { "line": 45.0, "branch": 30.0 }
  },
  "uncovered-files": ["OrderCancelService.kt", "PaymentAdapter.kt"]
}
```

## 6. Profile Output

Save to `.sub-test-engineer/test-profile.json`:

```json
{
  "language": "kotlin",
  "test-framework": "kotest",
  "mock-framework": "mockk",
  "assertion-library": "strikt",
  "coverage-tool": "kover",
  "mutation-tool": null,
  "integration-tools": ["testcontainers", "embedded-kafka"],
  "patterns": { "...learned patterns..." },
  "baseline-coverage": { "...coverage data..." },
  "build-tool": "gradle",
  "config-hash": "a1b2c3d4e5f6...",
  "detected-at": "2026-02-05T10:00:00Z"
}
```

**Caching:** Profile is cached with an MD5 hash key computed from:
- JVM: `build.gradle.kts` (or `build.gradle` or `pom.xml`) content hash
- Node: `package.json` + `package-lock.json` (or `yarn.lock`) content hash
- Plus: test config files (`jest.config.*`, `vitest.config.*`, `kotest.config.*`) content hash

```bash
# Example hash computation
md5sum build.gradle.kts jest.config.ts 2>/dev/null | md5sum | cut -d' ' -f1
```

Invalidate and re-run Phase 0 if hash differs from `test-profile.json → config-hash` field.
