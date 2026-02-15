# Distributed Database: DynamoDB Throughput Optimization Reference
<!-- Agent: f4-dynamodb-throughput-optimizer -->
<!-- Scope: Partition key distribution, capacity modes, throttling/back pressure, high-TPS operations -->

> Static reference for the **f4-dynamodb-throughput-optimizer** agent.
> Covers practical design guidance for DynamoDB high-throughput workloads,
> including hot partition mitigation, GSI back pressure, adaptive capacity limits,
> and operation-level safeguards.

---

## 1. Throughput Scaling Fundamentals

### Partition distribution is the first bottleneck check

In DynamoDB high-TPS workloads, table-level capacity can look sufficient while
specific partitions are saturated. Always evaluate:

- partition key cardinality
- skew (top-key concentration)
- burst concentration windows
- GSI write concentration

**Practical signal**
- throttling appears on specific request groups/keys
- p99 latency spikes during bursts
- table aggregate utilization does not fully explain failures

### Read/write path considerations

- Write-heavy paths are more sensitive to key skew and GSI propagation.
- Strongly consistent reads increase read cost and can reduce throughput headroom.
- Retry storms can amplify load if idempotency controls are weak.

---

## 2. Capacity Mode Strategy

### On-demand vs Provisioned + Auto Scaling

| Mode | Strength | Trade-off | Recommended when |
|------|----------|-----------|------------------|
| On-demand | Operational simplicity, good for uncertain bursts | Cost predictability can be lower at sustained high usage | Traffic volatility is high or baseline is unknown |
| Provisioned + Auto Scaling | Better baseline control and cost governance | Requires baseline/headroom tuning and scaling policy care | Sustained high TPS with predictable baseline |

### Headroom policy

For p99-sensitive systems, reserve explicit headroom instead of targeting near-maximum steady utilization.

- define baseline for normal sustained traffic
- define burst window policy
- align auto scaling reaction expectations with burst profile

---

## 3. Adaptive Capacity, Burst Behavior, and Throttling

### Adaptive capacity interpretation

Adaptive capacity can reduce imbalance effects, but it does not replace good key design.
If the workload is dominated by a narrow hot key range, throttling may persist despite
adequate aggregate table capacity.

### GSI back pressure and propagation

A common high-TPS issue is GSI write throttling that propagates back to base table writes.
This creates end-to-end throughput collapse symptoms even when base table settings appear reasonable.

**Reference**: AWS DynamoDB Developer Guide — GSI write throttling and back pressure.

### Root-cause split checklist

1. **Key design issue**: hot partition / hot key concentration
2. **Capacity policy issue**: insufficient baseline or slow scaling reaction
3. **Index design issue**: skewed GSI write pattern and back pressure

---

## 4. Data Modeling and Workload Isolation Patterns

### Write-sharded keys for heavy tenants/hot entities

- Pattern: `logical_key#bucket`
- Goal: distribute write load while keeping deterministic query assembly strategy

### Table separation for pathological hotspots

When a workload segment remains hot even after key redesign, isolate it into a dedicated table/path.

- separates failure domain and capacity policy
- reduces collateral throttling on unrelated entities

### Operational fallback

- introduce back-pressure handling in application layer
- degrade non-critical write paths first
- protect critical path latency SLO explicitly

---

## 5. Idempotency, Conditional Writes, and Transactions

### Idempotency under retry-heavy load

High TPS plus retries requires strict duplicate-side-effect prevention.
Use request-level idempotency keys and conditional writes.

### Conditional expressions

Use conditional write guards to prevent duplicate inserts/updates during transient retries.

### Transaction scope

Transactions improve correctness but can reduce throughput ceilings on hot paths.
Keep transaction scope minimal and avoid broad multi-item transactional coupling in the highest-throughput path.

---

## 6. Real-world Notes (Documented Cases)

### Channel Corporation engineering notes

From the Channel Corporation engineering write-up and AWS architecture modernization post:

- identified GSI hot partition / write back-pressure patterns
- discussed back-pressure-aware mitigation in the application path
- documented model separation decisions (including table split decisions) to isolate hot traffic domains

These case notes reinforce that high-TPS DynamoDB optimization is primarily
**distribution + isolation + operational control**, not capacity tuning alone.

### AWS large-scale public metrics

AWS public Prime Day metrics reported DynamoDB peak request rates at very large scale
(e.g., 126M+ / 146M+ / 151M+ requests per second in recent annual reports), illustrating
that platform-level scale is achievable when workload distribution and operations are designed correctly.

Use these figures as capability evidence, not direct sizing templates.

---

## 7. Decision Matrix

| Symptom | Likely primary cause | First action |
|---------|----------------------|--------------|
| Throttling with moderate aggregate utilization | Hot partition/key skew | Redesign partition key distribution |
| Base writes throttled when GSI active | GSI write back pressure | Rework index/key pattern and isolate hot index path |
| p99 spikes during short bursts | Baseline/headroom mismatch | Raise baseline or tune scaling policy for burst window |
| Retry storm increases failure rate | Weak idempotency controls | Add idempotency key + conditional write guards |
| Persistent localized hotspot | Workload concentration beyond key redesign | Split hot path/table and isolate capacity policy |

---

## 8. References

1. [AWS DynamoDB Developer Guide — GSI write throttling and back pressure](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/gsi-throttling.html)
2. [AWS DynamoDB Developer Guide — On-demand capacity mode](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/on-demand-capacity-mode.html)
3. [AWS DynamoDB Developer Guide — Maximum throughput for on-demand tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/on-demand-capacity-mode-max-throughput.html)
4. [AWS Tech Blog (KO) — Architecture modernization journey of Channel Corporation with Amazon DynamoDB, Part 1](https://aws.amazon.com/ko/blogs/tech/architecture-modernization-journey-of-channel-corporation-with-amazon-dynamodb-part1/)
5. [Channel Corporation Engineering — 메시지 트래픽 100배에도 끄떡 없게 고객 테이블 뜯어고치기 (1)](https://channel.io/ko/team/blog/articles/tech-user-table-refactoring-6ace7347)
6. [AWS News Blog — Prime Day 2025 scale metrics](https://aws.amazon.com/blogs/aws/aws-services-scale-to-new-heights-for-prime-day-2025-key-metrics-and-milestones/)
7. [AWS News Blog — Prime Day 2024 scale metrics](https://aws.amazon.com/blogs/aws/how-aws-powered-prime-day-2024-for-record-breaking-sales/)
8. [AWS News Blog — Prime Day 2023 scale metrics](https://aws.amazon.com/blogs/aws/prime-day-2023-powered-by-aws-all-the-numbers/)

---

*Last updated: 2026-02. Include only source-backed claims; avoid unsourced numerical tuning rules in recommendations.*
