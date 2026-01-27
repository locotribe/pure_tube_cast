plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.pure_tube_cast"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    // Java 17 を app モジュールだけに適用
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Kotlin 17
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.pure_tube_cast"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Kotlin の JVM Toolchain（Android 推奨）
kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}
