# Join Optimization Reference — b2-join-optimizer Agent

<!-- Agent: b2-join-optimizer -->
<!-- Purpose: Join algorithm internals, practical join tuning, EXPLAIN-based -->
<!-- join analysis, and decision matrices for choosing the optimal join strategy. -->
<!-- Source: split from domain-b-index-scan.md section 5, expanded with examples -->

---

## 1. Join Algorithms

### Nested Loop Join

- **Algorithm**: For each row in outer table, scan inner table for matches
- **Complexity**: O(N * M) without index; O(N * log M) with index on inner table
- **When chosen**: Small outer table, indexed inner table, or very small result set
- **Variants**: Simple, Index, Block (batches outer rows to amortize I/O)
- **Optimization**: Ensure inner table has index on join column

```sql
-- Setup: small departments table joined to large employees table
-- departments: 50 rows, employees: 500,000 rows with index on dept_id
SELECT d.name, e.full_name, e.salary
FROM departments d
JOIN employees e ON e.dept_id = d.id
WHERE d.region = 'APAC';

-- PostgreSQL EXPLAIN ANALYZE output:
-- Nested Loop  (cost=0.43..2845.12 rows=5000 width=64)
--              (actual time=0.035..18.220 rows=4832 loops=1)
--   -> Seq Scan on departments d  (cost=0.00..1.62 rows=5 width=20)
--        Filter: (region = 'APAC')
--        Rows Removed by Filter: 45
--   -> Index Scan using idx_emp_dept on employees e  (cost=0.43..520.70 rows=1000 width=44)
--        Index Cond: (dept_id = d.id)
--        (actual loops=5)
-- Planning Time: 0.15 ms
-- Execution Time: 19.44 ms
```

**Why Nested Loop won here**: Only 5 departments match the filter, and each probes an index on `employees.dept_id`. Total: 5 index lookups instead of a full scan.

### Hash Join

- **Algorithm**: Build hash table from smaller relation, probe with larger relation
- **Complexity**: O(N + M) average case
- **Memory**: Requires `work_mem` (PostgreSQL) or `join_buffer_size` (MySQL) for hash table
- **When chosen**: Large tables without useful indexes, equality joins
- **Spill to disk**: If hash table exceeds memory, uses Grace Hash Join (partition-based)
- **MySQL**: Available since 8.0.18 (previously only Nested Loop)

```sql
-- Setup: joining two large tables with no index on join column
SELECT o.order_id, o.total, c.company_name
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_date >= '2025-01-01';

-- PostgreSQL EXPLAIN ANALYZE output:
-- Hash Join  (cost=1250.00..45820.00 rows=200000 width=52)
--            (actual time=42.10..385.60 rows=198450 loops=1)
--   Hash Cond: (o.customer_id = c.customer_id)
--   -> Seq Scan on orders o  (cost=0.00..35000.00 rows=200000 width=32)
--        Filter: (order_date >= '2025-01-01')
--   -> Hash  (cost=1000.00..1000.00 rows=50000 width=28)
--        Buckets: 65536  Batches: 1  Memory Usage: 3520kB
--        -> Seq Scan on customers c  (cost=0.00..1000.00 rows=50000)
-- Planning Time: 0.35 ms
-- Execution Time: 412.80 ms
```

**Key observation**: `Batches: 1` means hash table fit in memory. `Batches > 1` means disk spill -- increase `work_mem`.

### Merge Join (Sort-Merge Join)

- **Algorithm**: Sort both inputs on join key, merge in single pass
- **Complexity**: O(N log N + M log M) for sort, O(N + M) for merge
- **When chosen**: Both inputs already sorted (from index scan), or very large inputs
- **Advantage**: Handles non-equality predicates (range joins)
- **PostgreSQL**: Materializes inner input if needed for rescan

```sql
-- Setup: both tables have indexes on the join column (pre-sorted)
SELECT t.txn_id, t.amount, a.account_name
FROM transactions t
JOIN accounts a ON a.account_id = t.account_id
WHERE t.txn_date BETWEEN '2025-01-01' AND '2025-03-31';

-- PostgreSQL EXPLAIN ANALYZE output:
-- Merge Join  (cost=0.85..78420.30 rows=300000 width=48)
--             (actual time=0.042..298.15 rows=295120 loops=1)
--   Merge Cond: (t.account_id = a.account_id)
--   -> Index Scan using idx_txn_account on transactions t
--        (cost=0.43..62000.00 rows=300000 width=28)
--        Filter: (txn_date >= '2025-01-01' AND txn_date <= '2025-03-31')
--   -> Index Scan using accounts_pkey on accounts a
--        (cost=0.42..8500.00 rows=200000 width=24)
-- Planning Time: 0.28 ms
-- Execution Time: 325.40 ms
```

**Why Merge Join won**: Both inputs arrive pre-sorted from index scans, so no sort step is needed. The merge phase streams through both in O(N+M).

---

## 2. Join Performance Anti-Patterns

### Anti-Pattern 1: Missing Index on Inner Table

```sql
-- BAD: no index on orders.customer_id forces Nested Loop -> Seq Scan inner
EXPLAIN ANALYZE
SELECT c.name, o.total
FROM customers c
JOIN orders o ON o.customer_id = c.id;

-- Plan: Nested Loop (actual time=0.03..14520.00 rows=500000 loops=1)
--   -> Seq Scan on customers c (rows=10000 loops=1)
--   -> Seq Scan on orders o    (rows=500000 loops=10000)  <-- CATASTROPHIC
--      Filter: (customer_id = c.id)

-- FIX: add index
CREATE INDEX idx_orders_customer ON orders (customer_id);
-- New plan uses Index Scan on inner, time drops from 14.5s to ~50ms
```

