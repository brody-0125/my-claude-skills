# Priority Matrix

> Single source of truth for conflict resolution priorities across all engineering-workflow systems.
> Referenced by: synthesis-protocol.md, constraint-propagation.md, error-playbook.md

---

## Category Priority (Universal)

All constraint conflicts and recommendation trade-offs are resolved using this hierarchy.
Higher number = higher priority = wins in conflicts.

| Level | Category | Priority | Rationale | Examples |
|-------|----------|----------|-----------|----------|
| 5 | **Data Integrity** | Highest | Data loss is irreversible | Transaction isolation, FK constraints, backup strategy |
| 4 | **Security** | High | Vulnerabilities compound and escalate | Authentication, authorization, encryption, audit |
| 3 | **Availability** | Medium-High | Downtime has immediate business impact | Replication, failover, disaster recovery, health checks |
| 2 | **Performance** | Medium | Can be iteratively improved post-launch | Indexes, caching, query optimization, connection pools |
| 1 | **Convenience/DX** | Low | Important but secondary to correctness | Code structure, API design, naming, developer tooling |

## Multi-Category Scoring

When a recommendation touches multiple categories (e.g., "add replicas" affects both Availability and Performance):

```
For each recommendation R:
  1. Score R against each category (0.0-1.0):
     data_integrity_score, security_score, availability_score, performance_score, convenience_score
  2. Compute weighted_priority = sum(category_level * category_score)
     where category_level = 5, 4, 3, 2, 1 respectively
  3. Primary category = category with highest individual score
  4. Use weighted_priority for conflict resolution comparisons
```

## System Priority (Equal-Category Tiebreaker)

When two recommendations from different systems have the same weighted_priority (within 10%):

| Priority | System | Rationale |
|----------|--------|-----------|
| 1 (highest) | SE (Security) | Security vulnerabilities are hardest to fix retroactively |
| 2 | DB (Database) | Data layer is foundational; changes cascade upward |
| 3 | BE (Backend) | Application layer adapts more easily |
| 4 (lowest) | IF (Infrastructure) | Infrastructure is most flexible to reconfigure |

## Conflict Resolution Procedure

```
RESOLVE(conflict):
  1. Score both recommendations using multi-category scoring
  2. The recommendation with higher weighted_priority wins

  IF weighted_priority within 10% (effectively tied):
    3a. Compare primary categories — higher level wins
    3b. If same primary category: apply system priority tiebreaker
    3c. If same system: prefer completed > partial > stub orchestrator result

  4. Propose a mitigation plan for the losing side
  5. Record the resolution rationale including scores and rule applied
```

## User Overrides

The default matrix can be overridden using `priority_overrides` in constraints:

```json
{
  "priority_overrides": [
    "performance > availability",
    "convenience > performance"
  ]
}
```

Overrides apply only to the specified pairs; unspecified pairs follow the default matrix.

---

*This matrix is the single source of truth. All other documents (synthesis-protocol.md, constraint-propagation.md, error-playbook.md) reference this file instead of defining their own priority rules.*
