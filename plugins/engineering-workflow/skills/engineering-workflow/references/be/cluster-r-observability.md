# Resilience Observability Reference (R-4)

> Static reference for resilience observability design.

---

## 1. Tracing Infrastructure

### Micrometer-OTel Architecture

```
Application Code
  └─ Micrometer Observation API (ObservationRegistry, @Observed)
       ├─ tracing-bridge-otel (Primary) ──► OTel SDK ──► OTel Collector ──► Tempo/Jaeger
       └─ tracing-bridge-brave (Legacy) ──► Brave ──► Zipkin
```

- Application code depends ONLY on Micrometer Observation API (no direct OTel/Brave imports)
- Bridge selection is an infrastructure concern -- swappable without code changes
- OTel bridge is primary; Brave bridge exists for legacy compatibility

### Auto-Instrumentation Scope

| Component | Instrumentation | Mechanism |
|-----------|----------------|-----------|
| REST Controllers | Automatic | Spring MVC ObservationFilter |
| Feign Clients | Automatic | MicrometerObservationCapability |
| JDBC Queries | Automatic | Datasource proxy with ObservationRegistry |
| SQS Producer/Consumer | Automatic | Spring Cloud AWS messaging integration |
| Custom Business Logic | Manual | ObservationRegistry + Observation API |

---

## 2. Observation API Code

### PgAdapter with ObservationRegistry

```kotlin
@Component
class PgPaymentAdapter(
    private val pgPaymentClient: PgPaymentClient,
    private val observationRegistry: ObservationRegistry,
) : PgPaymentPort {

    override fun processPayment(request: PaymentRequest): PaymentResponse {
        val observation = Observation.createNotStarted(
            "pg.payment.process",
            observationRegistry
        )
            .contextualName("PG Payment Processing")
            .lowCardinalityKeyValue("pg.payment.type", request.paymentType.name)
            .lowCardinalityKeyValue("pg.payment.currency", request.currency)
            .highCardinalityKeyValue("pg.payment.merchant_id", request.merchantId)

        return observation.observe {
            pgPaymentClient.processPayment(
                PgPaymentRequest(
                    idempotencyKey = request.idempotencyKey,
                    amount = request.amount,
                    currency = request.currency,
                    merchantId = request.merchantId,
                    orderId = request.orderId,
                )
            ).toDomain()
        }
    }
}
```

For consistent naming, implement `ObservationConvention<T>` with `getName()`, `getContextualName()`, and `getLowCardinalityKeyValues()` methods.

---

## 3. Metrics Catalog

### Circuit Breaker Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `resilience4j_circuitbreaker_state` | Gauge | Current CB state: 0=CLOSED, 1=OPEN, 2=HALF_OPEN, 3=DISABLED, 4=FORCED_OPEN |
| `resilience4j_circuitbreaker_calls_total` | Counter | Total calls, tagged by `kind`: successful, failed, ignored, not_permitted |
| `resilience4j_circuitbreaker_failure_rate` | Gauge | Current failure rate percentage (-1 if below minimumNumberOfCalls) |
| `resilience4j_circuitbreaker_slow_call_rate` | Gauge | Current slow call rate percentage |
| `resilience4j_circuitbreaker_slow_calls_total` | Counter | Total slow calls, tagged by `kind`: successful_slow, failed_slow |
| `resilience4j_circuitbreaker_not_permitted_calls_total` | Counter | Total calls rejected in OPEN state |
| `resilience4j_circuitbreaker_buffered_calls` | Gauge | Number of calls in the sliding window |

### Bulkhead Metrics (Semaphore)

| Metric Name | Type | Description |
|------------|------|-------------|
| `resilience4j_bulkhead_available_concurrent_calls` | Gauge | Available permits |
| `resilience4j_bulkhead_max_allowed_concurrent_calls` | Gauge | Maximum configured permits |

### Thread Pool Bulkhead Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `resilience4j_thread_pool_bulkhead_queue_depth` | Gauge | Current number of tasks in the queue |
| `resilience4j_thread_pool_bulkhead_thread_pool_size` | Gauge | Current thread count in the pool |
| `resilience4j_thread_pool_bulkhead_core_thread_pool_size` | Gauge | Core thread pool size |
| `resilience4j_thread_pool_bulkhead_max_thread_pool_size` | Gauge | Maximum thread pool size |
| `resilience4j_thread_pool_bulkhead_available_queue_capacity` | Gauge | Remaining queue capacity |

