# Isolation Level Reference — c1-isolation-advisor Agent

<!--
  Agent: c1-isolation-advisor
  Purpose: Provides isolation level theory, anomaly classification, SI vs SSI comparison,
           distributed DB isolation strategies (Spanner, CockroachDB), and workload-to-isolation
           decision guidance.
  Source: Extracted and enriched from domain-c-concurrency.md sections 1, 3, 7 (partial), 8 (partial).
-->

---

## 1. SQL Standard Isolation Levels

| Level | Dirty Read | Non-Repeatable Read | Phantom Read | Serialization Anomaly |
|-------|-----------|--------------------|--------------|-----------------------|
| **Read Uncommitted** | Possible | Possible | Possible | Possible |
| **Read Committed** | Prevented | Possible | Possible | Possible |
| **Repeatable Read** | Prevented | Prevented | Possible* | Possible* |
| **Serializable** | Prevented | Prevented | Prevented | Prevented |

*InnoDB's Repeatable Read prevents phantoms via gap locks. PostgreSQL's Repeatable Read prevents phantoms via snapshot isolation but allows write skew.

### Default Isolation Levels by Database

| Database | Default Level | Notes |
|----------|--------------|-------|
| PostgreSQL | Read Committed | Configurable per transaction |
| MySQL/InnoDB | Repeatable Read | Includes gap locking for phantom prevention |
| Oracle | Read Committed | Serializable available but rarely used |
| SQL Server | Read Committed | Snapshot isolation available as alternative |
| CockroachDB | Serializable | Only level available, enforced globally |

### Configuring Isolation per Transaction

```sql
-- PostgreSQL: set per-transaction isolation
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT * FROM orders WHERE customer_id = 42;
-- all reads within this TX see the same snapshot
COMMIT;

-- MySQL/InnoDB: set per-session or per-transaction
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- OR
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;  -- next TX only
START TRANSACTION;
SELECT * FROM orders WHERE customer_id = 42;
COMMIT;

-- SQL Server: enable snapshot isolation (requires DB-level opt-in)
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
SELECT * FROM orders WHERE customer_id = 42;
COMMIT;
```

---

## 2. Anomaly Definitions and Demonstrations

### Dirty Read

Transaction T2 reads data written by T1 before T1 commits. If T1 rolls back, T2 has read non-existent data.

```sql
-- Session 1 (T1)                          -- Session 2 (T2, Read Uncommitted)
BEGIN;                                       SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
UPDATE accounts SET balance = 0             BEGIN;
  WHERE id = 1;  -- was 1000                SELECT balance FROM accounts WHERE id = 1;
                                            -- => 0 (dirty: T1 not yet committed)
ROLLBACK;                                   -- T2 acted on phantom balance
                                            COMMIT;
```

### Non-Repeatable Read

```sql
-- Session 1 (T1, Read Committed)          -- Session 2 (T2)
BEGIN;
SELECT balance FROM accounts WHERE id = 1;
-- => 1000
                                            BEGIN;
                                            UPDATE accounts SET balance = 500 WHERE id = 1;
                                            COMMIT;
SELECT balance FROM accounts WHERE id = 1;
-- => 500 (different on second read!)
COMMIT;
```

### Phantom Read

```sql
-- Session 1 (T1, Read Committed)          -- Session 2 (T2)
BEGIN;
SELECT count(*) FROM orders
  WHERE status = 'pending';
-- => 5
                                            BEGIN;
                                            INSERT INTO orders (status) VALUES ('pending');
                                            COMMIT;
SELECT count(*) FROM orders
  WHERE status = 'pending';
-- => 6 (phantom row appeared)
COMMIT;
```

### Write Skew

The most subtle anomaly — not prevented by Snapshot Isolation alone:

```sql
-- Constraint: at least 1 doctor must be on call
-- doctors_on_call table: {doctor_a: on_call=true, doctor_b: on_call=true}

-- Session 1 (T1, Repeatable Read)          -- Session 2 (T2, Repeatable Read)
BEGIN;                                       BEGIN;
SELECT count(*) FROM doctors_on_call
  WHERE on_call = true;
-- => 2 (safe to remove one)
                                            SELECT count(*) FROM doctors_on_call
                                              WHERE on_call = true;
                                            -- => 2 (safe to remove one)
UPDATE doctors_on_call
  SET on_call = false
  WHERE doctor = 'A';
                                            UPDATE doctors_on_call
                                              SET on_call = false
                                              WHERE doctor = 'B';
COMMIT;                                     COMMIT;
-- Result: 0 doctors on call — CONSTRAINT VIOLATED
-- Fix: Use SERIALIZABLE or explicit locking
```

