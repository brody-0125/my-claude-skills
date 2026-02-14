# Query Plan Analysis Reference — b3-query-plan-analyst Agent

<!-- Agent: b3-query-plan-analyst -->
<!-- Purpose: EXPLAIN plan interpretation for MySQL and PostgreSQL, annotated -->
<!-- real-world examples, red flags identification, and before/after case studies. -->
<!-- Source: split from domain-b-index-scan.md section 6, 7 (GitHub), expanded -->

---

## 1. PostgreSQL EXPLAIN Fundamentals

### Reading Cost Estimates

```
Seq Scan on orders  (cost=0.00..1520.00 rows=50000 width=48)
                         ^start   ^total  ^estimated ^avg_row_bytes
  Filter: (status = 'active')
  Rows Removed by Filter: 450000
```

- **cost** (start..total): Arbitrary units. Sequential page read = 1.0, random page read = 4.0
- **rows**: Estimated row count (compare with `EXPLAIN ANALYZE` actual for accuracy)
- **width**: Average row size in bytes
- **Buffers** (with `ANALYZE, BUFFERS`): shared hit (cache) vs shared read (disk)

### EXPLAIN Variants

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'active';                  -- plan only
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'active';          -- plan + actual
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT * FROM orders WHERE status = 'active'; -- full
```

### Key Node Types

| Node Type | Performance Concern |
|-----------|-------------------|
| Seq Scan | Full table scan -- slow on large tables |
| Index Scan | Good, but heap fetches add I/O |
| Index Only Scan | Best -- no heap access |
| Bitmap Heap Scan | Recheck = lossy bitmap (increase work_mem) |
| Hash Join | Watch for Batches > 1 (disk spill) |
| Sort | Watch for external merge (disk spill) |

---

## 2. PostgreSQL EXPLAIN — Annotated Examples

### Example 1: Sequential Scan (Problem)

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_email = 'alice@example.com';
```

```
Seq Scan on orders  (cost=0.00..25000.00 rows=1 width=120)
                    (actual time=142.50..285.30 rows=1 loops=1)
  Filter: (customer_email = 'alice@example.com'::text)
  Rows Removed by Filter: 999999
  Buffers: shared read=12500
Planning Time: 0.08 ms
Execution Time: 285.35 ms
```

**Diagnosis**: Scanning 1M rows to find 1 match. 12,500 pages read from disk.

**Fix**:
```sql
CREATE INDEX idx_orders_email ON orders (customer_email);
```

**After**:
```
Index Scan using idx_orders_email on orders  (cost=0.42..8.44 rows=1 width=120)
                                              (actual time=0.025..0.026 rows=1 loops=1)
  Index Cond: (customer_email = 'alice@example.com'::text)
  Buffers: shared hit=4
Planning Time: 0.10 ms
Execution Time: 0.04 ms
```

**Improvement**: 285ms -> 0.04ms (7,000x faster). 12,500 page reads -> 4 buffer hits.

### Example 2: Bitmap Index Scan with Lossy Recheck

```
Bitmap Heap Scan on events  (actual time=8.20..125.40 rows=43800)
  Heap Blocks: exact=8500 lossy=2300    <-- lossy = work_mem too low
  Rows Removed by Index Recheck: 1200   <-- false positives from lossy blocks
```

**Fix**: `SET work_mem = '64MB';` -- eliminates lossy blocks, drops time to 98ms.

---

## 3. MySQL EXPLAIN — Annotated Examples

### MySQL EXPLAIN Key Columns

| Column | Key Values | Meaning |
|--------|-----------|---------|
| **type** | system > const > eq_ref > ref > range > index > ALL | Join type (best to worst) |
| **key** | index name or NULL | Actually used index |
| **rows** | integer | Estimated rows to examine |
| **filtered** | percentage | Rows remaining after WHERE filter |
| **Extra** | Using index, Using where, Using temporary, Using filesort | Execution details |

### Example 1: Full Table Scan (type=ALL)

```sql
EXPLAIN SELECT * FROM orders WHERE YEAR(order_date) = 2025;
```

