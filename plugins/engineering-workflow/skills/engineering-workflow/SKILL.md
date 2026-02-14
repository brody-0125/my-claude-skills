---
name: engineering-workflow
description: >-
  Micro-agent system for engineering architecture decisions across DB, BE, IF, SE domains.
  Routes queries to specialized micro agents for deep technical analysis.
  Activated by keywords: "db architecture", "storage engine", "index design", "query optimization",
  "concurrency", "isolation level", "schema design", "replication", "sharding", "consistency model",
  "engineering workflow", "architecture decision".
argument-hint: "[query | analyze | compare | recommend] [--domain db|be|if|se] [--depth shallow|deep]"
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Task
---

# Engineering Workflow — Micro-Agent Orchestration System

> A 3-tier micro-agent system that routes engineering architecture queries to specialized domain agents,
> resolves cross-domain constraints, and synthesizes unified recommendations.

## Role

A **3-tier micro-agent orchestration system** for engineering architecture decisions spanning four
major systems: **DB** (Database), **BE** (Backend), **IF** (Infrastructure), and **SE** (Security).
Instead of a monolithic analysis approach, this plugin decomposes queries into domain-specific
sub-problems, dispatches them to specialized micro agents, and synthesizes their outputs into
coherent, constraint-aware recommendations.

### Architecture Overview

```
                         Tier 1: Gateway Router (this SKILL.md)
                                    |
                    ┌───────────────┼───────────────┐
                    |               |               |
               Tier 2: System Orchestrators
               ┌────┐  ┌────┐  ┌────┐  ┌────┐
               │ DB │  │ BE │  │ IF │  │ SE │
               └──┬─┘  └──┬─┘  └──┬─┘  └──┬─┘
                  |        |        |        |
               Tier 3: Micro Agents (domain-specific)
               ┌─────────────────────────────┐
               │ A: Storage  D: API Design   │
               │ B: Query    E: Concurrency  │
               │ C: Schema   F: Networking   │
               │ ...         ...             │
               └─────────────────────────────┘
```

### Core Principles

1. **Route, don't monolith**: Every query is classified and routed to the narrowest competent agent
2. **Constraint-first synthesis**: Agents declare constraints; conflicts are detected and resolved before output
3. **Token-efficient orchestration**: Only load agent definitions and references needed for the specific query
4. **Deterministic fast-path**: Use `classify-query.sh` for unambiguous queries; reserve LLM classification for edge cases
5. **Graceful degradation**: If an agent fails or times out, return partial results with clear warnings

---

## Routing Table

### System Detection

| System | Keywords | Orchestrator |
|--------|----------|--------------|
| **DB** | database, storage engine, index, query optimization, schema, replication, sharding, partition, consistency model, isolation level, MVCC, WAL, B-tree, LSM, vacuum, ACID | `agents/db-orchestrator.md` |
| **BE** | backend, API design, service layer, concurrency, thread pool, connection pool, caching strategy, microservice, event-driven, CQRS, saga, domain model | `agents/be-orchestrator.md` |
| **IF** | infrastructure, deployment, container, kubernetes, CI/CD, load balancer, CDN, monitoring, observability, scaling, network topology, DNS, TLS | `agents/if-orchestrator.md` |
| **SE** | security, authentication, authorization, encryption, key management, RBAC, ABAC, OAuth, JWT, zero-trust, penetration, vulnerability, compliance | `agents/se-orchestrator.md` |

### DB Sub-Domain Detection (A-F)

| Sub-Domain | Code | Keywords | Agents |
|------------|------|----------|--------|
| Storage Engine | A | storage engine, B-tree, LSM-tree, page layout, WAL, buffer pool, compaction, write amplification | `a1-engine-selector`, `a2-compaction-strategist` |
| Index & Query Plan | B | query plan, explain analyze, index scan, seq scan, join strategy, cost estimation, query rewrite, statistics | `b1-index-architect`, `b2-join-optimizer`, `b3-query-plan-analyst` |
| Concurrency & Locking | C | concurrency, isolation level, MVCC, locking, deadlock, optimistic, pessimistic, serializable, phantom read | `c1-isolation-advisor`, `c2-mvcc-specialist`, `c3-lock-designer` |
| Schema & Normalization | D | schema design, normalization, denormalization, document model, embedding, referencing, access pattern | `d1-schema-expert`, `d2-document-modeler`, `d3-access-pattern-modeler` |
| I/O & Buffer Management | E | page, buffer pool, WAL, write-ahead log, checkpoint, dirty page, flush, I/O optimization | `e1-page-optimizer`, `e2-wal-engineer`, `e3-buffer-tuner` |
| Distributed & Replication | F | replication, failover, consensus, raft, paxos, sharding, partition, consistency, CAP theorem | `f1-replication-designer`, `f2-consistency-selector`, `f3-sharding-architect` |

### BE Sub-Domain Detection (4 Clusters: S/B/R/T)