---

## 3. Snapshot Isolation vs Serializable

### Snapshot Isolation (SI)

- Each transaction reads from a consistent snapshot taken at start
- Writes go to private workspace, committed atomically
- **First-Committer-Wins (FCW)**: If two transactions write same row, second one aborts
- Prevents: dirty reads, non-repeatable reads, phantoms (for reads)
- Does NOT prevent: write skew (transactions write to different rows based on stale reads)

### Serializable Snapshot Isolation (SSI) — PostgreSQL

- Extends SI with additional tracking to detect serialization conflicts
- Tracks: read-write dependencies between concurrent transactions
- Uses: SIREAD locks (predicate locks) that do not block, only record dependencies
- Detects: "dangerous structure" in dependency graph (pivot = T1 reads what T2 writes, T2 reads what T3 writes)
- On detection: aborts one transaction with serialization failure (40001)
- False positives: May abort transactions that would not actually cause anomalies

### Practical Comparison

| Aspect | Snapshot Isolation | Serializable (SSI) |
|--------|-------------------|-------------------|
| Read performance | Excellent (no blocking) | Good (SIREAD lock overhead ~5-10%) |
| Write skew | Not prevented | Prevented |
| Abort rate | Low (only write-write conflicts) | Higher (includes rw-dependency aborts) |
| Use case | Most OLTP applications | Financial, inventory, booking systems |
| Implementation | PostgreSQL RR, MySQL RR | PostgreSQL Serializable, CockroachDB |
| Retry needed | Rarely | Yes, application must handle 40001 errors |

### Handling Serialization Failures in Application Code

```python
# Python/psycopg2 example: retry loop for SSI
import psycopg2
from psycopg2 import extensions

MAX_RETRIES = 3

def transfer_funds(conn_params, from_id, to_id, amount):
    for attempt in range(MAX_RETRIES):
        conn = psycopg2.connect(**conn_params)
        conn.set_isolation_level(extensions.ISOLATION_LEVEL_SERIALIZABLE)
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT balance FROM accounts WHERE id = %s", (from_id,))
                balance = cur.fetchone()[0]
                if balance < amount:
                    raise ValueError("Insufficient funds")
                cur.execute("UPDATE accounts SET balance = balance - %s WHERE id = %s",
                            (amount, from_id))
                cur.execute("UPDATE accounts SET balance = balance + %s WHERE id = %s",
                            (amount, to_id))
            conn.commit()
            return  # success
        except psycopg2.errors.SerializationFailure:
            conn.rollback()
            if attempt == MAX_RETRIES - 1:
                raise
            # exponential backoff recommended here
        finally:
            conn.close()
```

---

## 4. Distributed Database Isolation Strategies

### Google Spanner: TrueTime + External Consistency

**External Consistency (Linearizability)**
- If T1 commits before T2 starts, T1's commit timestamp < T2's commit timestamp
- Implementation: T1 waits for TrueTime uncertainty interval before committing
- Wait time = `TT.now().latest - TT.now().earliest` (typically 1-7ms)
- This "commit wait" ensures timestamp ordering matches real-time ordering

**Concurrency Protocol**
- Paxos groups for replication within each partition
- Two-Phase Commit (2PC) for cross-partition transactions
- Read-only transactions: assigned timestamp without locks, served from any replica
- Read-write transactions: acquire locks, assigned timestamp at commit, replicated via Paxos

**Quantitative Data**
- Median read latency: 5-10ms (within region), 50-100ms (cross-region)
- Write latency: 10-50ms (includes commit wait + Paxos replication)
- Typical TrueTime uncertainty: <7ms (with atomic clock + GPS)

### CockroachDB: Serializable by Default

**Design Philosophy**
- Only supports Serializable isolation (no weaker levels)
- "If you're going to pick one isolation level, it should be the strongest"
- Eliminates entire classes of concurrency bugs at the database level

