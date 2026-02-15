# Resilience Configuration Reference (R-1, R-2, R-3)

> Static reference for Bulkhead, Circuit Breaker, Retry/Timeout configuration.

## Table of Contents

| Section | Line |
|---------|------|
| 1. Dependency Isolation Map | ~23 |
| 2. Bulkhead YAML Configuration | ~43 |
| 3. CB Integration Method 1: Spring Cloud OpenFeign + Resilience4j | ~114 |
| 4. CB Integration Method 2: Resilience4jFeign (Programmatic) | ~206 |
| 5. Per-Dependency CB Configuration Table | ~246 |
| 6. Exception Classification YAML | ~264 |
| 7. CB State Transition Diagram | ~306 |
| 8. Resilience4j Decorator Chain | ~343 |
| 9. Per-Dependency Timeout Budget Table | ~390 |
| 10. Retry Policy YAML | ~411 |
| 11. Payment idempotencyKey Code | ~475 |
| 12. Fallback Strategy Table | ~527 |
| 13. Fallback Implementation Patterns | ~540 |

---

## 1. Dependency Isolation Map

| Dependency | Module | Criticality | Bulkhead Type | Pool Size | Queue Cap | CB failureRate | Retry maxAttempts | Total Timeout (ms) |
|-----------|--------|------------|---------------|-----------|-----------|---------------|-------------------|---------------------|
| PG Payment | external-pg | CRITICAL | Thread Pool | 25 | 10 | 50% | 3 | 6000 |
| Easy Pay | external-easy-pay | CRITICAL | Thread Pool | 20 | 10 | 50% | 3 | 6000 |
| Bank | external-bank | CRITICAL | Thread Pool | 15 | 5 | 50% | 3 | 10000 |
| Tax Invoice | external-tax-invoice | HIGH | Thread Pool | 10 | 5 | 60% | 3 | 6000 |
| Key Mgmt | external-key-mgmt | HIGH | Semaphore | 15 | - | 40% | 3 | 2500 |
| Auth | external-auth | HIGH | Thread Pool | 15 | 5 | 50% | 3 | 3500 |
| Digital Sign | external-digital-sign | HIGH | Thread Pool | 10 | 5 | 50% | 3 | 6000 |
| Messaging | external-messaging | MEDIUM | Thread Pool | 10 | 10 | 60% | 3 | 6000 |
| File Storage | external-file-storage | MEDIUM | Thread Pool | 10 | 10 | 60% | 3 | 11000 |
| Team Messenger | external-team-messenger | LOW | Thread Pool | 5 | 5 | 70% | 2 | 3500 |
| SQS | external-sqs | MEDIUM | Semaphore | 20 | - | 50% | 3 | 6000 |
| MySQL | persistence-mysql | CRITICAL | HikariCP | 30 | - | - | - | 5000 |
| Redis | persistence-redis | HIGH | Lettuce | 20 | - | - | - | 2000 |

---

## 2. Bulkhead YAML Configuration

### Thread Pool Bulkhead (for blocking Feign calls)

```yaml
resilience4j:
  thread-pool-bulkhead:
    configs:
      default:
        maxThreadPoolSize: 10
        coreThreadPoolSize: 5
        queueCapacity: 5
        keepAliveDuration: 100ms
        writableStackTraceEnabled: true
    instances:
      pgPayment:        # CRITICAL: largest pool
        baseConfig: default
        maxThreadPoolSize: 25
        coreThreadPoolSize: 20
        queueCapacity: 10
      easyPay:
        baseConfig: default
        maxThreadPoolSize: 20
        coreThreadPoolSize: 15
        queueCapacity: 10
      bank:
        baseConfig: default
        maxThreadPoolSize: 15
        coreThreadPoolSize: 10
        queueCapacity: 5
      # HIGH/MEDIUM instances: taxInvoice(10/7/5), auth(15/10/5),
      # digitalSign(10/7/5), messaging(10/7/10), fileStorage(10/7/10)
      teamMessenger:    # LOW: smallest pool
        baseConfig: default
        maxThreadPoolSize: 5
        coreThreadPoolSize: 3
        queueCapacity: 5
```

### Semaphore Bulkhead (for non-blocking or already-async calls)

