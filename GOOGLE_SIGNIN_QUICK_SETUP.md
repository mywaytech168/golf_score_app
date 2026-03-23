# Google Sign-In 快速配置清单

## ✅ 已完成的配置

- ✅ `lib/pages/login_page.dart` - 支持 iOS/Android 平台特定 Client ID
- ✅ `ios/Runner/Info.plist` - iOS URL Schemes 和 Client ID 配置
- ✅ `android/app/src/main/AndroidManifest.xml` - Android 配置
- ✅ 创建了配置指南文档

## 📋 您需要完成的步骤

### 步骤 1: 获取 iOS Client ID

1. 打开 https://console.cloud.google.com
2. 进入您的项目
3. 点击 APIs & Services > Credentials
4. 找到或创建 iOS Client ID
5. 复制 iOS Client ID

### 步骤 2: 更新 Dart 代码

编辑 `lib/pages/login_page.dart` 第 210 行:

```dart
// iOS
googleSignIn = GoogleSignIn(
  clientId: 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com',
  // 将 YOUR_IOS_CLIENT_ID 替换为您的实际 ID
);
```

### 步骤 3: 更新 iOS 配置

编辑 `ios/Runner/Info.plist`:

搜索并替换以下内容:

```xml
<string>com.googleusercontent.apps.446697241300</string>
<!-- 替换为: -->
<string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>

<string>446697241300-your-ios-client-id.apps.googleusercontent.com</string>
<!-- 替换为: -->
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
```

### 步骤 4: Android 配置 (需要 SHA-1)

运行以下命令获取 Debug SHA-1:

```bash
cd android
./gradlew signingReport
```

在输出中找到 SHA1 值，然后:

1. 打开 Google Cloud Console
2. 找到 Android Client ID
3. 点击编辑
4. 在 "SHA-1 certificates" 中添加您的 SHA-1
5. 保存

### 步骤 5: 测试

```bash
flutter clean
flutter pub get
flutter run
```

## 🔑 您已有的 IDs

| 平台 | Client ID | 状态 |
|------|-----------|------|
| Android | 446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com | ✅ 已配置 |
| iOS | `需要获取` | ⏳ 待配置 |
| Web | `需要获取` | ⏳ 可选 |

## 🔗 文档链接

- [完整配置指南](./GOOGLE_SIGNIN_SETUP.md)
- [Google Sign-In iOS 文档](https://developers.google.com/identity/sign-in/ios)
- [Google Sign-In Android 文档](https://developers.google.com/identity/sign-in/android)

## 💡 提示

- iOS 和 Android 需要**不同的** Client IDs
- 每个 Client ID 对应一个平台/应用配置
- Android 需要 SHA-1 指纹才能工作
- Web Client ID 用于后端验证 (可选)
