# Constraint Propagation Protocol

> Defines how constraints flow between agents, how conflicts are detected and resolved,
> and how constraint state is managed across the query lifecycle.
> Loaded when entering Phase 3: Constraint Resolution.

## Overview

Constraints are the primary mechanism for inter-agent communication in the engineering-workflow
system. Each agent declares constraints that its recommendation imposes on other domains.
These constraints flow upward through orchestrators, are merged and checked for conflicts,
and ultimately produce a resolved constraint set that informs the final recommendation.

---

## Constraint Schema

### constraints-template.json

Every constraint object follows this schema:

```json
{
  "id": "c-{source_agent}-{sequence_number}",
  "source_agent": "db/a1-engine-selector",
  "source_system": "DB",
  "source_domain": "A",
  "constraint_type": "requires",
  "target_system": "DB",
  "target_domain": "C",
  "description": "LSM-tree selection requires sorted string table key design in schema",
  "priority": "hard",
  "evidence": "Random key insertion causes 3x write amplification in LSM-tree compaction",
  "timestamp": "2026-02-12T10:30:00Z",
  "status": "declared"
}
```

### Field Definitions

| Field | Type | Values | Description |
|-------|------|--------|-------------|
| `id` | string | `c-{agent}-{N}` | Unique constraint identifier |
| `source_agent` | string | agent path | Agent that declared this constraint |
| `source_system` | string | DB, BE, IF, SE | System of the source agent |
| `source_domain` | string | A-F or sub-domain name | Domain of the source agent |
| `constraint_type` | enum | requires, recommends, prohibits, conflicts_with | Relationship type |
| `target_system` | string | DB, BE, IF, SE, any | System affected by this constraint |
| `target_domain` | string | A-F, sub-domain name, any | Domain affected |
| `description` | string | free text | Human-readable constraint description |
| `priority` | enum | hard, soft | Hard = must satisfy; Soft = should satisfy |
| `evidence` | string | free text | Technical justification |
| `timestamp` | ISO 8601 | datetime | When the constraint was declared |
| `status` | enum | declared, accepted, rejected, resolved, archived | Lifecycle status |

### Constraint Types

| Type | Semantics | Example |
|------|-----------|---------|
| `requires` | Target domain MUST adopt this condition | "Sharding requires application-level routing" |
| `recommends` | Target domain SHOULD adopt this condition | "LSM recommends time-based partitioning for efficient compaction" |
| `prohibits` | Target domain MUST NOT do this | "Synchronous replication prohibits cross-region writes for latency SLA" |
| `conflicts_with` | Explicit declaration of known conflict | "Read replicas conflict with strong consistency requirements" |

---

## How Agents Declare Constraints

### Declaration Rules

Each agent includes a `constraints` array in its output:

```
1. Declare at least 1 constraint if your recommendation imposes requirements on other domains
2. Declare 0 constraints only if your analysis is fully self-contained
3. Maximum 5 constraints per agent (to prevent constraint explosion)
4. Each constraint must include evidence (no unsupported assertions)
5. Use "hard" priority sparingly — only for genuine technical requirements
6. Use "soft" priority for best-practice recommendations
```

### Constraint Granularity

```
TOO BROAD:  "requires good schema design"          → rejected (not actionable)
TOO NARROW: "requires column X to be VARCHAR(255)" → acceptable only if specific schema is known
JUST RIGHT: "requires sorted key layout for LSM compaction efficiency" → accepted
```

### Self-Constraints

Agents may declare constraints on their own domain to document assumptions:

```json
{
  "source_agent": "db/a1-engine-selector",
  "target_domain": "A",
  "constraint_type": "requires",
  "description": "Assumes SSD storage with >= 10K IOPS",
  "priority": "hard"
}
```

---

## Cross-Agent Constraint Merge Logic

### Intra-System Merge (Orchestrator Level)

Orchestrators merge constraints from agents within their system.

```
Procedure:
1. Collect all constraint objects from completed agents
2. Group constraints by target_domain
3. For each target_domain group:
   a. Check for conflicts (see Conflict Detection below)
   b. If no conflicts: accept all constraints, set status = "accepted"
   c. If conflicts found: apply Intra-System Resolution (see below)
4. Output: merged constraint list with statuses updated
```

### Cross-System Merge (Synthesizer Level)

The synthesizer merges constraints from different orchestrators.