```yaml
resilience4j:
  bulkhead:
    configs:
      default:
        maxConcurrentCalls: 10
        maxWaitDuration: 500ms
    instances:
      keyMgmt:
        baseConfig: default
        maxConcurrentCalls: 15
        maxWaitDuration: 300ms
      sqs:
        baseConfig: default
        maxConcurrentCalls: 20
        maxWaitDuration: 500ms
```

### Sizing Formulas

```
Pool Size = ceil(peak_rps * avg_latency_sec * 1.5)
Queue Capacity = ceil(pool_size * 0.5)   # CRITICAL
Queue Capacity = pool_size               # MEDIUM / LOW
Total Thread Budget = sum(all pool sizes) < container_thread_limit - app_threads
```

---

## 3. CB Integration Method 1: Spring Cloud OpenFeign + Resilience4j

### application.yml (full configuration)

```yaml
spring:
  cloud:
    openfeign:
      circuitbreaker:
        enabled: true
        alphanumeric-ids:
          enabled: true
      client:
        config:
          default:
            connectTimeout: 1000
            readTimeout: 5000
            loggerLevel: BASIC

resilience4j:
  circuitbreaker:
    configs:
      default:
        registerHealthIndicator: true
        slidingWindowType: COUNT_BASED
        slidingWindowSize: 50
        minimumNumberOfCalls: 10
        failureRateThreshold: 50
        slowCallRateThreshold: 80
        slowCallDurationThreshold: 5000ms
        waitDurationInOpenState: 30s
        permittedNumberOfCallsInHalfOpenState: 5
        automaticTransitionFromOpenToHalfOpenEnabled: true
        recordExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - java.net.ConnectException
        ignoreExceptions:
          - feign.FeignException.BadRequest
          - feign.FeignException.NotFound
          - feign.FeignException.UnprocessableEntity
      critical:
        slidingWindowSize: 100
        minimumNumberOfCalls: 20
        failureRateThreshold: 50
        slowCallRateThreshold: 80
        waitDurationInOpenState: 30s
        permittedNumberOfCallsInHalfOpenState: 10
      lenient:
        slidingWindowSize: 20
        minimumNumberOfCalls: 5
        failureRateThreshold: 70
        slowCallRateThreshold: 90
        waitDurationInOpenState: 15s
        permittedNumberOfCallsInHalfOpenState: 3
    instances:
      pgPayment:                            # CRITICAL: uses 'critical' config
        baseConfig: critical
        slowCallDurationThreshold: 5000ms
        waitDurationInOpenState: 30s
      easyPay:
        baseConfig: critical
        slowCallDurationThreshold: 5000ms
      bank:
        baseConfig: critical
        slowCallDurationThreshold: 8000ms
        waitDurationInOpenState: 60s
        permittedNumberOfCallsInHalfOpenState: 5
      keyMgmt:                              # HIGH: stricter failure threshold
        baseConfig: default
        failureRateThreshold: 40
        slowCallRateThreshold: 70
        slowCallDurationThreshold: 2000ms
        waitDurationInOpenState: 15s
      # Other HIGH: taxInvoice(60%/5000ms), auth(default/3000ms), digitalSign(default/5000ms)
      teamMessenger:                        # LOW: uses 'lenient' config
        baseConfig: lenient
        slowCallDurationThreshold: 3000ms
      sqs:                                  # MEDIUM: adds SqsException
        baseConfig: default
        slowCallDurationThreshold: 5000ms
        recordExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - software.amazon.awssdk.services.sqs.model.SqsException
```

### Feign Client Instance Naming

With `alphanumeric-ids.enabled: true`, CB instance names: `{FeignClientName}{methodName}{paramTypes}` (e.g. `PgPaymentClientprocessPaymentPaymentRequest`).

---

## 4. CB Integration Method 2: Resilience4jFeign (Programmatic)

```kotlin
import feign.Feign
import io.github.resilience4j.circuitbreaker.CircuitBreaker
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry
import io.github.resilience4j.feign.FeignDecorators
import io.github.resilience4j.feign.Resilience4jFeign

@Configuration
class PgPaymentFeignConfig(
    private val circuitBreakerRegistry: CircuitBreakerRegistry,
    private val pgPaymentFallback: PgPaymentFallback,
) {
    @Bean
    fun pgPaymentClient(): PgPaymentClient {
        val circuitBreaker = circuitBreakerRegistry.circuitBreaker("pgPayment")

        val decorators = FeignDecorators.builder()
            .withCircuitBreaker(circuitBreaker)
            .withFallback(pgPaymentFallback)
            .build()

        return Resilience4jFeign.builder(decorators)
            .encoder(JacksonEncoder())
            .decoder(JacksonDecoder())
            .target(PgPaymentClient::class.java, "https://pg-api.example.com")
    }
}
```

