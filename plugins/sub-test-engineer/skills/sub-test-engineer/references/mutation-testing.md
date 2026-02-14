# Mutation Testing Reference

> Code examples and configurations for mutation testing. Concepts assumed known.

## JVM: PIT (PITest)

### Gradle Setup
```kotlin
plugins {
    id("info.solidsoft.pitest") version "1.15.0"
}

dependencies {
    testImplementation("org.pitest:pitest-junit5-plugin:1.2.1")
}

pitest {
    targetClasses.set(setOf("com.example.order.domain.*"))
    targetTests.set(setOf("com.example.order.domain.*Test"))
    mutators.set(setOf("DEFAULTS"))  // or "STRONGER", "ALL"
    outputFormats.set(setOf("HTML", "XML"))
    timestampedReports.set(false)
    threads.set(4)
}
```

### Run
```bash
./gradlew pitest
# Report: build/reports/pitest/index.html
```

### Common PIT Mutators
| Mutator | What it does | Example |
|---------|-------------|---------|
| CONDITIONALS_BOUNDARY | `>` to `>=`, `<` to `<=` | `if (age > 18)` to `if (age >= 18)` |
| NEGATE_CONDITIONALS | `==` to `!=`, `>` to `<=` | `if (x == 0)` to `if (x != 0)` |
| MATH | `+` to `-`, `*` to `/` | `total + tax` to `total - tax` |
| INCREMENTS | `++` to `--` | `count++` to `count--` |
| RETURN_VALS | change return value | `return true` to `return false` |
| VOID_METHOD_CALLS | remove void method call | removes `repository.save(entity)` |

## TypeScript/JavaScript: Stryker Mutator

### Setup
```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner @stryker-mutator/typescript-checker
npx stryker init
```

### Configuration (stryker.config.mjs)
```javascript
export default {
  mutate: ['src/**/*.ts', '!src/**/*.test.ts', '!src/**/*.d.ts'],
  testRunner: 'jest',
  checkers: ['typescript'],
  reporters: ['html', 'clear-text', 'progress'],
  coverageAnalysis: 'perTest',
  thresholds: { high: 80, low: 60, break: 50 },
};
```

### Run
```bash
npx stryker run
# Report: reports/mutation/html/index.html
```

## Target Scores

| Context | Target Score |
|---------|-------------|
| Domain logic | 80%+ |
| Application services | 60-70% |
| Infrastructure | 40-50% |
| Overall project | 60%+ |
