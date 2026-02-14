# MVCC Implementation Reference — c2-mvcc-specialist Agent

<!--
  Agent: c2-mvcc-specialist
  Purpose: Provides deep knowledge of Multi-Version Concurrency Control implementations
           across PostgreSQL (xmin/xmax), InnoDB (undo log), and Oracle (SCN).
           Includes monitoring queries, health checks, and Aurora case study.
  Source: Extracted and enriched from domain-c-concurrency.md sections 2, 7 (Aurora partial).
-->

---

## 1. PostgreSQL MVCC: xmin/xmax Model

### Mechanism

Each row version (tuple) is stored in the heap with system columns:
- `xmin`: Transaction ID that created this version
- `xmax`: Transaction ID that deleted/updated this version (0 if live)
- `cmin`/`cmax`: Command IDs within transaction
- `ctid`: Physical location (page, offset)

Updates create a new tuple version (copy-on-write); the old version remains until VACUUM.

### Snapshot Visibility

- Transaction snapshot contains: `xmin` (oldest active), `xmax` (next to assign), `xip[]` (active TxIDs)
- Visibility rule: Tuple visible if `xmin` committed AND (`xmax` = 0 OR `xmax` not committed in snapshot)
- Read Committed: New snapshot per statement
- Repeatable Read / Serializable: Snapshot taken at first query in transaction

### Trade-offs

| Property | Detail |
|----------|--------|
| **Readers block writers** | Never — readers always use snapshots |
| **Table bloat** | Dead tuples accumulate until VACUUM reclaims them |
| **VACUUM** | Reclaims dead tuples, updates visibility map, freezes old TxIDs |
| **HOT optimization** | Heap-Only Tuple: avoids index update when update does not change indexed columns |
| **Autovacuum** | Background process with configurable thresholds |

### Inspecting MVCC State

```sql
-- View hidden system columns for a table
SELECT ctid, xmin, xmax, * FROM orders LIMIT 5;

-- Check tuple versions: xmax > 0 means a newer version exists (or delete pending)
SELECT ctid, xmin, xmax,
       CASE WHEN xmax = 0 THEN 'live' ELSE 'dead/updated' END AS status,
       *
FROM orders
WHERE id = 42;

-- After an UPDATE, the old ctid points to a dead tuple, new ctid appears
-- Example output:
--  ctid  | xmin | xmax | status
-- (0,1)  |  100 |  105 | dead/updated   <-- old version
-- (0,5)  |  105 |    0 | live           <-- new version
```

### Monitoring VACUUM Health

```sql
-- Check tables needing vacuum (dead tuple ratio)
SELECT
    schemaname, relname,
    n_live_tup,
    n_dead_tup,
    ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- Check autovacuum workers currently running
SELECT pid, datname, relid::regclass, phase,
       heap_blks_total, heap_blks_scanned, heap_blks_vacuumed
FROM pg_stat_progress_vacuum;

-- Tables with excessive bloat (estimated)
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    n_dead_tup,
    last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC
LIMIT 20;
```

### Autovacuum Tuning Parameters

```sql
-- Key autovacuum configuration parameters
SHOW autovacuum_vacuum_threshold;        -- default: 50 rows
SHOW autovacuum_vacuum_scale_factor;     -- default: 0.2 (20% of table)
-- Vacuum triggers when: dead_tuples > threshold + scale_factor * n_live_tup

-- Per-table override for high-churn tables
ALTER TABLE hot_events SET (
    autovacuum_vacuum_threshold = 100,
    autovacuum_vacuum_scale_factor = 0.01,  -- 1% instead of 20%
    autovacuum_vacuum_cost_delay = 5        -- more aggressive (default: 20ms)
);

-- Check current effective thresholds
SELECT relname,
       reloptions,
       n_live_tup,
       50 + 0.2 * n_live_tup AS default_threshold,
       n_dead_tup
FROM pg_stat_user_tables
JOIN pg_class ON relname = pg_class.relname
WHERE n_dead_tup > 50 + 0.2 * n_live_tup
ORDER BY n_dead_tup DESC;
```

### Transaction ID Wraparound Prevention

```sql
-- Check proximity to transaction ID wraparound (critical!)
SELECT datname,
       age(datfrozenxid) AS xid_age,
       2147483647 - age(datfrozenxid) AS remaining_xids,
       ROUND(age(datfrozenxid)::numeric / 2147483647 * 100, 2) AS pct_consumed
FROM pg_database
ORDER BY xid_age DESC;

-- Per-table freeze age
SELECT relname, age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relkind = 'r'
ORDER BY xid_age DESC
LIMIT 10;
-- WARNING: If age approaches 2 billion, emergency anti-wraparound vacuum triggers
-- which can be extremely disruptive. Keep autovacuum healthy!
```

---

## 2. MySQL/InnoDB MVCC: Undo Log Model

### Mechanism

Row stored in clustered index with hidden columns:
- `DB_TRX_ID`: Last transaction that modified the row (6 bytes)
- `DB_ROLL_PTR`: Pointer to undo log record (7 bytes)
- `DB_ROW_ID`: Auto-generated row ID if no PK (6 bytes)

