# Access Pattern Driven Design Reference
<!-- Agent: d3-access-pattern-modeler -->
<!-- Purpose: Access-pattern-driven schema design — pattern analysis, impact scoring, -->
<!-- hot path identification, decision matrices, and E-Commerce SQL examples. -->
<!-- Source: Extracted from domain-d-normalization.md sections 4, 7 + expanded examples. -->

> Reference for the **d3-access-pattern-modeler** agent.
> Covers access pattern analysis, impact scoring formulas, hot path identification,
> normalization-level decision matrices, and a worked E-Commerce example.

---

## 1. Access Pattern Analysis Process

### Methodology

1. **Enumerate all queries** — every query the application executes
2. **Classify by type** — read vs write, point lookup vs range scan vs aggregation
3. **Rank by frequency** — QPS under normal and peak load
4. **Rank by criticality** — user-facing (critical path) vs background
5. **Compute impact score** — combine frequency + criticality
6. **Model for top patterns** — optimize schema for top 5–10 queries
7. **Verify remaining** — ensure all other queries are feasible

### Impact Score Formula

```
Impact Score = (0.6 × QPS_normalized) + (0.4 × Criticality_score)
```

- `QPS_normalized` = query QPS / max QPS (range 0–1)
- `Criticality_score`: 1.0 = user-facing latency-sensitive, 0.7 = user-facing tolerant,
  0.4 = internal near-real-time, 0.1 = background batch

```sql
CREATE TABLE access_pattern_registry (
    pattern_id     SERIAL PRIMARY KEY,
    pattern_name   VARCHAR(200) NOT NULL,
    query_template TEXT NOT NULL,
    qps_avg        NUMERIC(10,2),
    qps_peak       NUMERIC(10,2),
    criticality    NUMERIC(3,2) CHECK (criticality BETWEEN 0 AND 1),
    impact_score   NUMERIC(5,3) GENERATED ALWAYS AS (
        0.6 * (qps_avg / NULLIF(qps_peak, 0)) + 0.4 * criticality
    ) STORED
);

INSERT INTO access_pattern_registry (pattern_name, query_template, qps_avg, qps_peak, criticality)
VALUES
    ('Get product by ID',       'SELECT … FROM products WHERE id = $1',   8000, 10000, 1.0),
    ('List by category',        'SELECT … WHERE cat = $1 ORDER BY …',     1500, 10000, 0.9),
    ('Order with items',        'SELECT … FROM orders JOIN items …',       800, 10000, 1.0),
    ('Product search',          'SELECT … WHERE tsv @@ to_tsquery($1)',    500, 10000, 0.8),
    ('User order history',      'SELECT … WHERE user_id = $1 ORDER BY …', 400, 10000, 0.7),
    ('Nightly sales report',    'SELECT … GROUP BY …',                    0.01, 10000, 0.1);
```

---

## 2. Hot Path Identification

A **hot path** is the small set of queries dominating the workload. Optimizing
these yields the largest performance gain per engineering effort.

### Identification Techniques

| Technique | Tool | Reveals |
|-----------|------|---------|
| `pg_stat_statements` | PostgreSQL extension | QPS, mean/max time, rows |
| Slow query log | MySQL `long_query_time` | Queries exceeding threshold |
| Application APM | Datadog, New Relic | End-to-end latency |
| Query tagging | `/* pattern:X */` SQL comment | Map DB stats to app patterns |

```sql
-- PostgreSQL: top 10 queries by total execution time
SELECT queryid, LEFT(query, 80) AS preview, calls,
       ROUND(total_exec_time::numeric, 2) AS total_ms,
       ROUND(mean_exec_time::numeric, 2) AS mean_ms
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

### Optimization Checklist

1. Does an appropriate index exist? (`EXPLAIN ANALYZE`)
2. Is the query using the index or doing a seq scan?
3. Can a covering index satisfy it (index-only scan)?
4. Should the data be denormalized (cache table, materialized view)?
5. Can results be cached at app layer (Redis, in-process)?

---

## 3. E-Commerce Platform — Worked Example

### Access Patterns Ranked

| # | Pattern | Type | QPS | Crit. | Impact |
|---|---------|------|-----|-------|--------|
| 1 | Get product by ID | Point read | 8,000 | 1.0 | **0.88** |
| 2 | List by category (sorted) | Range scan | 1,500 | 0.9 | **0.45** |
| 3 | Order with all items | Join | 800 | 1.0 | **0.45** |
| 4 | Product search | FTS | 500 | 0.8 | **0.35** |
| 5 | User order history | Range | 400 | 0.7 | **0.30** |
| 6 | Add to cart | Write | 600 | 0.9 | **0.40** |
| 7 | Place order | Txn | 200 | 1.0 | **0.41** |
| 8 | Nightly report | Agg | 0.01 | 0.1 | **0.04** |

### Schema Decisions

**Pattern 1 — Product by ID (highest impact)**

```sql
CREATE TABLE products (
    id            BIGSERIAL PRIMARY KEY,
    name          VARCHAR(255) NOT NULL,
    category_id   INT NOT NULL,
    category_name VARCHAR(100) NOT NULL,  -- DENORMALIZED for pattern 2
    price         DECIMAL(10,2) NOT NULL,
    stock_qty     INT NOT NULL DEFAULT 0,
    description   TEXT,
    search_vector TSVECTOR,               -- for pattern 4
    created_at    TIMESTAMP DEFAULT NOW()
);

