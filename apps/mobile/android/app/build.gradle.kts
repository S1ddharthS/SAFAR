import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is supplied through the environment (preferred) or a
// gitignored android/key.properties. There is no debug-key fallback: a release
// build without configured signing fails instead of shipping a debug signature.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun signingValue(environment: String, property: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("SAFAR_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("SAFAR_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("SAFAR_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("SAFAR_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it != null }

android {
    namespace = "app.safar.safar_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.safar.safar_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any {
        it.name == "assembleRelease" ||
            it.name == "bundleRelease" ||
            it.name == "packageRelease" ||
            it.name == "packageReleaseBundle"
    }
    if (wantsRelease && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Set SAFAR_KEYSTORE_PATH, " +
                "SAFAR_KEYSTORE_PASSWORD, SAFAR_KEY_ALIAS and SAFAR_KEY_PASSWORD " +
                "(or android/key.properties). SAFAR never signs releases with the " +
                "debug key.",
        )
    }
}

flutter {
    source = "../.."
}
