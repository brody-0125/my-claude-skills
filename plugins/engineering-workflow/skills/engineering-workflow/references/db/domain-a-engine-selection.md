# Storage Engine Selection Reference — Engine Selector Agent

<!-- Agent: a1-engine-selector -->
<!-- Purpose: Provides the a1-engine-selector agent with comprehensive reference material -->
<!-- for comparing storage engines (B+Tree vs LSM-Tree), evaluating InnoDB, RocksDB, -->
<!-- and WiredTiger architectures, and making data-driven engine selection decisions. -->

---

## 1. Fundamental Trade-offs: The RUM Conjecture

Every storage engine optimizes for at most two of three amplification factors:

| Factor | Definition | B+Tree | LSM-Tree |
|--------|-----------|--------|----------|
| **Read Amplification** | I/Os per point read | 1-3 (optimal) | 1-N levels |
| **Write Amplification** | Bytes written / bytes ingested | 10-30x (page splits) | 10-30x (compaction) |
| **Space Amplification** | Storage used / logical data size | ~1.0-1.5x (fragmentation) | 1.1-2.0x (duplicates) |

### B+Tree Characteristics
- **Structure**: Balanced tree with sorted leaf pages linked in doubly-linked list
- **Write path**: Find leaf page -> insert in-place -> split if full -> propagate upward
- **Read path**: Root -> internal nodes -> leaf page (O(log_B N) I/Os)
- **Strengths**: Predictable read latency, efficient range scans, mature implementations
- **Weaknesses**: Random write I/O, page splits cause write amplification, fragmentation

### LSM-Tree Characteristics
- **Structure**: In-memory buffer (memtable) + sorted on-disk levels (SSTables)
- **Write path**: Append to memtable -> flush to L0 -> compact through levels
- **Read path**: Check memtable -> check each level (bloom filters reduce I/O)
- **Strengths**: Sequential write I/O, high write throughput, compressible
- **Weaknesses**: Read amplification across levels, compaction CPU/I/O overhead

### Quantitative Data (FAST'22 / VLDB'21)
- B+Tree random write: 10-30x write amplification on HDD, 2-10x on SSD
- LSM leveled compaction: ~10x write amp; tiered: ~4x write amp but ~2x space amp
- Point read latency: B+Tree 0.1-0.5ms vs LSM 0.5-5ms (without bloom filters)
- Bloom filters reduce LSM read amplification by 90%+ for point queries

```sql
-- Compare storage amplification across engines in a test schema
SELECT engine,
       ROUND(data_length / 1024 / 1024, 2) AS data_mb,
       ROUND(index_length / 1024 / 1024, 2) AS index_mb,
       ROUND((data_length + index_length) / data_free, 2) AS space_amp_ratio
FROM information_schema.tables
WHERE table_schema = 'sbtest'
ORDER BY engine, table_name;
```

---

## 2. InnoDB (MySQL)

### Architecture
```
┌─────────────────────────────┐
│   Buffer Pool (70-80% RAM)  │  Data Pages + Adaptive Hash Index
├─────────────────────────────┤
│   Change Buffer             │  Secondary index DML caching
├─────────────────────────────┤
│   Redo Log (WAL)            │  Circular log files
├─────────────────────────────┤
│   Undo Tablespace           │  MVCC version chain
├─────────────────────────────┤
│   Tablespace Files (.ibd)   │  Clustered index + secondary indexes
└─────────────────────────────┘
```

### Key Components
- **Buffer Pool**: LRU with midpoint insertion (5/8 young, 3/8 old). 16KB pages. Adaptive hash index on hot pages.
- **Clustered Index**: Rows stored in PK order. Secondary indexes store PK (double traversal needed).
- **MVCC**: Undo log linked list. DB_TRX_ID + DB_ROLL_PTR per row. Purge thread GCs old versions.
- **Change Buffer**: Caches secondary index changes for non-resident pages. Reduces random I/O.