```
Procedure:
1. Collect all constraint lists from orchestrators
2. Group constraints by (target_system, target_domain)
3. For each group:
   a. Check for cross-system conflicts
   b. If no conflicts: accept all
   c. If conflicts found: apply Cross-System Resolution (see below)
4. Output: fully resolved constraint set
```

---

## Conflict Detection

### Definition of Conflict

Two constraints conflict when:
- They target the same domain
- One requires X while the other prohibits X (direct conflict)
- One requires X while the other requires NOT-X (implicit conflict)
- Both require X but with incompatible parameters (parameter conflict)

### Detection Algorithm (resolve-constraints.sh)

```bash
# Pseudocode for resolve-constraints.sh

for each pair (C1, C2) in constraints where C1.target == C2.target:
  # Direct conflict: requires vs prohibits
  if C1.type == "requires" and C2.type == "prohibits":
    if semantic_overlap(C1.description, C2.description):
      mark_conflict(C1, C2, "direct")

  # Implicit conflict: both require contradictory things
  if C1.type == "requires" and C2.type == "requires":
    if contradicts(C1.description, C2.description):
      mark_conflict(C1, C2, "implicit")

  # Parameter conflict: same requirement, different values
  if C1.type == C2.type and same_topic(C1, C2):
    if different_parameters(C1, C2):
      mark_conflict(C1, C2, "parameter")
```

**Note**: `semantic_overlap`, `contradicts`, and `same_topic` are implemented as keyword
matching heuristics in the shell script. For complex cases, the orchestrator or synthesizer
uses LLM judgment.

### Conflict Output Format

```json
{
  "conflict_id": "cf-001",
  "type": "direct",
  "constraint_a": "c-db-storage-1",
  "constraint_b": "c-db-schema-2",
  "description": "Storage agent requires LSM (sequential writes) but Schema agent requires B-tree (random reads)",
  "severity": "high",
  "resolution": null
}
```

---

## Conflict Resolution

### Intra-System Resolution (Orchestrator)

The orchestrator resolves conflicts between agents in its system using domain expertise.

```
Resolution order:
1. Priority comparison: hard beats soft
   - If C1.priority == "hard" and C2.priority == "soft": accept C1, relax C2
2. Evidence strength: prefer constraint with stronger quantified evidence
3. Domain priority (DB-specific, aligned with priority-matrix.md):
   - Correctness (Domain C) → Data Integrity (Level 5)
   - Durability (Domain E: WAL, checkpoint, flush) → Data Integrity (Level 5)
   - Performance (Domains A, B; Domain E: buffer/I/O tuning) → Performance (Level 2)
   - Scalability (Domain F) → Availability (Level 3)
   - Simplicity (Domain D) → Convenience (Level 1)
   - Domain E spans both levels: durability aspects at Level 5, I/O tuning at Level 2
   - Resolution follows: Data Integrity > Availability > Performance > Convenience
   - Example: concurrency-control (C, Level 5) hard constraint beats
     query-optimization (B, Level 2) soft constraint
4. If unresolvable: escalate to synthesizer with both constraints + context
```

### Resolved vs Unresolved Constraint Split

Orchestrators MUST separate constraints into two categories in their output:

- **`resolved_constraints`**: Constraints that were resolved within the system (no conflicts, or conflicts resolved by intra-system priority rules)
- **`unresolved_constraints`**: Constraints that could not be resolved within the system, OR constraints that may have cross-system implications

This split enables the synthesizer to detect cross-system conflicts that would otherwise be hidden by intra-system resolution.

**Rule**: When an intra-system constraint has an `impacts` field pointing to another system, it MUST be included in BOTH `resolved_constraints` AND passed to the synthesizer via the orchestrator output, even if resolved locally.

### Resolved Constraint Object Schema

Each object in the `resolved_constraints` array follows this schema:

```json
{
  "source": "f3-sharding-architect",
  "type": "requires | recommends | prohibits | conflicts_with",
  "description": "Hash-based shard routing required",
  "impacts": ["BE"],
  "resolution": "Accepted — no intra-DB conflict"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source` | string | yes | Agent ID that declared the constraint |
| `type` | enum | yes | Constraint type: requires, recommends, prohibits, conflicts_with |
| `description` | string | yes | Human-readable constraint description |
| `impacts` | string[] | no | Systems affected beyond the source system. Include when cross-system implications exist |
| `resolution` | string | yes | How the constraint was resolved (e.g., "Accepted — no conflict", "Accepted — hard beats soft") |

### Unresolved Constraint Object Schema

