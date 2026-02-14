# sub-test-engineer

Type-aware testing workflow agent that generates high-quality tests for Java, Kotlin, TypeScript, and Go backends through automated type analysis, strategy selection, and iterative validation.

## Quick Start

```
# 1. Install: Copy this plugin directory into your Claude Code plugins path
# 2. Invoke the skill in a Claude Code session:
/sub-test-engineer OrderService 테스트 생성. loop 3
# 3. The agent runs: Analyze -> Strategize -> Generate -> Validate (x3 loops)
#    producing compiled, passing tests with coverage and mutation feedback.
```

## Features

- **Type-Driven Test Case Discovery** -- Extracts sealed classes, enums, validation annotations, and nullable types to automatically derive test cases (boundary values, subtype coverage, null paths).
- **3-Layer Type Extraction Pipeline** -- Layer 1a (ast-grep structural extraction), Layer 1b (LLM semantic interpretation), Layer 2 (ClassGraph bytecode enrichment). Falls back gracefully when tools are unavailable.
- **Multi-Technique Orchestration** -- Selects the optimal testing technique per code layer: property-based testing for domain logic, contract tests for APIs, architecture tests for structural rules, and more.
- **Coverage + Mutation Dual Feedback Loop** -- Uses line/branch coverage (JaCoCo, Kover, Istanbul) and mutation testing (PIT, Stryker) as feedback signals to iteratively close test gaps.
- **5-Stage Validation Pipeline** -- Compilation check, test execution, coverage measurement, mutation testing, and quality assessment (naming, assertions, isolation, determinism).
- **Project Pattern Conformance** -- Learns existing test patterns (naming conventions, assertion styles, fixture patterns, base classes) and generates tests that match the project style.
- **Large Scope Processing** -- For large targets (5+ test classes), supports sequential processing (default) or parallel generation via Agent Teams (experimental).
- **Convergence Failure Handling** -- 3-strike rule triggers root-cause analysis sub-agent when the same error recurs.
- **Test Debt Analysis** -- Scans packages for untested and under-tested code, produces prioritized action plans.

## Supported Languages

| Language | Frameworks | Test Frameworks | Mock Libraries | Coverage Tools |
|----------|-----------|-----------------|----------------|----------------|
| **Java** | Spring Boot, Jakarta EE | JUnit 5 | Mockito | JaCoCo, PIT |
| **Kotlin** | Spring Boot, Ktor | JUnit 5, Kotest | MockK, Mockito | JaCoCo, Kover, PIT |
| **TypeScript** | NestJS, Express | Jest, Vitest, Mocha | jest.mock, ts-mockito, Sinon | Istanbul/c8, Stryker |
| **Go** | Gin, Echo, net/http | testing, Ginkgo | testify/mock, mockgen | go test -cover |

## Usage Modes

| Mode | Input Example | Behavior |
|------|---------------|----------|
| **All-in-one** (default) | `OrderService 테스트 생성` | Analyze, Strategize, Generate, Validate (1 loop) |
| **All-in-one + loop** | `OrderService 테스트 생성. loop 3` | Full cycle with 3 validation iterations |
| **Step-by-step** | `analyze: PaymentService` | Execute only the specified phase |
| **Coverage target** | `coverage-target 80%` | Iterate until 80% coverage (max 5 loops) |
| **Technique-specific** | `property-test: OrderValidator` | Skip strategy selection, use specified technique |
| **Dry-run** | `OrderService 테스트. dry-run` | Simulate strategy without writing files |
| **Test debt** | `test-debt: com.example.order` | Analyze untested code, produce prioritized report |
| **Validate only** | `validate loop 2` | Discover existing tests, validate, gap-fill |

Step-by-step commands: `analyze`, `strategize:`, `generate`, `validate`

## Example Commands

```
# Generate tests for a service class with 3 validation loops
/sub-test-engineer OrderService 테스트 생성. loop 3

# Analyze a class without generating anything
/sub-test-engineer analyze: PaymentService

# Generate property-based tests for a domain validator
/sub-test-engineer property-test: OrderValidator

# Scan a package for untested code and get a prioritized plan
/sub-test-engineer test-debt: com.example.order

# Generate tests until 80% line coverage is reached
/sub-test-engineer OrderService. coverage-target 80%
```

## Architecture

### 5-Phase Pipeline

```
 ┌──────────┐   ┌─────────┐   ┌────────────┐   ┌──────────┐   ┌──────────┐
 │ Phase 0  │──>│ Phase 1 │──>│  Phase 2   │──>│ Phase 3  │──>│ Phase 4  │
 │ Discovery│   │ Analyze │   │ Strategize │   │ Generate │   │ Validate │
 └──────────┘   └─────────┘   └────────────┘   └──────────┘   └────┬─────┘
                                                     ^              │
                                                     │  Gap Report  │
                                                     └──────────────┘
```

