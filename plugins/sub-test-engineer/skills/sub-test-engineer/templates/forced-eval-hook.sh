#!/bin/bash
# forced-eval-hook.sh — Forces Claude to evaluate and activate sub-test-engineer skill
# Installation: Copy to ~/.claude/hooks/ or project .claude/hooks/
# Add to settings.json UserPromptSubmit hook

# Detect if the prompt contains test-related keywords
# This script outputs instructions that get injected as a system reminder

cat <<'EOF'
INSTRUCTION: MANDATORY SKILL ACTIVATION CHECK

Check <available_skills> for sub-test-engineer relevance before proceeding.

Trigger keywords for sub-test-engineer:
- "test", "tests", "testing", "테스트"
- "coverage", "커버리지"
- "mutation", "뮤테이션"
- "property test", "contract test", "architecture test"
- "generate tests", "테스트 생성"
- "test debt", "테스트 부채"
- "untested", "미테스트"

IF any trigger keywords are present AND working with Java/Kotlin/TypeScript backend:
  1. State: "sub-test-engineer skill detected as relevant because: [reason]"
  2. Activate: Use Skill(skill: "sub-test-engineer", args: "[user request]") tool NOW
  3. Follow the skill's workflow (Analyze → Strategize → Generate → Validate)

IF no trigger keywords OR not a typed backend project:
  - Proceed directly with your response (no statement needed)

CRITICAL: The evaluation is WORTHLESS unless you ACTIVATE the skill via Skill() tool.
Do NOT attempt to generate tests manually without activating sub-test-engineer first.
EOF
