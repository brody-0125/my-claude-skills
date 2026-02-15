# Cross-System Synthesis Protocol

> Defines the cross-system synthesis procedure followed by the synthesizer agent

---

## 1. Result Collection Format

Each orchestrator must return results in the following standard format.

### 1.1 Orchestrator Result Schema

This schema matches the output format defined in `orchestration-protocol.md`.

```json
{
  "system": "DB | BE | IF | SE",
  "status": "completed | partial | error",
  "guidance": "Brief unified recommendation text",
  "query": "Original user query",
  "domains_analyzed": ["A", "B"],
  "agents_dispatched": ["a1-engine-selector", "b1-index-architect"],
  "chain_executed": ["S→B→R"],
  "agent_results": [ "... per-agent output objects ..." ],
  "recommendations": [
    {
      "id": "rec_{system}_{seq}",
      "title": "Recommendation title",
      "description": "Detailed description",
      "priority": "critical | high | medium | low",
      "impacts": ["List of affected systems"]
    }
  ],
  "resolved_constraints": [ "... constraints resolved within this system ..." ],
  "unresolved_constraints": [ "... constraints needing cross-system resolution ..." ],
  "constraints_used": { "key": "value, ... environment constraints used during analysis" },
  "conflicts": [ "... intra-system conflicts detected ..." ],
  "cross_notes": [{"from_agent": "agent-id", "target_system": "DB|BE|IF|SE", "constraint": "description"}],
  "metadata": {
    "confidence": 0.85,
    "analysis_duration_ms": 1250
  }
}
```

Field notes:
- `chain_executed`: BE orchestrator only — dependency chain order for sequential dispatch. Omit for other systems.
- `constraints_used`: Key-value map of environment constraints used during analysis.
- `conflicts`: Intra-system conflicts detected before resolution.
- `cross_notes`: Structured array of cross-system constraint objects (`{from_agent, target_system, constraint}`).
- `analysis_duration_ms`: Wall-clock time spent in orchestrator execution.

### 1.1.1 Required Field Enforcement

Before synthesis, each orchestrator result is validated by `scripts/audit-analysis.sh orchestrator`.
Missing fields are handled according to this policy:

| Field | Severity | Missing Action |
|-------|----------|----------------|
| `system` | CRITICAL | Reject result — cannot synthesize without system identifier |
| `status` | CRITICAL | Default to `"partial"` + EW-AUD-006 warning |
| `guidance` | Required | Substitute from `recommendations[0].title` if available; else `"No guidance provided"` |
| `recommendations` | Required | Default to `[]` + warning; synthesis proceeds with reduced scope |
| `resolved_constraints` | Required | Default to `[]`; constraint analysis skipped for this system |
| `unresolved_constraints` | Required | Default to `[]`; cross-system conflict detection may miss issues |
| `metadata.confidence` | Required | Default to `0.5` + warning; affects overall confidence calculation |

**Validation trigger**: Phase 3.5 (Contract Enforcement Gate) for STANDARD+ tier.
For LIGHT tier, only `system` and `status` are validated (critical fields only).

### 1.2 Stub Result Format

A stub orchestrator must include at least the following fields:

```json
{
  "system": "IF",
  "status": "stub",
  "guidance": "General guideline text",
  "query": "Original user query",
  "recommendations": [],
  "resolved_constraints": [],
  "unresolved_constraints": [],
  "metadata": { "confidence": 0.0 }
}
```

---

## 2. Dependency Detection Rules

### 2.1 Cross-System Dependency Patterns

Cross-system dependencies are detected using the following rules.

#### Keyword-Based Detection

| Trigger Keyword (Source) | Affected System | Dependency Type |
|---------------------|-----------|-----------|
| `sharding`, `partition` | BE | Requires connection pool and routing changes |
| `schema migration`, `ALTER TABLE` | BE | Requires repository/DTO changes |
| `read replica`, `replication` | IF | Requires infrastructure provisioning |
| `API contract`, `endpoint change` | IF | Requires client call updates |
| `new service`, `microservice` | IF | Requires deployment pipeline addition |
| `cache`, `redis`, `memcached` | IF | Requires cache infrastructure + invalidation |
| `auth`, `OAuth`, `JWT` | SE | Requires authentication flow and security review |

#### Transitive Dependencies

Transitive dependencies are derived from direct dependencies:

```
IF DB → BE AND BE → IF THEN DB →(transitive)→ IF
```

