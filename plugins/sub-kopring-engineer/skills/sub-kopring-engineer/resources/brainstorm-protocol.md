# Brainstorm Protocol

> A protocol for converting ambiguous requests into concrete implementation requirements

## When It Activates

The Brainstorm phase is executed when any of the following conditions apply:

| Condition | Example |
|-----------|---------|
| Unclear scope | "Build a payment feature" (What payment? What scope?) |
| Ambiguous technology choice | "Send notifications" (Slack? Email? Push?) |
| Potential conflict with existing code | Similar functionality exists in the same domain |
| Multi-layer impact | Changes needed across all 4 layers |
| DB query library not detected | "Order lookup feature" (project has neither QueryDSL nor JOOQ) |

The following cases are **skipped**:

| Condition | Example |
|-----------|---------|
| Clear single task | "Add cancelledAt field to OrderJpaEntity" |
| Specific file designated | "Add validate logic to OrderCancelService" |
| Bug fix | "Fix NPE in OrderReader.getById" |

---

## 3-Level Ambiguity Assessment

### Level 1: LOW — Apply defaults and proceed

Minor ambiguity. Apply reasonable defaults and document the assumptions in the Plan.

```
User: "Add soft delete to Order"
→ Assumptions: Add deletedAt field, use isActive flag, auto-filter in Reader
→ Record in Plan under "Assumptions" section and proceed
```

### Level 2: MEDIUM — Present 2-3 options

Core design decisions needed. Present options and get user selection.

```
User: "Build an order status change feature"

Question: Confirming the scope of status changes.

Options:
A) Single state transition (e.g., PENDING → CONFIRMED)
   - Impact: application layer only
   - Effort: Small

B) State machine (define all state transition rules)
   - Impact: core + application + infrastructure
   - Effort: Medium

C) Event-driven state transition (including domain event publishing)
   - Impact: All layers
   - Effort: Large

Which approach do you prefer?
```

**DB query library selection (when DB query feature is requested in a project with query-lib=none):**

```
Question: Confirming which library to use for complex query operations.

Options:
A) QueryDSL — Code generation based on JPA Entities, natural integration with Spring Data JPA
   - Suitable for: JPA-centric projects, simple to moderate complexity queries
   - Dependency: kapt (Kotlin) or APT (Java)

B) JOOQ — SQL-first, code generation based on DB schema, close to pure SQL
   - Suitable for: Complex reporting/analytics queries, Window functions, CTEs
   - Dependency: nu.studer.jooq plugin

C) Spring Data JPA only — No additional dependencies
   - Suitable for: Simple CRUD, cases where @Query is sufficient
   - Limitations: Limited for dynamic queries and complex conditions

Which approach do you prefer?
```

### Level 3: HIGH — Halt implementation, request clarification

Critical information missing. Ambiguity at a level that prevents proceeding.

```
User: "Integrate with external system"

Clarification needed before proceeding:
1. What is the target system? (Is there API documentation?)
2. Communication method? (REST API / gRPC / Message Queue)
3. Authentication method? (API Key / OAuth / mTLS)
4. Retry policy on errors?
```

---

## Brainstorm Question Rules

1. **Ask only one question at a time** — Do not ask multiple questions at once
2. **Verify codebase facts directly** — Explore using Glob/Grep/Read instead of asking the user
3. **State trade-offs for each option** — Impact scope and effort for each option
4. **Limit options to 2-3** — Prevent decision fatigue

---

## Brainstorm Output

Once Brainstorm is complete, finalize the following and proceed to the Plan phase:

```markdown
## Brainstorm Results

### Confirmed Items
- Task scope: {specific scope}
- Technology choice: {selected approach}
- Affected layers: {layer list}

### Assumptions (Level 1 applied)
- {Assumption 1}: {rationale}
- {Assumption 2}: {rationale}

### Excluded Items
- {Items excluded from this scope}
```

---

## Phase Handoff

**Entry Condition**: Request ambiguity Level 2+ detected in Phase 0 (see SKILL.md line 61)

**Exit Condition**: All clarifications resolved OR Level 1 assumptions applied

**Next Phase**: → [plan-protocol.md](./plan-protocol.md) (Phase 2 Plan)
