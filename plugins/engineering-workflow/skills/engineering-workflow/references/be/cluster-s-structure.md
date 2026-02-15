# BE Structure Cluster Reference

> Code examples and detailed specifications for agents S-1 (Dependency Rule Auditor),
> S-2 (DI Pattern Selector), S-3 (Architecture Style Advisor), and S-4 (Fitness Function Engineer).
> Agent files reference this document for all Kotlin/Gradle code snippets.

## Table of Contents

| Section | Line |
|---------|------|
| 1. 5-Layer Model Code Examples | ~27 |
| 2. Violation Severity Matrix | ~133 |
| 3. DI Pattern Catalog | ~174 |
| 4. Stub Double Pattern | ~238 |
| 5. Pattern Selection Decision Tree | ~291 |
| 6. Module Naming Convention | ~310 |
| 7. Gradle Multi-Module Structure | ~334 |
| 8. java-test-fixtures Plugin Setup | ~371 |
| 9. New Module Addition Decision Tree | ~399 |
| 10. ArchUnit Rules | ~425 |
| 11. Konsist Rules | ~475 |
| 12. Test Name Byte Limit | ~536 |
| 13. Gradle Dependency Scope | ~564 |
| 14. CI/CD Pipeline | ~588 |

---

## 1. 5-Layer Model Code Examples

### ArchUnit onionArchitecture Configuration

```kotlin
@AnalyzeClasses(packages = [".."])
class LayerDependencyArchTest {

    @ArchTest
    val `5-Layer hexagonal architecture` =
        Architectures.onionArchitecture()
            .domainModels("..core.domain..")
            .domainServices("..core.port..", "..core.usecase..")
            .applicationServices("..application..")
            .adapter("persistence", "..persistence..")
            .adapter("external", "..external..")
            .adapter("interfaces", "..interfaces..")
            .withOptionalLayers(true)

    @ArchTest
    val `Core must not depend on Infrastructure` =
        noClasses().that().resideInAPackage("..core..")
            .should().dependOnClassesThat()
            .resideInAnyPackage("..infrastructure..", "..persistence..",
                                "..external..")

    @ArchTest
    val `Domain Model must not use JPA annotations` =
        noClasses().that().resideInAPackage("..core.domain..")
            .should().beAnnotatedWith("jakarta.persistence.Entity")
            .orShould().beAnnotatedWith("jakarta.persistence.Table")
            .orShould().beAnnotatedWith("jakarta.persistence.Column")

    @ArchTest
    val `No direct dependency between Infrastructure Adapters` =
        slices().matching("..infrastructure.(*)..")
            .should().notDependOnEachOther()
}
```

### Layer Direction Rule (text-based)

```
App ──(compile)──→ Application ──→ Core ←──(implements)── Infrastructure
                       ↓                         ↓
                    Library ←──────────────── Library
```

### Layer 0 -- Core Constraints

```
Layer 0 — Core (innermost):
  - Modules: {project}-core, {project}-core/domain-model
  - Contains: Port interfaces, UseCase definitions, Domain Entities,
    Value Objects (Money, Email, BusinessRegistrationNumber)
  - Dependency: ZERO external dependencies EXCEPT {project}-lib/extensions
  - FORBIDDEN: JPA annotations (@Entity, @Table, @Column), framework
    imports (Spring, Feign, Resilience4j), infrastructure classes
```

### Layer 1 -- Application Constraints

```
Layer 1 — Application:
  - Module: {project}-application
  - Contains: UseCase implementations, business logic composition,
    Application Service orchestration
  - Dependency: Core Layer ports ONLY. Never Infrastructure directly.
  - Pattern: ApplicationService injects N Port interfaces via constructor
```

### Layer 2 -- Infrastructure Constraints

```
Layer 2 — Infrastructure (implements Core):
  - Modules: persistence-mysql, persistence-redis, external-*,
    internal-event-*, config-async-executor
  - Contains: Port implementations (Adapters), JPA entities, Feign clients,
    SQS producers/listeners, Resilience4j decorator wrapping
  - Dependency: Core Layer ports (implements them). Never Application.
```

