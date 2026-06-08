plugins {
    id("com.android.application")
    // ---------- 套用 Kotlin 外掛 ----------
    // 改用完整外掛識別名稱，確保沿用 settings.gradle.kts 中宣告的 2.0.21 版本
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 👇 配置编译器以支持 Java 17 (系统当前版本)
tasks.withType(JavaCompile::class).configureEach {
    sourceCompatibility = JavaVersion.VERSION_17.toString()
    targetCompatibility = JavaVersion.VERSION_17.toString()
}

android {
    namespace = "com.aethertek.tekswing"
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
        applicationId = "com.aethertek.tekswing"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ✅ JNI：只打包用到的 ABI，避免 APK 增大
        // arm64-v8a  = 絕大多數現代 Android 裝置（有 NEON SIMD）
        // x86_64     = 模擬器
        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
    }

    // ✅ golf_native.so：YUV→NV12 + composite overlay 的 C 加速實作
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            storeFile = file("tekswing.jks")
            storePassword = System.getenv("STORE_PASSWORD") ?: ""
            keyAlias = "tekswing"
            keyPassword = System.getenv("KEY_PASSWORD") ?: ""
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
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

    // ✅ TFLite 模型不可被壓縮：AAPT 對壓縮資産無法用 openFd() 讀取
    androidResources {
        noCompress += listOf("tflite", "lite")
    }
}

flutter {
    source = "../.."
}

// ── 強制降版：避免部分 AndroidX 依賴要求 AGP 8.9.1+（目前環境使用 8.6.0）
// androidx.browser 1.9.0 / core 1.17.0 的 AAR metadata 有 minAndroidGradlePlugin=8.9.1
// 固定在這裡的版本不含該限制，功能上完全相容
configurations.all {
    resolutionStrategy {
        force("androidx.browser:browser:1.8.0")
        force("androidx.core:core:1.15.0")
        force("androidx.core:core-ktx:1.15.0")
    }
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

    // ✅ TFLite Android API（YOLOv8 球偵測，Kotlin 側推論）
    implementation("org.tensorflow:tensorflow-lite:2.16.1")

    // SAF DocumentFile（資料夾選擇寫檔）
    implementation("androidx.documentfile:documentfile:1.0.1")
}