| Cluster | Sub-Domain | Code | Keywords | Agent |
|---------|------------|------|----------|-------|
| **S** Structure | Dependency Audit | S1 | dependency violation, import direction, runtimeOnly, layer rule, module boundary | `agents/be/s1-dependency-auditor.md` |
| **S** Structure | DI Pattern | S2 | Port design, Adapter injection, Constructor Injection, Stub pattern, DI | `agents/be/s2-di-pattern-selector.md` |
| **S** Structure | Architecture | S3 | new module, naming convention, publisher vs producer, module layout, hexagonal | `agents/be/s3-architecture-advisor.md` |
| **S** Structure | Fitness Function | S4 | ArchUnit, Konsist, checkTestNames, fitness function, CI automation | `agents/be/s4-fitness-engineer.md` |
| **B** Boundary | Context Classification | B1 | external system, ACL vs Conformist, Semantic Gap, context mapping | `agents/be/b1-context-classifier.md` |
| **B** Boundary | ACL Design | B2 | ACL design, Translator, Feign, testFixtures, anti-corruption | `agents/be/b2-acl-designer.md` |
| **B** Boundary | Event Architecture | B3 | internal event, external event, SQS, event versioning, domain event | `agents/be/b3-event-architect.md` |
| **B** Boundary | Saga Coordination | B4 | payment flow, compensation, Saga, Pivot step, compensable, retryable | `agents/be/b4-saga-coordinator.md` |
| **R** Resilience | Bulkhead | R1 | bulkhead, Thread Pool, Semaphore, pool size, isolation | `agents/be/r1-bulkhead-architect.md` |
| **R** Resilience | Circuit Breaker | R2 | Circuit Breaker, failureRate, slowCall, Resilience4j, half-open | `agents/be/r2-cb-configurator.md` |
| **R** Resilience | Retry/Timeout | R3 | timeout budget, retry, fallback, idempotencyKey, backoff | `agents/be/r3-retry-strategist.md` |
| **R** Resilience | Observability | R4 | monitoring, dashboard, tracing, Grafana, Prometheus, alert rule, micrometer | `agents/be/r4-observability-designer.md` |
| **S** Structure | Convention Verifier | S5 | convention, code style, naming rule, JPA pattern, entity model, dynamic update | `agents/be/s5-convention-verifier.md` |
| **B** Boundary | Implementation Guide | B5 | implementation guide, code pattern, feign client, translator code, saga implementation | `agents/be/b5-implementation-guide.md` |
| **T** Test | Test Guard | T1 | Fixture Monkey, FakeRepository, test name byte, spyk, MockK, testcontainers | `agents/be/t1-test-guard.md` |
| **T** Test | Test Strategist | T2 | test strategy, test technique, coverage target, property-based, contract test | `agents/be/t2-test-strategist.md` |
| **T** Test | Test Generator | T3 | generate test, test generation, write test, focal context, type-driven | `agents/be/t3-test-generator.md` |
| **T** Test | Quality Assessor | T4 | test quality, coverage, mutation, validation pipeline, gap analysis | `agents/be/t4-quality-assessor.md` |

---

## Execution Patterns

### Pattern 1: Single-Domain (1 Agent)

The simplest case. Query maps to exactly one system and one sub-domain.

```
User: "Should I use B-tree or LSM-tree for my write-heavy workload?"
  → System: DB
  → Sub-domain: A (Storage Engine)
  → Dispatch: db-orchestrator → a1-engine-selector
  → Token budget: ~6K
```

**Flow**:
```
Gateway Router
  └─→ classify-query.sh → { system: "DB", domains: ["A"], confidence: 0.95 }
  └─→ Read agents/db-orchestrator.md
  └─→ Task(db-orchestrator): "Route to a1-engine-selector for B-tree vs LSM comparison"
        └─→ Read agents/db/a1-engine-selector.md
        └─→ Task(a1-engine-selector): "Compare B-tree and LSM-tree for write-heavy workload"
        └─→ Return: analysis + recommendation + constraints
  └─→ format-output.sh → structured output
```

### Pattern 2: Multi-Domain (2-3 Agents within Same System)

Query spans multiple sub-domains within one system. Agents run in parallel; results are merged
with constraint resolution.

```
User: "Design a schema for time-series data with high write throughput and range queries"
  → System: DB
  → Sub-domains: A (Storage Engine) + D (Schema & Normalization) + B (Index & Query Plan)
  → Dispatch: db-orchestrator → 3 agents parallel
  → Token budget: ~10K
```

**Flow**:
```
Gateway Router
  └─→ classify-query.sh → { system: "DB", domains: ["A", "D", "B"], confidence: 0.88 }
  └─→ Read agents/db-orchestrator.md
  └─→ Task(db-orchestrator):
        ├─→ Task(a1-engine-selector): "LSM vs B-tree for time-series writes"
        ├─→ Task(d1-schema-expert): "Time-series schema with partitioning"
        └─→ Task(b1-index-architect): "Range query optimization for time-series"
        └─→ resolve-constraints.sh → merge constraints from 3 agents
        └─→ Return: unified analysis + resolved constraints
  └─→ format-output.sh → structured output
```

