# Locking and Deadlock Reference — c3-lock-designer Agent

<!--
  Agent: c3-lock-designer
  Purpose: Provides lock type theory, deadlock detection/prevention, optimistic vs pessimistic
           strategy guidance, lock monitoring queries, and practical locking patterns.
  Source: Extracted and enriched from domain-c-concurrency.md sections 4, 5, 6.
-->

---

## 1. Lock Types

### Lock Granularity Hierarchy (InnoDB)

```
Table-level
  └── Intent Locks (IS, IX)
       └── Page-level (implicit in InnoDB, explicit in SQL Server)
            └── Row-level
                 ├── Record Lock (locks index record)
                 ├── Gap Lock (locks gap before index record)
                 └── Next-Key Lock (record + gap before it)
```

### Lock Types Detailed

**Shared (S) Lock**
- Allows concurrent reads, blocks writes
- Acquired by: `SELECT ... FOR SHARE` (PostgreSQL), `SELECT ... LOCK IN SHARE MODE` (MySQL)

**Exclusive (X) Lock**
- Blocks both reads-for-update and writes
- Acquired by: `SELECT ... FOR UPDATE`, `INSERT`, `UPDATE`, `DELETE`

**Intent Locks (IS, IX)**
- Table-level indicators of row-level lock intent
- Purpose: Avoid checking every row when requesting table-level lock
- IS: "Some rows have S locks" — compatible with IS, IX, S
- IX: "Some rows have X locks" — compatible with IS, IX only

**Gap Lock (InnoDB)**
- Locks the gap between index records (prevents phantom inserts)
- Only in Repeatable Read and Serializable isolation
- Purpose: Prevents other transactions from inserting into the locked gap

**Next-Key Lock (InnoDB)**
- Combination: record lock + gap lock on the gap before the record
- Default locking mode for InnoDB in Repeatable Read
- Prevents phantoms without requiring table-level locks

### Lock Acquisition Examples

```sql
-- Shared lock: multiple readers, block writers
-- PostgreSQL
SELECT * FROM orders WHERE id = 42 FOR SHARE;
-- MySQL
SELECT * FROM orders WHERE id = 42 LOCK IN SHARE MODE;

-- Exclusive lock: single writer, block all others
SELECT * FROM orders WHERE id = 42 FOR UPDATE;

-- Gap lock demonstration (InnoDB, Repeatable Read)
-- Given records at id = 5, 10, 15:
SELECT * FROM orders WHERE id BETWEEN 10 AND 20 FOR UPDATE;
-- Locks: record at id=10, gap (10,15), record at id=15, gap (15, next)
-- Another TX cannot INSERT id=12 until this lock is released

-- Next-key lock: records at id=5, 10, 15
-- Locking id=10 creates next-key lock on (5, 10]
-- The gap (5,10) is locked AND the record at 10 is locked
```

### Lock Compatibility Matrix (InnoDB Row-Level)

| Request \ Held | S | X | Gap | Next-Key |
|---------------|---|---|-----|----------|
| **S** | OK | Wait | OK | Wait (on record part) |
| **X** | Wait | Wait | OK | Wait |
| **Gap** | OK | OK | OK | OK |
| **Next-Key** | Wait (record) | Wait | OK | Wait |

Note: Gap locks are compatible with each other (they only prevent inserts, not other gap locks).

---

## 2. Lock Monitoring Queries

### PostgreSQL Lock Monitoring

```sql
-- View all current locks with human-readable info
SELECT
    l.pid,
    l.locktype,
    l.mode,
    l.granted,
    l.relation::regclass AS table_name,
    a.query,
    a.state,
    age(now(), a.query_start) AS query_duration
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.relation IS NOT NULL
ORDER BY l.granted, a.query_start;

-- Find blocked and blocking sessions
SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query,
    age(now(), blocked.query_start) AS waiting_duration
FROM pg_stat_activity blocked
JOIN pg_locks bl ON blocked.pid = bl.pid AND NOT bl.granted
JOIN pg_locks gl ON bl.relation = gl.relation
    AND bl.locktype = gl.locktype
    AND gl.granted
JOIN pg_stat_activity blocking ON gl.pid = blocking.pid
WHERE blocked.pid != blocking.pid;

-- Advisory lock usage
SELECT * FROM pg_locks WHERE locktype = 'advisory';
```

### InnoDB Lock Monitoring

