# Boundary Context & ACL Design Reference

> Static reference for B-1 (Context Classifier) and B-2 (ACL Designer).
> Covers DDD context mapping patterns, external system maps, ACL module layout, tier-specific code examples, Feign Client design, and Stub patterns.

---

## 1. DDD Context Mapping Patterns

### Pattern Definitions and Criteria

| Pattern | Definition | Criteria | Example |
|---------|-----------|----------|---------|
| **Partnership** | Two teams succeed/fail together toward a shared goal. Bidirectional coordination and joint releases | Same team or closely collaborating relationship. Shared release cycles | Order-payment module (owned by same team) |
| **Shared Kernel** | Explicit shared model exists. Changes require bilateral agreement | Common domain model shared at source code level. High cost of change | Shared Value Object library |
| **Customer/Supplier** | Upstream (supplier) reflects downstream (customer) requirements | Same company, upstream team is cooperative with downstream needs | File management API provided by infrastructure team |
| **Conformist** | Downstream conforms to the upstream model. Used as-is without transformation | Upstream cannot be changed but model is acceptably compatible | AWS S3 SDK model used as-is |
| **ACL (Anti-Corruption Layer)** | Translator prevents the external model from corrupting the internal domain | Upstream model is semantically incompatible with the domain model | PG payment API integration |
| **OHS + PL (Open Host Service + Published Language)** | Service provided via standardized protocol and published model | When providing a consistent API to multiple consumers | Public REST API with OpenAPI spec |
| **Separate Ways** | Abandon integration and implement independently | When integration cost significantly exceeds independent implementation cost | Legacy system replacement implementation |

### Classification Decision Tree

```
1. Owned by the same team?
   ├─ YES → Is there a shared model?
   │        ├─ YES → Shared Kernel
   │        └─ NO  → Partnership
   └─ NO  → Same company?
            ├─ YES → Can upstream reflect requirements?
            │        ├─ YES → Customer/Supplier
            │        └─ NO  → Is the model acceptable?
            │                 ├─ YES → Conformist
            │                 └─ NO  → ACL
            └─ NO  → External vendor/API
                     ├─ Model acceptable?    → Conformist
                     ├─ Model incompatible?  → ACL
                     └─ Integration cost excessive? → Separate Ways
```

---

## 2. External System Map

| Category | Module | Relationship | Gap | Rationale |
|----------|--------|-------------|-----|-----------|
| Payment/Finance | TossPayments | ACL | 8 | PG API model completely different from internal payment domain |
| Payment/Finance | NHN KCP | ACL | 8 | When swapping PG, only ACL needs replacement; domain unaffected |
| Payment/Finance | HomeTax (Tax Invoice) | ACL | 9 | National Tax Service e-tax invoice schema, extremely different |
| Payment/Finance | Settlement system | Customer/Supplier | 5 | Accounting standard differences, settlement team is cooperative |
| Infrastructure | File management service | Customer/Supplier | 2 | Simple CRUD, metadata-level differences |
| Infrastructure | Spreadsheet engine | ACL | 6 | Concept conversion between cell/sheet model and domain model |
| Infrastructure | Notification gateway | ACL | 4 | Notification template-to-domain event mapping |
| Notification | Email (SMTP/SES) | ACL | 4 | MIME standard to domain notification model conversion |
| Notification | SMS gateway | ACL | 3 | Carrier specification code mapping |
| Notification | Kakao Notification | ACL | 5 | Business message API, template code system |
| Notification | Slack webhook | Conformist | 2 | Block Kit model is generic, usable as-is |
| AWS | S3 | Conformist | 2 | SDK model is generic |
| AWS | SQS | ACL | 4 | Serialization, visibility timeout, and other infrastructure isolation |
| AWS | SNS | ACL | 4 | Topic/subscription model conversion |
| AWS | CloudWatch | Conformist | 3 | Metric/log standard, SDK usable as-is |
| External | Public API | ACL | 7 | Public data standard, different from internal domain |
| External | External ERP | ACL | 8 | ERP code system, voucher/account model incompatibility |
| External | OAuth provider | Conformist | 3 | OAuth2 standard, token/profile acceptable |
| Internal | Member module | Shared Kernel | 1 | Same monolith, shared model |
| Internal | Order module | Partnership | 2 | Same team, order-payment integration |
| Internal | Product module | Customer/Supplier | 3 | Product team API, some transformation needed |
| Internal | Inventory module | Customer/Supplier | 3 | Inventory deduction/restoration API |

