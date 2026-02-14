# Directory Context Guide

> Mapping information for each directory referenced by the profile's Layer Paths.
> Detailed rules for each layer are found in the loaded architecture reference.

> **Profile Priority Principle:**
> When a Project Profile is found, the actual layer paths and naming patterns override the defaults in this document.
> Only items not present in the profile use the defaults from this document.

---

## Directory Mapping

### Domain Model

| Structure | Path |
|-----------|------|
| Single module | `core/domain-model/` |
| Multi-module | `:core/src/main/.../domain/` |
| Domain-split | `:{domain}-core/src/main/.../domain/` |

> Rules: Domain Model section of `references/hexagonal-architecture.md`
> Key: No external dependencies, state changes use Definition pattern (Kotlin) / immutable pattern (Java)

### Ports

| Structure | Path |
|-----------|------|
| Single module | `core/` |
| Multi-module | `:core/src/main/.../` (Port interfaces) |
| Domain-split | `:{domain}-core/src/main/.../` |

> Rules: core section of `references/hexagonal-architecture.md`
> Key: Interfaces only, Reader/Appender/Updater separation, reference profile's `repository-pattern`

### Business Logic (Application)

| Structure | Path |
|-----------|------|
| Single module | `application/` |
| Multi-module | `:application/src/main/.../` |
| Domain-split | `:{domain}-application/src/main/.../` |

> Rules: Application section of `references/hexagonal-architecture.md`
> Key: @Service, Use Case implementation, access external resources only through Ports

### Data Access (Infrastructure)

| Structure | Path |
|-----------|------|
| Single module | `infrastructure/` |
| Multi-module | `:infrastructure/src/main/.../` |
| Domain-split | `:{domain}-infrastructure/src/main/.../` |

> Rules: Infrastructure section of `references/hexagonal-architecture.md`
> Key: JPA Entity (*JpaEntity), toModel()/from() conversion, no Port references
> JOOQ: `references/jooq-conventions.md` (*JooqAdapter)

### Presentation

| Structure | Path |
|-----------|------|
| Single module | `app/` |
| Multi-module | `:api/src/main/.../` |

> Rules: Controller section of `references/hexagonal-architecture.md`
> Key: Reference only Use Cases, no direct Reader/Port references, *HttpRequest/*HttpResponse

### Shared Kernel (Multi-module only)

| Structure | Path |
|-----------|------|
| Multi-module | `:shared-kernel/src/main/.../` |

> Rules: Shared Kernel section of `references/hexagonal-architecture.md`
> Key: 공유 Value Object, Domain Event 인터페이스, 공통 예외 타입. 비즈니스 로직 금지.

### Bootstrap (Multi-module only)

| Structure | Path |
|-----------|------|
| Multi-module | `:bootstrap/src/main/.../` |

> Key: Spring Boot Main, Configuration, 전체 모듈 의존성 조립

### Test

| Type | Path | Reference Document |
|------|------|--------------------|
| Unit tests | `test/` | testing reference (unit-testing / java-unit-testing) |
| Integration tests | `integrationTest/` | testing reference (integration-testing / java-integration-testing) |
| Test Fixtures | `testFixtures/` | hexagonal-architecture.md (Port Stub Pattern) |

> Rules adjusted based on profile's `test-structure` and `assertion` information

---

## How to Use

Before writing/modifying a file, identify the layer for that directory and check the reference document from the mapping above.
This guide is automatically referenced during the Implement phase, and serves as the basis for checking directory-level rule violations during the Verify phase.

For multi-module projects, the module name determines the layer (e.g., `:core` = Domain Model + Ports, `:application` = Business Logic).
For domain-split projects, the `{domain}-` prefix determines the bounded context.
