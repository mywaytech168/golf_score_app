# Google Sign-In 配置指南 (iOS 和 Android)

## 📋 当前状态
- **Android Client ID**: 446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com
- **iOS Client ID**: 需要获取
- **Web Client ID**: 需要获取

## 🔧 步骤 1: 获取所有必要的 Client IDs

### 1.1 访问 Google Cloud Console
1. 打开 [Google Cloud Console](https://console.cloud.google.com)
2. 选择您的项目（如果没有，请创建一个新项目）
3. 导航到 **APIs & Services** > **Credentials**

### 1.2 确认 OAuth 2.0 Client IDs
您应该能看到以下 Client IDs：
- **Android**: `446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com`
- **iOS**: `YOUR_IOS_CLIENT_ID` (需要创建或查找)
- **Web**: `YOUR_WEB_CLIENT_ID` (用于后端验证)

如果 iOS 或 Web Client ID 不存在，请按以下步骤创建：

#### 创建 iOS Client ID:
1. 点击 **Create Credentials** > **OAuth 2.0 Client ID**
2. 选择 **iOS**
3. 填入以下信息:
   - **App name**: Golf Score App
   - **Bundle ID**: com.example.golf_score_app (或您的实际 Bundle ID)
   - **Team ID**: 您的苹果开发者 Team ID
   - **App Store ID**: (可选)

#### 创建 Web Client ID:
1. 点击 **Create Credentials** > **OAuth 2.0 Client ID**
2. 选择 **Web application**
3. 填入授权重定向 URIs (如果有后端):
   ```
   https://yourdomain.com/auth/google/callback
   ```

## 🚀 步骤 2: 更新应用配置

### 2.1 更新 Dart 代码

编辑 `lib/pages/login_page.dart`:

```dart
// Android
googleSignIn = GoogleSignIn(
  clientId: '446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com',
  scopes: const ['email', 'profile'],
);

// iOS
googleSignIn = GoogleSignIn(
  clientId: 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com',
  scopes: const ['email', 'profile'],
);
```

### 2.2 配置 iOS

编辑 `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.example.golfScoreApp</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <!-- 格式: com.googleusercontent.apps.YOUR_IOS_CLIENT_ID -->
            <string>com.googleusercontent.apps.446697241300-YOUR_IOS_ID</string>
        </array>
    </dict>
</array>
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
```

### 2.3 配置 Android

编辑 `android/app/src/main/AndroidManifest.xml` (已完成):

```xml
<meta-data
    android:name="com.google.android.gms.version"
    android:value="@integer/google_play_services_version" />
```

## 🔐 步骤 3: 获取 SHA-1 指纹 (Android)

### 3.1 生成 Debug SHA-1
```bash
cd android
./gradlew signingReport
```

输出示例:
```
Variant: debug
Config: debug
Store: /Users/username/.android/keystore
Alias: AndroidDebugKey
MD5: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF
SHA1: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33
SHA-256: ...
```

### 3.2 添加 SHA-1 到 Google Cloud
1. 在 Google Cloud Console 中，找到 Android Client ID
2. 点击编辑
3. 添加您的 SHA-1 指纹 (支持多个)
4. 保存

## 📝 步骤 4: 后端验证配置

如果您有后端服务器，需要验证 Google idToken:

### Python 示例:
```python
from google.auth.transport import requests
from google.oauth2 import id_token

try:
    idinfo = id_token.verify_oauth2_token(
        id_token_str, 
        requests.Request(), 
        client_id='YOUR_WEB_CLIENT_ID'
    )
    # idinfo 现在包含用户信息
    email = idinfo['email']
    name = idinfo['name']
except ValueError:
    # Invalid token
    pass
```

### Node.js 示例:
```javascript
const {OAuth2Client} = require('google-auth-library');
const client = new OAuth2Client(CLIENT_ID);

async function verify(token) {
  const ticket = await client.verifyIdToken({
    idToken: token,
    audience: CLIENT_ID,
  });
  const payload = ticket.getPayload();
  return payload;
}
```

## 🧪 测试清单

- [ ] Android 应用可以成功打开 Google Sign-In 对话框
- [ ] iOS 应用可以成功打开 Google Sign-In 对话框
- [ ] 两个平台都能获取 idToken
- [ ] 后端可以成功验证 idToken
- [ ] 用户信息 (email, name, photo) 正确保存
- [ ] JWT token 成功返回给应用

## ⚠️ 常见问题

### Q: "sign_in_failed - API 异常: 10"
**A**: 这通常意味着:
1. SHA-1 指纹未添加到 Google Cloud
2. Package name 不匹配
3. Client ID 配置错误

**解决方案**:
- 运行 `gradlew signingReport` 获取 SHA-1
- 在 Google Cloud 中添加 SHA-1
- 重新构建应用

### Q: iOS 显示 "Safari 无法打开页面"
**A**: URL Scheme 配置可能有问题

**解决方案**:
- 确保 CFBundleURLSchemes 中的值与 Client ID 匹配
- 检查 Info.plist 格式

### Q: 后端无法验证 token
**A**: 可能使用了错误的 Client ID

**解决方案**:
- 后端应该使用 **Web Client ID** 来验证
- 确保您在验证时使用了正确的 CLIENT_ID 参数

## 📞 获取帮助

- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios)
- [Google Sign-In for Android](https://developers.google.com/identity/sign-in/android)
- [Google OAuth 2.0 文档](https://developers.google.com/identity/protocols/oauth2)