-- Pattern 1: PK lookup, already optimal
SELECT id, name, price, stock_qty, description FROM products WHERE id = 42;
```

**Pattern 2 — Category listing (sorted)**

```sql
CREATE INDEX idx_products_cat_price ON products (category_id, price);

SELECT id, name, price, category_name
FROM products WHERE category_id = 5 ORDER BY price ASC LIMIT 20;
-- EXPLAIN: Index Scan using idx_products_cat_price
```

Decision: `category_name` denormalized — categories change rarely.

**Pattern 3 — Order with items**

```sql
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    item_count INT DEFAULT 0, total DECIMAL(12,2) DEFAULT 0,  -- aggregates
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY, order_id BIGINT NOT NULL REFERENCES orders(id),
    product_id BIGINT NOT NULL, product_name VARCHAR(255) NOT NULL,  -- snapshot
    qty INT NOT NULL, unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (qty * unit_price) STORED
);
CREATE INDEX idx_order_items_order ON order_items (order_id);

SELECT o.id, o.status, o.total, oi.product_name, oi.qty, oi.line_total
FROM orders o JOIN order_items oi ON oi.order_id = o.id WHERE o.id = 1001;
```

**Pattern 4 — Full-text search**

```sql
CREATE INDEX idx_products_search ON products USING GIN (search_vector);

CREATE FUNCTION products_search_trigger() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', NEW.name || ' ' || COALESCE(NEW.description,''));
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_products_search BEFORE INSERT OR UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION products_search_trigger();

SELECT id, name, price, ts_rank(search_vector, q) AS rank
FROM products, to_tsquery('english', 'wireless & headphones') q
WHERE search_vector @@ q ORDER BY rank DESC LIMIT 20;
```

**Pattern 5 — User order history (keyset pagination)**

```sql
CREATE INDEX idx_orders_user_date ON orders (user_id, created_at DESC);

SELECT id, status, total, created_at FROM orders
WHERE user_id = 789 AND created_at < '2025-04-01T00:00:00Z'
ORDER BY created_at DESC LIMIT 20;
```

**Pattern 8 — Nightly report (materialized view)**

```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT DATE(created_at) AS sale_date, COUNT(*) AS order_count, SUM(total) AS revenue
FROM orders WHERE status NOT IN ('cancelled','refunded') GROUP BY DATE(created_at);
CREATE UNIQUE INDEX idx_mv_daily_sales ON mv_daily_sales (sale_date);
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
```

---

## 4. Decision Matrix: Access Pattern to Normalization Level

| Access Pattern | Recommended Level | Denormalization Approach | Trade-off |
|---------------|-------------------|--------------------------|-----------|
| OLTP with complex joins | 3NF | Covering indexes first | Consistency vs read speed |
| Read-heavy API | 3NF + cache tables | Denormalized read models | Staleness vs latency |
| Analytics/reporting | Star schema | Materialized views | Storage vs query speed |
| Document CRUD | Embedded docs | N/A (native) | Flexibility vs consistency |
| Event sourcing | Append-only + projections | Projected read models | Complexity vs auditability |
| Time-series | Bucket (denormalized) | Pre-aggregated rollups | Ingestion vs query flex |
| Search/autocomplete | Inverted index (GIN) | Search projections | Index size vs speed |

### By Read:Write Ratio

| Ratio | Strategy |
|-------|----------|
| < 5:1 | Keep 3NF, optimize indexes |
| 5:1 – 20:1 | Selective denorm (cache tables, embedded aggregates) |
| 20:1 – 100:1 | Aggressive denorm (mat views, read replicas) |
| > 100:1 | Fully denormalized read models, CQRS |

---

## 5. Checklist

```
[ ] All queries enumerated and documented
[ ] QPS measured/estimated (avg + peak)
[ ] Criticality scores assigned
[ ] Impact scores calculated and ranked
[ ] Top 5–10 patterns have optimized schema
[ ] Remaining patterns verified as feasible
[ ] Hot paths identified (pg_stat_statements / APM)
[ ] Denormalization decisions documented with trade-offs
[ ] Index strategy covers all high-impact reads
[ ] Write latency verified
```

---

## 6. References

1. **Kleppmann (2017)** — "Designing Data-Intensive Applications"
2. **Rick Houlihan (2019)** — "Advanced Design Patterns for DynamoDB"
3. **Codd (1970)** — "A Relational Model of Data for Large Shared Data Banks"

---

*Extracted from domain-d-normalization.md for d3-access-pattern-modeler. Last updated: 2025-05.*
