# Advanced Testing Guide

> Mutation Testing, Contract Testing, Performance Testing patterns for Hexagonal Architecture

---

## 1. Mutation Testing (PIT/Pitest)

Mutation testing measures test quality by injecting faults into code and checking if tests detect them.

### 1-1. Gradle Setup

```kotlin
// build.gradle.kts
plugins {
    id("info.solidsoft.pitest") version "1.15.0"
}

pitest {
    targetClasses.set(setOf("com.example.core.*", "com.example.application.*"))
    targetTests.set(setOf("com.example.*Test", "com.example.*Spec"))
    mutators.set(setOf("DEFAULTS"))  // or "STRONGER", "ALL"
    outputFormats.set(setOf("HTML", "XML"))
    timestampedReports.set(false)
    threads.set(4)
    mutationThreshold.set(80)  // Fail if mutation coverage < 80%
}
```

### 1-2. Layer-Specific Application

| Layer | Mutation Testing 적용 | 이유 |
|-------|---------------------|------|
| **core (Domain)** | ✅ 필수 | 비즈니스 로직 핵심. 높은 mutation coverage 요구 |
| **application (UseCase)** | ✅ 권장 | 조합 로직 검증. Port 호출 순서/조건 |
| **infrastructure** | ⚠️ 선택 | 외부 연동 코드. Testcontainers 기반 테스트에서 제한적 가치 |
| **api (Presentation)** | ❌ 불필요 | 단순 위임 코드. Integration test로 충분 |

### 1-3. 실행 및 결과 해석

```bash
./gradlew pitest

# 결과 확인: build/reports/pitest/index.html
```

**Mutation Score 해석**:
- **90%+**: 우수 — 테스트가 대부분의 변이를 감지
- **80~90%**: 양호 — Domain 레이어 목표 수준
- **70~80%**: 개선 필요 — 경계 조건, 예외 케이스 추가
- **<70%**: 테스트 품질 문제 — 테스트 케이스 보강 필요

### 1-4. Survived Mutants 대응

```kotlin
// 원본 코드
fun calculateDiscount(amount: Money, rate: Rate): Money {
    if (rate.value <= 0) return Money.ZERO  // Mutant: <= → <
    return amount * rate
}

// 테스트가 누락한 경계 케이스
@Test
fun `rate가 0일 때 할인 없음`() {
    val result = calculateDiscount(Money(1000), Rate(0.0))
    expectThat(result).isEqualTo(Money.ZERO)
}
```

---

## 2. Contract Testing (Spring Cloud Contract)

API 계약을 코드로 정의하고, Provider/Consumer 양쪽에서 검증한다.

### 2-1. Gradle Setup

```kotlin
// Provider 모듈 (api/)
plugins {
    id("org.springframework.cloud.contract") version "4.1.0"
}

dependencies {
    testImplementation("org.springframework.cloud:spring-cloud-starter-contract-verifier")
}

contracts {
    baseClassForTests.set("com.example.api.ContractTestBase")
    testMode.set(TestMode.MOCKMVC)
}
```

### 2-2. Contract DSL (Kotlin)

```kotlin
// src/test/resources/contracts/order/createOrder.kts
import org.springframework.cloud.contract.spec.ContractDsl.Companion.contract

contract {
    name = "should create order"
    description = "주문 생성 계약"

    request {
        method = POST
        url = "/api/orders"
        headers {
            contentType = APPLICATION_JSON
        }
        body = mapOf(
            "productId" to "PROD-001",
            "quantity" to 2
        )
    }

    response {
        status = CREATED
        headers {
            contentType = APPLICATION_JSON
        }
        body = mapOf(
            "orderId" to $(regex("[A-Z0-9-]+")),
            "status" to "PENDING"
        )
    }
}
```

### 2-3. Hexagonal Port 기반 계약

```kotlin
// Port 인터페이스 기반 Base Class
abstract class ContractTestBase {

    @MockkBean
    lateinit var createOrderUseCase: CreateOrderUseCase

    @BeforeEach
    fun setup() {
        every { createOrderUseCase.execute(any()) } returns
            OrderResult(orderId = "ORD-123", status = OrderStatus.PENDING)
    }
}
```

**원칙**: Contract Test는 UseCase Port를 Mock하고, Controller의 요청/응답 변환만 검증한다.

### 2-4. Consumer Stub 생성

```bash
./gradlew generateClientStubs

# Consumer 프로젝트에서 Stub 사용
testImplementation("com.example:api:+:stubs")
```

---

## 3. Performance Testing

### 3-1. JMH 마이크로벤치마크 (Domain Layer)

Domain 레이어의 순수 연산 성능을 측정할 때 사용한다.

```kotlin
// build.gradle.kts
plugins {
    id("me.champeau.jmh") version "0.7.2"
}

jmh {
    warmupIterations.set(2)
    iterations.set(5)
    fork.set(1)
    resultFormat.set("JSON")
}
```

```kotlin
// src/jmh/kotlin/com/example/core/MoneyBenchmark.kt
@State(Scope.Benchmark)
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
open class MoneyBenchmark {

    private lateinit var money1: Money
    private lateinit var money2: Money

    @Setup
    fun setup() {
        money1 = Money(BigDecimal("1234567.89"))
        money2 = Money(BigDecimal("9876543.21"))
    }

    @Benchmark
    fun addMoney(): Money = money1 + money2

    @Benchmark
    fun multiplyByRate(): Money = money1 * Rate(0.15)
}
```

```bash
./gradlew jmh

# 결과: build/results/jmh/results.json
```

### 3-2. 적용 기준

| 대상 | JMH 적용 여부 | 이유 |
|------|-------------|------|
| Value Object 연산 | ✅ 권장 | Money, Rate 등 빈번한 연산 |
| Domain Service 순수 로직 | ✅ 권장 | 복잡한 계산 알고리즘 |
| UseCase | ❌ 불필요 | Port 호출 포함. 통합 성능은 별도 측정 |
| Repository/Adapter | ❌ 불필요 | 외부 의존성. JMH 부적합 |

### 3-3. 결과 해석 가이드

```
Benchmark                    Mode  Cnt    Score    Error   Units
MoneyBenchmark.addMoney     thrpt    5  125.432 ± 3.456  ops/us
MoneyBenchmark.multiplyByRate thrpt  5   98.765 ± 2.123  ops/us
```

- **ops/us** (operations per microsecond): 높을수록 좋음
- **Error**: 표준 편차. Score 대비 10% 이하가 안정적
- **Cnt**: 반복 횟수 (iterations)

---

## 4. 테스트 전략 요약

| 테스트 유형 | 목적 | 대상 레이어 | 도구 |
|------------|------|------------|------|
| **Unit Test** | 개별 클래스 동작 | core, application | JUnit5 + MockK |
| **Integration Test** | 레이어 간 연동 | infrastructure, api | Testcontainers |
| **Mutation Test** | 테스트 품질 | core, application | PIT/Pitest |
| **Contract Test** | API 계약 | api (Provider) | Spring Cloud Contract |
| **Performance Test** | 연산 성능 | core (Value Objects) | JMH |

---

## 참고

- [PIT Mutation Testing](https://pitest.org/)
- [Spring Cloud Contract](https://spring.io/projects/spring-cloud-contract)
- [JMH (Java Microbenchmark Harness)](https://github.com/openjdk/jmh)
