# Kotlin/Spring Boot Idioms Reference

> Code idioms and conventions for agents S5 (Convention Verifier) and B5 (Implementation Guide).
> Defines canonical Kotlin/Spring Boot patterns for code generation and verification.

---

## 1. Kotlin Idioms

### Data Classes: Immutable by Default

```kotlin
data class OrderLine(val productId: ProductId, val quantity: Int, val unitPrice: Money)  // CORRECT: val
// WRONG: data class OrderLine(var productId: ProductId, ...) -- var is FORBIDDEN
```

### Sealed Classes for Polymorphism

```kotlin
sealed class DomainException(
    val errorCode: ErrorCode, override val message: String
) : RuntimeException(message) {
    class NotFound(errorCode: ErrorCode, msg: String) : DomainException(errorCode, msg)
    class BusinessRuleViolation(errorCode: ErrorCode, msg: String) : DomainException(errorCode, msg)
    class Conflict(errorCode: ErrorCode, msg: String) : DomainException(errorCode, msg)
}

sealed interface OrderStatus {
    data object Draft : OrderStatus
    data object Confirmed : OrderStatus
    data class Shipped(val trackingNumber: String) : OrderStatus
    data object Cancelled : OrderStatus
}
```

### Extension Functions for Conversion

```kotlin
fun OrderJpaEntity.toModel(): Order = Order(id = OrderId(this.id), status = this.status, lines = this.lines.map { it.toModel() })
fun Order.toResponse(): OrderHttpResponse = OrderHttpResponse(id = this.id.value, status = this.status.name, totalAmount = this.totalAmount().value)
fun Order.toEntity(): OrderJpaEntity = OrderJpaEntity(id = this.id.value, status = this.status, lines = this.lines.map { it.toEntity() })
```

### Factory Methods

```kotlin
class Money private constructor(val value: BigDecimal) {
    companion object {
        fun of(value: Long): Money = Money(BigDecimal.valueOf(value))
        fun of(value: BigDecimal): Money = Money(value)
        fun ofNullable(value: BigDecimal?): Money? = value?.let { Money(it) }
        fun from(raw: String): Money = Money(BigDecimal(raw))
    }
}
```

### Single-Expression Functions

```kotlin
fun Order.totalAmount(): Money = lines.fold(Money.of(0)) { acc, line -> acc + line.subtotal() }
fun OrderLine.subtotal(): Money = unitPrice * quantity
```

### Scope Functions

```kotlin
val displayName = user.nickname?.let { "($it)" } ?: ""                     // let: null-safe transform
val result = order.run { require(status == OrderStatus.Draft); confirm() }  // run: execute on receiver
val config = HttpClient().apply { connectTimeout = Duration.ofSeconds(5) }  // apply: configure + return
val saved = repository.save(order).also { publisher.publishEvent(it) }      // also: side-effect
```

### Null Safety

```kotlin
user.email?.let { sendVerificationEmail(it) }                                  // safe call + let
val order = repository.findById(orderId)
    ?: throw DomainException.NotFound(ErrorCode.ORDER_NOT_FOUND, "Not found")  // elvis + throw
val userId = requireNotNull(securityContext.userId) { "User ID required" }     // requireNotNull
```

---

## 2. Code Style Rules

| Rule | Value |
|------|-------|
| Max line length | 140 characters |
| Indentation | 4 spaces (no tabs) |
| Trailing comma | Allowed in multiline declarations |
| Star imports | PROHIBITED (`import com.example.domain.*` is forbidden) |
| Blank lines between top-level declarations | 1 |

### Single-Use Private Methods

```kotlin
// WRONG: extracting logic called from only one place
class OrderService(private val repo: OrderRepository) {
    fun cancel(orderId: OrderId) { val order = findOrderOrThrow(orderId); order.cancel(); repo.save(order) }
    private fun findOrderOrThrow(orderId: OrderId): Order = repo.findById(orderId) ?: throw DomainException.NotFound(...)
}

// CORRECT: inline the logic at the single call site
class OrderService(private val repo: OrderRepository) {
    fun cancel(orderId: OrderId) {
        val order = repo.findById(orderId)
            ?: throw DomainException.NotFound(ErrorCode.ORDER_NOT_FOUND, "Not found")
        order.cancel(); repo.save(order)
    }
}
```

