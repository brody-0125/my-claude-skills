# Error Handling Framework

> Standardized error response patterns across all phases.
> For specific error resolutions, see [error-playbook.md](error-playbook.md).

---

## 1. Error Levels

### Level 1: Immediate Retry (Transient)

**Characteristics:**
- Network errors, timeouts
- Temporary resource unavailability
- Intermittent failures

**Response Pattern:**
```
1. Retry up to 3 times
2. Use exponential backoff: 1s, 2s, 4s
3. If all retries fail → escalate to Level 2
```

**Examples:**
- Network timeout during `git fetch`
- Docker container startup delay
- Temporary port conflict

---

### Level 2: Alternative Approach (Fallback)

**Characteristics:**
- Tool unavailable
- Permission denied
- Feature not configured

**Response Pattern:**
```
1. Identify available alternative
2. Apply fallback approach
3. Log warning about degraded mode
4. Continue with reduced functionality
```

**Examples:**
| Primary | Fallback | Impact |
|---------|----------|--------|
| ast-grep extraction | LLM-only analysis | Slower, less precise |
| ClassGraph (Layer 2) | Layer 1a+1b only | Missing bytecode info |
| JaCoCo coverage | Skip coverage stage | No coverage metrics |
| PIT mutation | Skip mutation stage | No mutation metrics |
| Agent Teams | Sequential processing | Slower execution |

**Log Format:**
```
⚠ {Tool} not available. Falling back to {Alternative}.
  To enable: {installation instructions}
```

---

### Level 3: Root Cause Analysis (3-Strike Rule)

**Characteristics:**
- Same error occurs 3 consecutive times
- Fix attempts do not resolve the issue
- Indicates deeper problem

**Response Pattern:**
```
1. Capture: Record error + all 3 fix attempts
2. Analyze: Identify wrong assumption or root cause
3. Reapproach: Design fundamentally different solution
4. Apply: Implement from scratch (not incremental patch)
5. If still failing → escalate to Level 4
```

**Trigger Conditions:**
- Same compilation error 3x
- Same test failure 3x after fixes
- Same validation violation 3x

**Analysis Template:**
```markdown
### Root Cause Analysis

**Error**: {error message}
**Occurrences**: 3

**Fix Attempts**:
1. {attempt 1} → Failed because: {reason}
2. {attempt 2} → Failed because: {reason}
3. {attempt 3} → Failed because: {reason}

**Root Cause**: {identified assumption/issue}

**New Approach**: {fundamentally different solution}
```

---

### Level 4: User Escalation (Unrecoverable)

**Characteristics:**
- All automatic resolution failed
- Requires manual intervention
- Environment/configuration issue

**Response Pattern:**
```
1. Stop automatic attempts
2. Report full context to user
3. Suggest manual investigation steps
4. Continue with remaining targets (if possible)
```

**Report Format:**
```markdown
### Unrecoverable Error

**Phase**: {phase name}
**Target**: {file/class name}
**Error**: {error message}

**Attempted Solutions**:
1. {solution 1} — {outcome}
2. {solution 2} — {outcome}

**Suggested Actions**:
- {manual step 1}
- {manual step 2}

**Impact**: {what will be skipped/affected}
```

---

## 2. Error Categories

### 2.1 Build/Compilation Errors

| Error Type | Level | Resolution |
|------------|-------|------------|
| Missing import | 2 | Add import automatically |
| Type mismatch | 3 | Analyze type hierarchy, fix |
| Unresolved reference | 3 | Check cross-module deps |
| Syntax error | 2 | Parse and fix syntax |

### 2.2 Test Execution Errors

| Error Type | Level | Resolution |
|------------|-------|------------|
| Assertion failure | 2 | Review logic, adjust assertion |
| Mock setup error | 2 | Add missing stub |
| NullPointerException | 2 | Add null-safe setup |
| Timeout | 2 | Add async handling |
| Infrastructure error | 2 | Fallback or skip |

### 2.3 Tool Errors

| Error Type | Level | Resolution |
|------------|-------|------------|
| Tool not found | 2 | Use fallback |
| Tool version mismatch | 2 | Warn and proceed |
| Out of memory | 2 | Narrow scope, retry |
| Configuration error | 4 | Report to user |

