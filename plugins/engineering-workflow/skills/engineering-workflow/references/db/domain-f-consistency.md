# Distributed Database: Consistency Models & Conflict Resolution Reference
<!-- Agent: f2-consistency-selector -->
<!-- Scope: Consistency models, conflict resolution, CAP/PACELC, practical trade-offs -->
<!-- Split from: domain-f-distributed.md -->

> Static reference for the **f2-consistency-selector** agent.
> Covers consistency model hierarchy, CAP/PACELC frameworks, conflict resolution
> mechanisms, and practical examples demonstrating consistency trade-offs.

---

## 1. Consistency Models

### Hierarchy (Strongest to Weakest)

```
Linearizability (Strongest)
    │
Sequential Consistency
    │
Causal Consistency
    │
Eventual Consistency (Weakest)
```

**Linearizability** -- Every operation appears instantaneous between invocation and response. All clients see the same order. Examples: Spanner, CockroachDB.

**Sequential Consistency** -- Operations of each process appear in program order, all see same total order, but need not respect wall-clock time.

**Causal Consistency** -- Causally related ops seen in same order everywhere; concurrent ops may differ. Examples: COPS, MongoDB sessions.

**Eventual Consistency** -- All replicas converge if no new updates; no ordering guarantees during convergence. Examples: DynamoDB, Cassandra, DNS.

### Practical Example: Consistency Levels in Action

```
Writer:   W(x=1) at T1        W(x=2) at T3
          ─────●─────────────────●──────────────>

Reader A (Linearizable):
          ─────────●(x=1)───────────●(x=2)────> always latest

Reader B (Sequential):
          ─────────●(x=1)──●(x=1)──●(x=2)────> in order, may lag

Reader C (Eventual):
          ─────●(x=0)──●(x=0)──●(x=1)──●(x=2)> stale, then converges
```

#### Cassandra Tunable Consistency

```cql
-- QUORUM write + QUORUM read: guarantees reading latest (W+R > N)
INSERT INTO users (user_id, name, email) VALUES (uuid(), 'Alice', 'alice@ex.com')
USING CONSISTENCY QUORUM;

SELECT * FROM users WHERE user_id = ? USING CONSISTENCY QUORUM;

-- ONE: fastest but may return stale data
SELECT * FROM users WHERE user_id = ? USING CONSISTENCY ONE;

-- ALL: highest durability, lowest availability
INSERT INTO users (user_id, name, email) VALUES (uuid(), 'Bob', 'bob@ex.com')
USING CONSISTENCY ALL;
```

#### MongoDB Read/Write Concern

```javascript
// Strong consistency: majority write + majority read
db.orders.insertOne(
  { orderId: "ORD-123", status: "placed", total: 99.50 },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
);
db.orders.find({ orderId: "ORD-123" }).readConcern("majority");

// Causal consistency via sessions
const session = db.getMongo().startSession({ causalConsistency: true });
const col = session.getDatabase("shop").orders;
col.insertOne({ orderId: "ORD-456", status: "placed" });
col.findOne({ orderId: "ORD-456" }); // guaranteed to see the write
session.endSession();

// Linearizable read (strongest)
db.orders.find({ orderId: "ORD-123" }).readConcern("linearizable");
```

---

## 2. CAP Theorem and PACELC

**CAP** (Brewer, 2000): Consistency + Availability + Partition tolerance -- pick two. Since partitions are unavoidable, real choice is CP vs AP.

| Category | During Partition | Examples |
|----------|-----------------|----------|
| CP | Reject writes for consistency | Spanner, CockroachDB, HBase, MongoDB |
| AP | Accept writes, resolve later | Cassandra, DynamoDB, CouchDB, Riak |

**PACELC** (Abadi, 2012): If Partition -> A or C; Else -> Latency or Consistency.

| System | P+A/P+C | E+L/E+C | Classification |
|--------|---------|---------|----------------|
| DynamoDB | PA | EL | PA/EL |
| Cassandra | PA | EL | PA/EL (tunable) |
| Spanner | PC | EC | PC/EC |
| MongoDB | PC | EC | PC/EC |
| PostgreSQL | PC | EL | PC/EL |

```
Network partition scenario:

  ┌─────────────┐   XXXXX   ┌─────────────────────┐
  │  Node A     │   XXXXX   │  Node B    Node C   │
  │  (leader)   │           │  (replicas)         │
  └─────────────┘           └─────────────────────┘

CP (CockroachDB): Node A rejects writes (no majority). B/C elect new leader.
AP (Cassandra CL=ONE): All nodes accept writes independently. Resolve on heal.
```

---

## 3. Conflict Resolution

### Last-Write-Wins (LWW)
- Highest timestamp wins; simple but causes silent data loss on concurrent writes
- Requires synchronized clocks (NTP) or logical timestamps
- Used by: Cassandra (default), DynamoDB (conditional writes as alternative)

### Vector Clocks
- Per-node counter vector: `{A:3, B:2, C:5}`. Concurrent if neither dominates.
- On conflict: return both versions for application-level resolution
- Used by: Riak (previously), Amazon Dynamo (original paper)

```
Initial: x = {value: "A", clock: {N1:0, N2:0}}

Client writes x="B" to N1:  clock {N1:1, N2:0}
Client writes x="C" to N2:  clock {N1:0, N2:1}  (concurrent)

Read discovers both: neither dominates -> CONFLICT
App resolves -> x="B+C", clock {N1:1, N2:1, N3:1}
```

