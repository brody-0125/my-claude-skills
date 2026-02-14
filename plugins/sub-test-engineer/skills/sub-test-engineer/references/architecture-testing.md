# Architecture Testing Reference

> Code examples and configurations for architecture testing. Concepts assumed known.

## JVM: ArchUnit

### Gradle Setup
```kotlin
testImplementation("com.tngtech.archunit:archunit-junit5:1.4.1")
```

### Rules
```kotlin
@AnalyzeClasses(packages = ["com.example.order"])
class ArchitectureTest {
    // Layer dependency
    @ArchTest
    val `domain should not depend on infrastructure` = noClasses()
        .that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAPackage("..infrastructure..")

    @ArchTest
    val `domain should not depend on Spring` = noClasses()
        .that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAPackage("org.springframework..")

    // Onion architecture
    @ArchTest
    val `hexagonal architecture` = Architectures.onionArchitecture()
        .domainModels("..domain.model..")
        .domainServices("..domain.service..")
        .applicationServices("..application..")
        .adapter("persistence", "..adapter.persistence..")
        .adapter("web", "..adapter.web..")

    // Naming conventions
    @ArchTest
    val `repositories should end with Repository` = classes()
        .that().implement(Repository::class.java)
        .should().haveSimpleNameEndingWith("Repository")

    @ArchTest
    val `use cases should be interfaces` = classes()
        .that().haveSimpleNameEndingWith("UseCase")
        .should().beInterfaces()

    // Annotation placement
    @ArchTest
    val `Transactional only on application services` = noClasses()
        .that().resideOutsideOfPackage("..application..")
        .should().beAnnotatedWith(Transactional::class.java)
}
```

## Kotlin: Konsist

### Gradle Setup
```kotlin
testImplementation("com.lemonappdev:konsist:0.17.3")
```

### Kotlin-Specific Rules
```kotlin
class KonsistArchitectureTest {
    @Test
    fun `domain classes should not use Spring annotations`() {
        Konsist.scopeFromPackage("com.example.order.domain")
            .classes()
            .assertFalse { it.hasAnnotationOf(Component::class) }
    }

    @Test
    fun `data classes in domain should have private setters`() {
        Konsist.scopeFromPackage("com.example.order.domain.model")
            .classes()
            .filter { it.hasModifier(KoModifier.DATA) }
            .properties()
            .assertFalse { it.hasMutableModifier }
    }
}
```

## TypeScript: dependency-cruiser

```bash
npm install --save-dev dependency-cruiser
npx depcruise --init
```

### Configuration (.dependency-cruiser.cjs)
```javascript
module.exports = {
  forbidden: [
    {
      name: 'domain-no-infra',
      from: { path: '^src/domain' },
      to: { path: '^src/infrastructure' },
    },
    {
      name: 'no-circular',
      from: {},
      to: { circular: true },
    },
  ],
};
```

### Run
```bash
npx depcruise src --config .dependency-cruiser.cjs
```
