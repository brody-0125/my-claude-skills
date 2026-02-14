# JOOQ Conventions

> Code convention guide for using JOOQ.
> Loaded when the profile's query-lib includes jooq.
> Applies to both Kotlin and Java.

---

## Code Generation Rules

### Generated Code Location

- Default location: `build/generated-sources/jooq/`
- **Manual modification prohibited** -- automatically regenerated during build
- Include in `.gitignore` to exclude from version control (common practice)

### Code Generation Configuration

```kotlin
// build.gradle.kts (nu.studer.jooq plugin)
jooq {
    configurations {
        create("main") {
            jooqConfiguration.apply {
                jdbc.apply {
                    driver = "com.mysql.cj.jdbc.Driver"
                    url = "jdbc:mysql://localhost:3306/mydb"
                }
                generator.apply {
                    database.apply {
                        inputSchema = "mydb"
                    }
                    target.apply {
                        packageName = "com.example.generated.jooq"
                        directory = "build/generated-sources/jooq"
                    }
                }
            }
        }
    }
}
```

---

## Usage Rules per Architecture

### Hexagonal Architecture

```
DSLContext is used only in Infrastructure Adapters.
Direct usage in Application/Core layers is prohibited.

core/domain-model → Pure domain models (no JOOQ dependency)
core (ports)      → Repository interfaces (JOOQ-independent)
application       → Use Case Service (JOOQ-independent)
infrastructure    → JOOQ Adapter (uses DSLContext)
```

```kotlin
// ✅ Using DSLContext in Infrastructure Adapter
@Repository
class OrderJooqAdapter(
    private val dsl: DSLContext,
) : OrderReader {

    override fun getById(id: Long): Order {
        return dsl.selectFrom(ORDERS)
            .where(ORDERS.ID.eq(id))
            .fetchOneInto(OrderRecord::class.java)
            ?.toModel()
            ?: throw EntityNotFoundException("Order not found: $id")
    }
}
```

```java
// ✅ Java: Infrastructure Adapter
@Repository
@RequiredArgsConstructor
public class OrderJooqAdapter implements OrderReader {
    private final DSLContext dsl;

    @Override
    public Order getById(Long id) {
        return Optional.ofNullable(
                dsl.selectFrom(ORDERS)
                    .where(ORDERS.ID.eq(id))
                    .fetchOneInto(OrderRecord.class))
            .map(OrderMapper::toModel)
            .orElseThrow(() -> new EntityNotFoundException("Order not found: " + id));
    }
}
```

---

## Type-safe Query Writing

### Required Rules

1. **Use generated Table/Field references** -- hardcoded strings prohibited
2. **Map results with `fetchInto()` / `fetchOneInto()`** -- minimize manual mapping
3. **Null-safe handling in conditions** -- use `DSL.noCondition()`

```kotlin
// ✅ Type-safe query
dsl.select(ORDERS.ID, ORDERS.STATUS, ORDERS.AMOUNT)
    .from(ORDERS)
    .where(ORDERS.WORKSPACE_ID.eq(workspaceId))
    .and(ORDERS.STATUS.eq(OrderStatus.ACTIVE.name))
    .orderBy(ORDERS.CREATED_AT.desc())
    .limit(pageSize)
    .offset(offset)
    .fetchInto(OrderSummary::class.java)

// ❌ Hardcoded strings
dsl.resultQuery("SELECT * FROM orders WHERE workspace_id = ?", workspaceId)
```

### Dynamic Conditions

```kotlin
fun findOrders(workspaceId: Long, status: String?, search: String?): List<OrderSummary> {
    var condition = ORDERS.WORKSPACE_ID.eq(workspaceId)
    status?.let { condition = condition.and(ORDERS.STATUS.eq(it)) }
    search?.let { condition = condition.and(ORDERS.NAME.containsIgnoreCase(it)) }

    return dsl.selectFrom(ORDERS)
        .where(condition)
        .fetchInto(OrderSummary::class.java)
}
```

```java
// Java dynamic conditions
public List<OrderSummary> findOrders(Long workspaceId, String status, String search) {
    var condition = ORDERS.WORKSPACE_ID.eq(workspaceId);
    if (status != null) condition = condition.and(ORDERS.STATUS.eq(status));
    if (search != null) condition = condition.and(ORDERS.NAME.containsIgnoreCase(search));

    return dsl.selectFrom(ORDERS)
        .where(condition)
        .fetchInto(OrderSummary.class);
}
```

---

## Result -> Domain Model Mapping

### Kotlin: Extension Function

```kotlin
fun OrderRecord.toModel(): Order = Order(
    id = this.id,
    status = OrderStatus.valueOf(this.status),
    amount = this.amount,
)
```

### Java: Static Mapper

```java
public final class OrderMapper {
    private OrderMapper() {}

    public static Order toModel(OrderRecord record) {
        return new Order(
            record.getId(),
            OrderStatus.valueOf(record.getStatus()),
            record.getAmount()
        );
    }
}
```

---

## Naming

| Pattern | Description |
|---------|-------------|
| `*JooqAdapter` | JOOQ-based Adapter (infrastructure layer) |
| `*Mapper` | Record → Domain Model mapping class (Java) |
| `*.toModel()` | Record → Domain Model conversion function (Kotlin) |

---

## QueryDSL vs JOOQ Comparison

| Aspect | QueryDSL | JOOQ |
|--------|----------|------|
| Approach | JPA Entity-based | DB schema-based (SQL-first) |
| Code generation | APT (Q-class) | DB metadata (Table/Field) |
| JPA integration | Natural (JPAQueryFactory) | Separate (DSLContext) |
| SQL control | JPA abstraction level | Close to raw SQL |
| Complex queries | JOINs somewhat limited | Supports window functions, CTEs, etc. |
| Suitable cases | JPA-centric projects | Complex reporting/analytics queries |
| Kotlin support | Requires kapt (slow builds) | Native support |

### Guide for Mixed Usage (query-lib = querydsl+jooq)

- **CRUD / simple queries**: QueryDSL (leveraging JPA Entity)
- **Complex queries / reporting**: JOOQ (SQL-first)
- **When both are used for the same table**: Distinguish by naming (`*CustomImpl` vs `*JooqAdapter`)