---

## 3. Semantic Gap to ACL Tier Mapping

| Semantic Gap | ACL Tier | Translator Complexity | Component Structure |
|-------------|----------|----------------------|---------------------|
| 0-3 | Tier 1 (Simple Mapper) | Field name/type conversion level. Direct mapping in Adapter | Adapter + Client + DTO |
| 4-6 | Tier 2 (Translator) | Concept-level transformation logic. Separate Translator class required | Adapter + Client + Translator + DTO |
| 7-10 | Tier 3 (Full Translator + ErrorMapper) | Full model transformation + error classification. Translator + ErrorMapper mandatory | Adapter + Client + Translator + ErrorMapper + DTO |

---

## 4. ACL Module Layout

### Standard Directory Structure

```
infrastructure/acl/{external-system}/
├── adapter/
│   └── {System}Adapter.kt          -- implements domain Port interface
├── client/
│   └── {System}FeignClient.kt      -- @FeignClient interface
├── translator/
│   └── {System}Translator.kt       -- external DTO <-> domain model
│   └── {System}ErrorMapper.kt      -- (Tier 3 only) error code classification
├── dto/
│   ├── {System}Request.kt          -- external API request DTO
│   └── {System}Response.kt         -- external API response DTO
├── config/
│   └── {System}FeignConfig.kt      -- timeout, interceptor, error decoder
└── testFixtures/
    ├── stub/
    │   └── Stub{System}Port.kt     -- test double implementing Port
    └── configuration/
        └── Stub{System}PortConfiguration.kt  -- @Configuration @Profile("test")
```

---

## 5. ACL Tier Code Examples

### Tier 1: Simple Mapper (FileManagementAdapter)

```kotlin
@Component
class FileManagementAdapter(
    private val fileClient: FileManagementFeignClient,
) : FilePort {

    override fun upload(command: FileUploadCommand): FileResult {
        val request = FileUploadRequest(
            fileName = command.fileName,
            contentType = command.contentType,
            data = command.data,
        )
        val response = fileClient.upload(request)
        return FileResult(
            fileId = response.fileId,
            url = response.downloadUrl,
            size = response.fileSize,
        )
    }

    override fun download(fileId: String): ByteArray {
        return fileClient.download(fileId)
    }

    override fun delete(fileId: String) {
        fileClient.delete(fileId)
    }
}
```

### Tier 2: Translator (SpreadsheetAdapter + SpreadsheetTranslator)

```kotlin
@Component
class SpreadsheetAdapter(
    private val spreadsheetClient: SpreadsheetFeignClient,
    private val translator: SpreadsheetTranslator,
) : SpreadsheetPort {

    override fun createReport(command: ReportCreateCommand): ReportResult {
        val sheetRequest = translator.toSheetRequest(command)
        val sheetResponse = spreadsheetClient.createWorkbook(sheetRequest)
        return translator.toReportResult(sheetResponse)
    }

    override fun updateCells(command: CellUpdateCommand): CellUpdateResult {
        val cellRequest = translator.toCellUpdateRequest(command)
        val cellResponse = spreadsheetClient.updateCells(cellRequest)
        return translator.toCellUpdateResult(cellResponse)
    }
}
```

