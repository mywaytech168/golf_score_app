plugins {
    id("com.android.application")
    // ---------- 套用 Kotlin 外掛 ----------
    // 改用完整外掛識別名稱，確保沿用 settings.gradle.kts 中宣告的 2.0.21 版本
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
        minSdk = 26
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

dependencies {
    // ---------- 影片覆蓋處理所需的 Media3 元件 ----------
    // 維持 1.4.1 版本以取得最新的覆蓋穩定性修正與效果 API，確保轉檔結果可被播放器解析
    implementation("androidx.media3:media3-transformer:1.4.1")
    implementation("androidx.media3:media3-effect:1.4.1")
    implementation("androidx.media3:media3-extractor:1.4.1")
    implementation("androidx.media3:media3-common:1.4.1")
    // ---------- 圖片方向解析 ----------
    // 透過 ExifInterface 讀取頭像 EXIF 資訊，以修正相機拍攝的旋轉方向
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
