# Safety Rules — 안전 가드레일 상세 규칙

> autopilot 실행 시 준수해야 할 안전 규칙.

## ⚠️ Mandatory Read Protocol (SKILL.md 참조)

**모든 Phase에서 반드시 준수해야 할 최우선 규칙**:
- Edit/Write 전 반드시 Read로 전체 파일 읽기
- Edit/Write 후 반드시 Read로 검증
- 이전에 읽은 파일 내용에 의존 금지 (항상 재읽기)
- 상세 규칙은 SKILL.md의 "Mandatory Read Protocol" 섹션 참조

이 규칙을 위반하면 파일 손상, 의도치 않은 변경, stale context 기반 오류가 발생한다.

## 파일 시스템 안전

### 편집 금지 패턴

다음 패턴의 파일은 편집하지 않는다 (PreToolUse hook에서도 차단):

```
application-prod*
secrets*
credentials*
private-key*
.env
.env.*
*.pem
*.key
id_rsa*
```

### Scope 제한

사용자가 지정한 scope 밖의 파일은 수정하지 않는다:

| Scope | 허용 범위 |
|-------|----------|
| `file` | 명시된 파일만 |
| `module` | 지정 디렉토리 하위 전체 |
| `project` | git 루트 하위 전체 (단, 위 금지 패턴 제외) |

### 파괴적 명령 금지

다음 명령은 사전 백업 없이 실행하지 않는다:

```
rm -rf (재귀 삭제)
git reset --hard
git checkout -- . (전체 파일 복원)
git clean -f
git push --force
DROP TABLE / TRUNCATE (SQL)
```

## 작업 범위 안전

### 범위 초과 감지

작업 실행 중 지침 범위를 벗어나는 변경이 필요한 경우:

```
1. 변경 필요성 기록
2. 현재 작업은 범위 내에서 가능한 만큼만 수행
3. 범위 초과 변경은 "다음 세션 권장" 목록에 추가
4. 사용자에게 알림: "scope 밖의 변경이 필요합니다: {파일/모듈}"
```

### 연쇄 에러 중단

```
error_history = []

ON error:
  error_history.append(error.signature)
  IF last 3 errors have same signature:
    작업을 "blocked"로 표시
    "동일 에러가 3회 반복되어 작업을 중단합니다" 출력
    다음 작업으로 이동
```

### 테스트 보호

```
기존 테스트가 깨지는 경우:
1. 변경 사항이 의도적인 동작 변경인지 확인
2. 의도적이면: 테스트 업데이트
3. 의도적이지 않으면: 변경 롤백 → 다른 접근법 시도
4. 2회 시도 후에도 실패: 작업 blocked
```

## Gran-Maestro 연동 안전

### REQ 실행 시 규칙

```
1. spec.md 없는 REQ는 실행 불가
2. 이미 completed된 REQ는 재실행 불가
3. --auto 플래그 필수 (사용자 승인 대신 autopilot이 승인)
4. plan.md는 읽기 전용 (수정 금지)
5. config.resolved.json의 설정 준수
```

### REQ 실패 복구

```
IF REQ 구현 실패:
  1. 변경된 파일을 안전한 상태로 복원
  2. REQ status를 "spec_ready"로 되돌림
  3. 실패 사유를 session-state.json에 기록
  4. 다음 REQ로 이동
```

## 긴급 중단 조건

다음 상황에서 즉시 모든 작업을 중단하고 Phase 3 (Wind-down)으로 전환:

| 조건 | 판단 기준 |
|------|----------|
| **대규모 테스트 실패** | 변경 전 대비 테스트 실패 수 5배 이상 증가 |
| **빌드 깨짐** | 프로젝트 빌드가 완전히 실패 |
| **디스크 공간 부족** | 가용 디스크 < 100MB |
| **권한 에러** | 반복적인 Permission denied |
| **사용자 중단 요청** | 사용자가 "중단", "stop", "cancel" 입력 |