```kotlin
@Component
class SpreadsheetTranslator {

    fun toSheetRequest(command: ReportCreateCommand): CreateWorkbookRequest {
        return CreateWorkbookRequest(
            title = command.reportTitle,
            sheets = command.sections.map { section ->
                SheetDefinition(
                    name = section.sectionName,
                    columns = section.columns.map { col ->
                        ColumnDefinition(
                            header = col.label,
                            type = mapColumnType(col.dataType),
                            width = col.preferredWidth,
                        )
                    },
                    rows = section.rows.map { row ->
                        row.cells.map { cell ->
                            CellValue(
                                value = cell.value,
                                format = mapCellFormat(cell.format),
                            )
                        }
                    },
                )
            },
        )
    }

    fun toReportResult(response: CreateWorkbookResponse): ReportResult {
        return ReportResult(
            reportId = response.workbookId,
            downloadUrl = response.exportUrl,
            sheetCount = response.sheets.size,
            createdAt = response.createdAt,
        )
    }

    // toCellUpdateRequest, toCellUpdateResult -- similar pattern omitted for brevity

    private fun mapColumnType(dataType: DataType): String = when (dataType) {
        DataType.TEXT -> "STRING"; DataType.NUMBER -> "NUMBER"
        DataType.CURRENCY -> "CURRENCY"; DataType.DATE -> "DATE"
        DataType.PERCENTAGE -> "PERCENT"
    }
}
```

### Tier 3: Full Translator (PgAdapter + PgTranslator + PgErrorMapper)

```kotlin
@Component
class PgAdapter(
    private val pgClient: PgFeignClient,
    private val translator: PgTranslator,
    private val errorMapper: PgErrorMapper,
) : PaymentPort {

    override fun approve(command: PaymentApproveCommand): PaymentResult {
        val request = translator.toApproveRequest(command)
        return try {
            val response = pgClient.approve(request)
            translator.toPaymentResult(response)
        } catch (e: FeignException) {
            throw errorMapper.mapError(e)
        }
    }

    override fun cancel(command: PaymentCancelCommand): PaymentCancelResult {
        val request = translator.toCancelRequest(command)
        return try {
            val response = pgClient.cancel(request)
            translator.toCancelResult(response)
        } catch (e: FeignException) {
            throw errorMapper.mapError(e)
        }
    }
}
```

```kotlin
@Component
class PgTranslator {

    fun toApproveRequest(command: PaymentApproveCommand): PgApproveRequest {
        return PgApproveRequest(
            orderId = command.orderId.value,
            amount = command.amount.value.toLong(),
            paymentKey = command.paymentKey,
            method = mapPaymentMethod(command.method),
        )
    }

    fun toPaymentResult(response: PgApproveResponse): PaymentResult {
        return PaymentResult(
            paymentId = PaymentId(response.transactionId),
            status = mapPaymentStatus(response.status),
            approvedAt = response.approvedAt,
            receiptUrl = response.receiptUrl,
            cardInfo = response.card?.let { card ->
                CardInfo(
                    issuer = mapCardIssuer(card.issuerCode),
                    number = card.maskedNumber,
                    installmentMonths = card.installmentPlanMonths,
                )
            },
        )
    }

    fun toCancelRequest(command: PaymentCancelCommand): PgCancelRequest {
        return PgCancelRequest(
            transactionId = command.paymentId.value,
            cancelAmount = command.cancelAmount?.value?.toLong(),
            cancelReason = command.reason,
        )
    }

    fun toCancelResult(response: PgCancelResponse): PaymentCancelResult {
        return PaymentCancelResult(
            cancelId = response.cancelId,
            cancelledAmount = Money(response.cancelAmount.toBigDecimal()),
            cancelledAt = response.cancelledAt,
        )
    }

    private fun mapPaymentMethod(method: PaymentMethod): String = when (method) {
        PaymentMethod.CARD -> "CARD"
        PaymentMethod.VIRTUAL_ACCOUNT -> "VIRTUAL_ACCOUNT"
        PaymentMethod.BANK_TRANSFER -> "TRANSFER"
        PaymentMethod.MOBILE -> "MOBILE_PHONE"
    }

    private fun mapPaymentStatus(status: String): PaymentStatus = when (status) {
        "DONE" -> PaymentStatus.APPROVED
        "CANCELED" -> PaymentStatus.CANCELLED
        "PARTIAL_CANCELED" -> PaymentStatus.PARTIALLY_CANCELLED
        "WAITING_FOR_DEPOSIT" -> PaymentStatus.PENDING
        "EXPIRED" -> PaymentStatus.EXPIRED
        else -> PaymentStatus.UNKNOWN
    }

    private fun mapCardIssuer(issuerCode: String): String = when (issuerCode) {
        "11" -> "KB Kookmin"
        "21" -> "Hana"
        "31" -> "BC"
        "41" -> "Shinhan"
        "51" -> "Samsung"
        "61" -> "Hyundai"
        "71" -> "Lotte"
        else -> "Other($issuerCode)"
    }
}
```

