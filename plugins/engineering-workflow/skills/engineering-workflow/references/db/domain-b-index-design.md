# Index Design Reference — b1-index-architect Agent

<!-- Agent: b1-index-architect -->
<!-- Purpose: B+Tree internals, index type selection, covering index design, -->
<!-- composite index column ordering, and real-world index strategy case studies. -->
<!-- Source: split from domain-b-index-scan.md sections 1-4, 7 (partial), 8 -->

---

## 1. B+Tree Index Internals

### Structure

```
                    [Root: 50|100]
                   /       |       \
         [20|35]      [70|85]      [120|150]
         /  |  \      /  |  \      /   |   \
       [10,15] [25,30] [40,45] [55,65] [75,80] [90,95] ...
        Leaf pages linked: <- [10,15] <-> [25,30] <-> [40,45] -> ...
```

### Leaf Page Structure
- **Page header**: page type, checksum, LSN, free space offset
- **Record directory**: slots pointing to records within the page
- **Records**: key + value (clustered) or key + PK pointer (secondary)
- **Free space**: grows from middle (directory grows down, records grow up)
- **Page size**: typically 8KB (PostgreSQL) or 16KB (InnoDB)

### Fill Factor
- Controls how full leaf pages are during initial index build
- Default: 90% (PostgreSQL), 100% for leaf / 15/16 for non-leaf (InnoDB)
- Lower fill factor: leaves room for future inserts, reduces page splits
- Trade-off: lower fill factor = more pages = larger index = more I/O for scans
- Recommendation: 70-80% for frequently updated indexes, 90-100% for read-only

### Page Splits — How They Happen

```
Before insert of key 33 into full page [25,28,30,35]:
  Page A: [25, 28, 30, 35]  (full)

After split:
  Page A: [25, 28]           (left half)
  Page B: [30, 33, 35]       (right half, new key inserted)
  Parent updates to include pointer to Page B with separator key 30.
```

- Splits propagate upward if the parent node is also full (cascading split)
- Monotonically increasing keys (auto-increment) always split the rightmost page
- Random keys (UUID v4) cause splits throughout the tree -- 2-3x more random I/O

### Fragmentation
- **Internal fragmentation**: wasted space within pages (from deletes/updates)
- **External fragmentation**: logical order differs from physical order on disk
- Detection: `pg_stat_user_indexes` (PostgreSQL), `SHOW INDEX` + fragmentation% (InnoDB)
- Resolution: `REINDEX` (PostgreSQL), `ALTER TABLE ... ENGINE=InnoDB` (MySQL), `OPTIMIZE TABLE`
- Impact: 2-5x performance degradation when fragmentation exceeds 30%

---

## 2. Index Types

### Hash Index
- **Mechanism**: Hash function maps key to bucket, O(1) average for point lookups
- **Limitations**: No range scans, no ordering, hash collisions degrade to O(n)
- **PostgreSQL**: Persistent hash indexes since v10, WAL-logged
- **Use case**: Exact equality on high-cardinality columns (UUID, session_id)

```sql
-- PostgreSQL: persistent hash index for session lookups
CREATE INDEX idx_sessions_token_hash ON sessions USING hash (session_token);
-- Supported: WHERE session_token = 'abc123def456'
-- NOT supported: WHERE session_token > 'abc'  (falls back to seq scan)
```

### GIN (Generalized Inverted Index) -- PostgreSQL
- **Structure**: Maps each element/token to a posting list of row IDs
- **Best for**: Full-text search (`tsvector`), JSONB containment (`@>`), array membership
- **Write overhead**: 3-10x slower inserts (posting list maintenance); `fastupdate` helps
- **Size**: Typically 2-5x larger than B+Tree on same column

```sql
-- Full-text search
WHERE document_tsvector @@ to_tsquery('english', 'database & index');
-- JSONB containment
WHERE metadata @> '{"type": "click", "source": "mobile"}';
-- Array overlap
WHERE tags @> ARRAY['electronics', 'sale'];
```

### GiST (Generalized Search Tree) -- PostgreSQL
- **Structure**: Balanced tree with lossy internal nodes
- **Best for**: Geometric data, range types, nearest-neighbor (KNN with `<->`)
- **Trade-off vs GIN**: GiST is faster to update, GIN is faster to search

```sql
-- PostGIS: spatial proximity query
CREATE INDEX idx_stores_location ON stores USING gist (geom);
SELECT name FROM stores
ORDER BY geom <-> ST_MakePoint(-73.99, 40.73)::geography LIMIT 10;
```

