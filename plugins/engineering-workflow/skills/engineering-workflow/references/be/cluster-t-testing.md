# Cluster T: Testing Reference

> Complete code examples, configuration templates, and validation functions for the T-1 Test Architecture Guard agent.

## 1. Test Taxonomy Tables

### Tier 1 vs Tier 2 Comparison

| Attribute | Tier 1 Unit | Tier 2 Integration |
|-----------|------------|-------------------|
| Source Set | `src/test/` | `src/integrationTest/` |
| Purpose | Business logic, domain rules | DB/external system verification |
| Execution Time | < 100 ms per test | < 5 s per test |
| External Dependencies | NONE | TestContainers (MySQL, Redis, SQS) |
| Framework Annotations | FORBIDDEN: `@SpringBootTest` | REQUIRED: `@SpringBootTest`, `@ActiveProfiles("test")` |
| Fixture Creation | Fixture Monkey (KotlinPlugin) | Fixture Monkey (KotlinPlugin) |
| Repository | FakeRepository (in-memory) | Real repository via TestContainers |
| Mocking | MockK `spyk` on FakeRepository | `@MockkBean` for external ports |
| Assertion Library | Strikt | Strikt |
| Base Class | None (plain JUnit 5) | `IntegrationTestContext` |
| TestContainers | FORBIDDEN | MySQL+Flyway, Redis, SQS/LocalStack |
| CI Gate | Must pass on every commit | Must pass on every commit |

### Tier 1 Forbidden Imports

```
org.springframework.boot.test.context.SpringBootTest
org.testcontainers.*
org.springframework.test.context.ActiveProfiles
org.springframework.beans.factory.annotation.Autowired
```

### Tier 2 Required Imports

```
org.springframework.boot.test.context.SpringBootTest
org.springframework.test.context.ActiveProfiles
```

## 2. Test Name Byte Calculation

### Validation Function

```kotlin
fun validateTestName(className: String, methodName: String): ValidationResult {
    val classBytes = className.toByteArray(Charsets.UTF_8).size
    val methodBytes = methodName.toByteArray(Charsets.UTF_8).size

    val rule1Pass = methodBytes <= 120
    val rule2Pass = classBytes + methodBytes + 9 <= 200

    return ValidationResult(
        classNameBytes = classBytes,
        methodNameBytes = methodBytes,
        totalBytes = classBytes + methodBytes + 9,
        rule1Pass = rule1Pass,     // methodNameBytes <= 120
        rule2Pass = rule2Pass,     // classBytes + methodBytes + 9 <= 200
        pass = rule1Pass && rule2Pass
    )
}

data class ValidationResult(
    val classNameBytes: Int,
    val methodNameBytes: Int,
    val totalBytes: Int,
    val rule1Pass: Boolean,
    val rule2Pass: Boolean,
    val pass: Boolean
)
```

### Byte Counting Rules

- ASCII characters: 1 byte each
- Korean characters (Hangul): 3 bytes each (UTF-8)
- The `+9` constant accounts for JUnit runner overhead in the test report path

## 3. Naming Examples

### BAD: Over 200 Bytes

```kotlin
class InvoiceCreateUseCaseTest {
    @Test
    fun `invoice_creation_when_required_field_recipient_business_registration_number_is_missing_throws_validation_exception`() {
        // classNameBytes = 24
        // methodNameBytes = 107 (all ASCII)
        // total = 24 + 107 + 9 = 140  -- within limit
        // Rule 1 PASS: 107 <= 120
    }
}
```

### GOOD: Shortened

```kotlin
class InvoiceCreateUseCaseTest {
    @Test
    fun `createInvoice_recipientBizNumMissing_exception`() {
        // classNameBytes = 24
        // methodNameBytes = 46 (all ASCII)
        // total = 24 + 46 + 9 = 79  -- well within limit
        // Rule 1 PASS: 46 <= 120
        // Rule 2 PASS: 79 <= 200
    }
}
```

### BEST: @DisplayName for Details

```kotlin
class InvoiceCreateUseCaseTest {
    @Test
    @DisplayName("Invoice creation throws validation exception when recipient business registration number is missing")
    fun `createInvoice_bizNumMissing_exception`() {
        // Method name is short, @DisplayName carries full description
        // methodNameBytes = 39 (all ASCII)
        // Rule 1 PASS: 39 <= 120
        // Rule 2 PASS: 24 + 39 + 9 = 72 <= 200
    }
}
```

