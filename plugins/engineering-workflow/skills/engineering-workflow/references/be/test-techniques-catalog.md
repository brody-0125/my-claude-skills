# Test Techniques Catalog

> Consolidated reference of 7 testing technique categories with code examples for T2 (Test Strategist). Kotlin-first, with Java alternatives where noted.

## Table of Contents

| Section | Line |
|---------|------|
| 1. Unit Testing | ~21 |
| 2. Property-Based Testing | ~108 |
| 3. Integration Testing | ~159 |
| 4. Contract Testing | ~240 |
| 5. Architecture Testing | ~321 |
| 6. Event Testing | ~379 |
| 7. Parameterized Testing | ~467 |
| 8. Test Quality Checklist | ~549 |
| 9. Framework Selection Guide | ~586 |

---

## 1. Unit Testing

### Kotlin: Kotest BehaviorSpec + MockK + Strikt

```kotlin
class OrderServiceTest : BehaviorSpec({
    val orderRepository = mockk<OrderRepository>()
    val sut = OrderService(orderRepository)

    given("a valid order request") {
        val order = Order(id = OrderId(1L), amount = Money.of(5000), status = OrderStatus.PENDING)
        every { orderRepository.save(any()) } returns order

        `when`("the order is placed") {
            val result = sut.placeOrder(CreateOrderCommand(amount = Money.of(5000)))
            then("the order is saved with PENDING status") {
                expectThat(result) {
                    get { status }.isEqualTo(OrderStatus.PENDING)
                    get { amount.value }.isEqualTo(5000L)
                }
                verify(exactly = 1) { orderRepository.save(any()) }
            }
        }
    }
})
```

### Java: JUnit 5 + Mockito + AssertJ

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {
    @Mock OrderRepository orderRepository;
    @InjectMocks OrderService sut;

    @Test
    void placeOrder_savesWithPendingStatus() {
        var order = new Order(1L, Money.of(5000), OrderStatus.PENDING);
        when(orderRepository.save(any())).thenReturn(order);

        var result = sut.placeOrder(new CreateOrderCommand(Money.of(5000)));

        assertThat(result.getStatus()).isEqualTo(OrderStatus.PENDING);
        assertThat(result.getAmount()).isEqualTo(Money.of(5000));
        verify(orderRepository, times(1)).save(any());
    }
}
```

### SUT Pattern with FakeRepository

```kotlin
class OrderCancelUseCaseTest {
    private val fakeRepo = FakeOrderRepository()
    private val repoSpy = spyk(fakeRepo)
    private val sut = OrderCancelUseCase(repoSpy)

    @BeforeEach
    fun setUp() {
        fakeRepo.truncate()
        clearMocks(repoSpy, answers = false) // answers=false preserves FakeRepo behavior
    }