### Layer 3 -- App Constraints

```
Layer 3 — App (outermost):
  - Modules: {project}-api, {project}-admin-api, {project}-batch,
    {project}-consumer
  - Contains: REST endpoints (@RestController), Spring Security,
    batch jobs (@Scheduled), SQS consumer entry points
  - Dependency: Application (compile-time), Infrastructure (runtime ONLY)
  - CRITICAL: Infrastructure modules are runtimeOnly in Gradle
```

### Layer X -- Library Constraints

```
Layer X — Library (cross-cutting):
  - Modules: {project}-lib/* (extensions, tracing-bridge-otel,
    tracing-bridge-brave, json-web-token, circuitbreaker)
  - Rules: Core MAY depend on extensions ONLY. Other lib modules
    are consumed by Infrastructure or App layers.
```

---

## 2. Violation Severity Matrix

| Violation | Severity | Fix |
|-----------|----------|-----|
| domain-model imports persistence-mysql class | CRITICAL | Extract Port in Core, implement in persistence |
| domain-model carries @Entity, @Table, @Column | CRITICAL | Clean domain entity; map in JpaEntity |
| Application imports external-* class directly | CRITICAL | Depend on Port interface in Core only |
| App module has implementation() on infrastructure module | HIGH | Change to runtimeOnly() |
| Core depends on {project}-lib (non-extensions) | HIGH | Move dependency to Infrastructure/App |
| external-* references domain entity directly | MEDIUM | Map via JPA entity / Translator |
| Shared DTO between {project}-api and {project}-admin-api | LOW | Extract to shared contract or duplicate |
| internal-event-model depends on external-event-model | HIGH | Separate models; translate at boundary |
| Infrastructure module A imports Infrastructure module B directly | MEDIUM | Route through Core Port or extract shared interface |

### Gradle Dependency Audit Checklist

- [ ] App modules: Infrastructure dependencies are `runtimeOnly` only?
- [ ] Application module: No direct import of `persistence-*`, `external-*`, `internal-event-*`?
- [ ] Core/domain-model: Only depends on `extensions` from lib?
- [ ] Infrastructure modules: Only implements Core ports, never imports Application?
- [ ] Infrastructure modules: No direct inter-module dependency? (Adapter coupling prevention)
- [ ] testImplementation: `testFixtures(project(...))` paths are correct?

### Violation Report Example

```
┌─ VIOLATION REPORT ────────────────────────────────────
│ Module:    {project}-application
│ Import:    external-pg.adapter.PgFeignClient
│ Direction: Layer 1 → Layer 2 (Application → Infrastructure)
│ Severity:  CRITICAL
│ Fix:       Application must depend on Core PgPort interface only.
│            PgFeignClient is an Infrastructure adapter implementation detail.
│ ArchUnit:  noClasses().that().resideInAPackage("..application..")
│              .should().dependOnClassesThat()
│              .resideInAPackage("..external.pg..")
└────────────────────────────────────────────────────────
```

---

## 3. DI Pattern Catalog

### Kotlin Constructor Injection -- Correct

```kotlin
// CORRECT: Primary constructor injection
@Service
class InvoiceIssuanceUseCase(
    private val invoiceRepository: InvoiceRepository,  // Core Port
    private val pgPort: PgPort,                         // Core Port
    private val taxInvoiceGwPort: TaxInvoiceGwPort,    // Core Port
    private val notificationPort: NotificationPort      // Core Port
) {
    fun issue(command: IssueInvoiceCommand): Invoice { ... }
}
```

### Kotlin Constructor Injection -- Wrong (Field Injection)

```kotlin
// WRONG: Field injection
@Service
class InvoiceIssuanceUseCase {
    @Autowired lateinit var invoiceRepository: InvoiceRepository
}
```

### Kotlin Constructor Injection -- Wrong (Service Locator)

```kotlin
// WRONG: Service Locator -- FORBIDDEN
@Service
class InvoiceIssuanceUseCase(
    private val ctx: ApplicationContext
) {
    fun issue(...) {
        val repo = ctx.getBean(InvoiceRepository::class.java) // FORBIDDEN
    }
}
```

