# Phase 1: Analyze Protocol

> Inspects code-under-test to identify testable units, complexity, and edge cases using the 3-Layer Type Extraction Pipeline.

## 0. Type Extraction Pipeline Overview

```
┌────────────────────────────────────────────────────────────────────┐
│ Layer 1a: ast-grep (결정적 구조 추출)                              │
│   scripts/extract-types.sh <target> [lang] [category]              │
│   → NDJSON: 메서드, 어노테이션, 생성자, 클래스 계층, 검증 어노테이션 │
│   → 속도: ~1초 / 정확도: 85-90% / 토큰: ~200/파일                  │
├────────────────────────────────────────────────────────────────────┤
│ Layer 1b: LLM (시맨틱 해석)                                        │
│   ast-grep JSON을 컨텍스트로 주입하여 시맨틱 분석                    │
│   → 레이어 분류, 복잡도 평가, 크로스파일 추론, 엣지 케이스           │
│   → 정확도: 90-95%                                                  │
├────────────────────────────────────────────────────────────────────┤
│ Layer 2: ClassGraph (바이트코드 보강, 선택적)                       │
│   scripts/extract-type-info.sh <target> (컴파일 후)                 │
│   → 완전한 클래스 계층, 해석된 제네릭, sealed 서브타입               │
│   → 정확도: 95%+                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Pipeline Decision Flow

```
Step 1: Check ast-grep availability
  → Run: scripts/check-ast-grep.sh
  → IF available (exit 0) → proceed to Layer 1a
  → IF unavailable (exit 1) → SKIP Layer 1a, go to Layer 1b (source-file mode)

Step 2: Layer 1a — ast-grep extraction
  → Run: scripts/extract-types.sh <target> [lang] all
  → IF exit 0 AND output non-empty → parse NDJSON, proceed to Layer 1b (with JSON context)
  → IF exit non-zero OR empty output → log warning, proceed to Layer 1b (source-file mode)

Step 3: Layer 1b — LLM semantic interpretation
  → IF Layer 1a succeeded → inject NDJSON as context (see Layer Handoff Prompt below)
  → IF Layer 1a skipped → read source files directly, perform full LLM analysis

Step 4: Layer 2 — ClassGraph bytecode enrichment (optional, JVM only)
  → Prerequisites: java 17+, compiled project, classgraph-extractor JAR built
  → Run: scripts/extract-type-info.sh <classpath> <target-pattern>
    - Gradle: classpath = "build/classes/kotlin/main" or "build/classes/java/main"
    - Maven:  classpath = "target/classes"
  → IF successful → merge with Layer 1a+1b using rules below
  → IF unavailable or fails → proceed with Layer 1a+1b (sufficient for most cases)

  Layer 2 Merge Rules:
    1. sealed class subtypes    → OVERRIDE Layer 1b (Layer 2 has cross-file visibility)
    2. resolved generics        → OVERRIDE Layer 1b (Layer 2 has full type resolution)
    3. interface→impl mapping   → OVERRIDE Layer 1b (Layer 2 scans full classpath)
    4. annotations              → MERGE (Layer 1a source + Layer 2 runtime annotations)
    5. method signatures        → KEEP Layer 1a (source-level signatures are richer)
    6. nullable info            → MERGE (Layer 1a Kotlin `?` + Layer 2 @Nullable metadata)
    Conflict resolution: Layer 1a (source) takes precedence over Layer 2 (bytecode)
