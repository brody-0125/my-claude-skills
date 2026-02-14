# Event & Saga Design Reference

> Static reference for B-3 (Event Architect) and B-4 (Saga Coordinator).
> Covers Domain/Integration Event architecture, Spring ApplicationEvent patterns, AWS SQS integration, naming conventions, saga step classification, orchestrator patterns, and testing strategies.

---

## 1. Domain Event vs Integration Event Architecture

### Theoretical Comparison

| Aspect | Domain Event | Integration Event |
|--------|-------------|-------------------|
| **Definition** | A business-meaningful occurrence within the domain | A message transformed for sharing with external systems |
| **Immutability** | Immutable (past tense, already occurred fact) | Immutable (serialized message) |
| **Naming** | `{Aggregate}{PastVerb}Event` | `{Context}{PastVerb}Message` |
| **Transport** | Spring ApplicationEvent (in-process) | AWS SQS (cross-process/service) |
| **Scope** | Single application boundary | Crosses service/system boundaries |
| **Schema** | Internal domain model, no versioning needed | JSON with version field, backward compatibility required |
| **Transaction** | @TransactionalEventListener (after commit) | Separate transaction, Outbox or eventual |
| **Coupling** | Domain language based, internal coupling | Contract based, loose coupling |

### Critical Translation Rule

```
Domain Event  ──→  Translation Layer  ──→  Integration Event
(Spring)           (Listener/Translator)     (SQS Message)
```

**Publishing Domain Events directly to external consumers is PROHIBITED.** They must always pass through a translation layer.

Reasons:
1. Exposing the internal domain model to external consumers makes model changes a breaking change
2. External schemas must evolve independently (version field)
3. Internal event names (domain language) and external message names (contract language) may differ

---

## 2. Internal Event System (Spring ApplicationEvent)

### Domain Event Data Class

```kotlin
data class InvoiceIssuedEvent(
    val invoiceId: InvoiceId,
    val customerId: CustomerId,
    val totalAmount: Money,
    val issuedAt: LocalDateTime,
    val lineItems: List<InvoiceLineItem>,
) : ApplicationEvent(invoiceId)
```

Key characteristics:
- Immutable data class
- Uses domain value objects (InvoiceId, Money, etc.)
- Past tense naming: `Issued`, not `Issue` or `Issuing`
- Extends `ApplicationEvent` (Spring convention, source = aggregate ID)
- Contains all information needed by listeners (no lazy loading)

### Domain Event Publisher

```kotlin
@Component
class SpringDomainEventPublisher(
    private val applicationEventPublisher: ApplicationEventPublisher,
) : DomainEventPublisher {

    override fun publish(event: Any) {
        applicationEventPublisher.publishEvent(event)
    }

    override fun publishAll(events: List<Any>) {
        events.forEach { applicationEventPublisher.publishEvent(it) }
    }
}
```

Usage pattern:
- Domain service or UseCase calls `publisher.publish(event)` after domain operation
- Publisher is a thin wrapper around Spring's `ApplicationEventPublisher`
- Interface (`DomainEventPublisher`) lives in domain layer; implementation in infrastructure

### Event Listener

```kotlin
@Component
class InvoiceEventListener(
    private val notificationService: NotificationService,
    private val sqsInvoiceProducer: SqsInvoiceEventProducer,
    private val invoiceStatisticsService: InvoiceStatisticsService,
) {

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onInvoiceIssued(event: InvoiceIssuedEvent) {
        // 1. Internal side effect: statistics update
        invoiceStatisticsService.recordIssuance(
            customerId = event.customerId,
            amount = event.totalAmount,
            issuedAt = event.issuedAt,
        )

        // 2. Internal notification trigger
        notificationService.sendInvoiceNotification(
            customerId = event.customerId,
            invoiceId = event.invoiceId,
        )

        // 3. External publishing: Domain Event -> Integration Event translation
        sqsInvoiceProducer.publishInvoiceConfirmed(event)
    }
}
```

Transaction behavior:
- `AFTER_COMMIT`: listener runs after source transaction commits successfully
- If source transaction rolls back, listener does NOT execute
- Listener failure does NOT rollback the source transaction
- For critical side effects, consider Outbox pattern for guaranteed delivery

