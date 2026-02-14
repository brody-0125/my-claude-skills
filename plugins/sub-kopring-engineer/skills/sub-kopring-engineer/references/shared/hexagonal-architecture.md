# Hexagonal Architecture (Ports & Adapters)

Uses Hexagonal Architecture, with strictly defined dependency directions between each layer.

## Layer Structure

```
app (API/Batch/Consumer) → application → core (domain-model + ports)
                                ↓
                          infrastructure
```

## Layering Principles Implementation

This Hexagonal Architecture implements Martin Fowler's general layering principles as follows:

- **Low coupling**: Communication between modules is done only through explicit Port interfaces
- **Business logic isolation**: Concentrated in core/domain-model + application; app/infrastructure handle only technical concerns
- **Dependency direction**: Outside → Inside (app → application → core ← infrastructure); reverse direction prohibited
- **Use of abstraction**: The application layer references technical services only through Ports (abstractions)
- **Independent testing**: core can be tested without Spring; infrastructure can be independently tested with Mock Ports
- **Logical separation**: Layers are logical divisions and do not necessarily correspond to physical deployment units

> General principles in detail: [layering-principles.md](./layering-principles.md)

### Responsibilities per Module

#### `core/domain-model`
- **Pure domain entities and value objects**
- No external dependencies (except validation)
- Business rules included in constructors/methods

#### `core`
- **Port interface definitions** (abstractions for external dependencies)
- **Repository interfaces** (Reader/Appender/Updater pattern)
- Use case interfaces
- Domain service interfaces

#### `application`
- **Use case implementations**
- Business logic combining Ports and Repositories
- Transaction management
- Domain event publishing

#### `infrastructure`
- **Port/Repository adapter implementations**
- JPA entity to domain model conversion
- External service clients

#### `app/*`
- **Entry points** (REST Controller, Batch Job, Consumer)
- Dependency assembly via Spring DI
- HTTP request/response models

---

## Dependency Rules

1. **core/domain-model**: Does not depend on any module
2. **core**: Depends only on domain-model
3. **application**: Depends on core, domain-model
4. **infrastructure**: Depends on core, domain-model (dependency on application is prohibited)
5. **app**: Can depend on all modules (runtime assembly)

---

## Layer Constraints

### No Cross-referencing Between Use Cases

A Use Case (Service in the application layer) cannot directly reference another Use Case.

```kotlin
// ❌ Prohibited: Referencing another Use Case from a Use Case
@Service
class OrderCreationService(
    private val orderLabelAssignService: OrderLabelAssignService, // Use Case reference prohibited
) : OrderCreation

// ✅ Allowed: Referencing a Port from a Use Case
@Service
class OrderCreationService(
    private val labelAssigner: DomainEntityAttributeAssigner, // Port reference
) : OrderCreation
```

When shared logic is needed:
- Abstract through a **Port interface** and implement in infrastructure
- **Internal (Domain) Service**: Define as a pure domain service with no external dependencies (located in the domain-model module)
- Extract into **pure functions/objects in domain-model** for reuse

### No Port References Within Infrastructure

Within infrastructure sub-modules such as persistence-mysql, Port interfaces (Reader/Appender/Updater, etc.) cannot be referenced.

```kotlin
// ❌ Prohibited: Referencing a Port within persistence-mysql
@Repository
class OrderAssignerAdapter(
    private val orderReader: OrderReader, // Port reference prohibited
) : OrderAssigner

// ✅ Allowed: Using JPA Repository directly within persistence-mysql
@Repository
class OrderAssignerAdapter(
    private val orderJpaRepository: OrderJpaRepository, // Direct JPA Repository usage
) : OrderAssigner
```

When complex business logic is needed in an Adapter:
- **Pure functions/objects**: Extract stateless logic into objects or functions in domain-model
- The Adapter fetches data -> calls domain logic -> updates based on the result

### No Direct Repository/Port References from App (Controller)

