import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.myvault.myvault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.myvault.myvault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The release key lives outside the repo (tools/make_release_keys.py). Android
    // only accepts updates signed with the same key, so every release must use it.
    // Without it (someone else's machine) the build falls back to the debug key.
    val releaseProps = File(System.getProperty("user.home"), ".myvault-release/key.properties")
    signingConfigs {
        if (releaseProps.exists()) {
            val p = Properties().apply { releaseProps.inputStream().use { load(it) } }
            create("release") {
                storeFile = File(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
            }
        }
    }

    // "direct": GitHub releases, which update themselves (signed with MyVault's key).
    // "play": Google Play, which does the updates, so the updater is left out.
    flavorDimensions += "channel"
    productFlavors {
        create("direct") { dimension = "channel" }
        create("play") { dimension = "channel" }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // Tesseract's native code calls back into its Java classes by name.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    implementation("androidx.core:core:1.13.1")   // FileProvider, for installing updates
    // Reading document text on the phone: Tesseract (open source, Apache 2.0), with
    // its English and Arabic models in assets/tessdata. Offline, and no Google
    // services: nothing about you or the app is sent anywhere.
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.8.0")
    // Unlock with a fingerprint or face (Android's Keystore + BiometricPrompt).
    implementation("androidx.biometric:biometric:1.1.0")
}
