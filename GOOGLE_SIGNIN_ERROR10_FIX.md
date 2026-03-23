# 🔧 Google Sign-In Android ApiException: 10 修复指南

## 📌 问题描述

```
❌ Google 登入平台錯誤: sign_in_failed - com.google.android.gms.common.api.ApiException: 10
```

**Error Code 10** 表示应用的签名信息与 Google Cloud 中注册的信息不匹配。

## 🎯 您的应用信息

| 项目 | 值 |
|-----|-----|
| Package Name | `com.example.golf_score_app` |
| Android Client ID | `446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com` |
| SHA-1 | `需要获取` ⬇️ |

## 🔑 步骤 1: 获取 Debug SHA-1 指纹

### Windows 用户:

打开命令行，在项目根目录运行:

```bash
cd android
gradlew.bat signingReport
```

### macOS/Linux 用户:

```bash
cd android
./gradlew signingReport
```

### 输出示例:

```
Variant: debug
Config: debug
Store: C:\Users\YourName\.android\keystore
Alias: AndroidDebugKey
MD5: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF
SHA1: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33
SHA-256: ...
```

**复制 SHA1 的值** (不要 MD5 或 SHA-256)

## 🌐 步骤 2: 在 Google Cloud 中添加 SHA-1

### 2.1 打开 Google Cloud Console

访问: https://console.cloud.google.com

### 2.2 选择您的项目

确保选择了正确的项目 (包含您的 Google Sign-In 配置)

### 2.3 进入 Credentials

导航到: **APIs & Services** → **Credentials**

### 2.4 找到 Android Client ID

查找类似这样的条目:
- Type: OAuth 2.0 Client ID
- Application type: Android

### 2.5 编辑 Client ID

1. 点击 Android Client ID 行
2. 在打开的详情页中，找到 **"SHA-1 certificates"** 部分
3. 点击 **"Add Certificate"** 或相似按钮

### 2.6 添加 SHA-1

1. 粘贴您从 `gradlew signingReport` 获得的 SHA-1 值
2. 点击 **Save** 或 **Update**

### 2.7 完成

Google Cloud 现在应该显示:

```
SHA-1 certificates:
- 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33
```

## 🔄 步骤 3: 重新构建应用

```bash
# 清理旧的构建
flutter clean

# 获取依赖
flutter pub get

# 重新构建 Android 应用
flutter run
```

## ✅ 验证步骤

完成上述步骤后，测试 Google Sign-In:

1. 打开应用
2. 点击 **"使用 Google 登入"** 按钮
3. 应该看到 Google 登入对话框
4. 选择 Google 账户
5. 如果成功，应该看到: `✅ Google 登入成功`

## ⚠️ 常见问题

### Q1: 我不知道如何找到 gradlew signingReport 的输出

**A:** 尝试以下命令:

```bash
cd android
gradlew.bat signingReport > output.txt
type output.txt
```

这会将输出保存到 `output.txt` 文件中。

### Q2: SHA-1 值很长，我担心复制错误

**A:** 
1. 运行 `gradlew signingReport`
2. 找到 SHA1 行
3. 选择整个 SHA1 值 (包括冒号)
4. 按 Ctrl+C 复制
5. 在 Google Cloud 中粘贴 (Ctrl+V)

### Q3: 我添加了 SHA-1，但仍然得到 Error 10

**A:** 尝试以下:

1. **等待 5-10 分钟** - Google Cloud 可能需要时间来应用更改
2. **清理应用缓存**:
   ```bash
   adb shell pm clear com.example.golf_score_app
   ```
3. **完全卸载应用** (如果已安装):
   ```bash
   adb uninstall com.example.golf_score_app
   ```
4. **重新运行应用**:
   ```bash
   flutter run
   ```

### Q4: 我有多个 SHA-1 值，应该添加哪一个？

**A:** 添加 **Debug** 的 SHA-1 值用于开发测试。输出中通常显示为:

```
Variant: debug      ← 这是 Debug
Config: debug
...
SHA1: XX:XX:XX... ← 添加这个
```

当应用发布到 Google Play Store 时，还需要添加 **Release** 的 SHA-1。

## 📞 快速检查清单

在联系支持前，确保您已检查:

- [ ] Package name 是否为 `com.example.golf_score_app`
- [ ] Android Client ID 是否正确配置在 `login_page.dart`
- [ ] SHA-1 已从 `gradlew signingReport` 获取
- [ ] SHA-1 已添加到 Google Cloud Console
- [ ] 已等待至少 5 分钟
- [ ] 已清理应用缓存
- [ ] 已运行 `flutter clean` 和 `flutter pub get`
- [ ] 已完全卸载旧版本应用

## 🆘 仍然无法工作？

如果完成上述所有步骤后仍然失败，请提供:

1. `gradlew signingReport` 的输出
2. Google Cloud Console 中 Android Client ID 的截图
3. `flutter run` 的完整输出日志
4. Package name 确认