Each object in the `unresolved_constraints` array follows this schema:

```json
{
  "source": "a1-engine-selector",
  "type": "conflicts_with",
  "description": "LSM compaction conflicts with page fill factor recommendation",
  "conflicting_agent": "e1-page-optimizer"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source` | string | yes | Agent ID that declared the constraint |
| `type` | enum | yes | Constraint type: requires, recommends, prohibits, conflicts_with |
| `description` | string | yes | Human-readable constraint description |
| `conflicting_agent` | string | no | Agent ID whose output conflicts with this constraint. Include when the conflict is with a specific agent |

### Example

```json
{
  "resolved_constraints": [
    {
      "source": "f3-sharding-architect",
      "type": "requires",
      "description": "Hash-based shard routing required",
      "impacts": ["BE"],
      "resolution": "Accepted — no intra-DB conflict"
    }
  ],
  "unresolved_constraints": [
    {
      "source": "a1-engine-selector",
      "type": "conflicts_with",
      "description": "LSM compaction conflicts with page fill factor recommendation",
      "conflicting_agent": "e1-page-optimizer"
    }
  ]
}
```

### Cross-System Resolution (Synthesizer)

The synthesizer resolves conflicts between different systems.

> **Priority rules**: All conflict resolution follows the unified [priority-matrix.md](./priority-matrix.md). Intra-system conflicts use category priority; cross-system conflicts additionally use the system tiebreaker.

```
Resolution order:
1. Security hard constraints MUST win (non-negotiable)
2. Data integrity hard constraints beat performance soft constraints
3. For soft vs soft: evaluate trade-offs and present both options to user
4. For hard vs hard (rare): document the conflict and ask user for priority input

System priority hierarchy (for equal-priority conflicts):
  SE (security) > DB (data integrity) > BE (application logic) > IF (infrastructure)
```

### Resolution Output

```json
{
  "conflict_id": "cf-001",
  "resolution": "accept_a",
  "rationale": "LSM write performance is the primary requirement; schema will use sorted key design",
  "constraint_a_status": "accepted",
  "constraint_b_status": "rejected",
  "compromise": "Schema agent recommendation modified to use time-sorted partition keys"
}
```

---

## Storage: constraints.json

### File Location

```
~/.claude/cache/engineering-workflow/constraints.json
```

### File Structure

```json
{
  "session_id": "ew-2026-02-12-001",
  "query": "original user query",
  "classification": { ... },
  "constraints": [
    { ... constraint objects with updated statuses ... }
  ],
  "conflicts": [
    { ... conflict objects with resolutions ... }
  ],
  "resolved_set": [
    { ... only accepted/resolved constraints ... }
  ],
  "metadata": {
    "created_at": "2026-02-12T10:30:00Z",
    "resolved_at": "2026-02-12T10:31:15Z",
    "total_declared": 8,
    "total_accepted": 6,
    "total_rejected": 1,
    "total_conflicts": 2,
    "total_resolved": 2
  }
}
```

---

## Session Lifecycle

### Create (Phase 2 start)

```
1. Initialize empty constraints.json with session_id and query
2. Set metadata.created_at
```

### Update (During Phase 2 agent execution)

```
1. As each agent completes, append its constraints to constraints[]
2. Update metadata.total_declared
```

### Resolve (Phase 3)

```
1. Run resolve-constraints.sh on constraints[]
2. Populate conflicts[] with detected conflicts
3. Orchestrator/synthesizer resolves conflicts
4. Populate resolved_set[] with accepted constraints only
5. Set metadata.resolved_at and counts
```

### Archive (Phase 5 completion)

```
1. Copy constraints.json to session-history:
   ~/.claude/cache/engineering-workflow/history/{session_id}-constraints.json
2. Clear constraints.json for next query
3. Update session-history.jsonl with constraint summary
```

### Retention

```
- Active constraints.json: overwritten per query
- Archived history: keep last 20 sessions
- Pattern cache promotion: if same constraint pattern appears 3+ times, cache it
```

### Cross-Session Learning

Storage layout:
```
~/.claude/cache/engineering-workflow/
├── constraints.json          # Current session constraints
├── session-history.jsonl     # Past query classifications + outcomes
└── pattern-cache.json        # Learned routing patterns
```

1. After each query completion, append classification + outcome to `session-history.jsonl`
2. If the same query pattern appears 3+ times, cache the routing decision in `pattern-cache.json`
3. On next similar query, use cached routing for instant classification (confidence: 1.0)
