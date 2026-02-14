# Buffer Pool Management & Tuning Reference

<!-- Agent: e3-buffer-tuner
     Purpose: Buffer pool algorithms (LRU, clock-sweep, ARC), sizing guidelines,
              InnoDB doublewrite/adaptive flushing, and monitoring queries.
     Source: Split from domain-e-io-pages.md (section 2 and related case studies) -->

---

## 1. Buffer Pool Algorithms

### LRU (Least Recently Used)
- **Algorithm**: Evict least recently accessed page when buffer pool is full
- **Problem**: Sequential scan flood evicts all hot pages
- **Mitigation**: LRU-K, midpoint insertion, scan-resistant variants

### InnoDB Buffer Pool (LRU with Midpoint Insertion)
```
+-----------------------------------+
|         Young Sublist             |  <- 5/8 of pool; pages promoted after 2nd access
|         MRU end ------>           |
+-----------------------------------+  <- Midpoint (3/8 boundary)
|          Old Sublist              |  <- New pages inserted here; eviction candidates
|         <------ LRU end           |
+-----------------------------------+
```

```ini
# my.cnf -- Buffer pool sizing for 128GB RAM server
innodb_buffer_pool_size = 96G           # ~75% of RAM
innodb_buffer_pool_instances = 64       # 1 per ~1.5GB, reduces mutex contention
innodb_buffer_pool_chunk_size = 1G      # Online resizing chunk (default 128M)
innodb_old_blocks_pct = 37              # Old sublist = 37%
innodb_old_blocks_time = 1000           # 1s window prevents scan pollution
innodb_lru_scan_depth = 1024
```

### PostgreSQL Clock-Sweep (Shared Buffers)
- **Algorithm**: Circular buffer with usage counter (capped at 5) per page
- **Sweep**: Clock hand decrements counter; evicts at 0
- Frequently accessed pages survive multiple sweeps

```ini
# postgresql.conf -- Buffer config for 64GB RAM
shared_buffers = 16GB                   # ~25% of RAM
effective_cache_size = 48GB             # shared_buffers + OS cache hint
huge_pages = try                        # Reduce TLB misses
```

### ARC (Adaptive Replacement Cache)
- **Used by**: ZFS, IBM DB2
- Two LRU lists (L1=recency, L2=frequency) + two ghost lists (B1, B2)
- Self-tuning: hit in B1 grows L1; hit in B2 grows L2

### Algorithm Comparison

| Algorithm | Scan Resistant | Self-Tuning | Used By |
|-----------|---------------|-------------|---------|
| Plain LRU | No | No | Simple caches |
| LRU + Midpoint | Yes | No | InnoDB |
| Clock-Sweep | Partial | No | PostgreSQL |
| ARC | Yes | Yes | ZFS, DB2 |

---

## 2. Buffer Pool Monitoring

### InnoDB Monitoring

```sql
-- Buffer pool hit rate (target > 99%)
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%';
-- Hit rate = 1 - (reads / read_requests)

-- Per-pool detailed status
SELECT POOL_ID, POOL_SIZE, FREE_BUFFERS, DATABASE_PAGES,
       MODIFIED_DB_PAGES, PAGES_MADE_YOUNG, PAGES_NOT_MADE_YOUNG, HIT_RATE
FROM information_schema.INNODB_BUFFER_POOL_STATS;
```

```sql
-- Top tables in buffer pool
SELECT TABLE_NAME, COUNT(*) AS pages,
       ROUND(COUNT(*) * 16 / 1024, 2) AS mb_in_buffer
FROM information_schema.INNODB_BUFFER_PAGE
WHERE TABLE_NAME IS NOT NULL
GROUP BY TABLE_NAME ORDER BY pages DESC LIMIT 20;
```

### PostgreSQL Monitoring

```sql
-- Buffer cache hit rate (target > 99% for OLTP)
SELECT ROUND(100.0 * sum(blks_hit) /
    NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) AS hit_rate_pct
FROM pg_stat_database;
```

```sql
-- Per-table buffer usage (requires pg_buffercache)
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
SELECT c.relname, COUNT(*) AS buffers,
       ROUND(COUNT(*) * 8.0 / 1024, 2) AS mb_cached,
       ROUND(AVG(usagecount), 2) AS avg_usage
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
GROUP BY c.relname ORDER BY buffers DESC LIMIT 20;
```