- **Phase 0 (Discovery):** Detects test framework, mock library, coverage tools, module structure, existing patterns.
- **Phase 1 (Analyze):** 3-Layer type extraction -- ast-grep structural scan, LLM semantic interpretation, optional ClassGraph bytecode enrichment.
- **Phase 2 (Strategize):** Selects testing techniques per code layer (property-based, contract, architecture, mock-based unit, integration).
- **Phase 3 (Generate):** Writes test code following approved strategy and learned project patterns.
- **Phase 4 (Validate):** Runs 5-stage pipeline (compile, execute, coverage, mutation, quality). Feeds gap report back to Phase 3 for iterative improvement.

### 3-Layer Type Extraction

```
Layer 1a: ast-grep (deterministic, ~1s)
  └─ Method signatures, annotations, constructors, class hierarchy, enums
Layer 1b: LLM semantic interpretation (from Layer 1a JSON)
  └─ Code layer classification, complexity, cross-file inference, edge cases
Layer 2:  ClassGraph bytecode (optional, requires JDK 17+)
  └─ Full class hierarchy, resolved generics, sealed class subtypes
```

## File Structure

```
plugins/sub-test-engineer/
├── .claude-plugin/
│   └── plugin.json                    # Plugin metadata and hooks
├── skills/sub-test-engineer/
│   ├── SKILL.md                       # Core skill definition
│   ├── sgconfig.yml                   # ast-grep configuration
│   ├── resources/
│   │   ├── test-discovery-protocol.md # Phase 0 procedure
│   │   ├── analyze-protocol.md        # Phase 1 procedure
│   │   ├── strategize-protocol.md     # Phase 2 procedure
│   │   ├── generate-protocol.md       # Phase 3 procedure
│   │   ├── validate-protocol.md       # Phase 4 procedure
│   │   ├── validation-tiers.md        # LIGHT/STANDARD/THOROUGH tiers
│   │   └── error-playbook.md          # Error resolution protocols
│   ├── references/
│   │   ├── unit-testing-techniques.md
│   │   ├── go-testing-techniques.md
│   │   ├── integration-testing-techniques.md
│   │   ├── property-based-testing.md
│   │   ├── contract-testing.md
│   │   ├── mutation-testing.md
│   │   ├── architecture-testing.md
│   │   └── test-quality-checklist.md
│   ├── rules/
│   │   ├── java/extract-*.yml         # ast-grep rules for Java (5 rules)
│   │   ├── kotlin/extract-*.yml       # ast-grep rules for Kotlin (5 rules)
│   │   ├── typescript/extract-*.yml   # ast-grep rules for TypeScript (5 rules)
│   │   ├── go/extract-*.yml           # ast-grep rules for Go (4 rules)
│   │   └── __tests__/                 # Rule test fixtures per language
│   ├── scripts/
│   │   ├── check-ast-grep.sh          # ast-grep installation check
│   │   ├── check-agent-teams.sh       # Agent Teams availability check
│   │   ├── extract-types.sh           # Structural extraction wrapper
│   │   ├── extract-type-info.sh       # ClassGraph extraction wrapper
│   │   ├── measure-coverage.sh        # Coverage measurement
│   │   ├── run-mutation-test.sh       # Mutation testing execution
│   │   ├── setup-check.sh             # Environment setup verification
│   │   ├── hook-post-edit.sh          # Post-edit compile check hook
│   │   ├── hook-stop-gate.sh          # Session-end test gate hook
│   │   ├── verify-doc-consistency.sh  # Documentation consistency check
│   │   ├── agent-teams/               # Agent Teams scripts
│   │   │   ├── spawn-teammate.sh      # Teammate spawn wrapper
│   │   │   ├── poll-inbox.sh          # Inbox polling utility
│   │   │   ├── shutdown-team.sh       # Graceful shutdown
│   │   │   ├── detect-modules.sh      # Multi-module detection
│   │   │   ├── partition-targets.sh   # Target partitioning
│   │   │   └── aggregate-results.sh   # Result aggregation
│   │   ├── ci/check-quality.sh        # CI quality gate
│   │   ├── benchmark/
│   │   │   ├── run-benchmark.sh       # Benchmark runner
│   │   │   ├── collect-metrics.sh     # Metrics collector
│   │   │   ├── compare-runs.sh        # Cross-run comparison
│   │   │   ├── check-regression.sh    # Regression detection
│   │   │   ├── generate-report.sh     # Report generator
│   │   │   ├── thresholds.yml         # Pass/fail thresholds
│   │   │   ├── projects/              # Target project configs
│   │   │   └── results/               # Benchmark output
│   │   └── classgraph-extractor/      # Layer 2 bytecode extractor
│   └── templates/
│       ├── hooks-config.json          # Project-level hooks template
│       ├── validation-report-template.md
│       ├── forced-eval-hook.sh        # Skill activation improvement hook
│       ├── settings-forced-eval.json  # Settings template for forced eval
│       ├── team-config.json           # Agent Teams configuration
│       ├── task-schema.json           # Task definition schema
│       └── prompts/                   # Teammate prompts
│           ├── unit-tester.md
│           ├── integration-tester.md
│           └── property-tester.md
└── README.md                          # This file
```

## Requirements

