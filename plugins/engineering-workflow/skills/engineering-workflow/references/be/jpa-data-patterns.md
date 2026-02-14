# JPA, Data Access & Gradle Build Patterns

> Reference for S-5 (Convention Verifier) and B-5 (Implementation Guide) agents.
> Covers JPA entity conventions, repository design, QueryDSL/JOOQ adapters, Gradle multi-module builds,
> soft delete, and Spring Data auditing.

---

## 1. Entity-Model Separation Pattern

Domain models live in Core (no JPA annotations). JPA entities live in Infrastructure (persistence).
Conversion happens exclusively in Infrastructure adapters via `toModel()` / `toEntity()`.

### Domain Model (Core Layer)

```kotlin
// core/domain/order/Order.kt -- pure Kotlin, no JPA
data class Order(
    val id: OrderId,
    val customerId: CustomerId,
    val status: OrderStatus,
    val items: List<OrderItem>,
    val totalAmount: Money,
    val orderedAt: Instant,
    val memo: String? = null
) {
    fun cancel(): Order {
        require(status == OrderStatus.PLACED) { "Only PLACED orders can be cancelled" }
        return copy(status = OrderStatus.CANCELLED)
    }
}
```

### JPA Entity (Infrastructure Layer)

```kotlin
// infrastructure/persistence-mysql/order/OrderJpaEntity.kt
@Entity
@Table(name = "orders")
@DynamicUpdate
class OrderJpaEntity(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L,
    @Column(nullable = false) val customerId: Long,
    @Enumerated(EnumType.STRING) @Column(nullable = false) var status: OrderStatus,
    @Column(nullable = false) val totalAmount: BigDecimal,
    @Column(nullable = false) val orderedAt: Instant,
    val memo: String? = null
) : BaseAuditEntity() {

    companion object {
        fun from(order: Order): OrderJpaEntity = OrderJpaEntity(
            id = order.id.value, customerId = order.customerId.value,
            status = order.status, totalAmount = order.totalAmount.value,
            orderedAt = order.orderedAt, memo = order.memo
        )
    }

    fun toModel(): Order = Order(
        id = OrderId(id), customerId = CustomerId(customerId),
        status = status, items = emptyList(),
        totalAmount = Money.of(totalAmount), orderedAt = orderedAt, memo = memo
    )
}
```

### Conversion Extension Functions (Alternative)

```kotlin
fun Order.toEntity(): OrderJpaEntity = OrderJpaEntity.from(this)
fun OrderJpaEntity.toDomain(): Order = this.toModel()
```

### Rules

- Domain model MUST NOT import `jakarta.persistence.*`
- Conversion logic is ONLY in Infrastructure adapter or mapper
- `toModel()` / `toEntity()` are the standard conversion method names

---

## 2. JPA Entity Best Practices

### @DynamicUpdate on All Entities

```kotlin
@Entity @Table(name = "invoices")
@DynamicUpdate  // REQUIRED: UPDATE only changed columns
class InvoiceJpaEntity(/* ... */)
```

Prevents overwriting unchanged columns, reducing lock contention.

### @Embeddable for Value Objects

```kotlin
@Embeddable
data class Address(
    @Column(name = "address_street") val street: String,
    @Column(name = "address_city") val city: String,
    @Column(name = "address_zip_code") val zipCode: String
)

@Entity @Table(name = "customers")
class CustomerJpaEntity(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) val id: Long = 0L,
    @Embedded val address: Address
)
```

### Protected No-Arg Constructor

Use `kotlin-jpa` compiler plugin to auto-generate protected no-arg constructors
for `@Entity`, `@Embeddable`, and `@MappedSuperclass`:

```kotlin
plugins { kotlin("plugin.jpa") version libs.versions.kotlin.get() }
```

### equals() / hashCode() on Business Key