Updates modify the row in-place; the previous version is stored in the undo log.
Undo log forms a version chain: current row -> undo record 1 -> undo record 2 -> ...

### Read View

- Created at transaction start (Repeatable Read) or statement start (Read Committed)
- Contains: `m_low_limit_id` (next TxID), `m_up_limit_id` (lowest active), `m_ids` (active list)
- Visibility: Row visible if `DB_TRX_ID` < `m_up_limit_id` AND not in `m_ids`
- If not visible: follow `DB_ROLL_PTR` chain to find visible version

### Trade-offs

| Property | Detail |
|----------|--------|
| **Table bloat** | None — in-place updates, no dead tuples in heap |
| **Undo log growth** | Long transactions hold undo logs, causing tablespace growth |
| **Purge thread** | Background cleanup of undo logs no longer referenced |
| **History list length** | Metric for pending undo purge work; growth indicates problems |

### Monitoring InnoDB MVCC Health

```sql
-- Check history list length (critical MVCC health metric)
SHOW ENGINE INNODB STATUS\G
-- Look for: "History list length" in the TRANSACTIONS section
-- Healthy: < 1,000. Warning: > 10,000. Critical: > 100,000

-- Undo tablespace usage
SELECT
    TABLESPACE_NAME,
    FILE_NAME,
    ROUND(TOTAL_EXTENTS * EXTENT_SIZE / 1024 / 1024, 2) AS size_mb
FROM information_schema.FILES
WHERE TABLESPACE_NAME LIKE 'innodb_undo%';

-- Long-running transactions that block undo purge
SELECT
    trx_id, trx_state,
    trx_started,
    TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS duration_sec,
    trx_rows_locked,
    trx_rows_modified
FROM information_schema.INNODB_TRX
ORDER BY trx_started ASC;
-- Kill long-running idle transactions to allow undo purge to proceed!

-- Purge lag monitoring (MySQL 8.0+)
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
WHERE NAME IN ('trx_rseg_history_len', 'purge_del_mark_per_sec', 'purge_upd_exist_per_sec');
```

### Undo Tablespace Management (MySQL 8.0+)

```sql
-- Check undo tablespace state
SELECT TABLESPACE_NAME, FILE_NAME, FILE_TYPE, ENGINE,
       ROUND(TOTAL_EXTENTS * EXTENT_SIZE / 1048576) AS size_mb
FROM information_schema.FILES
WHERE FILE_TYPE = 'UNDO LOG';

-- Create additional undo tablespace for rotation
CREATE UNDO TABLESPACE undo_003 ADD DATAFILE 'undo_003.ibu';

-- Mark old tablespace as inactive (allows truncation when empty)
ALTER UNDO TABLESPACE innodb_undo_001 SET INACTIVE;

-- Configure automatic undo truncation
SET GLOBAL innodb_undo_log_truncate = ON;
SET GLOBAL innodb_max_undo_log_size = 1073741824;  -- 1GB trigger
SET GLOBAL innodb_purge_rseg_truncate_frequency = 128;
```

---

## 3. Oracle MVCC: SCN-Based Model

### Mechanism

- System Change Number (SCN): monotonically increasing counter
- Each transaction assigned SCN at commit time
- Block-level SCN tracking: each data block header contains recent SCN
- Undo segments store before-images with SCN timestamps
- Consistent read: reconstruct block as of query's SCN using undo

### Characteristics

| Property | Detail |
|----------|--------|
| **Default consistency** | Statement-level (Read Committed) |
| **ORA-01555** | "Snapshot too old" — undo segments recycled before long query completes |
| **Undo retention** | Configurable but bounded by undo tablespace size |
| **Flashback Query** | Leverages SCN-based versioning for time-travel queries |

### Oracle Undo and SCN Monitoring

```sql
-- Check current SCN
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER FROM DUAL;

-- Undo tablespace utilization
SELECT tablespace_name, status,
       ROUND(SUM(bytes) / 1048576) AS size_mb
FROM dba_undo_extents
GROUP BY tablespace_name, status
ORDER BY tablespace_name, status;
-- STATUS: ACTIVE (in use), UNEXPIRED (still within retention), EXPIRED (reclaimable)

-- Undo retention settings
SHOW PARAMETER undo_retention;  -- target retention in seconds (default: 900)
SHOW PARAMETER undo_tablespace;

-- Sessions at risk of ORA-01555 (long-running queries)
SELECT sid, serial#, username,
       ROUND((sysdate - sql_exec_start) * 86400) AS running_sec,
       sql_id
FROM v$session
WHERE status = 'ACTIVE'
  AND type = 'USER'
ORDER BY sql_exec_start ASC NULLS LAST;

-- Flashback query example (time-travel read)
SELECT * FROM orders AS OF SCN 123456789 WHERE id = 42;
SELECT * FROM orders AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '10' MINUTE) WHERE id = 42;
```

---

## 4. Amazon Aurora: Lock-Free Reads via MVCC

### Architecture Innovation

- Separates compute (SQL processing) from storage (distributed log-structured)
- "Log is the database": only writes redo log records to storage
- 6-way replication across 3 AZs (2 copies per AZ)
- Quorum: 4/6 for writes, 3/6 for reads