### Pattern 3: Cross-System (DB+BE, DB+SE, etc.)

Query requires agents from different systems. Multiple orchestrators run, then a synthesizer
merges results across system boundaries.

```
User: "Design a multi-tenant architecture with tenant isolation at DB and API levels"
  → Systems: DB + BE + SE
  → Dispatch: 3 orchestrators → synthesizer
  → Token budget: ~14K
```

**Flow**:
```
Gateway Router
  └─→ classify-query.sh → { systems: ["DB", "BE", "SE"], confidence: 0.82 }
  └─→ Read agents/db-orchestrator.md, agents/be-orchestrator.md, agents/se-orchestrator.md
  └─→ Parallel:
  │   ├─→ Task(db-orchestrator): "Multi-tenant DB isolation (schema-per-tenant vs RLS)"
  │   ├─→ Task(be-orchestrator): "Multi-tenant API routing and context propagation"
  │   └─→ Task(se-orchestrator): "Tenant-level authorization and data isolation"
  └─→ Read agents/synthesizer.md
  └─→ Task(synthesizer): merge 3 orchestrator outputs + resolve cross-system constraints
  └─→ format-output.sh → structured output
```

---

## Phase Flow

### Phase 0: Query Classification

> **Resource**: Read [resources/routing-protocol.md](./resources/routing-protocol.md) when entering this phase.

1. Parse user input for explicit flags (`--domain`, `--depth`)
2. Run `scripts/classify-query.sh "$QUERY"` for keyword-based fast-path classification
3. If confidence >= 0.85: proceed with fast-path result
4. If confidence < 0.85: use LLM classification (read routing-protocol.md for detailed algorithm)
5. Output: `{ systems: [...], domains: [...], pattern: "single|multi|cross", confidence: float }`

**Status Display**:
```
[engineering-workflow] Phase: Classification | Pattern: {single|multi|cross} | Systems: {DB,BE,...}
```

### Phase 1: Orchestrator Dispatch

> **Resource**: Read [resources/orchestration-protocol.md](./resources/orchestration-protocol.md) when entering this phase.

1. Based on classification result, identify required orchestrator(s)
2. Read the orchestrator `.md` file(s) from `agents/`
3. Construct Task prompt per orchestration-protocol.md template
4. For single-system: invoke one orchestrator Task
5. For cross-system: invoke multiple orchestrator Tasks in parallel

**Orchestrator Task prompt template**:
```
You are the {system} System Orchestrator.

## Classification
{classification result from Phase 0}

## User Query
{original user query}

## Instructions
Read the relevant agent definition(s) from agents/{system}/ and dispatch sub-tasks.
Collect agent outputs and resolve intra-system constraints.
Return your analysis in the structured format defined in your orchestrator definition.
```

### Phase 2: Agent Execution

Orchestrators handle this phase internally. Each orchestrator:

1. Reads the required agent `.md` file(s) from `agents/{system}/`
2. Constructs focused Task prompts for each agent
3. For multi-domain: dispatches agents in parallel via concurrent Task calls
4. Collects results and performs intra-system constraint merge
5. Returns structured output with constraints declared

**Agent Task prompt template**:
```
You are the {domain} Micro Agent.

## Query Context
{focused sub-question extracted by orchestrator}

## Reference Material
{relevant excerpts loaded by orchestrator via Read with offset/limit}

## Output Requirements
1. Analysis: detailed technical analysis
2. Recommendation: concrete actionable recommendation
3. Constraints: declare any constraints your recommendation imposes on other domains
4. Trade-offs: explicit trade-off documentation
```

### Phase 2.5: Analysis Quality Gate

> **Resource**: Read [resources/analysis-audit-protocol.md](./resources/analysis-audit-protocol.md) when entering this phase.

Audit tier is determined automatically based on classification and agent count
(`scripts/audit-analysis.sh tier`). This phase validates agent output quality
before constraint resolution.

| Tier | Steps | Additional Tokens |
|------|-------|-------------------|
| LIGHT | Confidence gating only | +0.3K |
| STANDARD | Confidence + Completeness + Feasibility | +1.5K |
| THOROUGH | All above + Dynamic Expansion via `audit-reviewer` agent | +3.5K |

**Steps**:
1. **Confidence Gating** (all tiers): Run `scripts/audit-analysis.sh confidence` per agent result
   - >= 0.70: PASS
   - 0.50-0.69: PASS + warning
   - 0.30-0.49: Simplified re-dispatch (1 attempt)
   - < 0.30: Reject, orchestrator fallback
2. **Completeness Audit** (STANDARD+): 6-point checklist (context, quantitative data, trade-offs, constraints, actionability, query reference)
3. **Feasibility Check** (STANDARD+): Verify recommendations against `constraints_used` environment
4. **Dynamic Expansion** (THOROUGH only): Dispatch `audit-reviewer` agent for gap detection and expansion

