# Code Style Guide

## Kotlin Idioms

### Data Classes & Sealed Classes
```kotlin
// Domain models use data classes
data class TotalAmount(val value: Long, val tax: Long?)

// Polymorphism via sealed class/interface
sealed class Receiver {
    data class Business(...) : Receiver()
    data class Individual(...) : Receiver()
}
```

### Extension Functions
- Write utility functions as extension functions
- Place them in a common lib/extensions module

```kotlin
// Time extensions
fun Instant.toLocalDate(zoneId: ZoneId): LocalDate
fun String.toInstant(pattern: String): Instant

// Infix operators
infix fun LocalDate.isAfterOrEquals(other: LocalDate): Boolean

// Null-safe operations
fun <T> T?.notNull(lazyMessage: () -> String): T
```

### Factory Methods
```kotlin
companion object {
    fun from(entity: SomeJpaEntity): DomainModel = DomainModel(...)
    fun of(text: String): ValueObject = ValueObject(sanitize(text))
    fun ofNullable(text: String?): ValueObject? = text?.let { of(it) }
}
```

---

## Method Rules

### No Extracting Single-Use Methods
- If a method is called from only one place, do not extract it into a separate method; keep it inlined at the call site
- Extract methods only when there are 2 or more call sites or when complex logic needs to be separated
- Even complex business logic should remain inlined if called only once (conciseness > readability)

```kotlin
// ❌ Single call site - do not extract into a method
class Repository {
    fun append() {
        copyAttributesToTarget()  // called from only one place
    }
    private fun copyAttributesToTarget() { ... }  // unnecessary extraction
}

// ✅ Keep inlined
class Repository {
    fun append() {
        val mappings = repository.findAllByXxx(...)
        if (mappings.isNotEmpty()) {
            mappings.map { ... }.let(repository::save)
        }
    }
}
```

### Return Values Must Be Used
- Method call results must be assigned to a local variable and used in subsequent logic
- Calling a method and ignoring its return value is prohibited

```kotlin
// ❌ Unused return value - prohibited
fun execute(command: Command): Entity {
    reader.getById(command.id)  // return value ignored
    return updater.update(viewId = command.id, ...)
}

// ✅ Assign return value to a variable and use it
fun execute(command: Command): Entity {
    val entity = reader.getById(command.id)
    return updater.update(viewId = entity.id, ...)
}
```

### No Test-only Methods
- Do not define methods in production code that are only used in tests
- If needed for tests, implement them directly in FakeRepository or test utilities

```kotlin
// ❌ Production method called only from tests - prohibited
interface EntityReader {
    fun getByIdOrNull(id: Long): Entity?
    fun getById(id: Long): Entity  // unused in production
}

// ✅ Define only methods actually used in production
interface EntityReader {
    fun getByIdOrNull(id: Long): Entity?
}

// Handle in tests via extension functions or FakeRepository
fun EntityReader.getById(id: Long): Entity =
    getByIdOrNull(id) ?: throw IllegalStateException("Not found")
```

---

## Naming Conventions

### Classes
| Type | Pattern | Example |
|------|---------|---------|
| Domain Model | `{Name}` (plain, no suffix) | `Order`, `Customer` |
| JPA Entity | `{Name}JpaEntity` | `OrderJpaEntity` |
| JOOQ Entity | `{Name}JooqEntity` | `OrderJooqEntity` |
| JDBC Entity | `{Name}JdbcEntity` | `OrderJdbcEntity` |
| JPA Embeddable | `{Name}JpaModel` | `OrderSnapshotJpaModel` |
| HTTP Response | `{Feature}HttpResponse` | `OrderDetailHttpResponse` |
| REST Controller | `{Feature}RestController` | `OrderFetchRestController` |
| Service | `{Feature}Service` | `OrderUpdateService` |
| Port | `{Feature}Port` | `NotificationPort` |
| Adapter | `{Feature}Adapter` | `SlackNotificationAdapter` |

> **Never use `*Dto` suffix.** Domain models use plain names (`Order` O, `OrderDto` X).
> Persistence entities **always** include the framework name: `{Name}{Framework}Entity`.

### Functions
| Type | Pattern | Example |
|------|---------|---------|
| Nullable getter | `get{Name}OrNull` | `getByIdOrNull(id)` |
| Throwing getter | `get{Name}` | `getById(id)` |
| Factory | `from`, `of` | `Email.of(text)` |
| Converter | `toModel`, `toEntity` | `entity.toModel()` |
| Command handler | `execute` | `execute(command)` |