### Other Rules

- **Return values must always be used**: `val saved = repository.save(order)` -- never ignore returns
- **No test-only methods in production code**: use Fixture Monkey or test builders in test source sets

---

## 3. Spring DI Patterns

### Constructor Injection Only

```kotlin
// CORRECT: primary constructor injection
@Service
class CancelOrderUseCase(
    private val orderRepository: OrderRepository,
    private val paymentPort: PaymentPort,
    private val notificationPort: NotificationPort
) { fun execute(command: CancelOrderCommand): Order { ... } }

// WRONG: field injection (@Autowired lateinit var) -- FORBIDDEN
// WRONG: setter injection (@Autowired fun setX()) -- FORBIDDEN
```

### @Configuration + @Bean for Complex Wiring

```kotlin
@Configuration
class PaymentConfiguration {
    @Bean
    fun paymentPort(client: PgFeignClient, cbFactory: CircuitBreakerFactory): PaymentPort =
        CircuitBreakerPaymentAdapter(delegate = PgPaymentAdapter(client), circuitBreakerFactory = cbFactory)
}
```

### @Qualifier for Multiple Implementations

```kotlin
@Component @Qualifier("email") class EmailAdapter : NotificationPort { ... }
@Component @Qualifier("sms")   class SmsAdapter : NotificationPort { ... }

@Service
class SendNotificationUseCase(
    @Qualifier("email") private val emailPort: NotificationPort,
    @Qualifier("sms") private val smsPort: NotificationPort
) { ... }
```

### ObjectProvider for Optional/Lazy Dependencies

```kotlin
@Service
class ReportUseCase(private val cacheProvider: ObjectProvider<CachePort>) {
    fun generate(): Report {
        val cache = cacheProvider.ifAvailable
        return cache?.get("report") ?: buildReport().also { cache?.put("report", it) }
    }
}
```

### @Profile and @ConditionalOnProperty

```kotlin
@Configuration @Profile("production")
class ProdPaymentConfig {
    @Bean fun paymentPort(client: PgFeignClient): PaymentPort = PgPaymentAdapter(client)
}

@Configuration @Profile("test")
class TestPaymentConfig {
    @Bean fun paymentPort(): PaymentPort = StubPaymentAdapter()
}

@Configuration
@ConditionalOnProperty(name = ["feature.new-pricing.enabled"], havingValue = "true")
class NewPricingConfig {
    @Bean fun pricingStrategy(): PricingStrategy = NewPricingStrategy()
}
```

---

## 4. Naming Conventions

### Class Suffix Rules

| Layer | Suffix | Example |
|-------|--------|---------|
| Domain Model | (plain) | `Order`, `Money`, `Email` |
| JPA Entity | `JpaEntity` | `OrderJpaEntity` |
| HTTP Response | `HttpResponse` | `OrderHttpResponse` |
| HTTP Request | `HttpRequest` | `CreateOrderHttpRequest` |
| Use Case | `UseCase` | `CancelOrderUseCase` |
| Controller | `Controller` | `OrderController` |
| Repository (Port) | `Repository` | `OrderRepository` |
| Port | `Port` | `PaymentPort` |
| Adapter | `Adapter` | `PgPaymentAdapter` |
| Command | `Command` | `CancelOrderCommand` |
| Event | `Event` | `OrderCancelledEvent` |
| Configuration | `Configuration` | `PaymentConfiguration` |
| Definition | `Definition` | `OrderCreationDefinition` |

### Function Naming Conventions

| Pattern | Usage | Example |
|---------|-------|---------|
| `getOrNull` | May return null | `fun getOrNull(id: OrderId): Order?` |
| `findBy` | Query returning list | `fun findByCustomerId(id: CustomerId): List<Order>` |
| `from()` | Factory from external data | `Money.from("10000")` |
| `of()` | Factory from primitives | `Money.of(10_000L)` |
| `toModel()` | JpaEntity to Domain | `entity.toModel()` |
| `toEntity()` | Domain to JpaEntity | `order.toEntity()` |
| `toResponse()` | Domain to HTTP DTO | `order.toResponse()` |
| `execute()` | UseCase entry point | `useCase.execute(command)` |

