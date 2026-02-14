# Test Generation Patterns Reference

> Patterns and templates for the T3 (Test Generator) agent. Covers focal context extraction,
> type-driven test case derivation, structural templates, pattern matching, extension rules,
> fixture generation, large scope processing, and anti-patterns to avoid.

---

## 1. Focal Context Injection

Focal context injection extracts the **minimal context** needed to generate a test for a given
target. Keep injected context under ~750 tokens per target -- only what is needed to produce
correct, compilable test code.

**Include:**

| Category | Example |
|----------|---------|
| Target class signature | Public methods, constructor parameters, visibility modifiers |
| Parameter type definitions | Data classes, value objects used as method inputs |
| Return type definitions | Result types, sealed response classes |
| Direct dependency interfaces | Port interfaces, Repository interfaces injected via constructor |
| Relevant domain constants | Enum values, companion object constants, validation thresholds |

**Exclude:**

| Category | Reason |
|----------|--------|
| Implementation details of dependencies | Adapter logic is irrelevant to unit test generation |
| Unrelated classes in same package | Adds noise without improving test accuracy |
| Comments and documentation | Not needed for structural test generation |
| Transitive dependencies | Only direct constructor-injected dependencies matter |
| Framework configuration | Spring config, bean definitions, YAML properties |

### Example: Focal Context for CancelOrderUseCase

```kotlin
// Target class signature
class CancelOrderUseCase(
    private val orderRepository: OrderRepository,
    private val paymentPort: PaymentPort,
    private val notificationPort: NotificationPort
) {
    fun execute(command: CancelOrderCommand): CancelOrderResult
}

// Parameter type
data class CancelOrderCommand(
    val orderId: OrderId, val reason: CancelReason, val requestedBy: UserId
)

// Return type (sealed -- drives test case count)
sealed class CancelOrderResult {
    data class Success(val order: Order) : CancelOrderResult()
    data class AlreadyCancelled(val orderId: OrderId) : CancelOrderResult()
    data class NotCancellable(val currentStatus: OrderStatus) : CancelOrderResult()
}

// Direct dependency interfaces
interface OrderRepository {
    fun findById(id: OrderId): Order?
    fun save(order: Order): Order
}
interface PaymentPort { fun cancelPayment(paymentKey: String): CancelPaymentResult }
interface NotificationPort { fun sendCancellationNotice(orderId: OrderId, userId: UserId) }

// Relevant domain enums
enum class CancelReason { CUSTOMER_REQUEST, OUT_OF_STOCK, PAYMENT_FAILURE }
enum class OrderStatus { CREATED, CONFIRMED, SHIPPED, DELIVERED, CANCELLED }
// ~650 tokens total
```

---

## 2. Type-Driven Test Case Derivation

### Sealed Classes: One Test per Subtype

When a method returns a sealed class, generate one test case for each concrete subtype.

```kotlin
// CancelOrderResult has 3 subtypes --> 3 test methods
@Test fun `execute - cancels order successfully`() { /* assert: Success */ }
@Test fun `execute - returns AlreadyCancelled when previously cancelled`() { /* assert: AlreadyCancelled */ }
@Test fun `execute - returns NotCancellable when order is shipped`() { /* assert: NotCancellable */ }
```

### Enum Types: @EnumSource for Exhaustive Coverage

```kotlin
@ParameterizedTest
@EnumSource(CancelReason::class)
fun `execute - handles all cancel reasons`(reason: CancelReason) {
    val command = fixture.giveMeBuilder<CancelOrderCommand>()
        .setExp(CancelOrderCommand::reason, reason).sample()
    val result = sut.execute(command)
    expectThat(result).isA<CancelOrderResult.Success>()
}
```

### Nullable Types: Both Null and Non-Null Paths

```kotlin
// For fun findById(id: OrderId): Order?  --> 2 test cases
@Test fun `execute - throws when order not found`() { /* repo returns null */ }
@Test fun `execute - processes existing order`() { /* repo returns Order */ }
```