---

## 3. External Event System (AWS SQS)

### Integration Event Message

```kotlin
data class InvoiceConfirmedMessage(
    val version: Int = 1,
    val invoiceId: String,
    val customerId: String,
    val totalAmount: Long,
    val currency: String = "KRW",
    val confirmedAt: String,
    val lineItemCount: Int,
    val messageId: String = UUID.randomUUID().toString(),
    val timestamp: String = Instant.now().toString(),
)
```

Key differences from Domain Event:
- Primitive types only (String, Long, Int) -- no domain value objects
- Explicit `version` field for schema evolution
- `messageId` for deduplication
- `timestamp` for ordering/debugging
- Naming: `Message` suffix (not `Event`)
- Amount as Long (not Money value object) with explicit currency

### SQS Event Producer

```kotlin
@Component
class SqsInvoiceEventProducer(
    private val sqsTemplate: SqsTemplate,
    private val objectMapper: ObjectMapper,
    @Value("\${sqs.queue.invoice-confirmed}") private val queueUrl: String,
) {

    fun publishInvoiceConfirmed(event: InvoiceIssuedEvent) {
        val message = InvoiceConfirmedMessage(
            invoiceId = event.invoiceId.value,
            customerId = event.customerId.value,
            totalAmount = event.totalAmount.value.toLong(),
            confirmedAt = event.issuedAt.toString(),
            lineItemCount = event.lineItems.size,
        )

        val payload = objectMapper.writeValueAsString(message)

        sqsTemplate.send(
            SendMessageRequest.builder()
                .queueUrl(queueUrl)
                .messageBody(payload)
                .messageGroupId(event.invoiceId.value)  // FIFO queue
                .messageDeduplicationId(message.messageId)
                .build()
        )
    }
}
```

Note the translation happening here:
- `InvoiceIssuedEvent` (domain) -> `InvoiceConfirmedMessage` (integration)
- Domain value objects decomposed to primitives
- Different naming: "Issued" (domain event) vs "Confirmed" (integration message)

### SQS Consumer Pattern

```
Message received from SQS
    │
    ▼
Deserialize JSON → InvoiceConfirmedMessage
    │
    ▼
Validate message (version check, required fields)
    │
    ▼
Check idempotency (has this messageId been processed?)
    │
    ├─ YES → Acknowledge and skip (duplicate)
    │
    └─ NO  → Process business logic
              │
              ▼
         Save processing record (messageId → processed)
              │
              ▼
         Acknowledge message (delete from queue)
              │
         On failure:
              ▼
         Message returns to queue (visibility timeout)
              │
         After max retries:
              ▼
         Moved to Dead Letter Queue (DLQ)
```

```kotlin
@Component
class InvoiceConfirmedConsumer(
    private val invoiceProcessingService: InvoiceProcessingService,
    private val idempotencyStore: IdempotencyStore,
    private val objectMapper: ObjectMapper,
) {

    @SqsListener("\${sqs.queue.invoice-confirmed}")
    fun consume(message: String) {
        val msg = objectMapper.readValue(message, InvoiceConfirmedMessage::class.java)

        // Idempotency check
        if (idempotencyStore.isProcessed(msg.messageId)) {
            return  // Already processed, skip
        }

        // Version check
        require(msg.version <= SUPPORTED_VERSION) {
            "Unsupported message version: ${msg.version}"
        }

        // Process
        invoiceProcessingService.handleConfirmed(
            invoiceId = msg.invoiceId,
            customerId = msg.customerId,
            amount = msg.totalAmount,
        )

        // Mark as processed
        idempotencyStore.markProcessed(msg.messageId)
    }

    companion object {
        private const val SUPPORTED_VERSION = 1
    }
}
```

---

## 4. Naming Convention Table

| Role | Internal (Spring) | External (SQS/Kafka) | Mixing Prohibited |
|------|-------------------|----------------------|-------------------|
| **Emitter** | Publisher (`DomainEventPublisher`) | Producer (`SqsEventProducer`) | Do not use Publisher for SQS or Producer for Spring |
| **Receiver** | Listener (`@TransactionalEventListener`) | Consumer (`@SqsListener`) | Do not use Listener for SQS or Consumer for Spring |
| **Payload** | Event (`InvoiceIssuedEvent`) | Message (`InvoiceConfirmedMessage`) | Do not use Event for external messages |
| **Delivery** | Synchronous (in-process, after TX) | Asynchronous (cross-process) | -- |