### Retry Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `resilience4j_retry_calls_total` | Counter | Total retry calls, tagged by `kind`: successful_without_retry, successful_with_retry, failed_with_retry, failed_without_retry |

### Application-Level Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `payment_process_duration_seconds` | Timer | Payment processing latency histogram |
| `payment_process_total` | Counter | Total payment attempts, tagged by `status`: success, failure, timeout |
| `payment_fallback_total` | Counter | Total fallback invocations, tagged by `strategy`: fail_fast, queue_retry, cached |
| `bank_transfer_duration_seconds` | Timer | Bank transfer call latency histogram |
| `tax_invoice_issue_duration_seconds` | Timer | Tax invoice issuance latency histogram |
| `external_call_duration_seconds` | Timer | Generic external call latency, tagged by `dependency` |
| `sqs_message_send_duration_seconds` | Timer | SQS message send latency histogram |
| `hikaricp_connections_active` | Gauge | HikariCP active connections |
| `hikaricp_connections_idle` | Gauge | HikariCP idle connections |
| `hikaricp_connections_pending` | Gauge | HikariCP pending connection requests |
| `hikaricp_connections_timeout_total` | Counter | HikariCP connection timeout count |

---

## 4. Prometheus Endpoint YAML

```yaml
management:
  endpoints:
    web:
      exposure:
        include:
          - health
          - info
          - prometheus
          - metrics
          - circuitbreakers
          - circuitbreakerevents
          - bulkheads
          - retries
          - retryevents
  endpoint:
    health:
      show-details: always
      show-components: always
    prometheus:
      enabled: true
  metrics:
    export:
      prometheus:
        enabled: true
        step: 15s
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active:local}
    distribution:
      percentiles-histogram:
        http.server.requests: true
        http.client.requests: true
      slo:
        http.server.requests: 50ms, 100ms, 200ms, 500ms, 1s, 5s
        http.client.requests: 100ms, 500ms, 1s, 5s, 10s
```

---

## 5. Dashboard Layout (Grafana)

| Row | Title | Key Panels | Key Metrics |
|-----|-------|-----------|-------------|
| 1 | System Overview | CB state summary (Stat), global failure rate (Gauge), throughput (Graph), active alerts (Stat) | All CB states, aggregate call rates |
| 2 | Payment Systems | PG Payment/Easy Pay/Bank CB state (State Timeline), failure rate + latency p99 + timeout count (Graph) | Payment failure rates, SLA compliance |
| 3 | Business Services | Tax Invoice/Key Mgmt/Auth/Digital Sign CB state (State Timeline), retry rate (Graph) | Per-service CB state, retry burden |
| 4 | Notification | Messaging/Team Messenger CB state (State Timeline), delivery rate (Graph), skip count (Counter) | Message delivery reliability |
| 5 | AWS Services | SQS CB state (State Timeline), bulkhead utilization + queue depth + retry rate (Graph) | SQS capacity, backpressure |
| 6 | Database | HikariCP active/pending/timeout (Graph), Redis Lettuce pool (Graph), query latency p99 (Graph) | Connection pool saturation |

---

## 6. Alert Rules by Severity

### P1 -- Critical (Immediate Response)

| Alert Name | Condition (PromQL) | Threshold | Duration | Channel |
|-----------|-------------------|-----------|----------|---------|
| PaymentCBOpen | `resilience4j_circuitbreaker_state{name=~"pgPayment\|easyPay"} == 1` | State = OPEN | 30s | PagerDuty + Slack #incidents |
| PaymentFailureSpike | `rate(resilience4j_circuitbreaker_calls_total{name=~"pgPayment\|easyPay",kind="failed"}[5m]) / rate(resilience4j_circuitbreaker_calls_total{name=~"pgPayment\|easyPay"}[5m]) > 0.10` | > 10% failure rate | 5m | PagerDuty + Slack #incidents |
| HikariPoolExhaustion | `hikaricp_connections_active / hikaricp_connections_max > 0.95` | > 95% utilization | 1m | PagerDuty + Slack #incidents |
| PaymentLatencyBreach | `histogram_quantile(0.99, rate(payment_process_duration_seconds_bucket[5m])) > 10` | p99 > 10s | 3m | PagerDuty + Slack #incidents |