### CRDTs (Conflict-free Replicated Data Types)
- Data structures that always merge without conflicts
- Types: G-Counter, PN-Counter, G-Set, OR-Set, LWW-Register, MV-Register
- Strong eventual consistency; limited data types + space overhead
- Used by: Redis (active-active), Riak, Automerge

```python
class GCounter:
    """Grow-only counter: each node increments its own slot."""
    def __init__(self, node_id, state=None):
        self.node_id = node_id
        self.state = state or {}

    def increment(self, n=1):
        self.state[self.node_id] = self.state.get(self.node_id, 0) + n

    def value(self):
        return sum(self.state.values())

    def merge(self, other):
        all_nodes = set(self.state) | set(other.state)
        return GCounter(self.node_id,
            {n: max(self.state.get(n,0), other.state.get(n,0)) for n in all_nodes})

# {A:3} merge {B:2} -> value = 5 (order-independent)
```

---

## 4. Case Studies

### Google Spanner: External Consistency via TrueTime

- TrueTime returns interval `[earliest, latest]`; commit wait ensures timestamp ordering
- Provides linearizability across geographically distributed datacenters

```sql
-- Strong read (default): always latest committed data
SELECT * FROM Accounts WHERE account_id = 'acc-001';

-- Stale read: bounded staleness for lower latency (served by nearest replica)
SELECT * FROM Accounts WHERE account_id = 'acc-001'
OPTIONS (read_timestamp = TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 SECOND));
```

- TrueTime uncertainty: 1-7ms; single-region write: 5-10ms; stale read: <5ms

### CockroachDB: Serializable Isolation with Raft

- Ranges replicated via Raft; serializable via MVCC + timestamp ordering

```sql
-- Default serializable isolation; automatic retry on conflict
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Follower reads: trade staleness for latency
SET CLUSTER SETTING kv.closed_timestamp.target_duration = '3s';
BEGIN AS OF SYSTEM TIME follower_read_timestamp();
SELECT * FROM accounts WHERE region = 'eu-west';
COMMIT;
```

```sql
-- Geo-partitioning for compliance (GDPR) + latency
ALTER TABLE users PARTITION BY LIST (region) (
    PARTITION us_east VALUES IN ('us-east-1', 'us-east-2'),
    PARTITION eu_west VALUES IN ('eu-west-1', 'eu-west-2')
);
ALTER PARTITION us_east OF INDEX users@primary CONFIGURE ZONE USING
    constraints = '[+region=us-east]';
```

- Single-region write: 2-10ms; multi-region: ~2x RTT; follower reads: <5ms (3s stale)

---

## 5. Decision Matrix

### Consistency Requirement to Protocol

| Consistency Need | Protocol | Trade-off | Example |
|-----------------|----------|-----------|---------|
| Linearizability | Raft/Paxos | Higher write latency (~1 RTT) | CockroachDB, Spanner |
| Causal | Logical clocks + tracking | Metadata overhead | MongoDB sessions |
| Read-your-writes | Session stickiness | May hit primary only | PostgreSQL sync |
| Eventual | Async replication | Stale reads possible | Cassandra |
| Strong eventual | CRDTs | Limited data types | Redis Enterprise |

### Conflict Resolution Strategy

| Factor | LWW | Vector Clocks | CRDTs | App-Level |
|--------|-----|--------------|-------|-----------|
| Complexity | Low | Medium | Medium-High | High |
| Data loss risk | High | None | None | None |
| Clock dependency | NTP | Logical | None | Varies |
| Best for | Cache, non-critical | Shopping carts | Counters, sets | Domain-specific |

### Consistency vs Performance

| Configuration | Write Latency | Read Latency | Data Loss Risk | Availability |
|--------------|---------------|-------------|----------------|-------------|
| Sync all replicas | Highest (~N RTT) | Lowest | None | Lowest |
| Semi-sync (1) | Medium (~1 RTT) | Low | Minimal | High |
| Async | Lowest | Low | Possible | Highest |
| Quorum W=2,R=2,N=3 | Medium (~1 RTT) | Medium | None | High |

### Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|-------------|---------|----------------|
| Eventual consistency for financial txns | Lost updates, double-spending | Serializable isolation |
| Ignoring replication lag in read-after-write | Stale reads after user write | Session stickiness or sync read |
| NTP-only LWW across regions | Clock skew picks wrong winner | Hybrid logical clocks |
| CP without latency evaluation | Degraded normal-case response | Evaluate PACELC trade-offs |
| Geo-replication without conflict strategy | Silent data loss | Define resolution before deploying |

---

## 6. References

1. **Corbett et al. (2013)** -- "Spanner: Google's Globally-Distributed Database" -- ACM TOCS
2. **Taft et al. (2020)** -- "CockroachDB: The Resilient Geo-Distributed SQL Database" -- SIGMOD'20
3. **Shapiro et al. (2011)** -- "Conflict-free Replicated Data Types" -- SSS'11
4. **Abadi (2012)** -- "Consistency Tradeoffs in Modern Distributed Database System Design" -- IEEE Computer
5. **Lloyd et al. (2011)** -- "COPS: Scalable Causal Consistency" -- SOSP'11
6. **DeCandia et al. (2007)** -- "Dynamo" -- SOSP'07

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
