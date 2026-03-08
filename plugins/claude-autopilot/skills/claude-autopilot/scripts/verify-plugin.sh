#!/usr/bin/env bash
# verify-plugin.sh — claude-autopilot 플러그인 무결성 검증 하네스
# Usage: ./verify-plugin.sh [--verbose]
# 종료 코드: 0=모두 통과, 1=실패 있음

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERBOSE="${1:-}"

passed=0
failed=0
warnings=0

pass() { passed=$((passed + 1)); [ "$VERBOSE" = "--verbose" ] && echo "  ✓ $1"; }
fail() { failed=$((failed + 1)); echo "  ✗ $1"; }
warn() { warnings=$((warnings + 1)); echo "  ⚠ $1"; }

echo "=== claude-autopilot Plugin Verification ==="
echo ""

# ── 1. 구조 검증 ────────────────────────────────────────────────────────
echo "[1/6] Structure check"

[ -f "${PLUGIN_ROOT}/SKILL.md" ] && pass "SKILL.md exists" || fail "SKILL.md missing"
[ -d "${PLUGIN_ROOT}/resources" ] && pass "resources/ exists" || fail "resources/ missing"
[ -d "${PLUGIN_ROOT}/scripts" ] && pass "scripts/ exists" || fail "scripts/ missing"
[ -d "${PLUGIN_ROOT}/templates" ] && pass "templates/ exists" || fail "templates/ missing"

# plugin.json
plugin_json="$(cd "${PLUGIN_ROOT}/../.." && pwd)/.claude-plugin/plugin.json"
[ -f "$plugin_json" ] && pass "plugin.json exists" || fail "plugin.json missing"

# ── 2. 리소스 파일 검증 ──────────────────────────────────────────────────
echo "[2/6] Resource files check"

required_resources=(
  "parse-init-protocol.md"
  "decompose-protocol.md"
  "execute-protocol.md"
  "winddown-protocol.md"
  "report-protocol.md"
  "time-management.md"
  "safety-rules.md"
  "error-playbook.md"
)

for res in "${required_resources[@]}"; do
  if [ -f "${PLUGIN_ROOT}/resources/${res}" ]; then
    # 빈 파일 검사
    if [ -s "${PLUGIN_ROOT}/resources/${res}" ]; then
      pass "${res}"
    else
      fail "${res} exists but is empty"
    fi
  else
    fail "${res} missing"
  fi
done

# ── 3. 스크립트 검증 ────────────────────────────────────────────────────
echo "[3/6] Scripts check"

required_scripts=(
  "_common.sh"
  "parse-deadline.sh"
  "init-session.sh"
  "check-deadline.sh"
  "update-task-status.sh"
  "generate-report.sh"
  "check-phase-gate.sh"
  "verify-plugin.sh"
)

for script in "${required_scripts[@]}"; do
  script_path="${PLUGIN_ROOT}/scripts/${script}"
  if [ -f "$script_path" ]; then
    pass "${script} exists"
    # 실행 권한 확인
    if [ -x "$script_path" ] || [ "$script" = "_common.sh" ]; then
      pass "${script} executable"
    else
      warn "${script} not executable (chmod +x needed)"
    fi
    # bash -n 문법 검사
    if bash -n "$script_path" 2>/dev/null; then
      pass "${script} syntax valid"
    else
      fail "${script} has syntax errors"
    fi
  else
    fail "${script} missing"
  fi
done

# ── 4. SKILL.md 필수 섹션 검증 ──────────────────────────────────────────
echo "[4/6] SKILL.md required sections check"

skill_md="${PLUGIN_ROOT}/SKILL.md"
if [ -f "$skill_md" ]; then
  required_sections=(
    "Mandatory Read Protocol"
    "Directive Drift Guard"
    "Git Checkpoint Protocol"
    "Phase Transition Gate"
    "Context Documents"
    "Time Management"
    "Safety"
  )

  for section in "${required_sections[@]}"; do
    if grep -qi "$section" "$skill_md" 2>/dev/null; then
      pass "Section: ${section}"
    else
      fail "Missing section: ${section}"
    fi
  done