### Anti-Pattern 2: Implicit Type Conversion Prevents Index Use

```sql
-- BAD: user_id is INT in users, but VARCHAR in logs
SELECT u.name, l.action
FROM users u
JOIN activity_logs l ON l.user_id = u.id;
-- If l.user_id is VARCHAR and u.id is INT, the planner may cast every row,
-- preventing index use on l.user_id.

-- FIX: ensure matching types or use explicit CAST in index
CREATE INDEX idx_logs_user_cast ON activity_logs ((CAST(user_id AS INTEGER)));
```

### Anti-Pattern 3: Non-Selective Filter Before Join

```sql
-- BAD: status='active' matches 95% of rows — join processes nearly entire table
SELECT * FROM orders o JOIN order_items oi ON oi.order_id = o.id
WHERE o.status = 'active';
-- BETTER: add date filter to narrow the set first
WHERE o.status = 'active' AND o.created_at >= '2025-06-01';
```

---

## 3. MySQL-Specific Join Behavior

```sql
-- Force hash join via hint (MySQL 8.0.18+)
SELECT /*+ HASH_JOIN(o, c) */ o.order_id, c.name
FROM orders o JOIN customers c ON c.id = o.customer_id;

-- MySQL 8.0 EXPLAIN FORMAT=TREE output:
-- -> Nested loop inner join  (cost=4520 rows=50000)
--     -> Filter: (o.order_date >= '2025-01-01')  (cost=2500 rows=50000)
--         -> Table scan on o  (cost=2500 rows=100000)
--     -> Single-row index lookup on c using PRIMARY (id=o.customer_id)
```

---

## 4. Join Tuning: work_mem / join_buffer_size

```sql
-- PostgreSQL: increase work_mem per-transaction
BEGIN;
SET LOCAL work_mem = '256MB';  -- default: 4MB
-- run heavy join query
COMMIT;

-- MySQL: increase join_buffer_size per-session
SET SESSION join_buffer_size = 67108864;  -- 64MB (default: 256KB)
```

- `work_mem` is allocated per-sort-operation, not per-query (5 hash joins = 5x)
- Safe formula: `available_ram / max_connections / avg_operations_per_query`
- Monitor with `EXPLAIN (ANALYZE, BUFFERS)` -- look for `Batches > 1`

---

## 5. Decision Matrix: Choosing the Right Join

### By Row Count Thresholds

| Outer Rows | Inner Rows | Index on Inner? | Best Join | Expected Time |
|-----------|-----------|----------------|----------|--------------|
| < 100 | < 100 | Any | Nested Loop | < 1ms |
| < 100 | > 100K | Yes | Nested Loop (Index) | < 10ms |
| < 100 | > 100K | No | Hash Join | 10-100ms |
| > 10K | > 10K | No | Hash Join | 50-500ms |
| > 10K | > 10K | Both sorted | Merge Join | 50-500ms |
| > 1M | > 1M | No | Hash Join (may spill) | 1-10s |
| > 1M | > 1M | Both sorted | Merge Join | 0.5-5s |

### By Query Characteristics

| Scenario | Best Join | Reason |
|----------|----------|--------|
| Small outer, indexed inner | Nested Loop (Index) | O(N * log M), minimal memory |
| Large tables, no indexes | Hash Join | O(N + M), single pass |
| Both tables sorted/indexed | Merge Join | No sort needed, streaming |
| Very small both (<100 rows) | Nested Loop | Minimal overhead |
| Outer large, inner very small | Hash Join (inner=build) | Tiny hash table, fast probe |
| Non-equality join (range) | Nested Loop or Merge | Hash join requires equality |
| Anti-join (NOT IN / NOT EXISTS) | Hash Anti Join | Single-pass exclusion |
| Semi-join (EXISTS) | Hash Semi Join | Stops at first match per bucket |

### Quick Decision Flowchart

```
Is this an equality join?
  NO  -> Nested Loop (with index) or Merge Join
  YES -> Is one side very small (< 1000 rows)?
           YES -> Nested Loop (Index) if inner has index, else Hash Join
           NO  -> Are both sides pre-sorted (index order)?
                    YES -> Merge Join
                    NO  -> Hash Join
                           -> Check: does hash table fit in work_mem?
                                YES -> Single-batch Hash Join (fast)
                                NO  -> Increase work_mem or accept disk spill
```

---

## 6. EXPLAIN Checklist for Joins

1. **Join type matches expectation** -- Hash Join expected but Nested Loop seen? Check row estimates
2. **No seq scans on large inner tables** -- add index or switch to Hash Join
3. **Hash Batches = 1** -- if > 1, increase work_mem
4. **Merge Join has no Sort node** -- Sort node = index not used for ordering
5. **Row estimates accurate** -- run `ANALYZE` if estimated off by 10x+
6. **Filter vs Join Cond** -- `Filter` is post-join; move predicates to `JOIN ON` when possible

---

## 7. Academic References

1. **Hellerstein et al. (2007)** -- "Architecture of a Database System" -- Query processing fundamentals
2. **Graefe (2011)** -- "Modern B-Tree Techniques" -- Foundations and Trends in Databases
3. **MySQL 8.0 Reference Manual** -- "Hash Join Optimization"
4. **PostgreSQL Documentation** -- "Planner/Optimizer" -- Join strategy selection

---

*Last updated: 2025-05. Split from domain-b-index-scan.md for b2-join-optimizer agent.*
