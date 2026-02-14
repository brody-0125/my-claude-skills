# Page Structure & I/O Optimization Reference

<!-- Agent: e1-page-optimizer
     Purpose: Page layout internals, fragmentation detection, sequential vs random I/O tuning,
              and direct I/O vs buffered I/O selection.
     Source: Split from domain-e-io-pages.md (sections 1, 6, and related case studies) -->

---

## 1. Page Structure

### Generic Database Page Layout
```
+----------------------------------------------+
| Page Header (24-100 bytes)                   |
|  - Page ID, LSN, checksum, free space ptrs   |
|  - Previous/Next page pointers (B+Tree)      |
+----------------------------------------------+
| Item Pointers / Slot Array                   |
|  - Fixed-size entries pointing to tuples     |
|  - Grows downward from header               |
+----------------------------------------------+
|           Free Space                         |
+----------------------------------------------+
| Tuple Data / Records                         |
|  - Variable-length, grows upward from bottom |
+----------------------------------------------+
| Special Space (B+Tree sibling ptr, etc.)     |
+----------------------------------------------+
```

### PostgreSQL Page (8KB default)
- **Page header**: 24 bytes (pd_lsn, pd_checksum, pd_flags, pd_lower, pd_upper, pd_special)
- **Line pointers**: 4 bytes each, point to tuple locations
- **Tuples**: HeapTupleHeaderData (23 bytes) + null bitmap + user data
- **TOAST**: Tuples > ~2KB compressed or stored out-of-line
- **Fill factor**: Default 100% for indexes, configurable for heap

### InnoDB Page (16KB default)
- **Page header**: 38 bytes (FIL) + 56 bytes (index header)
- **Infimum/Supremum**: Pseudo-records bounding the page (26 bytes)
- **User records**: Clustered by PK, linked via next-record pointers
- **Page directory**: Sparse slots (every 4-8 records) for binary search

### Page Size Trade-offs

| Page Size | Read Amp. | Write Amp. | Fragmentation | Best For |
|-----------|----------|-----------|---------------|----------|
| 4KB | Higher | Lower | Lower | SSD, point queries |
| 8KB | Moderate | Moderate | Moderate | PostgreSQL default |
| 16KB | Lower | Higher | Higher | InnoDB default, range scans |
| 32-64KB | Lowest | Highest | Highest | Sequential scans, DW |

---

## 2. Page Inspection Queries

```sql
-- PostgreSQL: Inspect page header (requires pageinspect extension)
CREATE EXTENSION IF NOT EXISTS pageinspect;
SELECT lsn, checksum, flags, lower, upper, special, pagesize
FROM page_header(get_raw_page('orders', 0));

-- Show item pointers on page 0
SELECT lp, lp_off, lp_flags, lp_len
FROM heap_page_items(get_raw_page('orders', 0))
ORDER BY lp;
```

```sql
-- PostgreSQL: Table bloat detection (requires pgstattuple)
CREATE EXTENSION IF NOT EXISTS pgstattuple;
SELECT table_len, tuple_count, dead_tuple_count,
       dead_tuple_percent, free_space, free_percent
FROM pgstattuple('orders');
```

```sql
-- InnoDB: Table fragmentation check
SELECT TABLE_SCHEMA, TABLE_NAME, DATA_LENGTH, DATA_FREE,
       ROUND(DATA_FREE / DATA_LENGTH * 100, 2) AS fragmentation_pct
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'mydb' AND DATA_FREE > 0
ORDER BY fragmentation_pct DESC;
```

---

## 3. Fragmentation Monitoring

```sql
-- PostgreSQL: Monitor bloat across all tables
SELECT schemaname, relname AS table_name, n_live_tup, n_dead_tup,
    CASE WHEN n_live_tup > 0
         THEN ROUND(n_dead_tup::numeric / n_live_tup * 100, 2) ELSE 0
    END AS dead_pct,
    last_vacuum, last_autovacuum
FROM pg_stat_user_tables WHERE schemaname = 'public'
ORDER BY dead_pct DESC;
```

```sql
-- InnoDB: Rebuild table to reclaim fragmented space (online DDL)
ALTER TABLE orders ENGINE=InnoDB;

-- PostgreSQL: Set fill factor for HOT updates, then rewrite
ALTER TABLE orders SET (fillfactor = 80);
VACUUM FULL orders;
```

