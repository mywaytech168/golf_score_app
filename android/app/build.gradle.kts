plugins {
    id("com.android.application")
    // ---------- 套用 Kotlin 外掛 ----------
    // 改用完整外掛識別名稱，確保沿用 settings.gradle.kts 中宣告的 2.0.21 版本
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------- 依賴解析區 ----------
// 強制所有 Kotlin 標準函式庫統一使用 2.0.21，避免部份三方套件拉入 2.2.0 版導致 metadata 不相容
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin" && requested.name.startsWith("kotlin-")) {
            useVersion("2.0.21")
            because("統一 Kotlin 標準函式庫版本，避免出現 Binary version 2.2.0 與編譯器不符的錯誤")
        }
    }
}

android {
    namespace = "com.example.golf_score_app"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.golf_score_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
          getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