```sql
-- Current lock waits (MySQL 8.0+ performance_schema)
SELECT
    r.trx_id AS waiting_trx_id,
    r.trx_mysql_thread_id AS waiting_thread,
    r.trx_query AS waiting_query,
    b.trx_id AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_thread,
    b.trx_query AS blocking_query
FROM performance_schema.data_lock_waits w
JOIN information_schema.INNODB_TRX r ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.INNODB_TRX b ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID;

-- Detailed lock information
SELECT
    OBJECT_NAME, INDEX_NAME,
    LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
FROM performance_schema.data_locks
ORDER BY OBJECT_NAME, LOCK_TYPE;

-- Lock wait statistics
SELECT * FROM sys.innodb_lock_waits\G

-- Overall lock metrics
SHOW STATUS LIKE 'Innodb_row_lock%';
-- Key: Innodb_row_lock_current_waits, Innodb_row_lock_time_avg, Innodb_row_lock_waits
```

---

## 3. Deadlock Detection and Prevention

### Wait-For Graph (InnoDB)

- InnoDB maintains a wait-for graph of transaction lock dependencies
- Deadlock detection runs when a transaction must wait for a lock
- If cycle detected: rolls back the transaction with fewest undo log records (least work)
- Detection frequency: immediate (on each lock wait), not periodic

### Timeout-Based (Alternative)

- `innodb_lock_wait_timeout`: Default 50 seconds (InnoDB)
- `lock_timeout`: Configurable per session (PostgreSQL, default 0 = infinite)
- Simpler than graph detection, but causes unnecessary waits
- Useful as safety net even with graph-based detection

### Deadlock Prevention Strategies

| Strategy | Description | Use Case |
|----------|-----------|----------|
| **Lock ordering** | Always acquire locks in consistent order | Application-level discipline |
| **Lock timeout** | Abort if lock not acquired within limit | Fallback safety mechanism |
| **Nowait** | `SELECT ... FOR UPDATE NOWAIT` — fail immediately | Interactive applications |
| **Skip locked** | `SELECT ... FOR UPDATE SKIP LOCKED` — skip locked rows | Job queue processing |
| **Advisory locks** | Application-level named locks | Coordinating business logic |
| **Optimistic control** | Version column check on update | Low-contention workloads |

### Deadlock Analysis

```sql
-- InnoDB: view last detected deadlock
SHOW ENGINE INNODB STATUS\G
-- Find the section: "LATEST DETECTED DEADLOCK"
-- Contains: both transactions, their queries, locks held, locks waited on

-- PostgreSQL: enable deadlock logging
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET deadlock_timeout = '1s';  -- log after 1 second of waiting
SELECT pg_reload_conf();

-- PostgreSQL: search for deadlock events in logs
-- Log entries include: "Process X waits for ShareLock on transaction Y"
-- and "Process Y waits for ExclusiveLock on tuple (page, offset)"

-- InnoDB: proactive monitoring of lock wait chains
SELECT
    r.trx_id waiting_trx,
    r.trx_query waiting_query,
    r.trx_wait_started,
    TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS wait_seconds,
    b.trx_id blocking_trx,
    b.trx_query blocking_query
FROM information_schema.INNODB_TRX r
JOIN performance_schema.data_lock_waits w
    ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.INNODB_TRX b
    ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID
ORDER BY wait_seconds DESC;
```

### Reproducing and Resolving a Deadlock

```sql
-- Classic deadlock scenario:
-- Session 1                                -- Session 2
BEGIN;                                      BEGIN;
UPDATE accounts SET balance = 100           UPDATE accounts SET balance = 200
  WHERE id = 1;  -- X lock on row 1          WHERE id = 2;  -- X lock on row 2

UPDATE accounts SET balance = 200           UPDATE accounts SET balance = 100
  WHERE id = 2;  -- WAITS for row 2          WHERE id = 1;  -- WAITS for row 1
-- DEADLOCK! One session is rolled back.

-- FIX: Always lock in consistent order (e.g., by ascending id)
-- Session 1                                -- Session 2
BEGIN;                                      BEGIN;
SELECT * FROM accounts WHERE id IN (1,2)    SELECT * FROM accounts WHERE id IN (1,2)
  ORDER BY id FOR UPDATE;                     ORDER BY id FOR UPDATE;
-- Both lock id=1 first, then id=2          -- Session 2 waits for id=1 (no deadlock)
UPDATE accounts SET balance = 100 WHERE id = 1;
UPDATE accounts SET balance = 200 WHERE id = 2;
COMMIT;                                     -- Now Session 2 proceeds
                                            UPDATE accounts SET balance = 200 WHERE id = 1;
                                            UPDATE accounts SET balance = 100 WHERE id = 2;
                                            COMMIT;
```

