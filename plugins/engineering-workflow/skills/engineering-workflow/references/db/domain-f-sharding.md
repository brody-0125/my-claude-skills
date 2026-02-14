# Distributed Database: Sharding & Partitioning Reference
<!-- Agent: f3-sharding-architect -->
<!-- Scope: Sharding strategies, partition key design, rebalancing, case studies -->
<!-- Split from: domain-f-distributed.md -->

> Static reference for the **f3-sharding-architect** agent.
> Covers sharding strategies, partition key design, rebalancing approaches,
> and real-world case studies (Uber, Vitess, CockroachDB).

---

## 1. Sharding Strategies

### Hash-Based Sharding
```
shard_id = hash(partition_key) % num_shards
```
- **Advantage**: Even distribution with good hash function, simple routing
- **Disadvantage**: Range queries scatter to all shards, resharding expensive
- **Hotspot risk**: Low if partition key has good cardinality

```python
import hashlib
NUM_SHARDS = 64

def get_shard(partition_key: str) -> int:
    h = hashlib.md5(partition_key.encode()).hexdigest()
    return int(h, 16) % NUM_SHARDS

# get_shard("user-1001") -> 23, get_shard("user-1002") -> 47
```

```sql
-- Application-level shard routing (PostgreSQL schemas per shard)
CREATE TABLE shard_0.orders (
    order_id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL,
    total DECIMAL(10,2), created_at TIMESTAMPTZ DEFAULT NOW()
);
-- Cross-shard aggregate: scatter to all shards, sum client-side
```

### Range-Based Sharding
```
Shard 1: keys [A-F]    Shard 2: keys [G-M]
Shard 3: keys [N-S]    Shard 4: keys [T-Z]
```
- **Advantage**: Efficient range queries within single shard
- **Disadvantage**: Hotspots on sequential keys (auto-increment, timestamps)
- **Used by**: CockroachDB, HBase, Spanner

```sql
-- PostgreSQL declarative range partitioning
CREATE TABLE events (
    event_id BIGSERIAL, user_id BIGINT NOT NULL,
    event_type TEXT, payload JSONB, created_at TIMESTAMPTZ NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2025_01 PARTITION OF events
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE events_2025_02 PARTITION OF events
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- Range query hits only events_2025_02 (partition pruning)
SELECT * FROM events
WHERE created_at >= '2025-02-01' AND created_at < '2025-03-01';
```

### Directory-Based Sharding
- Lookup service maps each key to its shard; flexible but SPOF risk
- Mitigation: cache aggressively, replicate lookup service

```python
class ShardDirectory:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.cache = {}

    def get_shard(self, entity_id: str) -> str:
        if entity_id in self.cache:
            return self.cache[entity_id]
        shard = self.redis.hget("shard_dir", entity_id)
        if shard:
            self.cache[entity_id] = shard.decode()
            return self.cache[entity_id]
        shard = self._assign_shard(entity_id)
        self.redis.hset("shard_dir", entity_id, shard)
        self.cache[entity_id] = shard
        return shard

    def move_entity(self, entity_id: str, target: str):
        self.redis.hset("shard_dir", entity_id, target)
        self.cache.pop(entity_id, None)
```

### Partition Key Design

**Cardinality**: Bad: `country` (200 values, skewed). Good: `user_id` (millions). Better: `user_id + type`.

**Hotspot Avoidance**: Celebrity/viral content concentrates writes. Strategies: key salting, write sharding, dedicated hot-key capacity.

```sql
-- Hotspot avoidance via key salting
INSERT INTO user_activity (user_id, salt, activity_time, data)
VALUES ('celebrity_123', floor(random() * 10)::int, NOW(), '...');

-- Read: scatter across all 10 salts
SELECT * FROM user_activity
WHERE user_id = 'celebrity_123' AND salt IN (0,1,2,3,4,5,6,7,8,9)
  AND activity_time > NOW() - INTERVAL '1 hour';
```

**Scatter-Gather**: Queries without partition key touch all shards. Mitigate with denormalization or secondary indexes.

---

## 2. Rebalancing Strategies

### Fixed Number of Partitions
- Pre-allocate (e.g., 1000 on 10 nodes); move partitions on scale-out
- Used by: Elasticsearch, Riak, CouchDB

```json
{
  "settings": {
    "number_of_shards": 30,
    "number_of_replicas": 1
  }
}
```

### Dynamic Splitting
- Split at size threshold; merge below threshold. Adapts to data volume.
- Used by: HBase (region split), CockroachDB (512MB default)

### Consistent Hashing
```
     Node A          Node B
       │                │
   ────●────────────────●────────────
   0          Node C             2^32
               │
   ────────────●─────────────────────
```
- ~1/N keys move on scale-out; virtual nodes for even distribution
- Used by: DynamoDB, Cassandra

---

## 3. Case Studies

### Uber: Schemaless Sharding with Mezzanine

```
  ┌────────────────┐
  │  Application   │
  └───────┬────────┘
  ┌───────▼────────┐
  │   Mezzanine    │  <- Shard routing via ZooKeeper shard map
  └───┬───┬───┬────┘
  ┌───▼┐ ┌▼──┐ ┌▼───┐
  │ S1 │ │S2 │ │ S3 │  <- MySQL (N virtual shards each)
  └────┘ └───┘ └────┘
```

- 4096 virtual shards, consistent hashing with virtual nodes
- Rebalancing: MySQL replication to target, replay binlog, cut over
- Goal: <10% load variance across hosts
- Scale: millions of trips/day, dozens of clusters, cross-shard via Kafka

