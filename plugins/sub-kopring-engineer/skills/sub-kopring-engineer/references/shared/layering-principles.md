# Layering Principles

> Martin Fowler의 레이어링 원칙을 Spring Boot Hexagonal Architecture에 적용하는 가이드.
> 상세 아키텍처 규칙: [hexagonal-architecture.md](./hexagonal-architecture.md)

---

## Core Principles (Fowler Consensus)

### 1. Separation of Concerns -- Each Layer Has a Single Concern

Each layer handles only one concern (Presentation, Business Logic, Data Access).
Maximize cohesion within layers and minimize coupling between layers.

### 2. Dependency Direction -- Lower Layers Do Not Know About Upper Layers

Lower layers (Data Access) do not depend on upper layers (Presentation, Business Logic).
In traditional top-down, only top-to-bottom is allowed; in hexagonal, all dependencies point inward (toward core).

### 3. No Business Logic in Presentation

Controllers contain only request validation and response mapping.
Business rules, state changes, and computation logic must reside in the Service/Domain layer.

### 4. No UI/Presentation References in Business Layer

Services must not reference Presentation elements such as Controller, HttpServletRequest, or HttpServletResponse.

### 5. No Circular References Between Layers

Circular dependencies of the form A → B → A are never allowed under any circumstances.
If circular dependencies arise, resolve them through interface extraction or event-based decoupling.

### 6. Business Layer Uses Only Abstractions of Technical Services

Do not depend directly on technical services such as DB, messaging, or external APIs.
Access them only through abstracted forms like interfaces (Ports, Repository interfaces).

### 7. Each Layer Must Be Independently Testable

Business logic must be unit-testable without the Spring context.
Inter-layer dependencies must be structured so they can be replaced with Mocks/Fakes.

### 8. Layers Are Logical Divisions (Independent of Physical Deployment)

Layers are logical separation units in the code and do not necessarily correspond to deployment units (artifacts).
Layering should be maintained even within a monolith.

### 9. Encapsulation Within Layers -- Hide Implementation Details

Each layer does not expose its internal implementation to upper layers.
Only public interfaces are provided externally, and internal classes/methods have restricted access.

---

## Spring Boot 3-Layer Mapping

| Logical Layer | Spring Boot | Hexagonal Path |
|--------------|-------------|----------------|
| Presentation | @RestController | app/ |
| Domain Logic | @Service | application/ + core/ |
| Data Access | @Repository | infrastructure/ |
| Domain Model | data class / Entity | core/domain-model/ |

---

## Dependency Direction Rules

**Inside-out (Hexagonal):**
```
app → application → core ← infrastructure
                     ↑
              (all dependencies point toward core)
```
Outer layers point toward the inside (core). Core does not depend on anything.

---

## Anti-patterns (Fowler: Strongly Rejected)

### 1. Splitting Teams by Layer
Teams should be full-stack (vertical slice). Splitting teams by layer causes coordination costs to skyrocket when changes are needed.

### 2. Blindly Re-wrapping Exceptions at Layer Boundaries
Valueless exception wrapping pollutes stack traces. Only wrap when conversion is actually needed.
```kotlin
// ❌ Pointless re-wrapping
catch (e: RepositoryException) { throw ServiceException(e) }

// ✅ Convert only when necessary
catch (e: JpaException) { throw DomainNotFoundException(e.entityId) }
```

### 3. Layer = Deployment Unit
Logical layer separation does not imply physical deployment separation. Introducing network calls significantly increases complexity and latency.

---

## Large-Scale Systems: Domain-Oriented Modularization

Fowler: "domain-oriented modules which are internally layered"

In large-scale systems, **domain-based module separation** is more effective than layer-based separation.
Each domain module follows Hexagonal Architecture internally.

> 상세 가이드:
> - Module Separation Strategy → [hexagonal-architecture.md § Multi-Module Hexagonal Architecture](./hexagonal-architecture.md)
> - Domain-Based Module Separation → [hexagonal-architecture.md § Domain-Based Module Separation](./hexagonal-architecture.md)
> - Shared Kernel → [hexagonal-architecture.md § Shared Kernel](./hexagonal-architecture.md)
> - Event-Driven Inter-Module Communication → [hexagonal-architecture.md § Event-Driven Inter-Module Communication](./hexagonal-architecture.md)

---

## Code Generation Checklist

- [ ] Before creating a new class: Confirm which layer it belongs to
- [ ] Before adding a new dependency: Verify dependency direction rules
- [ ] After implementation: Verify no circular references exist
- [ ] Business logic tests: Verify testability without Spring context
- [ ] Verify @Transactional is not used on Controllers (a signal of business logic leaking in)
