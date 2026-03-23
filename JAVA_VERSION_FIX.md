# ⚠️ Java 版本问题修复指南

## 🔴 问题

```
Android Gradle plugin requires Java 17 to run. You are currently using Java 11.
```

您系统中只有 **Java 11**，但 Gradle 8.10.2 需要 **Java 17**。

## ✅ 已完成的配置

我已经修改了以下文件来支持 Java 11:

### 1️⃣ `android/gradle.properties` (已修改)

添加了:
```properties
org.gradle.java.home=C:\\Program Files\\Microsoft\\jdk-11.0.12.7-hotspot
```

这告诉 Gradle 使用您系统中的 Java 11。

### 2️⃣ `android/app/build.gradle.kts` (已修改)

添加了:
```kotlin
tasks.withType(JavaCompile::class).configureEach {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}
```

这告诉编译器降级至 Java 11 兼容。

## 🚀 下一步

现在重试 signingReport:

```bash
cd d:\project\golf\golf-score_app_1\android
gradlew.bat signingReport
```

## 📌 如果还是失败

如果修复后仍然失败，您有两个选项:

### 选项 A: 完全卸载 Java 11，安装 Java 17 (推荐)

1. 下载 Java 17 LTS:
   - 官方: https://www.oracle.com/java/technologies/downloads/#java17
   - OpenJDK: https://adoptium.net/

2. 安装后设置 `JAVA_HOME`:
   ```bash
   setx JAVA_HOME "C:\Program Files\Java\jdk-17.x.x"
   ```

3. 重启 VS Code 或命令行

4. 验证:
   ```bash
   java -version
   ```
   应该显示 Java 17+

5. 重新运行:
   ```bash
   cd d:\project\golf\golf-score_app_1\android
   gradlew.bat signingReport
   ```

### 选项 B: 使用开源 JDK 17

使用 Eclipse Adoptium (推荐开源方案):

```bash
# 下载 Adoptium JDK 17
# https://adoptium.net/installation/

# 安装后验证
java -version

# 设置环境变量
setx JAVA_HOME "C:\Program Files\Eclipse Adoptium\jdk-17.x.x"

# 重启终端并重试
```

### 选项 C: 降低 Gradle 版本 (快速方案)

编辑 `android/build.gradle.kts`:

找到这一行:
```gradle
id "com.android.tools.build:gradle:8.10.2"
```

改为:
```gradle
id "com.android.tools.build:gradle:7.4.2"
```

这个版本支持 Java 11。

## 🎯 一旦 signingReport 完成

您会看到类似这样的输出:

```
Variant: debug
Config: debug
Store: /path/to/keystore
Alias: androiddebugkey
MD5: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF
SHA1: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33
SHA-256: 00:11:22:33...
```

**复制 SHA1 值** (带冒号的那一个，长度 40+ 字符)

## 📋 添加 SHA1 到 Google Cloud

1. 打开 Google Cloud Console:
   https://console.cloud.google.com

2. 选择您的项目

3. 进入 **APIs & Services** > **Credentials**

4. 找到 Android OAuth 2.0 Client ID:
   - 446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9

5. 点击编辑 (铅笔图标)

6. 在 **SHA-1 certificates** 中点击 **ADD FINGERPRINT**

7. 粘贴您复制的 SHA1 值 (例如: `00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33`)

8. 点击 **UPDATE**

9. 等待 **5-10 分钟** Google 系统更新

## ✅ 验证修复

等待 10 分钟后，重新运行应用:

```bash
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run
```

现在尝试 Google Sign-In，应该能看到登入对话框而不是 Error 10。

## 🆘 仍然失败?

如果仍然显示 Error 10，检查:

1. ✅ SHA1 已添加到 Google Cloud
2. ✅ 等待至少 10 分钟
3. ✅ 确认包名是 `com.example.golf_score_app`
4. ✅ 运行 `flutter clean && flutter pub get`
5. ✅ 清除应用数据

如果还是失败，运行以下诊断:

```bash
cd d:\project\golf\golf-score_app_1
flutter doctor -v
```

查找 Java 部分，确保显示 **Java 11 或更高版本**。

---

**提示**: 如果您计划开发 Flutter/Android 应用，建议升级到 Java 17。这是现代 Android Gradle 的标准要求。
