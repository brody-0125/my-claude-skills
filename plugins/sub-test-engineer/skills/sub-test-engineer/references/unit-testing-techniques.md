# Unit Testing Techniques Reference

> Code examples and configurations for unit testing. Concepts assumed known.

## Kotlin (Kotest + MockK + Strikt)

```kotlin
class OrderServiceTest : BehaviorSpec({
    val orderRepository = mockk<OrderRepository>()
    val eventPublisher = mockk<EventPublisher>(relaxed = true)
    val sut = OrderService(orderRepository, eventPublisher)

    Given("an existing order") {
        val order = OrderFixture.create(status = OrderStatus.CONFIRMED)
        every { orderRepository.findById(order.id) } returns order

        When("cancel is requested") {
            val result = sut.cancel(order.id, CancelReason.USER_REQUEST)

            Then("order status changes to CANCELLED") {
                result.status shouldBe OrderStatus.CANCELLED
            }

            Then("cancel event is published") {
                verify(exactly = 1) { eventPublisher.publish(any<OrderCancelledEvent>()) }
            }
        }
    }
})
```

### Strikt Assertions
```kotlin
expectThat(result) {
    get { status }.isEqualTo(OrderStatus.CANCELLED)
    get { cancelledAt }.isNotNull()
    get { reason }.isEqualTo(CancelReason.USER_REQUEST)
}
```

## Java (JUnit 5 + Mockito + AssertJ)

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {
    @Mock OrderRepository orderRepository;
    @Mock EventPublisher eventPublisher;
    @InjectMocks OrderService sut;

    @Nested
    @DisplayName("cancel")
    class Cancel {
        @Test
        @DisplayName("should cancel confirmed order")
        void shouldCancelConfirmedOrder() {
            var order = OrderFixture.confirmed();
            when(orderRepository.findById(order.getId())).thenReturn(Optional.of(order));

            var result = sut.cancel(order.getId(), CancelReason.USER_REQUEST);

            assertThat(result.getStatus()).isEqualTo(OrderStatus.CANCELLED);
            verify(eventPublisher).publish(any(OrderCancelledEvent.class));
        }
    }
}
```
