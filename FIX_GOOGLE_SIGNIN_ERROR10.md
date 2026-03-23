# 🚀 修复 Google Sign-In Error 10 (已获取您的 SHA-1!)

## ❌ 问题

```
Google 登入平台錯誤: sign_in_failed - 
com.google.android.gms.common.api.ApiException: 10
```

**原因**: Android 调试 SHA-1 指纹未在 Google Cloud 注册

---

## ✅ 步骤 1️⃣: 您的 SHA-1 指纹 (已获取)

您的 Debug SHA-1:
```
15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

**复制上面的值** (包括冒号) ← 关键信息!

---

## 步骤 2️⃣: 添加到 Google Cloud Console (3 分钟)

### 2a. 打开 Google Cloud Console
```
https://console.cloud.google.com
```

### 2b. 找到您的项目
- 顶部下拉菜单 → 选择您的项目

### 2c. 进入凭据配置
```
APIs & Services → Credentials
```

### 2d. 编辑 Android Client ID
- 找到: `446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com`
- 点击它 (蓝色链接)
- 点击 **编辑** (铅笔图标)

### 2e. 添加 SHA-1
1. 向下滚动找到 **SHA-1 certificates**
2. 点击 **ADD FINGERPRINT**
3. 粘贴您从步骤 1 复制的 SHA-1 值
4. 点击 **UPDATE** 保存

---

## 步骤 3️⃣: 等待并测试 (10 分钟)

### 等待 5-10 分钟
Google 需要时间更新记录。

### 重新构建应用

```bash
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run -d 24094RAD4C
```

### 测试 Google Sign-In
1. 在应用中点击 **"使用 Google 登入"**
2. 应该看到 Google 登入对话框 (不是错误!)
3. 选择账户并登入

---

## 📋 检查清单

- [ ] 运行了 `gradlew.bat signingReport`?
- [ ] 找到并复制了 SHA-1 值?
- [ ] 登入了 Google Cloud Console?
- [ ] 找到了 Android Client ID?
- [ ] 添加了 SHA-1 到 Google Cloud?
- [ ] 等待了 5-10 分钟?
- [ ] 重新构建了应用?

---

## ❌ 如果仍然失败

### 诊断步骤

1. 验证 SHA-1 值正确:
   ```bash
   cd d:\project\golf\golf-score_app_1\android
   gradlew.bat signingReport | find "SHA1"
   ```

2. 验证 Google Cloud 中确实添加了:
   - 打开 Google Cloud Console
   - APIs & Services → Credentials
   - 编辑 Android Client ID
   - 检查 SHA-1 certificates 是否有您的值

3. 清除应用数据:
   - 手机上: Settings → Apps → Golf Score App → Storage → Clear Data
   - 或运行: `adb shell pm clear com.example.golf_score_app`

4. 重新安装应用:
   ```bash
   flutter clean
   flutter run -d 24094RAD4C
   ```

---

## 🔍 什么是 Error 10?

Error 10 = `DEVELOPER_ERROR`

**含义**: 应用的签名不匹配 Google Cloud 中的记录。

**解决**: 添加正确的 SHA-1 指纹到 Google Cloud。

---

## 💡 重要信息

- **包名**: `com.example.golf_score_app`
- **Client ID**: `446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com`
- **Keystore**: Android 默认调试密钥库 (`~/.android/debug.keystore`)

---

## ⏱️ 预计耗时

| 任务 | 耗时 |
|------|------|
| 获取 SHA-1 | 1 分钟 |
| 添加到 Google Cloud | 3 分钟 |
| 等待 Google 更新 | 5-10 分钟 |
| 重新构建和测试 | 3 分钟 |
| **总计** | **15 分钟** |

---

**现在就开始!** 👉 打开终端运行 `gradlew.bat signingReport`
