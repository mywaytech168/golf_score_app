import org.gradle.api.file.Directory

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

buildscript {
    extra["kotlin_version"] = "2.1.0"
    repositories {
        google()
        mavenCentral()
        maven(url = "https://jcenter.bintray.com/")
        maven(url = "https://github.com/Canardoux/flutter_sound/raw/master/bin/flutter_sound_core")
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.6.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
        classpath("com.google.gms:google-services:4.4.2")
    }
}

// ---------- 編譯設定說明 ----------
// 各子模組需自行設定 Java 與 Kotlin 版本，避免在此全域覆寫造成 sourceCompatibility 終結錯誤

