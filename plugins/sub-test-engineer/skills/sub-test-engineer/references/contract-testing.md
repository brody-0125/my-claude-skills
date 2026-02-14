# Contract Testing Reference

> Code examples and configurations for contract testing. Concepts assumed known.

## Pact (Consumer-Driven)

### Consumer Side (Kotlin)
```kotlin
@ExtendWith(PactConsumerTestExt::class)
class PaymentClientPactTest {
    @Pact(consumer = "order-service", provider = "payment-service")
    fun chargeOrderPact(builder: PactDslWithProvider): V4Pact {
        return builder
            .given("payment method exists")
            .uponReceiving("charge order request")
            .method("POST")
            .path("/api/payments/charge")
            .body("""{"orderId": 1, "amount": 10000}""")
            .willRespondWith()
            .status(200)
            .body("""{"transactionId": "tx-123", "status": "SUCCESS"}""")
            .toPact(V4Pact::class.java)
    }

    @Test
    @PactTestFor(pactMethod = "chargeOrderPact")
    fun `should charge order successfully`(mockServer: MockServer) {
        val client = PaymentClient(baseUrl = mockServer.getUrl())
        val result = client.charge(orderId = 1L, amount = 10000)
        assertThat(result.status).isEqualTo("SUCCESS")
    }
}
```

## Spring Cloud Contract (Provider-Driven)

### Contract DSL (Groovy)
```groovy
// src/test/resources/contracts/order/cancel.groovy
Contract.make {
    request {
        method POST()
        url '/api/orders/1/cancel'
        body(reason: 'USER_REQUEST')
        headers { contentType applicationJson() }
    }
    response {
        status 200
        body(id: 1, status: 'CANCELLED')
        headers { contentType applicationJson() }
    }
}
```

## Async Contract Testing (Pact Message)

```kotlin
@PactTestFor(providerType = ProviderType.ASYNCH)
class OrderEventPactTest {
    @Pact(consumer = "notification-service", provider = "order-service")
    fun orderCancelledEvent(builder: MessagePactBuilder): V4Pact {
        return builder
            .expectsToReceive("order cancelled event")
            .withContent("""{"orderId": 1, "reason": "USER_REQUEST", "cancelledAt": "2026-01-01T00:00:00Z"}""")
            .toPact(V4Pact::class.java)
    }
}
```
