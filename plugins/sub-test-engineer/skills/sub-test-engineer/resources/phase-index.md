# Phase Index

> Quick reference for navigating sub-test-engineer protocol phases

---

## Phase Overview

| Phase | Name | Purpose | Primary Output |
|-------|------|---------|----------------|
| 0 | Discovery | Detect project context | test-profile.json |
| 1 | Analyze | Extract type information | type-analysis.json |
| 2 | Strategize | Select testing techniques | test-strategy.md |
| 3 | Generate | Write test code | *Test.{kt,java,ts,go} |
| 4 | Validate | Verify test quality | validation-report.md |

---

## Phase Protocols

### Phase 0: Discovery
**Protocol:** [test-discovery-protocol.md](test-discovery-protocol.md)

**Detects:**
- Build tool (Gradle/Maven/npm/pnpm/Go)
- Test framework (JUnit 5/Kotest/Jest/Vitest/testing)
- Mock library (Mockito/MockK/jest.mock/testify)
- Coverage tool (JaCoCo/Kover/Istanbul/go test -cover)
- Multi-module structure

**Output:** `.sub-test-engineer/test-profile.json`

---

### Phase 1: Analyze
**Protocol:** [analyze-protocol.md](analyze-protocol.md)

**3-Layer Extraction:**
1. **Layer 1a:** ast-grep structural extraction (~1s, deterministic)
2. **Layer 1b:** LLM semantic interpretation
3. **Layer 2:** ClassGraph bytecode enrichment (optional)

**Output:** Type analysis JSON with:
- Method signatures
- Class hierarchy
- Validation annotations
- Enum/sealed class variants

---

### Phase 2: Strategize
**Protocol:** [strategize-protocol.md](strategize-protocol.md)

**Technique Selection by Layer:**
| Code Layer | Techniques |
|------------|------------|
| Domain | Property-based, Unit |
| Application | Unit with mocks |
| Infrastructure | Integration, Contract |
| API | Contract, E2E |

**Output:** Test strategy document

---

### Phase 3: Generate
**Protocol:** [generate-protocol.md](generate-protocol.md)

**Capabilities:**
- Pattern conformance (learns project style)
- Focal context injection
- Agent Teams parallel generation (5+ targets)

**Output:** Test source files

---

### Phase 4: Validate
**Protocol:** [validate-protocol.md](validate-protocol.md)

**5-Stage Pipeline:**
1. Compile check
2. Test execution
3. Coverage measurement
4. Mutation testing (STANDARD+)
5. Quality assessment

**Tiers:** [validation-tiers.md](validation-tiers.md)

---

## Common Cross-References

| Topic | Document |
|-------|----------|
| Error recovery | [error-playbook.md](error-playbook.md) |
| Validation thresholds | [validation-tiers.md](validation-tiers.md) |
| Multi-module handling | [multi-module-context.md](multi-module-context.md) |
| Error handling levels | [error-handling-framework.md](error-handling-framework.md) |

---

## Execution Modes

| Mode | Entry Phase | Exit Phase |
|------|-------------|------------|
| All-in-one | Discovery | Validate |
| `analyze:` | Discovery | Analyze |
| `strategize:` | Analyze | Strategize |
| `generate` | Strategize | Generate |
| `validate` | Generate | Validate |
| `loop N` | Discovery | Validate (N iterations) |
| `coverage-target N%` | Discovery | Validate (until N% coverage) |

---

## Quick Navigation

**By Task:**
- "How to detect build tool?" → Phase 0, [test-discovery-protocol.md](test-discovery-protocol.md)
- "How to extract type info?" → Phase 1, [analyze-protocol.md](analyze-protocol.md)
- "How to select technique?" → Phase 2, [strategize-protocol.md](strategize-protocol.md)
- "How to handle errors?" → [error-playbook.md](error-playbook.md)
- "What tier to use?" → [validation-tiers.md](validation-tiers.md)

**By Language:**
- Java → `rules/java/`, JUnit 5/Mockito
- Kotlin → `rules/kotlin/`, JUnit 5/Kotest/MockK
- TypeScript → `rules/typescript/`, Jest/Vitest
- Go → `rules/go/`, testing/testify
