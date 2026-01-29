// android/app/build.gradle.kts

// 1. 冒頭にインポート文を追加
import java.util.Properties

// 2. key.properties の読み込み処理を修正
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties() // インポートしたので直接書けます
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.pure_tube_cast"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    signingConfigs {
        create("release") {
            // 安全のため、ファイルが存在しない場合のフォールバックを考慮
            keyAlias = keystoreProperties["keyAlias"] as? String ?: ""
            keyPassword = keystoreProperties["keyPassword"] as? String ?: ""
            storeFile = file(keystoreProperties["storeFile"] as? String ?: "dummy.jks")
            storePassword = keystoreProperties["storePassword"] as? String ?: ""
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
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
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}