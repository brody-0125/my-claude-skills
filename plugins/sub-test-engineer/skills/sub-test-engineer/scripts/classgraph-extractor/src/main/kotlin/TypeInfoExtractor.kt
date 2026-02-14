package sub.test.engineer

import com.google.gson.GsonBuilder
import io.github.classgraph.ClassGraph
import io.github.classgraph.ClassInfo
import io.github.classgraph.MethodInfo

/**
 * Layer 2: ClassGraph bytecode enrichment for sub-test-engineer.
 *
 * Extracts type information that ast-grep (Layer 1a) cannot provide:
 * - Cross-file sealed class subtype enumeration
 * - Resolved generic type parameters
 * - Complete interface → implementation mappings
 * - Runtime annotation metadata
 */

data class ExtractedClass(
    val name: String,
    val simpleName: String,
    val kind: String,                  // enum, sealed, data, abstract, interface, class
    val superclass: String?,
    val interfaces: List<String>,
    val subtypes: List<String>,        // sealed class subtypes or interface implementations
    val enumConstants: List<String>,
    val constructorParams: List<ParamInfo>,
    val methods: List<MethodSummary>,
    val annotations: List<String>,
    val resolvedGenerics: Map<String, String>  // type param name → resolved type
)

data class ParamInfo(
    val name: String?,                 // null if not preserved in bytecode
    val type: String,
    val nullable: Boolean,
    val annotations: List<String>
)

data class MethodSummary(
    val name: String,
    val params: List<ParamInfo>,
    val returnType: String,
    val annotations: List<String>
)

fun main(args: Array<String>) {
    val config = parseArgs(args)

    val results = ClassGraph()
        .overrideClasspath(config.classpath)
        .acceptPackages(config.packagePattern.removeSuffix(".**"))
        .enableAllInfo()
        .scan()
        .use { scanResult ->
            scanResult.allClasses
                .filter { !it.name.contains("\$\$") }  // exclude generated proxies
                .filter { !it.name.endsWith("\$Companion") }  // exclude companion objects
                .map { classInfo -> extractClass(classInfo, scanResult.allClasses) }
        }

    val gson = GsonBuilder().setPrettyPrinting().create()
    println(gson.toJson(results))
}

private fun extractClass(ci: ClassInfo, allClasses: io.github.classgraph.ClassInfoList): ExtractedClass {
    return ExtractedClass(
        name = ci.name,
        simpleName = ci.simpleName,
        kind = classifyKind(ci),
        superclass = ci.superclass?.name?.takeIf { it != "java.lang.Object" && it != "kotlin.Any" },
        interfaces = ci.interfaces.map { it.name },
        subtypes = findSubtypes(ci, allClasses),
        enumConstants = if (ci.isEnum) {
            ci.declaredFieldInfo
                .filter { it.isPublic && it.isStatic && it.isFinal }
                .filter { it.typeDescriptor.toString() == ci.name }
                .map { it.name }
        } else emptyList(),
        constructorParams = extractConstructorParams(ci),
        methods = extractMethods(ci),
        annotations = ci.annotationInfo.map { it.name },
        resolvedGenerics = extractResolvedGenerics(ci)
    )
}

private fun classifyKind(ci: ClassInfo): String = when {
    ci.isEnum -> "enum"
    ci.isAnnotation -> "annotation"
    ci.isInterface -> "interface"
    isSealed(ci) -> "sealed"
    isDataClass(ci) -> "data"
    ci.isAbstract -> "abstract"
    else -> "class"
}

private fun isSealed(ci: ClassInfo): Boolean {
    // Primary: JVM sealed class detection (works for both Java 17+ and Kotlin 1.5+)
    // Kotlin sealed classes compile with PermittedSubclasses bytecode attribute
    try {
        if (ci.loadClass().isSealed) return true
    } catch (_: Exception) {
        // loadClass() may fail if class has missing dependencies — use heuristic
    }

    // Fallback heuristic for Kotlin sealed classes when loadClass() fails:
    // abstract + @Metadata + only private constructors + has subclasses in scan
    return ci.hasAnnotation("kotlin.Metadata") &&
        ci.isAbstract &&
        ci.declaredConstructorInfo.let { ctors ->
            ctors.isNotEmpty() && ctors.none { it.isPublic }
        } &&
        ci.subclasses.isNotEmpty()
}