    @Test
    fun `cancel order transitions status to CANCELLED`() {
        val order = fakeRepo.persist(Order(status = OrderStatus.CONFIRMED))
        val result = sut.cancel(order.id)
        expectThat(result) { get { status }.isEqualTo(OrderStatus.CANCELLED) }
        verify(exactly = 1) { repoSpy.save(any()) }
    }
}
```

### Test Double Taxonomy

| Type  | Purpose                            | Verification    |
|-------|------------------------------------|-----------------|
| Dummy | Fill parameter lists, never called | None            |
| Stub  | Return canned answers              | State           |
| Spy   | Record calls on a real object      | State + Interaction |
| Mock  | Pre-programmed expectations        | Interaction     |
| Fake  | Working lightweight implementation | State           |

**Preference**: Stubbing over mocking. State verification is more resilient to refactoring than behavior verification.

---

## 2. Property-Based Testing

### jqwik (JVM)

```java
class MoneyPropertyTest {
    @Property
    void additionIsCommutative(@ForAll @IntRange(min = 0, max = 1_000_000) int a,
                                @ForAll @IntRange(min = 0, max = 1_000_000) int b) {
        assertThat(Money.of(a).add(Money.of(b))).isEqualTo(Money.of(b).add(Money.of(a)));
    }
    @Property void roundtrip(@ForAll("orders") Order order) {
        assertThat(objectMapper.readValue(objectMapper.writeValueAsString(order), Order.class)).isEqualTo(order);
    }
    @Provide Arbitrary<Order> orders() {
        return Combinators.combine(Arbitraries.longs().between(1, 10_000),
            Arbitraries.of(OrderStatus.values()), Arbitraries.integers().between(1, 1_000_000).map(Money::of)
        ).as(Order::new);
    }
}
```

### Kotest PBT

```kotlin
class MoneyPropertySpec : FunSpec({
    test("addition is commutative") {
        checkAll(Arb.positiveLong(max = 1_000_000), Arb.positiveLong(max = 1_000_000)) { a, b ->
            Money.of(a).add(Money.of(b)) shouldBe Money.of(b).add(Money.of(a))
        }
    }
    test("encode-decode roundtrip") {
        checkAll(Arb.bind(Arb.long(1..10_000), Arb.enum<OrderStatus>()) { id, s ->
            Order(OrderId(id), s)
        }) { order -> objectMapper.readValue<Order>(objectMapper.writeValueAsString(order)) shouldBe order }
    }
})
```

### When to Use

| Pattern       | Rule                    | Example                          |
|---------------|-------------------------|----------------------------------|
| Commutativity | `f(a,b) == f(b,a)`     | Addition, set union              |
| Idempotency   | `f(f(x)) == f(x)`      | Deduplication, normalization     |
| Roundtrip     | `decode(encode(x)) == x`| JSON, DTO mapping               |
| Invariant     | Property holds for all  | Balance never negative           |
| Oracle        | Compare to reference    | Optimized sort vs naive sort     |

---

## 3. Integration Testing

### Testcontainers + @DynamicPropertySource

```kotlin
@Testcontainers @SpringBootTest @ActiveProfiles("test")
class OrderRepositoryIntegrationTest {
    companion object {
        @Container @JvmStatic
        val postgres = PostgreSQLContainer("postgres:16-alpine")
            .withDatabaseName("testdb").withUsername("test").withPassword("test")
        @DynamicPropertySource @JvmStatic
        fun props(r: DynamicPropertyRegistry) {
            r.add("spring.datasource.url") { postgres.jdbcUrl }
            r.add("spring.datasource.username") { postgres.username }
            r.add("spring.datasource.password") { postgres.password }
        }
    }
    @Autowired lateinit var orderRepository: OrderRepository

    @Test
    fun `save and retrieve order by id`() {
        val saved = orderRepository.save(Order(amount = Money.of(10_000), status = OrderStatus.PENDING))
        expectThat(orderRepository.findById(saved.id)) { isNotNull(); get { amount }.isEqualTo(Money.of(10_000)) }
    }
}
```

### Spring Boot 3.1+ @ServiceConnection (no @DynamicPropertySource needed)

```kotlin
companion object {
    @Container @ServiceConnection @JvmStatic val mysql = MySQLContainer("mysql:8.0")
    @Container @ServiceConnection @JvmStatic val redis = GenericContainer("redis:7-alpine").withExposedPorts(6379)
}
```

### @DataJpaTest + @WebMvcTest

```kotlin
// Repository layer: @DataJpaTest with real database
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class OrderJpaRepositoryTest {
    @Container @ServiceConnection companion object {
        @JvmStatic val postgres = PostgreSQLContainer("postgres:16-alpine")
    }
    @Autowired lateinit var repository: OrderJpaRepository

    @Test
    fun `find orders by status`() {
        repository.saveAll(listOf(
            OrderEntity(status = "PENDING", amount = 1000),
            OrderEntity(status = "CONFIRMED", amount = 2000),
        ))
        expectThat(repository.findByStatus("PENDING")).hasSize(1)
    }
}

