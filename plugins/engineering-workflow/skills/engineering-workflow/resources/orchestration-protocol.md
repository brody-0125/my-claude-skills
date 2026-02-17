# Orchestration Protocol — Agent Invocation Procedure

> Detailed procedure for Phase 1 (Orchestrator Dispatch) and Phase 2 (Agent Execution).
> Loaded when entering Phase 1: Orchestrator Dispatch.

## Table of Contents

| Section | Line |
|---------|------|
| 1. Overview | ~21 |
| 2. Step 1: Reading Agent Definitions | ~41 |
| 3. Step 2: Constructing Task Prompts | ~122 |
| 4. Step 3: Passing Reference Excerpts | ~231 |
| 5. Step 4: Parallel vs. Sequential Agent Dispatch | ~281 |
| 6. Step 5: Result Collection and Merging | ~338 |
| 7. Step 5.5: Quality Indicators | ~421 |
| 8. Step 6: Token Budget Management | ~460 |
| 9. Cross-System Orchestration | ~499 |
| 10. Phase Transition Context Management | ~569 |
| 11. Pattern Examples | ~635 |

## Overview

This document defines how the Gateway Router invokes orchestrators, how orchestrators invoke
micro agents, and how results are collected, merged, and returned through the tier hierarchy.

```
Gateway Router
  ├─→ reads orchestrator .md
  ├─→ constructs Task prompt
  ├─→ invokes Task (orchestrator)
  │     ├─→ reads agent .md(s)
  │     ├─→ constructs Task prompt(s) for agents
  │     ├─→ invokes Task(s) (agents)
  │     ├─→ collects agent results
  │     └─→ merges results + resolves intra-system constraints
  └─→ collects orchestrator output(s)
```

---

## Step 1: Reading Agent Definitions

### Orchestrator Definitions

Location: `agents/{system}-orchestrator.md`

```
agents/
├── db-orchestrator.md
├── be-orchestrator.md
├── if-orchestrator.md
├── se-orchestrator.md
└── synthesizer.md
```

**Reading procedure**:
1. Identify required orchestrator(s) from Phase 0 classification
2. Read each orchestrator .md file in full (these are concise definition files, typically <150 lines)
3. Extract from the definition:
   - Role description
   - Available micro agents list
   - Intra-system constraint resolution rules
   - Output format specification

### Micro Agent Definitions

Location: `agents/{system}/{agent-name}.md`

```
agents/
├── db/                          # 6 domains, 18 agents
│   ├── a1-engine-selector.md        # A: Storage Engine
│   ├── a2-compaction-strategist.md  # A: Storage Engine
│   ├── b1-index-architect.md        # B: Index & Query Plan
│   ├── b2-join-optimizer.md         # B: Index & Query Plan
│   ├── b3-query-plan-analyst.md     # B: Index & Query Plan
│   ├── c1-isolation-advisor.md      # C: Concurrency & Locking
│   ├── c2-mvcc-specialist.md        # C: Concurrency & Locking
│   ├── c3-lock-designer.md          # C: Concurrency & Locking
│   ├── d1-schema-expert.md          # D: Schema & Normalization
│   ├── d2-document-modeler.md       # D: Schema & Normalization
│   ├── d3-access-pattern-modeler.md # D: Schema & Normalization
│   ├── e1-page-optimizer.md         # E: I/O & Buffer Management
│   ├── e2-wal-engineer.md           # E: I/O & Buffer Management
│   ├── e3-buffer-tuner.md           # E: I/O & Buffer Management
│   ├── f1-replication-designer.md   # F: Distributed & Replication
│   ├── f2-consistency-selector.md   # F: Distributed & Replication
│   ├── f3-sharding-architect.md     # F: Distributed & Replication
│   └── f4-dynamodb-throughput-optimizer.md # F: Distributed & Replication
├── be/                          # 4 clusters, 18 agents
│   ├── s1-dependency-auditor.md     # S: Structure
│   ├── s2-di-pattern-selector.md    # S: Structure
│   ├── s3-architecture-advisor.md   # S: Structure
│   ├── s4-fitness-engineer.md       # S: Structure
│   ├── s5-convention-verifier.md    # S: Structure
│   ├── b1-context-classifier.md     # B: Boundary
│   ├── b2-acl-designer.md           # B: Boundary
│   ├── b3-event-architect.md        # B: Boundary
│   ├── b4-saga-coordinator.md       # B: Boundary
│   ├── b5-implementation-guide.md   # B: Boundary
│   ├── r1-bulkhead-architect.md     # R: Resilience
│   ├── r2-cb-configurator.md        # R: Resilience
│   ├── r3-retry-strategist.md       # R: Resilience
│   ├── r4-observability-designer.md # R: Resilience
│   ├── t1-test-guard.md             # T: Test
│   ├── t2-test-strategist.md        # T: Test
│   ├── t3-test-generator.md         # T: Test
│   └── t4-quality-assessor.md       # T: Test
├── if/
│   └── (stub — planned: pipeline-architect, observability-planner, reliability-engineer)
└── se/
    └── (stub — planned: auth-designer, encryption-advisor, compliance-auditor)
```

