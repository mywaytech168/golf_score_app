import com.android.build.gradle.LibraryExtension
import org.gradle.api.file.Directory
import org.gradle.kotlin.dsl.configure
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// ---------- 子模組命名空間修正 ----------
// 為避免第三方套件未設 namespace 造成 AGP 8 編譯失敗，在此補上必要設定
subprojects {
    // 僅針對 sign_in_with_apple 套件處理 namespace，避免誤動其他模組
    if (name == "sign_in_with_apple") {
        // ---------- 生命週期 ----------
        // 透過 plugins.withId 確保在 Android Library Plugin 載入後才設定 namespace，防止存取尚未初始化的擴充
        plugins.withId("com.android.library") {
            // ---------- 方法區 ----------
            // 使用 extensions.configure 取得 LibraryExtension，設定 namespace 以符合 AGP 8 要求
            extensions.configure<LibraryExtension>("android") {
                // 這裡直接設定套件的 namespace，確保 build.gradle 與 AndroidManifest 保持一致
                namespace = "com.aboutyou.dart_packages.sign_in_with_apple"
            }
        }
        // ---------- 編譯相容設定 ----------
        // Kotlin 預設的 JVM 目標版本與模組內 Java 設定不同步會造成編譯錯誤，統一調整為 1.8 以維持一致性
        tasks.withType<KotlinCompile>().configureEach {
            kotlinOptions {
                jvmTarget = "1.8"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// ---------- 編譯設定說明 ----------
// 各子模組需自行設定 Java 與 Kotlin 版本，避免在此全域覆寫造成 sourceCompatibility 終結錯誤

