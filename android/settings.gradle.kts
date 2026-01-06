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

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    // 讀取 flutter sdk 路徑以加入 engine 本地 maven
    val flutterProps = java.util.Properties().apply {
        file("local.properties").inputStream().use { load(it) }
    }
    val flutterSdk: String? = flutterProps.getProperty("flutter.sdk")

    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        if (flutterSdk != null) {
            maven {
                // Flutter engine artifacts (jar only, no pom)
                url = uri("file://$flutterSdk/bin/cache/artifacts/engine")
                metadataSources {
                    artifact()
                }
                content {
                    includeGroup("io.flutter")
                }
            }
        }
        exclusiveContent {
            forRepository {
                maven { url = uri("https://maven.arthenica.com/public") }
            }
            filter {
                includeGroup("com.arthenica")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.6.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
