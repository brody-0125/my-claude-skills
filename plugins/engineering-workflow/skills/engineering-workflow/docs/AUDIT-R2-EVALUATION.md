# Research Round 2 — Finding Evaluation

> Step 2: Categorize, validate against current file state, check ROI, set PASS/FAIL.
> Date: 2026-02-14
> Status: **ALL 8 PASS ITEMS IMPLEMENTED AND VERIFIED**

## Methodology

4 parallel research agents explored the codebase across:
- a7f1a1b: Workflow + Routing
- ab30861: Agents + Orchestrators
- a26a049: Design Patterns + Protocols
- a82633e: Context + Token Design

Each finding was validated by reading the actual file content. Stale findings
(referring to already-fixed issues) and hallucinations are marked FAIL.

---

## PASS — Implement

### P1. routing-protocol.md Domain Codes C/D/E Wrong [HIGH, LOW effort]
**Source**: a7f1a1b | **Validated**: YES

routing-protocol.md lines 137-140 define:
- C: Schema Design (should be C: Concurrency & Locking)
- D: Replication & HA (should be D: Schema & Normalization)
- E: Concurrency Control (should be E: I/O & Buffer Management)
- F: Sharding & Distribution (should be F: Distributed & Replication)

SKILL.md and _common.sh have the correct mappings. routing-protocol.md was not
updated during the domain name fix pass.

**Fix**: Update routing-protocol.md Step 3 table to match SKILL.md domain names/codes.

### P2. orchestration-protocol.md Stale Agent File Paths [HIGH, LOW effort]
**Source**: a26a049, a82633e | **Validated**: YES

orchestration-protocol.md lines 55-71 list old agent names:
- `storage-engine-agent.md` (actual: `a1-engine-selector.md`, `a2-compaction-strategist.md`)
- `query-optimization-agent.md` (actual: `b1-index-architect.md`, `b2-join-optimizer.md`, `b3-query-plan-analyst.md`)
- 6 DB agents listed (actual: 17 agents)
- 4 BE agents listed (actual: 18 agents)

**Fix**: Update the agent tree to reflect actual file names.

### P3. orchestration-protocol.md Output Schema Stale [HIGH, LOW effort]
**Source**: a26a049 | **Validated**: YES

orchestration-protocol.md lines 114-120 show old format:
```json
{"analysis": {}, "recommendation": "", "constraints": [], "trade_offs": [], "confidence": 0.0}
```

Actual orchestrator output (db-orchestrator.md, be-orchestrator.md) uses:
```json
{"system": "", "status": "", "guidance": "", "recommendations": [], "resolved_constraints": [], "unresolved_constraints": [], "metadata": {"confidence": 0.0}}
```

**Fix**: Update orchestration-protocol.md output template to match actual schemas.

### P4. Constraint Schema Mismatch [HIGH, MEDIUM effort]
**Source**: a26a049, a82633e | **Validated**: YES

- `_common.sh` write_constraint() creates a **flat array**: `[{constraint}, ...]`
- `resolve-constraints.sh` line 39 reads `.constraints // []` — expects **nested object**
- `constraint-propagation.md` documents nested: `{session_id, query, constraints: [...]}`

Result: resolve-constraints.sh will always get empty array from _common.sh-written files.

**Fix**: Update _common.sh to write the nested format matching constraint-propagation.md,
OR update resolve-constraints.sh to accept both formats.

### P5. Unused Orphan Reference Files [LOW, TRIVIAL effort]
**Source**: a7f1a1b, ab30861 | **Validated**: YES

Two old pre-split DB reference files remain:
- `references/db/domain-b-index-scan.md` (not referenced by any agent)
- `references/db/domain-e-io-pages.md` (not referenced by any agent)

**Fix**: Delete both files.

### P6. Missing NEVER Sections in 14/17 DB Agents [LOW, MEDIUM effort]
**Source**: ab30861 | **Validated**: YES

Only a1, a2, d3 have NEVER sections. All 18 BE agents have them.
Missing from: b1, b2, b3, c1, c2, c3, d1, d2, e1, e2, e3, f1, f2, f3.

**Fix**: Add concise NEVER sections to 14 DB agents for consistency.

### P7. Confidence Threshold Documentation Clarity [MEDIUM, LOW effort]
**Source**: a7f1a1b | **Validated**: YES

Three different threshold references:
- error-playbook.md EW-CLF-002: `confidence < 0.60` = ambiguous
- routing-protocol.md LLM thresholds: `0.50-0.69` = proceed with caveat
- classify-query.sh: `0.60` = multi-system result

