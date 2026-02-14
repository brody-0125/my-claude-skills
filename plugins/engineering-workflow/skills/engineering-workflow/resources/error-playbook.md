# Error Playbook — Engineering Workflow

> Error handling procedures and fallback strategies for the engineering-workflow plugin.
> Loaded on-demand when errors occur during any phase.

## Error Code Registry

All errors use the prefix `EW-` followed by a category code and sequence number.

| Code | Category | Description | Severity |
|------|----------|-------------|----------|
| EW-CLF-001 | Classification | No keyword match — query does not match any system | WARNING |
| EW-CLF-002 | Classification | Ambiguous classification — confidence < 0.60 | WARNING |
| EW-CLF-003 | Classification | Multiple systems matched — requires cross-system routing | INFO |
| EW-ORC-001 | Orchestration | Agent timeout — agent Task did not return within 60s | ERROR |
| EW-ORC-002 | Orchestration | Agent returned invalid JSON — output failed schema validation | ERROR |
| EW-ORC-003 | Orchestration | Reference file not found — agent reference .md missing | WARNING |
| EW-ORC-004 | Orchestration | Orchestrator returned stub status — system not fully implemented | INFO |
| EW-CST-001 | Constraint | Direct conflict — same target, different values | WARNING |
| EW-CST-002 | Constraint | Semantic conflict — related targets with incompatible values | WARNING |
| EW-CST-003 | Constraint | Unresolvable conflict — hard vs hard, requires user decision | ERROR |
| EW-SYN-001 | Synthesis | Input schema mismatch — orchestrator output missing required fields | ERROR |
| EW-SYN-002 | Synthesis | Dependency cycle detected — circular cross-system dependency | WARNING |
| EW-SYN-003 | Synthesis | All orchestrators returned stubs — low confidence synthesis | WARNING |
| EW-CTX-001 | Context | Token budget exceeded — context at 80%+ capacity | WARNING |
| EW-CTX-002 | Context | Critical context pressure — context at 90%+ capacity | ERROR |
| EW-SES-001 | Session | Session history file corrupted or unparseable | WARNING |
| EW-SES-002 | Session | Pattern cache eviction triggered | INFO |
| EW-AUD-001 | Audit | Moderate confidence (0.50-0.69) — warning added to output | WARNING |
| EW-AUD-002 | Audit | Low confidence (0.30-0.49) — simplified re-dispatch triggered | WARNING |
| EW-AUD-003 | Audit | Very low confidence (< 0.30) — agent rejected, orchestrator fallback | ERROR |
| EW-AUD-004 | Audit | Dynamic expansion suppressed — token budget > 80% | WARNING |
| EW-AUD-005 | Audit | Feasibility issue — recommendation conflicts with environment constraints | WARNING |
| EW-AUD-006 | Audit | Contract violation — orchestrator output missing required field or priority inconsistency | WARNING |
| EW-AUD-007 | Audit | Coverage gap — system not reflected in unified_recommendation | WARNING |
| EW-AUD-008 | Audit | Ordering violation — depends_on references non-existent phase | ERROR |
| EW-AUD-009 | Audit | Risk-rollback gap — high-risk phase missing rollback strategy | WARNING |
| EW-AUD-010 | Audit | Missing constraints — multi-domain analysis with 0 constraints declared | WARNING |

## Unified Retry Policy

### Default: No Automatic Retry

Failed agents are NOT automatically retried. The orchestrator provides fallback analysis instead.

### Exceptions (Automatic Retry Allowed)

| Condition | Retry Count | Modified Input | Rationale |
|-----------|-------------|----------------|-----------|
| Network/Task timeout (EW-ORC-001) | 1 | Simplified: remove reference_excerpt, keep query + constraints only | Transient failure; reduced input lowers timeout risk |
| Invalid JSON output (EW-ORC-002) | 1 | Add explicit instruction: "Return ONLY valid JSON, no markdown" | Common LLM formatting error; explicit instruction usually fixes |
| Stub orchestrator (EW-ORC-004) | 0 | — | Stub cannot produce better results on retry |
| Reference missing (EW-ORC-003) | 0 | Proceed without reference | Reference absence is permanent; retry won't help |

### Retry Behavior

```
ON agent_failure(error):
  IF error.code IN [EW-ORC-001, EW-ORC-002] AND retry_count == 0:
    retry_count += 1
    modified_input = simplify_input(original_input)
    result = dispatch_agent(agent, modified_input)
    IF result.success:
      RETURN result

  # Fallback: orchestrator provides general guidance
  RETURN orchestrator_fallback(agent.domain, original_query)
```

## Quick Index