| Requirement | Required | Notes |
|-------------|:--------:|-------|
| Claude Code | Yes | Runtime environment for the skill |
| ast-grep >= 0.30.0 | No | Enables Layer 1a structural extraction. Without it, falls back to LLM-only analysis. |
| JDK 17+ | No | Required for Layer 2 ClassGraph bytecode enrichment and running JVM-based projects. |
| Python 3 + PyYAML | No | Required for benchmark scripts (YAML config parsing). |

## Configuration

### Forced Eval Hook (Skill Activation Improvement)

By default, Claude Code skills have ~20% activation reliability. Adding a "Forced Eval Hook" improves this to ~84% by making Claude explicitly evaluate skill relevance before proceeding.

**Installation:**

```bash
# 1. Create hooks directory
mkdir -p ~/.claude/hooks

# 2. Copy the forced eval hook
cp plugins/sub-test-engineer/skills/sub-test-engineer/templates/forced-eval-hook.sh \
   ~/.claude/hooks/forced-eval-hook.sh

# 3. Make it executable
chmod +x ~/.claude/hooks/forced-eval-hook.sh

# 4. Add to ~/.claude/settings.json:
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/forced-eval-hook.sh"
          }
        ]
      }
    ]
  }
}
```

**How it works:**

1. `UserPromptSubmit` hook fires before Claude processes each user message
2. The hook injects instructions requiring Claude to:
   - Check for test-related keywords
   - Explicitly state if sub-test-engineer is relevant
   - Activate the skill via `Skill()` tool before implementation
3. This "commitment mechanism" prevents Claude from bypassing the skill

**Trade-off:** More verbose responses (evaluation visible in output), but significantly more reliable activation.

### Hooks Setup

Copy the hooks template into your project to enable automatic compile-checking on test file edits and a test quality gate on session stop:

```bash
# Option A: Project-level hooks (recommended)
cp plugins/sub-test-engineer/skills/sub-test-engineer/templates/hooks-config.json \
   /path/to/your-project/.claude/hooks-config.json

# Option B: Plugin-level hooks (already configured in plugin.json)
# No action needed — hooks are defined in .claude-plugin/plugin.json
```

**Hooks behavior:**
- **PostToolUse (Edit/Write):** When a test file (`*Test.kt`, `*Test.java`, `*.test.ts`) is modified, automatically runs a compile check.
- **Stop:** Before session ends, runs all modified tests. Blocks exit if tests fail.

### ast-grep Rules

The `sgconfig.yml` at the skill root configures rule directories:

```yaml
ruleDirs:
  - rules/java
  - rules/kotlin
  - rules/typescript
  - rules/go
testConfigs:
  - testDir: rules/__tests__/java
  - testDir: rules/__tests__/kotlin
  - testDir: rules/__tests__/typescript
  - testDir: rules/__tests__/go
```

Run extraction manually:

```bash
scripts/extract-types.sh <target-file-or-dir> [lang] [category]
```

## Benchmark

Benchmark scripts validate the skill against real-world reference projects.

### Running a Benchmark

```bash
cd plugins/sub-test-engineer/skills/sub-test-engineer

# Run against a specific project
scripts/benchmark/run-benchmark.sh scripts/benchmark/projects/petclinic-kotlin.yml

# Compare two benchmark runs
scripts/benchmark/compare-runs.sh results/2025-01-01 results/2025-01-15

# Check for regressions against thresholds
scripts/benchmark/check-regression.sh results/2025-01-15
```

### Reference Projects

| Project | Language | Build Tool | Config |
|---------|----------|------------|--------|
| spring-petclinic-kotlin | Kotlin | Gradle | `projects/petclinic-kotlin.yml` |
| spring-petclinic-java | Java | Gradle | `projects/petclinic-java.yml` |
| nestjs-realworld | TypeScript | npm | `projects/nestjs-realworld.yml` |

Results are stored in `scripts/benchmark/results/`.

## Agent Teams (Experimental)

For large test generation tasks (5+ targets), Agent Teams enables parallel generation via multiple Claude instances:

### Enabling Agent Teams

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Or in your Claude Code settings:

```json
{
  "experimental": {
    "agentTeams": true
  }
}
```

### How It Works

When Agent Teams is enabled and targets >= 5:

1. **Team Lead** (your session) completes Phase 0-2 (Discovery, Analyze, Strategize)
2. **Teammates** are spawned for parallel generation:
   - `unit-tester`: Generates unit tests
   - `integration-tester`: Generates integration tests
   - `property-tester`: Generates property-based tests
3. Each Teammate works in its own context window, reducing context pressure
4. Lead collects results and proceeds to Phase 4 (Validate)

### Trade-offs

| Metric | Sequential | Agent Teams |
|--------|------------|-------------|
| Time (5 targets) | ~15 min | ~6 min |
| Token cost | 1x | ~2.5x |
| Context pressure | High | Low per agent |

### Fallback Behavior

- If Agent Teams is not enabled: uses sequential processing
- If Teammate spawn fails: falls back to sequential for failed targets
- No code changes required -- automatic detection

See the repository documentation for full design details.

## Related

- [sub-kopring-engineer](../sub-kopring-engineer/) -- Kotlin/Java Spring Boot code generation workflow agent
- [CLAUDE.md](../../CLAUDE.md) -- Project-level skill index and conventions