### Repository Interface Separation

```kotlin
interface OrderReader {
    fun getOrNull(id: OrderId): Order?
    fun findByCustomerId(customerId: CustomerId): List<Order>
}
interface OrderAppender { fun save(order: Order): Order }
interface OrderUpdater  { fun update(order: Order): Order }
interface OrderRepository : OrderReader, OrderAppender, OrderUpdater
```

---

## 5. Immutability Patterns

### Domain Models: All Properties val

```kotlin
data class Order(
    val id: OrderId, val customerId: CustomerId, val status: OrderStatus,
    val lines: List<OrderLine>, val createdAt: Instant, val updatedAt: Instant
) {
    fun confirm(): Order = copy(status = OrderStatus.Confirmed, updatedAt = Instant.now())
    fun cancel(): Order = copy(status = OrderStatus.Cancelled, updatedAt = Instant.now())
}
```

### CreationDefinition / UpdateDefinition

```kotlin
data class OrderCreationDefinition(
    val customerId: CustomerId, val lines: List<OrderLineDefinition>, val shippingAddress: Address
)
data class OrderUpdateDefinition(val shippingAddress: Address? = null, val lines: List<OrderLineDefinition>? = null)

@Service
class CreateOrderUseCase(private val orderRepository: OrderRepository) {
    fun execute(def: OrderCreationDefinition): Order {
        val order = Order.create(customerId = def.customerId, lines = def.lines.map { it.toOrderLine() }, shippingAddress = def.shippingAddress)
        return orderRepository.save(order)
    }
}
```

### Value Objects with init Validation

```kotlin
data class Email(val value: String) {
    init {
        require(value.contains("@")) { "Invalid email format: $value" }
        require(value.length <= 255) { "Email exceeds max length" }
    }
}

data class Money(val value: BigDecimal) {
    init {
        require(value >= BigDecimal.ZERO) { "Money cannot be negative: $value" }
        require(value.scale() <= 2) { "Money scale exceeds 2 decimal places" }
    }
    operator fun plus(other: Money): Money = Money(this.value + other.value)
    operator fun times(quantity: Int): Money = Money(this.value * BigDecimal(quantity))
}

data class BusinessRegistrationNumber(val value: String) {
    init { require(value.matches(Regex("^\\d{3}-\\d{2}-\\d{5}$"))) { "Invalid format: $value" } }
}
```

### Aggregate Root Invariant Enforcement

```kotlin
data class Order(val id: OrderId, val status: OrderStatus, val lines: List<OrderLine>) {
    init { require(lines.isNotEmpty()) { "Order must have at least one line" } }

    fun addLine(line: OrderLine): Order {
        require(status == OrderStatus.Draft) { "Cannot add lines to non-draft order" }
        return copy(lines = lines + line)
    }
    fun removeLine(productId: ProductId): Order {
        require(status == OrderStatus.Draft) { "Cannot remove lines from non-draft order" }
        val updated = lines.filter { it.productId != productId }
        require(updated.isNotEmpty()) { "Order must retain at least one line" }
        return copy(lines = updated)
    }
}
```

---

## 6. Error Handling

### requireBusiness with ErrorCodeBook

```kotlin
enum class ErrorCode(val status: Int, val defaultMessage: String) {
    ORDER_NOT_FOUND(404, "Order not found"),
    ORDER_ALREADY_CANCELLED(409, "Order is already cancelled"),
    INSUFFICIENT_STOCK(422, "Insufficient stock"),
    PAYMENT_FAILED(502, "Payment processing failed"),
}

inline fun requireBusiness(
    condition: Boolean, errorCode: ErrorCode,
    lazyMessage: () -> String = { errorCode.defaultMessage }
) { if (!condition) throw DomainException.BusinessRuleViolation(errorCode, lazyMessage()) }

fun Order.cancel(): Order {
    requireBusiness(status != OrderStatus.Cancelled, ErrorCode.ORDER_ALREADY_CANCELLED)
    return copy(status = OrderStatus.Cancelled, updatedAt = Instant.now())
}
```

### Sealed Class Error Hierarchy

