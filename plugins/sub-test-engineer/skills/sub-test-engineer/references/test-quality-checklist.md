# Test Quality Checklist

> Checklist items and rules for test quality validation. Concepts assumed known.

## Naming

| Rule | Good | Bad |
|------|------|-----|
| Describes behavior, not method | `should reject order when stock insufficient` | `testCancelOrder` |
| Uses domain language | `cancelled order cannot be shipped` | `test_status_change_3` |
| Specifies condition | `should return empty when no orders exist` | `testFindOrders` |

## Assertion Quality

| Severity | Rule | Bad Example | Good Example |
|----------|------|-------------|-------------|
| ERROR | No empty test bodies | `@Test fun test() {}` | Must have at least one assertion |
| ERROR | No tautological assertions | `assertTrue(true)` | Assert actual behavior |
| WARNING | Use specific assertions | `assertTrue(result == expected)` | `assertEquals(expected, result)` |
| WARNING | Assert on domain properties | `assertNotNull(result)` | `assertEquals(OrderStatus.CANCELLED, result.status)` |
| WARNING | Verify side effects | (no verify call) | `verify { eventPublisher.publish(any()) }` |

## Test Isolation

| Severity | Rule | Detection |
|----------|------|-----------|
| ERROR | No shared mutable state | `companion object` or `static` mutable field |
| ERROR | Each test sets up own data | Missing `@BeforeEach` with state that leaks |
| WARNING | No test ordering dependency | `@TestMethodOrder` without `@TestInstance(PER_CLASS)` justification |
| WARNING | No global side effects | File I/O, environment variables, system properties |

## Determinism

| Severity | Pattern to Avoid | Alternative |
|----------|-----------------|-------------|
| ERROR | `Thread.sleep(N)` | `Awaitility.await().until { condition }` |
| ERROR | `System.currentTimeMillis()` | Inject `Clock`, use `Clock.fixed()` in tests |
| ERROR | `Random()` without seed | `Random(42)` or deterministic fixture |
| ERROR | `LocalDateTime.now()` | `LocalDateTime.now(fixedClock)` |
| WARNING | `UUID.randomUUID()` in assertions | Capture and assert, or use deterministic UUID factory |

## Structure

| Severity | Rule |
|----------|------|
| INFO | Clear AAA/GWT separation |
| INFO | Single act per test |
| WARNING | No logic in tests (no if/else, loops, try-catch) |
| WARNING | Test is readable standalone |

## Coverage Completeness

| Severity | Rule |
|----------|------|
| WARNING | All enum variants covered in parameterized tests |
| WARNING | All sealed class subtypes tested |
| WARNING | Happy path + at least one error path per method |
| WARNING | Null input tested for nullable parameters |
| INFO | Boundary values tested for constrained parameters |

## Mock Usage

| Severity | Rule |
|----------|------|
| WARNING | Mock interfaces, not concrete classes |
| WARNING | Don't mock value objects or data classes |
| ERROR | Don't mock the system-under-test |
| WARNING | Prefer `relaxed = true` for non-essential mocks |
| INFO | Use `verify` for side effects, `returns` for queries |
