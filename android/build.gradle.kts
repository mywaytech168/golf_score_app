import org.gradle.api.JavaVersion
import org.gradle.api.file.Directory
import com.android.build.gradle.BaseExtension
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    // ---------- Java 編譯設定 ----------
    // 針對所有套用 Android Plugin 的模組統一 Java 版本為 11
    plugins.withId("com.android.application") {
        extensions.configure<BaseExtension>("android") {
            // 明確指定來源與目標版本，避免預設 1.8 造成與 Kotlin 不一致
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<BaseExtension>("android") {
            // Library 模組同樣使用 Java 11，確保整體環境一致
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        }
    }

    // ---------- Kotlin 編譯設定 ----------
    // 統一 Kotlin 編譯設定，確保所有模組皆使用 JVM 11
    tasks.withType<KotlinCompile>().configureEach {
        // 強制 Kotlin 使用 JVM 11，避免與 Java 版本不一致
        kotlinOptions {
            jvmTarget = "11"
        }
    }
}
