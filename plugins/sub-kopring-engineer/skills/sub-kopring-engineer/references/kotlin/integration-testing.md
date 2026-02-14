# Integration Testing Guide

## Test Location
- `src/integrationTest/kotlin/`: Integration tests
- `src/integrationTest/resources/test-setup/`: SQL setup scripts

---

## Base Test Classes

### BaseMockMvcTest (API Module)
```kotlin
@ExtendWith(SpringExtension::class, MockKExtension::class)
@ActiveProfiles("test")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
abstract class BaseMockMvcTest : MySQLTestContainer, RedisTestContainer {
    protected lateinit var mockMvc: MockMvc

    @BeforeEach
    internal fun setUp(context: WebApplicationContext) {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build()
        // Request context setup
    }

    @AfterEach
    internal fun reset() {
        // Thread-local context cleanup
    }
}
```

### BatchJobTestInitSupporter (Batch Module)
```kotlin
@SpringBatchTest
@ExtendWith(SpringExtension::class, MockKExtension::class)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
abstract class BatchJobTestInitSupporter : MySQLTestContainer {
    protected abstract fun addSetUp()
    protected abstract fun addTearDown()
}
```

---

## Testcontainers

### Container Interfaces
Test classes inherit the container interfaces they need:
- `MySQLTestContainer`: MySQL + Flyway migration
- `RedisTestContainer`: Redis
- `SqsTestContainer`: LocalStack SQS
- `S3TestContainer`: LocalStack S3
- `KmsTestContainer`: LocalStack KMS

```kotlin
class MyIntegrationTest : MySQLTestContainer, RedisTestContainer {
    // Test code
}
```

### Container Configuration
- `LocalStackContainerHolder`: Singleton management for AWS service containers
- `@DynamicPropertySource`: Runtime property injection
- Automatic Flyway migration execution (MySQL)

---

## Test Data Setup

### SQL-based Setup
```kotlin
@Test
@SqlGroup(value = [
    Sql(
        scripts = [
            "classpath:/test-setup/setup-workspace.sql",
            "classpath:/test-setup/setup-account.sql",
        ],
        executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD,
    ),
    Sql(
        scripts = ["classpath:/test-setup/cleanup-tables.sql"],
        executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD,
    ),
])
fun testMethod() { ... }
```

### FixtureMonkey Usage
```kotlin
// Single object creation
val entity = fixture<Entity>()

// Customized
val entity = fixture<Entity> {
    set(Entity::workspaceId, 1L)
    set(Entity::status, Status.ACTIVE)
}

// List creation
val entities = fixtures<Entity>(5)
```

### Context Setup / Cleanup
```kotlin
@BeforeEach
fun setUp() {
    AuditorHolder.set(Auditor.ofSystem())
    // Set up required Thread-local context
}

@AfterEach
fun tearDown() {
    AuditorHolder.clear()
    // Clean up all Thread-local context
}
```

---

## Naming Conventions

### Test Class Names
| Type | Pattern |
|------|---------|
| REST Controller | `{Controller}RestControllerTest` |
| Service | `{Service}ServiceTest` |
| Repository | `{Entity}RepositoryTest` |
| Batch Job | `{Job}ConfigTest` |
| Adapter | `{Adapter}IntegrationTest` |

### Test Method Names
```kotlin
@Test
@DisplayName("execute - entity should be created on success")
fun `execute - happy path`() { ... }

@Test
@DisplayName("execute - should throw exception when precondition is not met")
fun test_should_throw_exception_when_precondition_not_met() { ... }
```

---

## Unit vs Integration Testing

| Aspect | Unit Test | Integration Test |
|--------|-----------|-----------------|
| Purpose | Isolate and verify business logic | Verify component interactions |
| Dependencies | Stub/Fake (in-memory) | Testcontainers + @MockkBean |
| Speed | Milliseconds | Seconds |
| Scope | Single Service/UseCase | Controller → Service → Real DB |
| DB | None (Fake Repository) | Testcontainers (MySQL, Redis) |
| When to write | Every Service/UseCase method | API endpoints, Repository queries, cross-layer flows |

**Rule of thumb:** If you're testing business logic → Unit Test with Stubs. If you're testing wiring, SQL, or HTTP contracts → Integration Test.

---

## Mocking

### @MockkBean (Spring Integration)
```kotlin
@MockkBean
private lateinit var externalPort: ExternalServicePort

@BeforeEach
fun setup() {
    every { externalPort.call(any()) } returns Result.Success(...)
}
```

### SQL Script Location
- `integrationTest/resources/test-setup/setup-*.sql`
- `integrationTest/resources/test-setup/cleanup-*.sql`

---

## Test Method Name Length Limit

Test method names (including backticks) must not exceed **120 bytes**.
Automatically validated when running ktlintCheck.