Transitive dependencies are tagged with urgency levels:
- **Direct dependencies**: `urgency: "hard"` — must be respected in phase assignment
- **Transitive dependencies**: `urgency: "soft"` — informational for planning, not enforced in phase ordering

Phase assignment uses only `hard` (direct) dependencies for topological sort.
Soft (transitive) dependencies are included in the output for awareness but do not
create additional ordering constraints. This prevents over-constraining the
implementation order when the intermediate dependency already enforces the correct sequence.

### 2.2 Dependency Graph Construction

```
1. Add all direct dependencies to directed graph G
2. Compute transitive dependencies (transitive closure)
3. Detect cycles (DFS-based)
4. When a cycle is found:
   a. Identify the lowest-priority edge within the cycle
   b. Remove that edge + record a warning
   c. Record the removed edge separately as a "soft dependency"
```

---

## 3. Conflict Resolution Priority Matrix

> **Single source of truth**: See [priority-matrix.md](./priority-matrix.md) for the complete priority hierarchy, multi-category scoring algorithm, system tiebreaker rules, and user override mechanism.

The synthesizer applies the priority matrix as follows:

1. Score each conflicting recommendation using multi-category scoring (priority-matrix.md)
2. Higher weighted_priority wins
3. If tied: apply system priority tiebreaker (SE > DB > BE > IF)
4. If still tied: prefer completed > partial > stub orchestrator result
5. Propose mitigation for the losing side
6. Record resolution rationale

### User Overrides

If `constraints.priority_overrides` contains explicit rules (e.g., `["performance > availability"]`), these override the default matrix for the specified category pairs only.

---

## 4. Implementation Ordering Algorithm

### 4.1 Topological Sort-Based Ordering

```
COMPUTE_ORDER(dependencies[], recommendations[]):
  1. Construct dependency graph G (see section 2.2)
  2. Perform topological sort -> layers[]
  3. Sorting criteria within each layer:
     a. Prioritize conflict resolution winners
     b. Prioritize high-risk changes first (fail-fast)
     c. Prioritize foundational changes first
  4. Phase assignment:
     - Phase 1: Nodes with no incoming dependencies
     - Phase 2: Nodes depending only on Phase 1
     - Phase N: Nodes depending on Phase N-1
```

### 4.2 Per-Phase Metadata

Each phase includes the following information:

| Field | Description |
|------|------|
| `phase` | Sequence number (starting from 1) |
| `system` | Target system |
| `action` | Description of the action to perform |
| `depends_on` | List of prerequisite phases |
| `estimated_duration` | Estimated time required ("unknown" if stub) |
| `risk` | high / medium / low |
| `rollback` | Rollback strategy |

### 4.3 Parallelizable Segments

Tasks within the same phase that have no mutual dependencies are marked as parallelizable:

```json
{
  "phase": 2,
  "parallel_groups": [
    ["BE connection pool update", "SE monitoring setup"],
    ["IF auth flow update"]
  ]
}
```

---

## 5. Partial Result Handling

### 5.1 Orchestrator Failure Scenarios

| Scenario | Handling Method |
|---------|----------|
| Orchestrator timeout | Collect partial results, mark `status: "timeout"` |
| Orchestrator error | Exclude that system's results, record a warning |
| Stub orchestrator | Include only general guidelines, set `confidence: "low"` |
| All orchestrators are stubs | Proceed with synthesis but state "all analyses are at general guideline level" |

### 5.2 Partial Result Synthesis Rules

```
IF available_results.length == 0:
  -> Return error: "No results available for synthesis"

IF available_results.length == 1:
  -> Skip cross-system analysis
  -> Return the single system result directly + state limitations

IF available_results.all(status == "stub"):
  -> Proceed with synthesis
  -> confidence_assessment.overall = "low"
  -> Message: "All orchestrators are in stub state. Re-execution after implementation is recommended."

OTHERWISE:
  -> Proceed with normal synthesis procedure
  -> Include stub results in dependency analysis but assign them lower priority in conflict resolution
```

### 5.3 Confidence Calculation

```
confidence_score = (
  completed_count * 1.0 +
  partial_count * 0.5 +
  stub_count * 0.1
) / total_systems

overall_confidence:
  >= 0.8 → "high"
  >= 0.4 → "medium"
  <  0.4 → "low"
```

---

*This protocol is an on-demand resource referenced step-by-step by the `synthesizer.md` agent.*
