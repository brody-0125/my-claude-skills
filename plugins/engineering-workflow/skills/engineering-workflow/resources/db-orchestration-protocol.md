# DB Orchestration Protocol

> Detailed routing, dispatch, and merge protocol for the DB orchestrator and its 18 micro agents.

## 1. Agent Selection Matrix (Expanded)

### Domain A: Storage Engine

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| storage engine, engine selection, workload analysis | a1-engine-selector | Primary engine selection |
| LSM, compaction, write amplification, space amplification | a1 + a2-compaction-strategist | LSM-specific tuning required |
| RocksDB, LevelDB, WiredTiger, MyRocks | a1 + a2 | These engines use LSM trees |
| InnoDB, B-Tree only workload | a1 only | No LSM tuning needed |

### Domain B: Index & Scan

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| index, composite index, covering index, cardinality | b1-index-architect | Index design decisions |
| join, join order, nested loop, hash join, merge join | b2-join-optimizer | Join strategy optimization |
| EXPLAIN, query plan, full table scan, filesort | b3-query-plan-analyst | Plan interpretation |
| slow query, query optimization (broad) | b1 + b3 | Needs both index and plan analysis |

### Domain C: Concurrency

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| isolation level, read committed, serializable | c1-isolation-advisor | Isolation level selection |
| MVCC, version chain, vacuum, snapshot isolation | c2-mvcc-specialist | Version management |
| lock, deadlock, row lock, gap lock, latch | c3-lock-designer | Lock strategy design |
| concurrent transaction + deadlock | c1 + c3 | Needs isolation + lock analysis |

### Domain D: Normalization

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| normalization, 3NF, BCNF, functional dependency | d1-schema-expert | Schema normalization |
| document model, embed vs reference, MongoDB schema | d2-document-modeler | Document DB modeling |
| access pattern, hot path, query frequency | d3-access-pattern-modeler | Pattern-driven modeling |
| schema design + access patterns | d1 + d3 | Needs both schema and pattern analysis |

### Domain E: I/O & Pages

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| page, fill factor, fragmentation, I/O optimization | e1-page-optimizer | Page-level optimization |
| WAL, write-ahead log, checkpoint, durability, fsync | e2-wal-engineer | WAL configuration |
| buffer pool, cache hit, eviction, memory | e3-buffer-tuner | Buffer pool tuning |
| I/O performance (broad) | e1 + e3 | Needs page + buffer analysis |

### Domain F: Distributed

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| replication, replica, failover, leader-follower | f1-replication-designer | Replication topology |
| consistency, CAP theorem, PACELC, linearizable | f2-consistency-selector | Consistency model |
| sharding, partition, shard key, rebalancing | f3-sharding-architect | Sharding strategy |
| dynamodb, rcu, wcu, hot partition, adaptive capacity, throttling, provisioned throughput, on-demand, tps | f4-dynamodb-throughput-optimizer | DynamoDB high-throughput optimization |
| distributed database design (broad) | f1 + f2 + f3 + f4 | Full distributed design |

## 2. Cross-Domain Dependency Rules

Dependencies dictate dispatch ordering. Independent domains run in parallel.

```
A (Storage Engine) ──affects──▶ E (I/O & Pages)
  Rationale: Engine choice (B-Tree vs LSM) fundamentally changes
  page layout, WAL behavior, and buffer pool characteristics.

D (Normalization) ──affects──▶ B (Index & Scan)
  Rationale: Schema structure determines which columns exist for
  indexing and which join patterns are needed.

C (Concurrency) ──affects──▶ F (Distributed)
  Rationale: Local isolation guarantees constrain what distributed
  consistency models are feasible.

B (Index & Scan) ──affects──▶ E (I/O & Pages)
  Rationale: Index design impacts page read patterns and
  buffer pool working set size.
```

### Dependency Resolution Algorithm

```
1. Build dependency graph from requested domains
2. Topological sort to determine wave ordering
3. Wave 1: domains with no incoming dependencies
4. Wave 2: domains that depend on Wave 1 results
5. Wave 3: domains that depend on Wave 2 results (rare)
6. Within each wave, dispatch agents in parallel
```

> **Note**: f4-dynamodb-throughput-optimizer has no upstream dependencies; it MUST run in Wave 1 regardless of other requested domains. The C → F dependency applies to f1/f2/f3 (consistency model selection) but not to f4 (DynamoDB throughput is independent of local isolation guarantees).

Example: Query involves domains A, B, E
- Wave 1: A (no dependencies among requested)
- Wave 2: B (independent of A, can run in Wave 1 too), E (depends on A)
- Optimized: Wave 1 = {A, B} parallel, Wave 2 = {E} with A's results

## 3. Reference Excerpt Extraction Procedure

Each domain has a reference file at `references/db/domain-{X}.md`.

### Extraction Steps

1. Determine the relevant section heading from `classification.sub_topics`
2. Read the reference file with offset/limit to find the section:
   - First pass: Read first 50 lines to get table of contents
   - Identify line range for relevant section
   - Second pass: Read only that section (typically 50-150 lines)
3. Pass extracted text as `reference_excerpt` in agent input
4. Maximum excerpt size: 200 lines per agent

### Section Mapping