REST Controllers and other App layer components cannot directly inject Repository interfaces like Reader/Appender/Updater or Ports. Business logic must be accessed only through Use Cases.

```kotlin
// ❌ Prohibited: Direct Reader reference from Controller
@RestController
class OrderRetrieveRestController(
    private val orderReader: OrderReader, // Direct Port/Repository reference prohibited
) { ... }

// ✅ Allowed: Reference only Use Cases from Controller
@RestController
class OrderRetrieveRestController(
    private val orderRetrieve: OrderRetrieve, // Use Case reference
) { ... }
```

When data retrieval is needed, create a separate query Use Case or add query functionality to an existing Use Case.

---

## Port/Adapter Pattern

```kotlin
// Port (defined in core module)
interface NotificationPort {
    fun send(channel: String, title: String, body: String)
}

// Adapter (implemented in infrastructure module)
@Component
class SlackNotificationAdapter(
    private val slackClient: SlackClient,
) : NotificationPort {
    override fun send(channel: String, title: String, body: String) { ... }
}
```

---

## Repository Pattern (Reader/Appender/Updater)

```kotlin
// Role-based interface separation in core module
interface OrderReader {
    fun getById(id: Long): Order
    fun getByIdOrNull(id: Long): Order?
}

interface OrderAppender {
    fun append(order: Order): Order
}

interface OrderUpdater {
    fun update(orderId: Long, definition: OrderUpdateDefinition): Order
}

// A single Repository in infrastructure implements multiple interfaces
@Repository
class OrderRepository(...) : OrderReader, OrderAppender, OrderUpdater
```

### findBy vs findByOrNull Selection Criteria
- **Update/Delete logic**: Do not validate existence in the Use Case; use `findBy` within the Repository (throws exception if not found)
- **Conditional creation logic**: Use `findByOrNull` when the logic updates if exists, creates if not

```kotlin
// ❌ Unnecessary existence check in Use Case
fun execute(command: Command) {
    val entity = reader.getByIdOrNull(command.id)
    requireBusiness(entity != null, ...)  // unnecessary
    updater.update(command.id, definition)
}

// ✅ Skip validation in Use Case, use findBy in Repository
fun execute(command: Command) {
    return updater.update(command.id, definition)
}
// Repository
override fun update(id: Long, definition: Definition) {
    val entity = jpaRepository.findBy(id)  // throws exception if not found
    // ...
}
```

---

## Definition Pattern (CreationDefinition / UpdateDefinition)

State changes via `copy()` on domain models are prohibited. Use the Definition pattern instead.

```kotlin
// ❌ Using domain model copy() is prohibited
fun execute(command: Command): Entity {
    val entity = reader.getById(command.id)
    val updated = entity.copy(name = command.name)  // prohibited
    return updater.update(updated)
}

// ✅ Use the Definition pattern
// 1. Define the Definition (core/domain-model)
data class EntityUpdateDefinition(
    val name: String? = null,
    val status: Status? = null,
)

// 2. Updater interface (core)
interface EntityUpdater {
    fun update(id: Long, definition: EntityUpdateDefinition): Entity
}

// 3. Usage in Service (application)
fun execute(command: Command): Entity {
    val entity = reader.getById(command.id)
    return updater.update(
        id = entity.id,
        definition = EntityUpdateDefinition(name = command.name),
    )
}

// 4. JPA Entity update in Repository (infrastructure)
override fun update(id: Long, definition: EntityUpdateDefinition): Entity {
    val jpaEntity = jpaRepository.findBy(id)
    definition.name?.let { jpaEntity.name = it }
    definition.status?.let { jpaEntity.status = it }
    return jpaEntity.toModel()
}
```

### CreationDefinition

The same pattern applies for creation:

```kotlin
data class EntityCreationDefinition(
    val workspaceId: Long,
    val name: String,
    val type: EntityType,
)

interface EntityAppender {
    fun append(definition: EntityCreationDefinition): Entity
}
```

---

## Domain Modeling Patterns

