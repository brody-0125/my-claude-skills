---
name: numerical
description: >-
  Numerical computing verification and optimization agent for Python/Dart.
  Provides expert analysis of ndarray/tensor operations, floating-point correctness,
  broadcasting validation, SIMD/GPU optimization, and test case verification
  through Analyze → Verify → Optimize phases.
  Activated by keywords: "numeric", "tensor", "ndarray", "broadcasting", "precision",
  "floating-point", "SIMD", "GPU", "numpy", "scipy", "dart_tensor", "linear algebra",
  "FFT", "verify test", "optimize computation".
version: 1.0.0
argument-hint: "[task description | analyze | verify | optimize | loop N | dry-run]"
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Task
---

# Numerical — Numerical Computing Verification & Optimization Agent

> An agent that verifies correctness and optimizes performance of numerical computing code through Analyze → Verify → Optimize workflow

## Role

A workflow agent specializing in **numerical computing** for Python and Dart projects.
It automatically detects the project language (Python/Dart/Mixed), numeric libraries (NumPy, SciPy, CuPy, dart_tensor, etc.), and provides **expert-level verification and optimization** of array/tensor operations, floating-point arithmetic, broadcasting, memory layout, SIMD utilization, and GPU processing.

### Core Principles

1. Lazy-load context documents per Phase to ensure verification thoroughness
2. Sequential execution of Analyze → Verify → Optimize
3. Repeat Verify loop the number of times specified by the user (Ralph-style)
4. Automatically adjust verification level based on computational complexity (Tiered Verification)
5. IEEE 754 compliance as the baseline for all floating-point analysis

### Quick Start (Zero-Config)

Phase 0 자동으로 모든 설정을 완료하므로 사용자 개입이 필요 없다:

```
1. Project Discovery    — pyproject.toml / pubspec.yaml 분석 → 언어, 라이브러리, GPU 지원 자동 감지
2. Numeric Profile      — dtype 사용 패턴, 배열 차원, 연산 유형 자동 프로파일링
3. Tool Detection       — pytest/ruff/mypy/dart analyze 등 검증 도구 자동 감지
4. Hooks Installation   — lint-on-edit, secret-guard, test-quality-gate 자동 설치
```

첫 실행 시 추가 프롬프트 없이 위 4단계가 순차적으로 실행된다.
감지된 설정을 변경하려면 해당 파일을 직접 편집하면 된다:
- 정적 분석 도구: `.numerical/analysis-tools.txt` (줄 단위, 삭제 시 재감지)
- Hooks: `.claude/settings.json`의 `hooks` 섹션 (삭제 시 재설치)

---

## Phase Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         numerical                         │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────┐
                    │      Phase 0: Discovery   │
                    │  • 언어/라이브러리/GPU 감지   │
                    │  • 수치 프로파일 캐시 저장    │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │      Phase 1: Analyze     │
                    │  • 수치 연산 패턴 분석       │
                    │  • dtype/shape 추적         │
                    │  • 정밀도 위험 감지          │
                    └────────────┬─────────────┘
                                 │
              ┌──── dry-run? ────┴──────────────────┐
              │                                      │
         ┌────▼────┐                    ┌───────────▼───────────┐
         │  HALT   │                    │   Phase 2: Verify      │
         │ (리포트만)│                    │  • 부동소수점 정합성 검증  │
         └─────────┘                    │  • 브로드캐스팅 규칙 검증  │
                                        │  • 테스트 케이스 검증      │
                                        │  • 에지 케이스 분석        │
                                        └───────────┬───────────┘
                                                    │
                    ┌───────────────────────────────▼───────────────────────────────┐
                    │                    Phase 3: Optimize                          │
                    │  ┌─────────────────────────────────────────────────────────┐  │
                    │  │  • SIMD 정렬/벡터화 최적화 제안                            │  │
                    │  │  • GPU 메모리 관리 최적화                                  │  │
                    │  │  • 메모리 레이아웃 (C/F-contiguous) 최적화                  │  │
                    │  │  • 알고리즘 수치 안정성 개선                                │  │
                    │  └─────────────────────────┬───────────────────────────────┘  │
                    │                            │                                   │
                    │           ┌────────────────▼────────────────┐                  │
                    │           │         종료 조건 확인           │                  │
                    │           │  • 위반 0개?                    │                  │
                    │           │  • 정밀도 목표 달성?             │                  │
                    │           │  • 동일 이슈 3회 반복?           │                  │
                    │           │  • max loop 도달?               │                  │
                    │           └────────────────┬────────────────┘                  │
                    │                            │                                   │
                    │         ┌─── EXIT ─────────┴─────── CONTINUE ───┐              │
                    │         │                                        │              │
                    │         │                              Loop N++ (재검증)        │
                    │         │                                        │              │
                    └─────────┼────────────────────────────────────────┘              │
                              │                                                       │
                              ▼                                                       │
                    ┌──────────────────────────┐                                     │
                    │        Complete          │◄────────────────────────────────────┘
                    │  • 분석 리포트 출력        │
                    │  • PROGRESS.md 기록       │
                    └──────────────────────────┘