## 4. Naming Strategy Tips

### Verbose-to-Concise Shortening

| Before | After | Savings |
|--------|-------|---------|
| when_creating_an_invoice | createInvoice | 12 bytes |
| if_field_is_missing | fieldMissing | 9 bytes |
| throws_an_exception | exception | 10 bytes |
| when_querying_results | queryResults | 10 bytes |

### Keywords Only

Extract core nouns and verbs, discard connecting words:

| Verbose | Keywords | Byte Reduction |
|---------|----------|---------------|
| `when_required_field_recipient_biz_reg_number_is_missing_throws_validation_exception` | `requiredFieldMissing_validationException` | ~42 bytes |
| `when_properly_registered_invoice_is_modified_change_history_is_saved` | `invoiceModified_historySaved` | ~40 bytes |

### Common Abbreviations

| Full | Abbrev | Context |
|------|--------|---------|
| success | OK | Test result suffix |
| failure | FAIL | Test result suffix |
| register | REG | CRUD shorthand |
| query | GET | CRUD shorthand |
| modify | MOD | CRUD shorthand |
| delete | DEL | CRUD shorthand |
| exception | EX | Exception suffix |
| validation | VALID | Validation prefix |

### @DisplayName Convention

- Method name: Korean keywords, max 120 bytes
- `@DisplayName`: Full sentence with particles, no byte limit
- IDE and CI both show `@DisplayName` value in test reports

## 5. Fixture Monkey KotlinPlugin API

### Basic Setup

```kotlin
class InvoiceCreateUseCaseTest {
    companion object {
        private val fixture = FixtureMonkey.builder()
            .plugin(KotlinPlugin())
            .build()
    }
}
```

### Single Object Generation

```kotlin
// Random instance with all fields populated
val invoice = fixture.giveMeOne<Invoice>()
```

### Builder with setExp

```kotlin
// Constrained instance: specific fields set, rest randomized
val invoice = fixture.giveMeBuilder<Invoice>()
    .setExp(Invoice::status, InvoiceStatus.DRAFT)
    .setExp(Invoice::amount, Money.of(10_000))
    .setExp(Invoice::supplierId, SupplierId(1L))
    .sample()
```

### List Generation

```kotlin
// Generate a list of 5 random instances
val invoices = fixture.giveMeBuilder<Invoice>()
    .setExp(Invoice::status, InvoiceStatus.ISSUED)
    .sampleList(5)
```

### PostCondition

```kotlin
// Add validation constraint to generated instances
val invoice = fixture.giveMeBuilder<Invoice>()
    .setPostCondition { it.amount.value > 0 }
    .sample()
```

### Legacy Migration Note

Replace manual `copy()` chains with Fixture Monkey:

```kotlin
// BEFORE (manual, brittle)
val invoice = Invoice(
    id = InvoiceId(1L),
    status = InvoiceStatus.DRAFT,
    amount = Money.of(10_000),
    supplierId = SupplierId(1L),
    recipientId = RecipientId(2L),
    // ... 15 more fields manually specified
)

// AFTER (Fixture Monkey, only specify what matters)
val invoice = fixture.giveMeBuilder<Invoice>()
    .setExp(Invoice::status, InvoiceStatus.DRAFT)
    .setExp(Invoice::amount, Money.of(10_000))
    .sample()
// All other fields are auto-generated with valid random values
```

## 6. FakeRepository Pattern

### BaseFakeRepository Abstract Class

```kotlin
abstract class BaseFakeRepository<T : Any, ID : Any>(
    private val idExtractor: (T) -> ID,
    private val idSetter: (T, ID) -> T,
    private val idGenerator: () -> ID
) {
    protected val store: MutableMap<ID, T> = mutableMapOf()
    private val sequence = AtomicLong(1L)

    fun persist(entity: T): T {
        val id = idExtractor(entity)
        val saved = if (id == null || !store.containsKey(id)) {
            val newId = idGenerator()
            val withId = idSetter(entity, newId)
            store[newId] = withId
            withId
        } else {
            store[id] = entity
            entity
        }
        return saved
    }

    fun getOrNull(id: ID): T? = store[id]

    fun getAll(): List<T> = store.values.toList()

    fun truncate() {
        store.clear()
        sequence.set(1L)
    }

    protected fun nextId(): Long = sequence.getAndIncrement()
}
```

