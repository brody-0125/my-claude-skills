# BE Orchestration Protocol

> Detailed routing, dispatch, chain execution, and merge protocol for the BE orchestrator and its 18 micro agents across 4 clusters.

## 1. Agent Selection Matrix (Expanded)

### Cluster S: Structure

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| dependency, import direction, layer violation | s1-dependency-auditor | Detects inward/outward dependency violations |
| dependency + fitness function | s1 + s4-fitness-engineer | Violation detection + automated rule |
| DI, injection, bean, scope, qualifier, provider | s2-di-pattern-selector | DI pattern selection |
| architecture, hexagonal, module structure, package | s3-architecture-advisor | Architecture style guidance |
| ArchUnit, Konsist, fitness function, automated check | s4-fitness-engineer | Fitness function implementation |
| convention, code style, naming rule, JPA pattern | s5-convention-verifier | 6-category convention verification |
| entity model, dynamic update, cascade rule | s5-convention-verifier | JPA convention verification |
| layer fix, violation fix (broad) | s1 + s2 + s4 | Chain 4: full violation fix pipeline |

### Cluster B: Boundary

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| bounded context, context mapping, DDD relationship | b1-context-classifier | Context relationship classification |
| external system, integration type, team ownership | b1-context-classifier | External system categorization |
| ACL, anti-corruption layer, translator, port mapping | b2-acl-designer | ACL design and tier selection |
| context classification + ACL design (broad) | b1 + b2 | Classification feeds ACL tier |
| domain event, event schema, event publish, subscribe | b3-event-architect | Event schema and flow design |
| saga, compensation, distributed transaction, step | b4-saga-coordinator | Saga orchestration design |
| saga + ACL + retry (broad) | b4 + b2 + r3 | Chain 3: saga with per-step resilience |
| implementation guide, code pattern, feign client | b5-implementation-guide | ACL/Event/Saga code pattern generation |
| implement ACL, implement event, implement saga | b5-implementation-guide | Concrete implementation patterns |

### Cluster R: Resilience

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| bulkhead, thread pool, isolation, pool size, semaphore | r1-bulkhead-architect | Bulkhead type and sizing |
| circuit breaker, failure rate, half-open, CB config | r2-cb-configurator | Circuit breaker parameterization |
| retry, backoff, timeout, idempotent, exponential | r3-retry-strategist | Retry and timeout strategy |
| resilience (broad), external call protection | r1 + r2 + r3 | Full Resilience Triad |
| metric, alert, dashboard, SLI, SLO, tracing, logging | r4-observability-designer | Observability design |
| observability + resilience | r1 + r2 + r3 + r4 | Full resilience with monitoring |

### Cluster T: Test

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| test, unit test, integration test, test convention | t1-test-guard | Test architecture enforcement |
| naming, byte limit, test name, DisplayName | t1-test-guard | Test name validation |
| Fixture Monkey, fixture, giveMeOne, giveMeBuilder | t1-test-guard | Fixture strategy validation |
| FakeRepository, fake, stub, mock, spyk | t1-test-guard | Test double pattern validation |
| TestContainers, IntegrationTestContext | t1-test-guard | Integration test base verification |
| test strategy, test technique, coverage target | t2-test-strategist | Layer-based technique selection |
| property-based, contract test, test planning | t2-test-strategist | Test technique mapping |
| generate test, test generation, write test | t3-test-generator | Test code generation |
| create test, test code, new test file | t3-test-generator | Test file creation |
| test quality, coverage, mutation testing | t4-quality-assessor | 5-stage validation pipeline |
| gap analysis, quality assessment, kill rate | t4-quality-assessor | Quality measurement and feedback |

## 2. Chain Selection Algorithm

When a query matches multiple chain triggers, apply this algorithm:

```
1. Score each chain: count keyword matches from query against chain trigger keywords
2. If exactly 1 chain scores > 0: execute that chain
3. If 2+ chains score > 0:
   a. Superset check: if Chain X's agent set is a superset of Chain Y's,
      execute Chain X only (subsumes Chain Y)
   b. No superset: merge unique agents from all matched chains
   c. Topological sort merged agents using cross-cluster dependency rules (Section 3)
4. Override: --chain N flag forces single chain execution
```

### Chain Precedence Order (Tiebreaking)

When merge ordering is ambiguous, apply this precedence:

| Priority | Chain | Name | Agents | Rationale |
|----------|-------|------|--------|-----------|
| 1 (highest) | Chain 1 | New External Integration | 11 | Most comprehensive, structural |
| 2 | Chain 3 | Saga Design | 4+ | Complex distributed coordination |
| 3 | Chain 2 | New Domain Event | 3 | Event architecture foundation |
| 4 | Chain 5 | Code Implementation | 4 | Implementation pipeline |
| 5 | Chain 6 | Test Generation | 4 | Test pipeline |
| 6 (lowest) | Chain 4 | Architecture Violation Fix | 3 | Targeted fix, narrow scope |

### Merge Example

Query: "implement a new external integration with tests"
- Chain 1 matches ("new external", "integration")
- Chain 5 matches ("implement")
- Chain 6 matches ("test")
- Chain 1 subsumes Chain 5 (S-3 → B-5 → T-3 → T-1 all covered)
- Chain 6 adds T-2 (before T-3) and T-4 (after T-3)
- Merged pipeline: S-3 → S-1 → S-2 → B-1 → B-2 → R-1 → R-2 → R-3 → R-4 → T-2 → T-3 → T-4 → T-1 → S-4

## 3. Chain Rules

### Chain 1: New External Integration

**Trigger**: Query contains "new external", "new integration", "new dependency", or describes adding a new external system.

**Pipeline**: `S-3 -> S-1 -> S-2 -> B-1 -> B-2 -> R-1 -> R-2 -> R-3 -> R-4 -> T-1 -> S-4`

| Step | Agent | Input | Output |
|------|-------|-------|--------|
| 1 | S-3 architecture-advisor | Query + project structure | Module placement recommendation |
| 2 | S-1 dependency-auditor | S-3 module placement | Dependency direction validation |
| 3 | S-2 di-pattern-selector | S-1 validated structure | DI wiring for new module |
| 4 | B-1 context-classifier | External system details | Context mapping pattern + semantic gap |
| 5 | B-2 acl-designer | B-1 classification + S-2 DI pattern | ACL tier + translator design |
| 6 | R-1 bulkhead-architect | B-2 ACL boundary | Bulkhead type + pool sizing |
| 7 | R-2 cb-configurator | R-1 isolation boundary | Circuit breaker parameters |
| 8 | R-3 retry-strategist | R-2 CB config | Retry/timeout strategy |
| 9 | R-4 observability-designer | R-1+R-2+R-3 resilience config | Metrics, alerts, dashboards |
| 10 | T-1 test-guard | All above results | Test structure for new module |
| 11 | S-4 fitness-engineer | S-1 rules + T-1 test structure | Automated fitness functions |

### Chain 2: New Domain Event

**Trigger**: Query contains "domain event", "new event", "event publish".

**Pipeline**: `B-3 -> S-3 -> T-1`

| Step | Agent | Input | Output |
|------|-------|-------|--------|
| 1 | B-3 event-architect | Event requirements | Event schema + publish/subscribe design |
| 2 | S-3 architecture-advisor | B-3 event design | Module placement for event handler |
| 3 | T-1 test-guard | B-3 schema + S-3 placement | Test structure for event flow |

### Chain 3: Saga Design

**Trigger**: Query contains "saga", "compensation", "distributed transaction".

**Pipeline**: `B-4 -> B-2(per step) -> R-3(per step) -> T-1`

| Step | Agent | Input | Output |
|------|-------|-------|--------|
| 1 | B-4 saga-coordinator | Saga requirements | Step definitions + compensation flow |
| 2 | B-2 acl-designer (repeated) | Per-step external boundary | ACL design per saga step |
| 3 | R-3 retry-strategist (repeated) | Per-step timeout/retry needs | Retry config per saga step |
| 4 | T-1 test-guard | Complete saga design | Saga test scenarios + compensation tests |

### Chain 4: Architecture Violation Fix

**Trigger**: Query contains "violation fix", "dependency fix", "layer fix".

**Pipeline**: `S-1 -> S-2 -> S-4`

| Step | Agent | Input | Output |
|------|-------|-------|--------|
| 1 | S-1 dependency-auditor | Violation details | Violation report with severity + fix |
| 2 | S-2 di-pattern-selector | S-1 fix recommendation | DI rewiring plan |
| 3 | S-4 fitness-engineer | S-1 violations + S-2 DI plan | Fitness function to prevent recurrence |

### Chain 5: Code Implementation

**Trigger**: Query contains "implement", "code generation", "create module", "build feature".

**Pipeline**: `S-3 -> B-5 -> T-3 -> T-1`