```sql
-- Buffer pool diagnostics
SELECT pool_id,
       pool_size * 16 / 1024 AS pool_size_mb,
       pages_dirty, pages_free, pages_data
FROM information_schema.innodb_buffer_pool_stats;
```

```ini
# my.cnf — InnoDB tuning for read-heavy OLTP (64GB RAM)
[mysqld]
innodb_buffer_pool_size        = 48G
innodb_buffer_pool_instances   = 16
innodb_log_file_size           = 2G
innodb_flush_log_at_trx_commit = 1
innodb_io_capacity             = 2000
innodb_io_capacity_max         = 4000
innodb_read_io_threads         = 16
innodb_write_io_threads        = 16
innodb_adaptive_hash_index     = ON
```

- Target: buffer pool hit rate >99%, throughput 10K-100K+ TPS

---

## 3. RocksDB / MyRocks (General Overview)

### Compaction Strategies Summary

| Strategy | Write Amp | Space Amp | Read Amp | Best For |
|----------|-----------|-----------|----------|----------|
| **Leveled** | ~10x | ~1.1x | Low | General purpose, read-heavy |
| **Universal** | ~4x | ~2x | Medium | Write-heavy, batch ingestion |
| **FIFO** | ~1x | ~1x | Low | Time-series, TTL data |

### MyRocks Key Metrics
- 50% storage reduction vs InnoDB (compression + no fragmentation)
- 10x less write amplification for write-heavy workloads
- Trade-off: higher read latency for range scans, no adaptive hash index

```sql
-- Compare InnoDB vs MyRocks storage footprint
SELECT t.table_name, t.engine,
       ROUND((t.data_length + t.index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.tables t
WHERE t.table_schema = 'benchmark_db'
ORDER BY t.table_name, t.engine;
```

---

## 4. WiredTiger (MongoDB)

- Default engine since MongoDB 3.2. B+Tree for collections. Document-level MVCC.
- **Concurrency**: Document-level locking, ticket-based admission (128 read/write tickets)
- **Compression**: Snappy (default, ~2x), zstd (~5-8x, storage-constrained), prefix compression for indexes (50-80%)
- **Cache**: 50% of (RAM - 1GB). Eviction at 80%, aggressive at 95%.

```javascript
// WiredTiger cache and concurrency diagnostics
db.serverStatus().wiredTiger.cache
// "bytes currently in the cache", "tracked dirty bytes", "pages evicted"
db.serverStatus().wiredTiger.concurrentTransactions
// { "read": { "out": N, "available": M, "totalTickets": 128 } }
```

```yaml
# mongod.conf — WiredTiger tuning (32GB RAM)
storage:
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 15
    collectionConfig:
      blockCompressor: zstd
    indexConfig:
      prefixCompression: true
```

---

## 5. Case Studies

### Pinterest: 75B+ Pins on InnoDB
- 8192 virtual shards on MySQL/InnoDB. ID format: `[shard_id:16][type:16][local_id:32]`
- Chose InnoDB over Cassandra for strong consistency. Buffer pool 75% RAM, hit rate >99.5%
- p99 read latency <5ms, replication lag <100ms

### Uber: Schemaless to Docstore
- Switched from PostgreSQL to MySQL/InnoDB due to write amplification and replication issues
- Schemaless: append-only cells on InnoDB, 100K+ writes/sec sustained
- Docstore: document-oriented successor with secondary indexes and per-partition transactions

### Netflix: Multi-Engine Strategy
| Use Case | Engine | Rationale |
|----------|--------|-----------|
| User profiles | Cassandra | High availability, global replication |
| Billing, accounts | MySQL (InnoDB) | ACID, strong consistency |
| Viewing history | Cassandra | Write-heavy, time-series |
| Content metadata | EVCache | Ultra-low latency (<1ms p99) |
| Analytics | Redshift/Spark | Columnar, batch processing |

---

## 6. Decision Matrix