**Reading procedure** (performed by orchestrator, not Gateway Router):
1. Orchestrator determines which agent(s) to invoke based on classified domains
2. Read each required agent .md file
3. Agent definitions are typically <100 lines and always read in full

---

## Step 2: Constructing Task Prompts

### Orchestrator Task Prompt Template

The Gateway Router constructs prompts for orchestrators using this template:

```markdown
You are the {system_name} System Orchestrator for the engineering-workflow plugin.

## Your Definition
{contents of agents/{system}-orchestrator.md}

## Classification Result
{JSON classification from Phase 0}

## User Query
{original user query, verbatim}

## Instructions
1. Read the relevant micro agent definition(s) from agents/{system}/
2. For each relevant domain, construct a focused sub-question
3. Dispatch agent Tasks (parallel if independent, sequential if dependent)
4. Collect agent outputs
5. Resolve any intra-system constraint conflicts using your domain expertise
6. Return your structured output following the format in your definition

## Constraints
- Token budget for this orchestrator: {allocated_budget}K
- Depth: {shallow|deep}
- Mode: {query|analyze|compare|recommend}

## Output Format
Return a JSON object matching the orchestrator's defined output schema:
{
  "system": "DB|BE|IF|SE",
  "status": "completed|partial|error",
  "guidance": "Brief unified recommendation text",
  "query": "Original user query",
  "domains_analyzed": ["A", "B"],
  "agents_dispatched": ["a1-engine-selector", "b1-index-architect"],
  "chain_executed": ["A→B"],
  "agent_results": [ ... per-agent output objects (see schema below) ... ],
  "recommendations": [ ... actionable recommendation objects ... ],
  "resolved_constraints": [ ... constraints resolved within this system ... ],
  "unresolved_constraints": [ ... constraints needing cross-system resolution ... ],
  "constraints_used": { "key": "value, ... environment constraints used during analysis" },
  "conflicts": [ ... intra-system conflicts detected ... ],
  "cross_notes": [{"from_agent": "agent-id", "target_system": "DB|BE|IF|SE", "constraint": "description"}],
  "metadata": { "confidence": 0.0-1.0, "analysis_duration_ms": 1250 }
}

Field notes:
- `chain_executed`: BE orchestrator only — records the dependency chain order used for sequential agent dispatch. Omit for DB/IF/SE orchestrators.
- `constraints_used`: Key-value map of environment constraints used during analysis (e.g., `{"db_engine": "MySQL 8.0", "scale": "50GB"}`).
- `conflicts`: Intra-system conflicts detected before resolution (see constraint-propagation.md for schema).
- `cross_notes`: Structured array of cross-system constraint objects (`{from_agent, target_system, constraint}`). Each entry declares a constraint that one agent's recommendation imposes on another system.
```

### Agent Task Prompt Template

Orchestrators construct prompts for micro agents using this template:

```markdown
You are the {domain_name} Micro Agent.

## Your Definition
{contents of agents/{system}/{agent-name}.md}

## Query Context
{focused sub-question extracted by orchestrator from the user query}

## Reference Material
{relevant reference excerpts — see Step 3 below}

## Upstream Results (if sequential dispatch)
{results from prior agents in this wave — only included when this agent depends
on outputs from already-completed agents. Omit this section for parallel dispatch.}

## Depth
{shallow|deep}

## Output Requirements
Provide your analysis as a JSON object:
{
  "analysis": "detailed technical analysis (markdown)",
  "recommendation": "concrete actionable recommendation",
  "constraints": [
    {
      "constraint_type": "requires|recommends|prohibits|conflicts_with",
      "target_domain": "{other domain code or 'any'}",
      "description": "what this recommendation imposes",
      "priority": "hard|soft",
      "evidence": "why this constraint exists"
    }
  ],
  "trade_offs": [
    {
      "option": "option name",
      "pros": ["pro1", "pro2"],
      "cons": ["con1", "con2"],
      "recommended_when": "scenario description"
    }
  ],
  "confidence": 0.0-1.0  // see resources/confidence-calibration.md for 5-factor scoring rubric
}
```

