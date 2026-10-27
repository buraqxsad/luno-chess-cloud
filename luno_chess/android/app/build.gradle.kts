import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file(
    providers.gradleProperty("lunoSigningPropertiesFile").getOrElse("key.properties"),
)
val keystoreProperties = Properties()
var signingPropertiesReadable = true
if (keystorePropertiesFile.exists()) {
    try {
        FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    } catch (_: Exception) {
        signingPropertiesReadable = false
    }
}

val releaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }
val signingReady = signingPropertiesReadable && keystorePropertiesFile.exists() &&
    releaseSigningKeys.all { !keystoreProperties.getProperty(it).isNullOrBlank() } &&
    releaseStoreFile?.isFile == true
val validateLunoReleaseSigning = tasks.register("validateLunoReleaseSigning") {
    doLast {
        check(signingReady) {
            "Luno release signing unavailable. Provide a valid local key.properties " +
                "and upload keystore. Debug builds do not require release credentials."
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateLunoReleaseSigning)
}

android {
    namespace = "com.luno.chess"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.luno.chess"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingReady) {
            create("releaseUpload") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (signingReady) signingConfig = signingConfigs.getByName("releaseUpload")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