```kotlin
@Component
class PgErrorMapper {

    fun mapError(e: FeignException): PaymentException {
        val errorBody = parseErrorBody(e)
        val errorCode = errorBody?.code ?: "UNKNOWN"

        return when {
            isRetryable(e.status(), errorCode) -> PaymentRetryableException(
                code = errorCode,
                message = errorBody?.message ?: "PG temporary error",
                cause = e,
            )
            isCardError(errorCode) -> PaymentCardDeclinedException(
                code = errorCode,
                message = mapCardErrorMessage(errorCode),
                cause = e,
            )
            isInvalidRequest(errorCode) -> PaymentInvalidRequestException(
                code = errorCode,
                message = errorBody?.message ?: "Invalid payment request",
                cause = e,
            )
            else -> PaymentUnknownException(
                code = errorCode,
                message = errorBody?.message ?: "Unknown payment error",
                cause = e,
            )
        }
    }

    private fun isRetryable(httpStatus: Int, errorCode: String): Boolean {
        return httpStatus in listOf(408, 429, 500, 502, 503, 504) ||
            errorCode in listOf("PROVIDER_ERROR", "TIMEOUT", "RATE_LIMIT")
    }

    private fun isCardError(errorCode: String): Boolean {
        return errorCode.startsWith("CARD_") ||
            errorCode in listOf("INSUFFICIENT_BALANCE", "EXCEED_LIMIT", "RESTRICTED_CARD")
    }

    private fun isInvalidRequest(errorCode: String): Boolean {
        return errorCode.startsWith("INVALID_") ||
            errorCode in listOf("ALREADY_PROCESSED", "EXPIRED_KEY")
    }

    private fun mapCardErrorMessage(errorCode: String): String = when (errorCode) {
        "CARD_DECLINED" -> "Card authorization was declined"
        "INSUFFICIENT_BALANCE" -> "Insufficient balance"
        "EXCEED_LIMIT" -> "Payment limit exceeded"
        "RESTRICTED_CARD" -> "Card is restricted from use"
        else -> "Card payment error occurred ($errorCode)"
    }

    private fun parseErrorBody(e: FeignException): PgErrorResponse? {
        return try {
            e.contentUTF8()?.let { body ->
                objectMapper.readValue(body, PgErrorResponse::class.java)
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private val objectMapper = ObjectMapper().apply {
            registerModule(KotlinModule.Builder().build())
        }
    }
}
```

---

## 6. Feign Client Design

```kotlin
@FeignClient(
    name = "pg-client",
    url = "\${external.pg.base-url}",
    configuration = [PgFeignConfig::class],
)
interface PgFeignClient {

    @PostMapping("/v1/payments/confirm")
    fun approve(@RequestBody request: PgApproveRequest): PgApproveResponse

    @PostMapping("/v1/payments/{transactionId}/cancel")
    fun cancel(
        @PathVariable transactionId: String,
        @RequestBody request: PgCancelRequest,
    ): PgCancelResponse

    @GetMapping("/v1/payments/{transactionId}")
    fun getPayment(@PathVariable transactionId: String): PgPaymentDetailResponse
}
```

```kotlin
@Configuration
class PgFeignConfig {

    @Bean
    fun pgRequestInterceptor(
        @Value("\${external.pg.secret-key}") secretKey: String,
    ): RequestInterceptor {
        val encoded = Base64.getEncoder().encodeToString("$secretKey:".toByteArray())
        return RequestInterceptor { template ->
            template.header("Authorization", "Basic $encoded")
            template.header("Content-Type", "application/json")
        }
    }

    @Bean
    fun pgErrorDecoder(): ErrorDecoder {
        return ErrorDecoder { methodKey, response ->
            FeignException.errorStatus(methodKey, response)
        }
    }

    @Bean
    fun pgOptions(): Request.Options {
        return Request.Options(
            /* connectTimeout = */ 5, TimeUnit.SECONDS,
            /* readTimeout = */ 30, TimeUnit.SECONDS,
            /* followRedirects = */ false,
        )
    }
}
```

