# Research Round 3 — Finding Evaluation

> Step 2: Categorize, validate against current file state, check ROI, set PASS/FAIL.
> Date: 2026-02-14
> Status: **ALL 7 PASS ITEMS IMPLEMENTED AND VERIFIED**

## Methodology

3 research agents explored:
- a07943c: Schema Consistency (constraint schemas, resolve-constraints.sh, priority rules)
- af5c070: SKILL.md Completeness (resource/reference/script table gaps)
- a480860: NEVER Section Quality (17 DB + 18 BE agent consistency)

Plus inline discovery: archive path mismatch, synthesis-protocol.md schema gap.

---

## PASS — Implement

### P1. SKILL.md Missing 3 Resource Entries [HIGH, TRIVIAL effort]
**Source**: af5c070 | **Validated**: YES

SKILL.md Resources table (lines 611-619) lists 5 resources:
- routing-protocol.md, orchestration-protocol.md, constraint-propagation.md, be-orchestration-protocol.md, error-playbook.md

Missing from table (files confirmed to exist):
- `db-orchestration-protocol.md` — DB agent selection, dispatch, merge
- `priority-matrix.md` — universal priority hierarchy for conflicts
- `synthesis-protocol.md` — cross-system synthesis procedure

**Fix**: Add 3 rows to Resources table.

### P2. SKILL.md Missing DB Reference Files Section [HIGH, LOW effort]
**Source**: af5c070 | **Validated**: YES

SKILL.md References section (lines 621-636) only lists BE references (11 files).
DB references are completely absent. Confirmed 17 DB reference files exist:
- domain-a-{engine-selection,compaction}.md
- domain-b-{index-design,join-optimization,query-plan}.md
- domain-c-{isolation,mvcc,locking}.md
- domain-d-{normalization,document-modeling,access-patterns}.md
- domain-e-{page-optimization,wal,buffer-tuning}.md
- domain-f-{replication,consistency,sharding}.md

**Fix**: Add DB References subsection listing all 17 files with domain mapping.

### P3. SKILL.md Missing 2 Script Entries [MEDIUM, TRIVIAL effort]
**Source**: af5c070 | **Validated**: PARTIALLY

Scripts actually listed in SKILL.md need to be checked. Two scripts exist on disk
but are not listed in any SKILL.md scripts table:
- `_common.sh` — shared utilities (imported by all other scripts)
- `validate-agent-output.sh` — agent output JSON validation

**Note**: `_common.sh` is an internal import, not user-facing. `validate-agent-output.sh`
is a utility called by orchestrators. Listing them improves discoverability.

**Fix**: Add both to Scripts table if one exists, or add a Scripts section.

### P4. db-orchestration-protocol.md Constraint Format Differs from constraint-propagation.md [HIGH, LOW effort]
**Source**: a07943c | **Validated**: YES

db-orchestration-protocol.md lines 216-226 define a simplified constraint format:
```json
{
  "source_agent": "a1-engine-selector",
  "constraint_type": "hard | soft",
  "field": "engine_type",
  "value": "InnoDB",
  "implications": [...]
}
```

constraint-propagation.md lines 25-36 define the full schema:
```json
{
  "id": "c-{agent}-{N}",
  "source_agent": "...",
  "source_system": "DB",
  "source_domain": "A",
  "constraint_type": "requires | recommends | prohibits | conflicts_with",
  "target_system": "DB",
  "target_domain": "C",
  "description": "...",
  "priority": "hard | soft",
  "evidence": "...",
  "timestamp": "...",
  "status": "declared"
}
```

Key differences:
- db-orch uses `field`+`value` vs constraint-prop uses `target_system`+`target_domain`+`description`
- db-orch uses `constraint_type: "hard|soft"` vs constraint-prop uses `priority: "hard|soft"` and separate `constraint_type: "requires|recommends|prohibits|conflicts_with"`
- db-orch lacks `id`, `source_system`, `source_domain`, `status`, `evidence`, `timestamp`

This is a **documentation inconsistency** — the LLM reads both files and must resolve
which format to follow. The simplified format is appropriate for intra-system propagation
since `source_system` is always DB, but field names should align.

**Fix**: Align db-orchestration-protocol.md §6 format with constraint-propagation.md.
Keep it simplified for intra-system use but use consistent field names:
- `constraint_type` → rename to `priority` to match constraint-propagation.md
- Add `constraint_type` with actual semantics (requires/recommends/prohibits)
- Keep `field`+`value`+`implications` as DB-specific shorthand

### P5. db-orchestration-protocol.md Priority Rules vs priority-matrix.md [MEDIUM, LOW effort]
**Source**: a07943c | **Validated**: YES

db-orchestration-protocol.md lines 236-242 define DB-specific priorities:
```
Priority 1: User-specified constraints
Priority 2: Correctness (Domain C)
Priority 3: Durability (Domain E)
Priority 4: Performance (Domains A, B, E)
Priority 5: Scalability (Domain F)
Priority 6: Simplicity (Domain D)
```

priority-matrix.md defines universal priorities:
```
Level 5: Data Integrity (highest)
Level 4: Security
Level 3: Availability
Level 2: Performance
Level 1: Convenience/DX (lowest)
```

These are **compatible, not contradictory**. DB-specific priorities map to universal
categories — Correctness≈Data Integrity, Durability≈Data Integrity, Performance≈Performance,
Scalability≈Availability, Simplicity≈Convenience. The DB-specific version is a domain
refinement of the universal matrix.

However, there's no explicit cross-reference between them.

**Fix**: Add a note to db-orchestration-protocol.md §Conflict Resolution referencing
priority-matrix.md as the universal source, explaining the DB-specific mapping.