### Repository Interfaces

- `{Entity}Reader`: Read operations
- `{Entity}Appender`: Create operations
- `{Entity}Updater`: Update operations
- Implementation: `{Entity}Repository` (implements multiple interfaces)

---

## JPA Entity Patterns

### Entity Structure
```kotlin
@Entity
@Table(name = "orders")
@DynamicUpdate
class OrderJpaEntity(
    override val id: Long,

    @Embedded
    val details: OrderDetails,

    @Convert(converter = BooleanToYNConverter::class)
    val isActive: Boolean,

    @ManyToOne(fetch = FetchType.EAGER, cascade = [CascadeType.ALL])
    val parentEntity: ParentJpaEntity,
) : BaseAuditingJpaEntity() {

    companion object {
        private val properties = arrayOf(OrderJpaEntity::id)
    }

    override fun equals(other: Any?) = kotlinEquals(other, properties)
    override fun hashCode() = kotlinHashCode(properties)
}
```

### Embeddable Usage
- Use `@Embeddable` for grouping related fields
- Map column names with `@AttributeOverrides`

### QueryDSL Custom Repository Pattern
```kotlin
// Interface definition
interface OrderFetcher : BaseJpaRepository<OrderJpaEntity, Long>, OrderFetcherCustom

interface OrderFetcherCustom {
    fun findAllActiveByWorkspaceIdIn(workspaceIds: List<Long>): List<OrderJpaEntity>
}

// Implementation (must use {Interface}Impl naming)
class OrderFetcherCustomImpl(
    private val jpaQueryFactory: JPAQueryFactory,
) : OrderFetcherCustom {
    private val qOrder = QOrderJpaEntity.orderJpaEntity

    override fun findAllActiveByWorkspaceIdIn(workspaceIds: List<Long>): List<OrderJpaEntity> {
        return jpaQueryFactory
            .selectFrom(qOrder)
            .where(qOrder.workspaceId.`in`(workspaceIds))
            .fetch()
    }
}
```

---

## Spring Boot Patterns

### Constructor Injection Only
```kotlin
@Component
class OrderUpdateService(
    private val orderReader: OrderReader,
    private val orderAppender: OrderAppender,
    private val domainEventPublisher: DomainNotificationEventPublisher,
)
```

### Controller Structure
```kotlin
@RestController
class OrderFetchRestController(
    private val orderRetrieve: OrderRetrieve,
) {
    @GetMapping(
        value = ["/api/v1/orders/{orderId}"],
        produces = [MediaType.APPLICATION_JSON_VALUE],
    )
    fun getOrder(@PathVariable orderId: Long): OrderHttpResponse
}
```

---

## Error Handling

### Business Exception
```kotlin
requireBusiness(
    condition = entity.status in UPDATABLE_STATUSES,
    errorCodeBook = ErrorCodeBook.COULD_NOT_CHANGE_ON_CURRENT_STATUS,
    details = mapOf("id" to id, "status" to status),
)
```

### Error Code Enum
- `ErrorCodeBook`: Business error codes
- Naming: `SCREAMING_SNAKE_CASE`

### ProblemDetail (RFC 7807/9457)

```kotlin
// Error hierarchy based on sealed class
sealed class DomainException(
    val errorCode: ErrorCodeBook,
    val detail: String,
    val properties: Map<String, Any> = emptyMap(),
) : RuntimeException(detail)

class OrderNotFoundException(orderId: Long) : DomainException(
    errorCode = ErrorCodeBook.ORDER_NOT_FOUND,
    detail = "Order not found: $orderId",
    properties = mapOf("orderId" to orderId),
)

// @ControllerAdvice + ProblemDetail conversion
@RestControllerAdvice
class GlobalExceptionHandler : ResponseEntityExceptionHandler() {

    @ExceptionHandler(DomainException::class)
    fun handleDomain(ex: DomainException): ProblemDetail {
        val problem = ProblemDetail.forStatusAndDetail(
            ex.errorCode.httpStatus, ex.detail
        )
        problem.title = ex.errorCode.name
        problem.setProperty("errorCode", ex.errorCode.code)
        ex.properties.forEach { (k, v) -> problem.setProperty(k, v) }
        return problem
    }
}
```

**Anti-patterns:**
- ❌ Writing a separate @ExceptionHandler for each exception class -- consolidate with a sealed class hierarchy
- ❌ Constructing ResponseEntity directly -- use ProblemDetail instead

---

## Spring Security Conventions

### SecurityFilterChain Bean Pattern

