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

    // BouncyCastle's jars each carry the same licence and version notes.
    packaging {
        resources {
            excludes += setOf("META-INF/LICENSE.md", "META-INF/NOTICE.md", "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                "META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
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
            // BouncyCastle and JMRTD load their algorithms by name: keep them whole.
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
    // Reading document text on the phone: Google ML Kit with the model bundled
    // in the app, so it works offline and nothing is downloaded or sent.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // Scanning documents (edges found live, corners adjustable, several pages):
    // Google Play services, on the phone.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    // Unlock with a fingerprint or face (Android's Keystore + BiometricPrompt).
    implementation("androidx.biometric:biometric:1.1.0")
    // Reading e-passport / e-ID chips over NFC (ICAO 9303): JMRTD, with the
    // full BouncyCastle crypto it needs for BAC and PACE.
    implementation("org.jmrtd:jmrtd:0.8.9")
    implementation("net.sf.scuba:scuba-sc-android:0.0.27")
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
}
