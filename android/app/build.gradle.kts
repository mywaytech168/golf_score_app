plugins {
    id("com.android.application")
    // ---------- 套用 Kotlin 外掛 ----------
    // 改用完整外掛識別名稱，確保沿用 settings.gradle.kts 中宣告的 2.0.21 版本
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services plugin for Firebase and Google Sign-In
    id("com.google.gms.google-services")
}

// 👇 配置编译器以支持 Java 17 (系统当前版本)
tasks.withType(JavaCompile::class).configureEach {
    sourceCompatibility = JavaVersion.VERSION_17.toString()
    targetCompatibility = JavaVersion.VERSION_17.toString()
}

android {
    namespace = "com.example.golf_score_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    repositories {
        google()
        mavenCentral()
        maven(url = "https://jcenter.bintray.com/")
        maven(url = "https://github.com/Canardoux/flutter_sound/raw/master/bin/flutter_sound_core")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.golf_score_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 34
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

    // 🔧 Fix native library merging file system error
    packaging {
        exclude("lib/*/libVkLayer_*.so")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Media3 Transformer removed — VideoTrimmer now uses MediaExtractor+MediaMuxer directly
    // ---------- 圖片方向解析 ----------
    // 透過 ExifInterface 讀取頭像 EXIF 資訊，以修正相機拍攝的旋轉方向
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    
    // ✅ Google ML Kit Pose Detection
    // 版本需與 Flutter plugin google_mlkit_pose_detection:^0.12.0 的傳遞依賴一致（beta5）
    // 使用 beta1 會導致 mediapipe-internal 版本衝突 → JNI NoSuchFieldError
    implementation("com.google.mlkit:pose-detection:18.0.0-beta5")
    implementation("com.google.mlkit:vision-common:17.3.0")
}
