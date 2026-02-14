# Gradle Multi-Module Build Guide

> Convention Plugins 및 Version Catalog를 활용한 멀티모듈 빌드 구성 가이드

---

## Convention Plugins (build-logic/)

### 개요

Convention Plugin은 빌드 설정의 중복을 제거하고, 모듈별 역할에 맞는 의존성을 중앙에서 관리하는 패턴이다.

```
project-root/
├── build-logic/
│   ├── build.gradle.kts          ← Plugin 빌드 설정
│   ├── settings.gradle.kts       ← Version Catalog 연동
│   └── src/main/kotlin/
│       ├── kotlin-core.gradle.kts
│       ├── kotlin-application.gradle.kts
│       ├── kotlin-infrastructure.gradle.kts
│       └── kotlin-api.gradle.kts
├── settings.gradle.kts           ← includeBuild("build-logic")
└── ...modules
```

### build-logic 프로젝트 설정

```kotlin
// build-logic/settings.gradle.kts
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

// build-logic/build.gradle.kts
plugins {
    `kotlin-dsl`
}

repositories {
    gradlePluginPortal()
}

dependencies {
    implementation(libs.kotlin.gradle.plugin)
    implementation(libs.spring.boot.gradle.plugin)
    implementation(libs.spring.dependency.management)
}
```

### Hexagonal 레이어별 Convention Plugin

#### core 모듈 — 순수 Kotlin/Java

```kotlin
// build-logic/src/main/kotlin/kotlin-core.gradle.kts
plugins {
    kotlin("jvm")
    `java-test-fixtures`
}

dependencies {
    // 순수 Kotlin/Java만 허용 — Spring, JPA 등 금지
    testImplementation(libs.kotest)
    testImplementation(libs.mockk)
}
```

#### application 모듈 — Use Case

```kotlin
// build-logic/src/main/kotlin/kotlin-application.gradle.kts
plugins {
    kotlin("jvm")
}

dependencies {
    implementation(project(":core"))
    implementation(libs.spring.tx)

    testImplementation(testFixtures(project(":core")))
    testImplementation(libs.kotest)
    testImplementation(libs.mockk)
}
```

#### infrastructure 모듈 — Adapter

```kotlin
// build-logic/src/main/kotlin/kotlin-infrastructure.gradle.kts
plugins {
    kotlin("jvm")
    kotlin("plugin.jpa")
}

dependencies {
    implementation(project(":core"))
    implementation(libs.spring.boot.starter.data.jpa)

    testImplementation(testFixtures(project(":core")))
    testImplementation(libs.spring.boot.starter.test)
}
```

#### api 모듈 — Controller

```kotlin
// build-logic/src/main/kotlin/kotlin-api.gradle.kts
plugins {
    kotlin("jvm")
}

dependencies {
    implementation(project(":application"))
    implementation(libs.spring.boot.starter.web)

    testImplementation(libs.spring.boot.starter.test)
}
```

### 모듈에서 Convention Plugin 적용

```kotlin
// core/build.gradle.kts
plugins {
    id("kotlin-core")
}

// application/build.gradle.kts
plugins {
    id("kotlin-application")
}

// infrastructure/build.gradle.kts
plugins {
    id("kotlin-infrastructure")
}
```

### Java 프로젝트용 Convention Plugin

Java 프로젝트는 `kotlin("jvm")` 대신 `java-library`를 사용한다:

```kotlin
// build-logic/src/main/kotlin/java-core.gradle.kts
plugins {
    `java-library`
    `java-test-fixtures`
}

dependencies {
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.assertj)
    testImplementation(libs.mockito)
}
```

### Domain-Split 모듈 패턴

도메인별 모듈 분리 시, 공통 Convention Plugin을 재사용한다:

```kotlin
// order-core/build.gradle.kts
plugins {
    id("kotlin-core")
}
dependencies {
    implementation(project(":shared-kernel"))
}

// order-application/build.gradle.kts
plugins {
    id("kotlin-application")
}
dependencies {
    implementation(project(":order-core"))
    // 다른 도메인 참조 시 core만 허용 (event 소비용)
    implementation(project(":payment-core"))
}
```

---

## Version Catalog (libs.versions.toml)

### 파일 위치

```
project-root/
└── gradle/
    └── libs.versions.toml
```

### 구조

```toml
[versions]
kotlin = "2.0.21"
spring-boot = "3.4.1"
kotest = "5.9.1"
mockk = "1.13.13"
archunit = "1.3.0"

[libraries]
# Kotlin
kotlin-gradle-plugin = { module = "org.jetbrains.kotlin:kotlin-gradle-plugin", version.ref = "kotlin" }
kotlin-reflect = { module = "org.jetbrains.kotlin:kotlin-reflect", version.ref = "kotlin" }

# Spring
spring-boot-gradle-plugin = { module = "org.springframework.boot:spring-boot-gradle-plugin", version.ref = "spring-boot" }
spring-dependency-management = { module = "io.spring.gradle:dependency-management-plugin", version = "1.1.7" }
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
spring-tx = { module = "org.springframework:spring-tx" }

# Test
kotest = { module = "io.kotest:kotest-runner-junit5", version.ref = "kotest" }
mockk = { module = "io.mockk:mockk", version.ref = "mockk" }
archunit = { module = "com.tngtech.archunit:archunit-junit5", version.ref = "archunit" }

# Java Test
junit-jupiter = { module = "org.junit.jupiter:junit-jupiter" }
assertj = { module = "org.assertj:assertj-core" }
mockito = { module = "org.mockito:mockito-core" }

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-spring = { id = "org.jetbrains.kotlin.plugin.spring", version.ref = "kotlin" }
kotlin-jpa = { id = "org.jetbrains.kotlin.plugin.jpa", version.ref = "kotlin" }
```

### Convention Plugin에서 Version Catalog 참조

Convention Plugin(build-logic/) 내에서 `libs`로 참조하려면 settings.gradle.kts에서 연동이 필요하다:

```kotlin
// build-logic/settings.gradle.kts (위 Convention Plugin 섹션 참조)
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}
```

### 운용 원칙

| 원칙 | 설명 |
|------|------|
| 버전 중앙 관리 | 모든 버전은 `[versions]`에서 관리, 모듈별 하드코딩 금지 |
| Spring BOM 위임 | Spring 관련 라이브러리는 BOM 버전을 따르므로 `version` 생략 가능 |
| Plugin 알리아스 | Convention Plugin 내에서는 `libs.plugins.*` 대신 직접 플러그인 ID 사용 |
| 네이밍 컨벤션 | kebab-case, `그룹-아티팩트` 형식 (예: `spring-boot-starter-web`) |
