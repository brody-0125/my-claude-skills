# Write-Ahead Logging & Durability Reference

<!-- Agent: e2-wal-engineer
     Purpose: WAL internals, checkpoint strategies, fsync/durability tuning,
              replication considerations, and production WAL configuration.
     Source: Split from domain-e-io-pages.md (sections 3, 4, 5, and related case studies) -->

---

## 1. Write-Ahead Logging (WAL)

### Fundamental Principle
**WAL Protocol**: Before any data page modification is written to disk, the corresponding log record MUST be flushed to stable storage. This guarantees atomicity, durability, and crash recovery.

### WAL Record Format
```
+------------------------------------------------+
| LSN (Log Sequence Number)                      |  <- Monotonically increasing
| Transaction ID                                 |
| Previous LSN (same transaction)                |  <- Links transaction's log chain
| Record Type (INSERT/UPDATE/DELETE/COMMIT/etc)  |
| Page ID + Offset                               |
| Before Image (UNDO) / After Image (REDO)       |
| CRC/Checksum                                   |
+------------------------------------------------+
```

### LSN (Log Sequence Number)
- **PostgreSQL**: 64-bit byte offset into WAL stream (e.g., `0/16B3A60`)
- **InnoDB**: 64-bit byte offset into redo log (e.g., `LSN: 3456789012`)
- **Page LSN**: Each page header stores LSN of last modification
- **Recovery rule**: If page LSN < checkpoint LSN, page is current; otherwise replay WAL

---

## 2. Database-Specific WAL Internals

### PostgreSQL WAL
- **Segment files**: 16MB each in `pg_wal/`
- **Full page writes**: First modification after checkpoint writes entire page image (torn page protection)

```ini
# postgresql.conf -- WAL configuration
wal_buffers = 64MB               # Default -1 = auto (~1/32 of shared_buffers)
wal_level = replica               # minimal | replica | logical
synchronous_commit = on           # off = faster but risk losing last few txns
max_wal_size = 8GB                # Checkpoint trigger (default 1GB)
min_wal_size = 1GB                # Pre-allocated segments (default 80MB)
wal_compression = on              # Reduce WAL volume 50-70% (PG 15+)
full_page_writes = on             # NEVER turn off
```

```sql
-- WAL statistics (PostgreSQL 14+)
SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full FROM pg_stat_wal;

-- WAL generation rate: run twice and diff
SELECT pg_current_wal_lsn();
```

### InnoDB Redo Log
- **Circular log**: Fixed-size files, MTR (Mini-Transaction) ensures atomic page modifications
- **Group commit**: Multiple transactions share single fsync (since 5.6)

```ini
# my.cnf -- InnoDB redo log
innodb_log_buffer_size = 64M
innodb_redo_log_capacity = 2G       # MySQL 8.0.30+
```

```sql
-- Monitor redo log usage
SHOW ENGINE INNODB STATUS\G
-- Look for: Log sequence number, Log flushed up to
```

---

## 3. Checkpoint Strategies

### Sharp vs Fuzzy Checkpoint
- **Sharp**: Flush ALL dirty pages at checkpoint. Simple recovery but causes I/O storm. Used at shutdown.
- **Fuzzy**: Continuously flush in background. Spreads I/O but longer recovery window. InnoDB default.

### InnoDB Checkpoint Tuning

```ini
# my.cnf -- Checkpoint and flushing
innodb_io_capacity = 10000            # HDD:100-200, SSD:2K-20K, NVMe:20K-100K
innodb_io_capacity_max = 20000
innodb_max_dirty_pages_pct = 90
innodb_max_dirty_pages_pct_lwm = 10
innodb_adaptive_flushing = ON
innodb_page_cleaners = 4
```

### PostgreSQL Checkpoint Tuning

```ini
# postgresql.conf -- Checkpoint parameters
checkpoint_timeout = 15min             # Default 5min, prod: 15-30min
max_wal_size = 8GB                     # Default 1GB, prod: 4-16GB
checkpoint_completion_target = 0.9     # Spread I/O over 90% of interval
```

```sql
-- Monitor checkpoint activity
SELECT checkpoints_timed, checkpoints_req,
       checkpoint_write_time, checkpoint_sync_time,
       buffers_checkpoint, buffers_backend
FROM pg_stat_bgwriter;
-- High checkpoints_req -> increase max_wal_size
-- High buffers_backend -> increase shared_buffers
```

---

## 4. fsync and Durability

### Write Path
```
Application -> Kernel Buffer -> Disk Controller Cache -> Physical Media
              (OS page cache)   (volatile by default)
```

