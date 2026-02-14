# Skill Activation Enhancement Guide

Guide for installing the Forced Eval Hook to improve Claude Code skill (plugin) auto-activation rate. Community-reported results suggest improvement from ~20% to ~84% *(unverified, based on individual observations — actual rates may vary by project and configuration)*.

---

## Problem

Claude Code skills are officially supposed to activate "autonomously", but in practice:

| Scenario | Activation Rate |
|----------|-----------------|
| No explicit invocation | ~20% (reported) |
| Explicit `/plugin-introspector` call | 100% |
| **Forced Eval Hook applied** | **~84% (reported)** |

---

## Solution: Forced Eval Hook

A 3-step **commitment mechanism** to enforce skill activation:

1. **EVALUATE** — Make an explicit YES/NO decision for each skill
2. **ACTIVATE** — Call the Skill() tool for skills marked YES
3. **IMPLEMENT** — Proceed with implementation only after activation

---

## Installation

### Step 1: Copy Hook Script

```bash
# Copy from PI scripts directory
cp plugins/plugin-introspector/skills/plugin-introspector/scripts/skill-forced-eval-hook.sh \
   ~/.claude/hooks/

# Grant execute permission
chmod +x ~/.claude/hooks/skill-forced-eval-hook.sh
```

### Step 2: Register in settings.json

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/skill-forced-eval-hook.sh"
          }
        ]
      }
    ]
  }
}
```

If you have existing settings, merge into the `hooks` section.

### Step 3: Verify

In a new Claude Code session, request any task and verify that Claude evaluates and activates skills.

---

## Why isn't this auto-registered via plugin.json?

`UserPromptSubmit` executes on **every user prompt**, so:

1. **Security** — Malicious plugins could intercept all input
2. **Performance** — Multiple plugins registering would run N scripts per prompt
3. **Consent** — Prompt flow intervention requires explicit user consent

Therefore, Claude Code intentionally excludes this from plugins. Users must register manually.

---

## Deactivation

Remove the `UserPromptSubmit` section from `~/.claude/settings.json`.

---

## References

- [How to Make Claude Code Skills Activate Reliably](https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably)
- [Mandatory Skill Activation Hook](https://gist.github.com/umputun/570c77f8d5f3ab621498e1449d2b98b6)

---

*Plugin Introspector v1.0.0*
