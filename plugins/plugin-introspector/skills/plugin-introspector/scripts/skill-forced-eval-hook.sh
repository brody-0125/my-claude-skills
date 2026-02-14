#!/usr/bin/env bash
# Plugin Introspector — Optional Skill Forced Evaluation Hook
#
# This is an OPTIONAL hook for UserPromptSubmit that improves skill activation
# from ~20% to ~84% by forcing explicit evaluation before implementation.
#
# INSTALLATION:
#   1. Copy this file to ~/.claude/hooks/skill-forced-eval-hook.sh
#   2. Add to ~/.claude/settings.json (see skill-activation-guide.md)
#
# NOTE: This hook cannot be auto-registered via plugin.json because
# UserPromptSubmit is only available in user settings.json for security reasons.
#
# Reference: https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably

cat <<'EOF'
INSTRUCTION: SKILL ACTIVATION SEQUENCE

Step 1 - EVALUATE (in your response):
For each available skill, state: [skill-name] - YES/NO - [reason]

Step 2 - ACTIVATE (immediately after Step 1):
IF any skills are YES → Use Skill(skill-name) tool for EACH relevant skill NOW
IF all skills are NO → State "No skills needed" and proceed

Step 3 - IMPLEMENT:
Only after Step 2 is complete, proceed with implementation.

CRITICAL: You MUST call Skill() tool in Step 2. Do NOT skip to implementation.
The evaluation (Step 1) is WORTHLESS unless you ACTIVATE (Step 2) the skills.

Example of correct sequence:
- plugin-introspector: YES - need token analysis
- sub-kopring-engineer: NO - not a Kotlin task

[Then IMMEDIATELY use Skill() tool:]
> Skill(plugin-introspector)

[THEN and ONLY THEN start implementation]
EOF
