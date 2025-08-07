import org.gradle.api.tasks.compile.JavaCompile
import org.gradle.api.JavaVersion

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
    // 統一 Kotlin 與 Java 的編譯目標版本為 11，避免模組間版本不一致
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        // 強制 Kotlin 使用 JVM 11
        kotlinOptions {
            jvmTarget = "11"
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        // 統一 Java 編譯版本為 11
        sourceCompatibility = JavaVersion.VERSION_11.toString()
        targetCompatibility = JavaVersion.VERSION_11.toString()
    }
}
