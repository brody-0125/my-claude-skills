# Claude Code Skills Repository

Claude Code 스킬(플러그인) 모음 레포지토리. 5개 플러그인(sub-kopring-engineer, sub-test-engineer, plugin-introspector, numerical, engineering-workflow)으로 구성되며, 런타임 빌드 시스템 없이 셸 스크립트와 SKILL.md 기반으로 동작한다.

## Validation commands

컨벤션 검증 — 빌드 없이 실행 가능한 셸 스크립트:

```bash
# sub-kopring-engineer: Kotlin/Java 코드 컨벤션 검증
plugins/sub-kopring-engineer/skills/sub-kopring-engineer/scripts/verify-conventions.sh [대상경로]

# numerical: 수치 연산 코드 검증
plugins/numerical/skills/numerical/scripts/verify-numeric.sh [대상경로]

# sub-test-engineer: 문서 일관성 검증
plugins/sub-test-engineer/skills/sub-test-engineer/scripts/verify-doc-consistency.sh [대상경로]

# engineering-workflow: 쿼리 도메인 분류 (DB/BE/IF/SE)
plugins/engineering-workflow/skills/engineering-workflow/scripts/classify-query.sh "쿼리 텍스트"

# 프로젝트 자동 감지 (언어, 프레임워크, 쿼리 라이브러리 등)
plugins/sub-kopring-engineer/skills/sub-kopring-engineer/scripts/discover-project.sh
plugins/numerical/skills/numerical/scripts/discover-project.sh
```

## Architecture

### 2-Layer 스킬 구조

모든 플러그인이 공유하는 핵심 패턴:
- **SKILL.md** — Claude Code가 읽는 진입점. 코어 프롬프트와 워크플로우 정의
- **resources/** — 단계별 on-demand 로딩. 토큰 효율을 위해 필요한 단계에서만 주입

### Phase-based 워크플로우

각 플러그인은 단계별 워크플로우를 따른다:
- sub-kopring-engineer: Brainstorm → Plan → Implement → Verify
- sub-test-engineer: Analyze → Strategize → Generate → Validate
- numerical: Analyze → Verify → Optimize
- plugin-introspector: 명령어 기반 (status, dashboard, analyze 등)
- engineering-workflow: Classify → Route → Execute → Resolve → Synthesize

### Hook 시스템

`plugin.json`의 hooks로 자동화 트리거 설정:
- **PreToolUse** — Edit/Write 전 보안 검사 (프로덕션 시크릿 파일 차단 등)
- **PostToolUse** — Edit/Write 후 자동 lint (ktlint, checkstyle 등)
- **Stop** — 세션 종료 시 테스트 Quality Gate

Hook 명령은 `$CLAUDE_TOOL_INPUT`을 jq로 파싱하여 대상 파일 경로를 추출한다.

### 셸 스크립트 원칙

- 외부 의존성 없음: bash + jq + git만 사용
- LLM 호출 없이 결정론적 검증 수행
- 패턴 캐시 저장 위치: `~/.claude/cache/`

## Plugin layout

표준 플러그인 디렉터리 구조 (sub-kopring-engineer 기준):

```
plugins/sub-kopring-engineer/
├── .claude-plugin/
│   └── plugin.json          # hooks 정의 (PreToolUse/PostToolUse/Stop)
└── skills/
    └── sub-kopring-engineer/
        ├── SKILL.md          # 진입점 — Claude Code가 읽는 코어 프롬프트
        ├── resources/        # 단계별 on-demand 프로토콜 문서
        ├── references/       # 정적 참조 자료
        ├── scripts/          # 검증/감지 셸 스크립트
        ├── templates/        # 코드 생성 템플릿
        └── ast-grep-rules/   # AST 기반 정적 분석 규칙 (선택적)
```

plugin-introspector는 추가로 `skills/` 하위에 meta-rules, analysis-patterns, cost-tracking 지식 스킬을 포함한다.

## Key conventions

- **문서 언어**: 한국어 (SKILL.md, resources, 커밋 메시지 제외)
- **SKILL.md가 진입점**: Claude Code는 SKILL.md를 먼저 읽고, resources/는 해당 단계 진입 시 로딩
- **Tiered Verification**: 변경 규모에 따라 LIGHT / STANDARD / THOROUGH 자동 선택
- **plugin-introspector hooks**: `INTROSPECTOR_SCRIPTS` 환경변수로 훅 스크립트 디렉터리 경로 오버라이드 가능
- **패턴 학습**: 프로젝트 코드 패턴을 자동 학습 → `~/.claude/cache/`에 저장 → 코드 생성에 반영

## Cross-skill protocols

Sister-skill 간 연동은 `docs/shared/03-invoke-protocol.md`에 정의된 프로토콜을 따른다.
