# Unit Testing Guide

## Test Location
- `src/test/kotlin/`: Unit tests
- `src/testFixtures/kotlin/`: Shared test utilities, Stub/Fake implementations

---

## Test Double Philosophy

### Test Double Taxonomy

| Type | Purpose | Characteristics | When to Use |
|------|---------|----------------|-------------|
| **Dummy** | Fill parameter slots | No behavior, never called | Constructor/method requires a param you don't care about |
| **Stub** | Return predefined state | In-memory storage, deterministic | Repository, external service with predictable responses |
| **Spy** | Record interactions | Tracks calls + allows assertions on them | Side-effect verification (email sent, event published) |
| **Mock** | Verify behavior | Expects specific calls in specific order | Exactly-once guarantees, unexpected call prevention |
| **Fake** | Simplified implementation | Working logic with shortcuts | In-memory DB, lightweight HTTP server |

### Stubbing > Mocking

**State Verification (Stub)** is preferred over **Behavior Verification (Mock)**.

| Aspect | Stub (State Verification) | Mock (Behavior Verification) |
|--------|--------------------------|------------------------------|
| Asserts on | Return values, stored state | Method calls, call order |
| Coupling to SUT | Low — doesn't depend on implementation | High — depends on internal call sequence |
| Refactoring resilience | Strong — internals can change freely | Fragile — breaks when call order changes |
| Test readability | "given state → assert result" | "verify that X was called with Y" |

**Guideline:**
- Default to **Stub/Fake** for dependencies (Repository, external Port)
- Use **Spy** when you need to verify side-effects (email sent, event published)
- Use **Mock** only when behavior verification is essential (exactly-once, unexpected call prevention)

### When Mock is Appropriate

- Verifying a side-effect happened **exactly once** (e.g., payment gateway charge)
- Ensuring a method was **never called** in certain scenarios
- Verifying **call arguments** matter for correctness (not just the result)

---

## Test Structure

### SUT (System Under Test) Pattern

```kotlin
class OrderServiceTest {
    // Dependencies — Stub/Fake for state, Spy for side-effects
    private val orderRepository = FakeOrderRepository()
    private val paymentPort = PaymentPortStub()
    private val eventPublisher = EventPublisherSpy()

    // SUT
    private val sut = OrderService(
        orderRepository,
        paymentPort,
        eventPublisher,
    )

    @BeforeEach
    fun init() {
        orderRepository.clear()
        eventPublisher.clear()
    }

    @Test
    fun `create - saves order and publishes event`() {
        val command = OrderCreateCommand(customerId = 1L)

        val actual = sut.create(command)

        // State verification — assert on result and stored data
        expectThat(actual) {
            get { customerId } isEqualTo 1L
            get { status } isEqualTo OrderStatus.CREATED
        }
        expectThat(orderRepository.findById(actual.id)).isNotNull()
        expectThat(eventPublisher.publishedCount) isEqualTo 1
    }
}
```

**When mock is still needed** (e.g., external port with behavior contract):

```kotlin
class OrderServiceTest {
    private val orderRepository = FakeOrderRepository()
    private val externalPort = mockk<ExternalServicePort>()

    private val sut = OrderService(orderRepository, externalPort)

    @Test
    fun `execute - calls external service exactly once`() {
        every { externalPort.call(any()) } returns Result.success()

        sut.execute(command)

        verify(exactly = 1) { externalPort.call(any()) }
    }
}
```

---

## MockK Usage

### Creating Mocks
```kotlin
// Full mock — only when behavior verification is needed
private val externalPort = mockk<ExternalServicePort>()

// Spy on a Fake — when you need both state and call tracking
private val repository = spyk(FakeEntityRepository())
```

### Stubbing
```kotlin
every { externalPort.call(any()) } returns result
every { repository.getById(1L) } returns entity
every { port.send(any(), any()) } just Runs
```

### Verification
```kotlin
verify(exactly = 1) {
    repository.append(any())
    eventPublisher.publish(DomainEventType.ENTITY_CREATED, any())
}

verify { repository wasNot Called }
```

### Reset
```kotlin
@BeforeEach
fun init() {
    clearMocks(repository)
}
```

---

## Strikt Assertions

### Basic Assertions
```kotlin
expectThat(actual) isEqualTo expected
expectThat(result).isNull()
expectThat(result).isNotNull()
```

### Block-style Assertions
```kotlin
expectThat(entity) {
    get { id } isEqualTo 1L
    get { workspaceId } isEqualTo 100L
    get { status } isEqualTo Status.COMPLETE
}
```

### Collection Assertions
```kotlin
expectThat(items) {
    hasSize(3)
    withFirst {
        get { amount } isEqualTo 10000
    }
    withElementAt(1) {
        get { name } isEqualTo "item2"
    }
}
```

### Exception Assertions
```kotlin
expectThrows<ApplicationBusinessException> {
    sut.execute(invalidCommand)
}.and {
    get { businessCause } isEqualTo ErrorCodeBook.INVALID_INPUT
}
```