### Composition Root Principle

```
- App module ({project}-api etc.) is Spring DI container's Composition Root
- Infrastructure Adapters register via @Component/@Configuration
- App module loads Infrastructure onto classpath via runtimeOnly
- Spring DI container resolves Port <-> Adapter mapping automatically
```

### Pattern Catalog Table

| Pattern | Project Usage | Selection Criteria |
|---------|---------------|-------------------|
| Constructor Injection | DEFAULT for all UseCases | Always |
| Port/Adapter | All external-* modules | External system integration |
| Decorator | `{project}-lib/circuitbreaker` wrapping | Cross-cutting concern |
| Domain Events | internal-event-publisher/listener | Async between Aggregates |
| Strategy | Multi-PG routing, runtime branching | Same Port, multiple impls |
| Abstract Factory | Runtime variant selection | Complex object creation branching |
| Service Locator | FORBIDDEN | Never |

---

## 4. Stub Double Pattern

### Port Definition (Core)

```kotlin
interface PgPort {
    fun requestPayment(request: PaymentRequest): PaymentResult
    fun cancelPayment(paymentKey: String): CancelResult
}
```

### Stub Implementation (testFixtures)

```kotlin
// src/testFixtures/kotlin/.../stub/StubPgPort.kt
class StubPgPort : PgPort {
    var shouldFail = false  // Test scenario control flag

    override fun requestPayment(request: PaymentRequest): PaymentResult =
        if (shouldFail) PaymentResult.failure("stub-error")
        else PaymentResult.success(paymentKey = "test-key", amount = request.amount)

    override fun cancelPayment(paymentKey: String): CancelResult =
        CancelResult.success()
}
```

### Stub Configuration (testFixtures)

```kotlin
// src/testFixtures/kotlin/.../configuration/StubPgConfiguration.kt
@Configuration
@Profile("test")
class StubPgConfiguration {
    @Bean
    @Primary  // Takes precedence over real Adapter in test context
    fun stubPgPort(): PgPort = StubPgPort()
}
```

### Wiring (App module build.gradle.kts)

```kotlin
dependencies {
    runtimeOnly(project(":{project}-infrastructure:external-pg"))
    testImplementation(testFixtures(
        project(":{project}-infrastructure:external-pg")
    ))
}
```

---

## 5. Pattern Selection Decision Tree

```
Is a new dependency needed?
├─ Is it an external system?
│   ├─ YES → Port/Adapter + Constructor Injection + Stub
│   │   └─ Cross-cutting concern (CB, retry) needed? → Add Decorator
│   └─ NO (internal module) → Constructor Injection only
├─ Are multiple implementations of the same Port needed?
│   ├─ Compile-time decision → @Qualifier or @ConditionalOnProperty
│   └─ Runtime decision → Strategy pattern
├─ Is it async communication between Aggregates?
│   └─ YES → Domain Events (internal-event-publisher)
└─ Is a factory pattern needed?
    └─ YES → Abstract Factory
```

---

## 6. Module Naming Convention

| Layer | Pattern | Examples |
|-------|---------|----------|
| Root | `{project}-{layer}` | {project}-core, {project}-application |
| App | `{project}-{type}` | {project}-api, {project}-admin-api, {project}-batch, {project}-consumer |
| Persistence | `persistence-{store}` | persistence-mysql, persistence-redis |
| External API | `external-{domain-name}` | external-pg, external-bank, external-auth-service, external-digital-sign, external-tax-invoice-gw |
| Notification | `external-{channel-domain}` | external-messenger, external-message-sender, external-email |
| AWS/Cloud | `external-{function-name}` | external-file-management, external-key-management |
| Internal Event | `internal-event/{sub}` | internal-event-model, internal-event-listener, internal-event-publisher |
| External Event | `external-event/{sub}` | external-event-model, external-event-listener, external-event-producer |
| Library | `{function-name}` | extensions, circuitbreaker, json-web-token, tracing-bridge-otel |
| Config | `{project}-config` | Shared YAML config + testFixtures (TestContainers) |

### Critical Naming Rules

