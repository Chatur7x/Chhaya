import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeysFile = rootProject.file("key.properties")
if (releaseKeysFile.exists()) releaseKeysFile.inputStream().use { releaseKeys.load(it) }
val allowDebugRelease = System.getenv("CHHAYA_ALLOW_DEBUG_SIGNING") == "true"
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (releaseRequested && !releaseKeysFile.exists() && !allowDebugRelease) {
    throw GradleException("Release signing requires android/key.properties. For a test artifact only, set CHHAYA_ALLOW_DEBUG_SIGNING=true.")
}

android {
    namespace = "com.chaaya.app.chaaya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chaaya.app.chaaya"
        manifestPlaceholders["appLabel"] = "Chhaya"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion // Required minimum SDK for WebRTC/local_auth
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (releaseKeysFile.exists()) {
        signingConfigs {
            create("release") {
                storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
                storePassword = releaseKeys.getProperty("storePassword")
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // CI debug APKs use ephemeral signing keys. Give them a separate
            // package so testers can install updates without deleting data
            // from an existing Chhaya installation.
            applicationIdSuffix = ".test"
            manifestPlaceholders["appLabel"] = "Chhaya Test"
        }
        release {
            if (releaseKeysFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugRelease) {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