---

## 5. Saga Step Classification Table

| Classification | Description | Characteristics | Position in Saga | Failure Behavior |
|---------------|-------------|----------------|-----------------|------------------|
| **Compensable** | Can be reversed | Can be rolled back via compensating transaction | Early part of saga | Execute compensation on subsequent step failure |
| **Pivot** | Decision point | Irreversible decision point | Middle of saga (only one) | On failure, compensate all preceding compensable steps |
| **Retryable** | Can be retried | Must eventually succeed, retryable | Late part of saga (after Pivot) | Retry on failure, manual intervention on final failure |

Ordering invariant: `[Compensable]* → Pivot → [Retryable]*`

---

## 6. Payment Flow Saga Scenario

### Full 4-Step Flow

```
Step 1              Step 2             Step 3              Step 4
[Compensable]       [Compensable]      [Pivot]             [Retryable]
Change sub status ──→  Approve payment ──→  Issue tax invoice ──→  Send notification
     │                   │                  │                   │
     │                   │                  │                   │
  compensation:       compensation:      (no compensation)   retry:
  Restore prev plan   Cancel payment                         Max 3 attempts
```

### Failure Scenarios

| Failure Point | Compensation Flow |
|--------------|-------------------|
| Step 2 failure (payment declined) | Step 1 compensation (restore plan) -> Saga ends |
| Step 3 failure (tax invoice) | Step 2 compensation (cancel payment) -> Step 1 compensation (restore plan) -> Saga ends |
| Step 4 failure (notification) | Retry 3 times -> On final failure: log + manual processing queue (no prior step compensation, after Pivot) |

---

## 7. Orchestrator UseCase Code

### SubscriptionChangeUseCase

```kotlin
@Service
class SubscriptionChangeUseCase(
    private val subscriptionRepository: SubscriptionRepository,
    private val paymentPort: PaymentPort,
    private val taxInvoicePort: TaxInvoicePort,
    private val notificationPort: NotificationPort,
) {

    @Transactional
    fun changeSubscription(command: SubscriptionChangeCommand): SubscriptionChangeResult {
        val subscription = subscriptionRepository.findById(command.subscriptionId)
            ?: throw SubscriptionNotFoundException(command.subscriptionId)

        val previousPlan = subscription.currentPlan

        // Step 1 (Compensable): Change subscription status
        subscription.changePlan(command.newPlan)
        subscriptionRepository.save(subscription)

        // Step 2 (Compensable): Approve payment
        val paymentResult: PaymentResult
        try {
            paymentResult = paymentPort.approve(
                PaymentApproveCommand(
                    orderId = command.orderId,
                    amount = command.newPlan.price,
                    paymentKey = command.paymentKey,
                    method = command.paymentMethod,
                )
            )
        } catch (e: PaymentException) {
            // Step 1 compensation: Restore previous plan
            subscription.changePlan(previousPlan)
            subscriptionRepository.save(subscription)
            throw SagaCompensatedException("Subscription change cancelled due to payment failure", e)
        }

        // Step 3 (Pivot): Issue tax invoice
        try {
            taxInvoicePort.issue(
                TaxInvoiceIssueCommand(
                    customerId = subscription.customerId,
                    amount = command.newPlan.price,
                    paymentId = paymentResult.paymentId,
                    itemDescription = "Subscription plan change: ${command.newPlan.name}",
                )
            )
        } catch (e: TaxInvoiceException) {
            // Step 2 compensation: Cancel payment
            paymentPort.cancel(
                PaymentCancelCommand(
                    paymentId = paymentResult.paymentId,
                    cancelAmount = command.newPlan.price,
                    reason = "Payment cancelled due to tax invoice issuance failure",
                )
            )
            // Step 1 compensation: Restore previous plan
            subscription.changePlan(previousPlan)
            subscriptionRepository.save(subscription)
            throw SagaCompensatedException("Full rollback due to tax invoice issuance failure", e)
        }

        // Step 4 (Retryable): Send notification
        retryNotification(subscription, command.newPlan)

        return SubscriptionChangeResult(
            subscriptionId = subscription.id,
            newPlan = command.newPlan,
            paymentId = paymentResult.paymentId,
            status = ChangeStatus.COMPLETED,
        )
    }

    private fun retryNotification(subscription: Subscription, newPlan: SubscriptionPlan) {
        var lastException: Exception? = null
        repeat(3) { attempt ->
            try {
                notificationPort.send(NotificationCommand(
                    recipientId = subscription.customerId,
                    type = NotificationType.SUBSCRIPTION_CHANGED,
                    data = mapOf("planName" to newPlan.name, "price" to newPlan.price.toString()),
                ))
                return
            } catch (e: Exception) { lastException = e; Thread.sleep(1000L * (attempt + 1)) }
        }
        log.warn("Notification send final failure. subscriptionId={}, manual processing required", subscription.id, lastException)
    }

    companion object { private val log = LoggerFactory.getLogger(SubscriptionChangeUseCase::class.java) }
}
```