---

## Step 3: Passing Reference Excerpts

Agents may need reference material beyond their definition file. Orchestrators are responsible
for loading and passing relevant excerpts.

### Reference Loading Strategy

| Reference Size | Strategy | Example |
|----------------|----------|---------|
| <= 200 lines | Read entire file, pass as-is | Agent definition files |
| 201-500 lines | Read relevant section via offset/limit | Architecture guides |
| > 500 lines | Grep for relevant terms, then Read matched sections | Large specification documents |

### Inline vs. Read Delegation

Two strategies for providing references to agents:

**Strategy A: Inline in Prompt (preferred for small references)**
```
Orchestrator reads the reference file → includes excerpt in agent Task prompt
Agent does NOT need to call Read
Token cost: paid once in orchestrator context
```

**Strategy B: Read Delegation (for large or conditional references)**
```
Orchestrator passes file path + section hint in agent Task prompt
Agent calls Read with offset/limit to load what it needs
Token cost: paid in agent context only if needed
```

**Decision rule**:
- Reference <= 100 lines: Strategy A (inline)
- Reference > 100 lines: Strategy B (delegate)
- Reference needed by 2+ agents: Strategy A (inline in orchestrator, shared context)

### Reference Selection per Domain

Orchestrators select references based on the classified domains:

```
For each agent being invoked:
  1. Check agent .md for "## References" section
  2. Load listed references using the size-based strategy above
  3. For shallow depth: load only primary references
  4. For deep depth: load primary + secondary references
```

---

## Step 4: Parallel vs. Sequential Agent Dispatch

### Independence Analysis

Before dispatching agents, the orchestrator determines execution order.

**Independent agents** (can run in parallel):
- Agents analyzing different aspects of the same query
- Agents whose outputs do not depend on each other
- Example: storage-engine-agent and schema-design-agent analyzing the same workload

**Dependent agents** (must run sequentially):
- Agent B needs Agent A's output as input
- Example: query-optimization-agent needs schema-design-agent's schema to analyze query plans

### Parallel Dispatch

```
For independent agents A, B, C:
  Invoke 3 Task calls simultaneously
  Wait for all to complete
  Collect results: [result_A, result_B, result_C]
```

**Parallel dispatch rules**:
1. Maximum 3 concurrent agent Tasks per orchestrator (to manage token budget)
2. If 4+ agents needed: batch into groups of 3, run groups sequentially
3. Each parallel agent receives the same base context (query + classification)
4. Agents in parallel do NOT see each other's outputs

### Sequential Dispatch

```
For dependent agents A → B → C:
  result_A = Task(agent_A, query)
  result_B = Task(agent_B, query + result_A.relevant_excerpts)
  result_C = Task(agent_C, query + result_A.relevant_excerpts + result_B.relevant_excerpts)
```

**Sequential dispatch rules**:
1. Pass only relevant excerpts from prior agents, not full outputs
2. Mark which constraints from prior agents are inputs vs. informational
3. Track cumulative token usage; if approaching budget, truncate prior agent excerpts

### Dependency Detection Heuristics

| Agent Pair | Dependency | Direction |
|------------|-----------|-----------|
| Domain A (Engine) + Domain D (Schema) | Independent | Parallel |
| Domain D (Schema) + Domain B (Index) | Dependent | D → B |
| Domain C (Concurrency) + Domain F (Distributed) | Dependent | C → F |
| Domain A (Engine) + Domain E (I/O) | Dependent | A → E |
| Cluster S (Structure) + Cluster B (Boundary) | Independent | Parallel |
| Cluster B (Boundary) + Cluster R (Resilience) | Dependent | B → R |

---

## Step 5: Result Collection and Merging

### Collection Format

Each agent returns a structured JSON result (per the template in Step 2).
The orchestrator collects all results into an array.

```json
{
  "agent_results": [
    {
      "agent": "a1-engine-selector",
      "domain": "A",
      "result": { ... agent output ... },
      "confidence": 0.85
    },
    {
      "agent": "d1-schema-expert",
      "domain": "D",
      "result": { ... agent output ... },
      "confidence": 0.80
    }
  ]
}
```

### `agent_results` Internal Object Schema

The `agent_results` array contains per-agent output objects. The schema varies by system:

**DB Orchestrator** (domain-based grouping):
```json
{
  "agent": "a1-engine-selector",
  "domain": "A",
  "result": { "...agent output..." },
  "confidence": 0.85
}
```

**BE Orchestrator** (cluster-based grouping):
```json
{
  "agent": "b1-context-classifier",
  "cluster": "B",
  "result": { "...agent output..." },
  "confidence": 0.90
}
```

