# Validation Tiers

> Automatically adjusts validation intensity based on test generation scope.

## Tier Determination

```
Count = number of test classes generated in this session

LIGHT:     Count <= 2  (single class, simple tests)
STANDARD:  3 <= Count <= 8  (feature-level testing)
THOROUGH:  Count >= 9  (package/module-level testing)
```

**Override:** User can force tier via `validate --tier THOROUGH`

## Tier Capabilities

| Capability | LIGHT | STANDARD | THOROUGH |
|------------|-------|----------|----------|
| Compilation check | Yes | Yes | Yes |
| Test execution | Yes | Yes | Yes |
| Coverage measurement | Line only | Line + Branch | Line + Branch + Method |
| Coverage gap analysis | Skip | Top-5 gaps | All gaps |
| Mutation testing | Skip | PIT/Stryker (target classes only) | PIT/Stryker (full package) |
| Quality checklist | ERROR-only | ERROR + WARNING | All (ERROR + WARNING + INFO) |
| Architecture test check | Skip | If exists | Generate if missing |
| Quality re-review | No | No | Yes (re-read + check all generated tests) |

## Quality Re-review (THOROUGH only)

THOROUGH tier includes additional review step:
  → After Stage 4, re-read all generated test files
  → Check for test quality issues (empty assertions, duplicate logic, unreachable branches)
  → Report quality issues in Validation Report

## Tier Escalation

Automatic escalation from LIGHT to STANDARD if:
- Coverage result is below 60% line coverage
- More than 2 test failures on first run

Automatic escalation from STANDARD to THOROUGH if:
- Mutation kill rate is below 40%
- Same test failure persists for 3 consecutive fix attempts
