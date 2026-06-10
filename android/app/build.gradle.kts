import java.util.Properties

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
    namespace = "com.aethertek.orvia"
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
        applicationId = "com.aethertek.orvia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ABI 由 flutter CLI --target-platform 控制，不在此設定
    }

    // ✅ golf_native.so：YUV→NV12 + composite overlay 的 C 加速實作
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // ABI 由 flutter build apk --target-platform 控制，不在 Gradle 設定
    // （splits.abi 與 Flutter Plugin 自動設定的 ndk.abiFilters 互斥，會 build error）

    buildFeatures {
        buildConfig = true
    }

    // 讀取 android/key.properties（不進 git，本機存放密碼）
    val keyPropertiesFile = rootProject.file("key.properties")
    val keyProperties = Properties().also { props: Properties ->
        if (keyPropertiesFile.exists()) props.load(keyPropertiesFile.inputStream())
    }

    // 簽章密碼缺失時不可用空字串靜默簽出壞檔：release build 直接報錯
    val storePwd = keyProperties.getProperty("storePassword") ?: System.getenv("STORE_PASSWORD")
    val keyPwd   = keyProperties.getProperty("keyPassword")   ?: System.getenv("KEY_PASSWORD")
    val hasSigningCreds = !storePwd.isNullOrBlank() && !keyPwd.isNullOrBlank()

    signingConfigs {
        create("release") {
            storeFile = file(keyProperties.getProperty("storeFile") ?: "orvia.jks")
            storePassword = storePwd ?: ""
            keyAlias = keyProperties.getProperty("keyAlias") ?: "orvia"
            keyPassword = keyPwd ?: ""
        }
    }

    if (!hasSigningCreds) {
        gradle.taskGraph.whenReady {
            if (allTasks.any { it.name.contains("Release") }) {
                throw GradleException(
                    "缺少簽章密碼：請建立 android/key.properties 或設定 STORE_PASSWORD / KEY_PASSWORD 環境變數")
            }
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

    // ✅ 模型檔不可被壓縮：AAPT 對壓縮資産無法用 openFd() 讀取
    androidResources {
        noCompress += listOf("tflite", "lite", "task")
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
    // ---------- 圖片方向解析 ----------
    implementation("androidx.exifinterface:exifinterface:1.3.7")

    // ✅ MediaPipe Tasks Vision（Camera2 即時 Pose Landmarker）
    implementation("com.google.mediapipe:tasks-vision:0.10.14")

    // ✅ TFLite Android API（YOLOv8 球偵測）
    implementation("org.tensorflow:tensorflow-lite:2.16.1")

    // SAF DocumentFile
    implementation("androidx.documentfile:documentfile:1.0.1")
}
