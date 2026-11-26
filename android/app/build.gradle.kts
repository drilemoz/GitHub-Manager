import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

fun nonBlank(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

val officialApplicationId = "br.com.githubmanager.app"
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val hasReleaseSigning =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { nonBlank(keystoreProperties.getProperty(it)) != null }

android {
    namespace = "br.com.githubmanager.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = officialApplicationId
        multiDexEnabled = true
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // Sem Secrets, assina com a chave debug para gerar um APK de teste instalável.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.17.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

tasks.register("validateOfficialSigning") {
    group = "verification"
    description = "Bloqueia APK oficial sem a assinatura definitiva do novo GitHub Manager."
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException("Assinatura oficial não configurada. Cadastre KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS e KEY_PASSWORD.")
        }
        val pubspec = rootProject.file("../pubspec.yaml")
        val versionLine = pubspec.readLines().firstOrNull { it.trim().startsWith("version:") }
            ?: throw GradleException("version ausente no pubspec.yaml.")
        val currentCode = versionLine.substringAfter('+', "").trim().toIntOrNull()
            ?: throw GradleException("versionCode inválido no pubspec.yaml: $versionLine")
        if (currentCode <= 0) {
            throw GradleException("versionCode oficial precisa ser positivo.")
        }
    }
}
