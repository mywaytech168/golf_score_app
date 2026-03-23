# 🚀 Google Sign-In Error 10 快速修复 (临时方案)

## 立即可做的事情

如果您急于继续开发，可以暂时禁用 Google Sign-In 并依赖访客登入或账户密码登入：

### 选项 1: 完全禁用 Google Sign-In (快速方案)

编辑 `lib/pages/login_page.dart`，找到 `_handleGoogleLogin` 方法，替换为:

```dart
Future<void> _handleGoogleLogin() async {
  if (_isGoogleSigningIn) {
    return;
  }

  setState(() {
    _isGoogleSigningIn = true;
  });

  try {
    // 临时禁用 Google Sign-In，显示提示信息
    _showLoginResultSnackBar(
      '🔧 Google Sign-In 正在配置中。\n'
      '请使用以下方式登入:\n'
      '• 访客登入 (推荐)\n'
      '• 账户名和密码',
      isError: false,
    );
  } finally {
    if (mounted) {
      setState(() {
        _isGoogleSigningIn = false;
      });
    }
  }
}
```

这样用户仍可通过访客登入或账户密码登入，而 Google Sign-In 可在后台配置。

### 选项 2: 显示调试信息 (用于诊断)

如果您想看到详细的错误信息，替换为:

```dart
Future<void> _handleGoogleLogin() async {
  if (_isGoogleSigningIn) {
    return;
  }

  setState(() {
    _isGoogleSigningIn = true;
  });

  try {
    // 显示调试信息
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Sign-In 配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('需要完成以下步骤:'),
            const SizedBox(height: 12),
            const Text('1. 打开 Google Cloud Console'),
            const Text('2. 找到 Android Client ID'),
            const Text('3. 获取 Debug SHA-1 (运行: gradlew signingReport)'),
            const Text('4. 将 SHA-1 添加到 Google Cloud'),
            const Text('5. 等待 5-10 分钟'),
            const Text('6. 重新运行应用'),
            const SizedBox(height: 12),
            const Text(
              '您的应用信息:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('Package: com.example.golf_score_app'),
            const Text('Platform.isAndroid: ${Platform.isAndroid}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isGoogleSigningIn = false;
      });
    }
  }
}
```

## 📋 同时进行 SHA-1 配置

在应用正常工作的同时，按以下步骤完成 Google Sign-In 配置:

### 第一步: 获取 SHA-1 (即刻)

在命令行中运行:

```bash
cd d:\project\golf\golf-score_app_1\android
gradlew.bat signingReport > sha1.txt
type sha1.txt
```

找到类似这样的行:

```
SHA1: 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33
```

### 第二步: 添加到 Google Cloud (5 分钟)

1. 打开 https://console.cloud.google.com
2. 进入您的项目
3. 点击 APIs & Services > Credentials
4. 找到 Android Client ID: `446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9`
5. 点击编辑
6. 在 SHA-1 certificates 中添加上面复制的 SHA-1
7. 保存

### 第三步: 等待并测试 (5-10 分钟)

```bash
flutter clean
flutter pub get
flutter run
```

## 🎯 恢复 Google Sign-In

完成 SHA-1 配置后，恢复 `_handleGoogleLogin` 方法到原始代码:

```dart
Future<void> _handleGoogleLogin() async {
  if (_isGoogleSigningIn) {
    return;
  }

  setState(() {
    _isGoogleSigningIn = true;
  });

  try {
    late final GoogleSignIn googleSignIn;
    
    if (Platform.isAndroid) {
      googleSignIn = GoogleSignIn(
        clientId: '446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9.apps.googleusercontent.com',
        scopes: const ['email', 'profile'],
      );
    } else if (Platform.isIOS) {
      googleSignIn = GoogleSignIn(
        clientId: 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com',
        scopes: const ['email', 'profile'],
      );
    } else {
      googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
      );
    }
    
    // 先登出以强制显示账户选择器
    await googleSignIn.signOut();

    // 触发 Google 登入流程
    final googleUser = await googleSignIn.signIn();

    if (googleUser == null) {
      _showLoginResultSnackBar('已取消 Google 登入流程');
      return;
    }

    // 获取用户详细信息
    final googleAuth = await googleUser.authentication;

    // 验证 IdToken
    if (googleAuth.idToken == null) {
      _showLoginResultSnackBar('无法取得 Google IdToken', isError: true);
      return;
    }

    debugPrint('📤 Google 登入成功，准备发送到后端...');
    debugPrint('用户名称: ${googleUser.displayName}');
    debugPrint('用户邮箱: ${googleUser.email}');
    
    // ... 其他代码保持不变
  } catch (e) {
    debugPrint('❌ Google 登入异常: $e');
    _showLoginResultSnackBar('Google 登入失败：$e', isError: true);
  } finally {
    if (mounted) {
      setState(() {
        _isGoogleSigningIn = false;
      });
    }
  }
}
```

## ⏱️ 时间线

| 时间 | 任务 |
|------|------|
| 现在 | 应用选项 1 或 2，应用可以正常运行 |
| 5 分钟 | 获取 SHA-1 并添加到 Google Cloud |
| 10 分钟 | 等待 Google 系统更新 |
| 15 分钟 | 恢复 Google Sign-In 代码 |
| 20 分钟 | 重新构建并测试 |

## ✅ 完成后验证

当 Google Sign-In 恢复后:

1. 点击「使用 Google 登入」
2. 应该看到 Google 登入对话框 (不是错误)
3. 选择账户
4. 应该成功登入

---

**建议**: 先用选项 1，等 SHA-1 配置完成后再恢复完整的 Google Sign-In 代码。这样用户体验不会中断。