- Internal event emitter: **publisher** (Spring ApplicationEvent)
- External event emitter: **producer** (AWS SQS)
- publisher != producer -- NEVER mix these terms
- External module names use domain/function-based naming, NOT vendor company names

---

## 7. Gradle Multi-Module Structure

### App Module build.gradle.kts

```kotlin
// App module build.gradle.kts
dependencies {
    implementation(project(":{project}-application"))
    runtimeOnly(project(":{project}-infrastructure:external-pg"))
    runtimeOnly(project(":{project}-infrastructure:persistence-mysql"))
    testImplementation(testFixtures(project(":{project}-infrastructure:external-pg")))
    testImplementation(testFixtures(project(":{project}-core:domain-model")))
}
```

### Application Module build.gradle.kts

```kotlin
// Application module
dependencies {
    implementation(project(":{project}-core"))
    // NEVER: implementation(project(":{project}-infrastructure:..."))
}
```

### Infrastructure Module build.gradle.kts

```kotlin
// Infrastructure external-* module
dependencies {
    implementation(project(":{project}-core"))
    // NEVER: implementation(project(":{project}-application"))
}
```

---

## 8. java-test-fixtures Plugin Setup

```kotlin
// external-pg/build.gradle.kts
plugins {
    `java-test-fixtures`
}
// → Activates src/testFixtures/kotlin/ directory
// → Other modules can reference via testFixtures(project(...))
```

### Directory Structure

```
external-pg/
├── build.gradle.kts                          # includes java-test-fixtures plugin
├── src/
│   ├── main/kotlin/.../adapter/
│   │   └── PgFeignAdapter.kt                # Real adapter implementation
│   └── testFixtures/kotlin/.../
│       ├── stub/
│       │   └── StubPgPort.kt                # Stub implementation
│       └── configuration/
│           └── StubPgConfiguration.kt        # @Configuration @Profile("test")
```

---

## 9. New Module Addition Decision Tree

```
Is a new integration needed?
├─ External API integration?
│   └─ YES → external-{domain-name} under {project}-infrastructure
│       ├─ Port in {project}-core
│       ├─ Adapter in external-{domain-name}/src/main/
│       ├─ Stub in external-{domain-name}/src/testFixtures/
│       ├─ java-test-fixtures plugin added
│       ├─ runtimeOnly dep in App module
│       └─ → Chain: B-2 (ACL) → R-1~R-3 (resilience) → T-1 (test)
├─ New domain Aggregate?
│   └─ YES → {project}-core/domain-model
│       ├─ Entity + Value Objects in domain.{aggregate} package
│       ├─ Port interface in {project}-core
│       ├─ UseCase in {project}-application
│       └─ testFixture in domain-model/src/testFixtures/
├─ New notification channel?
│   └─ YES → external-{channel-domain}
└─ New batch job?
    └─ YES → Add to {project}-batch or create separate App module
```

---

## 10. ArchUnit Rules

### 5-Layer Hexagonal Architecture

```kotlin
@ArchTest
val `5-Layer hexagonal architecture` =
    Architectures.onionArchitecture()
        .domainModels("..core.domain..")
        .domainServices("..core.port..", "..core.usecase..")
        .applicationServices("..application..")
        .adapter("persistence", "..persistence..")
        .adapter("external", "..external..")
        .adapter("interfaces", "..interfaces..")
        .withOptionalLayers(true)
```

### Core Isolation

```kotlin
@ArchTest
val `Core must not depend on Infrastructure` =
    noClasses().that().resideInAPackage("..core..")
        .should().dependOnClassesThat()
        .resideInAnyPackage("..infrastructure..", "..persistence..",
                            "..external..")
```

### Domain Model JPA Prohibition

```kotlin
@ArchTest
val `Domain Model must not use JPA annotations` =
    noClasses().that().resideInAPackage("..core.domain..")
        .should().beAnnotatedWith("jakarta.persistence.Entity")
        .orShould().beAnnotatedWith("jakarta.persistence.Table")
        .orShould().beAnnotatedWith("jakarta.persistence.Column")
```