### fsync Semantics
- `fsync()`: Flush data + metadata to storage
- `fdatasync()`: Flush data only (faster)
- `O_DSYNC`: Per-write sync, `O_DIRECT`: Bypass OS cache

### Group Commit

| InnoDB `flush_log_at_trx_commit` | Behavior | Risk | TPS |
|----------------------------------|----------|------|-----|
| `1` | fsync every commit | Safest | ~10K (SSD) |
| `2` | OS cache, fsync/sec | Lose 1s on OS crash | ~50K |
| `0` | Log buffer, flush/sec | Lose 1s on any crash | ~100K |

```ini
# my.cnf -- Durability
innodb_flush_log_at_trx_commit = 1
sync_binlog = 1
```

```ini
# postgresql.conf -- Group commit
commit_delay = 10          # Microseconds delay to batch fsyncs
commit_siblings = 5        # Min active txns to trigger delay
```

```bash
# Verify hardware durability settings
sudo hdparm -W /dev/sda          # Check disk write cache
cat /sys/block/sda/queue/scheduler  # noop/none best for SSD
pg_test_fsync                     # Benchmark sync methods
```

---

## 5. Case Study: Aurora -- "Log Is the Database"

```
Traditional MySQL:
  Write -> Data pages + WAL -> flush both -> ship WAL -> replica applies

Aurora:
  Write -> WAL only -> ship to 6 storage nodes -> pages materialized on demand
```

- **Architecture**: Compute separated from log-structured storage across 3 AZs
- **Write quorum**: 4 of 6 (tolerates 1 AZ + 1 node failure)
- **Results**: 5x throughput, <1 min crash recovery, 46 vs 180+ I/Os per txn
- **Replication lag**: <20ms (typically <10ms)

---

## 6. Case Study: PostgreSQL WAL Tuning

| Parameter | Default | Production | Rationale |
|-----------|---------|------------|-----------|
| `wal_buffers` | auto | 64MB | Reduce WAL write contention |
| `checkpoint_timeout` | 5min | 15-30min | Reduce checkpoint frequency |
| `max_wal_size` | 1GB | 4-16GB | Allow WAL accumulation |
| `wal_compression` | off | on | Reduce volume 50-70% |
| `full_page_writes` | on | on | Never disable |

```ini
# Complete OLTP WAL config for NVMe SSD, 64GB RAM
shared_buffers = 16GB
wal_buffers = 64MB
wal_level = replica
synchronous_commit = on
max_wal_size = 8GB
min_wal_size = 2GB
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9
wal_compression = on
commit_delay = 10
commit_siblings = 5
```

```sql
-- Check if checkpoints are too frequent
SELECT checkpoints_timed, checkpoints_req,
    ROUND(100.0 * checkpoints_req /
        NULLIF(checkpoints_timed + checkpoints_req, 0), 1) AS req_pct
FROM pg_stat_bgwriter;
-- req_pct > 10% -> increase max_wal_size
```

---

## 7. Decision Matrix

### Durability Configuration

| Need | WAL Setting | Checkpoint | Group Commit | TPS |
|------|-----------|-----------|-------------|-----|
| Maximum (financial) | fsync/commit | 5-15min | Enabled | 1K-10K |
| Standard (OLTP) | fsync + group commit | 15-30min | Enabled | 10K-100K |
| Relaxed (analytics) | fsync periodic (1s) | 30-60min | Aggressive | 50K-500K |
| Minimal (ephemeral) | async, no fsync | Infrequent | N/A | 100K-1M+ |

### WAL Level Selection

| `wal_level` | Use Case | Supports |
|-------------|----------|----------|
| `minimal` | No replication | Crash recovery only |
| `replica` | Physical replication | Streaming, pg_basebackup, PITR |
| `logical` | CDC, logical replication | pgoutput, Debezium |

### Checkpoint Interval Trade-offs

| Interval | Recovery Time | I/O Pattern | Best For |
|----------|--------------|-------------|----------|
| 5min | <30s | Frequent small | Dev/test |
| 15min | ~1min | Balanced | General OLTP |
| 30min | ~2min | Infrequent larger | Write-heavy |
| 60min | ~5min | Rare massive | Analytics, batch |

---

## 8. References

1. **Mohan et al. (1992)** -- "ARIES" -- ACM TODS. Foundation of WAL and recovery
2. **Gray & Reuter (1992)** -- "Transaction Processing" -- Morgan Kaufmann
3. **Verbitski et al. (2017)** -- "Amazon Aurora" -- SIGMOD'17
4. **Verbitski et al. (2018)** -- "Aurora: Avoiding Distributed Consensus" -- SIGMOD'18

---

*Last updated: 2025-05. Split from domain-e-io-pages.md for e2-wal-engineer agent.*