### Sealed Class/Interface for Polymorphism
```kotlin
sealed interface Identifier {
    val sanitized: String
    val masked: String

    data class TypeA(private val value: String) : Identifier
    data class TypeB(val sensitiveValue: String) : Identifier
}
```

### Value Object with Validation
```kotlin
class Email private constructor(val sanitized: String) {
    init {
        requireBusiness(
            condition = isValid(sanitized),
            errorCodeBook = ErrorCodeBook.INVALID_EMAIL_FORMAT,
        )
    }

    companion object {
        fun of(text: String): Email = Email(sanitize(text))
        fun ofNullable(text: String?): Email? = text?.let { of(it) }
    }
}
```

### Aggregate Root Invariants
```kotlin
fun changeStatus(newStatus: Status): Entity {
    requireBusiness(
        condition = this.status == Status.PENDING,
        errorCodeBook = ErrorCodeBook.STATUS_COULD_NOT_CHANGE,
    )
    return this.apply { ... }
}
```

---

## Transaction Management

- **Read-only transactions**: Use Read Replica
- **Write transactions**: Use Primary DB
- **Distributed lock**: Redis-based

```kotlin
@DistributedLock(
    name = ENTITY_UPDATE_LOCK_PREFIX,
    key = ["#command.entityId"],
)
override fun execute(command: Command): Entity
```

---

## JPA Entity <-> Domain Model Conversion

```kotlin
// JPA Entity → Domain Model
fun OrderJpaEntity.toModel(): Order = Order(
    id = id,
    name = name,
    ...
)

// Domain Model → JPA Entity
companion object {
    fun from(order: Order): OrderJpaEntity = OrderJpaEntity(...)
}
```

Conversion logic is managed only in the Infrastructure layer, and domain models do not contain JPA annotations.

---

## Testing Strategy

### Principle: Stub Ports, Don't Mock Them

Port interfaces are **contracts** between the application and the outside world.
Testing with Stubs (state verification) produces tests that are resilient to refactoring.

### Port/Repository Stub 패턴

Port Stub과 Repository Stub(Reader/Appender/Updater) 구현 예제는 언어별 테스트 가이드를 참조한다:

