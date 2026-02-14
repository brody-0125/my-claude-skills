#!/bin/bash
# Module: detect-build-system.sh
# Detects build tool, versions, plugins, modules, and test frameworks.
#
# Input globals:  PROJECT_DIR
# Output globals: BUILD_TOOL, SPRING_BOOT_VERSION, KOTLIN_VERSION, JDK_VERSION,
#                 MODULES, PLUGINS, TEST_FRAMEWORKS

BUILD_TOOL="unknown"
SPRING_BOOT_VERSION=""
KOTLIN_VERSION=""
JDK_VERSION=""
MODULES=""
PLUGINS=""
TEST_FRAMEWORKS=""

detect_build() {
  if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    BUILD_TOOL="gradle-kotlin-dsl"
    local bf="$PROJECT_DIR/build.gradle.kts"

    # Spring Boot version
    SPRING_BOOT_VERSION=$(grep -oE 'org\.springframework\.boot[^0-9]*[0-9]+\.[0-9]+\.[0-9]+' "$bf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    [ -z "$SPRING_BOOT_VERSION" ] && SPRING_BOOT_VERSION=$(grep 'spring-boot-starter' "$bf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

    # Kotlin version
    KOTLIN_VERSION=$(grep -oE 'kotlin\("jvm"\)[[:space:]]*version[[:space:]]*"?[0-9.]+' "$bf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9.]+' | head -1 || true)
    [ -z "$KOTLIN_VERSION" ] && KOTLIN_VERSION=$(grep -oE 'kotlinVersion[[:space:]]*=[[:space:]]*"?[0-9.]+' "$bf" 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1 || true)

    # JDK version
    JDK_VERSION=$(grep -oE 'jvmToolchain\([0-9]+' "$bf" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    [ -z "$JDK_VERSION" ] && JDK_VERSION=$(grep -oE 'JavaVersion\.VERSION_[0-9]+' "$bf" 2>/dev/null | sed 's/JavaVersion\.VERSION_//' | head -1 || true)
    [ -z "$JDK_VERSION" ] && JDK_VERSION=$(grep -oE 'jvmTarget[[:space:]]*=[[:space:]]*"?[0-9]+' "$bf" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)

    # Plugin detection
    local detected_plugins=""
    grep -q "spring-boot" "$bf" 2>/dev/null && detected_plugins+="spring-boot, "
    grep -q "jpa\|hibernate" "$bf" 2>/dev/null && detected_plugins+="jpa, "
    grep -qiE "querydsl|kapt.*querydsl" "$bf" 2>/dev/null && detected_plugins+="querydsl, "
    grep -qiE "nu\.studer\.jooq|org\.jooq" "$bf" 2>/dev/null && detected_plugins+="jooq, "
    grep -q "kotlin-spring\|plugin.spring" "$bf" 2>/dev/null && detected_plugins+="kotlin-spring, "
    grep -q "kotlin-jpa\|plugin.jpa" "$bf" 2>/dev/null && detected_plugins+="kotlin-jpa, "
    grep -qiE "lombok" "$bf" 2>/dev/null && detected_plugins+="lombok, "
    grep -qiE "checkstyle" "$bf" 2>/dev/null && detected_plugins+="checkstyle, "
    grep -qiE "spotless" "$bf" 2>/dev/null && detected_plugins+="spotless, "
    grep -qiE "spotbugs" "$bf" 2>/dev/null && detected_plugins+="spotbugs, "
    grep -qiE "pmd" "$bf" 2>/dev/null && detected_plugins+="pmd, "
    grep -qiE "detekt" "$bf" 2>/dev/null && detected_plugins+="detekt, "
    grep -qiE "error.?prone|errorprone|net\.ltgt\.errorprone" "$bf" 2>/dev/null && detected_plugins+="error-prone, "
    grep -qiE "jacoco" "$bf" 2>/dev/null && detected_plugins+="jacoco, "
    PLUGINS="${detected_plugins%, }"

    # Test framework detection
    local test_libs="junit5"
    grep -qiE "strikt" "$bf" 2>/dev/null && test_libs+=", strikt"
    grep -qiE "kotest" "$bf" 2>/dev/null && test_libs+=", kotest"
    grep -qiE "assertj" "$bf" 2>/dev/null && test_libs+=", assertj"
    grep -qiE "mockk" "$bf" 2>/dev/null && test_libs+=", mockk"
    grep -qiE "mockito" "$bf" 2>/dev/null && test_libs+=", mockito"
    grep -qiE "fixture.monkey\|fixturemonkey" "$bf" 2>/dev/null && test_libs+=", fixture-monkey"
    grep -qiE "archunit" "$bf" 2>/dev/null && test_libs+=", archunit"
    TEST_FRAMEWORKS="$test_libs"

    # Module structure (settings.gradle.kts)
    local sf="$PROJECT_DIR/settings.gradle.kts"
    [ ! -f "$sf" ] && sf="$PROJECT_DIR/settings.gradle"
    if [ -f "$sf" ]; then
      MODULES=$(grep -oE 'include[[:space:]]*\([[:space:]]*"[^"]+' "$sf" 2>/dev/null | sed 's/include[[:space:]]*([[:space:]]*"//' | tr '\n' ', ' | sed 's/,$//' || true)
      [ -z "$MODULES" ] && MODULES=$(grep -oE "include[[:space:]]*\([[:space:]]*'[^']+" "$sf" 2>/dev/null | sed "s/include[[:space:]]*([[:space:]]*'//" | tr '\n' ', ' | sed 's/,$//' || true)
      [ -z "$MODULES" ] && MODULES=$(grep -oE "include[[:space:]]+'?[^'\")\s]+" "$sf" 2>/dev/null | sed "s/include[[:space:]]*'*//" | tr '\n' ', ' | sed 's/,$//' || true)
    fi

  elif [ -f "$PROJECT_DIR/build.gradle" ]; then
    BUILD_TOOL="gradle-groovy"
    local bf="$PROJECT_DIR/build.gradle"

    SPRING_BOOT_VERSION=$(grep -oE "springBootVersion[[:space:]]*=[[:space:]]*['\"]?[0-9.]+" "$bf" 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1 || true)
    KOTLIN_VERSION=$(grep -oE "kotlinVersion[[:space:]]*=[[:space:]]*['\"]?[0-9.]+" "$bf" 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1 || true)
    JDK_VERSION=$(grep -oE "jvmTarget[[:space:]]*=[[:space:]]*['\"]?[0-9]+" "$bf" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    [ -z "$JDK_VERSION" ] && JDK_VERSION=$(grep -oE "sourceCompatibility[[:space:]]*=[[:space:]]*['\"]?[0-9.]+" "$bf" 2>/dev/null | grep -oE '[0-9]+[0-9.]*' | head -1 || true)
    [ -z "$JDK_VERSION" ] && JDK_VERSION=$(grep -oE "JavaVersion\.VERSION_[0-9]+" "$bf" 2>/dev/null | sed 's/JavaVersion\.VERSION_//' | head -1 || true)

    local detected_plugins=""
    grep -q "spring-boot" "$bf" 2>/dev/null && detected_plugins+="spring-boot, "
    grep -q "jpa\|hibernate" "$bf" 2>/dev/null && detected_plugins+="jpa, "
    grep -qiE "querydsl|kapt.*querydsl" "$bf" 2>/dev/null && detected_plugins+="querydsl, "
    grep -qiE "nu\.studer\.jooq|org\.jooq" "$bf" 2>/dev/null && detected_plugins+="jooq, "
    grep -qiE "lombok" "$bf" 2>/dev/null && detected_plugins+="lombok, "
    grep -qiE "checkstyle" "$bf" 2>/dev/null && detected_plugins+="checkstyle, "
    grep -qiE "spotless" "$bf" 2>/dev/null && detected_plugins+="spotless, "
    grep -qiE "spotbugs" "$bf" 2>/dev/null && detected_plugins+="spotbugs, "
    grep -qiE "pmd" "$bf" 2>/dev/null && detected_plugins+="pmd, "
    grep -qiE "detekt" "$bf" 2>/dev/null && detected_plugins+="detekt, "
    grep -qiE "error.?prone|errorprone|net\.ltgt\.errorprone" "$bf" 2>/dev/null && detected_plugins+="error-prone, "
    grep -qiE "jacoco" "$bf" 2>/dev/null && detected_plugins+="jacoco, "
    PLUGINS="${detected_plugins%, }"

    local test_libs="junit5"
    grep -qiE "strikt" "$bf" 2>/dev/null && test_libs+=", strikt"
    grep -qiE "kotest" "$bf" 2>/dev/null && test_libs+=", kotest"
    grep -qiE "assertj" "$bf" 2>/dev/null && test_libs+=", assertj"
    grep -qiE "mockk" "$bf" 2>/dev/null && test_libs+=", mockk"
    grep -qiE "mockito" "$bf" 2>/dev/null && test_libs+=", mockito"
    grep -qiE "fixture.monkey" "$bf" 2>/dev/null && test_libs+=", fixture-monkey"
    grep -qiE "archunit" "$bf" 2>/dev/null && test_libs+=", archunit"
    TEST_FRAMEWORKS="$test_libs"

    local sf="$PROJECT_DIR/settings.gradle"
    [ ! -f "$sf" ] && sf="$PROJECT_DIR/settings.gradle.kts"
    if [ -f "$sf" ]; then
      MODULES=$(grep -oE "include[[:space:]]+'?[^'\")\s]+" "$sf" 2>/dev/null | sed "s/include[[:space:]]*'*//" | tr '\n' ', ' | sed 's/,$//' || true)
    fi

  elif [ -f "$PROJECT_DIR/pom.xml" ]; then
    BUILD_TOOL="maven"
    local pf="$PROJECT_DIR/pom.xml"
    SPRING_BOOT_VERSION=$(grep -oE '<spring-boot.version>[^<]+' "$pf" 2>/dev/null | sed 's/<spring-boot.version>//' | head -1 || true)
    [ -z "$SPRING_BOOT_VERSION" ] && SPRING_BOOT_VERSION=$(grep -A1 "spring-boot-starter-parent" "$pf" 2>/dev/null | grep -oE '<version>[^<]+' | sed 's/<version>//' | head -1 || true)
    KOTLIN_VERSION=$(grep -oE '<kotlin.version>[^<]+' "$pf" 2>/dev/null | sed 's/<kotlin.version>//' | head -1 || true)
    JDK_VERSION=$(grep -oE '<java.version>[^<]+' "$pf" 2>/dev/null | sed 's/<java.version>//' | head -1 || true)
    MODULES=$(grep -oE '<module>[^<]+' "$pf" 2>/dev/null | sed 's/<module>//' | tr '\n' ', ' | sed 's/,$//' || true)

    local test_libs="junit5"
    grep -qiE "strikt" "$pf" 2>/dev/null && test_libs+=", strikt"
    grep -qiE "kotest" "$pf" 2>/dev/null && test_libs+=", kotest"
    grep -qiE "assertj" "$pf" 2>/dev/null && test_libs+=", assertj"
    grep -qiE "mockk" "$pf" 2>/dev/null && test_libs+=", mockk"
    grep -qiE "mockito" "$pf" 2>/dev/null && test_libs+=", mockito"
    TEST_FRAMEWORKS="$test_libs"

    local detected_plugins=""
    grep -qiE "querydsl" "$pf" 2>/dev/null && detected_plugins+="querydsl, "
    grep -qiE "jooq" "$pf" 2>/dev/null && detected_plugins+="jooq, "
    grep -qiE "lombok" "$pf" 2>/dev/null && detected_plugins+="lombok, "
    grep -qiE "checkstyle" "$pf" 2>/dev/null && detected_plugins+="checkstyle, "
    grep -qiE "spotless" "$pf" 2>/dev/null && detected_plugins+="spotless, "
    grep -qiE "spotbugs" "$pf" 2>/dev/null && detected_plugins+="spotbugs, "
    grep -qiE "detekt" "$pf" 2>/dev/null && detected_plugins+="detekt, "
    grep -qiE "error.?prone|errorprone" "$pf" 2>/dev/null && detected_plugins+="error-prone, "
    grep -qiE "jacoco" "$pf" 2>/dev/null && detected_plugins+="jacoco, "
    PLUGINS="${detected_plugins%, }"

    grep -qiE "archunit" "$pf" 2>/dev/null && test_libs+=", archunit"
  fi
  return 0
}