```
+----+------+-------+------+------+----------+-------------+
| id | type | key   | rows | filt | Extra     | table       |
+----+------+-------+------+------+----------+-------------+
|  1 | ALL  | NULL  | 1000000 | 100 | Using where | orders   |
+----+------+-------+------+------+----------+-------------+
```

**Diagnosis**: `type=ALL` with 1M rows. The `YEAR()` function wraps the column, preventing index use.

**Fix**: Rewrite to use sargable predicate:
```sql
-- Use range instead of function
SELECT * FROM orders
WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01';
```

```
+----+-------+------------------+--------+------+-------------------+
| id | type  | key              | rows   | filt | Extra             |
+----+-------+------------------+--------+------+-------------------+
|  1 | range | idx_order_date   | 250000 | 100  | Using index cond  |
+----+-------+------------------+--------+------+-------------------+
```

**Improvement**: ALL -> range. Rows examined: 1M -> 250K.

### Example 2: Using temporary + Using filesort

```
Before: type=ALL, rows=1000000, Extra=Using where; Using temporary; Using filesort
```

**Fix**: `CREATE INDEX idx_orders_status_customer ON orders (status, customer_id);`

```
After:  type=ref, rows=300000, Extra=Using index; Using filesort
```

`Using temporary` eliminated. `Using filesort` remains (ORDER BY on aggregate cannot use index).

---

## 4. Red Flags Table

| Indicator | Problem | Resolution |
|-----------|---------|-----------|
| `type=ALL` (MySQL) | Full table scan | Add appropriate index |
| `Seq Scan` on large table (PG) | Full table scan | Add index, check predicate sargability |
| `Using temporary` | Temp table for GROUP BY/ORDER BY | Optimize query or add covering index |
| `Using filesort` | Sort not satisfied by index | Align index with ORDER BY clause |
| `rows` >> actual rows | Bad statistics | `ANALYZE TABLE` (MySQL) or `ANALYZE` (PG) |
| `filtered < 10%` | Index not selective enough | Consider composite index |
| `Rows Removed by Filter` very high (PG) | Scanning many irrelevant rows | Improve index selectivity |
| `Buffers: shared read` very high (PG) | Cache miss, cold data | Increase shared_buffers or add index |
| `Bitmap Heap Scan` with high `lossy` | work_mem too low for exact bitmap | Increase work_mem |
| `Sort Method: external merge` (PG) | Sort spilled to disk | Increase work_mem |
| `Hash Batches > 1` (PG) | Hash join spilled to disk | Increase work_mem |
| `Select tables optimized away` | Resolved from index metadata | No action (this is good) |

---

## 5. Case Study: GitHub PostgreSQL GIN for Code Search

200M+ repositories. PostgreSQL GIN indexes for structured metadata search (Blackbird engine).

```sql
-- Trigram GIN: flexible LIKE/ILIKE patterns on repo names
CREATE INDEX idx_repos_name_trgm ON repositories USING GIN (name gin_trgm_ops);
-- Plan: Bitmap Index Scan on idx_repos_name_trgm (actual time=1.80 rows=3500)

-- Array GIN: topic containment search
CREATE INDEX idx_repos_topics_gin ON repositories USING GIN (topics);
-- WHERE topics @> ARRAY['machine-learning', 'python']

-- JSONB GIN: language filter
CREATE INDEX idx_repos_languages_gin ON repositories
  USING GIN (language_breakdown jsonb_path_ops);
-- WHERE language_breakdown @> '{"Go": true}'
```

**Results**: <50ms p99 for metadata search. GIN indexes 3-5x larger than B+Tree but enable `ILIKE '%pattern%'` and containment queries.

---

## 6. Before/After Improvement Examples

### Example A: Adding a Partial Index

**Before**:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, assigned_to FROM tickets
WHERE status = 'open' AND priority = 'critical';