### MVCC Implementation

- Write node generates redo log records with LSN (Log Sequence Number)
- Storage nodes apply redo logs to construct page versions
- Read replicas read from storage with specific LSN snapshot
- No dirty page shipping between compute nodes (unlike traditional replication)

### Read Scaling

- Up to 15 read replicas, each with independent buffer cache
- Replica lag: typically <20ms (redo log replication, not binlog)
- Read replicas do not need locks for reads (MVCC from storage layer)
- Each read request specifies "read point" LSN

### Performance Data

| Metric | Value |
|--------|-------|
| Throughput vs standard MySQL | 5x on same hardware (Amazon benchmark) |
| Storage range | Auto-scales 10GB to 128TB |
| Failover time | <30 seconds (typically <15 seconds) |
| Write throughput | Up to 200K writes/sec (Aurora MySQL) |
| Replica lag | Typically <20ms |

### Aurora MVCC Monitoring

```sql
-- Aurora MySQL: check replica lag
SELECT SERVER_ID, SESSION_ID, REPLICA_LAG_IN_MILLISECONDS
FROM information_schema.REPLICA_HOST_STATUS;

-- Aurora MySQL: check volume status (storage-layer MVCC)
SHOW GLOBAL STATUS LIKE 'Aurora%';
-- Key metrics: Aurora_volume_bytes_left_total, Aurora_redo_log_bytes

-- Aurora PostgreSQL: standard pg_stat_replication works
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       sent_lsn - replay_lsn AS replication_lag
FROM pg_stat_replication;
```

---

## 5. MVCC Implementation Comparison

| Feature | PostgreSQL (xmin/xmax) | InnoDB (Undo Log) | Oracle (SCN) | Aurora |
|---------|----------------------|-------------------|-------------|--------|
| Version storage | Heap (in-table) | Undo tablespace | Undo tablespace | Storage layer (log-structured) |
| Update strategy | Copy-on-write (new tuple) | In-place + undo chain | In-place + undo chain | Redo log to storage |
| Cleanup mechanism | VACUUM (autovacuum) | Purge thread | Automatic undo recycling | Storage-layer GC |
| Bloat risk | Table bloat (dead tuples) | Undo tablespace growth | ORA-01555 risk | Minimal (log-structured) |
| Readers block writers | Never | Never | Never | Never |
| Long-TX impact | Blocks VACUUM, XID wraparound | History list length growth | Undo retention pressure | Minimal |
| Key health metric | `n_dead_tup`, XID age | History list length | Undo retention, ORA-01555 count | Replica lag, volume bytes |

---

## 6. Decision Matrix — MVCC Operational Guidance

### When to Intervene

| Symptom | Database | Root Cause | Action |
|---------|----------|-----------|--------|
| Dead tuple ratio > 20% | PostgreSQL | Autovacuum lagging | Tune thresholds, increase workers |
| XID age > 500M | PostgreSQL | Anti-wraparound risk | Emergency vacuum, kill long TXs |
| History list length > 10K | InnoDB | Long-running TXs block purge | Kill idle TXs, check for lock waits |
| Undo tablespace > 80% | InnoDB / Oracle | Undo retention too high | Reduce retention, add undo space |
| ORA-01555 errors | Oracle | Undo recycled during long query | Increase undo_retention, optimize query |
| Replica lag > 100ms | Aurora | Write volume exceeds replication capacity | Scale storage, reduce write batch size |

### MVCC-Friendly Application Patterns

| Pattern | Benefit | Implementation |
|---------|---------|---------------|
| Short transactions | Minimizes version retention | Keep TXs under 1 second |
| Avoid idle-in-TX | Prevents VACUUM/purge blocking | Set `idle_in_transaction_session_timeout` |
| Batch large updates | Reduces dead tuple spikes | Process in 1K-10K row batches with intermediate commits |
| Read replicas for analytics | Offloads long reads from writer | Route reporting queries to replicas |
| Partitioning | Simplifies VACUUM scope | Partition by time, drop old partitions instead of DELETE |

```sql
-- PostgreSQL: protect against idle-in-transaction sessions
ALTER SYSTEM SET idle_in_transaction_session_timeout = '60s';
SELECT pg_reload_conf();

-- MySQL: kill idle transactions exceeding threshold
-- (requires event scheduler or monitoring tool)
SELECT trx_mysql_thread_id
FROM information_schema.INNODB_TRX
WHERE TIMESTAMPDIFF(SECOND, trx_started, NOW()) > 300
  AND trx_state = 'RUNNING';
-- Then: KILL <thread_id>;
```

---

## 7. Academic References

1. **Verbitski et al. (2017)** — "Amazon Aurora: Design Considerations for High Throughput Cloud-Native Relational Databases" — SIGMOD'17
2. **Berenson et al. (1995)** — "A Critique of ANSI SQL Isolation Levels" — SIGMOD'95. Snapshot visibility definitions
3. **PostgreSQL Documentation** — Chapter 13: Concurrency Control (MVCC internals)
4. **MySQL Documentation** — InnoDB Multi-Versioning (undo log architecture)

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