**Auto-escalation** (upward only):
- 2+ agents with confidence < 0.50 → LIGHT→STANDARD
- Unexpected cross-system constraint → STANDARD→THOROUGH
- Security keywords in agent output → immediate THOROUGH

### Phase 3: Constraint Resolution

> **Resource**: Read [resources/constraint-propagation.md](./resources/constraint-propagation.md) when entering this phase.

1. Collect all constraint declarations from agents
2. Run `scripts/resolve-constraints.sh` to detect conflicts
3. If no conflicts: merge constraints into unified set
4. If conflicts detected:
   - For intra-system conflicts: orchestrator resolves using domain priority rules
   - For cross-system conflicts: escalate to synthesizer (Phase 4)
5. Store resolved constraints in `~/.claude/cache/engineering-workflow/constraints.json`

### Phase 3.5: Contract Enforcement Gate

> **Resource**: Reuse [resources/analysis-audit-protocol.md](./resources/analysis-audit-protocol.md) (already loaded at Phase 2.5).

STANDARD+ tier only. Validates orchestrator output contracts before synthesis.

**Steps**:
1. **Schema Contract Validation** (STANDARD+): Run `scripts/audit-analysis.sh orchestrator` per orchestrator output
   - Validates required fields (`system`, `status`, `guidance`, `recommendations`, etc.)
   - Auto-fills defaults for non-critical missing fields with warnings
2. **Priority Consistency Check** (THOROUGH only): Verify intra-system conflict resolutions follow `priority-matrix.md`
3. **Constraint Forwarding Completeness** (THOROUGH only): Verify cross-system `impacts` are forwarded to `unresolved_constraints`

### Phase 4: Synthesis (Cross-System Only)

Only activated for Pattern 3 (cross-system) queries.

1. Read `agents/synthesizer.md`
2. Pass all orchestrator outputs + resolved/conflicting constraints
3. Synthesizer produces:
   - Unified recommendation that respects all system constraints
   - Explicit documentation of cross-system trade-offs
   - Implementation priority ordering
   - Risk assessment for constraint violations

### Phase 4.5: Synthesis Validation Gate

> **Resource**: Reuse [resources/analysis-audit-protocol.md](./resources/analysis-audit-protocol.md) (already loaded at Phase 2.5).

THOROUGH tier, cross-system pattern only. Validates synthesis output integrity.

**Steps**:
1. **Coverage Check**: Run `scripts/audit-analysis.sh synthesis` — verify all `systems_analyzed` are reflected in `unified_recommendation`
2. **Ordering Validation**: Verify `implementation_order.depends_on` references valid phases (topological sort consistency)
3. **Risk-Rollback Completeness**: Verify `risk: "high"` phases have `rollback` strategies defined
4. **Confidence Floor**: If `confidence_assessment.overall` is `"low"`, add explicit caveat to output

### Phase 5: Output Formatting

1. Run `scripts/format-output.sh` to structure the final output
2. Output format:

```markdown
## Engineering Analysis: {query summary}

### Classification
- Pattern: {single|multi|cross}
- Systems: {DB, BE, ...}
- Domains: {A, C, ...}
- Depth: {shallow|deep}

### Analysis
{per-domain analysis sections}

### Recommendation
{unified recommendation}

### Constraints
{resolved constraint set}

### Trade-offs
| Option | Pros | Cons | Recommended When |
|--------|------|------|-----------------|

### Implementation Priority
1. {highest priority action}
2. {next action}
...

### Risk Assessment
| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
```

---

## Execution Modes

| Mode | Input Example | Behavior |
|------|---------------|----------|
| **Query** (default) | `"Should I use B-tree or LSM for writes?"` | Full pipeline: Classify → Dispatch → Execute → Resolve → Format |
| **Analyze** | `analyze: "our current sharding strategy"` | Deep analysis without recommendation |
| **Compare** | `compare: "PostgreSQL vs CockroachDB for multi-tenant"` | Structured comparison with decision matrix |
| **Recommend** | `recommend: "caching strategy for read-heavy API"` | Recommendation-focused with implementation steps |
| **Shallow** | `"index design" --depth shallow` | Quick analysis, single agent, ~3K tokens |
| **Deep** | `"index design" --depth deep` | Exhaustive analysis, all relevant agents, full references |

### Depth Modes

| Depth | Agent Count | Reference Loading | Token Budget | Use Case |
|-------|-------------|-------------------|--------------|----------|
| **shallow** | 1 (primary domain only) | Agent .md only, no extra references | ~3K | Quick guidance, confirmation checks |
| **deep** (default) | All relevant domains | Agent .md + reference excerpts via Read | ~6K-14K | Architecture decisions, design reviews |

---

## Resource Loading Instructions

Resources are loaded on-demand per phase. Never pre-load all resources.