-- Seq Scan on tickets  (actual time=0.02..520.00 rows=85 loops=1)
--   Filter: (status = 'open' AND priority = 'critical')
--   Rows Removed by Filter: 2999915
--   Buffers: shared read=42000
-- Execution Time: 520.15 ms
```

**After**: Partial index targeting only the rows that matter:
```sql
CREATE INDEX idx_tickets_critical_open
ON tickets (priority, assigned_to)
WHERE status = 'open';

-- Index Scan using idx_tickets_critical_open  (actual time=0.03..0.28 rows=85 loops=1)
--   Index Cond: (priority = 'critical')
--   Buffers: shared hit=12
-- Execution Time: 0.32 ms
```

**Improvement**: 520ms -> 0.32ms. Index size is tiny because 97% of rows are excluded by the WHERE clause.

### Example B: Fixing a Correlated Subquery

```sql
-- Before: subquery runs 200 times, each scanning 500K rows (4,252ms)
SELECT d.name,
  (SELECT COUNT(*) FROM employees e WHERE e.dept_id = d.id) AS emp_count
FROM departments d;
-- SubPlan 1: loops=200, Seq Scan on employees each time

-- After: rewrite as JOIN (185ms, 23x faster)
SELECT d.name, COUNT(e.id) AS emp_count
FROM departments d LEFT JOIN employees e ON e.dept_id = d.id
GROUP BY d.id, d.name;
-- HashAggregate -> Hash Right Join: single pass through employees
```

### Example C: Eliminating Redundant Sort

```sql
-- Before: index on (user_id) finds 125K rows, then sorts all to get top 50 (85ms)
-- Sort Method: top-N heapsort, Buffers: shared hit=95000
SELECT user_id, event_type, created_at FROM user_events
WHERE user_id = 12345 ORDER BY created_at DESC LIMIT 50;

-- After: composite index matching filter + sort order (0.10ms, 850x faster)
CREATE INDEX idx_events_user_created ON user_events (user_id, created_at DESC);
-- Index Scan: Buffers: shared hit=5 — LIMIT stops after 50 rows
```

---

## 7. Decision Matrix: When to Investigate Query Plans

| Symptom | First Check | Likely Cause | Action |
|---------|------------|-------------|--------|
| Query > 100ms on OLTP | `EXPLAIN ANALYZE` | Missing index or seq scan | Add index, check sargability |
| Query slowed after data growth | Compare `rows` estimate vs actual | Statistics stale | Run `ANALYZE` |
| Intermittent slow queries | `EXPLAIN (ANALYZE, BUFFERS)` | Buffer cache misses | Check shared_buffers, disk I/O |
| Memory pressure on DB server | Check `work_mem` usage | Hash/Sort spilling to disk | Tune work_mem or rewrite query |
| Write throughput degraded | Count indexes per table | Over-indexing | Remove unused indexes |
| Query plan changed unexpectedly | Compare plans with `pg_stat_statements` | Planner chose wrong plan | Pin plan with `pg_hint_plan` or fix stats |

### PostgreSQL-Specific Indicators
- **Bitmap Heap Scan**: Recheck condition means lossy bitmap (too many rows for exact bitmap)
- **Materialize**: Intermediate result cached for repeated access
- **Hash Cond vs Filter**: Hash Cond is efficient (part of hash join); Filter is post-join filtering

### Statistics Maintenance

```sql
-- PostgreSQL                              -- MySQL
ANALYZE orders;                            -- ANALYZE TABLE orders;
-- Check staleness:
SELECT relname, last_analyze, n_dead_tup
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC;
```

---

## 8. Academic References

1. **Hellerstein et al. (2007)** -- "Architecture of a Database System" -- Query processing fundamentals
2. **Graefe (2011)** -- "Modern B-Tree Techniques" -- Foundations and Trends in Databases
3. **Ding et al. (2020)** -- "ALEX: An Updatable Adaptive Learned Index" -- SIGMOD'20
4. **PostgreSQL Documentation** -- "Using EXPLAIN" -- Official guide to query plan interpretation

---

*Last updated: 2025-05. Split from domain-b-index-scan.md for b3-query-plan-analyst agent.*