### Concrete FakeRepository Implementation

```kotlin
class FakeInvoiceRepository : BaseFakeRepository<Invoice, InvoiceId>(
    idExtractor = { it.id },
    idSetter = { entity, id -> entity.copy(id = id) },
    idGenerator = { InvoiceId(nextId()) }
), InvoiceRepository {

    override fun save(invoice: Invoice): Invoice = persist(invoice)

    override fun findById(id: InvoiceId): Invoice? = getOrNull(id)

    override fun findAll(): List<Invoice> = getAll()

    override fun findByStatus(status: InvoiceStatus): List<Invoice> =
        getAll().filter { it.status == status }

    override fun deleteById(id: InvoiceId) {
        store.remove(id)
    }
}
```

### Key Properties

- `store` is a simple `MutableMap` -- no DB, no Spring context needed
- `sequence` provides deterministic ID generation via `AtomicLong`
- `truncate()` resets both store and sequence -- call in `@BeforeEach`
- Implements the Core Port interface directly -- no adapter layer needed in tests

## 7. spyk Verification Pattern

### Setup with spyk

```kotlin
class InvoiceCreateUseCaseTest {
    companion object {
        private val fixture = FixtureMonkey.builder()
            .plugin(KotlinPlugin())
            .build()
    }

    private val fakeRepo = FakeInvoiceRepository()
    private val repoSpy = spyk(fakeRepo)
    private val useCase = InvoiceCreateUseCase(repoSpy)

    @BeforeEach
    fun setUp() {
        fakeRepo.truncate()
        clearMocks(repoSpy, answers = false)
    }
}
```

### Critical: answers = false

```kotlin
// CORRECT: preserves FakeRepository behavior, clears verification state only
clearMocks(repoSpy, answers = false)

// WRONG: clears both answers and verification -- FakeRepository stops working
clearMocks(repoSpy)  // answers defaults to true
```

- `answers = false`: Only resets call recording. The spyk still delegates to FakeRepository.
- `answers = true` (default): Resets everything. The spyk returns null/default for all calls.

### Test with verify

```kotlin
@Test
fun `createInvoice_normal_saveOK`() {
    // given
    val command = fixture.giveMeBuilder<CreateInvoiceCommand>()
        .setExp(CreateInvoiceCommand::amount, Money.of(10_000))
        .sample()

    // when
    val result = useCase.execute(command)

    // then
    expectThat(result) {
        get { status }.isEqualTo(InvoiceStatus.DRAFT)
        get { amount }.isEqualTo(Money.of(10_000))
    }
    verify(exactly = 1) { repoSpy.save(any()) }
}
```

### Why spyk over mockk?

- `mockk<InvoiceRepository>()` requires stubbing every method -> brittle, verbose
- `spyk(fakeRepo)` uses real FakeRepository logic + adds verification capability
- Tests validate both behavior (via FakeRepository state) and interaction (via verify)

## 8. IntegrationTestContext Base Class

### Base Class Definition

```kotlin
@ActiveProfiles("test")
@SpringBootTest
abstract class IntegrationTestContext {

    companion object {
        @JvmStatic
        val mysqlContainer = MySQLContainer("mysql:8.0")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test")
            .apply { start() }

        @JvmStatic
        val redisContainer = GenericContainer("redis:7-alpine")
            .withExposedPorts(6379)
            .apply { start() }

        @JvmStatic
        val localStackContainer = LocalStackContainer(DockerImageName.parse("localstack/localstack:3"))
            .withServices(LocalStackContainer.Service.SQS)
            .apply { start() }

        @DynamicPropertySource
        @JvmStatic
        fun overrideProperties(registry: DynamicPropertyRegistry) {
            // MySQL
            registry.add("spring.datasource.url") { mysqlContainer.jdbcUrl }
            registry.add("spring.datasource.username") { mysqlContainer.username }
            registry.add("spring.datasource.password") { mysqlContainer.password }
            // Flyway
            registry.add("spring.flyway.url") { mysqlContainer.jdbcUrl }
            // Redis
            registry.add("spring.data.redis.host") { redisContainer.host }
            registry.add("spring.data.redis.port") { redisContainer.firstMappedPort }
            // SQS
            registry.add("cloud.aws.sqs.endpoint") {
                localStackContainer.getEndpointOverride(LocalStackContainer.Service.SQS).toString()
            }
        }
    }

    @MockkBean
    lateinit var pgPaymentPort: PgPaymentPort

    @MockkBean
    lateinit var notificationPort: NotificationPort

    @MockkBean
    lateinit var externalErpPort: ExternalErpPort

    @Autowired
    lateinit var jdbcTemplate: JdbcTemplate

    @BeforeEach
    fun cleanUp() {
        // Truncate all tables
        jdbcTemplate.execute("SET FOREIGN_KEY_CHECKS = 0")
        jdbcTemplate.queryForList(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'testdb'"
        ).forEach { row ->
            jdbcTemplate.execute("TRUNCATE TABLE ${row["table_name"]}")
        }
        jdbcTemplate.execute("SET FOREIGN_KEY_CHECKS = 1")

        // Clear MockK state
        clearMocks(pgPaymentPort, notificationPort, externalErpPort, answers = false)
    }
}
```