| Step | Agent | Input | Output |
|------|-------|-------|--------|
| 1 | S-3 architecture-advisor | Query + project structure | Module placement + architecture style |
| 2 | B-5 implementation-guide | S-3 placement + B-cluster analysis | Code patterns + file structure |
| 3 | T-3 test-generator | B-5 implementation patterns | Test code for new implementation |
| 4 | T-1 test-guard | T-3 generated tests | Test architecture validation |

### Chain 6: Test Generation

**Trigger**: Query contains "generate test", "write test", "test coverage", "test this".

**Pipeline**: `T-2 -> T-3 -> T-4 -> T-1`

| Step | Agent | Input | Output |
|------|-------|-------|--------|
| 1 | T-2 test-strategist | Target classes + project context | Test technique selection + coverage targets |
| 2 | T-3 test-generator | T-2 strategy + focal context | Generated test code |
| 3 | T-4 quality-assessor | T-3 generated tests | Validation results + gap report |
| 4 | T-1 test-guard | T-4 validated tests | Final test architecture check |

Note: T-4 may feed gap reports back to T-3 for iterative improvement (max 3 loops).

## 4. Cross-Cluster Dependency Rules

Dependencies dictate dispatch ordering. Independent clusters run in parallel.

```
S-1 (dependency-auditor) ──affects──▶ S-4 (fitness-engineer)
  Rationale: Detected violations determine which fitness functions
  to create for preventing future regressions.

B-1 (context-classifier) ──affects──▶ B-2 (acl-designer)
  Rationale: Context mapping pattern and semantic gap score
  determine ACL tier and translator complexity.

B-2 (acl-designer) ──affects──▶ R-1+R-2+R-3 (Resilience Triad)
  Rationale: ACL boundary definition determines which external
  calls need bulkheads, circuit breakers, and retry policies.

B-4 (saga-coordinator) ──affects──▶ T-1 (test-guard)
  Rationale: Saga step definitions determine which test scenarios
  and compensation test cases are required.

S-4 (fitness-engineer) ──↔──▶ T-1 (test-guard)
  Rationale: Fitness functions inform test architecture constraints,
  and test structure informs what fitness functions are feasible.
  Bidirectional: dispatch in parallel, cross-reference in merge.

B-2/B-3/B-4 (analysis) ──affects──▶ B-5 (implementation-guide)
  Rationale: ACL/Event/Saga analysis determines which
  implementation code patterns to generate.

T-2 (test-strategist) ──affects──▶ T-3 (test-generator)
  Rationale: Selected test techniques and coverage targets
  determine what test code to generate.

T-3 (test-generator) ──affects──▶ T-4 (quality-assessor)
  Rationale: Generated test code feeds the validation pipeline.

T-4 (quality-assessor) ──feedback──▶ T-3 (test-generator)
  Rationale: Gap reports drive iterative test improvement.

B-5 (implementation-guide) ──affects──▶ T-3 (test-generator)
  Rationale: Implementation patterns determine test targets.

S-5 (convention-verifier) ──affects──▶ T-1 (test-guard)
  Rationale: Convention violations may require test updates.
```

### Dependency Resolution Algorithm

```
1. Build dependency graph from requested clusters and agents
2. Topological sort to determine wave ordering
3. Wave 1: agents with no incoming dependencies among requested set
4. Wave 2: agents that depend on Wave 1 results
5. Wave 3: agents that depend on Wave 2 results
6. Within each wave, dispatch agents in parallel (max 3 concurrent)
7. Bidirectional dependencies (S-4 ↔ T-1): dispatch in same wave, merge with cross-reference
```

Example: Query involves clusters S, B, T with agents S-1, B-1, B-2, T-1
- Wave 1: {S-1, B-1} parallel (no incoming dependencies)
- Wave 2: {B-2} (depends on B-1)
- Wave 3: {T-1} (depends on B-2 if saga-related, otherwise Wave 1)
- S-4 would be Wave 2 if S-1 is in Wave 1

## 5. Reference Excerpt Extraction Procedure

### Cluster-to-Reference Mapping