```kotlin
@Entity @Table(name = "products")
class ProductJpaEntity(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) val id: Long = 0L,
    @Column(nullable = false, unique = true) val sku: String
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ProductJpaEntity) return false
        return sku == other.sku  // business key, NOT database ID
    }
    override fun hashCode(): Int = sku.hashCode()
}
```

- NEVER use `id` (database-generated PK) in `equals()` / `hashCode()`
- Use a business key; if none exists, use a UUID assigned at construction time

### @MappedSuperclass for Audit Fields

```kotlin
@MappedSuperclass
@EntityListeners(AuditingEntityListener::class)
abstract class BaseAuditEntity(
    @CreatedDate @Column(nullable = false, updatable = false) var createdAt: Instant = Instant.MIN,
    @LastModifiedDate @Column(nullable = false) var updatedAt: Instant = Instant.MIN
)
```

---

## 3. Cascade Management

| Cascade Type | Allowed | Reason |
|-------------|---------|--------|
| `PERSIST` | YES | Parent save propagates to new children |
| `MERGE` | YES | Parent update propagates to detached children |
| `REMOVE` | NO | Use explicit delete -- prevents accidental mass deletion |
| `ALL` | NO | Includes REMOVE -- too dangerous |

```kotlin
@OneToMany(mappedBy = "order",
    cascade = [CascadeType.PERSIST, CascadeType.MERGE],  // explicit and safe
    orphanRemoval = true,  // ONLY for genuine parent-child aggregates
    fetch = FetchType.LAZY)
val items: MutableList<OrderItemJpaEntity> = mutableListOf()
```

### N+1 Prevention

```kotlin
// @EntityGraph (declarative)
@EntityGraph(attributePaths = ["items", "items.product"])
fun findWithItemsById(id: Long): OrderJpaEntity?

// JOIN FETCH (JPQL)
@Query("SELECT o FROM OrderJpaEntity o JOIN FETCH o.items WHERE o.id = :id")
fun findWithItemsFetched(@Param("id") id: Long): OrderJpaEntity?

// @BatchSize (global lazy loading optimization)
@BatchSize(size = 100)
@OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
val items: MutableList<OrderItemJpaEntity> = mutableListOf()
```

---

## 4. Repository Pattern

### Role-Based Interface Separation (Core Layer)

```kotlin
interface OrderReader {
    fun findById(id: OrderId): Order?
    fun findByCustomerId(customerId: CustomerId): List<Order>
    fun existsById(id: OrderId): Boolean
}
interface OrderAppender { fun save(order: Order): Order }
interface OrderUpdater  { fun update(order: Order): Order }
interface OrderDeleter  { fun deleteById(id: OrderId) }

// Combined interface
interface OrderRepository : OrderReader, OrderAppender, OrderUpdater, OrderDeleter
```

### Spring Data JPA Base

```kotlin
interface OrderJpaRepository : JpaRepository<OrderJpaEntity, Long> {
    fun findByCustomerId(customerId: Long): List<OrderJpaEntity>
    fun findByStatusAndCreatedAtBetween(
        status: OrderStatus, from: Instant, to: Instant
    ): List<OrderJpaEntity>

    @Query("SELECT o FROM OrderJpaEntity o WHERE o.status = :status AND o.totalAmount >= :minAmount ORDER BY o.createdAt DESC")
    fun findHighValueOrders(
        @Param("status") status: OrderStatus,
        @Param("minAmount") minAmount: BigDecimal
    ): List<OrderJpaEntity>
}
```

### Adapter Implementation

```kotlin
@Repository
class OrderRepositoryAdapter(
    private val jpaRepository: OrderJpaRepository
) : OrderRepository {
    override fun findById(id: OrderId): Order? =
        jpaRepository.findByIdOrNull(id.value)?.toModel()
    override fun findByCustomerId(customerId: CustomerId): List<Order> =
        jpaRepository.findByCustomerId(customerId.value).map { it.toModel() }
    override fun existsById(id: OrderId): Boolean = jpaRepository.existsById(id.value)
    override fun save(order: Order): Order = jpaRepository.save(OrderJpaEntity.from(order)).toModel()
    override fun update(order: Order): Order = jpaRepository.save(OrderJpaEntity.from(order)).toModel()
    override fun deleteById(id: OrderId) = jpaRepository.deleteById(id.value)
}
```