---

## 4. Optimistic vs Pessimistic Concurrency

### Pessimistic Concurrency Control

```sql
-- Acquire lock before reading, hold until commit
BEGIN;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;  -- Lock acquired immediately
-- Perform business logic...
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;  -- Lock released

-- NOWAIT variant: fail immediately if locked
BEGIN;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
-- ERROR: could not obtain lock on row (if locked by another TX)
-- Application catches error and shows "resource busy" to user
COMMIT;
```

- **When to use**: High contention, short transactions, critical consistency
- **Advantage**: No retry logic needed, guaranteed consistency
- **Disadvantage**: Reduced concurrency, potential deadlocks, lock wait overhead

### Optimistic Concurrency Control

```sql
-- Step 1: Read with version
SELECT balance, version FROM accounts WHERE id = 1;
-- Result: balance=1000, version=5

-- Step 2: Application logic (can take time, no lock held)

-- Step 3: Update with version check
UPDATE accounts
SET balance = 900, version = version + 1
WHERE id = 1 AND version = 5;

-- Step 4: Check result
-- If affected_rows = 0 → version changed, someone else updated → RETRY
-- If affected_rows = 1 → success
```

- **When to use**: Low contention, longer transactions, read-heavy workloads
- **Advantage**: No locks held during read phase, higher throughput under low contention
- **Disadvantage**: Retry overhead under high contention, starvation risk

### Quantitative Guidance

| Contention Level | Collision Rate | Recommended Approach |
|-----------------|---------------|---------------------|
| Low (<1% conflicts) | <1 retry per 100 operations | Optimistic |
| Medium (1-10%) | 1-10 retries per 100 operations | Either (benchmark both) |
| High (>10%) | >10 retries per 100 operations | Pessimistic |

---

## 5. Practical Locking Patterns

### SKIP LOCKED — Job Queue Pattern

```sql
-- Worker picks up next available job (no contention between workers!)
BEGIN;
SELECT id, payload
FROM job_queue
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
-- Returns a row not locked by any other worker

-- Process the job...
UPDATE job_queue SET status = 'processing' WHERE id = :picked_id;
COMMIT;

-- Benefits:
-- 1. No deadlocks between workers
-- 2. No lock waits — each worker immediately gets a different row
-- 3. Scales linearly with number of workers
-- 4. Works in both PostgreSQL and MySQL 8.0+
```

### Advisory Locks — Application-Level Coordination

```sql
-- PostgreSQL: named advisory locks for business logic coordination
-- Use case: prevent duplicate processing of the same customer

-- Session-level lock (released at session end)
SELECT pg_advisory_lock(hashtext('customer_42'));
-- ... process customer 42 ...
SELECT pg_advisory_unlock(hashtext('customer_42'));

-- Transaction-level lock (released at TX end)
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('report_generation'));
-- ... generate report (only one at a time) ...
COMMIT;  -- lock auto-released

-- Try-lock variant (non-blocking)
SELECT pg_try_advisory_lock(hashtext('customer_42'));
-- Returns TRUE if acquired, FALSE if already held
```

### SELECT FOR UPDATE with Subquery Pattern

```sql
-- Lock specific rows identified by business logic
BEGIN;
SELECT * FROM inventory
WHERE product_id = 100
  AND warehouse_id IN (
      SELECT warehouse_id FROM warehouse_priority
      WHERE region = 'US-EAST'
      ORDER BY priority
      LIMIT 1
  )
FOR UPDATE;
-- Locked: only the specific inventory row for the highest-priority warehouse

UPDATE inventory SET quantity = quantity - 1
WHERE product_id = 100 AND warehouse_id = :selected_warehouse;
COMMIT;
```

### Monitoring Lock Contention Over Time