// Controller layer: @WebMvcTest with mocked service
@WebMvcTest(OrderController::class)
class OrderControllerTest {
    @Autowired lateinit var mockMvc: MockMvc
    @MockkBean lateinit var orderService: OrderService

    @Test
    fun `POST orders returns 201`() {
        every { orderService.placeOrder(any()) } returns OrderResponse(id = 42L)
        mockMvc.post("/api/v1/orders") {
            contentType = MediaType.APPLICATION_JSON; content = """{"amount": 5000}"""
        }.andExpect { status { isCreated() } }
    }
}
```

Share containers via `IntegrationTestContext` base class (see `cluster-t-testing.md` section 8).

---

## 4. Contract Testing

### Pact (Consumer-Driven)

```java
// Consumer: defines expected interaction
@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "inventory-service", port = "8080")
class OrderConsumerPactTest {
    @Pact(consumer = "order-service")
    V4Pact reserveStockPact(PactDslWithProvider builder) {
        return builder.given("product SKU-001 has 10 units in stock")
            .uponReceiving("a request to reserve 3 units")
            .path("/api/v1/inventory/reserve").method("POST")
            .headers("Content-Type", "application/json")
            .body(newJsonBody(b -> { b.stringValue("sku","SKU-001"); b.integerType("quantity",3); }).build())
            .willRespondWith().status(200)
            .body(newJsonBody(b -> { b.stringValue("status","RESERVED"); }).build())
            .toPact(V4Pact.class);
    }

    @Test @PactTestFor(pactMethod = "reserveStockPact")
    void reserveStock(MockServer mockServer) {
        assertThat(new InventoryClient(mockServer.getUrl()).reserve("SKU-001", 3).getStatus())
            .isEqualTo("RESERVED");
    }
}