Runbook: Verify dependency health, check for upstream outage, consider manual CB force-open, escalate to on-call.

### P2 -- High (Respond Within 30 Minutes)

| Alert Name | Condition (PromQL) | Threshold | Duration | Channel |
|-----------|-------------------|-----------|----------|---------|
| NonPaymentCBOpen | `resilience4j_circuitbreaker_state{name!~"pgPayment\|easyPay"} == 1` | State = OPEN | 2m | Slack #alerts |
| ThreadPoolBulkheadFull | `resilience4j_thread_pool_bulkhead_available_queue_capacity == 0` | Queue full | 1m | Slack #alerts |
| RetryExhaustionRate | `rate(resilience4j_retry_calls_total{kind="failed_with_retry"}[10m]) / rate(resilience4j_retry_calls_total[10m]) > 0.05` | > 5% retry exhaustion | 10m | Slack #alerts |
| BankCBOpen | `resilience4j_circuitbreaker_state{name="bank"} == 1` | State = OPEN | 1m | Slack #alerts |

Runbook: Check dependency logs, verify retry/fallback behavior, assess business impact, plan scaling if needed.

### P3 -- Warning (Review in Business Hours)

| Alert Name | Condition (PromQL) | Threshold | Duration | Channel |
|-----------|-------------------|-----------|----------|---------|
| SlowCallRateElevated | `resilience4j_circuitbreaker_slow_call_rate > 50` | > 50% slow calls | 15m | Slack #monitoring |
| BulkheadUtilizationHigh | `1 - (resilience4j_bulkhead_available_concurrent_calls / resilience4j_bulkhead_max_allowed_concurrent_calls) > 0.8` | > 80% utilized | 10m | Slack #monitoring |
| RedisPoolLow | `lettuce_pool_idle / lettuce_pool_max < 0.2` | < 20% available | 5m | Slack #monitoring |
| HikariPendingHigh | `hikaricp_connections_pending > 5` | > 5 pending | 5m | Slack #monitoring |

Runbook: Trend analysis, capacity planning, consider pool size adjustment in next deployment.

---

## 7. PromQL Examples

### CB State Check

```promql
# Current state of all circuit breakers
resilience4j_circuitbreaker_state

# Payment CBs that are NOT closed
resilience4j_circuitbreaker_state{name=~"pgPayment|easyPay|bank"} != 0

# Time since last CB state change (requires recording rule)
time() - resilience4j_circuitbreaker_state_changed_timestamp
```

### Failure Rate

```promql
# Failure rate per CB (5-minute window)
rate(resilience4j_circuitbreaker_calls_total{kind="failed"}[5m])
/
rate(resilience4j_circuitbreaker_calls_total[5m])

# Failure rate comparison across all payment dependencies
sum by (name) (
  rate(resilience4j_circuitbreaker_calls_total{kind="failed", name=~"pgPayment|easyPay|bank"}[5m])
)
/
sum by (name) (
  rate(resilience4j_circuitbreaker_calls_total{name=~"pgPayment|easyPay|bank"}[5m])
)

# Failure rate trend (1-hour range, 5-minute steps)
rate(resilience4j_circuitbreaker_calls_total{kind="failed", name="pgPayment"}[5m])
```

### HikariCP Pool Utilization

```promql
# Connection pool utilization percentage
hikaricp_connections_active{pool="HikariPool-1"}
/
hikaricp_connections_max{pool="HikariPool-1"}

# Pending requests (connection starvation indicator)
hikaricp_connections_pending{pool="HikariPool-1"}

# Connection acquisition time p99
histogram_quantile(0.99,
  rate(hikaricp_connections_acquire_seconds_bucket{pool="HikariPool-1"}[5m])
)
```

### Retry Effectiveness

```promql
# Retry success rate (retries that eventually succeeded)
rate(resilience4j_retry_calls_total{kind="successful_with_retry"}[10m])
/
(
  rate(resilience4j_retry_calls_total{kind="successful_with_retry"}[10m])
  +
  rate(resilience4j_retry_calls_total{kind="failed_with_retry"}[10m])
)

# Total retry overhead (calls that needed retry / all calls)
(
  rate(resilience4j_retry_calls_total{kind="successful_with_retry"}[10m])
  +
  rate(resilience4j_retry_calls_total{kind="failed_with_retry"}[10m])
)
/
rate(resilience4j_retry_calls_total[10m])
```

