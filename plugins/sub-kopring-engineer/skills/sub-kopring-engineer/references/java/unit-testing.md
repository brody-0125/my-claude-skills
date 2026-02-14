# Java Unit Testing Guide

> Java unit testing guide that corresponds 1:1 with the Kotlin unit-testing.md.
> Loaded when the profile language is java or mixed.

## Test Location

- `src/test/java/`: Unit tests
- `src/testFixtures/java/`: Shared test utilities, Stub/Fake implementations

---

## Test Double Philosophy

> Taxonomy, Stubbing > Mocking, and When Mock is Appropriate — see [unit-testing.md § Test Double Philosophy](./unit-testing.md#test-double-philosophy). The same principles apply to Java.

---

## Test Structure

### SUT (System Under Test) Pattern

```java
class OrderServiceTest {
    // Dependencies — Stub/Fake for state, Spy for side-effects
    private final FakeOrderRepository orderRepository = new FakeOrderRepository();
    private final PaymentPortStub paymentPort = new PaymentPortStub();
    private final EventPublisherSpy eventPublisher = new EventPublisherSpy();

    // SUT
    private final OrderService sut = new OrderService(
            orderRepository,
            paymentPort,
            eventPublisher
    );

    @BeforeEach
    void init() {
        orderRepository.clear();
        eventPublisher.clear();
    }

    @Test
    @DisplayName("create - saves order and publishes event")
    void createSavesOrderAndPublishesEvent() {
        var command = new OrderCreateCommand(1L);

        var actual = sut.create(command);

        // State verification — assert on result and stored data
        assertThat(actual.getCustomerId()).isEqualTo(1L);
        assertThat(actual.getStatus()).isEqualTo(OrderStatus.CREATED);
        assertThat(orderRepository.findById(actual.getId())).isPresent();
        assertThat(eventPublisher.getPublishedCount()).isEqualTo(1);
    }
}
```

**When mock is still needed** (e.g., external port with behavior contract):

```java
class OrderServiceTest {
    private final FakeOrderRepository orderRepository = new FakeOrderRepository();
    private final ExternalServicePort externalPort = mock(ExternalServicePort.class);

    private final OrderService sut = new OrderService(orderRepository, externalPort);

    @Test
    @DisplayName("execute - calls external service exactly once")
    void executeCallsExternalServiceExactlyOnce() {
        when(externalPort.call(any())).thenReturn(Result.success());

        sut.execute(command);

        verify(externalPort, times(1)).call(any());
    }
}
```

---

## Mockito Usage

### Creating Mocks

```java
// Full mock — only when behavior verification is needed
private final ExternalServicePort externalPort = mock(ExternalServicePort.class);

// Spy on a Fake — when you need both state and call tracking
private final FakeEntityRepository repository = spy(new FakeEntityRepository());
```

### Stubbing

```java
when(externalPort.call(any())).thenReturn(result);
when(repository.getById(1L)).thenReturn(entity);
doNothing().when(port).send(any(), any());

// void method
doNothing().when(publisher).publish(any(), any());
doThrow(new RuntimeException()).when(port).call(any());
```

### Verification

```java
verify(repository, times(1)).append(any());
verify(eventPublisher).publish(eq(DomainEventType.ENTITY_CREATED), any());

// Verify no calls were made
verifyNoInteractions(repository);
verifyNoMoreInteractions(repository);
```

### Reset

```java
@BeforeEach
void init() {
    Mockito.reset(repository);
}
```

---

## AssertJ Assertions

### Basic Assertions

```java
assertThat(actual).isEqualTo(expected);
assertThat(result).isNull();
assertThat(result).isNotNull();
assertThat(value).isTrue();
assertThat(value).isFalse();
```

### Chained Assertions

```java
assertThat(entity)
    .extracting("id", "workspaceId", "status")
    .containsExactly(1L, 100L, Status.COMPLETE);

// SoftAssertions (multiple verifications)
SoftAssertions.assertSoftly(softly -> {
    softly.assertThat(entity.getId()).isEqualTo(1L);
    softly.assertThat(entity.getWorkspaceId()).isEqualTo(100L);
    softly.assertThat(entity.getStatus()).isEqualTo(Status.COMPLETE);
});
```

### Collection Assertions

```java
assertThat(items)
    .hasSize(3)
    .first()
    .extracting(Item::getAmount)
    .isEqualTo(10000);

assertThat(items)
    .extracting(Item::getName)
    .containsExactly("item1", "item2", "item3");
```

### Exception Assertions

```java
assertThatThrownBy(() -> sut.execute(invalidCommand))
    .isInstanceOf(ApplicationBusinessException.class)
    .extracting("businessCause")
    .isEqualTo(ErrorCodeBook.INVALID_INPUT);

// Verify no exception is thrown
assertThatCode(() -> sut.execute(validCommand))
    .doesNotThrowAnyException();
```

---

## Test Fixtures

### FixtureMonkey (Java API)

```java
private static final FixtureMonkey fixtureMonkey = FixtureMonkey.builder()
    .objectIntrospector(ConstructorPropertiesArbitraryIntrospector.INSTANCE)
    .build();

// Single object
var entity = fixtureMonkey.giveMeOne(Entity.class);

// Customized
var entity = fixtureMonkey.giveMeBuilder(Entity.class)
    .set("id", 0L)
    .set("workspaceId", 1L)
    .sample();

// List
var entities = fixtureMonkey.giveMe(Entity.class, 5);
```

### Fake Repository Pattern

```java
// Defined in testFixtures
public abstract class BaseFakeRepository<V> {
    private final Map<Long, V> datasource = new ConcurrentHashMap<>();
    private final AtomicLong idCounter = new AtomicLong(1);

    protected abstract Long getId(V element);
    protected abstract V withId(V element, Long id);

    public V save(V element) {
        Long id = getId(element) != 0L ? getId(element) : idCounter.getAndIncrement();
        V saved = withId(element, id);
        datasource.put(id, saved);
        return saved;
    }

    public Optional<V> findById(Long id) {
        return Optional.ofNullable(datasource.get(id));
    }

    public List<V> findAll() {
        return new ArrayList<>(datasource.values());
    }

    public void clear() { datasource.clear(); }
}

// Concrete Fake for a specific domain
public class FakeOrderRepository extends BaseFakeRepository<Order>
        implements OrderRepository {

    @Override protected Long getId(Order element) { return element.getId(); }
    @Override protected Order withId(Order element, Long id) {
        return element.toBuilder().id(id).build();
    }

    @Override public Order save(Order order) { return super.save(order); }
    @Override public Optional<Order> findById(Long id) { return super.findById(id); }
    @Override public List<Order> findByCustomerId(Long customerId) {
        return findAll().stream()
            .filter(o -> o.getCustomerId().equals(customerId))
            .toList();
    }
}
```

### Reusable Stub Classes

```java
// testFixtures — Port Stub (with failure simulation)
public class PaymentPortStub implements PaymentPort {
    private final boolean shouldFail;
    private final List<Payment> payments = new ArrayList<>();

    public PaymentPortStub() { this(false); }
    public PaymentPortStub(boolean shouldFail) { this.shouldFail = shouldFail; }

    @Override
    public PaymentResult charge(Payment payment) {
        if (shouldFail) throw new PaymentException("Simulated failure");
        payments.add(payment);
        return PaymentResult.success(payment.getAmount());
    }

    public List<Payment> getChargedPayments() {
        return Collections.unmodifiableList(payments);
    }
}

// testFixtures — Spy (side-effect recording)
public class EventPublisherSpy implements DomainEventPublisher {
    private final List<DomainEvent> events = new ArrayList<>();

    @Override
    public void publish(DomainEvent event) {
        events.add(event);
    }

    public List<DomainEvent> getPublishedEvents() {
        return Collections.unmodifiableList(events);
    }

    public int getPublishedCount() { return events.size(); }
    public void clear() { events.clear(); }
}
```

### testFixtures Module Structure

```
src/
  main/java/                # Production code
  test/java/                # Unit tests
  testFixtures/java/
    ├── repository/
    │   ├── BaseFakeRepository.java
    │   └── FakeOrderRepository.java
    ├── stub/
    │   └── PaymentPortStub.java
    └── spy/
        └── EventPublisherSpy.java
```

`build.gradle`:
```groovy
plugins {
    id 'java-test-fixtures'
}
```

---

## Naming Conventions

### Test Class

- Production class name + `Test` suffix
- Example: `OrderCreationService` -> `OrderCreationServiceTest`

### Test Method

```java
// @DisplayName + camelCase (recommended)
@Test
@DisplayName("execute - happy path")
void executeHappyPath() { }

@Test
@DisplayName("execute - should throw exception when invalid input")
void executeShouldThrowExceptionWhenInvalidInput() { }
```

### @Nested Usage (Allowed)

`@Nested` inner classes are idiomatic in Java, so they are **allowed**.
(Prohibited in Kotlin due to build pipeline issues)

```java
// @Nested is allowed in Java
@Nested
@DisplayName("execute method")
class Execute {
    @Test
    @DisplayName("happy path")
    void happyPath() { }

    @Test
    @DisplayName("throws exception when invalid input")
    void throwsExceptionWhenInvalidInput() { }
}

// Flat structure is also allowed
@Test
@DisplayName("execute - happy path")
void executeHappyPath() { }
```

---

## Parameterized Tests

```java
@ParameterizedTest
@ValueSource(strings = {"TYPE_A", "TYPE_B"})
@DisplayName("resolve - per-type processing test")
void testTypeResolution(String rawType) {
    var type = EntityType.valueOf(rawType);
    var result = TypeResolver.resolve(type);
    assertThat(result).isEqualTo(type);
}

@ParameterizedTest
@MethodSource("provideInvalidInputs")
@DisplayName("execute - invalid inputs should throw")
void executeShouldThrowForInvalidInputs(Command command) {
    assertThatThrownBy(() -> sut.execute(command))
        .isInstanceOf(IllegalArgumentException.class);
}

static Stream<Arguments> provideInvalidInputs() {
    return Stream.of(
        Arguments.of(new Command(null, "name")),
        Arguments.of(new Command(-1L, null))
    );
}
```

---

## Setup/Teardown

```java
@BeforeEach
void init() {
    repository.clear();
    eventPublisher.clear();
}

@AfterEach
void tearDown() {
    repository.clear();
}
```