### BRIN (Block Range Index) -- PostgreSQL
- **Structure**: Stores min/max summary per range of physical pages (default 128 pages)
- **Size**: Orders of magnitude smaller than B+Tree (1MB vs 20GB for 1TB table)
- **Best for**: Large append-only tables with naturally ordered data (timestamps, sequential IDs)
- **Limitation**: Useless if data is randomly distributed across pages

```sql
CREATE INDEX idx_logs_created_brin ON event_logs USING brin (created_at)
  WITH (pages_per_range = 64);
```

### Bitmap Index (Oracle, PostgreSQL runtime)
- **Best for**: Low-cardinality columns (status, boolean); PostgreSQL creates at runtime
- **Oracle**: Persistent bitmap indexes for data warehouse star schema joins

---

## 3. Covering Index & Index-Only Scan

### Concept
A covering index contains all columns needed to satisfy a query, eliminating the need to access the heap/table.

### Implementation

```sql
-- Query
SELECT user_id, email, created_at FROM users WHERE email = 'user@example.com';

-- Covering index (PostgreSQL INCLUDE syntax)
CREATE INDEX idx_users_email_covering
ON users (email) INCLUDE (user_id, created_at);

-- InnoDB covering index (all columns in index)
CREATE INDEX idx_users_email_covering
ON users (email, user_id, created_at);
```

### PostgreSQL INCLUDE Columns (v11+)
- `INCLUDE` columns stored in leaf pages only (not in internal nodes)
- Reduces internal node size -> shallower tree -> faster traversal
- Not usable for search predicates, only for returning data
- Maintains uniqueness only on key columns: `CREATE UNIQUE INDEX ... ON t(a) INCLUDE (b)`

### InnoDB Covering Index
- No `INCLUDE` syntax; all index columns are searchable
- Secondary index leaf pages store: indexed columns + PK columns
- "Using index" in EXPLAIN Extra means index-only scan achieved

### Visibility Map & Performance (PostgreSQL)
- Index-only scan requires visibility map; VACUUM maintains it
- Index-only scan: 2-10x faster than index scan + heap fetch
- Trade-off: larger index size, more write overhead

### Practical Example: Turning a Slow Query into an Index-Only Scan

```sql
-- Before: index on (tenant_id) only
EXPLAIN ANALYZE
SELECT tenant_id, order_date, total
FROM orders
WHERE tenant_id = 42 AND order_date >= '2025-01-01';

-- Plan: Index Scan using idx_orders_tenant on orders
--   -> Heap Fetches: 85,320    <-- expensive random I/O
--   Execution Time: 340.22 ms

-- After: covering index
CREATE INDEX idx_orders_tenant_covering
ON orders (tenant_id, order_date) INCLUDE (total);

-- Plan: Index Only Scan using idx_orders_tenant_covering
--   -> Heap Fetches: 0          <-- no heap access
--   Execution Time: 12.55 ms   <-- 27x faster
```

---

## 4. Composite Index Design

### Column Order Rules

**Rule 1: Equality columns first, range columns last**
```sql
-- Query: WHERE status = 'active' AND created_at > '2024-01-01'
-- Good: (status, created_at) -- equality on status, range on created_at
-- Bad:  (created_at, status) -- range on created_at stops further index use
```

**Rule 2: Higher selectivity columns earlier (for equality-only queries)**
```sql
-- If user_id has 1M distinct values, status has 5:
-- (user_id, status) -- better for WHERE user_id = X AND status = 'active'
-- But: consider which columns appear in most queries
```

**Rule 3: Prefix rule -- leftmost prefix must be used**
```sql
-- Index: (a, b, c)
-- Uses index: WHERE a = 1; WHERE a = 1 AND b = 2; WHERE a = 1 AND b = 2 AND c = 3
-- Cannot use: WHERE b = 2; WHERE c = 3; WHERE b = 2 AND c = 3
```

**Rule 4: ORDER BY alignment**
```sql
-- Index: (a, b, c)
-- Can avoid sort: ORDER BY a, b, c; ORDER BY a, b; ORDER BY a
-- Cannot avoid sort: ORDER BY b, c; ORDER BY a, c (gap in b)
-- Mixed direction: ORDER BY a ASC, b DESC needs (a ASC, b DESC) index (PG v11+)
```

### Composite Index Size Estimation
```
Index size ~ (key_size + pointer_size) * num_rows * overhead_factor
key_size = sum of column sizes (e.g., INT=4B, BIGINT=8B, VARCHAR(n)=avg_len+2B)
pointer_size = 6B (InnoDB) or 6-8B (PostgreSQL TID)
overhead_factor = 1.3-1.5 (page overhead, fill factor)
```

### Multi-Query Index Consolidation

When multiple queries share a column prefix, a single composite index can serve all of them:

