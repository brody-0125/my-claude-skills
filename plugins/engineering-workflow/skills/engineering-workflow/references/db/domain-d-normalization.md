# Data Modeling & Normalization Reference

> Static reference for data modeling decisions.
> Covers normal forms, denormalization patterns, document modeling, and real-world case studies.

---

## 1. Normal Forms

### First Normal Form (1NF)
**Rule**: All columns contain atomic (indivisible) values; no repeating groups.

```
-- Violation: repeating group in single column
| order_id | products              |
|----------|-----------------------|
| 1        | "Widget, Gadget"      |  <- Non-atomic

-- 1NF compliant: separate rows
| order_id | product  |
|----------|----------|
| 1        | Widget   |
| 1        | Gadget   |
```

**Practical impact**: Enables indexing, filtering, and joining on individual values. Violations force application-level parsing.

### Second Normal Form (2NF)
**Rule**: 1NF + every non-key column depends on the entire primary key (no partial dependencies).
**Applies to**: Composite primary keys only.

```
-- Violation: student_name depends only on student_id, not on (student_id, course_id)
| student_id | course_id | student_name | grade |
|------------|-----------|-------------|-------|
| 1          | CS101     | Alice       | A     |
| 1          | CS201     | Alice       | B     |  <- student_name duplicated

-- 2NF compliant: separate tables
Students: | student_id | student_name |
Grades:   | student_id | course_id | grade |
```

**Practical impact**: Eliminates update anomalies where changing student_name requires updating multiple rows.

### Third Normal Form (3NF)
**Rule**: 2NF + no transitive dependencies (non-key column depends on another non-key column).

```
-- Violation: department_name depends on department_id, which depends on employee_id
| employee_id | department_id | department_name |
|-------------|--------------|-----------------|
| 1           | D10          | Engineering     |
| 2           | D10          | Engineering     |  <- department_name duplicated

-- 3NF compliant: separate tables
Employees:   | employee_id | department_id |
Departments: | department_id | department_name |
```

**Practical impact**: Eliminates data redundancy and insertion/update/deletion anomalies.

### Boyce-Codd Normal Form (BCNF)
**Rule**: Every determinant is a candidate key. Stricter than 3NF.

```
-- 3NF but not BCNF:
-- Scenario: Students, Subjects, Professors
-- Constraint: Each professor teaches exactly one subject
-- FDs: {student, subject} -> professor, professor -> subject

| student | subject | professor |
|---------|---------|-----------|
| Alice   | Math    | Dr. Smith |
| Bob     | Math    | Dr. Jones |
| Alice   | CS      | Dr. Lee   |

-- Professor -> Subject is a FD, but Professor is not a candidate key
-- BCNF compliant: decompose
Teaching:   | professor | subject |
Enrollment: | student | professor |
```

**Practical impact**: BCNF violations are rare in practice. When they occur, decomposition may lose functional dependencies that need to be enforced via application logic or triggers.

### Normal Form Summary

| Normal Form | Requirement | Eliminates |
|------------|------------|-----------|
| 1NF | Atomic values, no repeating groups | Multi-valued columns |
| 2NF | No partial dependencies on composite PK | Redundancy from partial key dependence |
| 3NF | No transitive dependencies | Redundancy from non-key dependencies |
| BCNF | Every determinant is candidate key | All remaining FD-based anomalies |

**Industry practice**: Most production schemas target 3NF with selective denormalization for performance.

---

## 2. Denormalization Patterns

### When to Denormalize
- Read queries significantly outnumber writes (>10:1 ratio)
- Join performance is unacceptable despite proper indexing
- Data consistency lag is tolerable (eventual consistency OK)
- Query patterns are well-known and stable

### Pattern: Materialized Views
```sql
-- PostgreSQL
CREATE MATERIALIZED VIEW monthly_sales AS
SELECT
    product_id,
    date_trunc('month', order_date) AS month,
    SUM(amount) AS total_sales,
    COUNT(*) AS order_count
FROM orders
GROUP BY product_id, date_trunc('month', order_date);

-- Refresh strategies
REFRESH MATERIALIZED VIEW monthly_sales;                    -- Full refresh (blocking)
REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_sales;       -- Non-blocking (requires unique index)
```
- **Use case**: Pre-computed aggregates for dashboards, reports
- **Trade-off**: Stale data between refreshes, storage overhead
- **Refresh frequency**: Depends on tolerance — every minute to every hour

