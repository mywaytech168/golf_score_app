pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    // ---------- Kotlin 版本說明 ----------
    // 受限於部分 Flutter 套件仍使用較舊的 Kotlin 編譯器，我們改回 2.0.21 並搭配對應版本的標準函式庫
    // 如此能與 package_info_plus 等套件維持相容，避免 metadata 版本衝突
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}

include(":app")