---

## 8. Saga Testing Code

### SubscriptionChangeUseCaseTest

```kotlin
class SubscriptionChangeUseCaseTest {

    private val subscriptionRepository = spyk(FakeSubscriptionRepository())
    private val paymentPort = StubPgPort()
    private val taxInvoicePort = StubTaxInvoicePort()
    private val notificationPort = StubNotificationPort()

    private val useCase = SubscriptionChangeUseCase(
        subscriptionRepository = subscriptionRepository,
        paymentPort = paymentPort,
        taxInvoicePort = taxInvoicePort,
        notificationPort = notificationPort,
    )

    @BeforeEach
    fun setUp() {
        paymentPort.reset()
        taxInvoicePort.reset()
        notificationPort.reset()
    }

    @Test
    fun `happy path - all steps succeed and subscription change completes`() {
        // given
        val subscription = createSubscription(plan = PlanType.BASIC)
        subscriptionRepository.save(subscription)
        val command = createChangeCommand(
            subscriptionId = subscription.id,
            newPlan = PlanType.PREMIUM,
        )

        // when
        val result = useCase.changeSubscription(command)

        // then
        assertThat(result.status).isEqualTo(ChangeStatus.COMPLETED)
        assertThat(result.newPlan).isEqualTo(PlanType.PREMIUM)
        assertThat(paymentPort.approveHistory).hasSize(1)
        assertThat(taxInvoicePort.issueHistory).hasSize(1)
        assertThat(notificationPort.sendHistory).hasSize(1)

        val saved = subscriptionRepository.findById(subscription.id)!!
        assertThat(saved.currentPlan).isEqualTo(PlanType.PREMIUM)
    }

    @Test
    fun `restore subscription status on payment failure (Step 1 compensation)`() {
        // given
        val subscription = createSubscription(plan = PlanType.BASIC)
        subscriptionRepository.save(subscription)
        paymentPort.shouldFailApprove = true  // Configure Step 2 failure

        val command = createChangeCommand(
            subscriptionId = subscription.id,
            newPlan = PlanType.PREMIUM,
        )

        // when & then
        assertThrows<SagaCompensatedException> {
            useCase.changeSubscription(command)
        }

        // Step 1 compensation verification: previous plan restored
        val saved = subscriptionRepository.findById(subscription.id)!!
        assertThat(saved.currentPlan).isEqualTo(PlanType.BASIC)

        // Payment cancel is not called (since the payment itself failed)
        assertThat(paymentPort.cancelHistory).isEmpty()
    }

    @Test
    fun `cancel payment and restore subscription on tax invoice failure (Step 2, 1 compensation)`() {
        // given
        val subscription = createSubscription(plan = PlanType.BASIC)
        subscriptionRepository.save(subscription)
        taxInvoicePort.shouldFailIssue = true  // Configure Step 3 (Pivot) failure

        val command = createChangeCommand(
            subscriptionId = subscription.id,
            newPlan = PlanType.PREMIUM,
        )

        // when & then
        assertThrows<SagaCompensatedException> {
            useCase.changeSubscription(command)
        }

        // Step 2 compensation verification: payment cancelled
        assertThat(paymentPort.cancelHistory).hasSize(1)
        assertThat(paymentPort.cancelHistory[0].reason)
            .contains("tax invoice issuance failure")

        // Step 1 compensation verification: previous plan restored
        val saved = subscriptionRepository.findById(subscription.id)!!
        assertThat(saved.currentPlan).isEqualTo(PlanType.BASIC)
    }

    @Test
    fun `saga succeeds after retrying notification failure (Retryable step)`() {
        // given
        val subscription = createSubscription(plan = PlanType.BASIC)
        subscriptionRepository.save(subscription)
        notificationPort.shouldFailSend = true  // Configure Step 4 failure (all retries fail)

        val command = createChangeCommand(
            subscriptionId = subscription.id,
            newPlan = PlanType.PREMIUM,
        )

        // when
        val result = useCase.changeSubscription(command)

        // then - Saga succeeds (Retryable step failure does not fail the saga)
        assertThat(result.status).isEqualTo(ChangeStatus.COMPLETED)

        // Verify 3 notification send attempts
        assertThat(notificationPort.sendHistory).hasSize(3)

        // Payment and tax invoice are not compensated
        assertThat(paymentPort.cancelHistory).isEmpty()
    }

    @Test
    fun `idempotency guaranteed when same request executed twice`() {
        // given
        val subscription = createSubscription(plan = PlanType.BASIC)
        subscriptionRepository.save(subscription)
        val command = createChangeCommand(
            subscriptionId = subscription.id,
            newPlan = PlanType.PREMIUM,
        )

        // when
        val result1 = useCase.changeSubscription(command)

        paymentPort.reset()
        taxInvoicePort.reset()
        notificationPort.reset()

        // Re-execute same command (already changed to PREMIUM)
        val result2 = useCase.changeSubscription(command)

        // then - Second execution also completes normally
        assertThat(result1.status).isEqualTo(ChangeStatus.COMPLETED)
        assertThat(result2.status).isEqualTo(ChangeStatus.COMPLETED)
    }
}
```

