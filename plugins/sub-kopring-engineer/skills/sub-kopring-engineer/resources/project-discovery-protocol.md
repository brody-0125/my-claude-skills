# Project Discovery Protocol

> Phase 0: Automatically detect the project's build configuration, code style, and architecture to provide dynamic context for subsequent Phases

---

## Overview

As the first step of every execution, the target project's profile is automatically discovered.
This is a mechanism for providing guidance tailored to the **actual project structure** instead of hardcoded conventions.

---

## Execution Procedure

### Step 0: Monorepo Detection (v2.2)

Before cache check, the script detects if the current directory is part of a monorepo:

```
Condition A: No settings.gradle.kts at root
             + Multiple settings.gradle.kts in 1-depth subdirectories (≥2)
             → Monorepo root detected

Condition B: settings.gradle.kts exists
             + Current directory ≠ Git root
             → Subproject detected (current dir = PROJECT_DIR)

Condition C: Neither A nor B
             → Single project (default behavior)
```

**Project Selection**:
```bash
# Default: auto-select based on current working directory
./discover-project.sh

# Explicit project selection
./discover-project.sh --project ./project-a
```

**Profile Output (monorepo mode)**:
```markdown
## Project Profile
- **monorepo**: true
- **project-name**: project-a
- **project-path**: /monorepo/project-a
- build: gradle-kotlin-dsl
...
```

**Cache Key (monorepo mode)**:
```
~/.claude/cache/sub-kopring-engineer-{hash}-{project-name}-profile.md
```

### Step 1: Cache Check

```
1. Calculate project-hash from md5 hash of the project root path
2. Check if cache file exists (includes project-name for monorepo)
3. If exists → Step 2 (hash verification)
4. If not → Step 3 (run script)
```

### Step 2: Cache Validity Verification

```
1. Calculate md5 hash of build.gradle.kts + settings.gradle.kts + .editorconfig
2. Compare with the stored hash on the first line of the cache file
3. Match → Use cache contents (proceed immediately)
4. Mismatch → Step 3 (rescan)
```

### Step 3: Run Script

```bash
bash scripts/discover-project.sh [project root] [--refresh] [--project <path>]
```

**Options**:
- `[project root]`: Target directory (default: current directory)
- `--refresh`: Force cache refresh
- `--project <path>`: Explicitly select a subproject in monorepo mode

The script automatically detects the following:

| Item | Detection Target |
|------|-----------------|
| **Build tool** | gradle-kotlin-dsl / gradle-groovy / maven |
| **Language** | kotlin / java / mixed (based on source directories + build configuration) |
| **Version** | Kotlin, JDK/Java, Spring Boot |
| **Module structure** | include statements in settings.gradle.kts |
| **Module dependencies** | project(":xxx") in each module's build.gradle.kts |
| **Source sets** | main, test, testFixtures, integrationTest |
| **Build logic** | build-logic/, buildSrc/, convention plugins |
| **Version catalog** | gradle/libs.versions.toml |
| **Plugins** | JPA, QueryDSL, JOOQ, kotlin-spring, lombok, checkstyle, spotless, etc. |
| **Query library** | querydsl / jooq / querydsl+jooq / none |
| **Test framework** | strikt/kotest/assertj, mockk/mockito, fixture-monkey |
| **Style configuration** | editorconfig, ktlint, detekt, checkstyle |
| **Lombok** | Usage (Java/mixed projects) |
| **Architecture pattern** | hexagonal (default) |
| **Layer paths** | Actual package paths (domain, ports, application, etc.) |
| **Naming patterns** | Entity suffix, Controller suffix, Repository pattern |

### Step 3b: Pattern Learning (automatic)

After discover-project.sh completes, `scripts/learn-patterns.sh` is automatically invoked.

```bash
# learn-patterns.sh learns code patterns in 5 categories:
# 1. Base Classes — abstract/open class inheritance trees
# 2. Custom Annotations — Project-specific annotations
# 3. Naming Patterns — Non-standard suffix patterns (≥3 files)
# 4. Test Fixtures — Factory/Fixture/TestHelper classes
# 5. Error Hierarchy — *Exception/*Error class trees
```

Cache location: `~/.claude/cache/sub-kopring-engineer-{project-hash}-learned-patterns.md`
- Invalidated using the same hash as discover-project.sh
- Target execution time: Under 5 seconds
- Ignored on failure (optional context)

### Step 4: Load Profile

Read the script output (or cache) and store in context for reference in subsequent Phases.
If a learned patterns cache exists, load it as well.

### Step 5: Static Analysis Tool Auto-Configuration

Static analysis tools are **automatically detected and configured** — no user prompt required.

```
1. Check if .sub-kopring-engineer/static-analysis-tools.txt exists
   - Exists → Read file and include in profile, check for newly added tools
   - Does not exist → Auto-detect from build plugins and save (see below)

2. Auto-detection (first run):
   - Scan profile plugins for: detekt, checkstyle, spotless, spotbugs, pmd, error-prone, archunit
   - Create .sub-kopring-engineer/static-analysis-tools.txt with all detected tools
   - Create .sub-kopring-engineer/.gitignore (excludes interaction-state.yaml)

3. Revalidation (subsequent runs):
   - New tools detected in build config → auto-add to allow-list

4. User override:
   - Edit .sub-kopring-engineer/static-analysis-tools.txt to add/remove tools
   - Delete the file to trigger re-detection
```

