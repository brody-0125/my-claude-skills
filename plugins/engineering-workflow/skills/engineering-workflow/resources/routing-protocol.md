# Routing Protocol — Query Classification Algorithm

> Detailed classification procedure for Phase 0 of the engineering-workflow plugin.
> Loaded when entering Phase 0: Query Classification.

## Overview

Query classification determines which system(s), sub-domain(s), and execution pattern to use.
The goal is to resolve classification as quickly as possible: deterministic keyword matching
first, LLM fallback only for ambiguous cases.

```
Input: raw user query string
Output: {
  systems: ["DB" | "BE" | "IF" | "SE"],
  domains: ["A" | "B" | "C" | "D" | "E" | "F" | ...],
  pattern: "single" | "multi" | "cross",
  confidence: 0.0 - 1.0,
  mode: "query" | "analyze" | "compare" | "recommend",
  depth: "shallow" | "deep"
}
```

---

## Step 1: Explicit Flag Extraction

Before any keyword analysis, extract explicit flags from the user input.

```
Parse input for:
  --domain {db|be|if|se}   → force system selection
  --depth {shallow|deep}   → override depth detection
  mode prefix:
    "analyze:" → mode = "analyze"
    "compare:" → mode = "compare"
    "recommend:" → mode = "recommend"
    (none) → mode = "query"
```

If `--domain` is provided, skip keyword-based system detection (Step 2) and proceed
directly to sub-domain detection (Step 3) with confidence 1.0.

---

## Step 2: Keyword-Based System Detection (classify-query.sh)

The `scripts/classify-query.sh` script performs deterministic keyword matching.
It outputs a JSON classification result.

### Keyword-to-System Matrix

Each keyword is assigned to one or more systems with a weight.

| Keyword Pattern | DB | BE | IF | SE | Weight |
|----------------|:--:|:--:|:--:|:--:|--------|
| `storage engine`, `B-tree`, `LSM` | 1.0 | | | | 1.0 |
| `index design`, `index scan`, `seq scan` | 1.0 | | | | 0.9 |
| `query optimization`, `explain analyze` | 1.0 | | | | 0.9 |
| `schema design`, `normalization` | 1.0 | | | | 0.8 |
| `replication`, `failover`, `HA` | 1.0 | | 0.3 | | 0.8 |
| `sharding`, `horizontal scaling` | 1.0 | | 0.2 | | 0.8 |
| `isolation level`, `MVCC`, `locking` | 1.0 | 0.2 | | | 0.9 |
| `consistency model`, `CAP theorem` | 0.7 | 0.3 | | | 0.7 |
| `API design`, `REST`, `GraphQL`, `gRPC` | | 1.0 | | | 0.9 |
| `microservice`, `monolith`, `DDD` | | 1.0 | | | 0.8 |
| `concurrency`, `thread pool` | 0.3 | 1.0 | | | 0.7 |
| `connection pool`, `caching strategy` | 0.3 | 1.0 | | | 0.7 |
| `CQRS`, `event sourcing`, `saga` | 0.4 | 1.0 | | | 0.8 |
| `kubernetes`, `container`, `docker` | | | 1.0 | | 0.9 |
| `CI/CD`, `deployment pipeline` | | | 1.0 | | 0.8 |
| `load balancer`, `CDN`, `DNS` | | | 1.0 | | 0.9 |
| `monitoring`, `observability`, `tracing` | | | 1.0 | | 0.7 |
| `scaling`, `auto-scaling` | | 0.3 | 1.0 | | 0.7 |
| `terraform`, `ansible`, `helm` | | | 1.0 | | 0.8 |
| `infrastructure`, `devops`, `logging` | | | 1.0 | | 0.7 |
| `authentication`, `OAuth`, `JWT` | | | | 1.0 | 0.9 |
| `authorization`, `RBAC`, `ABAC` | | | | 1.0 | 0.9 |
| `encryption`, `TLS`, `key management` | | | 0.3 | 1.0 | 0.8 |
| `zero-trust`, `compliance`, `audit` | | | 0.2 | 1.0 | 0.8 |
| `vulnerability`, `penetration testing` | | | | 1.0 | 0.9 |
| `security`, `CORS`, `CSRF`, `XSS` | | | | 1.0 | 0.8 |
| `firewall`, `certificate`, `token mgmt` | | | 0.3 | 1.0 | 0.7 |
| `multi-tenant` | 0.5 | 0.5 | 0.2 | 0.4 | 0.6 |
| `architecture decision` | 0.3 | 0.3 | 0.3 | 0.3 | 0.5 |