- **Kotlin**: [unit-testing.md § Test Fixtures](./unit-testing.md#test-fixtures) — Fake Repository, Port Stub, Spy
- **Java**: [java-unit-testing.md § Test Fixtures](./java-unit-testing.md#test-fixtures)

핵심 원칙:
- Port 인터페이스 → Stub 구현 (in-memory state, deterministic)
- Reader/Appender/Updater → 하나의 FakeRepository가 복수 인터페이스 구현
- Failure simulation → throwable 파라미터로 예외 주입

### testFixtures Module Structure

```
core/src/testFixtures/kotlin/  ← Port Stub, Repository Stub 배치
application/src/test/kotlin/   ← testFixtures(project(":core")) 참조
infrastructure/src/test/kotlin/ ← testFixtures(project(":core")) 참조
```

```kotlin
// core/build.gradle.kts
plugins { `java-test-fixtures` }

// application/build.gradle.kts
dependencies { testImplementation(testFixtures(project(":core"))) }
```

---

## Multi-Module Hexagonal Architecture

### Module Separation Strategy

Gradle 멀티모듈에서 Hexagonal 레이어를 모듈로 분리하는 표준 패턴:

```
project-root/
├── settings.gradle.kts
├── build-logic/              ← Convention Plugins
│   └── src/main/kotlin/
├── core/                     ← Domain Model + Port Interfaces
│   └── build.gradle.kts      (의존성: 없음 — 순수 Kotlin/Java)
├── application/              ← Use Case Services
│   └── build.gradle.kts      (의존성: core)
├── infrastructure/           ← Adapter/Repository 구현
│   └── build.gradle.kts      (의존성: core, Spring Data, JOOQ 등)
├── api/                      ← Controller, HTTP Models
│   └── build.gradle.kts      (의존성: application)
└── bootstrap/                ← Spring Boot Main, Configuration
    └── build.gradle.kts      (의존성: 전체 — runtime assembly)
```

### Module Dependency Rules

```kotlin
// core/build.gradle.kts — 외부 의존성 없음
dependencies {
    // 순수 Kotlin/Java만 허용. Spring, JPA 등 금지
}

// application/build.gradle.kts
dependencies {
    implementation(project(":core"))
}

// infrastructure/build.gradle.kts
dependencies {
    implementation(project(":core"))
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
}

// api/build.gradle.kts
dependencies {
    implementation(project(":application"))
}

// bootstrap/build.gradle.kts
dependencies {
    implementation(project(":api"))
    implementation(project(":infrastructure"))
}
```

**금지 의존성 (컴파일 타임에 강제):**

| From | To (금지) | 이유 |
|------|-----------|------|
| core | application, infrastructure, api | 의존성 역전 위반 |
| application | infrastructure, api | Port를 통해서만 접근 |
| infrastructure | application, api | core의 Port만 구현 |
| api | infrastructure | bootstrap에서 조립 |

### Single Module Structure

단일 모듈 프로젝트에서는 패키지로 레이어를 분리한다:

```
src/main/kotlin/com/example/
├── core/
│   ├── domain-model/
│   └── (Port interfaces)
├── application/
├── infrastructure/
└── app/
```

단일 모듈에서도 동일한 의존성 방향 규칙이 적용되며, 패키지 간 import로 검증한다.

---

## Domain-Based Module Separation

대규모 프로젝트에서 도메인별 모듈 분리 패턴:

```
project-root/
├── order/
│   ├── order-core/           ← Order 도메인 모델 + Port
│   ├── order-application/    ← Order Use Case
│   └── order-infrastructure/ ← Order Adapter
├── payment/
│   ├── payment-core/
│   ├── payment-application/
│   └── payment-infrastructure/
├── shared-kernel/            ← 도메인 간 공유 타입
│   └── build.gradle.kts      (의존성: 없음)
├── api/                      ← 통합 API (모든 application 모듈 참조)
└── bootstrap/                ← Spring Boot Main
```

### Shared Kernel

도메인 간 공유가 필요한 타입을 shared-kernel 모듈에 배치한다:

```kotlin
// shared-kernel/src/main/kotlin/

// 공유 Value Object
data class Money(val amount: Long, val currency: Currency)
data class Address(val city: String, val street: String, val zipCode: String)

// Domain Event 인터페이스
interface DomainEvent {
    val occurredAt: Instant
    val aggregateId: Long
}

// 공통 예외 타입
abstract class DomainException(
    val errorCode: ErrorCodeBook,
    val detail: String,
    val properties: Map<String, Any> = emptyMap(),
) : RuntimeException(detail)
```

**Shared Kernel 규칙:**
- 의존성 없음 (core 모듈과 동일 레벨)
- 변경 시 모든 참조 도메인에 영향 → 변경에 보수적이어야 함
- 도메인별 core 모듈이 shared-kernel을 참조: `implementation(project(":shared-kernel"))`
- 비즈니스 로직 포함 금지 (순수 타입 정의만)

---

## Event-Driven Inter-Module Communication

모듈 간 직접 참조 대신 이벤트 기반 통신을 사용한다.

### 이벤트 정의 (core 모듈)

```kotlin
// order-core/src/main/kotlin/.../event/
sealed class OrderEvent : DomainEvent {
    data class Created(
        override val aggregateId: Long,
        val customerId: Long,
        val totalAmount: Money,
        override val occurredAt: Instant = Instant.now(),
    ) : OrderEvent()

    data class Cancelled(
        override val aggregateId: Long,
        val reason: String,
        override val occurredAt: Instant = Instant.now(),
    ) : OrderEvent()
}
```

### 이벤트 발행 (application 모듈)

```kotlin
// order-application
@Service
class OrderCancelService(
    private val orderReader: OrderReader,
    private val orderUpdater: OrderUpdater,
    private val eventPublisher: ApplicationEventPublisher,
) : OrderCancel {
    @Transactional
    override fun execute(command: CancelCommand): Order {
        val order = orderReader.getById(command.orderId)
        val cancelled = orderUpdater.update(
            orderId = order.id,
            definition = OrderUpdateDefinition(status = OrderStatus.CANCELLED),
        )
        eventPublisher.publishEvent(
            OrderEvent.Cancelled(aggregateId = order.id, reason = command.reason)
        )
        return cancelled
    }
}
```

### 이벤트 소비 (다른 도메인의 application 모듈)

```kotlin
// payment-application
@Component
class OrderEventHandler(
    private val paymentCanceller: PaymentCanceller,
) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleOrderCancelled(event: OrderEvent.Cancelled) {
        paymentCanceller.cancelByOrderId(event.aggregateId)
    }
}
```

### Inter-Module Communication 규칙

| 규칙 | 설명 |
|------|------|
| 직접 참조 금지 | 다른 도메인의 application/infrastructure 모듈을 직접 `implementation`하지 않는다 |
| Event 경유 | shared-kernel의 DomainEvent 인터페이스 또는 다른 도메인의 core에 정의된 이벤트를 통해 통신 |
| AFTER_COMMIT | 이벤트 핸들러는 `@TransactionalEventListener(phase = AFTER_COMMIT)` 사용 |
| Immutable Event | 이벤트 객체는 data class로 정의하며, var 프로퍼티 금지 |
| 단방향 의존 | 이벤트 소비 모듈은 이벤트 발행 모듈의 **core만** 참조 가능 (application/infrastructure 참조 금지) |

---

## ArchUnit Architecture Tests

프로젝트에 ArchUnit이 포함된 경우, 아키텍처 규칙을 코드로 강제할 수 있다.

### 의존성 방향 테스트

```kotlin
@AnalyzeClasses(packages = ["com.example"])
class HexagonalArchitectureTest {

    @ArchTest
    val `core는 외부 레이어에 의존하지 않는다` = noClasses()
        .that().resideInAPackage("..core..")
        .should().dependOnClassesThat()
        .resideInAnyPackage("..application..", "..infrastructure..", "..app..")

    @ArchTest
    val `application은 infrastructure에 의존하지 않는다` = noClasses()
        .that().resideInAPackage("..application..")
        .should().dependOnClassesThat()
        .resideInAnyPackage("..infrastructure..", "..app..")

    @ArchTest
    val `infrastructure는 application에 의존하지 않는다` = noClasses()
        .that().resideInAPackage("..infrastructure..")
        .should().dependOnClassesThat()
        .resideInAnyPackage("..application..", "..app..")
}
```

### Port/Adapter 규칙 테스트

```kotlin
@AnalyzeClasses(packages = ["com.example"])
class PortAdapterRuleTest {

    @ArchTest
    val `Controller는 UseCase만 참조한다` = classes()
        .that().resideInAPackage("..app..")
        .and().areAnnotatedWith(RestController::class.java)
        .should().onlyDependOnClassesThat()
        .resideInAnyPackage("..app..", "..application..", "..core.domain..", "java..", "kotlin..", "org.springframework.web..")

    @ArchTest
    val `Infrastructure 내부에서 Port를 참조하지 않는다` = noClasses()
        .that().resideInAPackage("..infrastructure.persistence..")
        .should().dependOnClassesThat()
        .areInterfaces()
        .and().resideInAPackage("..core..")
        .andShould().haveSimpleNameEndingWith("Reader")
        .orShould().haveSimpleNameEndingWith("Appender")
        .orShould().haveSimpleNameEndingWith("Updater")
}
```

### build.gradle.kts 설정

```kotlin
dependencies {
    testImplementation("com.tngtech.archunit:archunit-junit5:1.3.0")
}
```

> ArchUnit 테스트 실패 시 해결 절차는 [Error Playbook § 10. ArchUnit Violations](../resources/error-playbook.md)을 참조한다.
