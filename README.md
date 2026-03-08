# Claude Code Skills

A curated collection of practical Claude Code skills for real engineering workflows.

This repository includes implementation guidance, type-driven test generation, cross-domain architecture routing (DB/BE/IF/SE), plugin introspection, and numerical verification/optimization. The skills are script-first and designed for lightweight, reproducible execution.

| Skill | Command | Purpose |
|-------|---------|---------|
| [sub-kopring-engineer](#sub-kopring-engineer) | `/sub-kopring-engineer` | Kotlin/Java Spring Boot implementation workflow |
| [sub-test-engineer](#sub-test-engineer) | `/sub-test-engineer` | Type-driven test generation |
| [engineering-workflow](#engineering-workflow) | `/engineering-workflow` | Engineering architecture routing across DB/BE/IF/SE |
| [plugin-introspector](#plugin-introspector) | `/plugin-introspector` | Plugin monitoring and self-improvement |
| [numerical](#numerical) | `/numerical` | Numerical computing verification and optimization |
| [claude-autopilot](#claude-autopilot) | `/claude-autopilot` | Time-bounded autonomous task orchestration |

## Install

Marketplace:

```
/plugin marketplace add brody-0125/claude-stunning-waddle
/plugin install <skill-name>@personal-plugins
```

Manual:

```
git clone https://github.com/brody-0125/claude-stunning-waddle.git
cp -r plugins/<skill-name>/skills/<skill-name> /path/to/project/.claude/skills/
```

---

## sub-kopring-engineer

Runs a Brainstorm, Plan, Implement, Verify pipeline on Kotlin/Java Spring Boot codebases.

Scans build files to detect the project language (Kotlin, Java, or mixed), architecture style (Hexagonal, Layered, Clean), and query library (JOOQ, QueryDSL). Convention checks run through a shell script (`verify-conventions.sh`, 578 lines) so they cost zero LLM tokens.

```
/sub-kopring-engineer
Order 취소 기능 구현해줘. loop 3
```

### Modes

| Mode | Example | Behavior |
|------|---------|----------|
| All-in-one | `Order 취소 기능` | Full pipeline, single pass |
| Loop | `Order 취소. loop 3` | Repeats Verify up to 3 times |
| Per-phase | `plan: 결제 취소` | Runs only the specified phase |
| Verify-only | `verify loop 2` | Verifies current code twice |
| Dry run | `Order 취소. dry-run` | Stops after Plan, no file changes |
| PRD | `Order 취소. prd loop 3` | Exits early when all acceptance criteria pass |

### Workflow

**Phase 0: Project Discovery.** `discover-project.sh` scans build files and source directories. Results are cached and not re-run unless the project structure changes.

**Phase 1: Brainstorm.** Only fires on ambiguous requests. Classifies ambiguity as LOW, MEDIUM, or HIGH. LOW gets defaults applied silently. MEDIUM gets a choice list. HIGH asks for more info. Specific instructions like "add soft delete" skip this phase.

**Phase 2: Plan.** Reads existing code and builds an implementation plan. Loads reference docs matching the detected language and architecture.

**Phase 3: Implement.** Writes code per the plan. When 10+ files change, the work splits into Domain, Infrastructure, and Test subagents to avoid cross-layer context pollution.

**Phase 4: Verify.** Runs `verify-conventions.sh` across 7 categories, 25 check items. Picks a tier based on change size: LIGHT (under 5 files), STANDARD (default), or THOROUGH (20+ files). If the same violation shows up 3 times, a root-cause analysis agent takes over and switches approach.

### Convention checks

| Category | Checks | Examples |
|----------|-------:|---------|
| Architecture | 7 | Layer dependency direction, port/adapter separation |
| Style | 5 | Constructor injection, no `@Autowired` |
| Naming | 4 | `*JpaEntity`, `*RestController` |
| JOOQ | 1 | Type-safe queries (only when JOOQ detected) |
| Test | 2 | No `@Nested` in Kotlin, SUT naming |
| JPA | 2 | `@DynamicUpdate`, `toModel()` |
| Git | 4 | Branch name format, commit message format |

Every check runs as a shell command. No LLM calls. Deterministic output.

### Pattern learning

`learn-patterns.sh` (373 lines) extracts base classes, custom annotations, naming patterns, and 4 other categories from the source tree, then caches results under `~/.claude/cache/`. After each Verify loop, `capture-task-patterns.sh` (322 lines) detects new patterns and only adds user-approved ones to the cache.

Cache invalidation triggers on MD5 hash change of build config files or source file count change.

### Context budget

Each phase loads only the docs it needs.

| Phase | Loaded docs | Tokens |
|-------|-------------|-------:|
| Always | SKILL.md (147 lines) | ~1,200 |
| Phase 0 | project-discovery-protocol.md + script output | ~2,400 |
| Phase 1 | brainstorm-protocol.md | ~730 |
| Phase 2 | plan-protocol + architecture ref + code style ref | ~3,740 |
| Phase 3 | + test refs + git-conventions | ~1,890 |
| Phase 4 | verification-tiers + error-playbook + script execution | ~1,580 |
| **Total** | | **~11,540** |

Worst case is under 15% of a 200K context window. With lazy loading, actual concurrent usage stays below 10%.

### Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| PostToolUse | `.kt`/`.java` file edited | `ktlintCheck` or `checkstyleMain` |
| PreToolUse | Secret file access | Blocks modification |
| Stop | Session end | `./gradlew test` must pass |

Manual setup: `scripts/setup-hooks.sh [project-path]`

> [SKILL.md](./plugins/sub-kopring-engineer/skills/sub-kopring-engineer/SKILL.md)

---

## sub-test-engineer

Reads type information from Java/Kotlin/TypeScript backends and generates tests. Follows an Analyze, Strategize, Generate, Validate sequence.

Derives test cases from type structures like sealed classes, enums, and validation annotations. Picks a fitting technique per code layer: property-based testing, contract tests, architecture tests, etc.

```
/sub-test-engineer
OrderService 테스트 생성. loop 3
```

### Modes

| Mode | Example | Behavior |
|------|---------|----------|
| All-in-one | `OrderService 테스트 생성` | Full pipeline |
| Loop | `loop 3` | Repeats Validate 3 times |
| Coverage target | `coverage-target 80%` | Loops until target met |
| Technique | `property-test: OrderValidator` | Runs only the specified technique |
| Test debt | `test-debt: com.example.order` | Analyzes untested code |
| Dry run | `dry-run` | Strategy simulation only |

### Type extraction

Three stages:

1. ast-grep for structural extraction (sealed class branches, annotation parameters)
2. LLM for semantic interpretation (business rules, boundary values)
3. ClassGraph for bytecode augmentation (runtime type relationships, generics)

### Validation pipeline

Five stages: compile, execute, measure coverage, run mutation tests, evaluate quality. Both coverage and mutation results feed back into the loop.

With 5+ targets, Agent Teams (experimental) can generate tests in parallel. Observed ~60% time reduction in benchmarks.

> [SKILL.md](./plugins/sub-test-engineer/skills/sub-test-engineer/SKILL.md)

---

## engineering-workflow

Routes architecture queries across **DB** (Database), **BE** (Backend), **IF** (Infrastructure), and **SE** (Security) domains using a 3-tier micro-agent orchestration model.

Starts with deterministic keyword classification (`classify-query.sh`), dispatches to system orchestrators and domain agents, then resolves cross-domain constraints before generating final recommendations. All agents enforce structured Exit Checklists for output validation, ensuring schema compliance and confidence-bounded responses.

```
/engineering-workflow
"Design a multi-tenant architecture with tenant isolation"
```

### Modes

| Mode | Example | Behavior |
|------|---------|----------|
| Query (default) | `"index design for large tables"` | Full pipeline: classify, dispatch, resolve, synthesize |
| Analyze | `analyze: current sharding strategy` | Deep analysis without recommendation focus |
| Compare | `compare: PostgreSQL vs CockroachDB` | Structured comparison and trade-off matrix |
| Recommend | `recommend: caching strategy for read-heavy API` | Recommendation-first output with priorities |
| Shallow | `--depth shallow` | Single primary domain, quick guidance |
| Deep | `--depth deep` | Multi-domain/cross-system orchestration |

### Core scripts

- `classify-query.sh`: deterministic fast-path classification
- `resolve-constraints.sh`: conflict detection and constraint merging
- `audit-analysis.sh`: confidence/schema/synthesis quality checks
- `format-output.sh`: standardized final output formatting

> [SKILL.md](./plugins/engineering-workflow/skills/engineering-workflow/SKILL.md) / [README](./plugins/engineering-workflow/README.md)

---

## plugin-introspector

A meta-plugin that collects tool calls, API requests, token usage, and execution patterns from other Claude Code plugins, then uses that data to improve them.

```
/plugin-introspector dashboard
/plugin-introspector quick-scan --target my-plugin
```

### Commands

| Command | What it does |
|---------|-------------|
| `status` | Session overview |
| `dashboard` | htop-style live monitoring |
| `flow` | Execution flow tree (OTel-based) |
| `analyze` | Workflow deep-dive |
| `tokens` | Token usage analysis with optimization suggestions |
| `quick-scan` | Plugin structure and security check (~1 min) |
| `security-dashboard` | Security risk visualization |
| `optimize` | APE loop-based prompt optimization |
| `evaluate` | LLM-as-Judge quality scoring on 4 dimensions |
| `report` | Full analysis report |

Ships with 12 analysis agents. Tracing is OTel GenAI Semantic Conventions compatible. Anomaly detection uses Z-score plus moving average. Data stored as JSONL; no dependencies beyond bash and jq.

### Security

Off by default. Toggle with environment variables:

```bash
export PI_ENABLE_SECURITY=1   # security checks
export PI_ENABLE_DLP=1         # sensitive data detection
export PI_SECURITY_BLOCK=1     # block CRITICAL commands
```

`security-scan` does static analysis on plugins. `compliance-report` generates SOC 2 / ISO 27001 reports.

> [SKILL.md](./plugins/plugin-introspector/skills/plugin-introspector/SKILL.md)

---

## numerical

Verifies correctness and optimizes performance of numerical computing code in Python and Dart. Follows an Analyze, Verify, Optimize sequence.

Scans build files (`pyproject.toml`, `pubspec.yaml`) to detect the project language, numeric libraries (NumPy, SciPy, CuPy, PyTorch, dart_tensor), and GPU support. Provides IEEE 754 floating-point analysis, broadcasting validation, dtype tracking, and SIMD/GPU optimization suggestions.

```
/numerical
numpy broadcasting 검증. loop 2
```

### Modes

| Mode | Example | Behavior |
|------|---------|----------|
| All-in-one | `numpy broadcasting 검증` | Full pipeline, single pass |
| Loop | `verify loop 3` | Repeats Verify up to 3 times |
| Per-phase | `analyze: matrix_ops.py` | Runs only the specified phase |
| Dry run | `precision 분석. dry-run` | Stops after Analyze, no file changes |
| Verify-only | `verify-only` | Skips Optimize phase |

### Workflow

**Phase 0: Project Discovery.** `discover-project.sh` scans build files and source directories. Detects language, libraries, GPU support, and numeric profiles. Results are cached.

**Phase 1: Analyze.** Examines numerical operation patterns, traces dtype and shape flow, and identifies precision risks such as catastrophic cancellation, implicit type promotion, and unstable formulas.

**Phase 2: Verify.** Runs `verify-numeric.sh` for floating-point correctness checks, broadcasting rule validation, test case verification (expected value math, tolerance appropriateness, edge case coverage), and memory layout consistency. Picks a tier based on computational complexity: LIGHT, STANDARD, or THOROUGH.

**Phase 3: Optimize.** Suggests SIMD vectorization opportunities, GPU memory management improvements (unnecessary host-device transfers, mixed precision), memory layout optimization (C/Fortran-contiguous alignment, cache efficiency), and numerically stable algorithm alternatives (log-sum-exp, Kahan summation, Welford's algorithm).

### Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| PostToolUse | `.py` file edited | `ruff check` or `flake8` (NumPy rules) |
| PostToolUse | `.dart` file edited | `dart analyze` |
| PreToolUse | Secret file access | Blocks modification |
| Stop | Session end | `pytest` or `dart test` must pass |

> [SKILL.md](./plugins/numerical/skills/numerical/SKILL.md)

---

## claude-autopilot

Time-bounded autonomous orchestration agent. Accepts a user directive and a deadline, then executes tasks autonomously until the specified time. Manages task decomposition, prioritization, progress tracking, and graceful wind-down near deadline.

```
/claude-autopilot
API 엔드포인트 리팩토링하고 테스트 추가해줘. --until 15:30
```

### Modes

| Mode | Example | Behavior |
|------|---------|----------|
| Standard | `"리팩토링해줘. 15:30까지"` | Full pipeline: Parse → Decompose → Execute → Wind-down → Report |
| Priority | `"버그 수정 --until 14:00 --priority high"` | High-impact tasks first, skip low priority if time runs out |
| Quick | `"TODO 정리 --until 13:00 --priority quick"` | Many small tasks, fast completion |
| Dry-run | `"리팩토링 분석. dry-run --until 16:00"` | Decompose only, outputs task plan without executing |
| Resume | `"autopilot resume"` | Continues a previously interrupted session |

### Workflow

**Phase 0: Parse & Init.** Parses directive and deadline from user input. Initializes session state at `~/.claude/cache/claude-autopilot/session-state.json`. Detects project structure.

**Phase 1: Decompose.** Breaks the directive into concrete tasks with dependency analysis (DAG). Estimates size (S/M/L/XL) and allocates time budget per task. Skips low-priority tasks that won't fit.

**Phase 2: Execute Loop.** Iterates: check remaining time → pick next task → execute → verify result → update state. Monitors time level (NORMAL → AWARE → CAUTION → WIND_DOWN → CRITICAL) and transitions to wind-down when deadline approaches.

**Phase 3: Wind-down.** Safely completes or rolls back in-progress work. Ensures code consistency, cleans up temp files, commits checkpoint.

**Phase 4: Report.** Outputs a session summary: completed/incomplete tasks, changed files, time spent, and recommendations for the next session.

### Time management

| Remaining | Level | Action |
|-----------|-------|--------|
| > 50% | NORMAL | Normal execution |
| 30-50% | AWARE | Avoid starting large tasks |
| 15-30% | CAUTION | No new tasks, finish current |
| 5-15% | WIND_DOWN | Enter Phase 3 |
| < 5% | CRITICAL | Save immediately, output report |

### Safety guardrails

- No destructive operations without backup (`rm -rf`, `git reset --hard`)
- Secret file edits blocked (`.env`, credentials, private keys)
- Scope enforcement — no edits outside user-specified scope
- Force push forbidden
- Auto-halt on 3 consecutive identical errors or mass test failure

### Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| PreToolUse | Edit/Write | Blocks secret file modification |
| PreToolUse | Edit/Write/Bash | Blocks actions after deadline |
| PreToolUse | Edit/Write | Blocks edits outside scope |
| PostToolUse | Edit/Write | Records last activity timestamp |
| Stop | Session end | Archives session state to history |

### Sister-skill integration

Delegates specialized work to other plugins when detected:

| Task type | Delegated to |
|-----------|-------------|
| Kotlin/Java code | sub-kopring-engineer |
| Test generation | sub-test-engineer |
| Numerical verification | numerical |
| Architecture analysis | engineering-workflow |

### Gran Maestro integration

When [gran-maestro](https://github.com/myrtlepn/gran-maestro) is installed, autopilot can read PLN plans and execute REQ batches autonomously within the time budget.

> [SKILL.md](./plugins/claude-autopilot/skills/claude-autopilot/SKILL.md)

---

## Project layout

```
plugins/
  sub-kopring-engineer/
    .claude-plugin/plugin.json
    skills/sub-kopring-engineer/
      SKILL.md                          # workflow definition (147 lines)
      references/                       # 11 language/style convention docs
      resources/                        # 8 per-phase protocol docs
      scripts/                          # 5 shell scripts
      templates/                        # 3 plan/PRD templates
  sub-test-engineer/
    .claude-plugin/plugin.json
    skills/sub-test-engineer/
      SKILL.md
  engineering-workflow/
    .claude-plugin/plugin.json
    skills/engineering-workflow/
      SKILL.md                          # routing/orchestration definition
      agents/                           # system orchestrators + micro agents
      resources/                        # phase protocols and matrices
      references/                       # DB/BE static technical references
      scripts/                          # classify/audit/resolve/format scripts
      tests/                            # classification/constraint/validation/format tests
      templates/                        # progress/constraint/hooks templates
  plugin-introspector/
    .claude-plugin/plugin.json
    skills/
      plugin-introspector/SKILL.md      # main
      meta-rules/SKILL.md
      analysis-patterns/SKILL.md
      cost-tracking/SKILL.md
  numerical/
    .claude-plugin/plugin.json
    skills/numerical/
      SKILL.md                          # workflow definition
      references/                       # 6 numeric/GPU/SIMD convention docs
      resources/                        # 6 per-phase protocol docs
      scripts/                          # 3 shell scripts
      templates/                        # 4 report/config templates
  claude-autopilot/
    .claude-plugin/plugin.json
    skills/claude-autopilot/
      SKILL.md                          # orchestration workflow definition
      resources/                        # 8 phase protocol docs
      scripts/                          # 8 shell scripts (deadline, session, gate checks)
      templates/                        # 3 report/hooks templates
```

### File stats (sub-kopring-engineer)

| Category | Files | Lines |
|----------|------:|------:|
| SKILL.md | 1 | 147 |
| resources/ | 8 | 1,032 |
| references/ | 11 | 2,612 |
| scripts/ | 5 | 1,965 |
| templates/ | 3 | 185 |
| **Total** | **28** | **5,941** |

## License

MIT