| Phase | Resource to Load | Trigger |
|-------|-----------------|---------|
| Phase 0 | `resources/routing-protocol.md` | Always at Phase 0 entry |
| Phase 1 | `resources/orchestration-protocol.md` | Always at Phase 1 entry |
| Phase 1 (DB) | `resources/db-orchestration-protocol.md` | When DB system detected |
| Phase 1 (BE) | `resources/be-orchestration-protocol.md` | When BE system detected |
| Phase 2.5 | `resources/analysis-audit-protocol.md` | Always at Phase 2.5 entry (reused in 3.5, 4.5) |
| Phase 3 | `resources/constraint-propagation.md` | Always at Phase 3 entry |
| Phase 3 | `resources/priority-matrix.md` | When conflicts detected (reused in Phase 4) |
| Phase 4 | `resources/synthesis-protocol.md` | Cross-system pattern only |
| Any | `resources/error-playbook.md` | On error occurrence |

**Agent definitions** (loaded by orchestrators during Phase 2):
- Orchestrator `.md` files: loaded by Gateway Router in Phase 1
- Micro agent `.md` files: loaded by orchestrators in Phase 2
- `agents/synthesizer.md`: loaded by Gateway Router in Phase 4 (cross-system only)

**Reference excerpts** (loaded by agents during Phase 2):
- Agents may use `Read` with `offset/limit` to load relevant sections from large reference files
- Follow the large file loading rules: <=200 lines full read, 201-500 lines offset/limit, >500 lines Grep then Read

---

## Constraint Propagation

Constraints are the mechanism by which agents communicate their requirements and limitations
to each other. Each agent declares constraints in its output; these flow upward through
orchestrators and are resolved before final synthesis.

### Constraint Schema

```json
{
  "source_agent": "db/a1-engine-selector",
  "constraint_type": "requires | recommends | prohibits | conflicts_with",
  "target_domain": "C",
  "description": "LSM-tree selection requires sorted string table schema layout",
  "priority": "hard | soft",
  "evidence": "Write amplification increases 3x without sorted key design"
}
```

### Constraint Flow

```
Agent A declares constraint → Orchestrator collects
Agent B declares constraint → Orchestrator collects
                                    ↓
                          Orchestrator merges
                          (intra-system resolution)
                                    ↓
                          Gateway Router collects
                          orchestrator outputs
                                    ↓
                    Synthesizer merges (cross-system)
                                    ↓
                        Resolved constraint set
                                    ↓
                    ~/.claude/cache/engineering-workflow/constraints.json
```

### Storage

Constraints are persisted at `~/.claude/cache/engineering-workflow/constraints.json` with
session lifecycle management:
- **Create**: New constraint set initialized per query
- **Update**: Agents append constraints during execution
- **Resolve**: Conflicts detected and resolved in Phase 3/4
- **Archive**: Completed constraint sets archived with timestamp

Details: [resources/constraint-propagation.md](./resources/constraint-propagation.md)

---

## Token Budget Guidelines

Token budgets are guidelines, not hard limits. Exceeding the budget triggers reference excerpt
truncation, not query failure.

| Pattern | Agents | Budget | Audit | Total |
|---------|--------|--------|-------|-------|
| **Shallow** | 1 | ~3.5K | +0.3K (LIGHT) | ~3.8K |
| **Analysis only** | 1-4 | ~6K | +1.5K (STANDARD) | ~7.5K |
| **Implementation guide** | 3-6 | ~8K | +1.5K (STANDARD) | ~9.5K |
| **Test generation** | 3-5 | ~10K | +1.5K (STANDARD) | ~11.5K |
| **Full pipeline** | 6-10 | ~12K | +1.5K (STANDARD) | ~13.5K |
| **Cross-system** | 3-6 | ~15K | +3.5K (THOROUGH) | ~18.5K |
| **Cross-system (pruning)** | 3-6 | ~10K | +3.5K (THOROUGH) | ~13.5K |

> **Note**: Budgets include ~20% contingency for complex queries requiring additional
> reference loading. Actual token usage is typically 10-20% below budget for standard queries.

**Budget guidelines** (informational, not enforced by scripts):
1. Orchestrators should prefer offset/limit reference loading over full-file reads
2. At high context pressure (>80%): truncate reference excerpts to essential sections only
3. At critical context pressure (>90%): skip remaining low-priority reference loading
4. Never sacrifice constraint resolution for token savings

---

## Error Handling

> **Resource**: Read [resources/error-playbook.md](./resources/error-playbook.md) on error occurrence.

### Error Categories

| Category | Example | Response |
|----------|---------|----------|
| Agent timeout/failure | Agent Task does not return within 60s | Fallback to general guidance from orchestrator |
| Constraint conflict | Two agents impose contradictory requirements | Escalate to synthesizer with both positions |
| Missing reference data | Referenced document or section not found | Degrade gracefully; note data gap in output |
| Unknown domain | Query does not match any routing keywords | Return routing suggestions with related domains |
| Token budget exceeded | Cumulative tokens exceed budget guideline | Truncate reference excerpts; preserve agent analysis |
| Cross-system failure | One orchestrator fails in cross-system query | Return partial results from successful orchestrators with warning |
| Classification ambiguity | confidence < 0.50 after LLM classification | Ask user for domain clarification |