```kotlin
@Configuration
@EnableMethodSecurity
class SecurityConfig {

    @Bean
    fun filterChain(http: HttpSecurity): SecurityFilterChain = http {
        csrf { disable() }
        sessionManagement { sessionCreationPolicy = SessionCreationPolicy.STATELESS }
        authorizeHttpRequests {
            authorize("/api/v1/public/**", permitAll)
            authorize("/actuator/health", permitAll)
            authorize(anyRequest, authenticated)
        }
        oauth2ResourceServer { jwt { } }
    }
}
```

### @PreAuthorize on Service (NOT Controller)

```kotlin
// ✅ Authorization checks on Service
@Service
class OrderUpdateService(...) {
    @PreAuthorize("hasRole('ADMIN') or #command.userId == authentication.principal.id")
    fun execute(command: UpdateCommand): Order { ... }
}

// ❌ @PreAuthorize on Controller -- prohibited
```

**Validation rules:**
- Detect missing `@EnableMethodSecurity`
- Detect hardcoded JWT secrets (`"secret"`, `"my-secret-key"`, etc.)
- Detect `@PreAuthorize` on `*RestController` -- recommend moving to service

---

## Spring Event Patterns

### @TransactionalEventListener

```kotlin
// Immutable events (sealed class hierarchy)
sealed class OrderEvent {
    data class Cancelled(val orderId: Long, val reason: String, val cancelledAt: Instant) : OrderEvent()
    data class Completed(val orderId: Long, val completedAt: Instant) : OrderEvent()
}

// Publishing
@Service
class OrderCancelService(
    private val eventPublisher: ApplicationEventPublisher,
) {
    @Transactional
    fun cancel(command: CancelCommand) {
        // ... business logic
        eventPublisher.publishEvent(OrderEvent.Cancelled(order.id, command.reason, Instant.now()))
    }
}

// Subscribing -- AFTER_COMMIT recommended
@Component
class OrderEventHandler {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleCancelled(event: OrderEvent.Cancelled) {
        // Side effects such as sending notifications, calling external systems
    }
}
```

**Anti-patterns:**
- ❌ Mutable event objects (var properties) -- keep immutable with data class
- ❌ DB changes in `@EventListener` -- use `@TransactionalEventListener(AFTER_COMMIT)` instead
- ❌ Omitting TransactionPhase -- explicitly specify the default AFTER_COMMIT

---

## Advanced JPA Patterns

### Preventing N+1

```kotlin
// @EntityGraph
@EntityGraph(attributePaths = ["details", "items"])
fun findByIdWithDetails(id: Long): OrderJpaEntity?

// JOIN FETCH (JPQL)
@Query("SELECT o FROM OrderJpaEntity o JOIN FETCH o.items WHERE o.id = :id")
fun findByIdFetchItems(@Param("id") id: Long): OrderJpaEntity?

// @BatchSize (batch loading of collections)
@BatchSize(size = 100)
@OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
val items: List<OrderItemJpaEntity> = emptyList()
```

### Projection

```kotlin
// Interface projection (read-only)
interface OrderSummaryProjection {
    val id: Long
    val status: String
    val totalAmount: Long
}

// DTO projection (JPQL new)
@Query("SELECT new com.example.OrderSummary(o.id, o.status, o.totalAmount) FROM OrderJpaEntity o")
fun findAllSummaries(): List<OrderSummary>
```

### Soft Delete

```kotlin
@Entity
@SQLDelete(sql = "UPDATE orders SET deleted = true WHERE id = ?")
@SQLRestriction("deleted = false")
class OrderJpaEntity(...)
```

### Spring Data Auditing

```kotlin
@EntityListeners(AuditingEntityListener::class)
@MappedSuperclass
abstract class BaseAuditingJpaEntity {
    @CreatedDate
    var createdAt: Instant? = null

    @LastModifiedDate
    var updatedAt: Instant? = null

    @CreatedBy
    var createdBy: String? = null
}
```

---

## Caching Patterns

```kotlin
@Service
class OrderRetrieveService(private val orderReader: OrderReader) {

    @Cacheable(cacheNames = ["orders"], key = "#id")
    fun getById(id: Long): Order = orderReader.getById(id)

    @CacheEvict(cacheNames = ["orders"], key = "#command.orderId")
    fun update(command: UpdateCommand): Order { ... }

    @CachePut(cacheNames = ["orders"], key = "#result.id")
    fun create(command: CreateCommand): Order { ... }
}
```