Common fields across all systems: `agent` (agent ID), `result` (full agent output object), `confidence` (0.0-1.0). The grouping key differs: DB uses `domain` (A-F), BE uses `cluster` (S/B/R/T). IF and SE will follow the same pattern with their respective grouping keys once implemented.

### Merging Strategy

The orchestrator merges agent results using this procedure:

```
1. Concatenate all analysis sections (ordered by domain code: A, B, C, ...)
2. Collect all constraints into a unified list
3. Persist constraints: for each agent constraint, call write_constraint()
   via Bash to append to ~/.claude/cache/engineering-workflow/constraints.json
4. For recommendations:
   a. If agents agree: use the consensus recommendation
   b. If agents disagree: present both with orchestrator's synthesis
5. For trade-offs: merge and deduplicate
6. Calculate overall confidence: weighted average of agent confidences
7. After merge: run resolve-constraints.sh on the persisted constraints
```

### Handling Agent Failures

```
IF agent.status == "failed" OR agent.status == "timeout":
  1. Log the failure: { agent_id, error, timestamp }
  2. If this is a parallel dispatch and other agents succeeded:
     → Continue with available results, note gap in output
  3. If this is a sequential dispatch and a dependency failed:
     → Skip dependent agents, provide orchestrator-level fallback analysis
  4. Add warning to merged result: "Agent {id} failed: {reason}. Analysis may be incomplete."
```

---

## Step 5.5: Quality Indicators

After collecting and merging agent results (Step 5), extract quality indicators
for use by the Analysis Quality Gate (Phase 2.5).

### Quality Indicator Extraction

```
For each agent_result in merged results:
  1. Run: scripts/validate-agent-output.sh domain-agent <agent-output>
     → Extract quality_score (0-100)
  2. Run: scripts/audit-analysis.sh confidence <agent-output>
     → Extract confidence action (PASS/WARN/RETRY/REJECT)
  3. Append to agent_result:
     quality_indicators: {
       quality_score: <from validate>,
       confidence_action: <from audit>,
       has_trade_offs: <boolean>,
       recommendation_length: <int>,
       constraint_count: <int>
     }
```

### Quality-Based Result Annotation

```
IF any agent confidence_action == "REJECT":
  Mark agent_result as excluded; use orchestrator fallback
IF any agent confidence_action == "RETRY":
  Re-dispatch with simplified prompt (query + constraints only, no references)
  Update agent_result with retry output
IF quality_score < 50:
  Add warning: "Low quality score ({score}) — analysis may lack depth"
```

These indicators feed directly into Phase 2.5 audit decisions.

---

## Step 6: Token Budget Management

### Budget Allocation

The Gateway Router allocates token budgets per execution pattern:

| Pattern | Base | Orchestrator(s) | Agents | Synthesizer | Format | Audit |
|---------|------|-----------------|--------|-------------|--------|-------|
| Single-domain | 6K | 1K | 4K | -- | 1K | +0.3K (LIGHT) |
| Multi-domain | 6K | 2K | 3K/agent (max 3) | -- | 1K | +1.5K (STANDARD) |
| Cross-system | 15K | 1K/orch (max 3) | 2K/agent (max 6) | 3K | 2K | +3.5K (THOROUGH) |

### Budget Tracking

```
At each Task invocation:
  1. Estimate token cost = prompt_tokens + expected_output_tokens
  2. Add to running total: cumulative_tokens += estimated_cost
  3. Check against budget:
     - cumulative < 80% budget: proceed normally
     - 80% <= cumulative < 100%: truncate reference excerpts for remaining agents
     - cumulative >= 100%: skip remaining low-priority agents; proceed with available results
```

### Reference Truncation Rules

When budget pressure triggers truncation:

```
Priority order for truncation (truncate lowest priority first):
1. Secondary reference excerpts (nice-to-have context)
2. Example sections within agent definitions
3. Trade-off analysis (reduce to top 2 options only)
4. Primary reference excerpts (reduce to key paragraphs)
5. NEVER truncate: agent core definition, user query, classification result, constraints
```

---

## Cross-System Orchestration

For Pattern 3 (cross-system) queries, the Gateway Router manages multiple orchestrators.

### Parallel Orchestrator Dispatch

```
1. Identify required orchestrators from classification
2. Dispatch all orchestrators in parallel
3. Each orchestrator runs its own agent pipeline independently
4. Collect all orchestrator outputs
5. Pass to synthesizer for cross-system integration
```

### Synthesizer Invocation