| Sub-topic Pattern | Reference Section |
|-------------------|-------------------|
| engine selection, workload | domain-A.md § Storage Engine Comparison |
| LSM, compaction | domain-A.md § LSM-Tree Internals |
| index design | domain-B.md § Index Design Principles |
| join strategy | domain-B.md § Join Algorithms |
| query plan | domain-B.md § Execution Plan Analysis |
| isolation | domain-C.md § Isolation Levels |
| MVCC | domain-C.md § MVCC Implementations |
| locking | domain-C.md § Lock Management |
| normalization | domain-D.md § Normal Forms |
| document model | domain-D.md § Document Modeling |
| access pattern | domain-D.md § Access Pattern Analysis |
| page, I/O | domain-E.md § Page Structure |
| WAL | domain-E.md § Write-Ahead Logging |
| buffer | domain-E.md § Buffer Management |
| replication | domain-F.md § Replication Topologies |
| consistency | domain-F.md § Consistency Models |
| sharding | domain-F.md § Sharding Strategies |
| dynamodb throughput, rcu/wcu, hot partition, adaptive capacity, throttling | domain-F-dynamodb-throughput.md § Throughput Scaling Fundamentals |

## 4. Parallel Dispatch Rules

### Concurrency Limits

- Maximum parallel agents: 3 (to stay within Task tool limits)
- If more than 3 agents needed, split into waves of max 3

### Dispatch Protocol

```
1. For each wave:
   a. Construct agent inputs (include upstream_results if available)
   b. Dispatch all agents in wave via parallel Task calls
   c. Await all results
   d. Validate each result is valid JSON
   e. If any agent fails, retry once with simplified input
2. Pass wave results to next wave as upstream_results
```

### Timeout Handling

- Per-agent timeout: 60 seconds
- If agent exceeds timeout, mark as timed_out and proceed
- Include timeout in output metadata

## 5. Result Merge Algorithm

### Step-by-Step Merge

```
1. Initialize merged_result = {}
2. For each agent result:
   a. Extract recommendation fields
   b. Add to merged_recommendations[] with source agent tag
   c. Check for conflicts with existing recommendations
3. For each pair of recommendations:
   a. If fields overlap and values differ → add to conflicts[]
   b. If fields overlap and values agree → merge and note agreement
4. Compute aggregate_confidence as weighted average
5. Generate cross_notes from dependency relationships
```

### Conflict Detection Rules

Two recommendations conflict when:
- Same configuration parameter, different values (e.g., fill_factor: 0.9 vs 0.7)
- Mutually exclusive strategies (e.g., "use read replicas" vs "use multi-leader")
- Resource allocation exceeds available budget (e.g., buffer pool + WAL memory > total RAM)

## 6. Constraint Propagation Between Agents

### Propagation Flow

```
User Constraints (explicit)
    │
    ▼
Domain A agent → engine_type, storage_model
    │
    ▼
Domain E agent receives: engine_type affects page_size, wal_format
Domain B agent receives: engine_type affects available index types
    │
    ▼
Domain D agent → schema_structure, document_model
    │
    ▼
Domain B agent receives: schema_structure affects index candidates
    │
    ▼
Domain C agent → isolation_level, lock_strategy
    │
    ▼
Domain F agent receives: isolation_level constrains consistency_model
```

### Constraint Format

Intra-DB constraints between agents use a simplified format derived from
the full schema defined in `constraint-propagation.md`:

```json
{
  "source_agent": "a1-engine-selector",
  "source_domain": "A",
  "constraint_type": "requires",
  "target_domain": "E",
  "priority": "hard",
  "description": "InnoDB engine selection constrains page layout and buffer pool behavior",
  "field": "engine_type",
  "value": "InnoDB",
  "implications": [
    "B-Tree based indexes only",
    "Clustered index on primary key",
    "Buffer pool is primary cache mechanism"
  ]
}
```

Field mapping to `constraint-propagation.md` full schema:
- `source_system` always "DB" (omitted for brevity in intra-system constraints)
- `target_system` always "DB" (omitted for brevity in intra-system constraints)
- `field` + `value` + `implications` are DB-specific shorthand extensions
- `id`, `evidence`, `timestamp`, `status` are added by `_common.sh` write_constraint()

- **Hard constraints** (`priority: "hard"`): Must be respected by downstream agents (e.g., engine choice)
- **Soft constraints** (`priority: "soft"`): Recommendations that downstream agents should consider but may override with justification

### Conflict Resolution Priority

> **Note**: This is a DB-specific refinement of the universal priority hierarchy
> defined in `priority-matrix.md`. The mapping is:
> - Correctness (Domain C) → Data Integrity (Level 5)
> - Durability (Domain E: WAL, checkpoint) → Data Integrity (Level 5)
> - Performance (Domain A, B, Domain E: buffer/I/O tuning) → Performance (Level 2)
> - Scalability (Domain F) → Availability (Level 3)
> - Simplicity (Domain D) → Convenience/DX (Level 1)
>
> Domain E spans two priority levels: durability aspects (WAL, checkpoint, flush)
> map to Data Integrity (Level 5); performance aspects (buffer pool sizing, I/O
> optimization) map to Performance (Level 2). When an E-domain constraint is
> ambiguous, classify by the specific sub-topic.
>
> For cross-system conflicts, use `priority-matrix.md` directly.

When DB agents produce conflicting intra-system recommendations:

```
Priority 1: User-specified constraints MUST win
Priority 2: Correctness (Domain C — isolation/concurrency)
Priority 3: Durability (Domain E — WAL/checkpoint/flush)
Priority 4: Performance (Domains A, B — engine/index; Domain E — buffer/I/O tuning)
Priority 5: Scalability (Domain F — distributed)
Priority 6: Simplicity (Domain D — schema design)
```

If `scripts/resolve-constraints.sh` is available, pipe conflicting outputs through it for automated resolution. Otherwise, apply the priority ranking above and document the resolution rationale.
