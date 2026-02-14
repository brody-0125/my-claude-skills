# Document Modeling Reference
<!-- Agent: d2-document-modeler -->
<!-- Purpose: Document database modeling — embedding vs referencing, MongoDB patterns, -->
<!-- DynamoDB single-table design, and practical query examples. -->
<!-- Source: Extracted from domain-d-normalization.md section 3 + case studies. -->

> Reference for the **d2-document-modeler** agent.
> Covers embedding-vs-referencing decisions, MongoDB patterns and guidelines,
> DynamoDB single-table design, and production query examples.

---

## 1. Embedding vs Referencing Decision Matrix

| Factor | Embed (subdocument) | Reference (separate collection) |
|--------|---------------------|--------------------------------|
| **Relationship** | 1:1, 1:few | 1:many, many:many |
| **Access pattern** | Always read together | Accessed independently |
| **Update frequency** | Rarely updated | Frequently updated |
| **Subdocument size** | < 1 KB, bounded | Large or growing |
| **Atomicity** | Need single-doc atomicity | Independent lifecycle |
| **Duplication** | Acceptable | Not acceptable |

**Embed when**: child has no meaning without parent, always co-read, bounded array.
**Reference when**: shared across parents, independent queries, unbounded growth.

---

## 2. Embedding Pattern (Subdocument)

```javascript
// Insert order with embedded items and address
db.orders.insertOne({
    _id: "order_123",
    customer_name: "Alice",
    items: [
        { product: "Widget", sku: "WDG-001", qty: 2, price: 9.99 },
        { product: "Gadget", sku: "GDG-042", qty: 1, price: 24.99 }
    ],
    shipping_address: { street: "123 Main St", city: "Springfield", zip: "62701" },
    created_at: new Date()
});

// Single-read retrieval
db.orders.findOne({ _id: "order_123" });

// Filter + index on embedded field
db.orders.find({ "items.sku": "WDG-001" });
db.orders.createIndex({ "items.sku": 1 });
```

**Advantages**: Single read, atomic updates, data locality.
**Risks**: Document growth, 16 MB BSON limit, nested-array update complexity.

---

## 3. Referencing Pattern (Normalized)

```javascript
// orders collection
db.orders.insertOne({
    _id: "order_123", customer_id: "cust_456",
    item_ids: ["item_1", "item_2"], status: "shipped"
});
// items collection
db.items.insertMany([
    { _id: "item_1", product: "Widget", qty: 2, price: 9.99 },
    { _id: "item_2", product: "Gadget", qty: 1, price: 24.99 }
]);
```

**Application-level join**:
```javascript
const order = db.orders.findOne({ _id: "order_123" });
const items = db.items.find({ _id: { $in: order.item_ids } }).toArray();
```

**Server-side $lookup**:
```javascript
db.orders.aggregate([
    { $match: { _id: "order_123" } },
    { $lookup: { from: "items", localField: "item_ids", foreignField: "_id", as: "items" } }
]);
```

**Advantages**: No duplication, independent updates. **Risks**: N+1 reads, no atomic cross-doc updates (pre-4.0).

---

## 4. Hybrid Pattern (Extended Reference)

```javascript
db.orders.insertOne({
    _id: "order_123",
    customer: { customer_id: "cust_456", name: "Alice", tier: "premium" },  // summary
    item_ids: ["item_1", "item_2"],   // full detail via reference
    total: 44.97
});

// Bulk-update stale embedded data
db.orders.updateMany(
    { "customer.customer_id": "cust_456" },
    { $set: { "customer.name": "Alice Johnson" } }
);
```

**Trade-off**: Embedded name may go stale. Acceptable when data changes rarely.

---

## 5. MongoDB-Specific Guidelines

### 16 MB Limit Strategies

| Strategy | Description | When |
|----------|-------------|------|
| Monitor size | `Object.bsonsize(db.coll.findOne({_id: id}))` | Always |
| Bucket pattern | Cap array at N elements, overflow doc | Time-series, logs |
| Subset pattern | Keep last N items, archive rest | Reviews, comments |
| GridFS | Chunk-based blob storage | Files > 16 MB |

```javascript
// Monitor document sizes
const doc = db.orders.findOne({ _id: "order_123" });
print("Size:", Object.bsonsize(doc), "bytes");
```

### Index Patterns

```javascript
db.orders.createIndex({ "items.product": 1 });              // embedded field
db.orders.createIndex({ customer_id: 1, created_at: -1 });  // compound
db.orders.createIndex({ status: 1 },                        // partial
    { partialFilterExpression: { status: { $ne: "archived" } } });
db.products.createIndex({ name: "text", description: "text" }); // full-text
```

