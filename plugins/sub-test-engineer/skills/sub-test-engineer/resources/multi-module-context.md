# Multi-module Project Context

> Consolidated reference for handling multi-module projects across all phases.
> This document replaces scattered multi-module logic in individual protocols.

---

## 1. Detection

### 1.1 Gradle

```
IF settings.gradle.kts OR settings.gradle exists:
  → Parse include(...) or include '...' declarations
  → For each submodule: verify build.gradle.kts or build.gradle exists
  → Map: module-name → { path, gradle-path, source-root, test-root }
```

**Example:**
```groovy
// settings.gradle.kts
include(":modules:order-domain")
include(":modules:order-api")
```

**Produces:**
```json
{
  "name": "order-domain",
  "path": "modules/order-domain",
  "gradle-path": ":modules:order-domain",
  "source-root": "modules/order-domain/src/main/{java,kotlin}",
  "test-root": "modules/order-domain/src/test/{java,kotlin}",
  "has-tests": true
}
```

### 1.2 Maven

```
IF root pom.xml contains <modules> section:
  → Parse <module> elements
  → For each submodule: verify pom.xml exists at module path
  → Map: module-name → { path, maven-path, source-root, test-root }
```

**Example:**
```xml
<!-- pom.xml -->
<modules>
  <module>modules/order-domain</module>
  <module>modules/order-api</module>
</modules>
```

### 1.3 Node (Monorepo)

```
IF root package.json has "workspaces" field:
  → Parse workspace glob patterns
  → For each workspace: verify package.json exists
IF NOT a monorepo → single-module project (skip)
```

**Example:**
```json
{
  "workspaces": ["packages/*"]
}
```

### 1.4 Go

```
IF go.work file exists:
  → Parse use directives
  → Map: module-name → { path, go-path }
IF go.mod with replace directives:
  → Parse replace local paths
```

---

## 2. Path Resolution

### 2.1 Gradle Path Conversion

Filesystem path to Gradle module path:
```
modules/order-domain → :modules:order-domain
```

**Library function:** `get_gradle_prefix()` in `scripts/lib/build-tool.sh`

```bash
# Usage
source scripts/lib/build-tool.sh
PREFIX=$(get_gradle_prefix "modules/order-domain")
# Result: :modules:order-domain:
```

### 2.2 Maven Module Flag

Filesystem path to Maven `-pl` flag:
```
modules/order-domain → -pl modules/order-domain
```

**Library function:** `get_maven_flag()` in `scripts/lib/build-tool.sh`

```bash
# Usage
source scripts/lib/build-tool.sh
FLAG=$(get_maven_flag "modules/order-domain")
# Result: -pl modules/order-domain
```

### 2.3 Source/Test Root Resolution

| Build Tool | Source Root | Test Root |
|------------|-------------|-----------|
| Gradle/Maven (Java) | `{module}/src/main/java` | `{module}/src/test/java` |
| Gradle/Maven (Kotlin) | `{module}/src/main/kotlin` | `{module}/src/test/kotlin` |
| npm/pnpm | `{workspace}/src` | `{workspace}/__tests__` or `{workspace}/*.test.ts` |
| Go | `{module}/` | `{module}/*_test.go` |

---

## 3. Command Prefix Conventions

### 3.1 Task Execution

| Build Tool | Single-module | Multi-module (target) |
|------------|---------------|----------------------|
| Gradle | `./gradlew test` | `./gradlew :modules:order:test` |
| Maven | `mvn test` | `mvn test -pl modules/order` |
| npm | `npm test` | `npm test --workspace=@scope/order` |
| Go | `go test ./...` | `go test ./modules/order/...` |

### 3.2 Compilation

```bash
# Gradle
./gradlew ${MODULE_PREFIX}compileTestKotlin
./gradlew ${MODULE_PREFIX}compileTestJava

# Maven
mvn test-compile ${MODULE_FLAG}

# npm (TypeScript)
npx tsc --noEmit --project ${WORKSPACE}/tsconfig.json
```

### 3.3 Coverage

```bash
# Gradle (JaCoCo)
./gradlew ${MODULE_PREFIX}jacocoTestReport

# Gradle (Kover)
./gradlew ${MODULE_PREFIX}koverXmlReport

# Maven (JaCoCo)
mvn jacoco:report ${MODULE_FLAG}
```

### 3.4 Mutation Testing

```bash
# Gradle (PIT)
./gradlew ${MODULE_PREFIX}pitest

# Maven (PIT)
mvn org.pitest:pitest-maven:mutationCoverage ${MODULE_FLAG}
```

---

## 4. Report Path Resolution

### 4.1 Gradle Reports

| Report Type | Single-module | Multi-module |
|-------------|---------------|--------------|
| JaCoCo XML | `build/reports/jacoco/test/jacocoTestReport.xml` | `{module}/build/reports/jacoco/test/jacocoTestReport.xml` |
| Kover XML | `build/reports/kover/xml/report.xml` | `{module}/build/reports/kover/xml/report.xml` |
| PIT HTML | `build/reports/pitest/index.html` | `{module}/build/reports/pitest/index.html` |
| PIT XML | `build/reports/pitest/mutations.xml` | `{module}/build/reports/pitest/mutations.xml` |

