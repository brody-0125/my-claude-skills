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

1. **Constraint-first synthesis**: Agents declare constraints; conflicts are detected and resolved before output
2. **Deterministic fast-path**: Use `classify-query.sh` for unambiguous queries; reserve LLM classification for edge cases
3. **Graceful degradation**: If an agent fails or times out, return partial results with clear warnings

---

## Routing Table

### System Detection

| System | Keywords | Orchestrator |
|--------|----------|--------------|
| **DB** | database, storage engine, index, query optimization, schema, replication, sharding, partition, consistency model, isolation level, MVCC, WAL, B-tree, LSM, vacuum, ACID, DynamoDB, RCU, WCU, hot partition, adaptive capacity, throttling | `agents/db-orchestrator.md` |
| **BE** | backend, API design, service layer, concurrency, thread pool, connection pool, caching strategy, microservice, event-driven, CQRS, saga, domain model | `agents/be-orchestrator.md` |
| **IF** | infrastructure, deployment, container, kubernetes, CI/CD, load balancer, CDN, monitoring, observability, scaling, network topology, DNS, TLS | `agents/if-orchestrator.md` |
| **SE** | security, authentication, authorization, encryption, key management, RBAC, ABAC, OAuth, JWT, zero-trust, penetration, vulnerability, compliance | `agents/se-orchestrator.md` |

### SE Sub-Domain Detection (6 Clusters: A/Z/E/N/C/V)

| Cluster | Sub-Domain | Code | Keywords | Agent |
|---------|------------|------|----------|-------|
| **A** Authentication | AuthN Flow Design | A1 | authentication, OAuth2, OIDC, SAML, SSO, login flow, protocol selection | `agents/se/a1-authn-flow-designer.md` |
| **A** Authentication | Token Strategy | A2 | JWT, refresh token, access token, token rotation, token storage, claims | `agents/se/a2-token-strategist.md` |
| **A** Authentication | Session Architecture | A3 | session management, MFA, SSO federation, stateless, session fixation | `agents/se/a3-session-architect.md` |
| **A** Authentication | Credential Management | A4 | bcrypt, argon2, passkey, WebAuthn, passwordless, credential rotation | `agents/se/a4-credential-manager.md` |
| **Z** Authorization | Access Model Selection | Z1 | RBAC, ABAC, ReBAC, access control model, multi-tenant, permission model | `agents/se/z1-access-model-selector.md` |
| **Z** Authorization | Policy Design | Z2 | OPA, Cedar, Casbin, policy engine, policy rule, policy test | `agents/se/z2-policy-designer.md` |
| **Z** Authorization | Permission Audit | Z3 | least privilege, over-privilege, permission matrix, role explosion | `agents/se/z3-permission-auditor.md` |
| **Z** Authorization | Scope Architecture | Z4 | OAuth scope, API permission, dynamic scope, consent, token-permission | `agents/se/z4-scope-architect.md` |
| **E** Encryption | Encryption Strategy | E1 | encryption at-rest, in-transit, field-level, AES-256, ChaCha20 | `agents/se/e1-encryption-advisor.md` |
| **E** Encryption | Key Lifecycle | E2 | key rotation, HSM, Vault, KMS, key escrow, key distribution | `agents/se/e2-key-lifecycle-planner.md` |
| **E** Encryption | TLS Configuration | E3 | TLS, mTLS, cipher suite, certificate chain, OCSP, certificate pinning | `agents/se/e3-tls-configurator.md` |
| **E** Encryption | Secret Management | E4 | HashiCorp Vault, AWS Secrets Manager, secret rotation, dynamic secret | `agents/se/e4-secret-manager.md` |
| **N** Network Security | Header Hardening | N1 | CORS, CSP, HSTS, X-Frame-Options, Referrer-Policy, security headers | `agents/se/n1-header-hardener.md` |
| **N** Network Security | WAF/Rate-Limiting | N2 | WAF, rate limiting, IP filtering, DDoS, geo-blocking, ModSecurity | `agents/se/n2-waf-rule-designer.md` |
| **N** Network Security | API Gateway Security | N3 | API gateway, auth delegation, request validation, throttling, API key | `agents/se/n3-api-gateway-security.md` |
| **N** Network Security | Input Sanitization | N4 | SQL injection, XSS, path traversal, content-type validation, sanitization | `agents/se/n4-input-sanitizer.md` |
| **C** Compliance | Compliance Mapping | C1 | SOC2, ISO27001, GDPR, PCI-DSS, compliance framework, cross-mapping | `agents/se/c1-compliance-mapper.md` |
| **C** Compliance | Audit Trail Design | C2 | audit logging, event schema, append-only, WORM, tamper detection | `agents/se/c2-audit-trail-designer.md` |
| **C** Compliance | Zero-Trust Planning | C3 | zero-trust, microsegmentation, device trust, BeyondCorp, continuous verification | `agents/se/c3-zero-trust-planner.md` |
| **C** Compliance | Privacy Engineering | C4 | GDPR data subject, consent management, PII, data masking, DPIA | `agents/se/c4-privacy-engineer.md` |
| **V** Vulnerability | Threat Modeling | V1 | STRIDE, PASTA, attack tree, threat scenario, attack surface | `agents/se/v1-threat-modeler.md` |
| **V** Vulnerability | OWASP Audit | V2 | OWASP Top 10, injection, XSS, auth flaw, SSRF, deserialization | `agents/se/v2-owasp-auditor.md` |
| **V** Vulnerability | Pentest Strategy | V3 | penetration test, black-box, white-box, Burp, ZAP, Nuclei | `agents/se/v3-pentest-strategist.md` |
| **V** Vulnerability | Supply Chain Audit | V4 | SCA, SBOM, license compliance, CVE, dependency vulnerability, Sigstore | `agents/se/v4-supply-chain-auditor.md` |