### Validation Annotations: Boundary Cases

| Annotation | Test Cases |
|------------|------------|
| `@Min(0)` | -1 (fail), 0 (pass), 1 (pass) |
| `@Max(100)` | 99 (pass), 100 (pass), 101 (fail) |
| `@Size(min=1, max=100)` | empty (fail), 1 char (pass), 100 chars (pass), 101 chars (fail) |
| `@NotBlank` | null (fail), empty (fail), blank (fail), non-blank (pass) |
| `@Pattern(regexp)` | matching (pass), non-matching (fail) |
| `@Email` | valid (pass), invalid format (fail), empty (fail) |

```kotlin
// For @Min(0) on Order::quantity
@Test fun `validate - quantity -1 fails`() { /* boundary below */ }
@Test fun `validate - quantity 0 passes`() { /* exact boundary */ }
@Test fun `validate - quantity 1 passes`() { /* boundary above */ }
```

### Generic Types: Test with Concrete Parameters

```kotlin
// For interface ResultHandler<T : DomainEvent>  --> use concrete type
@Test
fun `handle - processes OrderCancelledEvent correctly`() {
    val handler: ResultHandler<OrderCancelledEvent> = OrderCancelledHandler()
    val event = fixture.giveMeOne<OrderCancelledEvent>()
    handler.handle(event)
}
```

### Collections: Empty, Single, Multiple

```kotlin
// For fun findByStatus(status: OrderStatus): List<Order>
@Test fun `findByStatus - returns empty list when no orders match`() { ... }
@Test fun `findByStatus - returns single order`() { ... }
@Test fun `findByStatus - returns multiple orders`() { ... }
```

---

## 3. Test Structure Templates

### Kotlin -- Kotest BehaviorSpec

```kotlin
class CancelOrderUseCaseTest : BehaviorSpec({
    val orderRepository = FakeOrderRepository()
    val paymentPort = mockk<PaymentPort>()
    val notificationPort = mockk<NotificationPort>(relaxed = true)
    val sut = CancelOrderUseCase(orderRepository, paymentPort, notificationPort)
    val fixture = FixtureMonkey.builder().plugin(KotlinPlugin()).build()

    beforeEach {
        orderRepository.truncate()
        clearMocks(paymentPort, notificationPort, answers = false)
    }

    Given("a confirmed order exists") {
        val order = fixture.giveMeBuilder<Order>()
            .setExp(Order::status, OrderStatus.CONFIRMED).sample()
        orderRepository.persist(order)
        every { paymentPort.cancelPayment(any()) } returns CancelPaymentResult.Success

        When("cancel is requested") {
            val result = sut.execute(CancelOrderCommand(order.id, CancelReason.CUSTOMER_REQUEST, UserId(1L)))
            Then("order is cancelled successfully") {
                expectThat(result).isA<CancelOrderResult.Success>()
                expectThat(orderRepository.getOrNull(order.id)!!.status).isEqualTo(OrderStatus.CANCELLED)
            }
            Then("payment cancellation is triggered") {
                verify(exactly = 1) { paymentPort.cancelPayment(any()) }
            }
        }
    }
})
```

### Kotlin -- Flat Style with Backtick Names

```kotlin
class CancelOrderUseCaseTest {
    private val orderRepository = FakeOrderRepository()
    private val paymentPort = mockk<PaymentPort>()
    private val notificationPort = mockk<NotificationPort>(relaxed = true)
    private val sut = CancelOrderUseCase(orderRepository, paymentPort, notificationPort)
    private val fixture = FixtureMonkey.builder().plugin(KotlinPlugin()).build()

    @BeforeEach
    fun setUp() {
        orderRepository.truncate()
        clearMocks(paymentPort, notificationPort, answers = false)
    }

    @Test
    fun `execute - cancels confirmed order successfully`() {
        // given
        val order = fixture.giveMeBuilder<Order>()
            .setExp(Order::status, OrderStatus.CONFIRMED).sample()
        orderRepository.persist(order)
        every { paymentPort.cancelPayment(any()) } returns CancelPaymentResult.Success
        // when
        val result = sut.execute(CancelOrderCommand(order.id, CancelReason.CUSTOMER_REQUEST, UserId(1L)))
        // then
        expectThat(result).isA<CancelOrderResult.Success>()
        verify(exactly = 1) { paymentPort.cancelPayment(any()) }
    }
}
```