### Projections for Read-Only Data

```kotlin
interface OrderSummaryProjection {
    val id: Long; val status: OrderStatus; val totalAmount: BigDecimal; val orderedAt: Instant
}

@Query("SELECT o.id AS id, o.status AS status, o.totalAmount AS totalAmount, o.orderedAt AS orderedAt FROM OrderJpaEntity o WHERE o.customerId = :customerId")
fun findSummariesByCustomerId(@Param("customerId") customerId: Long): List<OrderSummaryProjection>
```

---

## 5. QueryDSL / JOOQ Adapter Pattern

### QueryDSL: Custom Repository ({Interface}Impl naming convention)

```kotlin
interface OrderQueryRepository {
    fun searchOrders(condition: OrderSearchCondition): List<Order>
}

class OrderQueryRepositoryImpl(  // MUST end with "Impl"
    private val queryFactory: JPAQueryFactory
) : OrderQueryRepository {
    private val order = QOrderJpaEntity.orderJpaEntity

    override fun searchOrders(condition: OrderSearchCondition): List<Order> =
        queryFactory.selectFrom(order)
            .where(statusEq(condition.status), amountGoe(condition.minAmount),
                   createdAtBetween(condition.from, condition.to))
            .orderBy(order.createdAt.desc())
            .offset(condition.offset).limit(condition.limit)
            .fetch().map { it.toModel() }

    private fun statusEq(status: OrderStatus?): BooleanExpression? =
        status?.let { order.status.eq(it) }
    private fun amountGoe(min: BigDecimal?): BooleanExpression? =
        min?.let { order.totalAmount.goe(it) }
    private fun createdAtBetween(from: Instant?, to: Instant?): BooleanExpression? {
        if (from != null && to != null) return order.createdAt.between(from, to)
        from?.let { return order.createdAt.goe(it) }
        to?.let { return order.createdAt.loe(it) }
        return null
    }
}
```

### QueryDSL: BooleanBuilder for Dynamic Conditions

```kotlin
fun buildDynamicWhere(condition: OrderSearchCondition): BooleanBuilder {
    val builder = BooleanBuilder()
    condition.status?.let { builder.and(order.status.eq(it)) }
    condition.minAmount?.let { builder.and(order.totalAmount.goe(it)) }
    condition.keyword?.let { builder.and(order.memo.containsIgnoreCase(it)) }
    return builder
}
```

### JOOQ: *JooqAdapter Naming (Infrastructure Only)

```kotlin
@Repository
class OrderJooqAdapter(private val dsl: DSLContext) {
    private val ORDER = Tables.ORDERS

    fun searchOrders(condition: OrderSearchCondition): List<Order> =
        dsl.selectFrom(ORDER)
            .where(buildCondition(condition))
            .orderBy(ORDER.CREATED_AT.desc())
            .offset(condition.offset).limit(condition.limit)
            .fetch().map { it.toDomain() }

    private fun buildCondition(cond: OrderSearchCondition): Condition {
        var where: Condition = DSL.noCondition()  // identity for AND
        cond.status?.let { where = where.and(ORDER.STATUS.eq(it.name)) }
        cond.minAmount?.let { where = where.and(ORDER.TOTAL_AMOUNT.ge(it)) }
        cond.from?.let { where = where.and(ORDER.CREATED_AT.ge(it)) }
        cond.to?.let { where = where.and(ORDER.CREATED_AT.le(it)) }
        return where
    }
}

// Record-to-domain mapping via extension function
fun OrdersRecord.toDomain(): Order = Order(
    id = OrderId(this.id), customerId = CustomerId(this.customerId),
    status = OrderStatus.valueOf(this.status), items = emptyList(),
    totalAmount = Money.of(this.totalAmount), orderedAt = this.createdAt, memo = this.memo
)
```