| Cluster/Agent | Reference Files |
|---------------|----------------|
| S (S1-S4) | `references/be/cluster-s-structure.md` |
| S5 | `references/be/kotlin-spring-idioms.md`, `references/be/jpa-data-patterns.md` |
| B (B1-B4) | `references/be/cluster-b-boundary-context.md`, `references/be/cluster-b-event-saga.md` |
| B5 | `references/be/cluster-b-boundary-context.md`, `references/be/cluster-b-event-saga.md`, `references/be/kotlin-spring-idioms.md` |
| R | `references/be/cluster-r-config.md`, `references/be/cluster-r-observability.md` |
| T1 | `references/be/cluster-t-testing.md` |
| T2 | `references/be/test-techniques-catalog.md` |
| T3 | `references/be/test-generation-patterns.md`, `references/be/test-techniques-catalog.md` |
| T4 | `references/be/test-quality-validation.md` |

### Extraction Steps

1. Determine the relevant section heading from `classification.sub_topics`
2. Read the reference file with offset/limit to find the section:
   - First pass: Read first 50 lines to get table of contents / heading structure
   - Identify line range for relevant section
   - Second pass: Read only that section (typically 50-150 lines)
3. Pass extracted text as `reference_excerpt` in agent input
4. Maximum excerpt size: 200 lines per agent

### Section Mapping

| Sub-topic Pattern | Reference Section |
|-------------------|-------------------|
| dependency, layer, module | cluster-s-structure.md SS Layer Model |
| DI, injection, bean | cluster-s-structure.md SS DI Patterns |
| architecture, hexagonal | cluster-s-structure.md SS Architecture |
| fitness, ArchUnit, Konsist | cluster-s-structure.md SS Fitness Functions |
| context mapping, bounded context | cluster-b-boundary-context.md SS Context Mapping |
| ACL, translator, adapter | cluster-b-boundary-context.md SS ACL Design |
| domain event, event schema | cluster-b-event-saga.md SS Event Architecture |
| saga, compensation | cluster-b-event-saga.md SS Saga Coordination |
| bulkhead, circuit breaker, retry | cluster-r-config.md SS Resilience Configuration |
| metric, alert, SLI, SLO | cluster-r-observability.md SS Observability |
| test, fixture, naming, fake | cluster-t-testing.md SS Test Architecture |
| convention, code style, naming rule | kotlin-spring-idioms.md SS Code Style Rules |
| JPA pattern, entity model, dynamic update | jpa-data-patterns.md SS Entity Best Practices |
| cascade, repository pattern, gradle | jpa-data-patterns.md SS Cascade / Repository / Gradle |
| implementation, feign client, translator | cluster-b-boundary-context.md SS ACL Design + kotlin-spring-idioms.md |
| test strategy, test technique, coverage | test-techniques-catalog.md SS Framework Selection |
| generate test, focal context, type-driven | test-generation-patterns.md SS Test Generation |
| coverage, mutation, validation pipeline | test-quality-validation.md SS Validation Pipeline |

## 6. Parallel Dispatch Rules

### Concurrency Limits

- Maximum parallel agents: 3 (to stay within Task tool limits)
- If more than 3 agents needed in a wave, split into sub-waves of max 3

### Dispatch Protocol

```
1. For each wave:
   a. Construct agent inputs (include upstream_results if available)
   b. Dispatch all agents in wave via parallel Task calls (max 3)
   c. Await all results
   d. Validate each result is valid JSON
   e. If any agent fails, retry once with simplified input
2. Pass wave results to next wave as upstream_results
3. For chain execution, follow the defined step ordering
```

### Timeout Handling

- Per-agent timeout: 60 seconds
- If agent exceeds timeout, mark as `timed_out` and proceed with remaining agents
- Include timeout in output metadata
- Chain execution: if a mid-chain agent times out, skip dependent steps and note gap

### Wave Batching Example

Query triggers Chain 1 (11 agents):
- Wave 1: {S-3} (1 agent)
- Wave 2: {S-1} with S-3 results (1 agent)
- Wave 3: {S-2, B-1} parallel (2 agents, independent)
- Wave 4: {B-2} with B-1 results (1 agent)
- Wave 5: {R-1, R-2, R-3} parallel with B-2 results (3 agents)
- Wave 6: {R-4, T-1} parallel with R-triad results (2 agents)
- Wave 7: {S-4} with S-1 + T-1 results (1 agent)

## 7. Result Merge Algorithm

### Step-by-Step Merge