### When to use Method 2

- Need method-level CB granularity within a single Feign client
- Need custom decorator stacking order
- Need programmatic fallback registration
- Integration with non-Spring Feign usage

---

## 5. Per-Dependency CB Configuration Table

| Dependency | failureRate (%) | slowCallRate (%) | slowCallDuration (ms) | windowSize | minCalls | waitInOpen (s) | halfOpenCalls |
|-----------|----------------|-----------------|---------------------|------------|----------|---------------|---------------|
| PG Payment | 50 | 80 | 5000 | 100 | 20 | 30 | 10 |
| Easy Pay | 50 | 80 | 5000 | 100 | 20 | 30 | 10 |
| Bank | 50 | 80 | 8000 | 50 | 10 | 60 | 5 |
| Tax Invoice | 60 | 80 | 5000 | 50 | 10 | 30 | 5 |
| Key Mgmt | 40 | 70 | 2000 | 50 | 10 | 15 | 5 |
| Auth | 50 | 80 | 3000 | 50 | 10 | 30 | 5 |
| Digital Sign | 50 | 80 | 5000 | 50 | 10 | 30 | 5 |
| Messaging | 60 | 90 | 5000 | 30 | 5 | 30 | 5 |
| File Storage | 60 | 90 | 10000 | 30 | 5 | 30 | 5 |
| Team Messenger | 70 | 90 | 3000 | 20 | 5 | 15 | 3 |
| SQS | 50 | 80 | 5000 | 50 | 10 | 30 | 5 |

---

## 6. Exception Classification YAML

```yaml
# Record as failure (affects CB failure rate)
resilience4j:
  circuitbreaker:
    configs:
      default:
        recordExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - java.net.ConnectException
          # 5xx FeignExceptions are recorded by default via recordFailurePredicate
        recordFailurePredicate: >
          com.example.resilience.predicate.ServerErrorPredicate
        ignoreExceptions:
          - feign.FeignException.BadRequest          # 400
          - feign.FeignException.NotFound             # 404
          - feign.FeignException.UnprocessableEntity   # 422
          - feign.FeignException.Forbidden             # 403
```

### ServerErrorPredicate (Kotlin)

```kotlin
package com.example.resilience.predicate

import feign.FeignException
import java.util.function.Predicate

class ServerErrorPredicate : Predicate<Throwable> {
    override fun test(throwable: Throwable): Boolean {
        return when (throwable) {
            is FeignException -> throwable.status() in 500..599
            else -> true  // non-Feign exceptions are recorded
        }
    }
}
```

---

## 7. CB State Transition Diagram

```
                    ┌──────────────────────────────────┐
                    │                                  │
                    ▼                                  │
              ┌──────────┐                             │
              │  CLOSED  │  (Normal operation)         │
              │          │  All calls pass through     │
              └────┬─────┘                             │
                   │                                   │
                   │ failureRate >= threshold           │
                   │ OR slowCallRate >= threshold       │
                   ▼                                   │
              ┌──────────┐                             │
              │   OPEN   │  (Circuit tripped)          │
              │          │  All calls rejected with    │
              │          │  CallNotPermittedException  │
              └────┬─────┘                             │
                   │                                   │
                   │ waitDurationInOpenState elapsed    │
                   ▼                                   │
              ┌──────────┐                             │
              │HALF_OPEN │  (Probing)                  │
              │          │  N calls permitted           │
              └──┬───┬───┘                             │
                 │   │                                 │
     failure ≥   │   │  failure < threshold            │
     threshold   │   │                                 │
                 │   └─────────────────────────────────┘
                 │             (Back to CLOSED)
                 │
                 └──────────► OPEN (Re-trip)
```

---

## 8. Resilience4j Decorator Chain

### Execution Order (Programmatic)