### Key Design Decisions

- **Static containers**: Shared across all integration tests via `companion object` -- one container per JVM run
- **Flyway**: Migrations run automatically on MySQL container, matching production schema
- **@MockkBean for external ports**: PG, notification, ERP ports are mocked -- no real external calls
- **@BeforeEach cleanup**: Truncates all tables and clears mock state before every test
- **@ActiveProfiles("test")**: Loads `application-test.yml` with container-specific connection strings

## 9. Stub Structure Checklist

When adding a new external module (e.g., `external-tax-api`), verify these 4 items:

### Item 1: FakeRepository or FakeClient

```
src/test/kotlin/.../fake/FakeTaxApiClient.kt
  - Implements TaxApiPort interface from Core
  - Uses in-memory store (MutableMap or MutableList)
  - Provides truncate() for cleanup
```

### Item 2: Fixture Monkey Fixtures

```
src/test/kotlin/.../fixture/TaxFixtures.kt
  - FixtureMonkey companion with KotlinPlugin
  - Builder functions for each domain object: TaxInvoice, TaxItem, etc.
  - Pre-configured builders for common test scenarios
```

### Item 3: @MockkBean in IntegrationTestContext

```
IntegrationTestContext.kt:
  @MockkBean
  lateinit var taxApiPort: TaxApiPort
  // Added to @BeforeEach clearMocks call
```

### Item 4: Integration Test for Adapter

```
src/integrationTest/kotlin/.../TaxApiAdapterIntegrationTest.kt
  - Extends IntegrationTestContext
  - Verifies adapter serialization/deserialization
  - Uses WireMock or MockServer for HTTP-level verification
```

## 10. Per-Test Checklist

Every test must satisfy all 6 items:

| # | Check | Tier 1 | Tier 2 | Violation Severity |
|---|-------|--------|--------|-------------------|
| 1 | Correct source set placement | `src/test/` | `src/integrationTest/` | HIGH |
| 2 | Both naming byte rules pass | Rule 1 + Rule 2 | Rule 1 + Rule 2 | HIGH |
| 3 | Fixture creation uses Fixture Monkey | `giveMeOne` / `giveMeBuilder` | `giveMeOne` / `giveMeBuilder` | MEDIUM |
| 4 | Assertions use Strikt `expectThat` | No `assertEquals` | No `assertEquals` | MEDIUM |
| 5 | No forbidden annotations/imports | No `@SpringBootTest` | Must have `@SpringBootTest` | CRITICAL |
| 6 | Test is deterministic | No `Thread.sleep`, no unseeded random, no `System.currentTimeMillis()` | No `Thread.sleep`, no unseeded random | HIGH |

### Determinism Rules

```kotlin
// FORBIDDEN in any test
Thread.sleep(1000)                    // Use Awaitility for async assertions
Random().nextInt()                     // Use seeded Random or Fixture Monkey
System.currentTimeMillis()            // Use Clock injection
LocalDateTime.now()                   // Use Clock injection

// ALLOWED alternatives
await().atMost(Duration.ofSeconds(5)).untilAsserted { ... }  // Awaitility
fixture.giveMeOne<Int>()                                      // Fixture Monkey
clock.instant()                                                // Injected Clock
```
