import org.gradle.api.JavaVersion
import org.gradle.api.file.Directory
import org.gradle.api.tasks.compile.JavaCompile
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
    // 統一 Java 編譯版本為 11，使用 release 參數避免屬性已終結
    tasks.withType<JavaCompile>().configureEach {
        // 設定編譯目標為 Java 11，避免模組自行設定不同版本
        options.release.set(11)
        // 不直接覆寫 sourceCompatibility，避免屬性已終結導致建置失敗
    }

    // 統一 Kotlin 編譯設定，確保所有模組皆使用 JVM 11
    tasks.withType<KotlinCompile>().configureEach {
        // 強制 Kotlin 使用 JVM 11，避免與 Java 版本不一致
        kotlinOptions {
            jvmTarget = "11"
        }
    }
}