---

## 7. Stub Design Patterns

### StubPgPort

```kotlin
class StubPgPort : PaymentPort {

    var shouldFailApprove: Boolean = false
    var shouldFailCancel: Boolean = false

    private val _approveHistory = mutableListOf<PaymentApproveCommand>()
    val approveHistory: List<PaymentApproveCommand> get() = _approveHistory.toList()

    private val _cancelHistory = mutableListOf<PaymentCancelCommand>()
    val cancelHistory: List<PaymentCancelCommand> get() = _cancelHistory.toList()

    override fun approve(command: PaymentApproveCommand): PaymentResult {
        _approveHistory.add(command)
        if (shouldFailApprove) {
            throw PaymentRetryableException(
                code = "STUB_FAIL",
                message = "Stub: payment approval failure simulation",
            )
        }
        return PaymentResult(
            paymentId = PaymentId("stub-txn-${command.orderId.value}"),
            status = PaymentStatus.APPROVED,
            approvedAt = LocalDateTime.now(),
            receiptUrl = "https://stub.example.com/receipt",
            cardInfo = CardInfo(
                issuer = "KB Kookmin",
                number = "****-****-****-1234",
                installmentMonths = 0,
            ),
        )
    }

    override fun cancel(command: PaymentCancelCommand): PaymentCancelResult {
        _cancelHistory.add(command)
        if (shouldFailCancel) {
            throw PaymentRetryableException(
                code = "STUB_FAIL",
                message = "Stub: payment cancellation failure simulation",
            )
        }
        return PaymentCancelResult(
            cancelId = "stub-cancel-${command.paymentId.value}",
            cancelledAmount = command.cancelAmount ?: Money(BigDecimal.ZERO),
            cancelledAt = LocalDateTime.now(),
        )
    }

    fun reset() {
        shouldFailApprove = false
        shouldFailCancel = false
        _approveHistory.clear()
        _cancelHistory.clear()
    }
}
```

---

## 8. Stub Configuration

```kotlin
@Configuration
@Profile("test")
class StubPgPortConfiguration {

    @Bean
    @Primary
    fun paymentPort(): PaymentPort {
        return StubPgPort()
    }
}
```

Key rules:
- `@Profile("test")` ensures stub is only active in test context
- `@Primary` overrides the real `PgAdapter` bean
- One configuration class per stub
- Bean method name should match the Port interface concept (e.g., `paymentPort`)

---

## 9. Wiring (build.gradle.kts)

### ACL Module build.gradle.kts

```kotlin
plugins {
    id("java-test-fixtures")
}

dependencies {
    // Domain module (Port interfaces)
    implementation(project(":domain:payment"))

    // Feign client
    implementation("org.springframework.cloud:spring-cloud-starter-openfeign")

    // Jackson for error parsing
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")

    // Test fixtures dependencies
    testFixturesImplementation(project(":domain:payment"))
}
```

### Consumer Module build.gradle.kts

```kotlin
dependencies {
    // Domain Port interface (compile-time)
    implementation(project(":domain:payment"))

    // ACL adapter (runtime only -- no compile-time dependency on ACL internals)
    runtimeOnly(project(":infrastructure:acl:pg"))

    // Test stubs from ACL testFixtures
    testImplementation(testFixtures(project(":infrastructure:acl:pg")))
}
```

Key principles:
- Consumer depends on domain Port interface at compile time
- ACL module is `runtimeOnly` -- consumer never imports ACL classes directly
- `testFixtures()` provides Stub for testing without real external calls
- This wiring ensures ACL can be swapped without consumer code changes

---

*Last updated: 2025-05. Based on DDD context mapping theory (Eric Evans, Vaughn Vernon) and production integration patterns.*