### Pattern: Summary Tables
```sql
-- Incrementally maintained summary
CREATE TABLE daily_metrics (
    date DATE NOT NULL,
    metric_name VARCHAR(50) NOT NULL,
    metric_value BIGINT NOT NULL,
    updated_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (date, metric_name)
);

-- Update via trigger or batch job
INSERT INTO daily_metrics (date, metric_name, metric_value)
VALUES (CURRENT_DATE, 'orders', 1)
ON CONFLICT (date, metric_name)
DO UPDATE SET metric_value = daily_metrics.metric_value + 1,
              updated_at = NOW();
```
- **Advantage over materialized view**: Incrementally updated, always current
- **Trade-off**: More complex maintenance logic, potential for drift

### Pattern: Cache Tables (Denormalized Read Models)
```sql
-- Denormalized user profile cache
CREATE TABLE user_profile_cache (
    user_id BIGINT PRIMARY KEY,
    username VARCHAR(100),
    email VARCHAR(255),
    follower_count INT,
    post_count INT,
    last_post_at TIMESTAMP,
    avatar_url TEXT,
    updated_at TIMESTAMP
);
```
- **Use case**: API responses that aggregate from multiple normalized tables
- **Maintenance**: Updated via application events, change-data-capture, or periodic sync
- **Invalidation**: Time-based TTL, event-driven, or hybrid

### Pattern: Embedding Aggregates
```sql
-- Store computed values directly on parent row
ALTER TABLE orders ADD COLUMN item_count INT DEFAULT 0;
ALTER TABLE orders ADD COLUMN total_amount DECIMAL(12,2) DEFAULT 0;

-- Maintained via trigger
CREATE TRIGGER update_order_totals
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION recalculate_order_totals();
```

---

## 3. Document Modeling: Embedding vs Referencing

### Embedding Decision Framework

| Factor | Embed | Reference |
|--------|-------|-----------|
| **Relationship** | 1:1, 1:few | 1:many, many:many |
| **Access pattern** | Always read together | Independent access |
| **Update frequency** | Rarely updated | Frequently updated independently |
| **Data size** | Subdocument < 1KB | Large or growing subdocuments |
| **Atomicity** | Need atomic updates | Independent lifecycle |
| **Duplication** | Acceptable (denormalized) | Not acceptable |

### Embedding (Subdocument)
```json
{
    "_id": "order_123",
    "customer_name": "Alice",
    "items": [
        {"product": "Widget", "qty": 2, "price": 9.99},
        {"product": "Gadget", "qty": 1, "price": 24.99}
    ],
    "shipping_address": {
        "street": "123 Main St",
        "city": "Springfield",
        "zip": "62701"
    }
}
```
- **Advantages**: Single read, atomic updates, data locality
- **Risks**: Document growth (array items), 16MB BSON limit (MongoDB), update complexity for nested arrays

### Referencing (Normalized)
```json
// orders collection
{"_id": "order_123", "customer_id": "cust_456", "item_ids": ["item_1", "item_2"]}

// items collection
{"_id": "item_1", "product": "Widget", "qty": 2, "price": 9.99}
{"_id": "item_2", "product": "Gadget", "qty": 1, "price": 24.99}
```
- **Advantages**: No duplication, independent updates, no size limit concerns
- **Risks**: Multiple reads (N+1 problem), no atomic cross-document updates (pre-4.0 MongoDB)

### Hybrid Pattern (Extended Reference)
```json
// Store frequently-accessed reference data inline, keep full data in separate collection
{
    "_id": "order_123",
    "customer": {
        "customer_id": "cust_456",
        "name": "Alice"           // Embedded summary
    },
    "item_ids": ["item_1", "item_2"]  // Referenced for full detail
}
```

### MongoDB-Specific Guidelines
- **16MB document limit**: Plan for maximum document size including array growth
- **Working set**: Frequently accessed documents should fit in WiredTiger cache
- **Index on embedded fields**: `db.orders.createIndex({"items.product": 1})` — works but increases index size
- **$lookup**: Server-side join (aggregation pipeline), useful but less efficient than application-level