```

### Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `ast-grep: command not found` | Not installed | Skip Layer 1a → Layer 1b source-file mode |
| `extract-types.sh` exits non-zero | Rule parsing error or unsupported language | Log warning → Layer 1b source-file mode |
| Empty NDJSON output | No matches found (possible wrong language detection) | Retry with explicit language → if still empty, Layer 1b source-file mode |
| `extract-type-info.sh` exits non-zero | JAR not built, classpath missing, or Java < 17 | Log warning → use Layer 1a+1b results |
| Source file not found | Wrong target path | Ask user for correct path |

## 1. Target Resolution

**Input parsing:**
- Explicit class/file: `analyze: OrderService` → find matching source file
- Package scope: `analyze: com.example.order` → find all classes in package
- Implicit: infer from recent changes (`git diff --name-only`)

**Target discovery:**
```bash
# Find source files matching target
glob "**/{TargetName}.{kt,java,ts,go}"
# Find existing tests for target
glob "**/{TargetName}Test.{kt,java}" OR "**/{TargetName}.test.{ts,tsx}" OR "**/{target_name}_test.go"
```

**Language auto-detection:**
```
IF target file extension is .kt → language = kotlin
IF target file extension is .java → language = java
IF target file extension is .ts or .tsx → language = typescript
IF target file extension is .go → language = go
IF multiple target files with mixed extensions → detect dominant language from build config
```

### Module Resolution (multi-module projects)

```
IF test-profile.json → multi-module is true:

  target is file path (e.g., "modules/order-domain/src/.../OrderService.kt"):
    → Extract module from path prefix
    → Match against test-profile.json → modules[].path
    → Set target-module in context

  target is class name (e.g., "OrderService"):
    → Glob across all module source roots
    → IF found in exactly 1 module → auto-set target-module
    → IF found in multiple modules → ask user: "OrderService exists in [order-domain, order-api]. Which module?"

  target is package name (e.g., "com.example.order"):
    → Search across all module source roots
    → IF found in 1 module → auto-set target-module
    → IF found in multiple → ask user to specify module

ELSE (single-module project):
  → Skip module resolution
```

## 2. Layer 1a: ast-grep Structural Extraction

> Prerequisite: `scripts/check-ast-grep.sh` passes. If not, skip to Layer 1b.

Run ast-grep extraction per category:

```bash
SCRIPT_DIR="plugins/sub-test-engineer/skills/sub-test-engineer/scripts"

# Full extraction (all categories)
$SCRIPT_DIR/extract-types.sh <target-path> [language] all > /tmp/analysis.ndjson

# Or category-by-category for targeted analysis:
$SCRIPT_DIR/extract-types.sh <target-path> [language] class-hierarchy
$SCRIPT_DIR/extract-types.sh <target-path> [language] methods
$SCRIPT_DIR/extract-types.sh <target-path> [language] constructors
$SCRIPT_DIR/extract-types.sh <target-path> [language] annotations
$SCRIPT_DIR/extract-types.sh <target-path> [language] validation
```

**Extraction rules by language:**

| Category | Java Rule | Kotlin Rule | TypeScript Rule | Go Rule |
|----------|-----------|-------------|-----------------|---------|
| Methods | `extract-methods.yml` | `extract-functions.yml` | `extract-methods.yml` | `extract-functions.yml` |
| Annotations | `extract-annotations.yml` | `extract-annotations.yml` | `extract-decorators.yml` | N/A |
| Constructors | `extract-constructors.yml` | `extract-constructors.yml` | `extract-constructors.yml` | N/A (use struct literal) |
| Class hierarchy | `extract-class-hierarchy.yml` | `extract-class-hierarchy.yml` | `extract-class-hierarchy.yml` | `extract-struct-hierarchy.yml` |
| Validation | `extract-validation.yml` | `extract-validation.yml` | `extract-validation.yml` | `extract-validation.yml` (struct tags) |
| Interface | N/A | N/A | N/A | `extract-interface.yml` |

**JSON output structure (per match):**
```json
{
  "text": "public Order createOrder(CreateOrderRequest request) { ... }",
  "file": "src/main/java/com/example/OrderService.java",
  "range": { "start": { "line": 15, "column": 4 }, "end": { "line": 25, "column": 5 } },
  "metaVariables": { "single": {}, "multi": {} }
}
```

## 3. Layer 1b: LLM Semantic Interpretation

### Layer Handoff Prompt (when Layer 1a succeeded)

```markdown
## ast-grep Structural Extraction Results (Layer 1a)

### Class Hierarchy
{paste class-hierarchy NDJSON results}

### Methods
{paste methods NDJSON results}

### Constructors
{paste constructors NDJSON results}

### Annotations
{paste annotations NDJSON results}

### Validation Annotations
{paste validation NDJSON results}

---