```sql
-- Query A: WHERE tenant_id = ? AND status = ?
-- Query B: WHERE tenant_id = ? AND created_at > ?
-- Query C: WHERE tenant_id = ? AND status = ? AND created_at > ?

-- One index serves all three:
CREATE INDEX idx_consolidated ON orders (tenant_id, status, created_at);

-- Query A: uses first two columns (equality, equality)
-- Query B: uses first column (equality), skips status, range on created_at
--          -> partial benefit (only tenant_id prefix used, then filter)
-- Query C: uses all three columns perfectly
```

To also optimize Query B, consider a second index:
```sql
CREATE INDEX idx_tenant_date ON orders (tenant_id, created_at);
```

---

## 5. Case Studies: Index Design in Production

### Slack: Index Optimization for Message Search

- Clustered index `(channel_id, ts)` for primary access pattern
- Secondary index `(user_id, ts)` for "my messages" queries
- Avoided over-indexing: each additional index adds write overhead

```sql
-- Primary access: latest messages in a channel (clustered, no sort needed)
SELECT msg_id, user_id, content, ts FROM messages
WHERE channel_id = 'C0123ABCDEF' ORDER BY ts DESC LIMIT 50;
```

**Results**: Channel lookup <5ms p99; index maintenance <15% of write cost.

### Shopify: Multi-Tenant Index Strategy

- **Tenant prefix on every index**: `(shop_id, ...)` as first column -- prevents cross-tenant scans
- Pod-based sharding with Rails middleware injecting `shop_id` into every query

```sql
-- Every query uses tenant prefix index
SELECT * FROM orders
WHERE shop_id = 98765 AND financial_status = 'paid'
  AND created_at >= '2025-01-01'
ORDER BY created_at DESC LIMIT 20;
-- Index: (shop_id, financial_status, created_at)
```

**Results**: Median <2ms, index sizes 30-40% of table sizes, 99.9% index utilization.

---

## 6. Decision Matrix: Query Pattern to Index Type

| Query Pattern | Recommended Index | Estimated Speedup | Notes |
|--------------|------------------|-------------------|-------|
| Equality on high-cardinality column | B+Tree or Hash | 100-1000x vs seq scan | Hash only for pure equality |
| Range scan (date/numeric) | B+Tree | 10-100x vs seq scan | Column must be first/leftmost |
| Multi-column equality + range | Composite B+Tree | 50-500x vs seq scan | Equality columns first, range last |
| Full-text search | GIN (tsvector) | 100-10000x vs LIKE | Requires tsvector column + to_tsquery |
| JSONB containment | GIN (jsonb_path_ops) | 50-500x vs seq scan | `jsonb_path_ops` is smaller than default |
| Pattern match (`LIKE '%x%'`) | GIN (pg_trgm) | 10-100x vs seq scan | Trigram minimum 3 chars |
| Spatial/geometric | GiST (PostGIS) | 100-1000x vs seq scan | R-tree structure under GiST |
| Large sequential table, correlated | BRIN | 10-100x vs seq scan | Index size: KB vs GB |
| Covering all query columns | B+Tree + INCLUDE | 2-10x vs index+heap | Eliminates heap access |
| Low-cardinality filter | Bitmap (runtime) | 5-20x vs seq scan | PostgreSQL auto-creates at runtime |

### Index Count Guidelines
- OLTP tables: 3-5 indexes maximum (more = slower writes)
- Read-replica query tables: 5-10 indexes acceptable
- Analytics tables: consider BRIN + targeted B+Tree
- Monitor: ratio of index size to table size (target: < 50% for OLTP)

### Index Selection Flowchart

```
Is the column used for equality only?
  YES -> Cardinality > 10,000?
           YES -> B+Tree (or Hash if no range/sort needed)
           NO  -> Consider partial index or bitmap (runtime)
  NO  -> Range or ORDER BY?
           YES -> B+Tree (ensure column is leftmost in composite)
           NO  -> Full-text / JSONB / Array / Spatial?
                    YES -> GIN (text/json/array) or GiST (spatial/range)
                    NO  -> Large append-only table, correlated column?
                             YES -> BRIN
                             NO  -> B+Tree (default safe choice)
```

---

## 7. Academic References

1. **Graefe (2011)** -- "Modern B-Tree Techniques" -- Foundations and Trends in Databases
2. **Kim et al. (2022)** -- "Revisiting B+-Tree Indexing for Modern Hardware" -- SIGMOD'22
3. **Idreos et al. (2018)** -- "The Data Calculator" -- VLDB'18
4. **PostgreSQL Documentation** -- "Index Types" -- GIN, GiST, BRIN, Hash implementations

---

*Last updated: 2025-05. Split from domain-b-index-scan.md for b1-index-architect agent.*