---

## 4. Access Pattern Driven Design

### Process
1. **List all queries**: Identify every query the application will execute
2. **Rank by frequency**: Which queries run most often?
3. **Rank by criticality**: Which queries are on the critical path (user-facing)?
4. **Model for top queries**: Design schema to optimize top 5-10 queries
5. **Verify remaining queries**: Ensure remaining queries are feasible (even if slower)

### Example: E-Commerce Platform

**Top queries identified:**
1. Get product by ID (80% of reads)
2. List products by category with sorting (15% of reads)
3. Get order with all items for display (critical path)
4. Search products by keyword (5% of reads)
5. Get user's order history (user-facing)

**Schema decisions:**
- Products table: denormalize category_name into products (avoids join for query 2)
- Orders: embed order_items (always read together for query 3)
- Products: GIN index on search_vector for query 4
- Orders: composite index (user_id, created_at DESC) for query 5

---

## 5. Schema Evolution Strategies

### Additive Changes (Safe)
- **Add nullable column**: `ALTER TABLE t ADD COLUMN new_col TYPE` — no data rewrite needed
- **Add index**: `CREATE INDEX CONCURRENTLY` (PostgreSQL) — non-blocking
- **Add table**: No impact on existing schema
- **Add default value**: Safe in PostgreSQL 11+ (stored in catalog, not rewritten)

### Dangerous Changes
- **Remove column**: May break existing queries; use deprecation period
- **Rename column**: Breaks all queries referencing old name; use view as alias
- **Change column type**: May require data rewrite; test with `pg_repack` or `pt-online-schema-change`
- **Add NOT NULL without default**: Fails if existing rows have NULL

### Backward-Compatible Migration Pattern
```
Phase 1: Add new column (nullable)
Phase 2: Deploy code that writes to both old and new columns
Phase 3: Backfill new column for existing rows
Phase 4: Deploy code that reads from new column
Phase 5: Remove old column (after verification period)
```

### Tools
- **PostgreSQL**: `pg_repack`, `pgroll` for zero-downtime migrations
- **MySQL**: `gh-ost` (GitHub), `pt-online-schema-change` (Percona) — online DDL alternatives
- **ORM migrations**: Flyway, Liquibase, Django migrations, Rails ActiveRecord migrations

---

## 6. Case Studies

### Instagram: Denormalized Feed Storage

**Challenge**
- 2B+ monthly active users, each with personalized feed
- Feed generation: complex ranking over posts from followed accounts
- Naive approach: query all followed accounts' posts at read time — too slow at scale

**Architecture**
- Fan-out-on-write: When user posts, write to all followers' feed tables
- Denormalized feed table: `(user_id, post_id, score, created_at)` per user
- Feed read: single range scan on user_id with ORDER BY score DESC

**Key Decisions**
- Trade-off: Write amplification (celebrity posts fan out to millions) vs read simplicity
- Hybrid: Fan-out-on-write for normal users, fan-out-on-read for celebrities (>10K followers)
- Feed table: Cassandra (wide-row, time-series friendly)
- Metadata: PostgreSQL (user profiles, relationships, post details)

**Quantitative Data**
- Feed read latency: <100ms p99 (single partition scan in Cassandra)
- Write fan-out: median ~200 followers, p99 ~50K followers
- Storage: ~500 bytes per feed entry, sharded by user_id

### MongoDB Atlas: Document Modeling Best Practices

**Official Patterns (from MongoDB documentation)**

| Pattern | Description | Use Case |
|---------|-----------|----------|
| **Attribute** | Key-value pairs as array of subdocuments | Polymorphic attributes (product specs) |
| **Bucket** | Group time-series data into time-bounded documents | IoT sensor data, logs |
| **Computed** | Pre-compute and store derived values | Dashboards, leaderboards |
| **Extended Reference** | Embed subset of referenced document | Avoid joins for frequently accessed fields |
| **Outlier** | Handle documents that exceed typical patterns differently | Celebrity follower lists, viral content |
| **Subset** | Embed most recent/relevant subset, reference full set | Recent reviews, top comments |

