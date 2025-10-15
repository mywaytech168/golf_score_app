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
    // 套件像是 package_info_plus 依賴 Kotlin 2.x 標準函式庫，若仍使用 1.8.x 會觸發 metadata 不相容錯誤
    // 因此統一升級至 2.0.21 版本，確保編譯時 Kotlin 編譯器與函式庫版本一致
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}

include(":app")
