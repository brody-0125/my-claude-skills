# RocksDB Compaction Strategies Reference — Compaction Strategist Agent

<!-- Agent: a2-compaction-strategist -->
<!-- Purpose: Provides the a2-compaction-strategist agent with deep reference material -->
<!-- for RocksDB/MyRocks compaction strategies, bloom filter tuning, configuration, -->
<!-- and compaction monitoring with quantitative decision thresholds. -->

---

## 1. LSM-Tree Architecture Recap

```
┌──────────────┐
│   Memtable   │  <- SkipList (default) / HashSkipList / Vector
├──────────────┤
│   Memtable   │  <- Immutable, being flushed
│ (Immutable)  │
├──────────────┤
│    Level 0   │  <- Flushed SSTables (may overlap)
├──────────────┤
│    Level 1   │  <- Non-overlapping, compacted
├──────────────┤
│    Level 2   │  <- 10x size of L1 (default multiplier)
├──────────────┤
│    Level N   │  <- Largest level
└──────────────┘
```

- L0 SSTables may overlap; L1+ are non-overlapping within each level
- Level size ratio: 10x default (`max_bytes_for_level_multiplier`)
- Write amplification dominated by compaction rewrites across levels

---

## 2. Compaction Strategies In Depth

### Strategy Comparison Matrix

| Strategy | Write Amp | Space Amp | Read Amp | CPU Cost | Best For |
|----------|-----------|-----------|----------|----------|----------|
| **Leveled** | ~10x | ~1.1x | Low | Medium | Read-heavy, general purpose |
| **Universal** | ~4x | ~2x | Medium | Lower | Write-heavy, batch ingestion |
| **FIFO** | ~1x | ~1x | Low | Minimal | Time-series, TTL data |
| **Lazy Leveling** | ~6x | ~1.2x | Low-Med | Medium | Balanced (Dostoevsky) |

### 2.1 Leveled Compaction

Default strategy. Picks one SSTable from Ln, merges with overlapping files in Ln+1. Each level is 10x larger than previous. Non-overlapping within each level except L0.

```cpp
// Leveled compaction configuration
rocksdb::Options options;
options.compaction_style = rocksdb::kCompactionStyleLevel;
options.max_bytes_for_level_base = 256 * 1024 * 1024;        // 256MB for L1
options.max_bytes_for_level_multiplier = 10;                   // 10x per level
options.level0_file_num_compaction_trigger = 4;
options.level0_slowdown_writes_trigger = 20;
options.level0_stop_writes_trigger = 36;
options.target_file_size_base = 64 * 1024 * 1024;             // 64MB SSTable
```

**Use when**: read latency critical (p99 < 2ms), space budget tight (< 1.2x), workload >60% reads.

### 2.2 Universal (Tiered) Compaction

Groups sorted runs by size. Merges when size ratio threshold exceeded. Lower write amp but higher temporary space.

```cpp
// Universal compaction configuration
rocksdb::Options options;
options.compaction_style = rocksdb::kCompactionStyleUniversal;
options.compaction_options_universal.size_ratio = 1;            // 1% trigger
options.compaction_options_universal.min_merge_width = 2;
options.compaction_options_universal.max_size_amplification_percent = 200;
options.level0_file_num_compaction_trigger = 4;
```

**Use when**: write throughput >100K/s, space not constrained (2x OK), batch/ETL workloads.

### 2.3 FIFO Compaction

Drops oldest SSTables when total size exceeds limit. No merge overhead.

```cpp
// FIFO compaction configuration
rocksdb::Options options;
options.compaction_style = rocksdb::kCompactionStyleFIFO;
options.compaction_options_fifo.max_table_files_size = 100ULL * 1024 * 1024 * 1024; // 100GB
options.ttl = 86400 * 7;  // 7-day TTL
```

**Use when**: time-series with known retention, no old-data lookups, cache-tier use cases.

---

## 3. Bloom Filters

### Configuration Options

| Type | Use Case | Memory | False Positive Rate |
|------|----------|--------|-------------------|
| Full key bloom | Point queries | ~1.2 bytes/key (10 bits) | ~1% |
| Prefix bloom | Range queries with known prefix | Varies | Depends on prefix |
| Partitioned bloom | Large datasets (>1B keys) | Same total | Same, better cache locality |

```cpp
// Bloom filter configuration
rocksdb::BlockBasedTableOptions table_options;
// Full key bloom — best for point lookups
table_options.filter_policy.reset(rocksdb::NewBloomFilterPolicy(10, false));
// Partitioned bloom — better cache locality
table_options.partition_filters = true;
table_options.index_type = rocksdb::BlockBasedTableOptions::kTwoLevelIndexSearch;
// Prefix bloom — for range scans with known prefix
options.prefix_extractor.reset(rocksdb::NewFixedPrefixTransform(8));
options.memtable_prefix_bloom_size_ratio = 0.1;
```

### Sizing Guide

| Keys | Bits/Key | Memory | FP Rate |
|------|----------|--------|---------|
| 100M | 10 | ~120 MB | ~1.0% |
| 100M | 15 | ~180 MB | ~0.1% |
| 1B | 10 | ~1.2 GB | ~1.0% |
| 1B | 15 | ~1.8 GB | ~0.1% |

Rule of thumb: 10 bits/key for most workloads. Increase to 15 only if reducing FP from 1% to 0.1% yields measurable latency gains.

---

## 4. MyRocks Specifics