### Escalation Protocol

```
1. Agent fails       → Orchestrator provides fallback analysis
2. Orchestrator fails → Gateway Router provides high-level guidance
3. Multiple failures  → Report partial results + clear error summary to user
4. Total failure      → Return classification result + suggest manual domain selection
```

---

## Context Health Protocol

Long sessions with multiple queries accumulate context. Monitor and manage proactively.

### Thresholds

| Usage | Level | Response |
|-------|-------|----------|
| **70%** | WARNING | Minimize reference loading; rely on agent expertise |
| **80%** | RECOMMEND | Complete current query, then suggest /compact |
| **85%** | CRITICAL | Truncate all non-essential context; complete with minimal references |

### Recovery After /compact

```
1. /compact executed → context summarized
2. Check for classification result in context
3. IF not found AND mid-query:
   - Re-run classify-query.sh (fast, deterministic)
   - Re-read only the orchestrator .md needed for current phase
4. Resume from current phase
```

---

## Status Display Protocol

Display current state at each phase entry.

### Format

```
[engineering-workflow] Phase: {phase} | Pattern: {pattern} | Systems: {systems} | Budget: {used}/{total}K
```

### Examples

```
[engineering-workflow] Phase: Classification | Pattern: pending | Systems: pending
[engineering-workflow] Phase: Orchestrator Dispatch | Pattern: multi-domain | Systems: DB | Budget: 1.2/10K
[engineering-workflow] Phase: Agent Execution | Pattern: cross-system | Systems: DB,BE,SE | Budget: 5.8/14K
[engineering-workflow] Phase: Synthesis | Pattern: cross-system | Systems: DB,BE,SE | Budget: 11.2/14K
[engineering-workflow] Phase: Output | Pattern: single-domain | Systems: DB | Budget: 4.1/6K
```

---

## Session Wisdom Protocol

### Storage

```
~/.claude/cache/engineering-workflow/
├── constraints.json          # Current session constraints
├── session-history.jsonl     # Past query classifications + outcomes
└── pattern-cache.json        # Learned routing patterns
```

### Cross-Session Learning

1. After each query completion, append classification + outcome to `session-history.jsonl`
2. If the same query pattern appears 3+ times, cache the routing decision in `pattern-cache.json`
3. On next similar query, use cached routing for instant classification (confidence: 1.0)

---

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `classify-query.sh` | Keyword-based query classification | `./classify-query.sh "$QUERY"` |
| `resolve-constraints.sh` | Constraint conflict detection and resolution | `./resolve-constraints.sh [constraints.json]` |
| `format-output.sh` | Structure final output into standard format | `./format-output.sh [results.json]` |
| `validate-agent-output.sh` | Agent output JSON schema + quality validation | `./validate-agent-output.sh <agent-type> [file]` |
| `audit-analysis.sh` | Deterministic audit checks (confidence, schema, synthesis) | `./audit-analysis.sh <mode> [input]` |

**Script requirements**:
- Required CLI: `bash 3.2+`, `jq`, `grep`, `awk`, `sed`
- Environment: Unix-like (Linux, macOS) -- Windows requires WSL/Git Bash

---

## Agents

### Orchestrators (Tier 2)

| Agent | Purpose | Model |
|-------|---------|-------|
| [db-orchestrator](./agents/db-orchestrator.md) | Database system orchestration | sonnet |
| [be-orchestrator](./agents/be-orchestrator.md) | Backend system orchestration | sonnet |
| [if-orchestrator](./agents/if-orchestrator.md) | Infrastructure system orchestration (stub) | haiku |
| [se-orchestrator](./agents/se-orchestrator.md) | Security system orchestration (stub) | haiku |
| [synthesizer](./agents/synthesizer.md) | Cross-system synthesis and constraint resolution | sonnet |
| [audit-reviewer](./agents/audit-reviewer.md) | Analysis quality audit (THOROUGH tier only) | sonnet |

### Micro Agents (Tier 3) -- DB (6 Domains, 17 Agents)