---

## 6. MongoDB Atlas Official Patterns

| Pattern | Description | Use Case |
|---------|-------------|----------|
| **Attribute** | KV pairs as subdocument array | Polymorphic attributes |
| **Bucket** | Time-bounded document groups | IoT sensors, logs |
| **Computed** | Pre-computed derived values | Dashboards, leaderboards |
| **Extended Reference** | Embed subset of referenced doc | Avoid joins for hot fields |
| **Outlier** | Handle atypical docs differently | Celebrity followers |
| **Subset** | Embed recent/relevant subset | Recent reviews |

### Bucket Pattern Example

```javascript
db.sensor_data.insertOne({
    sensor_id: "temp_01",
    bucket_start: ISODate("2025-05-01T10:00:00Z"),
    bucket_end:   ISODate("2025-05-01T10:59:59Z"),
    count: 60,
    readings: [
        { ts: ISODate("2025-05-01T10:00:00Z"), value: 22.1 },
        { ts: ISODate("2025-05-01T10:01:00Z"), value: 22.3 }
        // … up to 60 per bucket
    ],
    avg: 22.4, min: 21.8, max: 23.1
});

db.sensor_data.find({
    sensor_id: "temp_01",
    bucket_start: { $gte: ISODate("2025-05-01T00:00:00Z") },
    bucket_end:   { $lte: ISODate("2025-05-01T23:59:59Z") }
}).sort({ bucket_start: 1 });
```

### Subset Pattern Example

```javascript
db.products.insertOne({
    _id: "prod_widget", name: "Widget", price: 9.99,
    recent_reviews: [
        { user: "Bob", rating: 5, text: "Great!", date: ISODate("2025-05-10") },
        { user: "Carol", rating: 4, text: "Good", date: ISODate("2025-05-09") }
    ],
    review_count: 247
});
// Full history: db.reviews.find({ product_id: "prod_widget" }).sort({ date: -1 });
```

---

## 7. DynamoDB: Single-Table Design

**Philosophy**: All entities in one table. PK + SK composite key. GSI overloading
(`GSI1PK`, `GSI1SK`) supports multiple entity types per index.

```
| PK              | SK                  | GSI1PK          | GSI1SK         | Data             |
|-----------------|---------------------|-----------------|----------------|------------------|
| USER#alice      | PROFILE             | EMAIL#a@b.com   | USER#alice     | {name, email, …} |
| USER#alice      | ORDER#2024-001      | STATUS#shipped  | ORDER#2024-001 | {total, …}       |
| ORDER#2024-001  | ITEM#widget         |                 |                | {qty, price, …}  |
| PRODUCT#widget  | METADATA            | CAT#electronics | PRODUCT#widget | {name, cat, …}   |
```

### Access Patterns

```
Get user profile         PK = "USER#alice", SK = "PROFILE"
List user's orders       PK = "USER#alice", SK begins_with "ORDER#"
Get order items          PK = "ORDER#2024-001", SK begins_with "ITEM#"
Orders by status         GSI1PK = "STATUS#shipped"
User by email            GSI1PK = "EMAIL#a@b.com"
Products by category     GSI1PK = "CAT#electronics"
```

### Single-Table vs Multi-Table Decision

| Factor | Single-Table | Multi-Table |
|--------|-------------|-------------|
| Access patterns | Well-known, stable | Evolving, exploratory |
| Scale | High (millions+ items) | Moderate |
| Ad-hoc queries | Difficult | Easy |
| Team expertise | DynamoDB expertise required | Lower learning curve |

---

## 8. Document Modeling Decision Matrix

| Scenario | Approach | Key Consideration |
|----------|----------|-------------------|
| User + addresses (max 5) | Embed | Bounded, always co-read |
| Blog post + comments | Subset + Reference | Unbounded; embed recent |
| Product + variants | Embed | Bounded, queried together |
| Order + line items | Embed | Atomic updates, co-read |
| User + followers | Reference + Outlier | Unbounded, independent |
| IoT readings | Bucket | High volume, time-series |
| Polymorphic catalog | Attribute pattern | Varying schema per category |
| Chat messages | Bucket or Reference | High volume, pagination |

---

## 9. References

1. **Kleppmann (2017)** — "Designing Data-Intensive Applications"
2. **Rick Houlihan (2019)** — "Advanced Design Patterns for DynamoDB"
3. **MongoDB Documentation** — Data Modeling Patterns & Anti-Patterns

---

*Extracted from domain-d-normalization.md for d2-document-modeler. Last updated: 2025-05.*
