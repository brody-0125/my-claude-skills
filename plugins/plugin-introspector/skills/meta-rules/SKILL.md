---
name: meta-rules
description: >-
  Agent and skill writing rules for Claude Code plugins.
  Enforces anti-bloat constraints, token limits, and quality standards
  for all auto-generated improvements.
user-invocable: false
---

# Meta-Rules — Plugin Component Quality Gates

> Rules that govern how agents, skills, and workflows should be written.
> All auto-generated improvements MUST pass these rules before application.

## Token Limits

These limits apply to **auto-generated improvements** (output of improvement-generator and auto-optimizer). They constrain individual components, not the main orchestrating SKILL.md which serves as a command router.

| Component | Max Tokens | Measurement | Scope |
|-----------|-----------|-------------|-------|
| Agent description (.md) | 1000 | chars/4 | Per agent file |
| Knowledge skill (SKILL.md) | 500 | chars/4 | Per knowledge skill (meta-rules, analysis-patterns, cost-tracking) |
| Main skill (SKILL.md) | No hard limit | — | Orchestrating skill — uses lazy-load via resources/ |
| Single example | 200 | chars/4 | Per example block |
| Hook script | 100 lines | line count | Per standalone script |

## Writing Rules

### Agents

1. **ALWAYS use imperative voice** in instructions ("Analyze the traces" not "You should analyze the traces")
2. **ALWAYS specify input and output formats** explicitly
3. **NEVER exceed 1000 tokens** in the agent description
4. **ALWAYS include model assignment** (haiku/sonnet/opus) with justification
5. **Include 1-2 examples maximum** — more examples waste context
6. **NEVER use vague instructions** ("do your best", "try to", "if possible")
7. **ALWAYS specify exit conditions** — when is the agent done?

### Skills

1. **ALWAYS keep SKILL.md under 500 tokens** — use resources/ for details
2. **ALWAYS use the 2-layer structure**: SKILL.md (core) + resources/ (on-demand)
3. **NEVER load all resources at once** — lazy-load per phase/command
4. **ALWAYS declare allowed-tools explicitly** — minimal permissions
5. **ALWAYS include trigger conditions** in the description

### Hooks

1. **ALWAYS complete within 50ms** — hooks block execution
2. **ALWAYS use `|| true` fallback** — hook failures must not break workflow
3. **NEVER read large files** in hooks — use append-only writes
4. **ALWAYS use `set -euo pipefail`** in scripts
5. **NEVER install external dependencies** — bash + jq only

### Workflows

1. **ALWAYS define phase transitions** with explicit entry/exit conditions
2. **NEVER allow unbounded loops** — always set max_iterations
3. **ALWAYS provide rollback mechanisms** for destructive operations
4. **NEVER modify files without the user's explicit request**

## Anti-Bloat Rules

Prevent infinite growth of auto-generated content:

1. **Rule addition**: When adding a new rule, check if an existing rule covers the same case → merge instead of add
2. **Example cap**: Maximum 2 examples per section. If adding a third, remove the least useful existing one
3. **Description growth**: If a component grows beyond its token limit after improvement, the improvement MUST be rewritten to fit within the limit
4. **Periodic review**: Every 10 improvement cycles, run a deduplication pass on all agent/skill content
5. **Justification required**: Every rule must have a "why" — rules without justification are candidates for removal

## Validation Procedure

When checking a component against meta-rules:

```
1. Measure token count (chars / 4)
2. Check against component-type limit
3. Verify required sections exist (input, output, model assignment for agents)
4. Check for prohibited patterns (vague instructions, missing exit conditions)
5. Return: { passed: bool, violations: string[], token_count: number }
```