Based on these structural extraction results, perform semantic analysis:

1. **Layer Classification**: For each class, classify its architectural layer:
   - Domain (Entity, Value Object, Aggregate, Domain Service)
   - Application Service (orchestration, transaction boundary)
   - Infrastructure (Repository impl, External client, Adapter)
   - API (Controller, REST endpoint)
   - Event (Event handler, Message listener)

2. **Complexity Rating**: For each method, rate SIMPLE / MODERATE / COMPLEX based on:
   - Branch count (if/when/try-catch from method body)
   - Dependency interactions (calls to injected dependencies)
   - State mutations (writes to fields, DB, events)

3. **Cross-File Type Resolution**: From imports and type references:
   - Resolve interface → implementation mappings
   - Identify sealed class subtype locations
   - Map enum usage across classes

4. **Edge Case Catalog**: Derive from type information:
   - Each nullable parameter → null/non-null test paths
   - Each enum type → exhaustive variant coverage
   - Each validation annotation → boundary values
   - Each sealed class → subtype permutations
   - Each Result/Either return → success/failure paths

5. **Mock Target Identification**: For each constructor dependency:
   - Is it an interface? → primary mock target
   - Is it abstract? → primary mock target
   - Is it a concrete class? → avoid mocking, prefer real instance
   - Does it have side effects? → verify-only mock
```

### Layer 1b Standalone Mode (when Layer 1a was skipped)

When ast-grep is unavailable, read source files directly and perform the same analysis:

```markdown
## Source Code: {TargetName}

{paste full source file content}

Analyze this source code to extract:

1. **Class structure**: class type, generics, interfaces implemented, parent class
2. **Constructor dependencies**: parameter names, types, whether interface or concrete
3. **Method signatures**: name, parameters (name, type, nullable, annotations), return type
4. **Annotations**: class-level and method-level annotations with values
5. **Validation annotations**: @Min, @Max, @Size, @NotNull, @NotBlank, etc. with values
6. **Layer classification**: Domain/Service/Infrastructure/API/Event
7. **Complexity assessment**: SIMPLE/MODERATE/COMPLEX per method
8. **Edge case catalog**: derived from type features
9. **Mock targets**: interface dependencies to mock
```

## 4. Type Signature Schema

For each target class, synthesize analysis into a structured schema:

```yaml
target: OrderService
type-info:
  class-type: class                     # class, data class, sealed class, enum, interface, object
  generics: []                          # generic type parameters
  implements: [OrderUseCase]            # interfaces implemented
  constructor-deps:                     # DI dependencies (from Layer 1a constructors)
    - name: orderRepository
      type: OrderRepository
      interface: true
    - name: paymentClient
      type: PaymentClient
      interface: true
  methods:                              # from Layer 1a methods
    - name: cancelOrder
      params:
        - name: orderId
          type: OrderId                  # value class wrapping Long
          nullable: false
          validation: ["@Positive"]      # from Layer 1a validation
        - name: reason
          type: CancelReason
          type-kind: enum               # enum with N variants
          variants: [USER_REQUEST, ADMIN, TIMEOUT, PAYMENT_FAILED]  # from Layer 1a enum extraction
      return-type: Result<CancelResult>
      throws: [OrderNotFoundException, AlreadyCancelledException]
      side-effects: [repository-write, event-publish]  # LLM-inferred