| Agent | Domain | Model |
|-------|--------|-------|
| [a1-engine-selector](./agents/db/a1-engine-selector.md) | A: Storage Engine | sonnet |
| [a2-compaction-strategist](./agents/db/a2-compaction-strategist.md) | A: Storage Engine | haiku |
| [b1-index-architect](./agents/db/b1-index-architect.md) | B: Index & Query Plan | sonnet |
| [b2-join-optimizer](./agents/db/b2-join-optimizer.md) | B: Index & Query Plan | sonnet |
| [b3-query-plan-analyst](./agents/db/b3-query-plan-analyst.md) | B: Index & Query Plan | sonnet |
| [c1-isolation-advisor](./agents/db/c1-isolation-advisor.md) | C: Concurrency & Locking | sonnet |
| [c2-mvcc-specialist](./agents/db/c2-mvcc-specialist.md) | C: Concurrency & Locking | sonnet |
| [c3-lock-designer](./agents/db/c3-lock-designer.md) | C: Concurrency & Locking | haiku |
| [d1-schema-expert](./agents/db/d1-schema-expert.md) | D: Schema & Normalization | sonnet |
| [d2-document-modeler](./agents/db/d2-document-modeler.md) | D: Schema & Normalization | sonnet |
| [d3-access-pattern-modeler](./agents/db/d3-access-pattern-modeler.md) | D: Schema & Normalization | sonnet |
| [e1-page-optimizer](./agents/db/e1-page-optimizer.md) | E: I/O & Buffer Management | sonnet |
| [e2-wal-engineer](./agents/db/e2-wal-engineer.md) | E: I/O & Buffer Management | sonnet |
| [e3-buffer-tuner](./agents/db/e3-buffer-tuner.md) | E: I/O & Buffer Management | haiku |
| [f1-replication-designer](./agents/db/f1-replication-designer.md) | F: Distributed & Replication | sonnet |
| [f2-consistency-selector](./agents/db/f2-consistency-selector.md) | F: Distributed & Replication | sonnet |
| [f3-sharding-architect](./agents/db/f3-sharding-architect.md) | F: Distributed & Replication | sonnet |

### Micro Agents (Tier 3) -- BE (4 Clusters, 18 Agents)

| Agent | Cluster | Sub-Domain | Model |
|-------|---------|-----------|-------|
| [s1-dependency-auditor](./agents/be/s1-dependency-auditor.md) | S: Structure | Dependency Rule Audit | sonnet |
| [s2-di-pattern-selector](./agents/be/s2-di-pattern-selector.md) | S: Structure | DI Pattern Selection | sonnet |
| [s3-architecture-advisor](./agents/be/s3-architecture-advisor.md) | S: Structure | Architecture Style Advisory | sonnet |
| [s4-fitness-engineer](./agents/be/s4-fitness-engineer.md) | S: Structure | Fitness Function Engineering | sonnet |
| [s5-convention-verifier](./agents/be/s5-convention-verifier.md) | S: Structure | Code Convention Verification | sonnet |
| [b1-context-classifier](./agents/be/b1-context-classifier.md) | B: Boundary | Context Relationship Classification | sonnet |
| [b2-acl-designer](./agents/be/b2-acl-designer.md) | B: Boundary | ACL Design | sonnet |
| [b3-event-architect](./agents/be/b3-event-architect.md) | B: Boundary | Event Integration Architecture | sonnet |
| [b4-saga-coordinator](./agents/be/b4-saga-coordinator.md) | B: Boundary | Saga Coordination | sonnet |
| [b5-implementation-guide](./agents/be/b5-implementation-guide.md) | B: Boundary | Implementation Pattern Guide | sonnet |
| [r1-bulkhead-architect](./agents/be/r1-bulkhead-architect.md) | R: Resilience | Bulkhead Architecture | sonnet |
| [r2-cb-configurator](./agents/be/r2-cb-configurator.md) | R: Resilience | Circuit Breaker Configuration | sonnet |
| [r3-retry-strategist](./agents/be/r3-retry-strategist.md) | R: Resilience | Retry/Timeout Strategy | sonnet |
| [r4-observability-designer](./agents/be/r4-observability-designer.md) | R: Resilience | Observability Design | sonnet |
| [t1-test-guard](./agents/be/t1-test-guard.md) | T: Test | Test Architecture Guard | sonnet |
| [t2-test-strategist](./agents/be/t2-test-strategist.md) | T: Test | Test Technique Selection | sonnet |
| [t3-test-generator](./agents/be/t3-test-generator.md) | T: Test | Test Code Generation | sonnet |
| [t4-quality-assessor](./agents/be/t4-quality-assessor.md) | T: Test | Test Quality Assessment | sonnet |

---

## Resources (On-demand)

| Document | Purpose |
|----------|---------|
| [routing-protocol.md](./resources/routing-protocol.md) | Query classification algorithm and domain detection matrix |
| [orchestration-protocol.md](./resources/orchestration-protocol.md) | Agent invocation procedure and Task prompt construction |
| [constraint-propagation.md](./resources/constraint-propagation.md) | Constraint flow, merge logic, and conflict resolution |
| [be-orchestration-protocol.md](./resources/be-orchestration-protocol.md) | BE 4-cluster agent selection, chain rules, and dispatch protocol |
| [error-playbook.md](./resources/error-playbook.md) | Error handling procedures and fallback strategies |
| [analysis-audit-protocol.md](./resources/analysis-audit-protocol.md) | Analysis Quality Gate, Contract Enforcement, Synthesis Validation |
| [db-orchestration-protocol.md](./resources/db-orchestration-protocol.md) | DB agent selection matrix, dispatch protocol, and result merge algorithm |
| [priority-matrix.md](./resources/priority-matrix.md) | Universal priority hierarchy for conflict resolution across all systems |
| [synthesis-protocol.md](./resources/synthesis-protocol.md) | Cross-system synthesis procedure and dependency graph construction |