```
Request
  │
  ▼
┌─────────────┐
│ Rate Limiter│  ← Outermost: rate limit first
└──────┬──────┘
       ▼
┌─────────────┐
│    Retry    │  ← Retries the entire inner chain
└──────┬──────┘
       ▼
┌─────────────┐
│Circuit Break│  ← CB rejection triggers retry
└──────┬──────┘
       ▼
┌─────────────┐
│  Bulkhead   │  ← Thread/semaphore isolation
└──────┬──────┘
       ▼
┌─────────────┐
│ TimeLimiter │  ← Timeout enforcement per call
└──────┬──────┘
       ▼
┌─────────────┐
│  Feign Call │  ← Actual HTTP call
└─────────────┘
```

### Annotation Execution Order (Spring AOP)

```
@Bulkhead          ← Outermost AOP proxy (first to execute)
  └─ @TimeLimiter  ← Timeout within bulkhead thread
      └─ @CircuitBreaker  ← CB evaluation
          └─ @Retry        ← Innermost: retries CB+TimeLimiter+Bulkhead
              └─ method()  ← Actual method call
```

Note: Annotation order is reversed from programmatic order because AOP proxies wrap from outermost to innermost.

---

## 9. Per-Dependency Timeout Budget Table

| Dependency | Connect (ms) | Read (ms) | Total Budget (ms) | maxAttempts | Retry Budget (ms) | Fallback |
|-----------|-------------|----------|-------------------|------------|-------------------|----------|
| PG Payment | 1000 | 5000 | 6000 | 3 | 18000 | Fail Fast |
| Easy Pay | 1000 | 5000 | 6000 | 3 | 18000 | Fail Fast |
| Bank | 2000 | 8000 | 10000 | 3 | 30000 | Queue for Retry |
| Tax Invoice | 1000 | 5000 | 6000 | 3 | 18000 | Queue for Later |
| Key Mgmt | 500 | 2000 | 2500 | 3 | 7500 | Cached Response |
| Auth | 500 | 3000 | 3500 | 3 | 10500 | Fail Fast |
| Digital Sign | 1000 | 5000 | 6000 | 3 | 18000 | Queue for Retry |
| Messaging | 1000 | 5000 | 6000 | 3 | 18000 | Queue for Later |
| File Storage | 1000 | 10000 | 11000 | 3 | 33000 | Queue for Later |
| Team Messenger | 500 | 3000 | 3500 | 2 | 7000 | Skip |
| SQS | 1000 | 5000 | 6000 | 3 | 18000 | Queue for Retry |

**Budget Rule**: `Retry Budget = Total Budget * maxAttempts`
User-facing SLA must exceed the retry budget to prevent user-visible timeouts.

---

## 10. Retry Policy YAML

```yaml
resilience4j:
  retry:
    configs:
      default:
        maxAttempts: 3
        waitDuration: 500ms
        enableExponentialBackoff: true
        exponentialBackoffMultiplier: 2.0
        enableRandomizedWait: true
        randomizedWaitFactor: 0.1
        retryExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - java.net.ConnectException
        ignoreExceptions:
          - feign.FeignException.BadRequest
          - feign.FeignException.NotFound
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
      payment:
        maxAttempts: 3
        waitDuration: 1000ms
        enableExponentialBackoff: true
        exponentialBackoffMultiplier: 2.0
        enableRandomizedWait: true
        randomizedWaitFactor: 0.1
        retryExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - java.net.ConnectException
        ignoreExceptions:
          - feign.FeignException.BadRequest
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
      lenient:
        maxAttempts: 2
        waitDuration: 300ms
        enableExponentialBackoff: true
        exponentialBackoffMultiplier: 1.5
        retryExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
    instances:
      pgPayment:
        baseConfig: payment
      easyPay:
        baseConfig: payment
      bank:
        baseConfig: default
        waitDuration: 1000ms
      # Other default instances: taxInvoice, keyMgmt(300ms), auth, digitalSign, messaging, fileStorage(1000ms)
      teamMessenger:
        baseConfig: lenient
      sqs:
        baseConfig: default
        retryExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - software.amazon.awssdk.services.sqs.model.SqsException
```

---

## 11. Payment idempotencyKey Code

### Correct: With idempotencyKey (retry-safe)

```kotlin
class PgPaymentAdapter(
    private val pgPaymentClient: PgPaymentClient,
    private val idempotencyKeyGenerator: IdempotencyKeyGenerator,
) : PgPaymentPort {

    override fun processPayment(request: PaymentRequest): PaymentResponse {
        // Generate idempotency key BEFORE first attempt
        // Same key is reused across all retry attempts
        val idempotencyKey = idempotencyKeyGenerator.generate(
            merchantId = request.merchantId,
            orderId = request.orderId,
        )

        return pgPaymentClient.processPayment(
            PgPaymentRequest(
                idempotencyKey = idempotencyKey,  // PG deduplicates using this key
                amount = request.amount,
                currency = request.currency,
                merchantId = request.merchantId,
                orderId = request.orderId,
            )
        )
    }
}
```