### Scoring Algorithm

> **Implementation note**: The keyword-to-system matrix weights above are used for
> documentation and LLM classification context. The `classify-query.sh` fast-path
> uses a simplified fixed-tier confidence algorithm (below) which was chosen over
> weighted scoring because: (1) bash regex matching is binary (match/no-match),
> not weighted; (2) the fixed-tier approach is sufficient for keyword-based routing;
> (3) weighted scoring adds complexity without meaningful accuracy gains for a
> deterministic fast-path that falls through to LLM for ambiguous cases anyway.

**Actual confidence calculation** (implemented in `classify-query.sh`):

```
total_matches = count of systems with at least 1 keyword hit
domain_count  = count of DB sub-domains matched (A-F)
cluster_count = count of BE clusters matched (S/B/R/T)

IF total_matches == 0:
  confidence = 0.0      → no keywords matched, fall through to LLM
ELIF total_matches == 1 AND (domain_count >= 1 OR cluster_count >= 1):
  confidence = 0.85     → single system with specific sub-domain: high confidence
ELIF total_matches == 1:
  confidence = 0.70     → single system but no sub-domain: moderate confidence
ELIF total_matches >= 2:
  confidence = 0.60     → multi-system: lower confidence, may benefit from LLM refinement
```

All systems with at least one keyword match are included in the output `systems[]` array.

### Pattern Detection

```
IF len(systems) == 0: no classification (fall through to LLM)
IF len(systems) == 1 AND len(domains) <= 1: pattern = "single"
IF len(systems) == 1 AND len(domains) >= 2: pattern = "multi"
IF len(systems) >= 2: pattern = "cross"
```

---

## Step 3: Sub-Domain Detection

After system(s) are identified, detect specific sub-domains within each system.

### DB Sub-Domain Keywords

| Sub-Domain | Code | Primary Keywords | Secondary Keywords |
|------------|------|-----------------|-------------------|
| Storage Engine | A | storage engine, B-tree, LSM-tree, WAL | page layout, buffer pool, compaction, write amplification, fsync |
| Index & Query Plan | B | query plan, explain analyze, index design | index scan, nested loop, hash join, cost estimation, composite index |
| Concurrency & Locking | C | isolation level, MVCC, deadlock | optimistic locking, pessimistic locking, serializable, phantom read |
| Schema & Normalization | D | schema design, normalization, data model | migration, column type, constraint, partition strategy, ERD |
| I/O & Buffer Management | E | page, buffer pool, WAL, checkpoint | dirty page, flush, IO optimization, sequential IO, random IO |
| Distributed & Replication | F | replication, failover, sharding, shard key | consensus, raft, paxos, distributed transaction, resharding |

### BE Sub-Domain Keywords

| Sub-Domain | Primary Keywords | Secondary Keywords |
|------------|-----------------|-------------------|
| API Design | REST, GraphQL, gRPC, endpoint | versioning, pagination, rate limiting, contract-first, OpenAPI |
| Service Architecture | microservice, monolith, DDD | bounded context, saga, choreography, anti-corruption layer |
| Concurrency & Performance | thread pool, async, reactive | backpressure, circuit breaker, bulkhead, connection pool |
| Data Access | ORM, repository, CQRS | event sourcing, read model, cache invalidation, write-through |
| Convention Verification | convention, code style, naming rule | JPA pattern, entity model, dynamic update, import rule |
| Implementation Guide | implement, code pattern, feign client | translator code, event implementation, saga implementation |
| Test Strategy | test strategy, test technique, coverage target | property-based, contract test, test planning, layer mapping |
| Test Generation | generate test, write test, test code | focal context, type-driven, pattern matching, test file |
| Test Quality | test quality, coverage, mutation | validation pipeline, gap analysis, kill rate, quality score |

### Multi-Domain Detection Rules

```
IF 2+ sub-domains match within same system:
  pattern = "multi" (unless already "cross")
  domains = [all matching sub-domain codes]
  Sort domains by match score descending

IF only 1 sub-domain matches:
  pattern = "single" (unless already "cross")
  domains = [matching sub-domain code]
```

---

## Step 4: LLM Classification (Ambiguous Queries)