fi

# ── 5. plugin.json hooks 검증 ───────────────────────────────────────────
echo "[5/6] Hooks validation"

if [ -f "$plugin_json" ]; then
  # JSON 유효성
  if jq empty "$plugin_json" 2>/dev/null; then
    pass "plugin.json valid JSON"
  else
    fail "plugin.json invalid JSON"
  fi

  # 필수 hook 존재 확인
  pre_count=$(jq '.hooks.PreToolUse | length' "$plugin_json" 2>/dev/null || echo "0")
  post_count=$(jq '.hooks.PostToolUse | length' "$plugin_json" 2>/dev/null || echo "0")
  stop_count=$(jq '.hooks.Stop | length' "$plugin_json" 2>/dev/null || echo "0")

  [ "$pre_count" -gt 0 ] && pass "PreToolUse hooks: ${pre_count}" || fail "No PreToolUse hooks"
  [ "$post_count" -gt 0 ] && pass "PostToolUse hooks: ${post_count}" || fail "No PostToolUse hooks"
  [ "$stop_count" -gt 0 ] && pass "Stop hooks: ${stop_count}" || fail "No Stop hooks"

  # secret guard hook 존재
  if jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write") | .hooks[] | .command' "$plugin_json" 2>/dev/null | grep -q "secrets\|credentials\|\.env"; then
    pass "Secret guard hook present"
  else
    fail "Secret guard hook missing"
  fi

  # scope enforcement hook 존재
  if jq -e '.hooks.PreToolUse[]' "$plugin_json" 2>/dev/null | grep -q "project_root\|scope"; then
    pass "Scope enforcement hook present"
  else
    warn "Scope enforcement hook missing"
  fi
fi

# ── 6. 스크립트 기능 테스트 (jq 의존성) ─────────────────────────────────
echo "[6/6] Functional tests"

if command -v jq &>/dev/null; then
  pass "jq available"

  # parse-deadline.sh 테스트
  deadline_script="${PLUGIN_ROOT}/scripts/parse-deadline.sh"
  if [ -f "$deadline_script" ] && [ -x "$deadline_script" ]; then
    result=$("$deadline_script" "+30m" 2>/dev/null || echo "ERROR")
    if [ "$result" != "ERROR" ] && [ -n "$result" ]; then
      # 결과가 숫자(epoch)인지 확인
      if [[ "$result" =~ ^[0-9]+$ ]]; then
        pass "parse-deadline.sh: +30m → ${result}"
      else
        fail "parse-deadline.sh: unexpected output: ${result}"
      fi
    else
      fail "parse-deadline.sh: failed to parse +30m"
    fi
  fi

  # _common.sh progress_bar 테스트
  source "${PLUGIN_ROOT}/scripts/_common.sh" 2>/dev/null || true
  if type progress_bar &>/dev/null; then
    # pct=0 edge case
    bar_zero=$(progress_bar 0 10)
    if [ ${#bar_zero} -gt 0 ]; then
      pass "progress_bar(0) produces output"
    else
      warn "progress_bar(0) empty output"
    fi

    # pct=100
    bar_full=$(progress_bar 100 10)
    if [ ${#bar_full} -gt 0 ]; then
      pass "progress_bar(100) produces output"
    else
      fail "progress_bar(100) no output"
    fi
  fi
else
  fail "jq not installed"
fi

# ── 결과 요약 ────────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "  Passed:   ${passed}"
echo "  Failed:   ${failed}"
echo "  Warnings: ${warnings}"

if [ "$failed" -gt 0 ]; then
  echo ""
  echo "VERIFICATION FAILED (${failed} failures)"
  exit 1
else
  echo ""
  echo "VERIFICATION PASSED"
  exit 0
fi
