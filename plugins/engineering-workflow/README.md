# engineering-workflow

A **3-tier micro-agent orchestration plugin** for architecture decisions across four systems: **DB**, **BE**, **IF**, and **SE**.

Instead of a monolithic response, it classifies a query, routes it to the right system orchestrators and micro agents, resolves constraints, and returns a unified recommendation.

## Quick Start

```bash
# Example 1) General query (default: deep)
/engineering-workflow "Which is better for write-heavy workloads: B-tree or LSM-tree?"

# Example 2) Analyze mode
/engineering-workflow "analyze: bottlenecks in our current sharding strategy"

# Example 3) Compare mode
/engineering-workflow "compare: PostgreSQL vs CockroachDB for multi-tenant"

# Example 4) Recommend mode + depth
/engineering-workflow "recommend: caching strategy for read-heavy APIs" --depth shallow
```

Argument hint:

```text
[query | analyze | compare | recommend] [--domain db|be|if|se] [--depth shallow|deep]
```

---

## Core Features

- **Deterministic fast-path classification** via `scripts/classify-query.sh`
- **3-tier orchestration**
  - Tier 1: Gateway Router (SKILL)
  - Tier 2: System Orchestrators (DB/BE/IF/SE)
  - Tier 3: Domain Micro Agents
- **Constraint propagation and conflict resolution** via `resolve-constraints.sh`
- **Quality gates** via `audit-analysis.sh` (confidence/schema/synthesis checks)
- **Session learning cache** (`pattern-cache.json`) for repeated query patterns
- **False-positive resistant keyword matching** using word-boundary based detection

---

## Routing Overview

### System Routing

- **DB**: storage, index, query plans, concurrency, schema, replication, etc.
- **BE**: API, service layer, resilience, test architecture, etc.
- **IF**: infrastructure, deployment, k8s, CI/CD, observability, etc.
- **SE**: authentication, encryption, RBAC/ABAC, compliance, security, etc.

### Sub-routing

- **DB Domains A–F**: Storage, Query Plan, Concurrency, Schema, I/O, Distributed
- **BE Clusters S/B/R/T**: Structure, Boundary, Resilience, Test

For detailed matrices and routing rules, see:
- `skills/engineering-workflow/SKILL.md`
- `skills/engineering-workflow/resources/routing-protocol.md`
- `skills/engineering-workflow/resources/orchestration-protocol.md`

---

## Execution Pipeline

1. **Phase 0 — Classification**
2. **Phase 1 — Orchestrator Dispatch**
3. **Phase 2 — Agent Execution**
4. **Phase 2.5 — Analysis Quality Gate**
5. **Phase 3 — Constraint Resolution**
6. **Phase 3.5 — Contract Enforcement Gate**
7. **Phase 4 — Synthesis (cross-system only)**
8. **Phase 4.5 — Synthesis Validation Gate**
9. **Phase 5 — Output Formatting**

---

## Scripts

Location: `plugins/engineering-workflow/skills/engineering-workflow/scripts/`

| Script | Purpose |
|---|---|
| `classify-query.sh` | Query classification (`systems`, `domains`, `be_clusters`, `confidence`) |
| `resolve-constraints.sh` | Constraint conflict detection and resolution |
| `format-output.sh` | Final output formatting |
| `validate-agent-output.sh` | Agent output schema/quality validation |
| `audit-analysis.sh` | Audit tier, confidence, orchestrator, synthesis validation |
| `_common.sh` | Shared utilities (keywords/session cache/cleanup) |

---

## Tests

Location: `plugins/engineering-workflow/skills/engineering-workflow/tests/`

```bash
cd plugins/engineering-workflow/skills/engineering-workflow

# Classification regression tests
bash tests/run-classification-tests.sh

# Constraint resolution tests
bash tests/run-constraint-tests.sh

# Output format tests
bash tests/run-format-tests.sh

# Agent output validation tests
bash tests/run-validation-tests.sh
```

---

## Hook Behavior (`.claude-plugin/plugin.json`)

- **PreToolUse (Edit/Write)**: blocks edits to production secret/credential-like files
- **PostToolUse (Write)**: validates `constraints.json` as valid JSON
- **Stop**: archives constraints and trims history retention

---

## Cache and Session Storage

`~/.claude/cache/engineering-workflow/`

- `constraints.json`: current session constraint set
- `session-history.jsonl`: query classification history
- `pattern-cache.json`: repeated pattern cache
- `history/`: archived session constraints

---

## Directory Structure

```text
plugins/engineering-workflow/
├── .claude-plugin/
│   └── plugin.json
└── skills/engineering-workflow/
    ├── SKILL.md
    ├── agents/
    ├── resources/
    ├── references/
    ├── scripts/
    ├── tests/
    └── templates/
```

---

## Requirements

- `bash 3.2+`
- `jq`
- `grep`, `awk`, `sed`
- Unix-like environment (macOS/Linux recommended)

No external build runtime is required; the plugin is script-driven.

---

## References

- Main skill definition: `plugins/engineering-workflow/skills/engineering-workflow/SKILL.md`
- Priority rules: `plugins/engineering-workflow/skills/engineering-workflow/resources/priority-matrix.md`
- Synthesis protocol: `plugins/engineering-workflow/skills/engineering-workflow/resources/synthesis-protocol.md`
- Error handling: `plugins/engineering-workflow/skills/engineering-workflow/resources/error-playbook.md`
