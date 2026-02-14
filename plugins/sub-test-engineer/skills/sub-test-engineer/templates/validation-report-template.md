## Validation Report: Loop {N}

### Pipeline Results
| Stage | Status | Details |
|-------|--------|---------|
| Compilation | {PASS/FAIL} | {detail} |
| Execution | {PASS/FAIL} | {passed}/{total} tests green |
| Coverage | {PASS/FAIL/WARN} | {line%} line / {branch%} branch (target: {target%}) |
| Mutation | {PASS/FAIL/WARN/SKIP} | {kill%} kill rate (target: {target%}) |
| Quality | {PASS/WARN} | {error count} errors, {warning count} warnings |

### Coverage Delta
| Package | Before | After | Delta |
|---------|--------|-------|-------|
| {package} | {before%} | {after%} | {delta} |

### Uncovered Gaps (top 5)
| File | Line(s) | Type | Priority |
|------|---------|------|----------|
| {file} | {lines} | {error-path/branch/logic} | {HIGH/MEDIUM/LOW} |

### Survived Mutants (top 5)
| File:Line | Mutation | Missing Test |
|-----------|----------|-------------|
| {file}:{line} | {mutation description} | {suggested test} |

### Quality Violations
| Severity | File | Rule | Details |
|----------|------|------|---------|
| {ERROR/WARNING/INFO} | {file} | {rule} | {details} |

### Recommendations
- {actionable recommendation}

### Loop Decision
- **Action**: {EXIT (success) / EXIT (convergence) / CONTINUE / ESCALATE}
- **Reason**: {reason}
