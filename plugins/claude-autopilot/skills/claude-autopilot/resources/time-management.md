# Time Management — 시간 예산 관리 알고리즘

> autopilot 실행 전반에 걸친 시간 관리 전략.

## 시간 예산 계산

### 기본 공식

```
total_available = deadline_epoch - current_epoch (초 단위)
total_minutes = total_available / 60

wind_down_reserve = max(3, total_minutes * 0.10)  # 최소 3분, 최대 총 시간의 10%
parse_overhead = 2  # Phase 0-1에 소요되는 시간
execution_available = total_minutes - wind_down_reserve - parse_overhead
```

### Priority별 배분

#### Balanced (기본)

```
task_count = len(ready_tasks)
base_allocation = execution_available / task_count

FOR each task in dependency_order:
  IF task.size == "S":  allocation = base_allocation * 0.5
  IF task.size == "M":  allocation = base_allocation * 1.0
  IF task.size == "L":  allocation = base_allocation * 1.5
  IF task.size == "XL": allocation = base_allocation * 2.5

  normalize: sum(allocations) == execution_available
```

#### High

```
sorted_tasks = tasks.sort_by(impact DESC)
top_30_pct = sorted_tasks[:ceil(len * 0.3)]
rest = sorted_tasks[ceil(len * 0.3):]

top_budget = execution_available * 0.60
rest_budget = execution_available * 0.40

FOR each task in top_30_pct:
  allocation = top_budget / len(top_30_pct) * size_multiplier
FOR each task in rest:
  allocation = rest_budget / len(rest) * size_multiplier
```

#### Quick

```
FOR each task in tasks.sort_by(size ASC):
  allocation = min(5, execution_available / remaining_task_count)
  IF allocation < 2:
    task.status = "skip"  # 최소 2분 필요
```

## 시간 체크포인트

### check-deadline.sh 출력 형식

```json
{
  "remaining_seconds": 1800,
  "remaining_minutes": 30,
  "total_minutes": 60,
  "elapsed_minutes": 30,
  "progress_pct": 50,
  "level": "NORMAL",
  "wind_down_at": 1741340100,
  "deadline_epoch": 1741340400
}
```

### Level 판정 로직

```
remaining_pct = remaining_minutes / total_minutes * 100

IF remaining_pct > 50:       level = "NORMAL"
ELIF remaining_pct > 30:     level = "AWARE"
ELIF remaining_pct > 15:     level = "CAUTION"
ELIF remaining_pct > 5:      level = "WIND_DOWN"
ELSE:                        level = "CRITICAL"
```

### Level별 행동 제약

| Level | 새 작업 시작 | 새 S 작업 | 새 M+ 작업 | Wind-down |
|-------|------------|-----------|-----------|-----------|
| NORMAL | ✅ | ✅ | ✅ | - |
| AWARE | ✅ | ✅ | ⚠️ (시간 확인) | - |
| CAUTION | ❌ | ⚠️ (급한 것만) | ❌ | 준비 |
| WIND_DOWN | ❌ | ❌ | ❌ | 진행 중 |
| CRITICAL | ❌ | ❌ | ❌ | 즉시 완료 |

## 시간 초과 작업 처리

### 작업 시작 전 검증

```
IF task.estimated_minutes > remaining_minutes * 0.7:
  IF task is decomposable:
    sub_tasks = decompose(task)
    replace task with sub_tasks in queue
  ELIF task.size in ["S", "M"]:
    proceed with warning
  ELSE:
    mark as "skip" with reason "insufficient_time"
```

### 작업 실행 중 초과 감지

```
task_elapsed = now - task.started_at
IF task_elapsed > task.allocated_minutes * 1.5:
  "작업이 예상보다 오래 걸리고 있습니다"
  IF remaining_minutes < wind_down_reserve:
    현재 안전 지점에서 중단 → Phase 3
  ELSE:
    allocated_minutes += min(5, remaining_budget * 0.2)  # 약간 연장
```

## 시간 추정 보정

### 학습 데이터 수집

매 작업 완료 시:
```json
{
  "size": "M",
  "estimated_minutes": 10,
  "actual_minutes": 8,
  "task_type": "refactor",
  "language": "kotlin"
}
```

### 보정 계수 계산

```
FOR each size in [S, M, L, XL]:
  recent_samples = last 5 sessions' tasks WHERE size == size
  IF len(recent_samples) >= 3:
    calibration[size] = mean(actual / estimated for each sample)
  ELSE:
    calibration[size] = 1.0  # 데이터 부족 시 보정 없음

적용:
  corrected_estimate = base_estimate * calibration[task.size]
```