```

---

## Phase Transition Conditions

| Phase | Entry Condition | Exit Condition | Skip Condition |
|-------|----------------|----------------|----------------|
| **0 Discovery** | Always first | Numeric profile loaded and cached | Never |
| **1 Analyze** | After Phase 0 | Numeric operations cataloged, risks identified | Never |
| **2 Verify** | After Phase 1 | All correctness checks passed OR violations reported | `dry-run` mode active |
| **3 Optimize** | After Phase 2 | Optimization suggestions delivered | `verify-only` mode |

---

## Execution Modes

| Mode | Input Example | Behavior |
|------|---------------|----------|
| **All-in-one** (default) | `numpy broadcasting 검증` | Analyze → Verify → Optimize |
| **All-in-one + loop** | `tensor 연산 검증. loop 3` | Analyze → Verify×3 → Optimize |
| **Step-by-step** | `analyze: matrix_ops.py` | Execute only a specific phase |
| **Verify only** | `verify loop 2` | Verify×2 on current code |
| **Dry-run** | `precision 분석. dry-run` | Analyze only, no code changes |
| **Skip optimize** | `verify-only loop 2` | Analyze → Verify×2 (no Optimize) |

Step-by-step commands: `analyze`, `verify`, `optimize`

### Domain-Specific Keywords

도메인 특화 키워드로 워크플로우 동작을 세밀하게 제어할 수 있다.

| 키워드 | 효과 | 적용 Phase |
|--------|------|-----------|
| `precision-focus` | 부동소수점 정밀도 심층 분석 — ULP 비교, 오차 전파 추적 | Analyze, Verify |
| `broadcast-check` | 브로드캐스팅 규칙 위반 집중 검증 | Verify |
| `gpu-optimize` | GPU 메모리 관리, 커널 최적화 집중 | Optimize |
| `simd-focus` | SIMD 정렬, 벡터화 가능성 집중 분석 | Analyze, Optimize |
| `test-verify` | 테스트 케이스 입력값/기댓값 정합성 검증 집중 | Verify |
| `stability` | 수치 안정성 분석 — 조건수, catastrophic cancellation | Analyze, Verify |
| `memory-layout` | 메모리 레이아웃 (C/Fortran order) 일관성 검증 | Analyze, Optimize |

**사용 예시:**
```
numpy 행렬 연산 검증. precision-focus loop 3
dart_tensor 전처리 파이프라인 분석. broadcast-check simd-focus
GPU 연산 최적화. gpu-optimize memory-layout
테스트 기댓값 검증. test-verify loop 2
```

---

## Phase-specific Detailed Protocols

Detailed execution procedures for each Phase are defined in **resources/**.
**When entering a Phase, documents already read in the previous Phase are not reloaded.**
However, they are reloaded for step-by-step execution (individual Phase invocation) or when context compression occurs.
**Within Verify loops (loop 2+), protocol documents and references already loaded in loop 1 are not reloaded.**

**Context compression recovery:**
1. At start of each Phase/loop, check for `## Numeric Profile` header in current context
2. If FOUND → proceed normally (no reload needed)
3. If NOT FOUND:
   - **Loop 1 OR step-by-step mode** → Re-read profile + all Required Reads for current Phase
   - **Loop 2+** → Re-read profile + verify-snapshot.json only

### Phase 0: Project Discovery (automatic)

> Details: [resources/project-discovery-protocol.md](./resources/project-discovery-protocol.md)

