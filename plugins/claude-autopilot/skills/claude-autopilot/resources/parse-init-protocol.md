# Phase 0: Parse & Init Protocol

> claude-autopilot의 첫 단계. 사용자 입력을 파싱하고 세션을 초기화한다.

## Required Reads

- (없음 — 이 문서가 첫 로드 대상)

## Step 0: Pre-Flight Check

1. **의존성 확인**: `jq`, `date` 명령 사용 가능 여부
2. **이전 세션 감지**: `~/.claude/cache/claude-autopilot/session-state.json` 확인
   - `status == "in_progress"`: 이전 세션 중단됨
   - 중단된 세션의 deadline이 아직 미래: "이전 세션을 이어서 실행할까요?" 제안
   - 중단된 세션의 deadline이 과거: 아카이브 후 새 세션 시작
3. **캐시 디렉토리 확인**: `~/.claude/cache/claude-autopilot/` 생성 (없으면)

## Step 1: Directive Parsing

사용자 입력에서 구조화된 정보를 추출한다.

### 파싱 순서

```
1. --until / 까지 / +Nm / +Nh 패턴으로 deadline 추출
2. --priority 플래그 추출 (없으면 "balanced")
3. --scope 플래그 추출 (없으면 "project")
4. dry-run 키워드 감지
5. loop N 패턴 감지
6. 나머지 텍스트 = directive (핵심 지침)
```

### Deadline 파싱

`scripts/parse-deadline.sh`를 실행하여 epoch timestamp를 얻는다:

```bash
deadline_epoch=$(scripts/parse-deadline.sh "$deadline_input")
```

**파싱 실패 시**: 사용자에게 마감 시간 재입력 요청. 마감 시간 없이 실행 불가.

### 최소 시간 검증

```
남은 시간 = deadline_epoch - now
IF 남은 시간 < 5분:
  "최소 5분 이상의 시간이 필요합니다. 마감 시간을 재설정해주세요." 출력
  HALT
```

## Step 2: Gran-Maestro 감지

프로젝트에서 gran-maestro 연동 가능 여부를 확인한다.

```
1. {PROJECT_ROOT}/.gran-maestro/ 디렉토리 존재 확인
2. 존재 시:
   - mode.json 읽기 → active 상태 확인
   - directive에서 PLN-NNN / REQ-NNN 패턴 추출
   - config.resolved.json 읽기 → 기본 에이전트 확인
3. 결과를 session-state.json의 "gran_maestro" 필드에 기록
```

## Step 3: Session Initialize

`scripts/init-session.sh`를 실행하여 세션 상태 파일을 생성한다:

```bash
scripts/init-session.sh "$deadline_epoch" "$directive" "$priority" "$scope"
```

생성되는 파일: `~/.claude/cache/claude-autopilot/session-state.json`

## Step 4: Project Scan (Quick)

대상 프로젝트의 구조를 빠르게 파악한다:

```
1. 프로젝트 루트 탐지 (git rev-parse --show-toplevel)
2. 주요 언어/프레임워크 감지 (build.gradle.kts, package.json, pyproject.toml 등)
3. scope에 따른 대상 파일 범위 산정:
   - file: 지정된 파일만
   - module: 지정 모듈/디렉토리
   - project: 전체 프로젝트
4. 프로젝트 정보를 session-state.json에 기록
```

## Step 5: 초기화 완료 출력

```
[claude-autopilot] Session initialized
  Directive: {요약된 지침}
  Deadline:  {HH:MM} ({남은 시간}m remaining)
  Priority:  {priority}
  Scope:     {scope}
  Gran-Maestro: {detected|not found}
```

## 에러 처리

| 에러 | 대응 |
|------|------|
| deadline 파싱 실패 | 사용자에게 재입력 요청 |
| 남은 시간 < 5분 | HALT, 시간 재설정 요청 |
| 이전 세션 충돌 | 사용자에게 resume/new 선택 요청 |
| 캐시 디렉토리 생성 실패 | 임시 디렉토리(/tmp) 사용 후 경고 |