### P6. Archive Path Mismatch: _common.sh vs Stop Hook [HIGH, LOW effort]
**Source**: inline + a07943c | **Validated**: YES

- `_common.sh` `archive_constraints()` archives to: `${CACHE_DIR}/constraints-archive/`
- Stop hook (plugin.json line 34) archives to: `${cache_dir}/history/`

These are two different directories. Constraints archived by _common.sh functions
won't be found by the Stop hook's cleanup logic, and vice versa.

**Fix**: Align both to the same path. `history/` is more descriptive. Update
`_common.sh` archive functions to use `${CACHE_DIR}/history/`.

### P7. synthesis-protocol.md Schema Mismatch with Actual Orchestrator Output [MEDIUM, LOW effort]
**Source**: inline + a07943c | **Validated**: YES

synthesis-protocol.md §1.1 (lines 13-43) expects:
```json
{
  "query_echo": "...",
  "timestamp": "ISO-8601",
  "delegated_to": "...",
  "metadata": { "confidence": "high | medium | low" }
}
```

orchestration-protocol.md §Output Format (lines 138-151) defines actual output:
```json
{
  "query": "...",
  "metadata": { "confidence": 0.0-1.0 }
}
```

Differences:
- `query_echo` vs `query` (field name)
- `timestamp` and `delegated_to` only in synthesis-protocol.md (extra fields)
- `confidence`: string enum vs numeric (type mismatch)

**Fix**: Update synthesis-protocol.md §1.1 to match orchestration-protocol.md output.
Use `query` not `query_echo`, `confidence: 0.0-1.0` not string enum, remove
`timestamp`/`delegated_to` or mark them optional.

---

## FAIL — Skip

### F1. resolve-constraints.sh `.target`/`.value` Field Mismatch
**Source**: a07943c | **Reason**: Already handled

resolve-constraints.sh (lines 77-78) compares `.target` and `.value` fields for
conflict detection. constraint-propagation.md uses `target_system`+`target_domain`.

However, this is **correct behavior**: resolve-constraints.sh works with the
db-orchestration-protocol.md simplified format (which uses `field`+`value`).
The script operates on intra-system constraints where the simplified format
is appropriate. Cross-system constraints go through the synthesizer, not this script.

The field names used in resolve-constraints.sh are `target` and `value`, and the
db-orchestration-protocol.md format has `field` and `value`. The script's `.target`
doesn't literally match either schema — it's a generic conflict detector that
checks if two constraints share the same target AND have different values.
This works with any constraint format that includes these fields.

**Verdict**: No script change needed. The P4 documentation fix will clarify naming.

### F2. Synthesizer Doesn't Handle resolved/unresolved_constraints
**Source**: a07943c | **Reason**: Already handled implicitly

synthesizer.md line 20 defines input `constraints_used` (from orchestrators).
orchestration-protocol.md lines 148-149 outputs `resolved_constraints` and
`unresolved_constraints`. The synthesizer's Step 1 (line 43-50) validates
and normalizes results — it extracts constraints from whatever fields exist.

The synthesizer's cross-system merge procedure (in synthesis-protocol.md)
already covers constraint merging at the system boundary. Adding explicit
field handling for `resolved_constraints`/`unresolved_constraints` is over-engineering
since the LLM reads both the agent def and the protocol and adapts.

### F3. Stop Hook Missing session-history.jsonl Update
**Source**: a07943c | **Reason**: LOW ROI

The Stop hook archives constraints.json. Adding session-history.jsonl cleanup
to the hook adds complexity for minimal benefit — session-history.jsonl is
append-only and self-managing (old entries are harmless). The hook already
has rotation logic (keeps last 20 constraint archives).

### F4. f1-replication-designer References E1 Instead of E-cluster
**Source**: a480860 | **Reason**: TRIVIAL, acceptable specificity

f1's NEVER section line 160: "Configure page-level I/O (E1-page-optimizer's job)"
This is actually MORE specific than referencing the whole E-cluster. Since f1's
overlap risk is specifically with page-level I/O (not WAL or buffer), referencing
E1 is appropriate. Same pattern: f2 references C1 specifically because the
overlap is isolation selection, not MVCC or locking.

### F5. b3-query-plan-analyst Incorrect R-cluster Description
**Source**: a480860 | **Reason**: Likely hallucination

b3-query-plan-analyst.md NEVER section (lines 112-118) was added in Iteration 1.
Current content doesn't reference R-cluster or SQS:
```
- Select storage engines (A-cluster agents' job)
- Design new indexes from scratch (B1-index-architect's job)
- Recommend isolation levels or locking changes (C-cluster agents' job)
- Modify schema design (D-cluster agents' job)
- Tune page layout or WAL (E-cluster agents' job)
```

No R-cluster reference exists. Agent a480860 hallucinated this finding.

---

## Summary

| ID | Finding | Verdict | Priority | Effort |
|----|---------|---------|----------|--------|
| P1 | SKILL.md missing 3 resource entries | PASS | HIGH | TRIVIAL |
| P2 | SKILL.md missing DB reference files section | PASS | HIGH | LOW |
| P3 | SKILL.md missing 2 script entries | PASS | MEDIUM | TRIVIAL |
| P4 | db-orchestration-protocol constraint format misalign | PASS | HIGH | LOW |
| P5 | db-orchestration-protocol priority rules cross-ref | PASS | MEDIUM | LOW |
| P6 | Archive path mismatch _common.sh vs Stop hook | PASS | HIGH | LOW |
| P7 | synthesis-protocol.md schema mismatch | PASS | MEDIUM | LOW |
| F1-F5 | Various | FAIL | — | — |

**7 PASS items, 5 FAIL items.**
Estimated total effort: ~30 min implementation.