---

## 9. Saga Test Scenarios Checklist

### Required Test Coverage

| # | Scenario | What to Verify | Stub Configuration |
|---|----------|---------------|-------------------|
| 1 | **Happy Path** | All steps succeed, verify final state is correct | All stubs default (success) |
| 2 | **Step 1 Failure** | No compensation needed (first step failure terminates immediately) | N/A (internal logic failure) |
| 3 | **Step 2 Failure** | Verify Step 1 compensation executes | `paymentPort.shouldFailApprove = true` |
| 4 | **Step 3 (Pivot) Failure** | Step 2 -> Step 1 compensation in reverse order | `taxInvoicePort.shouldFailIssue = true` |
| 5 | **Step 4 Retry Exhaustion** | Enter manual processing path after 3 retries | `notificationPort.shouldFailSend = true` |
| 6 | **Idempotency** | Same result when same request executed twice | All stubs default |
| 7 | **Compensation Failure** | Log and require manual intervention when compensation itself fails | Add `paymentPort.shouldFailCancel = true` |

### Verification Points per Test

- **State verification**: Verify final state saved in repository
- **Interaction verification**: Verify call order/count recorded in stub history
- **Exception verification**: Verify appropriate exception type and message
- **Compensation ordering**: Verify reverse-order compensation execution sequence

### Test Infrastructure Requirements

| Component | Test Double | Source |
|-----------|------------|--------|
| SubscriptionRepository | `spyk(FakeSubscriptionRepository())` | In-memory fake with Mockk spy |
| PaymentPort | `StubPgPort` | testFixtures from ACL module |
| TaxInvoicePort | `StubTaxInvoicePort` | testFixtures from ACL module |
| NotificationPort | `StubNotificationPort` | testFixtures from ACL module |

All stubs follow the pattern defined in B-2:
- `shouldFail{Method}` flag for failure simulation
- `{method}History` list for interaction verification
- `reset()` method for test isolation

---

*Last updated: 2025-05. Based on saga pattern theory (Chris Richardson), Spring event model, and AWS SQS integration patterns.*
