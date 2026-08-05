plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ani_mart"
    // image_cropper requires compiling against SDK 36 (backward compatible).
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Google Play rejects com.example.* package names. NOTE: after this
        // change, register a NEW Android app with this package name in the
        // Firebase console (project animart-5eb9b) and update the appId in
        // lib/firebase_options.dart, or push notifications will stop working.
        applicationId = "com.animart.app"

        // Android 10 (API 29) and above only. Also satisfies every plugin's
        // floor (passkeys_android needs >= 23, ua_client_hints >= 22).
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Enables support for large library sets
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Silences the "unchecked/unsafe operations" notes and "obsolete source/target
// value 8" warnings coming from third-party plugin Java sources
// (google_mlkit_*, passkeys_doctor, etc.) that we don't control —
// purely cosmetic, doesn't change behavior.
tasks.withType<JavaCompile> {
    options.compilerArgs.addAll(listOf("-Xlint:-options", "-nowarn"))
}

flutter {
    source = "../.."
}