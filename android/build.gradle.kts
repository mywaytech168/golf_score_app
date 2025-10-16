import com.android.build.gradle.LibraryExtension
import org.gradle.api.Project
import org.gradle.api.file.Directory

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
    // 使用 Action 包裝 afterEvaluate，避免 Kotlin DSL 與 Groovy 間型別推斷不一致
    afterEvaluate(org.gradle.api.Action { subproject ->
        // 僅針對 sign_in_with_apple 套件補齊 namespace，避免影響其他模組
        if (subproject.name == "sign_in_with_apple") {
            val androidExtension = subproject.extensions.findByName("android") as? LibraryExtension
            // 需確認為 LibraryExtension 後才能設定 namespace，確保型別安全
            androidExtension?.namespace = "com.aboutyou.dart_packages.sign_in_with_apple"
        }
    })
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// ---------- 編譯設定說明 ----------
// 各子模組需自行設定 Java 與 Kotlin 版本，避免在此全域覆寫造成 sourceCompatibility 終結錯誤

