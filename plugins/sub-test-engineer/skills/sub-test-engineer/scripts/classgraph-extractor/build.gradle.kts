plugins {
    kotlin("jvm") version "1.9.25"
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "sub-test-engineer"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    implementation("io.github.classgraph:classgraph:4.8.174")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("org.jetbrains.kotlin:kotlin-stdlib")
}

kotlin {
    jvmToolchain(17)
}

tasks.shadowJar {
    archiveBaseName.set("classgraph-extractor")
    archiveClassifier.set("all")
    archiveVersion.set("")
    manifest {
        attributes("Main-Class" to "sub.test.engineer.TypeInfoExtractorKt")
    }
    mergeServiceFiles()
    minimize {
        exclude(dependency("io.github.classgraph:classgraph:.*"))
    }
}