Triggered when:
- confidence < 0.85 from keyword matching
- No keywords matched (score = 0 for all systems)
- Query is in a non-English language and keyword matching underperforms

### LLM Classification Prompt

```
You are a query classifier for an engineering architecture decision system.

Given the user query below, classify it into:
1. systems: one or more of [DB, BE, IF, SE]
2. domains: specific sub-domains within each system
3. pattern: "single" (1 domain), "multi" (2-3 domains, same system), "cross" (multiple systems)
4. confidence: your confidence in this classification (0.0 - 1.0)

## System Definitions
- DB: Database internals, storage engines, query optimization, schema design, replication, sharding, concurrency control
- BE: Backend application design, APIs, service architecture, DDD, resilience patterns, testing conventions
- IF: Infrastructure, deployment, containers, kubernetes, CI/CD, load balancing, CDN, DNS, monitoring, scaling, networking
- SE: Security, authentication, authorization, encryption, key management, RBAC/ABAC, zero-trust, compliance, vulnerability

## User Query
{query}

Respond in JSON format only.
```

### Confidence Thresholds After LLM

> **Note**: These thresholds apply to the LLM fallback path only. The keyword
> fast-path (`classify-query.sh`) uses a separate fixed-tier system: 0.85
> (single system + sub-domain), 0.70 (single system), 0.60 (multi-system).
> Error code EW-CLF-002 triggers at fast-path confidence < 0.60.

| LLM Confidence | Action |
|----------------|--------|
| >= 0.70 | Proceed with classification |
| 0.50 - 0.69 | Proceed but add caveat to output: "Classification confidence is moderate" |
| < 0.50 | Ask user for domain clarification before proceeding |

---

## Step 5: Pattern Cache Lookup

Before running keyword matching, check the pattern cache for known queries.

```
cache_path = ~/.claude/cache/engineering-workflow/pattern-cache.json

1. Compute query signature: lowercase, strip punctuation, sort words
2. Lookup signature in pattern-cache.json
3. IF found AND cache entry has count >= 3:
   → Return cached classification with confidence = 1.0
4. IF not found:
   → Proceed with keyword matching (Step 2)
5. After classification completes:
   → Append to session-history.jsonl
   → If same signature appears 3+ times in history: promote to pattern-cache.json
```

### Cache Entry Format

```json
{
  "signature": "b-tree design index lsm storage write",
  "classification": {
    "systems": ["DB"],
    "domains": ["A"],
    "pattern": "single",
    "confidence": 1.0
  },
  "hit_count": 5,
  "last_used": "2026-02-12T10:30:00Z"
}
```

---

## Step 6: Final Classification Assembly

Merge all detection results into the final classification object.

```
1. Start with keyword-based detection (Step 2)
2. Overlay explicit flags (Step 1) — flags always win
3. Apply LLM correction if triggered (Step 4)
4. Determine depth:
   - Default: "deep"
   - If --depth specified: use that
   - If query length < 10 words AND single-domain: suggest "shallow"
5. Determine mode:
   - From explicit prefix (Step 1), or default "query"
6. Assemble final classification JSON
7. Log to session-history.jsonl
```

### Validation Rules

```
ASSERT systems is non-empty
ASSERT domains is non-empty
ASSERT pattern in {"single", "multi", "cross"}
ASSERT confidence in [0.0, 1.0]
IF pattern == "cross": ASSERT len(systems) >= 2
IF pattern == "single": ASSERT len(domains) == 1
IF pattern == "multi": ASSERT len(domains) >= 2 AND len(set(system for d in domains)) == 1
```

---

## Edge Cases

### Ambiguous Cross-Domain Queries

Some queries naturally span domains without clear boundaries:

| Query | Classification | Rationale |
|-------|---------------|-----------|
| "database performance" | DB-B (single) | "Performance" in DB context maps to query optimization |
| "API performance" | BE-Concurrency (single) | "Performance" in API context maps to concurrency |
| "system performance" | DB-B + BE-Concurrency + IF-Scaling (cross) | Broad "system" triggers multi-system |
| "security best practices" | SE (all sub-domains, multi) | Too broad for single domain |

### Language-Specific Handling

The `classify-query.sh` script handles English keywords only. For non-English queries:
1. Keyword matching runs on any English technical terms present
2. If no English terms found, confidence will be 0.0
3. LLM classification (Step 4) handles non-English queries natively