---

## 4. Sequential vs Random I/O

### Impact by Storage Medium

| Operation | HDD | SSD (SATA) | SSD (NVMe) |
|-----------|-----|-----------|------------|
| Seq read (MB/s) | 100-200 | 500-550 | 3000-7000 |
| Seq write (MB/s) | 100-200 | 400-530 | 2000-5000 |
| Random IOPS (4KB) | 100-200 | 50K-100K | 500K-1M+ |
| Random read latency | 5-15ms | 50-100us | 10-30us |

**Key insight**: HDD random I/O is 500-1000x slower than sequential. SSD narrows this to 2-5x.

### Database Implications

| Decision | HDD Optimized | SSD Optimized |
|----------|---------------|---------------|
| Index type | B+Tree (seq leaf scans) | Either (random affordable) |
| Clustering | Critical | Less critical but beneficial |
| WAL placement | Separate disk | Same disk OK |
| `random_page_cost` (PG) | 4.0 (default) | 1.1-1.5 |

```sql
-- PostgreSQL: Tune planner costs for NVMe SSD
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET seq_page_cost = 1.0;
ALTER SYSTEM SET effective_io_concurrency = 200;
SELECT pg_reload_conf();
```

---

## 5. Direct I/O vs Buffered I/O

**Buffered I/O**: Reads/writes through OS page cache. Risk of double buffering. PostgreSQL uses this by design.

**Direct I/O (O_DIRECT)**: Bypasses OS cache. InnoDB default (`innodb_flush_method = O_DIRECT`). Avoids double buffering but loses OS read-ahead.

```ini
# MySQL/InnoDB: Recommended for production
innodb_flush_method = O_DIRECT
innodb_use_native_aio = ON

# PostgreSQL: Keep buffered I/O; tune OS instead
# /etc/sysctl.conf
# vm.dirty_ratio = 10
# vm.dirty_background_ratio = 3
# vm.swappiness = 1
```

```sql
-- MySQL: Verify flush method and monitor I/O
SHOW VARIABLES LIKE 'innodb_flush_method';
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
WHERE NAME IN ('os_data_reads', 'os_data_writes', 'os_data_fsyncs');
```

| Database | I/O Mode | Rationale |
|----------|----------|-----------|
| InnoDB | `O_DIRECT` | Manages its own buffer pool |
| PostgreSQL | Buffered I/O | Designed for OS page cache |
| MongoDB WT | Direct for data, buffered for journal | Hybrid |

---

## 6. Decision Matrix

### Page Size Selection

| Workload | Recommended Size | Rationale |
|----------|-----------------|-----------|
| OLTP point queries, SSD | 4-8KB | Minimize read amplification |
| Mixed OLTP | 8KB (PG) / 16KB (InnoDB) | Database defaults, balanced |
| Range scans, analytics | 16-32KB | Fewer page fetches |
| Wide rows (>4KB) | 16-32KB | Avoid row spanning |

### Fragmentation Action Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| PG dead_tuple_percent > 20% | Warning | Verify autovacuum; tune thresholds |
| PG free_percent > 40% | Action | `VACUUM FULL` or `pg_repack` |
| InnoDB DATA_FREE/DATA_LENGTH > 30% | Action | `ALTER TABLE ... ENGINE=InnoDB` |
| Index bloat > 30% | Action | `REINDEX CONCURRENTLY` (PG) |

### I/O Configuration by Storage Type

| Storage | `innodb_flush_method` | `random_page_cost` | Read-Ahead |
|---------|----------------------|-------------------|-----------|
| HDD | O_DIRECT | 4.0 | 256KB+ |
| SATA SSD | O_DIRECT | 1.5 | 128KB |
| NVMe SSD | O_DIRECT | 1.1 | 64-128KB |
| Network (EBS) | O_DIRECT | 1.5-2.0 | 128-256KB |
| Aurora | N/A (managed) | 1.1 | Managed |

---

## 7. References

1. **Harizopoulos et al. (2008)** -- "OLTP Through the Looking Glass" -- SIGMOD'08
2. **Gray & Reuter (1992)** -- "Transaction Processing: Concepts and Techniques" -- Morgan Kaufmann

---

*Last updated: 2025-05. Split from domain-e-io-pages.md for e1-page-optimizer agent.*