### Java -- JUnit 5 + Mockito

```java
@ExtendWith(MockitoExtension.class)
class CancelOrderUseCaseTest {
    @Mock OrderRepository orderRepository;
    @Mock PaymentPort paymentPort;
    @Mock NotificationPort notificationPort;
    @InjectMocks CancelOrderUseCase sut;

    @Test @DisplayName("Cancels a confirmed order and triggers payment refund")
    void shouldCancelConfirmedOrder() {
        // given
        var order = Order.builder().id(new OrderId(1L)).status(OrderStatus.CONFIRMED).build();
        when(orderRepository.findById(any())).thenReturn(Optional.of(order));
        when(paymentPort.cancelPayment(anyString())).thenReturn(CancelPaymentResult.success());
        // when
        var command = new CancelOrderCommand(new OrderId(1L), CancelReason.CUSTOMER_REQUEST, new UserId(1L));
        var result = sut.execute(command);
        // then
        assertThat(result).isInstanceOf(CancelOrderResult.Success.class);
        verify(paymentPort, times(1)).cancelPayment(anyString());
    }
}
```

---

## 4. Pattern Matching (Project Pattern Learning)

Scan existing test files (up to 10 representative files) to extract the project's testing
conventions. File selection priority: same module > similar use cases > related modules > any tests.

| Pattern Dimension | Possible Values | Detection Method |
|-------------------|-----------------|------------------|
| Naming convention | Backtick, camelCase, `@DisplayName` | Regex scan for method declarations |
| Assertion library | Strikt, AssertJ, Kotest matchers, JUnit assertions | Import statement scan |
| Mock framework | MockK, Mockito, manual fakes | Import statement scan |
| Fixture strategy | FixtureMonkey, manual builders, object mothers | Class reference scan |
| Test structure | BehaviorSpec, FunSpec, `@Nested`, flat `@Test` | Superclass / annotation scan |
| Setup pattern | `@BeforeEach`, `init {}`, `beforeEach {}` | Method annotation scan |
| Verification style | `verify {}`, `verify()`, state-based only | Call pattern scan |

### Application Rules

```
IF existing tests found:
    Extract patterns from majority style (>50% of scanned files)
    Apply ALL extracted patterns to generated tests
    Log which patterns were detected and applied
ELSE (no existing tests):
    Fallback defaults:
      Naming: backtick  |  Assertions: Strikt  |  Mocking: MockK + FakeRepository + spyk
      Fixtures: FixtureMonkey + KotlinPlugin  |  Structure: flat @Test  |  Setup: @BeforeEach
```

Generated tests MUST match the detected project style. A test that uses AssertJ in a
Strikt-based project is a defect, even if the assertions are logically correct.

---

## 5. Existing Test Extension Rules

**NEVER overwrite existing test files.** Existing tests represent validated, reviewed code.

### Extension Workflow

1. **Read** existing test file completely -- parse test method names, covered scenarios, style
2. **Map coverage** -- which target methods and input combinations are already tested
3. **Generate ONLY missing** test cases -- compare focal context paths against coverage matrix
4. **Append** new methods at end of class/spec with a blank line separator
5. **Match style exactly** -- naming convention, assertion library, fixture patterns, comment style

### New Test File Creation

When no existing test file exists for the target class:

1. Mirror directory: `src/main/kotlin/.../CancelOrderUseCase.kt` -> `src/test/kotlin/.../CancelOrderUseCaseTest.kt`
2. Same package declaration
3. Class name: `{TargetClassName}Test`
4. Imports based on detected project patterns