```kotlin
sealed class DomainException(
    val errorCode: ErrorCode, override val message: String
) : RuntimeException(message) {
    class NotFound(errorCode: ErrorCode, msg: String) : DomainException(errorCode, msg)
    class BusinessRuleViolation(errorCode: ErrorCode, msg: String) : DomainException(errorCode, msg)
    class Conflict(errorCode: ErrorCode, msg: String) : DomainException(errorCode, msg)
    class ExternalSystemFailure(errorCode: ErrorCode, msg: String, cause: Throwable? = null) :
        DomainException(errorCode, msg) { init { cause?.let { initCause(it) } } }
}
```

### ProblemDetail in @RestControllerAdvice (RFC 9457)

```kotlin
@RestControllerAdvice
class GlobalExceptionHandler {
    @ExceptionHandler(DomainException.NotFound::class)
    fun handleNotFound(ex: DomainException.NotFound): ProblemDetail = toProblemDetail(ex)

    @ExceptionHandler(DomainException.BusinessRuleViolation::class)
    fun handleBusinessRule(ex: DomainException.BusinessRuleViolation): ProblemDetail = toProblemDetail(ex)

    @ExceptionHandler(DomainException.Conflict::class)
    fun handleConflict(ex: DomainException.Conflict): ProblemDetail = toProblemDetail(ex)

    private fun toProblemDetail(ex: DomainException): ProblemDetail =
        ProblemDetail.forStatus(ex.errorCode.status).apply {
            title = ex.errorCode.name; detail = ex.message; setProperty("errorCode", ex.errorCode.name)
        }
}
```

---

## 7. Spring Event Patterns

### Immutable Events via Data Classes

```kotlin
// Domain event: within bounded context -- uses rich types
data class OrderConfirmedEvent(
    val orderId: OrderId, val customerId: CustomerId, val totalAmount: Money, val confirmedAt: Instant
)

// Integration event: across contexts -- uses primitives for serialization
data class OrderConfirmedIntegrationEvent(
    val orderId: Long, val customerId: Long, val totalAmount: BigDecimal, val confirmedAt: String
)
```

### @TransactionalEventListener for Side Effects

```kotlin
@Component
class OrderEventListener(private val notificationPort: NotificationPort) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onOrderConfirmed(event: OrderConfirmedEvent) {
        notificationPort.send(Notification.orderConfirmed(event.orderId, event.customerId))
    }
}
```

### ApplicationEventPublisher Injection

```kotlin
@Service
class ConfirmOrderUseCase(
    private val orderRepository: OrderRepository, private val eventPublisher: ApplicationEventPublisher
) {
    @Transactional
    fun execute(command: ConfirmOrderCommand): Order {
        val order = orderRepository.getOrNull(command.orderId)
            ?: throw DomainException.NotFound(ErrorCode.ORDER_NOT_FOUND, "Order not found")
        val saved = orderRepository.save(order.confirm())
        eventPublisher.publishEvent(OrderConfirmedEvent(saved.id, saved.customerId, saved.totalAmount(), Instant.now()))
        return saved
    }
}
```

### Domain Event vs Integration Event

| Aspect | Domain Event | Integration Event |
|--------|-------------|-------------------|
| Scope | Within bounded context | Across bounded contexts |
| Transport | Spring ApplicationEvent | SQS, Kafka |
| Types | Rich domain types (OrderId, Money) | Primitives and strings |
| Emitter term | publisher | producer |

---

## 8. Transaction Management

### Self-Invocation Pitfall

```kotlin
// WRONG: self-invocation bypasses proxy -- @Transactional is ignored
@Service
class OrderService(private val repo: OrderRepository) {
    fun processOrder(id: OrderId) { confirmOrder(id) }  // direct call -- NO tx boundary
    @Transactional fun confirmOrder(id: OrderId) { ... }
}

// CORRECT: extract into separate beans for proxy-mediated calls
@Service class ProcessOrderUseCase(private val confirm: ConfirmOrderUseCase) {
    fun execute(id: OrderId) { confirm.execute(id) }
}
@Service class ConfirmOrderUseCase(private val repo: OrderRepository) {
    @Transactional fun execute(id: OrderId) { ... }
}
```

### Propagation Levels Reference