### Bulkhead Pressure

```promql
# Thread pool bulkhead queue saturation
1 - (
  resilience4j_thread_pool_bulkhead_available_queue_capacity
  /
  (resilience4j_thread_pool_bulkhead_queue_depth + resilience4j_thread_pool_bulkhead_available_queue_capacity)
)

# Semaphore bulkhead utilization
1 - (
  resilience4j_bulkhead_available_concurrent_calls
  /
  resilience4j_bulkhead_max_allowed_concurrent_calls
)
```

---

## 8. Distributed Tracing Design

### Trace Propagation Flow

```
API Gateway (span-000) ──W3C traceparent──► Payment Service (span-002)
                                              ├── PG Payment Call (span-003, parent=span-002)
                                              ├── MySQL Query (span-004, parent=span-002)
                                              └── Redis Cache (span-005, parent=span-002)
All spans share traceId: abc123
```

### W3C Traceparent Header

Format: `00-{traceId:32hex}-{parentSpanId:16hex}-{traceFlags:01=sampled}`

### Feign Interceptor for Trace Propagation

```kotlin
@Component
class TracePropagationInterceptor(private val tracer: Tracer) : RequestInterceptor {
    override fun apply(template: RequestTemplate) {
        val ctx = tracer.currentSpan()?.context() ?: return
        template.header("traceparent", "00-${ctx.traceId()}-${ctx.spanId()}-01")
    }
}
```

---

## 9. Custom Span Attributes Code

### Resilience Event Span Attributes

```kotlin
@Component
class ResilienceSpanDecorator(
    private val tracer: Tracer,
) {

    fun addCircuitBreakerAttributes(cbName: String, state: CircuitBreaker.State) {
        val span = tracer.currentSpan() ?: return
        span.tag("resilience.cb.name", cbName)
        span.tag("resilience.cb.state", state.name)
    }

    fun addRetryAttributes(retryName: String, attemptNumber: Int) {
        val span = tracer.currentSpan() ?: return
        span.tag("resilience.retry.name", retryName)
        span.tag("resilience.retry.attempt", attemptNumber.toString())
    }

    fun addBulkheadAttributes(bulkheadName: String, waitTimeMs: Long) {
        val span = tracer.currentSpan() ?: return
        span.tag("resilience.bulkhead.name", bulkheadName)
        span.tag("resilience.bulkhead.wait_ms", waitTimeMs.toString())
    }

    fun addFallbackAttributes(dependency: String, strategy: String) {
        val span = tracer.currentSpan() ?: return
        span.tag("resilience.fallback.triggered", "true")
        span.tag("resilience.fallback.dependency", dependency)
        span.tag("resilience.fallback.strategy", strategy)
    }
}
```

### OTel SpanBuilder for Custom Business Spans

```kotlin
@Component
class PaymentTracer(
    private val tracer: Tracer,
) {

    fun tracePaymentProcess(
        merchantId: String,
        orderId: String,
        amount: Long,
        block: () -> PaymentResponse,
    ): PaymentResponse {
        val span = tracer.nextSpan()
            .name("payment.process")
            .tag("payment.merchant_id", merchantId)
            .tag("payment.order_id", orderId)
            .tag("payment.amount", amount.toString())
            .start()

        return try {
            tracer.withSpan(span).use {
                val response = block()
                span.tag("payment.status", "success")
                span.tag("payment.transaction_id", response.transactionId)
                response
            }
        } catch (e: Exception) {
            span.tag("payment.status", "failure")
            span.tag("payment.error", e.javaClass.simpleName)
            span.error(e)
            throw e
        } finally {
            span.end()
        }
    }
}
```

---

## 10. Saga Tracing

### Saga-as-Trace Model

Each saga = one trace. Each step = one span. Compensation steps are tagged `saga.compensation=true`.