private fun isDataClass(ci: ClassInfo): Boolean {
    // Kotlin data classes have copy(), componentN(), and @Metadata
    return ci.hasAnnotation("kotlin.Metadata") &&
        ci.declaredMethodInfo.any { it.name == "copy" } &&
        ci.declaredMethodInfo.any { it.name == "component1" }
}

private fun findSubtypes(ci: ClassInfo, allClasses: io.github.classgraph.ClassInfoList): List<String> {
    return when {
        ci.isInterface -> allClasses
            .filter { other -> other.interfaces.any { it.name == ci.name } }
            .map { it.name }
        isSealed(ci) || ci.isAbstract -> allClasses
            .filter { other -> other.superclass?.name == ci.name }
            .map { it.name }
        else -> emptyList()
    }
}

private fun extractConstructorParams(ci: ClassInfo): List<ParamInfo> {
    val constructors = ci.declaredConstructorInfo
    if (constructors.isEmpty()) return emptyList()

    // Use the primary constructor (longest parameter list for Kotlin, or first for Java)
    val primary = constructors.maxByOrNull { it.parameterInfo.size } ?: return emptyList()

    return primary.parameterInfo.map { param ->
        ParamInfo(
            name = param.name,  // may be null if not compiled with -parameters
            type = param.typeDescriptor.toString(),
            nullable = param.hasAnnotation("org.jetbrains.annotations.Nullable") ||
                param.hasAnnotation("javax.annotation.Nullable") ||
                param.hasAnnotation("jakarta.annotation.Nullable"),
            annotations = param.annotationInfo.map { it.name }
        )
    }
}

private fun extractMethods(ci: ClassInfo): List<MethodSummary> {
    return ci.declaredMethodInfo
        .filter { it.isPublic || it.name.startsWith("get") || it.name.startsWith("set") }
        .filter { !it.isSynthetic }
        .filter { it.name != "copy" && !it.name.startsWith("component") }
        .filter { it.name != "toString" && it.name != "hashCode" && it.name != "equals" }
        .map { method ->
            MethodSummary(
                name = method.name,
                params = method.parameterInfo.map { param ->
                    ParamInfo(
                        name = param.name,
                        type = param.typeDescriptor.toString(),
                        nullable = param.hasAnnotation("org.jetbrains.annotations.Nullable"),
                        annotations = param.annotationInfo.map { it.name }
                    )
                },
                returnType = method.typeDescriptor.resultType.toString(),
                annotations = method.annotationInfo.map { it.name }
            )
        }
}

private fun extractResolvedGenerics(ci: ClassInfo): Map<String, String> {
    val result = mutableMapOf<String, String>()
    // Extract resolved generics from superclass type signature
    val superSig = ci.typeSignature ?: return result
    superSig.superinterfaceSignatures.forEach { sig ->
        sig.typeArguments?.forEachIndexed { i, typeArg ->
            result["${sig.fullyQualifiedClassName}.T$i"] = typeArg.toString()
        }
    }
    superSig.superclassSignature?.typeArguments?.forEachIndexed { i, typeArg ->
        result["super.T$i"] = typeArg.toString()
    }
    return result
}

// --- CLI argument parsing ---
data class Config(
    val classpath: String,
    val packagePattern: String,
    val format: String
)

private fun parseArgs(args: Array<String>): Config {
    var classpath = ""
    var pattern = ""
    var format = "json"

    var i = 0
    while (i < args.size) {
        when (args[i]) {
            "--classpath" -> { classpath = args.getOrElse(i + 1) { "" }; i += 2 }
            "--pattern" -> { pattern = args.getOrElse(i + 1) { "" }; i += 2 }
            "--format" -> { format = args.getOrElse(i + 1) { "json" }; i += 2 }
            else -> i++
        }
    }

    require(classpath.isNotEmpty()) { "Missing --classpath argument" }
    require(pattern.isNotEmpty()) { "Missing --pattern argument" }

    return Config(classpath, pattern, format)
}