### Workload Type to Engine Recommendation

| Workload Profile | Recommended Engine | Key Metric Threshold |
|-----------------|-------------------|---------------------|
| Read-heavy (>80% reads) | B+Tree (InnoDB, PostgreSQL) | Read latency p99 < 5ms |
| Write-heavy (>50% writes) | LSM (RocksDB, MyRocks) | Write throughput > 50K/sec |
| Mixed (60-80% reads) | B+Tree with buffer pool tuning | Buffer pool hit rate > 99% |
| Time-series append | LSM with FIFO compaction | Sustained sequential writes |
| Document-centric | WiredTiger (MongoDB) | Flexible schema, document-level ops |
| High compression needed | LSM (RocksDB with zstd) | Storage cost reduction > 50% |

### Selection Criteria Scoring Formula

```
Score = (Read_Latency_Weight * Read_Score)
      + (Write_Throughput_Weight * Write_Score)
      + (Space_Efficiency_Weight * Space_Score)
      + (Operational_Complexity_Weight * Ops_Score)

Latency-sensitive OLTP:    Read=0.4, Write=0.2, Space=0.1, Ops=0.3
High-ingestion pipeline:   Read=0.1, Write=0.5, Space=0.2, Ops=0.2
Cost-optimized storage:    Read=0.2, Write=0.1, Space=0.5, Ops=0.2
```

### Engine Selection Benchmark Script

```bash
#!/usr/bin/env bash
# engine-benchmark.sh — Compare InnoDB vs RocksDB with sysbench
HOST="${1:-127.0.0.1}"; PORT="${2:-3306}"
TABLES="${3:-8}"; SIZE="${4:-1000000}"

for ENGINE in innodb rocksdb; do
  echo "=== Benchmarking ${ENGINE} ==="
  sysbench oltp_read_write \
    --mysql-host="$HOST" --mysql-port="$PORT" \
    --mysql-user=sbtest --mysql-password=sbtest \
    --mysql-db="sbtest_${ENGINE}" \
    --tables="$TABLES" --table-size="$SIZE" \
    --threads=16 --time=300 --report-interval=10 \
    run 2>&1 | tee "bench_${ENGINE}.log"
  grep -E 'transactions:|queries:|latency' "bench_${ENGINE}.log"
done
mysql -h "$HOST" -P "$PORT" -u sbtest -psbtest -e "
  SELECT table_schema, engine,
         ROUND(SUM(data_length+index_length)/1024/1024,2) AS total_mb
  FROM information_schema.tables
  WHERE table_schema LIKE 'sbtest_%' GROUP BY table_schema, engine;"
```

### Anti-Patterns

| Anti-Pattern | Why It Fails | Better Approach |
|-------------|-------------|----------------|
| LSM for range-scan-heavy OLAP | Read amplification across levels | B+Tree or columnar store |
| B+Tree for high-velocity time-series | Random I/O from page splits | LSM with FIFO or tiered compaction |
| WiredTiger for multi-doc ACID | Document-level only (pre-4.0) | InnoDB or PostgreSQL |
| Single engine for all workloads | RUM conjecture trade-offs | Polyglot persistence |

---

## 7. Academic References

1. **O'Neil et al. (1996)** — "The Log-Structured Merge-Tree (LSM-Tree)" — Acta Informatica
2. **Athanassoulis et al. (2016)** — "Designing Access Methods: The RUM Conjecture" — EDBT 2016
3. **Luo & Carey (2020)** — "LSM-based Storage Techniques: A Survey" — VLDB Journal
4. **Dong et al. (2021)** — "RocksDB: Evolution of Development Priorities" — FAST'21
5. **Huang et al. (2022)** — "Are B+Trees and LSM-Trees Fundamentally Different?" — FAST'22
6. **Dayan & Idreos (2018)** — "Dostoevsky: Better Space-Time Trade-Offs for LSM-Tree" — SIGMOD'18

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