### Type Assertions
```kotlin
expectThat(result).isA<ExpectedType>()
```

---

## Test Fixtures

### FixtureMonkey
```kotlin
// Single object
val entity = fixture<Entity>()

// Customized
val entity = fixture<Entity> {
    set(Entity::id, 0L)
    set(Entity::workspaceId, 1L)
}

// List
val entities = fixtures<Entity>(5)
```

### Fake Repository Pattern
```kotlin
// Defined in testFixtures
abstract class BaseFakeRepository<V : Any> {
    private val datasource = ConcurrentHashMap<Long, V>()
    private val idCounter = AtomicLong(1)

    protected abstract fun getId(element: V): Long
    protected abstract fun withId(element: V, id: Long): V

    fun save(element: V): V {
        val id = getId(element).takeIf { it != 0L } ?: idCounter.getAndIncrement()
        val saved = withId(element, id)
        datasource[id] = saved
        return saved
    }

    fun findById(id: Long): V? = datasource[id]
    fun findAll(): List<V> = datasource.values.toList()
    fun clear() { datasource.clear() }
}

// Concrete Fake for a specific domain
class FakeOrderRepository : BaseFakeRepository<Order>(), OrderRepository {
    override fun getId(element: Order) = element.id
    override fun withId(element: Order, id: Long) = element.copy(id = id)

    override fun save(order: Order): Order = super.save(order)
    override fun findById(id: Long): Order? = super.findById(id)
    override fun findByCustomerId(customerId: Long): List<Order> {
        return findAll().filter { it.customerId == customerId }
    }
}
```

### Reusable Stub Classes

```kotlin
// testFixtures — Port Stub (with failure simulation)
class PaymentPortStub(
    private val shouldFail: Boolean = false,
) : PaymentPort {
    private val payments = mutableListOf<Payment>()

    override fun charge(payment: Payment): PaymentResult {
        if (shouldFail) throw PaymentException("Simulated failure")
        payments.add(payment)
        return PaymentResult.success(payment.amount)
    }

    val chargedPayments: List<Payment> get() = payments.toList()
}

// testFixtures — Spy (side-effect recording)
class EventPublisherSpy : DomainEventPublisher {
    private val events = mutableListOf<DomainEvent>()

    override fun publish(event: DomainEvent) {
        events.add(event)
    }

    val publishedEvents: List<DomainEvent> get() = events.toList()
    val publishedCount: Int get() = events.size
    fun clear() { events.clear() }
}
```

### Dummy/Stub Objects
```kotlin
// Dummy (does nothing)
fun domainEventPublisherDummy() = object : DomainEventPublisher {
    override fun publish(event: DomainEvent) {
        // Do Nothing
    }
}
```

### testFixtures Module Structure

```
src/
  main/kotlin/              # Production code
  test/kotlin/              # Unit tests
  testFixtures/kotlin/
    ├── repository/
    │   ├── BaseFakeRepository.kt
    │   └── FakeOrderRepository.kt
    ├── stub/
    │   └── PaymentPortStub.kt
    └── spy/
        └── EventPublisherSpy.kt
```

`build.gradle.kts`:
```kotlin
plugins {
    `java-test-fixtures`
}
```

---

## Naming Conventions

### Test Class
- Production class name + `Test` suffix
- Example: `OrderCreationService` -> `OrderCreationServiceTest`

### Test Method
```kotlin
// Kotlin backtick style (recommended)
@Test
fun `execute - happy path`() { }

@Test
fun `execute - should throw exception when invalid input`() { }

// Using DisplayName
@Test
@DisplayName("execute - returns existing entity when duplicate data exists")
fun test_return_existing_when_duplicate() { }
```

### Test Method Name Length Limit
- Maximum **120 bytes** (including backticks)
- Automatically validated during ktlintCheck

### No Inner Class Usage
- Do not use `@Nested` inner classes
- Causes file path length limit issues in the build pipeline
- Write test cases in a flat structure, differentiated by method name prefix

```kotlin
// Do not use inner class
@Nested
inner class WhenValidInput {
    @Test
    fun `returns success`() { }
}

// Flat structure with prefix
@Test
fun `execute - returns success when valid input`() { }

@Test
fun `execute - throws exception when invalid input`() { }
```

---

## Parameterized Tests

```kotlin
@ParameterizedTest
@ValueSource(strings = ["TYPE_A", "TYPE_B"])
@DisplayName("resolve - per-type processing test")
fun test_type_resolution(rawType: String) {
    val type = EntityType.valueOf(rawType)
    val result = TypeResolver.resolve(type)
    expectThat(result) isEqualTo type
}
```

---

## Setup/Teardown

```kotlin
@BeforeEach
fun init() {
    repository.clear()
    eventPublisher.clear()
}

@AfterEach
fun tearDown() {
    repository.clear()
}
```