### DSLContext Injection Rules

- Inject `DSLContext` via constructor injection (never field injection)
- Only Infrastructure modules may depend on JOOQ; Core and Application MUST NOT

---

## 6. Gradle Multi-Module Build

### Convention Plugins in build-logic/

```
build-logic/
├── build.gradle.kts
├── settings.gradle.kts
└── src/main/kotlin/
    ├── kotlin-core.gradle.kts            # pure Kotlin, no Spring
    ├── kotlin-application.gradle.kts     # core + Spring tx
    ├── kotlin-infrastructure.gradle.kts  # core + Spring Data JPA
    └── kotlin-api.gradle.kts             # application + Spring Web
```

### kotlin-core.gradle.kts

```kotlin
plugins { kotlin("jvm") }
dependencies {
    implementation(project(":${rootProject.name}-lib:extensions"))  // ZERO Spring deps
}
tasks.withType<Test> { useJUnitPlatform() }
```

### kotlin-application.gradle.kts

```kotlin
plugins { id("kotlin-core") }
dependencies { implementation(libs.spring.tx) }  // spring-tx only, NO spring-web
```

### kotlin-infrastructure.gradle.kts

```kotlin
plugins { id("kotlin-core"); kotlin("plugin.jpa") }
dependencies {
    implementation(libs.spring.boot.starter.data.jpa)
    runtimeOnly(libs.mysql.connector.java)
    testImplementation(libs.testcontainers.mysql)
}
```

### kotlin-api.gradle.kts

```kotlin
plugins { id("kotlin-application"); kotlin("plugin.spring") }
dependencies {
    implementation(libs.spring.boot.starter.web)
    implementation(libs.spring.boot.starter.validation)
}
```

### Version Catalog (gradle/libs.versions.toml)

```toml
[versions]
kotlin = "1.9.25"
spring-boot = "3.3.4"
querydsl = "5.1.0"
jooq = "3.19.11"

[libraries]
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-tx = { module = "org.springframework:spring-tx" }
mysql-connector-java = { module = "com.mysql:mysql-connector-j" }
querydsl-jpa = { module = "com.querydsl:querydsl-jpa", version.ref = "querydsl" }
jooq = { module = "org.jooq:jooq", version.ref = "jooq" }
```

---

## 7. Dependency Scope Reference

| Scope | Compile | Runtime | Consumer | Use Case |
|-------|---------|---------|----------|----------|
| `implementation` | YES | YES | NO | Default choice. Module-internal dependency |
| `api` | YES | YES | YES | Exposed to consumers (Port interfaces in Core) |
| `runtimeOnly` | NO | YES | NO | JDBC drivers, JPA providers, Infrastructure in App |
| `compileOnly` | YES | NO | NO | Annotation processors |
| `testImplementation` | YES (test) | YES (test) | NO | Test-only dependencies |
| `testFixtures` | YES (test) | YES (test) | YES (test) | Shared test utilities across modules |

### testFixtures Cross-Module Syntax

```kotlin
dependencies {
    testImplementation(testFixtures(project(":${rootProject.name}-core:domain-model")))
    testImplementation(testFixtures(project(":${rootProject.name}-infrastructure:external-pg")))
}
```

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| `implementation` for JDBC driver | `runtimeOnly(libs.mysql.connector.java)` |
| `implementation` for Infrastructure in App | `runtimeOnly(project(":infrastructure:persistence-mysql"))` |
| `api` for everything | `api` ONLY when consumer must see transitive dependency |
| Missing `testFixtures` plugin | Add `java-test-fixtures` in the stub-providing module |

---

## 8. Soft Delete Pattern

### Entity Configuration