Automatically detects the project's build configuration, language (Python/Dart/Mixed), numeric libraries, and GPU capabilities.
If `.numerical/analysis-tools.txt` does not exist, it detects available analysis tools and requests selection.
Falls back to built-in reference conventions if discovery fails.

### Phase 1: Analyze

> Details: [resources/analyze-protocol.md](./resources/analyze-protocol.md)

Inspects numerical operations in the codebase:
- **dtype tracking**: Identify data types used across operations, detect implicit promotions
- **Shape analysis**: Trace array/tensor shapes through computation graphs
- **Precision risk detection**: Identify catastrophic cancellation, absorption, overflow/underflow risks
- **Broadcasting pattern cataloging**: Map all broadcasting operations and validate intent
- **Memory layout analysis**: Track C-contiguous vs Fortran-contiguous access patterns
- **Special value handling**: Check for NaN/Inf propagation paths

### Phase 2: Verify

> Details: [resources/verify-protocol.md](./resources/verify-protocol.md)
> Verification levels: [resources/verification-tiers.md](./resources/verification-tiers.md)
> Error handling: [resources/error-playbook.md](./resources/error-playbook.md)

**Scripts**: `scripts/verify-numeric.sh [target path] [summary|detailed]`
Loop 2+: incremental verification with `--changed-only`.

### Phase 3: Optimize

> Details: [resources/optimize-protocol.md](./resources/optimize-protocol.md)

Provides optimization suggestions based on analysis and verification results:
- SIMD alignment and vectorization opportunities
- GPU memory management improvements
- Memory layout optimization for cache performance
- Algorithmic numerical stability improvements
- Parallelization opportunities

### Loop Control

| Input | Behavior |
|-------|----------|
| `loop N` | Verify×N (with fixes) |
| `verify loop N` | Verify×N on current code |
| `loop 0` | Skip Verify |
| (not specified) | Verify×1 (default) |

**Loop termination decision flow (evaluated AFTER auto-fix attempt, in order):**

```
Loop N termination check (after fix):
1. violations == 0 (after fix)              → EXIT (success)
2. precision target met (all within tol)     → EXIT (success)
3. Same violation appears 3x consecutive    → Spawn root-cause analysis sub-agent, halt and await user decision
4. N >= max_loops AND violations > 0        → EXIT (report remaining violations)
Otherwise                                   → next iteration (N += 1)
```

---

## Context Documents (Lazy Load)

**Consistency assertion:** Once `numeric-lib` is detected in Phase 0 (e.g., numpy, scipy, cupy, dart_tensor, or none), the same value MUST be used consistently across all subsequent phases. Do not re-detect.

**Base Set** (loaded in Phases 1, 2, 3 — referenced by all protocol Required Reads):
- numeric project profile cache (unconditional, every phase)
- floating-point-guide.md (always)
- language-specific conventions (by detected language)

| Document | Phases | Load Condition | Load Frequency |
|----------|--------|----------------|----------------|
| **numeric profile** (auto-discovered) | 0, 1, 2, 3 | Every phase entry (unconditional) | Every Phase |
| [floating-point-guide.md](./references/floating-point-guide.md) | 1, 2, 3 | Always | Load Once |
| [broadcasting-rules.md](./references/broadcasting-rules.md) | 1, 2 | IF ndarray/tensor ops detected | Load Once |
| [numpy-conventions.md](./references/numpy-conventions.md) | 1, 2, 3 | IF language=python | Load Once |
| [dart-tensor-conventions.md](./references/dart-tensor-conventions.md) | 1, 2, 3 | IF language=dart | Load Once |
| [simd-alignment-guide.md](./references/simd-alignment-guide.md) | 1, 3 | IF SIMD ops detected OR `simd-focus` keyword | Load Once |
| [gpu-memory-guide.md](./references/gpu-memory-guide.md) | 1, 3 | IF GPU libs detected OR `gpu-optimize` keyword | Load Once |

## Resources (On-demand)

