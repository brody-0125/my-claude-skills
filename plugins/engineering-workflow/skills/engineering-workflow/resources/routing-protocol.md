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

### Scoring Algorithm (2-Phase)

Classification uses a 2-phase scoring pipeline implemented in `_common.sh`:

**Phase 1 — Binary keyword grep (fast path)**:
Each system has a dedicated keyword set. A grep match gives a binary 1/0 score per system.

**Phase 2 — Cross-keyword weighted scoring**:
~14 cross-system keyword groups (from the matrix above) are tested via `score_cross_keywords()`.
Each group contributes weighted scores to multiple systems (e.g., "replication|failover" → DB=0.80, IF=0.24).
Scores accumulate into `_EW_DB_SCORE`, `_EW_BE_SCORE`, `_EW_IF_SCORE`, `_EW_SE_SCORE`.

**Gap and Dominance** (computed when Phase 2 is active):
```
scores = [DB_SCORE, BE_SCORE, IF_SCORE, SE_SCORE]
max1 = highest score
max2 = second highest score
gap = max1 - max2
dominance = max1 / (max1 + max2)    # 0.5-1.0 range
```

**Confidence calculation** (`compute_confidence()` in `_common.sh`):

```
IF total_matches == 0 AND Phase 2 inactive:
  confidence = 0.0      → no keywords matched, fall through to LLM

IF Phase 2 inactive (no cross-keywords matched):
  # Fast path: fixed tiers (original behavior preserved)
  IF total_matches == 1 AND has_subdomain:  confidence = 0.85
  ELIF total_matches == 1:                   confidence = 0.70
  ELIF total_matches >= 2:                   confidence = 0.60

IF Phase 2 active (cross-keywords matched):
  # Continuous confidence from gap/dominance
  IF total_matches == 1:
    confidence = 0.70 + (dominance - 0.5) × 0.40 + subdomain_bonus(0.10)
    # Range: 0.70-1.00; high dominance → high confidence
  ELIF total_matches >= 2:
    confidence = 0.60 + gap × 0.30    # capped at 0.69
    # Multi-system stays below 0.70 threshold
```

**System selection when Phase 1 has 0 hits but Phase 2 found cross-keywords**:
- If gap >= 0.3: use only the dominant system
- If gap < 0.3: include all systems with score > 0

All systems with at least one keyword match are included in the output `systems[]` array.

### LLM Verification Flag (Enhancement 1-3)

When keyword classification produces confidence > 0.0 but < 0.85, the output includes
`needs_llm_verification: true` and a context-specific `verification_prompt` for LLM
confirmation. This bridges the gap between deterministic fast-path and full LLM fallback.

```
IF confidence > 0.0 AND confidence < 0.85:
  needs_llm_verification = true
  verification_prompt = context-specific prompt based on system count:
    - 0 systems: "Classify into [DB,BE,IF,SE]"
    - 1 system:  "Verify and suggest if other systems apply"
    - 2+ systems: "Confirm primary system(s) and relevance"
ELSE:
  needs_llm_verification = false
  verification_prompt = null
```

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
| Distributed & Replication | F | replication, failover, sharding, shard key, dynamodb, rcu, wcu, hot partition, adaptive capacity, throttling | consensus, raft, paxos, distributed transaction, resharding, provisioned throughput, on-demand, tps |

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
> fast-path (`classify-query.sh`) uses a 2-phase scoring system: Phase 1 fixed
> tiers (0.85/0.70/0.60) when no cross-keywords match; Phase 2 continuous
> confidence (0.60-1.00) based on gap/dominance when cross-keywords are present.
> Error code EW-CLF-002 triggers at fast-path confidence < 0.60.

| LLM Confidence | Action |
|----------------|--------|
| >= 0.70 | Proceed with classification |
| 0.50 - 0.69 | Proceed but add caveat to output: "Classification confidence is moderate" |
| < 0.50 | Ask user for domain clarification before proceeding |

---

## Step 4.5: LLM Verification (Mid-Confidence Classification)

Triggered when `needs_llm_verification == true` (keyword classification produced 0.0 < confidence < 0.85).
This is a lightweight single-turn LLM check — NOT a full LLM classification (Step 4).

### Purpose

Keyword classification sometimes underclassifies (misses a relevant system) or overclassifies
(includes a tangential system). LLM verification catches these errors before agent dispatch,
preventing wasted orchestrator invocations.

### Protocol

```
1. Input: keyword classification result + verification_prompt (generated by classify-query.sh)
2. Execute a single-turn LLM evaluation using the verification_prompt:

   Verification prompt templates (from classify-query.sh):
   - 0 systems matched: "Classify into [DB,BE,IF,SE]"
   - 1 system matched:  "Verify {system} and suggest if other systems apply"
   - 2+ systems matched: "Confirm primary system(s) and relevance of {systems}"

3. Compare LLM response with keyword classification:

   IF LLM agrees with keyword classification:
     → confidence += 0.10 (capped at 0.85)
     → classifier = "keyword+llm-confirmed"
     → Proceed to Step 5

   IF LLM disagrees (different systems or additional systems):
     → Adopt LLM classification for systems[]
     → Re-run sub-domain detection (Step 3) for new systems
     → Set classifier = "llm-verified"
     → Set confidence = LLM-provided confidence (apply Step 4 thresholds)
     → Proceed to Step 5
```

### Token Budget

- Single-turn prompt: ~150 tokens input, ~100 tokens output
- Total: ~0.2K per verification
- No reference loading required

### When to Skip

- `EW_PROGRESSIVE_CLASSIFICATION=0` does NOT disable this step (it only disables session context)
- Skip if token pressure > 90% (proceed with keyword classification as-is)
- Skip if `--domain` flag was explicitly set by user (confidence already 1.0)

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

## Step 5.5: Progressive Classification

When session history is available, the classifier augments the current classification with
prior context. This improves routing accuracy for conversational follow-up queries.

### Mechanism

```
1. Read last 5 entries from session-history.jsonl within 30-minute window
2. Compute prior_boost: overlap between current systems and recent history
   - boost = min(0.10, Σ(overlap_ratio × time_decay))
   - time_decay: most recent = 1.0, each older entry ×= 0.7
   - INVARIANT: if TOTAL_MATCHES == 0 (no keyword match), boost = 0
3. Lookup transition patterns in pattern-cache.json.__transitions__
   - Find frequent from→to system/domain transitions
   - transition_confidence = count / total_from_source (threshold: 0.20)
4. Add to output:
   - prior_boost: float (0.00-0.10)
   - suggested_expansions[]: array of expansion suggestions from transition history
```

### Output Fields

```json
{
  "prior_boost": 0.05,
  "suggested_expansions": [
    {
      "add_system": "DB",
      "add_cluster_or_domain": "F",
      "reason": "DB-F → BE-R 전환 7회 관측 (transition_confidence=0.70)",
      "transition_confidence": 0.70
    }
  ]
}
```

### Rollback

Set environment variable `EW_PROGRESSIVE_CLASSIFICATION=0` to disable progressive
classification entirely. All progressive fields will output default values (0, []).

---

## Step 6: Final Classification Assembly

Merge all detection results into the final classification object.

```
1. Start with keyword-based detection (Step 2)
2. Overlay explicit flags (Step 1) — flags MUST win
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