```kotlin
@Entity @Table(name = "users") @DynamicUpdate
@SQLRestriction("deleted_at IS NULL")  // Hibernate 6.3+ (replaces @Where)
class UserJpaEntity(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) val id: Long = 0L,
    @Column(nullable = false) val email: String,
    @Column(name = "deleted_at") var deletedAt: Instant? = null
) : BaseAuditEntity() {
    fun softDelete(clock: Clock = Clock.systemUTC()) { this.deletedAt = clock.instant() }
    val isDeleted: Boolean get() = deletedAt != null
}
```

### Repository Override

```kotlin
interface UserJpaRepository : JpaRepository<UserJpaEntity, Long> {
    // @SQLRestriction auto-filters soft-deleted rows for standard queries

    @Query("SELECT u FROM UserJpaEntity u WHERE u.id = :id")
    fun findByIdIncludingDeleted(@Param("id") id: Long): UserJpaEntity?
}
```

### Unique Constraint Implications

Soft-deleted records still occupy the unique slot. Solutions:

```sql
-- Partial unique index (MySQL 8.0.13+ / PostgreSQL)
CREATE UNIQUE INDEX uk_users_email ON users (email) WHERE deleted_at IS NULL;

-- Alternative: composite unique including deleted_at
ALTER TABLE users ADD CONSTRAINT uk_users_email_alive UNIQUE (email, deleted_at);
```

### Adapter Soft Delete

```kotlin
override fun deleteById(id: UserId) {
    val entity = jpaRepository.findById(id.value)
        .orElseThrow { EntityNotFoundException("User not found: ${id.value}") }
    entity.softDelete()  // @DynamicUpdate ensures only deleted_at is updated
}
```

---

## 9. Spring Data Auditing

### Configuration

```kotlin
@Configuration
@EnableJpaAuditing
class JpaAuditingConfig {
    @Bean
    fun auditorProvider(): AuditorAware<String> = AuditorAware {
        Optional.ofNullable(SecurityContextHolder.getContext().authentication)
            .map { it.name }.or { Optional.of("SYSTEM") }
    }
}
```

### Base Audit Entity (Full Version)

```kotlin
@MappedSuperclass
@EntityListeners(AuditingEntityListener::class)
abstract class BaseAuditEntity(
    @CreatedDate @Column(nullable = false, updatable = false) var createdAt: Instant = Instant.MIN,
    @LastModifiedDate @Column(nullable = false) var updatedAt: Instant = Instant.MIN,
    @CreatedBy @Column(nullable = false, updatable = false, length = 100) var createdBy: String = "",
    @LastModifiedBy @Column(nullable = false, length = 100) var updatedBy: String = ""
)
```

### Usage

```kotlin
@Entity @Table(name = "invoices") @DynamicUpdate
class InvoiceJpaEntity(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) val id: Long = 0L,
    @Column(nullable = false) val invoiceNumber: String,
    @Enumerated(EnumType.STRING) var status: InvoiceStatus
) : BaseAuditEntity()  // inherits createdAt, updatedAt, createdBy, updatedBy
```

### Field Summary

| Annotation | Field | Behavior |
|-----------|-------|----------|
| `@CreatedDate` | `createdAt` | Set once on INSERT, never updated |
| `@LastModifiedDate` | `updatedAt` | Updated on every UPDATE |
| `@CreatedBy` | `createdBy` | Set once on INSERT via `AuditorAware` |
| `@LastModifiedBy` | `updatedBy` | Updated on every UPDATE via `AuditorAware` |

In unit tests (Tier 1), audit fields are irrelevant since domain models do not carry them.
In integration tests (Tier 2), verify via `jdbcTemplate.queryForMap()` assertions on
`created_at`, `created_by`, `updated_at`, `updated_by` columns.

---

*Reference for agents S-5 (Convention Verifier) and B-5 (Implementation Guide). Source: JPA/Data Access/Gradle Build Patterns.*