| Document | Purpose |
|----------|---------|
| [project-discovery-protocol.md](./resources/project-discovery-protocol.md) | Phase 0 numeric project discovery procedure |
| [analyze-protocol.md](./resources/analyze-protocol.md) | Phase 1 numerical analysis procedure |
| [verify-protocol.md](./resources/verify-protocol.md) | Phase 2 verification procedure |
| [optimize-protocol.md](./resources/optimize-protocol.md) | Phase 3 optimization procedure |
| [verification-tiers.md](./resources/verification-tiers.md) | Verification levels by complexity |
| [error-playbook.md](./resources/error-playbook.md) | Numerical error type-specific resolution protocols |

## Scripts

| 스크립트 | 용도 | 사용법 |
|---------|------|--------|
| `discover-project.sh` | 프로젝트 프로파일 자동 감지 | `./discover-project.sh [--refresh] [--project path]` |
| `verify-numeric.sh` | 수치 연산 검증 | `./verify-numeric.sh [path] [summary\|detailed]` |
| `setup-hooks.sh` | Hooks 자동 설치 | `./setup-hooks.sh [--auto]` |
| `_common.sh` | 공유 유틸리티 (다른 스크립트에서 source) | 직접 실행 불가 — 내부 라이브러리 |

**스크립트 실행 요구사항:**
- 필수 CLI: `bash 4.0+`, `grep`, `find`, `wc`, `sed`, `awk`
- 선택적 CLI: `jq` (JSON 파싱), `python3` (AST 분석), `dart` (Dart 분석)
- 환경: Unix-like (Linux, macOS) — Windows는 WSL/Git Bash 필요

## Hooks Configuration

When Hooks are applied to the project, automatic verification runs on `.py`/`.dart` file modifications.
> Configuration: [templates/hooks-config.json](./templates/hooks-config.json)
> Installation script: `scripts/setup-hooks.sh`

**Note:** Hooks are defined in two places: `plugin.json` (plugin-level) and `templates/hooks-config.json` (project-level, installed via setup-hooks.sh). Use only one: plugin.json is active when the plugin is installed; hooks-config.json is for standalone use without the plugin. Do not enable both simultaneously to avoid duplicate hook execution.

## Context Health Protocol

롱 세션에서 컨텍스트 윈도우 사용량을 모니터링하고 선제적으로 대응한다.

### 임계값 대응

| 사용량 | 레벨 | 대응 |
|--------|------|------|
| **70%** | WARNING | "컨텍스트 70% 도달. 불필요한 파일 읽기 최소화하고 핵심 분석에 집중" |
| **80%** | RECOMMEND | "/compact 실행 후 프로파일 재로드 권장. 현재 Loop 완료 후 압축 진행" |
| **85%** | CRITICAL | "즉시 /compact 실행 필수. 압축 후 프로파일 + 현재 Phase 문서 재로드하여 계속" |

## Status Display Protocol

각 Phase/Loop 진입 시 현재 상태를 간결하게 표시한다.

### 표시 형식

```
[numerical] Phase: {phase} | Loop: {n}/{max} | Tier: {tier} | Context: {pct}% {bar}
```

**예시:**
```
[numerical] Phase: Verify | Loop: 2/3 | Tier: STANDARD | Context: 55% ▓▓▓▓▓░░░░░
[numerical] Phase: Analyze | Tier: N/A | Context: 23% ▓▓░░░░░░░░
[numerical] Phase: Optimize | Tier: THOROUGH | Context: 72% ▓▓▓▓▓▓▓░░░
```

## Session Wisdom Protocol

세션 간 수치 분석 결정과 학습 내용을 축적한다.

### 저장 위치

```
.numerical/PROGRESS.md
```

> 템플릿: [templates/progress-template.md](./templates/progress-template.md)

### 기록 시점

| 시점 | 기록 내용 | 자동/수동 |
|------|----------|----------|
| **Analyze 완료** | 발견된 수치 패턴, 정밀도 위험 요소 | 자동 |
| **에러 해결** | 이슈 + 원인 + 해결 방법 | 자동 |
| **Verify 완료** | 검증 결과, tolerance 설정 이력 | 자동 |
| **Optimize 완료** | 적용된 최적화, 성능 측정 결과 | 자동 |
| **세션 종료** | 다음 세션 TODO | 자동 |

### 보존 규칙

- **최근 5개 세션** 유지 (이전 세션은 요약으로 압축)
- **중요 결정**은 영구 보존 (tolerance 기준 변경, GPU 커널 설정)
- **반복 이슈**는 error-playbook.md로 승격 제안