### 2.4 Environment Errors

| Error Type | Level | Resolution |
|------------|-------|------------|
| Docker not running | 2 | Skip container tests |
| Network unavailable | 1 | Retry with backoff |
| Permission denied | 4 | Report to user |
| Disk full | 4 | Report to user |

---

## 3. Graceful Degradation Matrix

| Feature | Availability Check | Degradation |
|---------|-------------------|-------------|
| ast-grep | `command -v ast-grep` | LLM-only extraction |
| ClassGraph | `java -version` ≥ 17 | Skip Layer 2 |
| JaCoCo/Kover | `check_plugin "jacoco"` | Skip coverage stage |
| PIT/Stryker | `check_plugin "pitest"` | Skip mutation stage |
| Testcontainers | `docker info` | Skip integration tests |
| Agent Teams | env flag check | Sequential processing |

**Implementation:**
```bash
# In scripts, check before using optional features
if ! check_feature_available; then
    log_warning "Feature not available, using fallback"
    use_fallback_approach
fi
```

---

## 4. Error Response by Phase

### Phase 0 (Discovery)

| Error | Level | Action |
|-------|-------|--------|
| Build config not found | 4 | Report — cannot proceed |
| Test framework not detected | 2 | Warn, use heuristics |
| Coverage tool not configured | 2 | Skip coverage baseline |

### Phase 1 (Analyze)

| Error | Level | Action |
|-------|-------|--------|
| ast-grep not found | 2 | Fallback to LLM analysis |
| No matches found | 2 | Expand search scope |
| ClassGraph error | 2 | Skip Layer 2 |

### Phase 2 (Strategize)

| Error | Level | Action |
|-------|-------|--------|
| Unknown code layer | 2 | Use default technique |
| Missing dependency info | 2 | Infer from imports |

### Phase 3 (Generate)

| Error | Level | Action |
|-------|-------|--------|
| Pattern not learned | 2 | Use default patterns |
| Focal context too large | 2 | Trim to essentials |
| Agent Teams unavailable | 2 | Sequential processing |

### Phase 4 (Validate)

| Error | Level | Action |
|-------|-------|--------|
| Compilation error | 3 | Apply 3-strike rule |
| Test failure | 3 | Apply 3-strike rule |
| Coverage tool missing | 2 | Skip stage, report N/A |
| Mutation tool missing | 2 | Skip stage, report N/A |

---

## 5. Logging Standards

### Log Levels

| Level | Prefix | Use Case |
|-------|--------|----------|
| INFO | `[Phase N]` | Normal progress |
| WARN | `⚠` | Degraded mode, non-fatal |
| ERROR | `✗` | Fatal, requires action |
| DEBUG | `[DEBUG]` | Diagnostic (verbose mode) |

### Log Format

```
[Phase {N}] {action description}
  → {outcome}

⚠ {warning message}
  To enable: {instructions}

✗ {error message}
  Attempted: {solutions}
  Action required: {user steps}
```

---

## 6. Error Playbook Cross-Reference

For specific error resolutions, see sections in [error-playbook.md](error-playbook.md):

| Category | Playbook Section |
|----------|------------------|
| MockK errors | Section 1 |
| Mockito errors | Section 2 |
| Testcontainers errors | Section 3 |
| Coverage tool errors | Section 4 |
| Spring context errors | Section 5 |
| Test flakiness | Section 6 |
| ClassGraph errors | Section 7 |
| 3-Strike rule | Section 8 |
| Wrong file location | Section 9 |
| Suite isolation | Section 10 |
| Coverage report missing | Section 11 |
| Agent Teams errors | Section 12 |
| Go testing errors | Section 13 |

---

## 7. Quick Decision Tree

```
Error Occurred
    │
    ├─ Is it transient (network, timeout)?
    │   └─ Yes → Level 1: Retry (3x with backoff)
    │
    ├─ Is there a fallback/alternative?
    │   └─ Yes → Level 2: Use fallback, warn user
    │
    ├─ Has this same error occurred 3x?
    │   └─ Yes → Level 3: Root cause analysis
    │
    └─ Is automatic resolution possible?
        ├─ Yes → Apply resolution from playbook
        └─ No → Level 4: Escalate to user
```
