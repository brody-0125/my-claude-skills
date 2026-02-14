# Plugin Introspector Skills Map

> Central index for navigating the Plugin Introspector plugin structure.
> For commands and agents, see [SKILL.md](../SKILL.md).

---

## Directory Structure

```
plugin-introspector/
├── skills/
│   ├── plugin-introspector/     # Core orchestration skill
│   │   ├── SKILL.md             # Main command router (24 commands)
│   │   ├── agents/              # 12 analysis agents
│   │   ├── resources/           # Protocol documents
│   │   └── scripts/             # Hook and utility scripts
│   ├── meta-rules/              # Anti-bloat validation rules
│   ├── analysis-patterns/       # Reusable analysis heuristics
│   └── cost-tracking/           # Token/cost calculation
└── .claude-plugin/
    └── plugin.json              # 8 registered hooks
```

---

## Knowledge Skills

| Skill | Purpose | Key Constraints |
|-------|---------|-----------------|
| [meta-rules](../../meta-rules/SKILL.md) | Anti-bloat validation | Agent max 1000 tok, Hook max 100 lines/<50ms |
| [analysis-patterns](../../analysis-patterns/SKILL.md) | Analysis heuristics | Z-score, MA, tool sequence patterns |
| [cost-tracking](../../cost-tracking/SKILL.md) | Pricing & ROI | `(Impact x Confidence) / (Effort x Risk)` |

---

## Scripts

> 9 hook scripts (8 events) + 10 utility scripts, all sharing `_common.sh`.
> For detailed script-to-hook mappings and descriptions, see [orchestration-protocol.md](orchestration-protocol.md).

---

## Skill Dependencies

```
                    ┌─────────────────────┐
                    │ plugin-introspector │
                    │   (orchestrator)    │
                    └─────────┬───────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
  ┌───────────┐       ┌───────────────┐     ┌─────────────┐
  │meta-rules │       │analysis-      │     │cost-tracking│
  │           │       │patterns       │     │             │
  └───────────┘       └───────────────┘     └─────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                              ▼
                   ┌──────────────────────┐
                   │ improvement-generator│
                   │ auto-optimizer       │
                   │ (consume all three)  │
                   └──────────────────────┘
```

---

## Data Flow Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Hooks     │────►│  JSONL Data │────►│   Agents    │
│ (real-time) │     │  (storage)  │     │ (analysis)  │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              ▼
                                        ┌─────────────┐
                                        │  Proposals  │
                                        │ (improve)   │
                                        └─────────────┘
```

---

**Plugin Introspector v1.0.0**

*Last updated: 2026-02-06*
