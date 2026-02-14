# Integration Testing Techniques Reference

> Code examples and configurations for integration testing. Concepts assumed known.

## Database Testing (Testcontainers)

### Kotlin/Spring
```kotlin
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = Replace.NONE)
class OrderRepositoryTest {
    companion object {
        @Container
        val postgres = PostgreSQLContainer("postgres:15-alpine")
            .withDatabaseName("testdb")

        @JvmStatic
        @DynamicPropertySource
        fun configureProperties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url", postgres::getJdbcUrl)
            registry.add("spring.datasource.username", postgres::getUsername)
            registry.add("spring.datasource.password", postgres::getPassword)
        }
    }

    @Autowired
    lateinit var sut: OrderRepository

    @Test
    fun `should find orders by status`() {
        val order = OrderFixture.create(status = OrderStatus.CONFIRMED)
        entityManager.persist(order)
        entityManager.flush()

        val result = sut.findByStatus(OrderStatus.CONFIRMED)

        expectThat(result).hasSize(1)
        expectThat(result.first().status).isEqualTo(OrderStatus.CONFIRMED)
    }
}
```

## API Testing (MockMvc)

### Kotlin/Spring
```kotlin
@WebMvcTest(OrderController::class)
class OrderControllerTest {
    @Autowired lateinit var mockMvc: MockMvc
    @MockkBean lateinit var orderUseCase: OrderUseCase

    @Test
    fun `POST cancel should return 200 with cancelled order`() {
        every { orderUseCase.cancel(1L, any()) } returns CancelResult.success()

        mockMvc.post("/api/orders/1/cancel") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"reason": "USER_REQUEST"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.status") { value("CANCELLED") }
        }
    }
}
```

## Event-Driven Testing (Embedded Kafka)

### Spring
```kotlin
@SpringBootTest
@EmbeddedKafka(topics = ["order-events"], partitions = 1)
class OrderEventHandlerTest {
    @Autowired lateinit var kafkaTemplate: KafkaTemplate<String, String>
    @Autowired lateinit var orderEventHandler: OrderEventHandler

    @Test
    fun `should process order cancelled event`() {
        val event = """{"orderId": 1, "type": "ORDER_CANCELLED"}"""
        kafkaTemplate.send("order-events", event).get()

        await().atMost(5, SECONDS).untilAsserted {
            verify(exactly = 1) { orderService.handleCancellation(1L) }
        }
    }
}
```
