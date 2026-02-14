# Java Code Style Guide

> Java code style guide that corresponds 1:1 with the Kotlin code-style-guide.md.
> Loaded when the profile language is java or mixed.

---

## Java Idioms

### Records & Sealed Interfaces

```java
// Domain models: Record (Java 16+) or immutable class
public record TotalAmount(long value, Long tax) {}

// Polymorphism via sealed interface (Java 17+)
public sealed interface Receiver permits Receiver.Business, Receiver.Individual {
    record Business(String companyName, String bizNumber) implements Receiver {}
    record Individual(String name, String phone) implements Receiver {}
}

// Below Java 16: immutable POJO
@Getter
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public class TotalAmount {
    private final long value;
    private final Long tax;

    public static TotalAmount of(long value, Long tax) {
        return new TotalAmount(value, tax);
    }
}
```

### Static Utility Methods (Extension Function equivalent)

```java
// Kotlin extension function -> Java static utility
public final class TimeUtils {
    private TimeUtils() {}

    public static LocalDate toLocalDate(Instant instant, ZoneId zoneId) {
        return instant.atZone(zoneId).toLocalDate();
    }

    public static Instant toInstant(String text, String pattern) {
        return LocalDateTime.parse(text, DateTimeFormatter.ofPattern(pattern))
                .atZone(ZoneId.systemDefault()).toInstant();
    }
}

// Null-safe operations
public final class Preconditions {
    public static <T> T requireNotNull(T value, String message) {
        if (value == null) throw new IllegalArgumentException(message);
        return value;
    }
}
```

### Factory Methods

```java
// Kotlin companion object -> Java static factory
public class Order {
    public static Order from(OrderJpaEntity entity) {
        return new Order(entity.getId(), entity.getStatus(), ...);
    }

    public static ValueObject of(String text) {
        return new ValueObject(sanitize(text));
    }

    public static ValueObject ofNullable(String text) {
        return text == null ? null : of(text);
    }
}
```

---

## Method Rules

