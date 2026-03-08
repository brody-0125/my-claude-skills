# Error Playbook — 에러 유형별 대응 절차

> autopilot 실행 중 발생 가능한 에러와 대응 방법.

## 에러 카테고리

### Category 1: 파일 접근 에러

| 에러 | 증상 | 대응 |
|------|------|------|
| File not found | Read/Edit 대상 파일 없음 | Glob으로 재탐색, 경로 오류 수정 |
| Permission denied | 파일 읽기/쓰기 권한 없음 | 작업 skip, 보고서에 기록 |
| Binary file | 텍스트가 아닌 파일 편집 시도 | 작업 skip |

### Category 2: 코드 에러

| 에러 | 증상 | 대응 |
|------|------|------|
| Syntax error | 수정 후 파일이 문법적으로 무효 | 즉시 수정 시도 (1회), 실패 시 롤백 |
| Import error | 없는 모듈/클래스 import | import 경로 수정 또는 누락된 import 추가 |
| Type error | 타입 불일치 | 타입 분석 후 수정, 2회 실패 시 blocked |
| Compile error | 빌드 실패 | 에러 메시지 분석 → 수정, 3회 실패 시 전체 변경 롤백 |

### Category 3: 테스트 에러

| 에러 | 증상 | 대응 |
|------|------|------|
| Test failure (신규) | 새로 작성한 테스트 실패 | 테스트 코드 수정 (2회까지) |
| Test failure (기존) | 기존 테스트가 깨짐 | 변경 원인 분석 → 수정, 실패 시 롤백 |
| Test timeout | 테스트 실행 시간 초과 | 타임아웃 설정 확인, 무한 루프 검사 |
| Test environment | 테스트 환경 문제 (DB, network) | 작업 skip, 환경 문제 보고 |

### Category 4: 시간 관리 에러

| 에러 | 증상 | 대응 |
|------|------|------|
| Deadline parse failure | 시간 형식 인식 불가 | 사용자에게 재입력 요청 |
| Clock skew | 시스템 시간 이상 | `date` 명령 확인, 경고 후 진행 |
| Negative remaining | 이미 마감 지남 | 즉시 Phase 3 → Phase 4 |

### Category 5: Gran-Maestro 연동 에러

| 에러 | 증상 | 대응 |
|------|------|------|
| PLN not found | 지정 PLN 디렉토리 없음 | 사용 가능한 PLN 목록 제시 |
| REQ not found | 지정 REQ 없음 | 사용 가능한 REQ 목록 제시 |
| spec.md missing | REQ에 spec 미작성 | mst:request 실행 제안 |
| mst skill unavailable | gran-maestro 플러그인 미설치 | 연동 비활성화, 독립 모드 전환 |
| config parse error | config.resolved.json 파싱 실패 | 기본값으로 진행, 경고 |

### Category 6: 시스템 에러

| 에러 | 증상 | 대응 |
|------|------|------|
| Disk full | 파일 쓰기 실패 | 즉시 중단, Phase 3 |
| Memory pressure | 느린 응답, OOM | 컨텍스트 압축 후 계속 |
| Git conflict | merge conflict 발생 | 작업 중단, 충돌 파일 보고 |

## 에러 에스컬레이션

```
Level 1 (Self-heal):
  → 자동 수정 시도 (1-2회)
  → 성공 시 계속

Level 2 (Skip & Continue):
  → 작업 blocked/skip 처리
  → 다음 작업으로 이동
  → 보고서에 기록

Level 3 (Emergency Stop):
  → 모든 작업 중단
  → Phase 3 (Wind-down) 즉시 진입
  → 긴급 보고서 출력
```

## 에러 기록 형식

session-state.json에 기록:

```json
{
  "errors": [
    {
      "timestamp": "2026-03-07T15:12:34Z",
      "task_id": 2,
      "category": "code",
      "type": "compile_error",
      "message": "Unresolved reference: OrderStatus",
      "resolution": "self_healed",
      "attempts": 1
    }
  ]
}
```