**Output format line:**
```
- static-analysis: spotless, detekt
```

`not-configured` means no tools detected. `none` means file exists but is empty.

### Step 6: CLAUDE.md Skill Guidance Injection

For Hexagonal architecture projects, skill guidance is **automatically added to CLAUDE.md**.

```
1. Check architecture type
   - Not hexagonal/ports-adapters → Skip injection

2. Check CLAUDE.md state
   - Does not exist → Create with skill guidance section
   - Exists but no "sub-kopring-engineer" mention → Append guidance section
   - Already contains "sub-kopring-engineer" → Skip (no duplicate)

3. Injected content:
   ## AI Coding Guidance (sub-kopring-engineer)
   - Workflow: Brainstorm → Plan → Implement → Verify
   - Validation: Layer boundary, module dependency direction
   - Usage: /sub-kopring-engineer [request]
```

This enables Claude to recognize the skill's availability without requiring explicit user invocation.

### Post-task Pattern Capture

For post-Verify pattern capture procedure, see [verify-protocol.md Section 3-4](./verify-protocol.md).

---

## Output Format

The script outputs a ~30-line compact summary in markdown:

```
## Project Profile
- build: gradle-kotlin-dsl
- language: kotlin
- kotlin: 1.9.23 | jdk: 21
- spring-boot: 3.2.5
- modules: core, application, infrastructure, api, bootstrap
- module-deps: core→(none), application→core, infrastructure→core, api→application, bootstrap→api+infrastructure
- build-logic: build-logic/ (convention plugins)
- version-catalog: gradle/libs.versions.toml
- source-sets: main, test, testFixtures, integrationTest
- plugins: spring-boot, jpa, querydsl, kotlin-spring, kotlin-jpa
- architecture: hexagonal (high confidence)
- query-lib: querydsl
- test: junit5, strikt, mockk, fixture-monkey
- style: ktlint (4 rules disabled), editorconfig (indent=4, max_line=140)
- static-analysis: spotless, detekt

## Layer Paths
- domain: com.example.core.domain
- ports: com.example.core
- application: com.example.application
- infrastructure: com.example.infrastructure
- presentation: com.example.api

## Detected Conventions
- entity-suffix: JpaEntity
- controller-suffix: RestController
- repository-pattern: Reader/Appender/Updater
- test-structure: flat (no @Nested)
- assertion: strikt (expectThat, expectThrows)
```

**Java project example:**
```
## Project Profile
- build: gradle-groovy
- language: java
- java: 21
- lombok: true
- java-style: checkstyle, spotless
- spring-boot: 3.2.5
- plugins: spring-boot, jpa, jooq, lombok, checkstyle, spotless
- architecture: hexagonal (high confidence)
- query-lib: jooq
- test: junit5, assertj, mockito, fixture-monkey
- style: checkstyle (google), editorconfig (indent=4)
- static-analysis: checkstyle, spotless
```

---

## Cache Behavior

| Situation | Behavior |
|-----------|----------|
| No cache | Run script → Save result to cache |
| Cache hash match | Use cache immediately (no script execution) |
| Cache hash mismatch | Re-run script → Update cache |
| `--refresh` flag | Force rescan (ignore hash) |

Cache location: `~/.claude/cache/sub-kopring-engineer-{project-hash}-profile.md`
- Does not pollute the project directory
- Uses md5 of the project path as project-hash

---

## Profile vs references/ Conflict Resolution Rules

**Principle: Project profile takes priority** (actual project > general guide)

| Situation | Applied Rule |
|-----------|-------------|
| Profile architecture = hexagonal | Apply all of references/ |
| Profile architecture = unknown | Use references/ defaults as-is (fallback to hexagonal) |
| Profile naming pattern ≠ references/ | Profile's actual patterns take priority |
| Items not in profile | Use references/ defaults |

### Hexagonal Architecture Rules
- Enforce Port/Adapter interface separation
- Reader/Appender/Updater Repository separation pattern
- No external dependencies in core/domain-model
- Controller → only reference UseCase rule

### Common Rules (always applied)
- No circular references between layers (Fowler: No circular references)
- No business logic in Presentation layer (Fowler: UI contains no business logic)
- Data Access layer must not depend on upper layers (Fowler: Lower layers don't depend on upper)
- Constructor injection (no @Autowired)
- No star imports
- Definition pattern instead of copy() (for domain models only)
- Test conventions (SUT pattern, assertion libraries)
- Git conventions
- JPA Entity and Domain Model separation

---

## Fallback Strategy

When script execution fails (no build files, permission errors, etc.):

1. **Ignore the error** and use existing references/ as-is
2. Notify the user of profile discovery failure (warning level)
3. Subsequent Phases proceed normally with existing hardcoded conventions
4. User can manually retry with `--refresh` if desired

```
⚠️ Project Discovery failed: build.gradle.kts not found.
   Proceeding with default conventions (Hexagonal Architecture).
```