The synthesizer receives:
- All orchestrator outputs (analysis + constraints + recommendations)
- The original user query
- Classification result
- Any cross-system constraint conflicts detected by resolve-constraints.sh

```markdown
## Synthesizer Task Prompt

You are the Cross-System Synthesizer.

## Orchestrator Outputs
{orchestrator_1_output}
---
{orchestrator_2_output}
---
{orchestrator_3_output}

## Constraint Conflicts
{output of resolve-constraints.sh, if any conflicts detected}

## User Query
{original query}

## Instructions
1. Identify cross-system dependencies and conflicts
2. Resolve constraint conflicts using system-priority rules
3. Produce a unified recommendation that satisfies all systems
4. Document cross-system trade-offs explicitly
5. Provide implementation priority ordering

## Output Format
{same JSON format as orchestrator output, plus:
  "cross_system_dependencies": [...],
  "implementation_priority": [...],
  "risk_assessment": [...]
}
```

### System Priority Rules (for conflict resolution)

When constraints conflict across systems, the synthesizer applies these priority rules:

| Conflict Type | Resolution Rule |
|---------------|----------------|
| SE vs. any other system | Security constraints take priority (hard constraints only) |
| DB vs. BE | Evaluate based on data integrity impact; DB wins for consistency, BE wins for latency |
| IF vs. BE | Infrastructure constraints are advisory unless they involve hard capacity limits |
| DB vs. IF | DB requirements for storage/IOPS take priority over generic IF optimization |

These are defaults. The synthesizer may override with explicit justification in its output.

---

## Phase Transition Context Management

Context accumulates across pipeline phases. To manage token budgets, apply
phase-based context pruning at each transition point.

> **Implementation note**: Pruning rules are behavioral guidance — when
> transitioning phases, avoid loading or re-referencing materials from
> completed phases. Claude Code cannot selectively delete loaded context,
> but it can avoid re-reading files that are no longer needed. The "Prune"
> column below lists what should NOT be referenced or re-loaded after each
> transition, not what is physically removed from context.

### Pruning Rules by Phase Transition

| Transition | Prune | Retain |
|------------|-------|--------|
| Phase 1 → Phase 2 | — (no pruning) | Orchestrator context needed for agent dispatch |
| Phase 2 → Phase 2.5 | Agent `.md` definitions, reference file content | Agent output JSON, quality_indicators, orchestrator `.md` |
| Phase 2.5 → Phase 3 | Audit findings (internalized into annotations) | Annotated agent outputs, analysis-audit-protocol.md |
| Phase 3 → Phase 3.5 | Raw agent outputs (keep summaries) | Resolved/unresolved constraints, orchestrator outputs |
| Phase 3.5 → Phase 4 | Contract validation details (internalized) | Validated orchestrator outputs, classification |
| Phase 4 → Phase 4.5 | Orchestrator `.md` files | Synthesizer output, classification |
| Phase 4.5 → Phase 5 | Synthesis validation details | Final validated output, classification, SKILL.md core |

### Never Prune

These elements must remain in context throughout all phases:

1. **Classification result** — needed for output formatting
2. **SKILL.md core** (~100 lines: Role + Routing Table sections) — gateway reference
3. **Final output JSON** — the deliverable

### Context Budget Checkpoints

At each phase transition, estimate context usage:

```
context_pct = (estimated_tokens_used / pattern_budget) * 100

IF context_pct >= 80%:
  Apply pruning rules for current transition
  Log: "[EW] Context pruning applied at Phase {N} transition ({context_pct}%)"

IF context_pct >= 90% after pruning:
  Skip remaining low-priority reference loading
  Log: "[EW] Critical context pressure — skipping optional references"
```

### Cross-System Query Budget (with pruning)

Without pruning: ~14-18K tokens at Phase 4
With pruning: ~8-10K tokens at Phase 4

| Phase | Without Pruning | With Pruning | Notes |
|-------|----------------|-------------|-------|
| Phase 1 complete | 3.7K | 3.7K | No pruning yet |
| Phase 2 complete | 9.2K | 9.2K | Agent outputs generated |
| Phase 2.5 complete | 10.7K | **7.7K** | Agent defs + refs pruned; audit protocol loaded |
| Phase 3 entry | 11.3K | **8.0K** | Audit findings internalized |
| Phase 3.5 complete | 12.5K | **8.5K** | Contract validation internalized |
| Phase 4 entry | 13.0K | **9.0K** | Raw outputs pruned |
| Phase 4.5 complete | 14.5K | **10.0K** | Synthesis validation internalized |
| Phase 5 entry | 15.0K | **10.5K** | All validation artifacts pruned |

---

## Pattern Examples

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