```

## 5. Complexity Assessment

| Metric | How to assess | Impact on strategy |
|--------|---------------|-------------------|
| **Cyclomatic complexity** | Count branches (if/when/try-catch) | High → more parameterized tests needed |
| **Dependency count** | Constructor parameter count (Layer 1a) | High → mock-heavy, consider integration test |
| **Side effect count** | DB writes, event publishing, external calls | High → integration test preferred |
| **Type richness** | Sealed classes, enums, value classes (Layer 1a) | High → property-based / exhaustive testing |
| **Validation density** | @NotNull, @Min, @Max, @Size, require() (Layer 1a) | High → boundary value analysis |

**Output complexity rating:** SIMPLE (1-2 deps, linear logic) / MODERATE (3-5 deps, branching) / COMPLEX (6+ deps, side effects, state machine)

## 6. Layer Classification

| Layer | Signals (ast-grep detectable) | LLM-inferred signals | Default technique |
|-------|-------------------------------|----------------------|-------------------|
| **Domain** | No framework annotations | value classes, business logic | Property-based + unit |
| **Application Service** | `@Service`, `@Transactional` | orchestrates multiple deps | Mock-based unit |
| **Infrastructure** | `@Repository`, `@Component` | external client impl | Integration (Testcontainers) |
| **API** | `@RestController`, `@GetMapping` | routes, DTOs | MockMvc / supertest |
| **Event** | `@KafkaListener`, `@EventHandler` | async handlers | Embedded broker |

**Go-specific layer signals:**

| Layer | Go Signals | Default technique |
|-------|------------|-------------------|
| **Domain** | structs with validation tags, no external deps | Table-driven + property-based |
| **Service** | structs with interface dependencies | testify mock-based unit |
| **Repository** | interfaces returning models, SQL-related | Testcontainers + sqlmock |
| **Handler** | `http.HandlerFunc`, gin/echo handlers | httptest |
| **Middleware** | `func(http.Handler) http.Handler` | httptest chain |

## 7. Edge Case Catalog

Automatically derive edge cases from type information:

| Type Feature | Source (Layer) | Derived Edge Cases |
|--------------|----------------|-------------------|
| `nullable` param | 1a (Kotlin `?`) / 1b (LLM) | null input, non-null input |
| `enum` param | 1a (enum extraction) | each variant, exhaustive when() coverage |
| `sealed class` | 1a + 1b (cross-file) | each subclass instance |
| `@Min(1)` | 1a (validation extraction) | 0 (below), 1 (boundary), 2 (above) |
| `@Size(min=1, max=100)` | 1a (validation extraction) | empty, 1 char, 100 chars, 101 chars |
| `Result<T>` return | 1b (LLM inference) | success path, failure path |
| `List<T>` param | 1b (LLM inference) | empty, single, multiple, null elements |
| value class wrapping | 1b (LLM inference) | unwrapped boundary values |

**Go-specific edge cases:**

| Type Feature | Source (Layer) | Derived Edge Cases |
|--------------|----------------|-------------------|
| `*T` (pointer) | 1a (struct extraction) | nil, valid pointer |
| `error` return | 1a (function extraction) | nil error, specific error types |
| struct tag `validate:"required"` | 1a (validation extraction) | empty string, whitespace, valid |
| struct tag `validate:"min=N,max=M"` | 1a (validation extraction) | N-1, N, M, M+1 |
| `[]T` slice param | 1a (function extraction) | nil, empty, single, multiple |
| `map[K]V` param | 1a (function extraction) | nil, empty, single key, missing key |
| interface param | 1a (interface extraction) | mock implementation, nil interface |
| context.Context | 1a (function extraction) | context.Background(), cancelled context, timeout |

## 8. Output

```markdown
## Analysis Report: {TargetName}

### Extraction Summary
- Layer 1a (ast-grep): {N} methods, {N} annotations, {N} constructor deps, {N} validation constraints
  - Status: {completed | skipped (ast-grep unavailable) | partial (some categories failed)}
- Layer 1b (LLM): layer classification, complexity, cross-file inference
- Layer 2 (ClassGraph): {completed | skipped (not compiled) | not available}

### Targets
| # | Class | Layer | Complexity | Existing Coverage | Priority |
|---|-------|-------|------------|-------------------|----------|
| 1 | OrderService | Application | MODERATE | 45% line | HIGH |
| 2 | OrderValidator | Domain | SIMPLE | 0% line | CRITICAL |

### Type Info per Target
{Type Signature Schema YAML for each target — see Section 4}

### Edge Cases Identified
- OrderService.cancelOrder: 4 enum variants × 2 nullable paths × 3 error types = 24 cases
- OrderValidator.validate: 6 validation annotations → 18 boundary values

### Dependencies to Mock
- OrderRepository (interface) → MockK every{}/Mockito when()
- PaymentClient (interface) → MockK every{}/Mockito when()
- EventPublisher (interface) → verify-only mock
```