```
1. Initialize merged_result = { merged_recommendations: [], conflicts: [], cross_notes: [] }
2. For each agent result:
   a. Extract recommendation fields
   b. Add to merged_recommendations[] with source agent and cluster tag
   c. Check for conflicts with existing recommendations
3. For each pair of recommendations across clusters:
   a. If fields overlap and values differ -> add to conflicts[]
   b. If fields overlap and values agree -> merge and note cross-cluster agreement
4. For dependency pairs (S-1->S-4, B-1->B-2, B-2->R-triad, etc.):
   a. Verify downstream agent used upstream constraints
   b. Note constraint propagation in cross_notes
5. Compute aggregate_confidence as weighted average
6. Generate cross_notes from dependency relationships
```

### Conflict Detection Rules

Two recommendations conflict when:
- Same design decision, different approaches (e.g., Decorator vs @Aspect for ACL)
- Mutually exclusive patterns (e.g., saga orchestration vs choreography)
- Resource allocation tension (e.g., thread pool sizing vs overall thread budget)
- Convention contradiction (e.g., test naming style vs readability preference)

## 8. Conflict Resolution Protocol

When agents produce contradictory recommendations, follow this protocol strictly:

### Step 1: Present Both Sides

Format each side with the agent name, recommendation, and rationale:
```
Agent B-2 (acl-designer): Recommends Decorator pattern for ACL translator
  Rationale: Explicit wrapping, each translator is independently testable,
  composition is visible in DI configuration.

Agent S-2 (di-pattern-selector): Recommends @Aspect annotation for cross-cutting
  Rationale: Declarative, less boilerplate, Spring AOP handles proxy creation,
  consistent with other cross-cutting concerns in the project.
```

### Step 2: Enumerate Trade-Offs

| Factor | Decorator | @Aspect |
|--------|-----------|---------|
| Testability | Unit-testable without Spring context | Requires Spring AOP proxy |
| Visibility | Explicit in DI wiring | Implicit via annotation |
| Boilerplate | More code per translator | Less code per translator |
| Consistency | Different from other cross-cutting | Same pattern as auth, logging |
| Flexibility | Compose multiple decorators | Single aspect per concern |

### Step 3: Ask User Preference

Present the trade-off summary and ask:
> "Both approaches are valid. Decorator provides explicit testability; @Aspect provides consistency with existing cross-cutting patterns. Which approach do you prefer for this project?"

### Step 4: NEVER Silently Choose

- Do NOT apply priority rules to resolve design preference conflicts without user input
- Priority rules apply ONLY to correctness/safety conflicts (e.g., missing isolation = MUST fix)
- For design preference conflicts, ALWAYS surface to user
- Record resolution method: `"user_preference"` or `"priority_rule"` (for safety-only)

## 9. Implementation and Test Agent Protocol

### Query Type Routing

| Query Type | Agents | Pipeline |
|-----------|--------|----------|
| Architecture analysis | S1-S4, B1-B4, R1-R4, T1 | Analysis only |
| Convention verification | S5 | S5 reads changed files, reports violations |
| Code implementation | Analysis agents → B5 → S5 | Chain 5: analysis + implementation patterns + verification |
| Test generation | T2 → T3 → T4 → T1 | Chain 6: strategy + generation + validation + guard |
| Code review | S5 + T1 | Convention check + test architecture check |
| Refactoring guidance | S1 → S2 → B5 → S5 | Audit → DI plan → implementation patterns → verification |

### S5 Convention Verifier Trigger

S5 activates after any code-producing agent (B5, T3) completes:
1. Collect changed/generated file list from upstream agent
2. Dispatch S5 with file list and project context
3. S5 reports violations with severity and auto-fix guidance
4. If ERROR violations found: flag for user review before proceeding

### B5 Implementation Guide Trigger

B5 activates when analysis produces actionable implementation constraints:
1. Receive upstream analysis from B1/B2/B3/B4
2. Classify implementation type: ACL / Event / Saga
3. Generate file structure, code patterns, dependency additions
4. Pass output to S5 for convention verification and T3 for test generation

### T2-T3-T4 Test Pipeline

Sequential execution with feedback loop:
1. T2 classifies targets by layer, selects techniques, estimates test count
2. T3 generates test code using focal context + type-driven derivation
3. T4 runs 5-stage validation: compile → execute → coverage → mutation → quality
4. If T4 gap report indicates remaining gaps AND loop count < 3: return to T3
5. T1 performs final test architecture guard check

### Cross-Agent Data Flow

```
B-cluster analysis
  └──▶ B5 implementation patterns
         ├──▶ S5 convention verification
         └──▶ T2 test strategy
                └──▶ T3 test generation
                       └──▶ T4 quality validation
                              └──▶ (loop to T3 if gaps remain)
                                     └──▶ T1 final guard
```