```sql
-- Check if backends are doing their own I/O (should be low)
SELECT buffers_checkpoint, buffers_clean, buffers_backend,
    ROUND(100.0 * buffers_backend /
        NULLIF(buffers_checkpoint + buffers_clean + buffers_backend, 0), 2) AS backend_pct
FROM pg_stat_bgwriter;
-- backend_pct > 10% -> increase shared_buffers
```

---

## 3. Case Study: InnoDB Doublewrite & Adaptive Flushing

### Doublewrite Buffer
- **Problem**: Torn page from power failure during 16KB write
- **Solution**: Write to doublewrite area first, then actual location
- **Overhead**: ~5-10% write throughput; disable only if FS guarantees atomic writes

```ini
# my.cnf -- Doublewrite settings
innodb_doublewrite = ON
innodb_doublewrite_dir = /fast_ssd      # MySQL 8.0.20+
innodb_doublewrite_pages = 64
```

### Adaptive Flushing
- Dynamically adjusts flush rate based on redo log generation and dirty page ratio
- Prevents "redo log capacity" stalls

```ini
# my.cnf -- Adaptive flushing for NVMe SSD
innodb_adaptive_flushing = ON
innodb_adaptive_flushing_lwm = 10
innodb_io_capacity = 20000
innodb_io_capacity_max = 40000
innodb_max_dirty_pages_pct = 75
innodb_max_dirty_pages_pct_lwm = 10
innodb_page_cleaners = 4
```

```sql
-- Monitor dirty pages and flushing
SELECT variable_name, variable_value
FROM performance_schema.global_status
WHERE variable_name IN (
    'Innodb_buffer_pool_pages_dirty', 'Innodb_buffer_pool_pages_total',
    'Innodb_buffer_pool_wait_free', 'Innodb_pages_written');
```

---

## 4. Sizing Guidelines

| Database | Recommended | Rationale |
|----------|------------|-----------|
| InnoDB | 70-80% of RAM | Manages its own I/O |
| PostgreSQL | 25% of RAM | Relies on OS page cache |
| MongoDB WT | 50% of (RAM-1GB) | Separate from OS cache |
| Oracle SGA | 60-75% of RAM | Includes buffer cache + shared pool |

### Memory Budget (128GB InnoDB)

```ini
innodb_buffer_pool_size = 96G      # 75%
# Remaining: OS ~8GB, connections ~4GB, internal ~4GB, temp/sort ~8GB, margin ~8GB
```

### Memory Budget (64GB PostgreSQL)

```ini
shared_buffers = 16GB              # 25%
effective_cache_size = 48GB        # Planner hint
# Remaining: OS cache ~32GB, connections ~4GB, work_mem ~8GB, margin ~4GB
```

---

## 5. Decision Matrix

### Buffer Pool Sizing

| Scenario | Size | Rationale |
|----------|------|-----------|
| Working set fits in RAM | >= working set | 99%+ hit rate |
| Hot subset < RAM | >= hot subset | Acceptable hit rate |
| Working set >> RAM | All available RAM | Best effort; add replicas/cache |
| Cloud auto-scaling | 70% instance RAM | Headroom for OS, connections |

### When to Resize

| Symptom | Metric | Action |
|---------|--------|--------|
| Hit rate < 95% | `Innodb_buffer_pool_reads` up | Increase pool or add RAM |
| Wait_free > 0 | `Innodb_buffer_pool_wait_free` | Increase pool; tune flushing |
| Backend writes high | `buffers_backend` > 10% | Increase `shared_buffers` |
| Scan pollution | `pages_not_made_young` high | Increase `innodb_old_blocks_time` |
| Swapping | OS swap > 0 | Decrease pool; check memory budget |

### io_capacity by Storage Type

| Storage | `io_capacity` | `io_capacity_max` | `lru_scan_depth` |
|---------|--------------|-------------------|-----------------|
| HDD 7200 | 100-200 | 400 | 256 |
| SATA SSD | 2000-5000 | 10000 | 1024 |
| NVMe SSD | 10000-50000 | 100000 | 2048 |
| Cloud gp3 | 3000-16000 | 32000 | 1024 |
| Cloud io2 | 10000-64000 | 128000 | 2048 |

---

## 6. References

1. **O'Neil et al. (1993)** -- "The LRU-K Page Replacement Algorithm" -- SIGMOD'93
2. **Megiddo & Modha (2003)** -- "ARC: A Self-Tuning, Low Overhead Replacement Cache" -- FAST'03
3. **Harizopoulos et al. (2008)** -- "OLTP Through the Looking Glass" -- SIGMOD'08

---

*Last updated: 2025-05. Split from domain-e-io-pages.md for e3-buffer-tuner agent.*