// Provider: verifies against published pacts
@Provider("inventory-service") @PactBroker(url = "${PACT_BROKER_URL}")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class InventoryProviderPactTest {
    @TestTemplate @ExtendWith(PactVerificationInvocationContextProvider.class)
    void verifyPact(PactVerificationContext ctx) { ctx.verifyInteraction(); }

    @State("product SKU-001 has 10 units in stock")
    void setup() { inventoryRepository.save(new Inventory("SKU-001", 10)); }
}
```

### Spring Cloud Contract (Provider-Driven)

```groovy
Contract.make {
    description "should reserve inventory"
    request {
        method POST()
        url "/api/v1/inventory/reserve"
        headers { contentType applicationJson() }
        body(sku: "SKU-001", quantity: 3)
    }
    response {
        status OK()
        headers { contentType applicationJson() }
        body(reservationId: $(anyNonEmptyString()), status: "RESERVED")
    }
}
```

Auto-generates: (1) server-side test verifying provider, (2) client stub JAR via `@AutoConfigureStubRunner`.

### Async Contract Testing (Pact Message)

```java
@ExtendWith(PactConsumerTestExt.class)
class OrderEventConsumerPactTest {
    @Pact(consumer = "shipping-service", provider = "order-service")
    MessagePact orderCreatedEvent(MessagePactBuilder builder) {
        return builder.expectsToReceive("an order created event")
            .withContent(newJsonBody(b -> { b.integerType("orderId",42); b.stringValue("status","CREATED"); }).build())
            .toPact();
    }
    @Test @PactTestFor(pactMethod = "orderCreatedEvent")
    void handle(List<Message> msgs) {
        assertThat(objectMapper.readValue(msgs.get(0).contentsAsString(), OrderCreatedEvent.class)
            .getStatus()).isEqualTo("CREATED");
    }
}
```

---

## 5. Architecture Testing

### ArchUnit

```java
@AnalyzeClasses(packages = "com.example.order", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureRulesTest {
    @ArchTest static final ArchRule domainIndependence =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAnyPackage("..infrastructure..", "..adapter..");

    @ArchTest static final ArchRule onionArch =
        Architectures.onionArchitecture()
            .domainModels("..domain.model..").domainServices("..domain.service..")
            .applicationServices("..application..")
            .adapter("persistence", "..adapter.out.persistence..")
            .adapter("web", "..adapter.in.web..");

    @ArchTest static final ArchRule controllerNaming =
        classes().that().areAnnotatedWith(RestController.class)
            .should().haveSimpleNameEndingWith("Controller");

    @ArchTest static final ArchRule noFieldInjection =
        noFields().should().beAnnotatedWith(Autowired.class)
            .because("Use constructor injection instead");
}
```

### Konsist (Kotlin-Specific)

```kotlin
class KonsistArchitectureTest {
    @Test fun `domain must not depend on Spring`() {
        Konsist.scopeFromPackage("com.example.order.domain").classes()
            .assertFalse { it.hasImport { i -> i.name.startsWith("org.springframework") } }
    }
    @Test fun `domain data classes must be immutable`() {
        Konsist.scopeFromPackage("com.example.order.domain.model").classes()
            .filter { it.hasModifier(KoModifier.DATA) }.properties()
            .assertFalse { it.hasModifier(KoModifier.VAR) }
    }
    @Test fun `use cases have single public execute`() {
        Konsist.scopeFromPackage("com.example.order.application").classes()
            .filter { it.name.endsWith("UseCase") }.assertTrue {
                it.functions(includeNested = false)
                    .count { f -> f.name == "execute" && !f.hasModifier(KoModifier.PRIVATE) } == 1
            }
    }
    @Test fun `entities reside in domain model package`() {
        Konsist.scopeFromProject().classes()
            .filter { it.hasAnnotation { a -> a.name == "Entity" } }
            .assertTrue { it.resideInPackage("..domain.model..") }
    }
}
```

---

## 6. Event Testing

### Embedded Kafka

```kotlin
@SpringBootTest
@EmbeddedKafka(topics = ["order-events"], partitions = 1,
    brokerProperties = ["listeners=PLAINTEXT://localhost:9092"])
class OrderEventPublisherTest {
    @Autowired lateinit var kafkaTemplate: KafkaTemplate<String, String>
    @Autowired lateinit var consumer: EmbeddedKafkaConsumer

    @Test
    fun `publishes order created event`() {
        val event = OrderCreatedEvent(orderId = 42L, status = "CREATED")
        kafkaTemplate.send("order-events", objectMapper.writeValueAsString(event))

        await().atMost(5, SECONDS).untilAsserted {
            expectThat(consumer.getRecords("order-events")).hasSize(1)
        }
    }
}
```

### Spring Application Event Testing

```kotlin
@SpringBootTest
class DomainEventIntegrationTest {
    @Autowired lateinit var orderService: OrderService
    @Autowired lateinit var eventCaptor: TestEventCaptor

    @Test
    fun `order confirmation publishes OrderConfirmedEvent`() {
        val order = orderService.placeOrder(CreateOrderCommand(amount = Money.of(5000)))
        orderService.confirm(order.id)
        await().atMost(3, SECONDS).untilAsserted {
            expectThat(eventCaptor.captured<OrderConfirmedEvent>()).hasSize(1)
        }
    }
}

// Helper: captures @TransactionalEventListener events for test assertions
@Component class TestEventCaptor {
    private val events = CopyOnWriteArrayList<Any>()
    @TransactionalEventListener fun capture(event: Any) { events.add(event) }
    inline fun <reified T> captured(): List<T> = events.filterIsInstance<T>()
}
```

### SQS Testing with LocalStack

```kotlin
@SpringBootTest
class SqsEventHandlerTest {
    companion object {
        @Container @JvmStatic
        val localStack = LocalStackContainer(DockerImageName.parse("localstack/localstack:3"))
            .withServices(LocalStackContainer.Service.SQS)
        @DynamicPropertySource @JvmStatic
        fun configure(registry: DynamicPropertyRegistry) {
            registry.add("cloud.aws.sqs.endpoint") {
                localStack.getEndpointOverride(LocalStackContainer.Service.SQS).toString()
            }
        }
    }
    @Autowired lateinit var sqsTemplate: SqsTemplate

    @Test
    fun `processes payment completed SQS message`() {
        sqsTemplate.send("payment-completed-queue",
            objectMapper.writeValueAsString(PaymentCompletedMessage(orderId = 42L)))
        await().atMost(10, SECONDS).untilAsserted {
            expectThat(orderRepository.findById(OrderId(42L))!!.status).isEqualTo(OrderStatus.PAID)
        }
    }
}
```

### Awaitility: Always Use Instead of Thread.sleep

```kotlin
await().atMost(5, SECONDS).untilAsserted { expectThat(repository.findById(id)).isNotNull() }
await().atMost(10, SECONDS).pollInterval(500, MILLISECONDS).untilAsserted { ... }
```

---

## 7. Parameterized Testing

### @ValueSource / @EnumSource / @CsvSource

```kotlin
@ParameterizedTest @ValueSource(strings = ["PENDING", "CONFIRMED", "SHIPPED"])
fun `non-terminal statuses allow cancellation`(statusName: String) {
    expectThat(Order(status = OrderStatus.valueOf(statusName)).canCancel()).isTrue()
}

@ParameterizedTest @EnumSource(OrderStatus::class)
fun `all statuses have a display label`(status: OrderStatus) {
    expectThat(status.displayLabel).isNotBlank()
}

@ParameterizedTest @EnumSource(OrderStatus::class, names = ["CANCELLED","REFUNDED"], mode = EnumSource.Mode.EXCLUDE)
fun `non-terminal statuses can transition`(status: OrderStatus) {
    expectThat(status.canTransition()).isTrue()
}

@ParameterizedTest @CsvSource("1000,0,1000", "1000,10,900", "5000,50,2500", "10000,100,0")
fun `discount calculation`(price: Long, discountPct: Int, expected: Long) {
    expectThat(PriceCalculator.applyDiscount(Money.of(price), discountPct)).isEqualTo(Money.of(expected))
}
```

### @MethodSource

```kotlin
companion object {
    @JvmStatic fun invalidCommands(): Stream<Arguments> = Stream.of(
        Arguments.of(CreateOrderCommand(amount = Money.of(-1)), "negative amount"),
        Arguments.of(CreateOrderCommand(amount = Money.of(0)), "zero amount"),
        Arguments.of(CreateOrderCommand(items = emptyList()), "no items"),
    )
}
@ParameterizedTest(name = "rejects: {1}") @MethodSource("invalidCommands")
fun `invalid commands are rejected`(cmd: CreateOrderCommand, reason: String) {
    assertThrows<ValidationException> { orderService.placeOrder(cmd) }
}
```

### Boundary Value Analysis (BVA) with @MethodSource

Test boundaries systematically: min, min+1, typical, max-1, max, below-min, above-max.

```kotlin
companion object {
    @JvmStatic
    fun boundaryAmounts(): Stream<Arguments> = Stream.of(
        Arguments.of(1L, true, "min"),       Arguments.of(2L, true, "min+1"),
        Arguments.of(50_000L, true, "mid"),  Arguments.of(999_999L, true, "max-1"),
        Arguments.of(1_000_000L, true, "max"), Arguments.of(0L, false, "below min"),
        Arguments.of(1_000_001L, false, "above max"),
    )
}
@ParameterizedTest(name = "amount {0}: valid={1} ({2})")
@MethodSource("boundaryAmounts")
fun `amount boundary validation`(amount: Long, valid: Boolean, desc: String) {
    expectThat(Money.isValid(amount)).isEqualTo(valid)
}
```

### Sealed Class Exhaustive Testing with @MethodSource

```kotlin
companion object {
    @JvmStatic
    fun allPaymentMethods(): Stream<Arguments> = Stream.of(
        Arguments.of(PaymentMethod.CreditCard("4111111111111111", "12/28"), "CARD"),
        Arguments.of(PaymentMethod.BankTransfer("123-456-789"), "BANK"),
        Arguments.of(PaymentMethod.Cash, "CASH"),
    )
}
@ParameterizedTest @MethodSource("allPaymentMethods")
fun `all payment methods produce a receipt`(method: PaymentMethod, expectedType: String) {
    expectThat(paymentProcessor.process(method).type).isEqualTo(expectedType)
}
```

---

## 8. Test Quality Checklist

### Naming

- Describe **behavior**, not method name: `cancel throws exception for shipped order` (GOOD) vs `testCancel()` (BAD).

### Assertion Quality

- No tautological assertions. Assert domain properties, not implementation details.
- GOOD: `expectThat(result) { get { status }.isEqualTo(CONFIRMED) }`
- One logical assertion per test (multiple `get {}` on same subject is fine).

### Test Isolation

- No shared mutable state. Each test sets up own data. Never rely on execution order.

### Determinism

| Forbidden                        | Replacement                              |
|----------------------------------|------------------------------------------|
| `Thread.sleep(N)`                | `Awaitility.await().atMost(...)`         |
| `System.currentTimeMillis()`     | Inject `Clock`, use `clock.instant()`    |
| `LocalDateTime.now()`            | `LocalDateTime.now(clock)`               |
| `Random().nextInt()`             | `Random(seed)` or Fixture Monkey         |
| `UUID.randomUUID()` in asserts   | Inject `IdGenerator` interface           |

### Structure

- Follow AAA (Arrange-Act-Assert) or GWT (Given-When-Then) consistently.
- Single act (invocation) per test. No side effects in assert section.

### Mock Rules

- Mock **interfaces**, not concrete classes. Never mock the SUT or value objects.
- Prefer `spyk(fakeImpl)` over `mockk<Interface>()` when a Fake is available.
- More than 5 `every {}` blocks suggests you need a Fake instead.

## 9. Framework Selection Guide

### Decision Matrix

| Layer                  | Technique                | Primary Framework                  | Alternative                       |
|------------------------|--------------------------|------------------------------------|-----------------------------------|
| Domain (Core Logic)    | Property-based + Unit    | jqwik / Kotest PBT + MockK        | JUnit 5 + Mockito                 |
| Service (Application)  | BDD-style Unit           | Kotest BehaviorSpec + MockK        | JUnit 5 + Mockito                 |
| Repository (Infra)     | Integration              | Testcontainers + @DataJpaTest      | H2 (fallback only)               |
| Controller (API)       | Contract + MockMvc       | Spring Cloud Contract / Pact       | @WebMvcTest + MockK               |
| Event Handler          | Embedded broker          | EmbeddedKafka / LocalStack         | Spring ApplicationEvent capture   |
| Architecture Rules     | Architecture test        | ArchUnit / Konsist                 | Manual review (not recommended)   |
| Cross-service Contract | Consumer/Provider        | Pact + Pact Broker                 | Spring Cloud Contract stubs       |
| Edge Cases / Boundaries| Parameterized            | @ParameterizedTest + @MethodSource | Kotest data-driven testing        |

### When to Use Each

- **Property-Based**: Mathematical invariants, serialization roundtrips, unknown edge case discovery.
- **Contract**: Multi-team consumer/provider, API backward compatibility, async event boundaries.
- **Architecture**: Hexagonal/onion dependency enforcement, naming/annotation conventions at scale.
- **Parameterized**: Same logic across many inputs, systematic BVA, enum exhaustive checks.

Typical pyramid ratio: Unit 70-80%, Integration 15-25%, Contract 3-5%, Architecture 2-3%.
