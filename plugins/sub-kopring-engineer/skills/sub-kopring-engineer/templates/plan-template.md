# Implementation Plan

**Task**: {task description}
**Date**: {date}

## Summary
- Affected layers: {profile-based layer names}
- Estimated changed files: {N}
- Test inclusion: {unit tests / integration tests / both}

---

## Changes by Layer

<!-- Layer order: core/domain-model → core(ports) → application → infrastructure → app -->

### {Layer 1: Domain Model}
- [ ] {change item}

### {Layer 2: Business Logic}
- [ ] {change item}

### {Layer 3: Data Access}
- [ ] {change item}

### {Layer 4: Presentation}
- [ ] {change item}

---

## Multi-Module Changes (if applicable)

<!-- Include this section when adding new modules or modifying module dependencies -->

### New Modules
- [ ] Module name: `{module-name}` (role: core/application/infrastructure/api/bootstrap)
- [ ] `settings.gradle.kts` — `include("{module-name}")`
- [ ] `{module-name}/build.gradle.kts` — Convention Plugin 적용 (예: `id("kotlin-core")`)
- [ ] Module dependencies: `implementation(project(":xxx"))` — 의존성 방향 준수 확인

### Module Dependency Changes
- [ ] 변경 모듈: `{module-name}` → 추가 의존성: `project(":xxx")`
- [ ] 금지 의존성 방향 위반 없음 확인 (verify-conventions.sh)

> Convention Plugin 및 Version Catalog 가이드: [gradle-build-guide.md](../references/gradle-build-guide.md)

---

## Test Plan

### Unit Tests
- [ ] {test class}: {test scenario}

### Integration Tests
- [ ] {test class}: {test scenario}

---

## Convention Checkpoint

### General Layering
- [ ] Dependency direction compliance (upper → lower only)
- [ ] No circular references between layers

### Architecture-specific Core Constraints
- [ ] Compliance with architecture reference dependency rules

### Common
- [ ] Naming convention compliance

> Full verification items are automatically checked in the Verify Phase using verify-protocol.md + verify-conventions.sh

---

## Notes
- {special considerations}