```sql
-- PostgreSQL: enable lock wait logging and analyze patterns
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET deadlock_timeout = '200ms';  -- log waits > 200ms
SELECT pg_reload_conf();

-- Query pg_stat_activity for lock wait patterns
SELECT
    wait_event_type,
    wait_event,
    count(*) AS occurrence,
    ROUND(AVG(EXTRACT(EPOCH FROM (now() - query_start))), 2) AS avg_wait_sec
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
GROUP BY wait_event_type, wait_event
ORDER BY occurrence DESC;

-- InnoDB: lock wait summary over time
SELECT
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1e12 AS total_wait_sec,
    AVG_TIMER_WAIT / 1e9 AS avg_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE '%lock%row%';
```

---

## 6. Decision Matrix — Lock Strategy Selection

### Workload to Lock Strategy

| Workload Type | Lock Strategy | Pattern | Rationale |
|--------------|---------------|---------|-----------|
| Standard OLTP | Pessimistic (SELECT FOR UPDATE) | Short TX, row-level locks | Balance of performance and safety |
| Financial transactions | Pessimistic with advisory locks | Lock ordering + advisory | No anomalies tolerated |
| Inventory / booking | SELECT FOR UPDATE NOWAIT | Fail-fast on contention | Prevent overselling, responsive UX |
| Job queue processing | SKIP LOCKED | Workers skip locked rows | Zero contention between workers |
| Low-contention CRUD | Optimistic (version column) | Read-check-write | Minimal lock overhead |
| Read-heavy analytics | No locks (MVCC reads) | Read replicas | Maximize read throughput |

### Contention Mitigation Escalation

| Contention Level | Symptoms | Mitigation |
|-----------------|----------|-----------|
| Low | Lock waits < 1ms, no deadlocks | No action needed |
| Moderate | Lock waits 1-50ms, rare deadlocks | Optimize transaction duration, add indexes |
| High | Lock waits > 50ms, frequent deadlocks | Reduce transaction scope, use SKIP LOCKED, shard data |
| Extreme | Transaction timeouts, cascading retries | Redesign data model, separate hot rows, use queuing |

### Lock Strategy Decision Flowchart

```
Is contention > 10%?
├── YES → Pessimistic locking
│         └── Are transactions user-interactive?
│             ├── YES → FOR UPDATE NOWAIT (fail-fast)
│             └── NO  → FOR UPDATE (wait)
│                       └── Is it a queue pattern?
│                           ├── YES → SKIP LOCKED
│                           └── NO  → Standard FOR UPDATE with lock ordering
└── NO  → Optimistic locking (version column)
          └── Are retries expensive (e.g., complex computation)?
              ├── YES → Pessimistic anyway (avoid wasted work)
              └── NO  → Optimistic with exponential backoff retry
```

---

## 7. Configuration Reference

### Key Lock-Related Settings

| Parameter | Database | Default | Recommendation |
|-----------|----------|---------|---------------|
| `innodb_lock_wait_timeout` | MySQL | 50s | 5-10s for OLTP |
| `lock_timeout` | PostgreSQL | 0 (infinite) | 5s-30s depending on workload |
| `deadlock_timeout` | PostgreSQL | 1s | 200ms-1s (logging threshold) |
| `innodb_deadlock_detect` | MySQL 8.0+ | ON | OFF only if guaranteed no deadlocks |
| `log_lock_waits` | PostgreSQL | off | ON in production for diagnostics |
| `innodb_print_all_deadlocks` | MySQL | OFF | ON for detailed deadlock logging |

```sql
-- PostgreSQL: recommended lock settings for OLTP
ALTER SYSTEM SET lock_timeout = '10s';
ALTER SYSTEM SET deadlock_timeout = '500ms';
ALTER SYSTEM SET log_lock_waits = on;
SELECT pg_reload_conf();

-- MySQL: recommended lock settings for OLTP
SET GLOBAL innodb_lock_wait_timeout = 10;
SET GLOBAL innodb_print_all_deadlocks = ON;
SET GLOBAL innodb_deadlock_detect = ON;
```

---

## 8. Academic References

1. **Berenson et al. (1995)** — "A Critique of ANSI SQL Isolation Levels" — SIGMOD'95. Lock-based vs MVCC isolation
2. **Gray & Reuter (1993)** — "Transaction Processing: Concepts and Techniques". Foundational lock theory
3. **Kung & Robinson (1981)** — "On Optimistic Methods for Concurrency Control" — ACM TODS. Original OCC paper
4. **MySQL Documentation** — InnoDB Locking and Transaction Model
5. **PostgreSQL Documentation** — Chapter 13: Explicit Locking

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