These serve different purposes (fast-path vs LLM) but documentation doesn't
make this clear.

**Fix**: Add clarifying note to routing-protocol.md explaining the two-tier
threshold system (fast-path 0.60 / LLM 0.50).

### P8. Phase Pruning Clarification [MEDIUM, LOW effort]
**Source**: a82633e | **Validated**: PARTIALLY

orchestration-protocol.md lines 445-495 describe pruning rules. The agent
correctly notes Claude Code cannot delete context. However, pruning rules
serve as behavioral guidance (don't re-read/re-reference prior-phase files).

**Fix**: Add clarification note: "Pruning rules are behavioral guidance —
avoid loading or re-referencing materials from completed phases, rather
than literally removing them from context."

---

## FAIL — Skip

### F1. Execution Modes Not Implemented
**Source**: a7f1a1b | **Reason**: Aspirational design

Modes (query/analyze/compare/recommend) and flags (--domain, --depth) are
documented for LLM classification context, not for the bash fast-path.
The fast-path is intentionally simplified. Implementing modes in bash adds
complexity without value since the LLM fallback handles these.

### F2. Example Confidence Values Don't Match Algorithm
**Source**: a7f1a1b | **Reason**: Likely hallucination

The routing-protocol.md edge cases section (lines 286-290) does not include
confidence values. The research agent appears to have fabricated this finding.

### F3. Keyword List Differences SKILL.md vs _common.sh
**Source**: a7f1a1b | **Reason**: By design

routing-protocol.md's keyword-to-system matrix serves as LLM guidance context.
_common.sh contains the actual implementation keywords. They serve different
purposes and don't need to be identical.

### F4. Token Budgets Overstated by 20-34%
**Source**: a82633e | **Reason**: Conflated scopes

The research agent included SKILL.md core (2,540 tokens) and routing-protocol
(600 tokens) in per-query calculations. But SKILL.md is loaded once per
conversation, not per query. Token budgets in SKILL.md represent incremental
pipeline cost, not total conversation context. The 20% contingency note
already accounts for variations.

### F5. BE Chain 1 Doesn't Subsume Chain 5
**Source**: a26a049 | **Reason**: Handled correctly by merge algorithm

Chain 1 (11 agents) does not include B-5 and T-3 from Chain 5 (4 agents).
This is expected. The chain selection algorithm in be-orchestration-protocol.md
Step 3b handles non-superset cases correctly by merging unique agents.

### F6. Pattern Cache Signature Too Strict
**Source**: a82633e | **Reason**: LOW ROI, violates constraints

Natural language normalization would require NLP libraries, violating the
"bash + jq only" constraint. The pattern cache is a bonus optimization;
exact-match caching works for repeated identical queries.

### F7. Context Health Thresholds Not Implemented
**Source**: a82633e | **Reason**: Correctly documented as behavioral

The 70/80/85% thresholds in SKILL.md are behavioral guidelines for Claude
Code, not script-enforced limits. Claude Code naturally manages its own
context without explicit monitoring scripts.

### F8. Synthesizer Is "Just an Agent" — No Orchestration Logic
**Source**: a82633e | **Reason**: Correct architecture

The synthesizer IS an agent definition. It's dispatched by the Gateway Router
with orchestrator outputs as input. The synthesis logic is defined in the
agent's analysis procedure, same as all other agents. This is by design.

### F9. No Phase Tracking for Mid-Query Resumption
**Source**: a82633e | **Reason**: Aspirational, LOW ROI

Phase tracking would require persistent state management across Claude Code
sessions. The /compact recovery protocol is a nice-to-have, not a functional
requirement. Re-running classify-query.sh is fast and sufficient.

---

## Summary

| ID | Finding | Verdict | Priority | Effort |
|----|---------|---------|----------|--------|
| P1 | routing-protocol.md domain codes wrong | PASS | HIGH | LOW |
| P2 | orchestration-protocol.md stale agent paths | PASS | HIGH | LOW |
| P3 | orchestration-protocol.md output schema stale | PASS | HIGH | LOW |
| P4 | Constraint schema mismatch | PASS | HIGH | MEDIUM |
| P5 | Unused orphan reference files | PASS | LOW | TRIVIAL |
| P6 | Missing NEVER sections in DB agents | PASS | LOW | MEDIUM |
| P7 | Confidence threshold docs clarity | PASS | MEDIUM | LOW |
| P8 | Phase pruning clarification | PASS | MEDIUM | LOW |
| F1-F9 | Various | FAIL | — | — |

**8 PASS items, 9 FAIL items.**
Estimated total effort: ~45 min implementation.