**Required rules:**
- TTL configuration is mandatory (to prevent memory leaks): `@EnableCaching` + `RedisCacheConfiguration.defaultCacheConfig().entryTtl(Duration.ofMinutes(30))`
- Cache does not work with self-invocation inside `@Cacheable` (proxy bypass)

---

## Virtual Threads (Spring Boot 3.2+)

```yaml
# application.yml
spring:
  threads:
    virtual:
      enabled: true
```

- Suitable for I/O-bound tasks (DB, HTTP calls)
- Not suitable for CPU-bound tasks (encryption, image processing)
- Beware of blocking calls inside `synchronized` blocks (pinning)
- `@Async` + VirtualThread Executor:
  ```kotlin
  @Bean
  fun taskExecutor(): AsyncTaskExecutor = SimpleAsyncTaskExecutor().apply {
      setVirtualThreads(true)
  }
  ```

---

## Coroutines/Flow

```kotlin
// suspend fun in Controller
@RestController
class OrderFetchRestController(private val orderRetrieve: OrderRetrieveService) {
    @GetMapping("/api/v1/orders/{id}")
    suspend fun getOrder(@PathVariable id: Long): OrderHttpResponse =
        OrderHttpResponse.from(orderRetrieve.getById(id))
}

// Flow for streaming
@GetMapping("/api/v1/orders/stream", produces = [MediaType.TEXT_EVENT_STREAM_VALUE])
fun streamOrders(): Flow<OrderHttpResponse> = orderRetrieve.streamAll().map { OrderHttpResponse.from(it) }

// CoroutineCrudRepository
interface OrderCoroutineRepository : CoroutineCrudRepository<OrderJpaEntity, Long> {
    suspend fun findByStatus(status: String): List<OrderJpaEntity>
}
```

**Prohibited rules:**
- ❌ Using `runBlocking` in production code (test-only)
- ❌ `GlobalScope.launch` -- violates structured concurrency

---

## Testcontainers

### @ServiceConnection (Spring Boot 3.1+)

```kotlin
@SpringBootTest
@Testcontainers
class OrderIntegrationTest {

    companion object {
        @Container
        @ServiceConnection  // replaces @DynamicPropertySource
        val postgres = PostgreSQLContainer("postgres:16-alpine")
    }
}
```

### Container Lifecycle Strategy
- `per-method`: Full isolation, slow
- `per-class` (default @Testcontainers): Shared within class
- `shared` (static): Shared across entire test suite, fast

```yaml
# Parallel startup (Spring Boot 3.2+)
spring.testcontainers.beans.startup=parallel
```

---

## Transaction Management

### Self-invocation Pitfall

```kotlin
// ❌ Proxy bypass -- @Transactional does not work
@Service
class OrderService {
    fun process() {
        updateInternal()  // this call → bypasses proxy
    }

    @Transactional
    fun updateInternal() { ... }
}

// ✅ Separate into a different bean
@Service
class OrderService(private val orderUpdater: OrderUpdater) {
    fun process() {
        orderUpdater.update()  // goes through proxy
    }
}
```

### Propagation Level Guide

| Level | Usage |
|-------|-------|
| `REQUIRED` (default) | Joins existing transaction or creates a new one |
| `REQUIRES_NEW` | Independent transaction (audit logs, notifications, etc.) |
| `NESTED` | Savepoint-based (JDBC only) |

### readOnly Optimization

```kotlin
@Transactional(readOnly = true)  // Read Replica routing, snapshot optimization
fun getById(id: Long): Order = ...
```

---

## Structured Logging (Spring Boot 3.4+)

```yaml
# application.yml -- native structured logging
logging:
  structured:
    format:
      console: ecs  # ecs | logstash | gelf
```

```kotlin
// SLF4J Fluent API
logger.atInfo()
    .setMessage("Order processed")
    .addKeyValue("orderId", order.id)
    .addKeyValue("status", order.status)
    .log()
```

**Prohibited rules:**
- ❌ String concatenation: `logger.info("Order " + orderId)` -- use placeholders: `logger.info("Order {}", orderId)`
- MDC-based context propagation:
  ```kotlin
  MDC.put("traceId", traceId)
  try { ... } finally { MDC.clear() }
  ```

---

## Code Formatting

- Max line length: 140 (except test files)
- Indent: 4 spaces
- Trailing comma: allowed
- Star import: prohibited
- Follow ktlint rules

### Disabled ktlint Rules
```
ktlint_standard_string-template-indent = disabled
ktlint_standard_multiline-expression-wrapping = disabled
ktlint_standard_filename = disabled
ktlint_standard_if-else-wrapping = disabled
```
