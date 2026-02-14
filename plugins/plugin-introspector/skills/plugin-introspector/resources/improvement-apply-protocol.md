# Improvement Apply Protocol

> Defines the safe procedure for applying improvement proposals to target plugin files.
> All improvements go through: Review → Backup → Apply → Verify → Log.

## Prerequisites

- An improvement proposal from `improve` or `optimize` command
- The proposal MUST have `meta_rules_check.passed: true`
- The target plugin directory must be writable

---

## Apply Procedure

### Step 1: Review (User Required)

Display the proposal to the user:
```
Proposal: {id} — {description}
Target:   {target_file}
Type:     {change_type} (modify|add|remove)
Impact:   {estimated savings or score improvement}
Meta-rules: PASSED ✓

--- Diff ---
{diff content}
--- End ---

Apply this change? (yes/no)
```

**NEVER auto-apply.** Wait for explicit user confirmation.

### Step 2: Backup

Before modifying any file:
```
1. Create backup directory: SESSION_DIR/backups/
2. Copy target file: cp {target_file} SESSION_DIR/backups/{filename}.bak
3. Record backup path for rollback
```

### Step 3: Apply

Apply the diff using the Edit tool:
```
1. Read the target file
2. Use Edit tool with old_string/new_string from the diff
3. If Edit fails (old_string not found): abort and report mismatch
```

### Step 4: Verify

After applying:
```
1. Re-read the modified file
2. Run meta-rules validation on the modified component:
   - Token count within limits?
   - Required sections present?
   - No prohibited patterns?
3. If validation fails: rollback (restore from backup)
```

### Step 5: Log

Record the applied improvement:
```json
// Append to ~/.claude/plugin-introspector/improvement_log.jsonl
{
  "applied_at": "ISO-8601",
  "session_id": "session-20250131-120000",
  "proposal_id": "IMP-001",
  "target_plugin": "sub-kopring-engineer",
  "target_file": "agents/workflow-analyzer.md",
  "change_type": "modify",
  "description": "Added file caching instruction",
  "backup_path": "sessions/{sid}/backups/workflow-analyzer.md.bak",
  "pre_score": 3.2,
  "post_score": null,
  "status": "applied"
}
```

The `post_score` is filled in after the next evaluation cycle.
The `status` lifecycle: `applied` → `validated` (score maintained/improved) or `regressed` (score dropped >0.5).

---

## Rollback Procedure

If an improvement needs to be reverted:

```
1. Read improvement_log.jsonl to find the backup_path
2. Copy backup over the current file: cp {backup_path} {target_file}
3. Append rollback record to improvement_log.jsonl:
   {
     "rolled_back_at": "ISO-8601",
     "proposal_id": "IMP-001",
     "reason": "Post-evaluation score decreased"
   }
```

---

## Batch Apply (Multiple Proposals)

When `improve` generates multiple proposals:

```
1. Sort proposals by priority (CRITICAL → HIGH → MEDIUM → LOW)
2. Apply one at a time, verifying after each
3. If any proposal's verification fails: stop, report remaining unapplied
4. After all applied: run evaluate to get post-improvement scores
5. Update improvement_log.jsonl with post_score for each
```

---

## Closed Loop: Post-Apply Evaluation

After improvements are applied and the plugin is used in a subsequent session:

```
1. Next time evaluate runs: compare scores with pre-improvement baseline
2. If any dimension dropped by >0.5: flag for review
3. If overall weighted_score improved: mark improvement as "validated"
4. If overall weighted_score decreased: suggest rollback
```