### Infrastructure Adapter Isolation

```kotlin
@ArchTest
val `No direct dependency between Infrastructure Adapters` =
    slices().matching("..infrastructure.(*)..")
        .should().notDependOnEachOther()
```

---

## 11. Konsist Rules

### UseCase Location

```kotlin
@Test
fun `All UseCases must reside in the application package`() {
    Konsist.scopeFromProject()
        .classes()
        .withNameEndingWith("UseCase")
        .assertTrue { it.resideInPackage("..application..") }
}
```

### Port Location

```kotlin
@Test
fun `All Port interfaces must reside in the core package`() {
    Konsist.scopeFromProject()
        .interfaces()
        .withNameEndingWith("Port")
        .assertTrue { it.resideInPackage("..core..") }
}
```

### Repository Location

```kotlin
@Test
fun `All Repository interfaces in core, implementations in persistence`() {
    Konsist.scopeFromProject()
        .interfaces()
        .withNameEndingWith("Repository")
        .assertTrue { it.resideInPackage("..core..") }
}
```

### Hexagonal Layer Validation

```kotlin
@Test
fun `Hexagonal Architecture layer dependency validation`() {
    Konsist.scopeFromProject()
        .assertArchitecture {
            val core = Layer("Core", "..core..")
            val application = Layer("Application", "..application..")
            val infrastructure = Layer("Infrastructure",
                "..infrastructure..", "..persistence..", "..external..")
            val interfaces = Layer("Interfaces", "..interfaces..")

            core.dependsOnNothing()
            application.dependsOn(core)
            infrastructure.dependsOn(core)
            interfaces.dependsOn(application, core)
        }
}
```

---

## 12. Test Name Byte Limit

### checkTestNames Gradle Task

```kotlin
// Custom Gradle task
fun validateTestName(className: String, methodName: String) {
    val methodBytes = methodName.toByteArray(Charsets.UTF_8).size
    require(methodBytes <= 120) {
        "Method name ${methodBytes} bytes exceeds limit (max 120): $methodName"
    }
    val fullFileName = "${className}\$${methodName}\$1.class"
    val fileNameBytes = fullFileName.toByteArray(Charsets.UTF_8).size
    require(fileNameBytes <= 200) {
        "File name ${fileNameBytes} bytes exceeds limit (max 200): $fullFileName"
    }
}
```

### Why This Matters

- Korean test names (backtick-quoted) can exceed filesystem path limits
- CI tools (Jenkins, GitHub Actions) may truncate or fail on long file paths
- JVM generates inner class files from test methods: `ClassName$methodName$1.class`
- 120-byte method limit + 200-byte filename limit prevents CI breakage

---

## 13. Gradle Dependency Scope

### checkRuntimeOnlyDeps Task

```kotlin
tasks.register("checkRuntimeOnlyDeps") {
    doLast {
        // Verify that App modules use runtimeOnly for Infrastructure dependencies
        // implementation() declaration on Infrastructure = build failure
    }
}
```

### Scope Rules

| Module Type | Infrastructure Dependency Scope | Violation if |
|-------------|-------------------------------|--------------|
| App (`{project}-api`) | `runtimeOnly` | `implementation` used |
| Application | NONE | Any Infrastructure dependency |
| Infrastructure | NONE (inter-module) | Direct dependency on another Infrastructure module |
| Core | NONE | Any Infrastructure dependency |

---

## 14. CI/CD Pipeline

### ./gradlew check Composition

```
./gradlew check =
  test                 (unit tests)
  + integrationTest    (integration tests)
  + ktlintCheck        (code formatting)
  + checkTestNames     (test name byte limit)
  + detekt             (optional static analysis)
```

### Build-Breaking Rule

ALL fitness functions are build-breaking tests:
- Violation = build failure, NOT a warning
- CI pipeline halts on first fitness function failure
- Developers must fix the violation before merging

### Full CI Command

```bash
./gradlew check
```

This single command runs all fitness functions. Any failure causes the entire build to fail.

---

*Reference for agents S-1 through S-4. Source: v5.0 Micro-Agent Architecture, Structure Cluster.*