### FORBIDDEN: Without idempotencyKey

Omitting `idempotencyKey` from `PgPaymentRequest` is FORBIDDEN. If the call times out but PG processed it, the retry creates a SECOND charge. Always generate the key before the first attempt and include it in every retry.

### IdempotencyKeyGenerator

```kotlin
@Component
class IdempotencyKeyGenerator {
    fun generate(merchantId: String, orderId: String): String {
        // Deterministic key from business identifiers
        // Same input always produces same key = safe for retry
        return UUID.nameUUIDFromBytes(
            "$merchantId:$orderId".toByteArray()
        ).toString()
    }
}
```

---

## 12. Fallback Strategy Table

| Strategy | Description | Target Systems | Implementation Pattern |
|----------|------------|---------------|----------------------|
| Fail Fast | Return error immediately to caller, no fallback logic | PG Payment, Easy Pay, Auth | Throw domain exception |
| Queue for Retry | Enqueue failed request to SQS for async retry with backoff | Bank, Digital Sign, SQS | SQS producer + retry consumer |
| Queue for Later | Enqueue for batch processing in next scheduled cycle | Tax Invoice, Messaging, File Storage | SQS producer + batch consumer |
| Skip | Silently skip the call, log for manual review | Team Messenger | Log + return empty result |
| Degraded Feature | Disable non-critical feature via feature flag, proceed with core flow | Conditional per feature flag | Feature flag check + reduced response |
| Cached Response | Return last known good response from Redis cache | Key Mgmt | Redis cache lookup |

---

## 13. Fallback Implementation Patterns

### Fail Fast

```kotlin
class PgPaymentFallback : PgPaymentClient {
    override fun processPayment(request: PgPaymentRequest): PgPaymentResponse {
        throw PaymentGatewayUnavailableException(
            message = "PG payment gateway is unavailable. Please retry later.",
            originalRequest = request,
        )
    }
}
```

### Queue for Retry / Queue for Later

Both patterns use SQS. "Queue for Retry" retries with backoff; "Queue for Later" defers to next batch cycle.

```kotlin
class BankTransferFallback(
    private val sqsTemplate: SqsTemplate,
) : BankTransferClient {
    override fun transfer(request: BankTransferRequest): BankTransferResponse {
        sqsTemplate.send("bank-transfer-retry-queue", BankTransferRetryMessage(
            request = request, retryCount = 0, scheduledAt = Instant.now(),
        ))
        return BankTransferResponse.queued(message = "Queued for async retry.", trackingId = request.trackingId)
    }
}

// Queue for Later follows the same pattern with a batch queue destination
// e.g. sqsTemplate.send("tax-invoice-batch-queue", TaxInvoiceBatchMessage(..., batchCycle = "NEXT"))
```

### Skip

```kotlin
class TeamMessengerFallback(private val logger: Logger) : TeamMessengerClient {
    override fun sendNotification(request: NotificationRequest): NotificationResponse {
        logger.warn("Team messenger unavailable. Skipping. channel={}, correlationId={}",
            request.channel, request.correlationId)
        return NotificationResponse.skipped()
    }
}
```

### Cached Response

```kotlin
class KeyMgmtFallback(
    private val redisTemplate: RedisTemplate<String, KeyInfo>,
) : KeyMgmtClient {
    override fun getPublicKey(keyId: String): KeyInfo {
        return redisTemplate.opsForValue().get("key-mgmt:$keyId")
            ?: throw KeyManagementUnavailableException("No cached key for keyId=$keyId")
    }
}
```

### Degraded Feature

```kotlin
class FeatureDegradationFallback(private val featureFlagService: FeatureFlagService) {
    fun <T> withDegradation(featureKey: String, degradedResponse: T, call: () -> T): T {
        return try { call() } catch (e: CallNotPermittedException) {
            featureFlagService.disable(featureKey)
            degradedResponse
        }
    }
}
```

---

*Last updated: 2025-05. Resilience4j 2.x + Spring Cloud 2023.x + Spring Boot 3.x.*