```
Trace: saga-payment-order-12345
├── saga.step.validate_order (200ms)      tags: saga.step=1
├── saga.step.reserve_inventory (150ms)   tags: saga.step=2
├── saga.step.process_payment (3200ms)    tags: saga.step=3
│   ├── pg.payment.call (2800ms)          tags: resilience.cb.state=CLOSED
│   └── payment.idempotency_check (100ms)
├── saga.step.send_confirmation (500ms)   tags: saga.step=4
└── (On failure at step 3)
    ├── saga.compensation.release_inventory (180ms)  tags: saga.compensating_step=2
    └── saga.compensation.cancel_order (120ms)       tags: saga.compensating_step=1
```

### Saga Span Implementation

```kotlin
@Component
class SagaTracer(
    private val tracer: Tracer,
) {

    fun <T> traceSagaStep(
        sagaName: String,
        stepNumber: Int,
        stepName: String,
        block: () -> T,
    ): T {
        val span = tracer.nextSpan()
            .name("saga.step.$stepName")
            .tag("saga.name", sagaName)
            .tag("saga.step", stepNumber.toString())
            .tag("saga.step.name", stepName)
            .tag("saga.compensation", "false")
            .start()

        return try {
            tracer.withSpan(span).use {
                val result = block()
                span.tag("saga.step.status", "completed")
                result
            }
        } catch (e: Exception) {
            span.tag("saga.step.status", "failed")
            span.error(e)
            throw e
        } finally {
            span.end()
        }
    }

    fun traceCompensation(
        sagaName: String,
        compensatingStep: Int,
        compensationName: String,
        block: () -> Unit,
    ) {
        val span = tracer.nextSpan()
            .name("saga.compensation.$compensationName")
            .tag("saga.name", sagaName)
            .tag("saga.compensation", "true")
            .tag("saga.compensating_step", compensatingStep.toString())
            .start()

        try {
            tracer.withSpan(span).use {
                block()
                span.tag("saga.compensation.status", "completed")
            }
        } catch (e: Exception) {
            span.tag("saga.compensation.status", "failed")
            span.error(e)
            throw e
        } finally {
            span.end()
        }
    }
}
```

### Compensation Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `saga.name` | String | Business saga identifier (e.g., "payment", "refund") |
| `saga.step` | Integer | Step sequence number within the saga |
| `saga.step.name` | String | Human-readable step name |
| `saga.step.status` | String | completed, failed |
| `saga.compensation` | Boolean | true if this span is a compensation action |
| `saga.compensating_step` | Integer | The original step number being compensated |
| `saga.compensation.status` | String | completed, failed |

---

## 11. Health Indicator YAML

### Spring Boot Actuator + Resilience4j Health Integration

```yaml
management:
  health:
    circuitbreakers:
      enabled: true
    diskspace:
      enabled: true
    db:
      enabled: true
    redis:
      enabled: true
  endpoint:
    health:
      show-details: always
      show-components: always
      group:
        readiness:
          include:
            - db
            - redis
            - circuitBreakers
        liveness:
          include:
            - diskSpace

resilience4j:
  circuitbreaker:
    configs:
      default:
        registerHealthIndicator: true
    instances:
      pgPayment:
        registerHealthIndicator: true
      easyPay:
        registerHealthIndicator: true
      bank:
        registerHealthIndicator: true
      taxInvoice:
        registerHealthIndicator: true
      keyMgmt:
        registerHealthIndicator: true
      auth:
        registerHealthIndicator: true
      digitalSign:
        registerHealthIndicator: true
      messaging:
        registerHealthIndicator: true
      fileStorage:
        registerHealthIndicator: true
      teamMessenger:
        registerHealthIndicator: true
      sqs:
        registerHealthIndicator: true
```

### Health Status Mapping

| CB State | Health Status | Load Balancer Action |
|----------|-------------|---------------------|
| CLOSED | UP | Route traffic normally |
| HALF_OPEN | UP (with warning) | Route traffic, monitor closely |
| OPEN | DOWN | Remove from load balancer pool (if configured) |

### Health Endpoint Response

Each CB instance reports: `state`, `failureRate`, `slowCallRate`, `bufferedCalls`, `failedCalls`, `notPermittedCalls`. A CB in OPEN state sets its status to `CIRCUIT_OPEN`, which rolls up to the readiness group health. DB and Redis health checks are included in the readiness probe.

---

*Last updated: 2025-05. Micrometer Tracing 1.3.x + OpenTelemetry SDK 1.38.x + Resilience4j 2.x + Spring Boot 3.x.*
