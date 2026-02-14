# Property-Based Testing Reference

> Code examples and configurations for property-based testing. Concepts assumed known.

## Kotlin (jqwik)

### Gradle Setup
```kotlin
testImplementation("net.jqwik:jqwik:1.9.3")
testImplementation("net.jqwik:jqwik-kotlin:1.9.3")
```

### Basic Property
```kotlin
@Property
fun `order total is always non-negative`(
    @ForAll @IntRange(min = 1, max = 100) quantity: Int,
    @ForAll @BigRange(min = "0.01", max = "10000.00") price: BigDecimal
) {
    val item = OrderItem(quantity = quantity, unitPrice = price)
    assertThat(item.totalPrice()).isGreaterThanOrEqualTo(BigDecimal.ZERO)
}
```

### Custom Arbitrary
```kotlin
@Provide
fun orders(): Arbitrary<Order> = Arbitraries.of(OrderStatus.entries)
    .flatMap { status ->
        Arbitraries.integers().between(1, 10).map { itemCount ->
            OrderFixture.create(status = status, itemCount = itemCount)
        }
    }

@Property
fun `cancelled orders cannot be shipped`(@ForAll("orders") order: Order) {
    if (order.status == OrderStatus.CANCELLED) {
        assertThrows<IllegalStateException> { order.ship() }
    }
}
```

## Kotlin (Kotest Property Testing)

```kotlin
class MoneyPropertyTest : FunSpec({
    test("Money addition is commutative") {
        checkAll(Arb.positiveLong(), Arb.positiveLong()) { a, b ->
            Money(a) + Money(b) shouldBe Money(b) + Money(a)
        }
    }
})
```

## TypeScript (fast-check)

```bash
npm install --save-dev fast-check
```

```typescript
import fc from 'fast-check';

fc.assert(
  fc.property(
    fc.record({
      amount: fc.nat({ max: 1_000_000 }),
      currency: fc.constantFrom('USD', 'EUR', 'KRW'),
    }).map(({ amount, currency }) => new Money(amount, currency)),
    (money) => {
      expect(Money.fromJSON(JSON.parse(JSON.stringify(money)))).toEqual(money);
    }
  )
);
```