### Vitess: MySQL Horizontal Scaling

```
┌──────────┐     ┌─────────┐     ┌──────────────┐
│  App     │ --> │ vtgate  │ --> │ vttablet (s1)│ -> MySQL
│ (MySQL)  │     │ (proxy) │     │ vttablet (s2)│ -> MySQL
└──────────┘     └─────────┘     └──────────────┘
                                  ┌─────────────┐
                                  │  Topology   │ (etcd)
                                  └─────────────┘
```

```json
{
  "sharded": true,
  "vindexes": { "hash_vdx": { "type": "hash" } },
  "tables": {
    "users": { "column_vindexes": [{"column": "user_id", "name": "hash_vdx"}] },
    "orders": { "column_vindexes": [{"column": "user_id", "name": "hash_vdx"}] }
  }
}
```

```sql
-- vtgate routes transparent to app
SELECT * FROM users WHERE user_id = 12345;  -- single-shard
SELECT COUNT(*) FROM orders WHERE status = 'pending';  -- scatter-gather
```

**Resharding** (2-to-4 split): VReplication continuous copy -> catch up -> cut over (~1s write pause) -> clean up. Slack: millions QPS; <2s write unavailability per split; 100x connection reduction.

### CockroachDB: Automatic Range-Based Sharding

- 512MB ranges replicated via Raft (3-5 replicas); auto split/merge
- Balancer monitors range count, size, QPS; moves ranges to equalize load

```sql
-- Geo-partitioning for compliance and latency
ALTER TABLE users PARTITION BY LIST (region) (
    PARTITION us_east VALUES IN ('us-east-1', 'us-east-2'),
    PARTITION eu_west VALUES IN ('eu-west-1', 'eu-west-2')
);
ALTER PARTITION us_east OF INDEX users@primary CONFIGURE ZONE USING
    constraints = '[+region=us-east]';

-- Range splitting configuration
SET CLUSTER SETTING kv.range_max_bytes = 536870912;  -- 512MB
SET CLUSTER SETTING kv.range_min_bytes = 134217728;  -- 128MB merge

-- Pre-split hot tables
ALTER TABLE orders SPLIT AT VALUES ('2025-01-01'), ('2025-04-01'),
                                    ('2025-07-01'), ('2025-10-01');
ALTER TABLE orders SCATTER;
```

- Range split: seconds. Rebalancing: minutes. Single-region write: 2-10ms. Multi-region: ~2x RTT.

---

## 4. Decision Matrix

### Sharding Strategy Selection

| Factor | Hash | Range | Directory |
|--------|------|-------|-----------|
| Even distribution | Excellent | Depends on key | Flexible |
| Range query | Poor (scatter) | Excellent | Depends |
| Hotspot risk | Low | High (sequential) | Manageable |
| Resharding | High (rehash) | Medium (split) | Low (update dir) |
| Best for | KV lookups, OLTP | Time-series, logs | Complex routing |

### Scale Requirement to Architecture

| Scale | Architecture | Sharding | Example |
|-------|-------------|----------|---------|
| <1TB, single region | Leader + replicas | None | PostgreSQL |
| 1-10TB, single region | Leader + manual shard | Hash or range | App-level MySQL |
| >10TB, single region | Distributed SQL | Automatic | Vitess, CockroachDB |
| Multi-region, async OK | Leaderless | Consistent hash | Cassandra, DynamoDB |
| Multi-region, strong | Distributed SQL | Auto range | CockroachDB, Spanner |

### Sharding Middleware Comparison

| Feature | Vitess | ProxySQL | Citus | ShardingSphere |
|---------|--------|---------|-------|----------------|
| DB | MySQL | MySQL | PostgreSQL | MySQL/PG |
| Online resharding | Yes | No | Yes | Limited |
| Cross-shard joins | Yes | No | Yes | Yes |
| Maturity | High (2010) | Medium | Medium | Medium |
| Best for | Large MySQL | R/W split | PG scale-out | Java ecosystem |

### Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|-------------|---------|----------------|
| Cross-shard transactions | 2PC overhead, availability risk | Shard-local transactions |
| Sequential PK as shard key | All writes to one shard | Hash-based or composite key |
| Too few initial shards | Expensive resharding | Over-provision (1024+) |
| Sharding too early | Unnecessary complexity | Vertical first; shard at 1-5TB |
| Ignoring cross-shard queries | Scatter-gather kills p99 | Co-locate related data |
| No shard-aware ID generation | Needs directory lookup | Embed shard ID in entity ID |

### Partition Key Selection Checklist

```
1. [ ] Cardinality: enough distinct values? (>10x shard count)
2. [ ] Distribution: roughly even? (no 80/20 skew)
3. [ ] Query locality: most queries include partition key?
4. [ ] Write distribution: no celebrity/hotspot problem?
5. [ ] Join locality: related entities on same shard?
6. [ ] Growth pattern: stays even as data grows?
7. [ ] ID embedding: shard derivable from entity ID?
```

---

## 5. References

1. **DeCandia et al. (2007)** -- "Dynamo: Amazon's Highly Available Key-Value Store" -- SOSP'07
2. **Taft et al. (2020)** -- "CockroachDB: The Resilient Geo-Distributed SQL Database" -- SIGMOD'20
3. **Corbett et al. (2013)** -- "Spanner: Google's Globally-Distributed Database" -- ACM TOCS
4. **Curino et al. (2010)** -- "Schism: Workload-Driven Database Partitioning" -- VLDB'10

---

*Last updated: 2025-05. Sources include vendor documentation, engineering blogs, and peer-reviewed publications.*