### Scripts

| Script | Purpose |
|--------|---------|
| [classify-query.sh](./scripts/classify-query.sh) | Deterministic keyword-based query classification (fast-path) |
| [resolve-constraints.sh](./scripts/resolve-constraints.sh) | Constraint conflict detection and auto-resolution |
| [validate-agent-output.sh](./scripts/validate-agent-output.sh) | Agent output JSON schema + quality indicator validation |
| [audit-analysis.sh](./scripts/audit-analysis.sh) | Deterministic audit checks (confidence, schema, synthesis, tier) |
| [format-output.sh](./scripts/format-output.sh) | Output formatting for display |
| [_common.sh](./scripts/_common.sh) | Shared utilities — imported by all other scripts (not called directly) |

### References (Static) — BE

| Document | Cluster | Purpose |
|----------|---------|---------|
| [cluster-s-structure.md](./references/be/cluster-s-structure.md) | S | Hexagonal architecture, dependency rules, DI patterns |
| [cluster-b-boundary-context.md](./references/be/cluster-b-boundary-context.md) | B | Context mapping, ACL, conformist patterns |
| [cluster-b-event-saga.md](./references/be/cluster-b-event-saga.md) | B | Event architecture, saga coordination |
| [cluster-r-config.md](./references/be/cluster-r-config.md) | R | Bulkhead, circuit breaker, retry configuration |
| [cluster-r-observability.md](./references/be/cluster-r-observability.md) | R | Monitoring, tracing, alerting patterns |
| [cluster-t-testing.md](./references/be/cluster-t-testing.md) | T | Test architecture, test guard rules |
| [kotlin-spring-idioms.md](./references/be/kotlin-spring-idioms.md) | S | Kotlin code style, Spring DI, naming conventions |
| [jpa-data-patterns.md](./references/be/jpa-data-patterns.md) | S | Entity-Model separation, JPA, repository, Gradle |
| [test-techniques-catalog.md](./references/be/test-techniques-catalog.md) | T | 7 testing technique catalogs with framework guides |
| [test-generation-patterns.md](./references/be/test-generation-patterns.md) | T | Focal context injection, type-driven test generation |
| [test-quality-validation.md](./references/be/test-quality-validation.md) | T | 5-stage validation pipeline, coverage, mutation |

### References (Static) — DB

| Document | Domain | Purpose |
|----------|--------|---------|
| [domain-a-engine-selection.md](./references/db/domain-a-engine-selection.md) | A | Storage engine comparison (B-Tree vs LSM, InnoDB vs RocksDB) |
| [domain-a-compaction.md](./references/db/domain-a-compaction.md) | A | LSM compaction strategies and tuning |
| [domain-b-index-design.md](./references/db/domain-b-index-design.md) | B | Index design principles, composite indexes, cardinality |
| [domain-b-join-optimization.md](./references/db/domain-b-join-optimization.md) | B | Join algorithms (nested loop, hash, merge) |
| [domain-b-query-plan.md](./references/db/domain-b-query-plan.md) | B | Execution plan analysis (EXPLAIN output) |
| [domain-c-isolation.md](./references/db/domain-c-isolation.md) | C | Isolation level selection and trade-offs |
| [domain-c-mvcc.md](./references/db/domain-c-mvcc.md) | C | MVCC implementations and version management |
| [domain-c-locking.md](./references/db/domain-c-locking.md) | C | Lock types, deadlock detection, gap locking |
| [domain-d-normalization.md](./references/db/domain-d-normalization.md) | D | Normal forms, functional dependencies, denormalization |
| [domain-d-document-modeling.md](./references/db/domain-d-document-modeling.md) | D | Document DB schema design (embed vs reference) |
| [domain-d-access-patterns.md](./references/db/domain-d-access-patterns.md) | D | Access pattern analysis and hot path optimization |
| [domain-e-page-optimization.md](./references/db/domain-e-page-optimization.md) | E | Page structure, fill factor, fragmentation |
| [domain-e-wal.md](./references/db/domain-e-wal.md) | E | Write-ahead logging, checkpoints, durability |
| [domain-e-buffer-tuning.md](./references/db/domain-e-buffer-tuning.md) | E | Buffer pool sizing, eviction, cache hit optimization |
| [domain-f-replication.md](./references/db/domain-f-replication.md) | F | Replication topologies and failover design |
| [domain-f-consistency.md](./references/db/domain-f-consistency.md) | F | CAP/PACELC, consistency models, boundary design |
| [domain-f-sharding.md](./references/db/domain-f-sharding.md) | F | Shard key selection, rebalancing, routing |