---

## 6. Test Fixture Generation

### FixtureMonkey Patterns

```kotlin
companion object {
    private val fixture = FixtureMonkey.builder().plugin(KotlinPlugin()).build()
}

val order = fixture.giveMeOne<Order>()                                    // random valid object
val confirmed = fixture.giveMeBuilder<Order>()
    .setExp(Order::status, OrderStatus.CONFIRMED)
    .setExp(Order::totalAmount, Money.of(50_000)).sample()                // customized
val items = fixture.giveMeBuilder<OrderItem>()
    .setExp(OrderItem::orderId, orderId).sampleList(3)                    // collection
val valid = fixture.giveMeBuilder<Order>()
    .setPostCondition { it.totalAmount.value > 0 }.sample()              // post-condition
```

### FakeRepository Pattern

```kotlin
abstract class BaseFakeRepository<T : Any, ID : Any>(
    private val idExtractor: (T) -> ID,
    private val idSetter: (T, ID) -> T,
    private val idGenerator: () -> ID
) {
    protected val store: MutableMap<ID, T> = ConcurrentHashMap()
    private val sequence = AtomicLong(1L)

    fun persist(entity: T): T {
        val id = idExtractor(entity)
        return if (id == null || !store.containsKey(id)) {
            val newId = idGenerator()
            val withId = idSetter(entity, newId)
            store[newId] = withId; withId
        } else { store[id] = entity; entity }
    }
    fun getOrNull(id: ID): T? = store[id]
    fun getAll(): List<T> = store.values.toList()
    fun truncate() { store.clear(); sequence.set(1L) }
    protected fun nextId(): Long = sequence.getAndIncrement()
}
```

- `ConcurrentHashMap` for thread safety in parallel test execution
- `AtomicLong` for deterministic, auto-incrementing ID generation
- `truncate()` resets both store and sequence -- call in `@BeforeEach`
- Implements Core Port interface directly -- no adapter layer in tests

### Stub Patterns for External Ports

```kotlin
class StubPaymentPort : PaymentPort {
    var shouldFail = false
    private val _history = mutableListOf<PaymentRequest>()
    val history: List<PaymentRequest> get() = _history.toList()

    override fun requestPayment(request: PaymentRequest): PaymentResult {
        _history.add(request)
        return if (shouldFail) PaymentResult.failure("stub-error")
        else PaymentResult.success(paymentKey = "test-key-${_history.size}", amount = request.amount)
    }
    override fun cancelPayment(paymentKey: String): CancelPaymentResult =
        if (shouldFail) CancelPaymentResult.Failure("stub-cancel-error")
        else CancelPaymentResult.Success

    fun reset() { shouldFail = false; _history.clear() }
}
```

- `shouldFail` flag to toggle success/failure scenarios per test
- `history` list for verifying interactions without mock framework
- `reset()` for cleanup in `@BeforeEach`
- Immutable copy from `history` getter prevents test interference

---

## 7. Large Scope Processing

### Sequential Strategy (Default, < 5 Targets)

```
For each target:
  1. Extract focal context
  2. Detect project patterns (cached after first)
  3. Check for existing test file
  4. Existing: extend with missing cases | New: create full test file
  5. Validate generated test compiles (syntax check)
```

### Parallel Strategy (> 5 Targets, Agent Teams)

```
1. Split into batches of 3-5, group by module/bounded context
2. Each sub-agent receives: target list, focal contexts, detected patterns
3. Merge results: deduplicate overlapping fixtures/helpers, resolve import conflicts
4. Final validation: syntax check, no duplicate test method names
```

### Gap-Targeted Generation (Loop 2+)

When T4 (Coverage Analyzer) reports gaps:

```
Input:  Uncovered branches, surviving mutants, missing edge cases from T4
Process:
  1. Extract focal context around uncovered code
  2. Determine input to exercise uncovered branch
  3. Generate one focused test case per gap
  4. Name clearly: `execute - covers branch when amount is zero`
Output: Targeted test methods appended to existing test files
Stop:   Coverage target reached or no more actionable gaps
```

---

## 8. Anti-Patterns to Avoid

### No Logic in Tests

```kotlin
// BAD: if/else in test
@Test fun `execute - handles order`() {
    val result = sut.execute(command)
    if (result is Success) { expectThat(result.order).isNotNull() }  // NEVER
    else { fail("Expected success") }
}
// GOOD: direct assertion
@Test fun `execute - cancels order successfully`() {
    expectThat(sut.execute(command)).isA<CancelOrderResult.Success>()
}
```

### No Mocking the SUT

```kotlin
// BAD
val sut = mockk<CancelOrderUseCase>()
every { sut.execute(any()) } returns Success(order)
// GOOD: mock dependencies only
val sut = CancelOrderUseCase(fakeRepo, mockPaymentPort, mockNotificationPort)
```

### No Testing Private Methods

```kotlin
// BAD: reflection to access private methods
val method = CancelOrderUseCase::class.java.getDeclaredMethod("validateOrder", Order::class.java)
method.isAccessible = true; method.invoke(sut, order)
// GOOD: test through public API
expectThat(sut.execute(commandThatTriggersValidation)).isA<CancelOrderResult.NotCancellable>()
```

### No Over-Mocking

```kotlin
// BAD: mock everything
val orderRepo = mockk<OrderRepository>()
every { orderRepo.findById(any()) } returns order
every { orderRepo.save(any()) } returns order
// GOOD: FakeRepository for data, mock only external ports
val orderRepo = FakeOrderRepository()
orderRepo.persist(order)
```

### No Ignored Return Values

```kotlin
// BAD: ignoring result, only verifying interaction
sut.execute(command)
verify { repo.save(any()) }
// GOOD: assert on returned value
val result = sut.execute(command)
expectThat(result).isA<CancelOrderResult.Success>()
```

### No Magic Numbers Without Context

```kotlin
// BAD: unexplained literals
val command = CancelOrderCommand(OrderId(42L), CancelReason.CUSTOMER_REQUEST, UserId(99L))
// GOOD: use fixtures
val order = fixture.giveMeBuilder<Order>().setExp(Order::status, OrderStatus.CONFIRMED).sample()
val command = CancelOrderCommand(order.id, CancelReason.CUSTOMER_REQUEST, requesterId)
```

### No Shared Mutable State

```kotlin
// BAD: companion object with mutable state shared across tests
companion object { val sharedOrder = Order(...) }
// GOOD: fresh state per test
@BeforeEach fun setUp() { orderRepository.truncate(); clearMocks(paymentPort, answers = false) }
```

### No Test Ordering Dependencies

```kotlin
// BAD: test B depends on test A's side effects
@Test @Order(1) fun `create order`() { sut.create(command) }
@Test @Order(2) fun `cancel order`() { sut.cancel(orderId) }  // depends on test 1
// GOOD: self-contained
@Test fun `cancel order - succeeds for confirmed order`() {
    val order = fixture.giveMeBuilder<Order>().setExp(Order::status, OrderStatus.CONFIRMED).sample()
    orderRepository.persist(order)
    expectThat(sut.execute(CancelOrderCommand(order.id, CancelReason.CUSTOMER_REQUEST, userId)))
        .isA<CancelOrderResult.Success>()
}
```

### No Thread.sleep for Async

```kotlin
// BAD
sut.execute(command); Thread.sleep(2000); verify { eventPublisher.publish(any()) }
// GOOD: Awaitility
sut.execute(command)
await().atMost(Duration.ofSeconds(5)).untilAsserted { verify { eventPublisher.publish(any()) } }
```

---

*Reference for agent T3 (Test Generator). Source: v5.0 Micro-Agent Architecture, Testing Cluster.*