**Implementation: HLC (Hybrid Logical Clock)**
- Combines physical clock with logical counter
- HLC timestamp: (physical_time, logical_counter, node_id)
- Ensures causal ordering without TrueTime hardware
- Clock skew tolerance: max_offset = 500ms (default), transactions aborted if exceeded

**Concurrency Protocol**
- Serializable Snapshot Isolation (SSI) variant
- Write intents: uncommitted writes visible as "intents" in key-value store
- Serializable overhead vs hypothetical SI: ~5-10% throughput reduction
- Retry rate: typically <1% for well-designed workloads
- Recommended: keep transactions short (<100ms), retry with exponential backoff

```sql
-- CockroachDB: all transactions are serializable, no configuration needed
BEGIN;
SELECT balance FROM accounts WHERE id = 1;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;
-- If a serialization conflict occurs, the client receives:
-- ERROR: restart transaction (SQLSTATE 40001)
-- Application MUST implement retry logic
```

---

## 5. Isolation Verification Queries

```sql
-- PostgreSQL: check current isolation level
SHOW default_transaction_isolation;
SHOW transaction_isolation;  -- within a transaction

-- MySQL/InnoDB: check isolation level
SELECT @@global.transaction_isolation;
SELECT @@session.transaction_isolation;

-- PostgreSQL: monitor serialization failures
SELECT count(*) AS serialization_failures
FROM pg_stat_database
WHERE datname = current_database();
-- Check pg_stat_user_tables for conflict-related aborts

-- PostgreSQL: identify long-running transactions that might cause issues
SELECT pid, now() - xact_start AS duration, state, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC
LIMIT 10;
```

---

## 6. Decision Matrix — Workload to Isolation Strategy

| Workload Type | Recommended Isolation | Rationale |
|--------------|----------------------|-----------|
| Read-heavy analytics | Read Committed + read replicas | Maximize read throughput, no anomaly risk on reads |
| Standard OLTP | Read Committed | Balance of performance and safety |
| Financial transactions | Serializable | No anomalies tolerated, worth retry overhead |
| Inventory / booking | Repeatable Read + row locking | Prevent overselling; combine with FOR UPDATE NOWAIT |
| Low-contention CRUD | Read Committed | Minimal overhead; use optimistic locking at app layer |
| Global consistency | Serializable (Spanner / CRDB) | External consistency required across regions |

### Quick Selection Flowchart

```
Can your app tolerate write skew?
├── YES → Read Committed (default for PostgreSQL, Oracle)
│         └── Need repeatable reads within TX?
│             ├── YES → Repeatable Read
│             └── NO  → Read Committed is sufficient
└── NO  → Does the app span multiple regions?
          ├── YES → Spanner or CockroachDB (Serializable built-in)
          └── NO  → PostgreSQL Serializable + retry logic
```

### Isolation Level Overhead Comparison

| Isolation Level | Lock Overhead | MVCC Overhead | Retry Overhead | Total Impact |
|----------------|--------------|---------------|---------------|-------------|
| Read Committed | Minimal | Snapshot per statement | None | Baseline |
| Repeatable Read | Gap locks (InnoDB) | Snapshot per TX | Rare | +2-5% |
| Serializable (SSI) | SIREAD predicate locks | Snapshot per TX + dependency tracking | ~1-5% of TXs | +5-15% |
| Serializable (2PL) | Full read/write locks | N/A | Deadlock retries | +15-30% |

---

## 7. Academic References

1. **Berenson et al. (1995)** — "A Critique of ANSI SQL Isolation Levels" — SIGMOD'95. Defines snapshot isolation, write skew
2. **Cahill et al. (2009)** — "Serializable Isolation for Snapshot Databases" — SIGMOD'09. SSI algorithm used in PostgreSQL
3. **Corbett et al. (2013)** — "Spanner: Google's Globally-Distributed Database" — ACM TOCS. TrueTime + external consistency
4. **Taft et al. (2020)** — "CockroachDB: The Resilient Geo-Distributed SQL Database" — SIGMOD'20. HLC + serializable-by-default
5. **Fekete et al. (2005)** — "Making Snapshot Isolation Serializable" — ACM TODS. Theoretical foundation for SSI

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