| Error Type | Section | Trigger |
|------------|---------|---------|
| Agent timeout/failure | [1. Agent Failure](#1-agent-timeout--failure) | Task does not return or returns error |
| Constraint conflict | [2. Constraint Conflict](#2-constraint-conflict-escalation) | resolve-constraints.sh detects conflict |
| Missing reference data | [3. Missing Reference](#3-missing-reference-data) | Read fails or file not found |
| Unknown domain | [4. Unknown Domain](#4-unknown-domain) | Classification confidence < 0.50 |
| Token budget exceeded | [5. Token Budget](#5-token-budget-exceeded) | Cumulative tokens exceed budget |
| Cross-system failure | [6. Cross-System Failure](#6-cross-system-failure) | One or more orchestrators fail |
| Classification ambiguity | [7. Classification Ambiguity](#7-classification-ambiguity) | LLM classification low confidence |
| Audit sub-phase errors | [8. Audit Sub-Phase Errors](#8-audit-sub-phase-errors-ew-aud) | Quality gate failures in Phase 2.5/3.5/4.5 |

---

## 1. Agent Timeout / Failure

**Symptoms**: Agent Task does not return within expected time, or returns an error/malformed output.

**Detection**:
```
IF Task(agent) returns error OR output is not valid JSON:
  → agent.status = "failed"
IF Task(agent) does not return within 60 seconds:
  → agent.status = "timeout"
```

**Resolution protocol**:

| Scenario | Action |
|----------|--------|
| Single agent in single-domain query | Orchestrator provides fallback analysis using its own domain knowledge |
| One agent fails in multi-domain query | Continue with remaining agents; note gap in merged output |
| Dependent agent fails (sequential chain) | Skip all downstream agents; orchestrator provides partial analysis |
| All agents fail | Orchestrator returns high-level guidance based on query keywords only |

**Fallback analysis template**:
```markdown
> Note: The {domain} agent was unavailable. The following analysis is provided
> by the {system} orchestrator at a higher level of abstraction.
> For detailed analysis, retry the query or specify `--domain {system}` explicitly.

{orchestrator's general knowledge-based response}
```

**Retry policy**:
- Do NOT automatically retry failed agents (to avoid wasting tokens)
- Log the failure for session history
- If user re-issues the same query, agents are dispatched fresh

---

## 2. Constraint Conflict Escalation

**Symptoms**: `resolve-constraints.sh` reports one or more conflicts between agent constraints.

**Detection**:
```
IF resolve-constraints.sh output contains conflicts[] with length > 0:
  → constraint conflict detected
```

**Resolution protocol**:

| Conflict Type | Resolution |
|---------------|------------|
| Intra-system, hard vs soft | Accept hard constraint, relax soft constraint |
| Intra-system, hard vs hard | Orchestrator evaluates evidence strength; if unable to resolve, escalate to synthesizer |
| Cross-system, SE vs any | Security hard constraints always win |
| Cross-system, soft vs soft | Present both options with trade-offs to user |
| Cross-system, hard vs hard | Document conflict explicitly; ask user for priority input |

**Escalation chain**:
```
Agent conflict → Orchestrator resolves
  ↓ (if unresolvable)
Orchestrator conflict → Synthesizer resolves
  ↓ (if unresolvable)
Synthesizer conflict → Present to user with options
```

**Output when conflict is unresolvable**:
```markdown
### Unresolved Constraint Conflict

The following constraints are in direct conflict and require your input:

**Option A** (from {agent_a}):
{constraint_a description}
Evidence: {constraint_a evidence}

**Option B** (from {agent_b}):
{constraint_b description}
Evidence: {constraint_b evidence}

Please indicate your priority: performance, consistency, security, or cost.
```

---

## 3. Missing Reference Data

**Symptoms**: Agent attempts to Read a reference file that does not exist, or a required
section within a reference is not found.

**Detection**:
```
IF Read(file_path) returns "file not found" error:
  → missing reference
IF Grep(pattern, file_path) returns no matches:
  → section not found within reference
```

**Resolution protocol**:

| Scenario | Action |
|----------|--------|
| Agent definition .md missing | CRITICAL: Log error, skip agent, orchestrator provides fallback |
| Reference document missing | WARN: Agent proceeds without reference; note in output that analysis may lack depth |
| Section not found in reference | INFO: Agent proceeds with available content; do not block execution |
| Orchestrator .md missing | CRITICAL: Gateway Router provides system-level fallback guidance |

**Graceful degradation template**:
```markdown
> Note: Reference material for {topic} was not available.
> This analysis is based on the agent's built-in knowledge without project-specific context.
> Consider adding {missing_reference} to improve future analysis accuracy.
```

**Prevention**:
- On plugin installation, validate that all agent definition files exist
- Log missing references to `~/.claude/cache/engineering-workflow/missing-refs.log`
- After 3 occurrences of the same missing reference, suggest to user: "Consider creating {file}"

---

## 4. Unknown Domain

**Symptoms**: Query does not match any keywords in the routing table, and LLM classification
also fails to identify a domain.

**Detection**:
```
IF classify-query.sh returns empty systems[] AND
   LLM classification confidence < 0.50:
  → unknown domain
```

**Resolution protocol**:

```
1. Do NOT attempt to force-classify into a domain
2. Return routing suggestions based on partial keyword matches
3. Ask user for clarification
```

**Response template**:
```markdown
I was unable to classify your query into a specific engineering domain.

**Your query**: "{original_query}"

**Possible domains based on partial matches**:
- DB (Database): if your question relates to data storage, queries, or schema
- BE (Backend): if your question relates to application architecture or APIs
- IF (Infrastructure): if your question relates to deployment or networking
- SE (Security): if your question relates to authentication or authorization

**To help me route your query, try**:
- Adding domain keywords (e.g., "database", "API", "kubernetes", "security")
- Using explicit flag: `--domain db` or `--domain be`
- Rephrasing with more technical specificity
```

---

## 5. Token Budget Exceeded

**Symptoms**: Cumulative token usage exceeds the allocated budget for the current execution pattern.

**Detection**:
```
IF cumulative_tokens >= budget * 0.80: → WARNING (start truncation)
IF cumulative_tokens >= budget * 1.00: → LIMIT (stop additional loading)
IF cumulative_tokens >= budget * 1.20: → CRITICAL (force-complete current phase)
```

**Resolution protocol**:

| Level | Action |
|-------|--------|
| WARNING (80%) | Truncate reference excerpts for remaining agents to essential sections only |
| LIMIT (100%) | Skip remaining low-priority agents; proceed with available results |
| CRITICAL (120%) | Force-complete current phase; skip remaining phases except output formatting |

**Truncation priority** (truncate lowest priority first):
1. Secondary reference excerpts
2. Example sections within definitions
3. Trade-off analysis (limit to top 2 options)
4. Extended analysis paragraphs
5. NEVER truncate: core constraints, user query, classification, recommendations

**Output annotation**:
```markdown
> Note: Token budget was exceeded during analysis. The following sections
> may have reduced depth: {list of truncated sections}.
> For a deeper analysis, retry with `--depth deep` on a specific sub-domain.
```

---

## 6. Cross-System Failure

**Symptoms**: In a cross-system (Pattern 3) query, one or more orchestrators fail entirely.

**Detection**:
```
IF any orchestrator Task returns error or timeout in a cross-system query:
  → cross-system partial failure
```

**Resolution protocol**:

| Failed Orchestrators | Action |
|---------------------|--------|
| 1 of 2 | Return results from successful orchestrator with warning |
| 1 of 3 | Return results from 2 successful orchestrators; synthesizer works with partial input |
| 2 of 3 | Return results from 1 successful orchestrator; skip synthesis |
| All | Gateway Router provides high-level guidance without domain-specific analysis |

**Partial results template**:
```markdown
### Partial Analysis Warning

This is a partial analysis. The {failed_system} system analysis was not available
due to {failure_reason}. The following analysis covers {available_systems} only.

Cross-system constraints involving {failed_system} could not be evaluated.
Consider re-running with `--domain {failed_system}` separately for that component.
```

**Synthesizer behavior with partial input**:
- Synthesizer receives available orchestrator outputs + note about missing system
- Synthesizer does NOT fabricate analysis for the missing system
- Synthesizer notes any constraint gaps in its output
- Cross-system trade-offs involving the missing system are marked as "unverified"

---

## 7. Classification Ambiguity

**Symptoms**: Neither keyword matching nor LLM classification produces a confident result.

**Detection**:
```
IF classify-query.sh confidence < 0.50 AND
   LLM classification confidence < 0.50:
  → high ambiguity

IF classify-query.sh confidence 0.50-0.69 AND
   no explicit --domain flag:
  → moderate ambiguity
```

**Resolution protocol**:

| Ambiguity Level | Action |
|-----------------|--------|
| Moderate (0.50-0.69) | Proceed with best-guess classification; add caveat to output |
| High (< 0.50) | Ask user for clarification before proceeding |

**Clarification prompt**:
```markdown
Your query could relate to multiple engineering domains. To provide the most
relevant analysis, could you clarify which aspect you're most interested in?

1. **Database** — storage, indexing, query optimization, replication
2. **Backend** — API design, service architecture, application concurrency
3. **Infrastructure** — deployment, scaling, monitoring, networking
4. **Security** — authentication, authorization, encryption, compliance

Or you can specify directly: `--domain db` / `--domain be` / `--domain if` / `--domain se`
```

---

## General Principles

### Never Halt Silently

Every error must produce visible output. Even total failure should return:
1. What was attempted
2. Why it failed
3. What the user can do differently

### Log All Errors

Append error records to session history for pattern detection:
```json
{
  "timestamp": "2026-02-12T10:31:00Z",
  "error_type": "agent_timeout",
  "agent": "db/storage-engine-agent",
  "query_signature": "b-tree lsm storage",
  "resolution": "orchestrator_fallback"
}
```

### Repeated Error Escalation

If the same error type occurs 3+ times across sessions:
1. Log pattern in `~/.claude/cache/engineering-workflow/error-patterns.jsonl`
2. On next occurrence, proactively warn: "This agent has failed frequently. Consider checking agent definition integrity."
3. Suggest user run diagnostic: `scripts/validate-agent-output.sh <agent-type>`

---

## 8. Audit Sub-Phase Errors (EW-AUD-*)

**Symptoms**: Quality gate failures during Phase 2.5, 3.5, or 4.5.

**Detection**: `scripts/audit-analysis.sh` returns findings with WARN or FAIL status.

### EW-AUD-001 ~ 003: Confidence Gating

| Code | Confidence | Action |
|------|------------|--------|
| EW-AUD-001 | 0.50-0.69 | Add "Moderate confidence" caveat to agent output section. No re-dispatch. |
| EW-AUD-002 | 0.30-0.49 | Re-dispatch agent with simplified prompt (query + constraints only). If retry also < 0.50, replace with orchestrator fallback. |
| EW-AUD-003 | < 0.30 | Immediately reject agent result. Orchestrator provides fallback analysis. No retry. |

### EW-AUD-004: Dynamic Expansion Suppressed

```
Trigger: THOROUGH audit-reviewer identifies expansion_needed but token budget > 80%
Action:
  1. Log suppression: "Dynamic expansion suppressed for domain {X} — budget at {pct}%"
  2. Add note to output: "Additional analysis for {domain} recommended but deferred due to context pressure"
  3. Do NOT dispatch additional agents
```

### EW-AUD-005: Feasibility Issue

```
Trigger: Recommendation references infrastructure/scale not present in constraints_used
Action:
  1. Flag the specific recommendation with feasibility warning
  2. Request orchestrator to provide alternative within known constraints
  3. If no alternative available: keep recommendation with explicit caveat
```

### EW-AUD-006: Contract Violation / Priority Inconsistency

```
Trigger: audit-analysis.sh orchestrator finds missing fields or priority rule violation
Action:
  For missing fields:
    - CRITICAL fields (system, status): reject orchestrator result
    - Required fields: apply defaults (see analysis-audit-protocol.md)
  For priority inconsistency:
    - Log the specific violation
    - Add warning to output noting potential priority misalignment
```

### EW-AUD-007: Coverage Gap

```
Trigger: audit-analysis.sh synthesis finds a system in systems_analyzed
         not referenced in unified_recommendation
Action:
  1. Warning in output: "System {X} was analyzed but not reflected in the unified recommendation"
  2. Synthesizer should re-examine the omitted system's results
  3. If intentional omission: document reason in synthesis notes
```

### EW-AUD-008: Ordering Violation

```
Trigger: depends_on references a phase that doesn't exist in implementation_order
Action:
  1. ERROR — this indicates a structural bug in the synthesis output
  2. Remove the invalid dependency reference
  3. Re-validate topological sort without the invalid edge
  4. Add warning: "Implementation ordering corrected — invalid dependency removed"
```

### EW-AUD-009: Risk-Rollback Gap

```
Trigger: implementation_order contains a phase with risk: "high"
         but no rollback strategy defined
Action:
  1. Warning in output: "Phase {N} is high-risk but has no rollback strategy"
  2. Suggest generic rollback: "Consider: snapshot before change, staged rollout, feature flag"
  3. Do NOT block output delivery
```

### EW-AUD-010: Missing Constraints in Multi-Domain

```
Trigger: Multi-domain analysis (2+ domains) but agent declared 0 constraints
Action:
  1. Warning in completeness audit: "Agent {id} analyzed {domain} but declared no constraints"
  2. Flag as potential completeness gap — agent may have missed inter-domain interactions
  3. Do NOT block output delivery
```

### Audit Error Retry Policy

Audit errors do NOT trigger retries of the entire pipeline. They are additive quality warnings:

| Error | Blocks Output | Triggers Retry |
|-------|--------------|----------------|
| EW-AUD-001 | No | No |
| EW-AUD-002 | No | Single agent re-dispatch only |
| EW-AUD-003 | Partial (agent excluded) | Orchestrator fallback |
| EW-AUD-004 | No | No |
| EW-AUD-005 | No | No |
| EW-AUD-006 | Only if CRITICAL field missing | No |
| EW-AUD-007 | No | No |
| EW-AUD-008 | No (auto-corrected) | No |
| EW-AUD-009 | No | No |
| EW-AUD-010 | No | No |
