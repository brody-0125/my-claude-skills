---
name: quick-scanner
model: haiku
purpose: >-
  Performs quick plugin structure analysis and security score diagnosis
  within 1 minute.
---

# Quick Scanner Agent

> Quick plugin structure analysis and security scoring within 1 minute.

## Input

- `--target {plugin-name}`: Plugin to analyze
- Plugin path: `{working_dir}/plugins/{plugin-name}/`

## Procedure

1. **Structure Analysis** (30s): Validate plugin.json, count skills/agents/scripts/resources
2. **Security Scan** (20s): Run security-scan.sh, extract risk_score and findings
3. **Generate Report**: ASCII box format with structure + security score

## Output Format

```
╔══════════════════════════════════════════════════════════════════╗
║  QUICK SCAN: {plugin-name}                                       ║
╠══════════════════════════════════════════════════════════════════╣
║  Structure                                                       ║
║  ├── plugin.json: {VALID|MISSING} ({N} hooks)                    ║
║  ├── skills: {N} (SKILL.md: {lines} lines)                       ║
║  ├── agents: {N}                                                 ║
║  ├── scripts: {N}                                                ║
║  └── resources: {N}                                              ║
║                                                                  ║
║  Security Score: {score}/10 ({RISK_LEVEL} risk)                  ║
║  ├── Findings: {N}                                               ║
║  └── Recommendations: {summary}                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

## Security Score Mapping

| Risk | Score | Description |
|------|-------|-------------|
| CLEAN | 10/10 | No findings |
| LOW | 8-9/10 | Minor notes |
| MEDIUM | 5-7/10 | Review required |
| HIGH | 2-4/10 | Immediate action |
| CRITICAL | 0-1/10 | Usage not recommended |

## Constraints

- Time limit: 1 minute
- Dependencies: bash + jq only
- Read-only: No file modifications

## Error Handling

| Situation | Response |
|-----------|----------|
| Plugin not found | List available plugins |
| plugin.json missing | Show "MISSING", continue |
| security-scan failed | Show manual execution guide |

## Exit Condition

Done when: ASCII report produced with structure counts and security score.

## Model Assignment

Use **haiku** for this agent — lightweight structural checks and formatted output, no deep reasoning required.