**16MB Limit Strategies**
- Monitor document size: `Object.bsonsize(db.collection.findOne({_id: id}))`
- Use Bucket pattern: cap array at N elements, create overflow document
- Use Subset pattern: keep only last N items embedded, archive the rest
- GridFS: for documents/files exceeding 16MB (stores in chunks)

### DynamoDB: Single-Table Design

**Philosophy**
- Model all entities in a single table using composite keys
- Partition key (PK) + Sort key (SK) form composite primary key
- Global Secondary Indexes (GSI) enable additional access patterns
- "GSI overloading": use generic attribute names (GSI1PK, GSI1SK) to support multiple entity types

**Example: E-Commerce Single Table**
```
| PK              | SK                  | Data Attributes          |
|-----------------|---------------------|--------------------------|
| USER#alice      | PROFILE             | {name, email, ...}       |
| USER#alice      | ORDER#2024-001      | {total, status, ...}     |
| USER#alice      | ORDER#2024-002      | {total, status, ...}     |
| ORDER#2024-001  | ITEM#widget         | {qty, price, ...}        |
| ORDER#2024-001  | ITEM#gadget         | {qty, price, ...}        |
| PRODUCT#widget  | METADATA            | {name, category, ...}    |
```

**Access Patterns Enabled**
- Get user profile: `PK = USER#alice, SK = PROFILE`
- List user's orders: `PK = USER#alice, SK begins_with ORDER#`
- Get order items: `PK = ORDER#2024-001, SK begins_with ITEM#`
- GSI1: Invert PK/SK for reverse lookups (e.g., orders by status)

**Trade-offs**
- Advantage: All access patterns satisfied with key lookups (no joins, no scans)
- Advantage: Consistent single-digit millisecond latency at any scale
- Disadvantage: Complex data modeling, difficult ad-hoc queries
- Disadvantage: Tight coupling between data model and access patterns
- Recommendation: Use single-table design for high-scale, well-known access patterns; use multiple tables for exploratory or analytics workloads

---

## 7. Decision Matrix

### Access Pattern to Normalization Level

| Access Pattern | Recommended Level | Denormalization Approach | Trade-off |
|---------------|------------------|------------------------|-----------|
| OLTP with complex joins | 3NF | Selective (covering indexes first) | Write consistency vs read speed |
| Read-heavy API backend | 3NF + cache tables | Denormalized read models | Staleness vs latency |
| Analytics / reporting | Star schema (partial denorm) | Materialized views, summary tables | Storage vs query speed |
| Document API (CRUD) | Embedded documents | N/A (document model) | Flexibility vs consistency |
| Event sourcing | Append-only events + projections | Projected read models | Complexity vs auditability |
| Time-series | Bucket pattern (denormalized) | Pre-aggregated rollups | Ingestion speed vs query flexibility |

### Schema Evolution Risk Assessment

| Change Type | Risk Level | Downtime Required | Mitigation |
|------------|-----------|-------------------|-----------|
| Add nullable column | Low | No | None needed |
| Add column with default | Low | No (PG 11+, MySQL 8.0+) | Test with large tables |
| Add index | Low-Medium | No (CONCURRENTLY) | Monitor replication lag |
| Change column type | Medium-High | Possibly | Use online DDL tools |
| Drop column | Medium | No | Deprecation period, verify no references |
| Split table | High | Yes (usually) | Dual-write migration pattern |
| Merge tables | High | Yes (usually) | Backward-compatible views |

---

## 8. Academic References

1. **Codd (1970)** — "A Relational Model of Data for Large Shared Data Banks" — CACM. Foundation of normalization theory
2. **Date (2003)** — "An Introduction to Database Systems" — 8th Edition. Comprehensive normalization coverage
3. **Kleppmann (2017)** — "Designing Data-Intensive Applications" — O'Reilly. Modern data modeling with denormalization trade-offs
4. **Rick Houlihan (2019)** — "Advanced Design Patterns for DynamoDB" — AWS re:Invent. Single-table design methodology
5. **Copeland & Khoshafian (1985)** — "A Decomposition Storage Model" — SIGMOD. Column-store foundations relevant to denormalization

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