> Same rules as Kotlin — see [code-style-guide.md § Method Rules](./code-style-guide.md#method-rules):
> - No extracting single-use methods (keep inline if only one call site)
> - Return values must be used (no ignored returns)
> - No test-only methods in production code

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
| REST Controller | `{Feature}RestController` (or profile) | `OrderFetchRestController` |
| Service | `{Feature}Service` | `OrderUpdateService` |
| Port | `{Feature}Port` | `NotificationPort` |
| Adapter | `{Feature}Adapter` | `SlackNotificationAdapter` |
| Request/Response | `{Feature}Request` / `{Feature}Response` | `OrderCreateRequest` |

> **Never use `*Dto` suffix.** Domain models use plain names (`Order` O, `OrderDto` X).
> Persistence entities **always** include the framework name: `{Name}{Framework}Entity`.

### Functions

| Type | Pattern | Example |
|------|---------|---------|
| Nullable getter | `findById` / `getByIdOrNull` | `findById(id)` |
| Throwing getter | `getById` | `getById(id)` |
| Factory | `from`, `of` | `Email.of(text)` |
| Converter | `toModel`, `toEntity` | `entity.toModel()` |
| Command handler | `execute` | `execute(command)` |

### Repository Interfaces

**Hexagonal Architecture:** Same Reader/Appender/Updater separation as Kotlin.

```java
public interface OrderReader {
    Order getById(Long id);
    Order getByIdOrNull(Long id);
}
public interface OrderAppender {
    Order append(OrderCreationDefinition definition);
}
public interface OrderUpdater {
    Order update(Long id, OrderUpdateDefinition definition);
}
// Implementation: OrderRepository implements OrderReader, OrderAppender, OrderUpdater
```

---

## JPA Entity Patterns

### Entity Structure

```java
@Entity
@Table(name = "orders")
@DynamicUpdate
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class OrderJpaEntity extends BaseAuditingJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Embedded
    private OrderDetails details;

    @Convert(converter = BooleanToYNConverter.class)
    private Boolean isActive;

    @ManyToOne(fetch = FetchType.EAGER, cascade = CascadeType.ALL)
    private ParentJpaEntity parentEntity;

    // Creation factory
    public static OrderJpaEntity from(Order domain) {
        var entity = new OrderJpaEntity();
        entity.id = domain.getId();
        entity.details = OrderDetails.from(domain);
        entity.isActive = domain.getIsActive();
        return entity;
    }

    // Domain conversion
    public Order toModel() {
        return new Order(id, details.toModel(), isActive);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof OrderJpaEntity that)) return false;
        return id != null && Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }
}
```

### Embeddable Usage

Same as Kotlin. Map column names with `@Embeddable` + `@AttributeOverrides`.

### QueryDSL Custom Repository Pattern

```java
// Interface definition
public interface OrderFetcher extends BaseJpaRepository<OrderJpaEntity, Long>, OrderFetcherCustom {}

public interface OrderFetcherCustom {
    List<OrderJpaEntity> findAllActiveByWorkspaceIdIn(List<Long> workspaceIds);
}

// Implementation (must follow {Interface}Impl naming)
@RequiredArgsConstructor
public class OrderFetcherCustomImpl implements OrderFetcherCustom {
    private final JPAQueryFactory jpaQueryFactory;
    private final QOrderJpaEntity qOrder = QOrderJpaEntity.orderJpaEntity;

    @Override
    public List<OrderJpaEntity> findAllActiveByWorkspaceIdIn(List<Long> workspaceIds) {
        return jpaQueryFactory
                .selectFrom(qOrder)
                .where(qOrder.workspaceId.in(workspaceIds))
                .fetch();
    }
}
```

---

## Spring Boot Patterns

### Constructor Injection Only

```java
// @RequiredArgsConstructor + private final (when using Lombok)
@Service
@RequiredArgsConstructor
public class OrderUpdateService {
    private final OrderReader orderReader;
    private final OrderAppender orderAppender;
    private final DomainNotificationEventPublisher domainEventPublisher;
}

// Without Lombok
@Service
public class OrderUpdateService {
    private final OrderReader orderReader;
    private final OrderAppender orderAppender;

    public OrderUpdateService(OrderReader orderReader, OrderAppender orderAppender) {
        this.orderReader = orderReader;
        this.orderAppender = orderAppender;
    }
}
```

### Controller Structure

```java
@RestController
@RequiredArgsConstructor
public class OrderFetchRestController {
    private final OrderRetrieve orderRetrieve;

    @GetMapping(
        value = "/api/v1/orders/{orderId}",
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public OrderHttpResponse getOrder(@PathVariable Long orderId) {
        return OrderHttpResponse.from(orderRetrieve.execute(orderId));
    }
}
```

---

## Minimal Lombok Usage Policy

| Annotation | Allowed | Purpose |
|-------------|-----------|------|
| `@Getter` | Allowed | Read access |
| `@Setter` | Conditional | Prohibited on Entity, allowed on DTO only |
| `@RequiredArgsConstructor` | Allowed | Constructor for DI |
| `@NoArgsConstructor(access = PROTECTED)` | Allowed | For JPA Entity |
| `@Builder` | Conditional | Only when needed (default is static factory) |
| `@Data` | Prohibited | Auto-generated equals/hashCode is dangerous with JPA |
| `@EqualsAndHashCode` | Conditional | Only with `(of = "id")` specified |
| `@ToString` | Conditional | Only with `(of = "id")` specified |

---

## Error Handling

### Business Exception

```java
// Equivalent to Kotlin requireBusiness()
if (!UPDATABLE_STATUSES.contains(entity.getStatus())) {
    throw new ApplicationBusinessException(
        ErrorCodeBook.COULD_NOT_CHANGE_ON_CURRENT_STATUS,
        Map.of("id", id, "status", status)
    );
}

// Or using Guava/custom utility
Preconditions.checkBusiness(
    UPDATABLE_STATUSES.contains(entity.getStatus()),
    ErrorCodeBook.COULD_NOT_CHANGE_ON_CURRENT_STATUS
);
```

### ProblemDetail (RFC 7807/9457)

```java
// Error hierarchy - sealed interface (Java 17+) or abstract class
public abstract class DomainException extends RuntimeException {
    private final ErrorCodeBook errorCode;
    private final Map<String, Object> properties;

    protected DomainException(ErrorCodeBook errorCode, String detail, Map<String, Object> properties) {
        super(detail);
        this.errorCode = errorCode;
        this.properties = properties;
    }
    // getters...
}

public class OrderNotFoundException extends DomainException {
    public OrderNotFoundException(Long orderId) {
        super(ErrorCodeBook.ORDER_NOT_FOUND, "Order not found: " + orderId, Map.of("orderId", orderId));
    }
}

// @ControllerAdvice + ProblemDetail
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(DomainException.class)
    public ProblemDetail handleDomain(DomainException ex) {
        var problem = ProblemDetail.forStatusAndDetail(
            ex.getErrorCode().getHttpStatus(), ex.getMessage()
        );
        problem.setTitle(ex.getErrorCode().name());
        problem.setProperty("errorCode", ex.getErrorCode().getCode());
        ex.getProperties().forEach(problem::setProperty);
        return problem;
    }
}
```

---

## Spring Security Conventions

### SecurityFilterChain Bean Pattern

```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/public/**", "/actuator/health").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }
}
```

### @PreAuthorize on Service (NOT Controller)

```java
// Authorization checks on Service
@Service
@RequiredArgsConstructor
public class OrderUpdateService {
    @PreAuthorize("hasRole('ADMIN') or #command.userId == authentication.principal.id")
    public Order execute(UpdateCommand command) { ... }
}
```

**Validation rules**: Same as the Kotlin guide.

---

## Spring Event Patterns

```java
// Immutable event (record)
public sealed interface OrderEvent {
    record Cancelled(Long orderId, String reason, Instant cancelledAt) implements OrderEvent {}
    record Completed(Long orderId, Instant completedAt) implements OrderEvent {}
}

// Publishing
@Service
@RequiredArgsConstructor
public class OrderCancelService {
    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public void cancel(CancelCommand command) {
        // ... business logic
        eventPublisher.publishEvent(new OrderEvent.Cancelled(order.getId(), command.getReason(), Instant.now()));
    }
}

// Subscribing - AFTER_COMMIT recommended
@Component
public class OrderEventHandler {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleCancelled(OrderEvent.Cancelled event) { ... }
}
```

**Anti-patterns**: Same as the Kotlin guide (mutable events prohibited, TransactionPhase must be specified).

---

## Advanced JPA Patterns

> N+1 prevention, Projection, Soft Delete, Auditing — see [code-style-guide.md § Advanced JPA Patterns](./code-style-guide.md#advanced-jpa-patterns).
> Java syntax differs only in `Optional<>` return types and `@Getter` on base entity. Key differences:

```java
// Java: Optional return + @Getter on base entity
@EntityGraph(attributePaths = {"details", "items"})
Optional<OrderJpaEntity> findByIdWithDetails(Long id);

@EntityListeners(AuditingEntityListener.class)
@MappedSuperclass
@Getter  // Java requires explicit @Getter (vs Kotlin val)
public abstract class BaseAuditingJpaEntity { ... }
```

---

## Caching / Virtual Threads / Testcontainers / Transaction Management

> These patterns are identical to Kotlin — see [code-style-guide.md](./code-style-guide.md) for full examples.
> Java-specific notes:

| Topic | Java-specific difference |
|-------|------------------------|
| Virtual Threads | Prefer `ReentrantLock` over `synchronized` (prevents pinning) |
| Testcontainers | `static` field (vs Kotlin `companion object`) |
| Structured Logging | `logger.info("Order " + id)` prohibited → use `logger.info("Order {}", id)` |

---

## Code Formatting

- Max line length: 140
- Indent: 4 spaces
- Star import: Prohibited
- Follow Checkstyle or Spotless configuration
- Do not overuse `@SuppressWarnings`

### Key Checkstyle Rules (Based on Google Java Style)

```
- IndentationCheck (4 spaces)
- LineLength (140)
- AvoidStarImport
- UnusedImports
- NeedBraces (always use braces)
```