### DB Sub-Domain Detection (A-F)

| Sub-Domain | Code | Keywords | Agents |
|------------|------|----------|--------|
| Storage Engine | A | storage engine, B-tree, LSM-tree, page layout, WAL, buffer pool, compaction, write amplification | `agents/db/a1-engine-selector.md`, `agents/db/a2-compaction-strategist.md` |
| Index & Query Plan | B | query plan, explain analyze, index scan, seq scan, join strategy, cost estimation, query rewrite, statistics | `agents/db/b1-index-architect.md`, `agents/db/b2-join-optimizer.md`, `agents/db/b3-query-plan-analyst.md` |
| Concurrency & Locking | C | concurrency, isolation level, MVCC, locking, deadlock, optimistic, pessimistic, serializable, phantom read | `agents/db/c1-isolation-advisor.md`, `agents/db/c2-mvcc-specialist.md`, `agents/db/c3-lock-designer.md` |
| Schema & Normalization | D | schema design, normalization, denormalization, document model, embedding, referencing, access pattern | `agents/db/d1-schema-expert.md`, `agents/db/d2-document-modeler.md`, `agents/db/d3-access-pattern-modeler.md` |
| I/O & Buffer Management | E | page, buffer pool, WAL, write-ahead log, checkpoint, dirty page, flush, I/O optimization | `agents/db/e1-page-optimizer.md`, `agents/db/e2-wal-engineer.md`, `agents/db/e3-buffer-tuner.md` |
| Distributed & Replication | F | replication, failover, consensus, raft, paxos, sharding, partition, consistency, CAP theorem, dynamodb, rcu, wcu, hot partition, adaptive capacity, throttling, provisioned throughput, on-demand, TPS | `agents/db/f1-replication-designer.md`, `agents/db/f2-consistency-selector.md`, `agents/db/f3-sharding-architect.md`, `agents/db/f4-dynamodb-throughput-optimizer.md` |

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

Three execution patterns exist: Single-Domain (1 agent), Multi-Domain (2-3 agents, parallel dispatch),
and Cross-System (multiple orchestrators + synthesizer).

For detailed flow diagrams and examples, see [resources/orchestration-protocol.md § Pattern Examples](./resources/orchestration-protocol.md).

---

## Phase Flow

### Pre-Flight Check (before Phase 0)

Run before any phase execution to ensure clean session state and detect reusable context.

1. **Dependency check**: Verify `jq` is available (`command -v jq`)
2. **Interrupted session detection**: Read `~/.claude/cache/engineering-workflow/progress.json`
   - If `status == "in_progress"`: previous session was interrupted
   - Archive the interrupted progress file and notify: "Previous session interrupted at phase {phase}. Starting fresh."
3. **Session summary reuse**: Read `~/.claude/cache/engineering-workflow/session-summary.json`
   - If recent (< 30 min) and query is similar: display "Recent analysis available for reuse" with summary
   - Skip re-classification if the same query signature matches
4. **Initialize progress**: Write `progress.json` with `{phase: "pre-flight", status: "in_progress"}`
5. **Run cleanup**: Execute session cleanup (trim history, evict stale cache)

```
[engineering-workflow] Pre-Flight: deps=OK | prev_session={none|interrupted} | summary={available|none}
```

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
6. Run `scripts/enforce-budget.sh <pattern> orchestrator-dispatch <output>` to verify token budget before proceeding

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

**BE Test Pipeline Status Display** (when T2-T3-T4 loop is active):
```
[engineering-workflow] Phase: Test Pipeline | Loop: {n}/{max} | Coverage: {pct}% (target: {target}%)
```

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
0. **Budget Check**: Run `scripts/enforce-budget.sh <pattern> quality-gate <output>` to verify token budget before audit
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

1. Run `scripts/enforce-budget.sh <pattern> synthesis <output>` to verify token budget before synthesis
2. Read `agents/synthesizer.md`
3. Pass all orchestrator outputs + resolved/conflicting constraints
4. Synthesizer produces:
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

Depth flag: `--depth shallow` (1 agent, ~3K) or `--depth deep` (all relevant agents, ~6-14K, default).

---

## Resource Loading Instructions

