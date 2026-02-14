# Java Integration Testing Guide

> Java integration testing guide that corresponds 1:1 with the Kotlin integration-testing.md.
> Loaded when the profile language is java or mixed.

## Test Location

- `src/integrationTest/java/` or `src/test/java/`: Integration tests
- `src/integrationTest/resources/test-setup/`: SQL setup scripts

---

## Base Test Classes

### BaseMockMvcTest (API Module)

```java
@ExtendWith(SpringExtension.class)
@ActiveProfiles("test")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseMockMvcTest implements MySQLTestContainer, RedisTestContainer {
    protected MockMvc mockMvc;

    @BeforeEach
    void setUp(WebApplicationContext context) {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
        // Request context setup
    }

    @AfterEach
    void reset() {
        // Thread-local context cleanup
    }
}
```

### BatchJobTestInitSupporter (Batch Module)

```java
@SpringBatchTest
@ExtendWith(SpringExtension.class)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BatchJobTestInitSupporter implements MySQLTestContainer {
    protected abstract void addSetUp();
    protected abstract void addTearDown();
}
```

---

## Testcontainers

> Container interfaces (MySQLTestContainer, RedisTestContainer, etc.) — same pattern as Kotlin.
> See [integration-testing.md § Testcontainers](./integration-testing.md#testcontainers).

---

## Test Data Setup

### SQL-based Setup

```java
@Test
@SqlGroup({
    @Sql(
        scripts = {
            "classpath:/test-setup/setup-workspace.sql",
            "classpath:/test-setup/setup-account.sql"
        },
        executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD
    ),
    @Sql(
        scripts = "classpath:/test-setup/cleanup-tables.sql",
        executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD
    )
})
void testMethod() { ... }
```

### FixtureMonkey Usage (Java API)

```java
private static final FixtureMonkey fixtureMonkey = FixtureMonkey.builder()
    .objectIntrospector(ConstructorPropertiesArbitraryIntrospector.INSTANCE)
    .build();

// Single object
var entity = fixtureMonkey.giveMeOne(Entity.class);

// Customized
var entity = fixtureMonkey.giveMeBuilder(Entity.class)
    .set("workspaceId", 1L)
    .set("status", Status.ACTIVE)
    .sample();

// List
var entities = fixtureMonkey.giveMe(Entity.class, 5);
```

### Context Setup / Cleanup

```java
@BeforeEach
void setUp() {
    AuditorHolder.set(Auditor.ofSystem());
    // Set up required Thread-local context
}

@AfterEach
void tearDown() {
    AuditorHolder.clear();
    // Clean up all Thread-local context
}
```

---

## Naming Conventions

> Test class names table — same as Kotlin: see [integration-testing.md § Naming Conventions](./integration-testing.md#naming-conventions).
> Test method style: `@DisplayName` + camelCase (see [java-unit-testing.md § Naming Conventions](./java-unit-testing.md#naming-conventions)).

---

## Unit vs Integration Testing

> Same selection criteria as Kotlin — see [integration-testing.md § Unit vs Integration Testing](./integration-testing.md#unit-vs-integration-testing).

---

## Mocking

### @MockBean (Spring Integration)

```java
@MockBean
private ExternalServicePort externalPort;

@BeforeEach
void setup() {
    when(externalPort.call(any())).thenReturn(Result.success(...));
}
```

### @SpyBean

```java
@SpyBean
private OrderRepository orderRepository;

@Test
void testWithSpy() {
    // Use the real implementation while stubbing specific methods
    doReturn(Optional.of(entity)).when(orderRepository).findById(1L);
}
```

---

## MockMvc Usage

```java
@Test
@DisplayName("GET /api/v1/orders/{id} - retrieve order")
void getOrder() throws Exception {
    mockMvc.perform(get("/api/v1/orders/{id}", 1L)
            .contentType(MediaType.APPLICATION_JSON))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.id").value(1L))
        .andExpect(jsonPath("$.status").value("ACTIVE"));
}

@Test
@DisplayName("POST /api/v1/orders - create order")
void createOrder() throws Exception {
    var request = new OrderCreateRequest("item", 1000L);
    mockMvc.perform(post("/api/v1/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(request)))
        .andExpect(status().isCreated());
}
```