| Metric | InnoDB | MyRocks | Winner |
|--------|--------|---------|--------|
| Storage footprint | 1x | ~0.5x | MyRocks |
| Write amplification | 10-30x | 2-10x | MyRocks |
| Read latency (point) | 0.1-0.5ms | 0.3-1.0ms | InnoDB |
| Compression ratio | ~1.5-2x | ~3-5x (zstd) | MyRocks |

```ini
# my.cnf — MyRocks write-heavy OLTP configuration
[mysqld]
default-storage-engine = ROCKSDB
rocksdb_db_write_buffer_size         = 4G
rocksdb_write_buffer_size            = 256M
rocksdb_max_write_buffer_number      = 4
rocksdb_max_background_compactions   = 8
rocksdb_max_background_flushes       = 4
rocksdb_compaction_sequential_deletes = 14999
rocksdb_compaction_sequential_deletes_window = 15000
rocksdb_default_cf_options = "
  write_buffer_size=256m;target_file_size_base=64m;
  max_bytes_for_level_base=256m;level0_file_num_compaction_trigger=4;
  compression=kLZ4Compression;bottommost_compression=kZSTD;
  filter_policy=bloomfilter:10:false;optimize_filters_for_hits=true"
rocksdb_rate_limiter_bytes_per_sec   = 200M
```

Facebook UDB results: 50% storage reduction (tens of PB saved), write amp 30x -> 10x, p99 read latency 2ms -> 4ms (accepted trade-off).

---

## 5. Compaction Monitoring

```bash
#!/usr/bin/env bash
# compaction-monitor.sh — Monitor RocksDB compaction via MyRocks
HOST="${1:-127.0.0.1}"; PORT="${2:-3306}"
mysql -h "$HOST" -P "$PORT" -u monitor -pmonitor -e "
  SELECT * FROM information_schema.ROCKSDB_COMPACTION_STATS ORDER BY CF_NAME, LEVEL;"
mysql -h "$HOST" -P "$PORT" -u monitor -pmonitor -e "
  SHOW STATUS LIKE 'rocksdb_stall%';
  SHOW STATUS LIKE 'rocksdb_bloom_filter%';"
```

```bash
# Native RocksDB stats via LOG file
grep -E "Compaction Stats|Level|Cumulative" /data/rocksdb/LOG | tail -30
grep "bloom" /data/rocksdb/LOG | tail -10
# bloom.filter.useful = true negatives, bloom.filter.full.positive = false positives
```

### Alert Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| L0 file count | > 10 | > 20 | Increase compaction threads or reduce write rate |
| Write stall duration | > 100ms/min | > 1s/min | Tune L0 triggers, increase write buffer |
| Space amplification | > 1.5x | > 2.0x | Switch universal->leveled, or manual compaction |
| Pending compaction bytes | > 50GB | > 100GB | Increase `max_background_compactions` |
| Bloom filter FP rate | > 2% | > 5% | Increase bits_per_key or fix prefix config |

---

## 6. Compaction Decision Matrix

### Primary Decision Criteria

| Criterion | Leveled | Universal | FIFO |
|-----------|---------|-----------|------|
| Read/write ratio > 3:1 | **Yes** | Acceptable | No |
| Read/write ratio < 1:1 | No | **Yes** | If TTL data |
| Space budget < 1.3x | **Yes** | No | **Yes** |
| Write throughput > 100K/s | Risky (stalls) | **Yes** | **Yes** |
| Data has natural TTL | Acceptable | Acceptable | **Yes** |
| Deletes > 30% of ops | **Yes** (reclaim) | Slow reclaim | N/A |

### Quantitative Thresholds for Strategy Switching

```
IF write_stall_duration > 500ms/min AND style == leveled:
    → Switch to universal OR increase max_background_compactions to min(cores/2, 16)

IF space_amplification > 1.8x AND style == universal:
    → Switch to leveled OR reduce max_size_amplification_percent

IF data_ttl IS defined AND point_lookups_on_old_data < 1%:
    → Switch to FIFO; set max_table_files_size = expected_volume * 1.1

IF bloom_filter_fp_rate > 3%:
    → Increase bits_per_key 10→15; use partitioned bloom for >1B keys

IF pending_compaction_bytes > 100GB consistently:
    → Increase rate_limiter OR reduce write_buffer_size for smaller flushes
```

### Migration Checklist: Leveled to Universal
1. Benchmark on staging (expect 2-3x write throughput gain)
2. Verify disk headroom for 2x space amplification
3. Set `max_size_amplification_percent = 200` as guardrail
4. Monitor L0 file count and read latency regression for 72+ hours

---

## 7. Academic References (Compaction-Focused)

1. **O'Neil et al. (1996)** — "The Log-Structured Merge-Tree" — Acta Informatica
2. **Dong et al. (2021)** — "RocksDB: Evolution of Development Priorities" — FAST'21
3. **Dayan & Idreos (2018)** — "Dostoevsky: Better Space-Time Trade-Offs for LSM-Tree" — SIGMOD'18
4. **Luo & Carey (2020)** — "LSM-based Storage Techniques: A Survey" — VLDB Journal
5. **Huang et al. (2022)** — "Are B+Trees and LSM-Trees Fundamentally Different?" — FAST'22

---

*Last updated: 2025-05. Sources include RocksDB wiki, Facebook engineering blog, MyRocks documentation, and peer-reviewed publications.*