Resources are loaded on-demand per phase. MUST NOT pre-load all resources.

| Phase | Resource to Load | Trigger |
|-------|-----------------|---------|
| Phase 0 | `resources/routing-protocol.md` | Always at Phase 0 entry |
| Phase 1 | `resources/orchestration-protocol.md` | Always at Phase 1 entry |
| Phase 1 (DB) | `resources/db-orchestration-protocol.md` | When DB system detected |
| Phase 1 (BE) | `resources/be-orchestration-protocol.md` | When BE system detected |
| Phase 1 (SE) | `resources/se-orchestration-protocol.md` | When SE system detected |
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

Agents declare constraints (requires | recommends | prohibits | conflicts_with) in their output.
Constraints flow upward through orchestrators → synthesizer for resolution.
Hard constraints MUST be respected; soft constraints may be overridden with justification.

Schema, flow diagrams, and storage: [resources/constraint-propagation.md](./resources/constraint-propagation.md)

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

**Budget enforcement**: Run `scripts/enforce-budget.sh <pattern> <phase> <output>` at phase transitions.
Exits non-zero if estimated tokens exceed 120% of budget. Patterns: `shallow`, `analysis`, `implementation`, `test`, `full`, `cross-system`, `cross-pruning`.

**Budget guidelines**:
1. Orchestrators MUST use offset/limit reference loading over full-file reads
2. At high context pressure (>80%): truncate reference excerpts to essential sections only
3. At critical context pressure (>90%): skip remaining low-priority reference loading
4. MUST NOT sacrifice constraint resolution for token savings

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
[engineering-workflow] Phase: Agent Execution | Pattern: cross-system | Systems: DB,BE,SE | Budget: 5.8/14K
```

Session pattern caching: `~/.claude/cache/engineering-workflow/` (details in [constraint-propagation.md](./resources/constraint-propagation.md))

---

## Agents

### Orchestrators (Tier 2)

| Agent | Purpose | Model |
|-------|---------|-------|
| [db-orchestrator](./agents/db-orchestrator.md) | Database system orchestration | sonnet |
| [be-orchestrator](./agents/be-orchestrator.md) | Backend system orchestration | sonnet |
| [if-orchestrator](./agents/if-orchestrator.md) | Infrastructure system orchestration (stub) | haiku |
| [se-orchestrator](./agents/se-orchestrator.md) | Security system orchestration | sonnet |
| [synthesizer](./agents/synthesizer.md) | Cross-system synthesis and constraint resolution | sonnet |
| [audit-reviewer](./agents/audit-reviewer.md) | Analysis quality audit (THOROUGH tier only) | sonnet |

### Micro Agents (Tier 3)

- **DB**: 6 domains (A-F), 18 agents — see [db-orchestrator.md](./agents/db-orchestrator.md) § Agent Selection Matrix
- **BE**: 4 clusters (S/B/R/T), 18 agents — see [be-orchestrator.md](./agents/be-orchestrator.md) § Agent Selection Matrix
- **SE**: 6 clusters (A/Z/E/N/C/V), 24 agents — see [se-orchestrator.md](./agents/se-orchestrator.md) § Agent Selection Matrix

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
| [se-orchestration-protocol.md](./resources/se-orchestration-protocol.md) | SE 6-cluster agent selection, 8 chain rules, and security dispatch protocol |
| [priority-matrix.md](./resources/priority-matrix.md) | Universal priority hierarchy for conflict resolution across all systems |
| [synthesis-protocol.md](./resources/synthesis-protocol.md) | Cross-system synthesis procedure and dependency graph construction |

### Scripts

| Script | Purpose |
|--------|---------|
| [classify-query.sh](./scripts/classify-query.sh) | Deterministic keyword-based query classification (fast-path) |
| [resolve-constraints.sh](./scripts/resolve-constraints.sh) | Constraint conflict detection and auto-resolution |
| [validate-agent-output.sh](./scripts/validate-agent-output.sh) | Agent output JSON schema + quality indicator validation |
| [audit-analysis.sh](./scripts/audit-analysis.sh) | Deterministic audit checks (confidence, schema, synthesis, tier) |
| [format-output.sh](./scripts/format-output.sh) | Output formatting for display (supports `--summary` for compact output) |
| [enforce-budget.sh](./scripts/enforce-budget.sh) | Token budget enforcement — exits non-zero if output exceeds 120% of budget |
| [_common.sh](./scripts/_common.sh) | Shared utilities — imported by all other scripts (not called directly) |

### References (Static)

- **DB**: `references/db/` — 18 files covering domains A-F (mapped in [db-orchestrator.md § Load Reference Excerpts](./agents/db-orchestrator.md))
- **BE**: `references/be/` — 11 files covering clusters S/B/R/T (mapped in [be-orchestrator.md § Load Reference Excerpts](./agents/be-orchestrator.md))
- **SE**: `references/se/` — 7 files covering clusters A/Z/E/N/C/V + best practices (mapped in [se-orchestrator.md § Load Reference Excerpts](./agents/se-orchestrator.md))