### 4.2 Maven Reports

| Report Type | Single-module | Multi-module |
|-------------|---------------|--------------|
| JaCoCo XML | `target/site/jacoco/jacoco.xml` | `{module}/target/site/jacoco/jacoco.xml` |
| PIT HTML | `target/pit-reports/index.html` | `{module}/target/pit-reports/index.html` |

### 4.3 Finding Reports

**Library function:** `find_report()` in `scripts/lib/build-tool.sh`

```bash
# Usage
source scripts/lib/build-tool.sh
REPORT=$(find_report "jacocoTestReport.xml" "jacoco" "modules/order-domain")
```

---

## 5. Cross-module Dependencies

### 5.1 Detection

When analyzing a target class:
```
1. Parse imports/dependencies
2. Identify classes from other modules (different source root)
3. Mark as cross-module dependency
```

### 5.2 Test Implications

| Scenario | Approach |
|----------|----------|
| Target depends on sibling module class | Include sibling module in compile classpath |
| Test needs fixture from sibling module | Check for shared test fixtures module |
| Integration test spans modules | Run at root level or dedicated integration module |

### 5.3 Build Order

Gradle/Maven automatically handles dependency order. For explicit control:
```bash
# Gradle - build dependencies first
./gradlew :modules:order-domain:build :modules:order-api:test

# Maven - reactor handles order
mvn test -pl modules/order-api -am  # -am builds required modules
```

---

## 6. test-profile.json Structure

### 6.1 Single-module (default)

```json
{
  "multi-module": false,
  "modules": [],
  "target-module": null
}
```

### 6.2 Multi-module

```json
{
  "multi-module": true,
  "modules": [
    {
      "name": "order-domain",
      "path": "modules/order-domain",
      "gradle-path": ":modules:order-domain",
      "has-tests": true
    },
    {
      "name": "order-api",
      "path": "modules/order-api",
      "gradle-path": ":modules:order-api",
      "has-tests": true
    }
  ],
  "target-module": {
    "name": "order-domain",
    "path": "modules/order-domain",
    "gradle-path": ":modules:order-domain"
  }
}
```

### 6.3 Target Module Selection

When user specifies a target file:
```
1. Determine which module contains the file
2. Set target-module in test-profile.json
3. All subsequent commands scope to that module
```

When target spans multiple modules:
```
1. Set target-module to null
2. Run commands at root level
3. Aggregate reports across modules
```

---

## 7. Error Scenarios

### 7.1 Module Not Found

**Symptom:** `Could not find project ':modules:order'`

**Resolution:**
1. Verify module path exists
2. Check settings.gradle/pom.xml includes the module
3. Verify build config exists at module path

### 7.2 Cross-module Compilation Error

**Symptom:** `Unresolved reference: OrderEntity` (class from sibling module)

**Resolution:**
1. Verify sibling module is in dependencies
2. Build sibling module first: `./gradlew :sibling:build`
3. Check for circular dependency

### 7.3 Report Not Found

**Symptom:** Coverage/mutation report missing after command

**Resolution:**
1. Check module-specific report path (not root)
2. Verify plugin is configured in module's build file
3. Run with `--info` or `-X` for detailed logs

---

## 8. Phase-specific Handling

### 8.1 Phase 0 (Discovery)

- Detect multi-module structure
- Populate modules array in test-profile.json
- Do NOT set target-module yet (determined by user request)

### 8.2 Phase 1 (Analyze)

- If target file specified: determine containing module
- Set target-module in test-profile.json
- Run ast-grep scoped to module source root

### 8.3 Phase 2 (Strategize)

- Consider cross-module dependencies in strategy
- Flag integration tests if target spans modules

### 8.4 Phase 3 (Generate)

- Place generated tests in correct module test root
- Use appropriate import paths for cross-module types

### 8.5 Phase 4 (Validate)

- Run commands with module prefix/flag
- Find reports in module-specific paths
- Aggregate metrics if root-level run

---

## 9. Script Integration

All scripts should source the build-tool library:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-tool.sh"

# Detect build tool
BUILD_TOOL=$(detect_build_tool "$PROJECT_ROOT")

# Get module prefix/flag
case "$BUILD_TOOL" in
  gradle)
    PREFIX=$(get_gradle_prefix "$MODULE_PATH")
    run_gradle "test" "$MODULE_PATH"
    ;;
  maven)
    FLAG=$(get_maven_flag "$MODULE_PATH")
    run_maven "test" "$MODULE_PATH"
    ;;
esac

# Find report
REPORT=$(find_report "jacocoTestReport.xml" "jacoco" "$MODULE_PATH" "$PROJECT_ROOT")
```