| Level | Behavior | Use Case |
|-------|----------|----------|
| `REQUIRED` | Join existing or create new | Standard writes |
| `REQUIRES_NEW` | Always create new, suspend existing | Audit logging |
| `SUPPORTS` | Join if present, else non-tx | Read-only queries |
| `NOT_SUPPORTED` | Suspend existing, non-tx | External API calls |
| `MANDATORY` | Must have existing, else throw | Port implementations |
| `NEVER` | Must NOT have existing, else throw | Background jobs |

### readOnly Optimization

```kotlin
@Service @Transactional(readOnly = true)
class OrderQueryUseCase(private val reader: OrderReader) {
    fun findById(id: OrderId): Order? = reader.getOrNull(id)
    fun findByCustomer(cid: CustomerId): List<Order> = reader.findByCustomerId(cid)
}
```

### @Transactional Placement

- CORRECT: `@Transactional` on Application Service (UseCase)
- WRONG: `@Transactional` on Repository adapter -- transaction boundary belongs in UseCase

---

## 9. Spring Security Patterns

### SecurityFilterChain as @Bean

```kotlin
@Configuration @EnableWebSecurity
class SecurityConfig {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain =
        http.csrf { it.disable() }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .authorizeHttpRequests { auth ->
                auth.requestMatchers("/api/health", "/api/docs/**").permitAll()
                    .requestMatchers("/api/admin/**").hasRole("ADMIN")
                    .requestMatchers("/api/**").authenticated()
                    .anyRequest().denyAll()
            }
            .addFilterBefore(jwtFilter(), UsernamePasswordAuthenticationFilter::class.java)
            .build()
}
```

### @PreAuthorize on Service Layer (NOT Controller)

```kotlin
@Service
class AdminOrderUseCase(private val repo: OrderRepository) {
    @PreAuthorize("hasRole('ADMIN')")
    fun forceCancel(orderId: OrderId): Order { ... }

    @PreAuthorize("hasRole('ADMIN') or @orderChecker.isOwner(#orderId, authentication)")
    fun viewSensitiveDetails(orderId: OrderId): OrderDetail { ... }
}
// WRONG: @PreAuthorize on Controller -- FORBIDDEN; always place on Service layer
```

### @EnableMethodSecurity Requirement

```kotlin
@Configuration @EnableMethodSecurity(prePostEnabled = true)
class MethodSecurityConfig
// Required for @PreAuthorize to work. Place in App module config package.
```

---

## 10. Annotation Composition

### @DomainService = @Service + @Transactional(readOnly = true)

```kotlin
@Target(AnnotationTarget.CLASS) @Retention(AnnotationRetention.RUNTIME)
@Service @Transactional(readOnly = true)
annotation class DomainService

@DomainService
class OrderQueryUseCase(private val reader: OrderReader) {
    fun findById(id: OrderId): Order? = reader.getOrNull(id)
}
```

### @WriteService = @Service + @Transactional

```kotlin
@Target(AnnotationTarget.CLASS) @Retention(AnnotationRetention.RUNTIME)
@Service @Transactional
annotation class WriteService

@WriteService
class CreateOrderUseCase(private val repo: OrderRepository) {
    fun execute(command: CreateOrderCommand): Order { ... }
}
```

### @ApiController = @RestController + @RequestMapping + @Validated

```kotlin
@Target(AnnotationTarget.CLASS) @Retention(AnnotationRetention.RUNTIME)
@RestController @RequestMapping @Validated
annotation class ApiController(
    @get:AliasFor(annotation = RequestMapping::class, attribute = "value") val value: Array<String> = []
)

@ApiController(["/api/v1/orders"])
class OrderController(private val createUseCase: CreateOrderUseCase) {
    @PostMapping
    fun create(@Valid @RequestBody req: CreateOrderHttpRequest) = createUseCase.execute(req.toCommand()).toResponse()
}
```

### @IntegrationTest Composed Annotation

```kotlin
@Target(AnnotationTarget.CLASS) @Retention(AnnotationRetention.RUNTIME)
@SpringBootTest @ActiveProfiles("test") @Transactional
annotation class IntegrationTest  // usage: @IntegrationTest class MyTest { ... }
```

---

*Reference for agents S5 (Convention Verifier) and B5 (Implementation Guide). Source: Kotlin/Spring Boot idiom catalog.*
