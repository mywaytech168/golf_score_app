# Provider 层快速开始指南

## 🚀 立即开始

### 1. **编译和运行**
```bash
# 获取依赖
flutter pub get

# 编译运行（Android）
flutter run

# 或编译运行（iOS）
flutter run -d iPhone
```

### 2. **可能的编译问题及解决**

#### 问题 1: 缺少 import 路径
```
Error: The library 'providers/user_provider.dart' is imported but...
```
**解决**:
- 确保 `lib/providers/*.dart` 文件存在
- 检查 `import` 语句的路径是否正确

#### 问题 2: Provider 包版本不匹配
```
Error: The class 'ChangeNotifierProvider' could not be found...
```
**解决**:
```bash
# 更新 provider 包
flutter pub upgrade provider
```

#### 问题 3: google_sign_in 初始化错误
**解决**: 参考 [Google Sign-In 设置指南](GET_OAUTH_FASTEST_WAY.md)

---

## 📱 功能测试清单

### **认证流程**
- [ ] 应用启动 → AuthProvider 自动初始化
- [ ] 点击"登录" → Google Sign-In 弹窗
- [ ] 成功登录 → 令牌存储，导航到首页
- [ ] 点击"登出" → 清空令牌，返回登录页

### **首页显示**
- [ ] 用户头像显示（若无则显示默认图标）
- [ ] 今日统计数据加载
- [ ] 4 个快速操作按钮显示
- [ ] 进度条显示进度百分比
- [ ] 提示可关闭并消失

### **刷新功能**
- [ ] 下拉刷新 → 统计数据更新
- [ ] 右上角刷新按钮 → 数据重新加载
- [ ] 加载中显示加载指示器

### **用户信息**
- [ ] 首次进入 → 显示默认昵称
- [ ] 个人资料页 → 可编辑昵称和头像
- [ ] 保存后 → 首页实时更新显示

---

## 🔧 常见操作

### **在新页面中使用 Provider**

#### 获取统计数据
```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<StatisticsProvider>(
      builder: (context, stats, _) {
        return Text('今日揮桿: ${stats.getTodayMetrics()['totalSwings']}');
      },
    );
  }
}
```

#### 更新用户信息
```dart
// 一次性读取并操作
context.read<UserProvider>()
  .updateDisplayName('新昵称');

// 使用 watch 监听
final user = context.watch<UserProvider>();
Text(user.displayName);
```

#### 控制录制
```dart
ElevatedButton(
  onPressed: () async {
    await context.read<RecordingProvider>().startRecording();
  },
  child: const Text('开始录制'),
)
```

---

## 📊 Provider 状态查看

### **调试 Provider 状态**
```dart
// 在 HomePage 的 debug 面板打印状态
void _debugPrintProviderState() {
  final auth = context.read<AuthProvider>();
  final stats = context.read<StatisticsProvider>();
  final user = context.read<UserProvider>();
  
  debugPrint('=== Provider State ===');
  debugPrint('Auth: ${auth.isLoggedIn}');
  debugPrint('User: ${user.displayName}');
  debugPrint('Stats: ${stats.getTodayMetrics()}');
}
```

### **使用 DevTools 监控 Provider**
```bash
# 启用调试工具栏
flutter run --enable-software-test-drivers

# 或在 DevTools 中查看 Provider 树
flutter run
# 按 'w' 打开济览器 DevTools
```

---

## 🎯 逐步集成其他页面

### **Step 1: 更新 RecordingSessionPage**
```dart
// 原来:
const Text('Recording...')

// 改为:
Consumer<RecordingProvider>(
  builder: (context, recording, _) {
    return Text(recording.isRecording ? '录制中...' : '就绪');
  },
)
```

### **Step 2: 更新 VidePlayerPage**
```dart
// 原来:
VideoPlayer(controller)

// 改为:
Consumer<VideoProvider>(
  builder: (context, video, _) {
    return Column(
      children: [
        if (video.controller != null)
          VideoPlayer(video.controller!),
        LinearProgressIndicator(
          value: video.getProgressPercentage(),
        ),
      ],
    );
  },
)
```

### **Step 3: 连接 LoginPage**
```dart
// 在登录页中
ElevatedButton(
  onPressed: () async {
    final success = await context
      .read<AuthProvider>()
      .signInWithGoogle();
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  },
  child: const Text('登入'),
)
```

---

## 💡 最佳实践

### ✅ 做这些
```dart
// ✅ 好的做法：在业务逻辑中使用 read
void handleButtonPress() {
  context.read<AuthProvider>().signOut();
}

// ✅ 好的做法：在 build 中使用 watch 或 Consumer
Widget buildUI() {
  final user = context.watch<UserProvider>();
  return Text(user.displayName);
}

// ✅ 好的做法：错误处理
Consumer<StatisticsProvider>(
  builder: (context, stats, _) {
    if (stats.errorMessage != null) {
      return ErrorWidget(message: stats.errorMessage!);
    }
    return StatsWidget();
  },
)
```

### ❌ 避免这些
```dart
// ❌ 避免：在非 build 方法中使用 watch
void initState() {
  context.watch<UserProvider>(); // ❌ 错误！
}

// ❌ 避免：创建多个 Provider 实例
class MyWidget extends StatelessWidget {
  final provider = StatisticsProvider(); // ❌ 不必要！
}

// ❌ 避免：忘记错误处理
Consumer<StatisticsProvider>(
  builder: (context, stats, _) {
    return Text('${stats.todayStatistics?.totalCount}'); // 可能为 null
  },
)
```

---

## 🧪 测试 Provider

### **单元测试示例**
```dart
void main() {
  group('AuthProvider', () {
    test('初始化时检查登录状态', () async {
      final provider = AuthProvider();
      await provider.initialize();
      expect(provider.isLoggedIn, isFalse);
    });
  });

  group('StatisticsProvider', () {
    test('載入今日統計', () async {
      final provider = StatisticsProvider();
      await provider.loadTodayStatistics();
      expect(provider.todayStatistics, isNotNull);
    });
  });
}
```

### **Widget 测试示例**
```dart
testWidgets('首页显示用户昵称', (tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => UserProvider(),
        ),
      ],
      child: const MaterialApp(home: HomePage(cameras: [])),
    ),
  );

  expect(find.text('Golf Player'), findsOneWidget);
});
```

---

## 📋 检查清单：编译前

- [ ] 所有 Provider 文件都在 `lib/providers/` 中
- [ ] main.dart 已更新 MultiProvider 配置
- [ ] HomePage 的 import 路径正确
- [ ] 没有循环依赖 (circular imports)
- [ ] 所有 Provider 都在 pubspec.yaml 中声明（provider 包）
- [ ] 没有硬拼的路径，使用相对路径

---

## 🆘 遇到问题？

### 常见错误排查

| 错误 | 原因 | 解决 |
|------|------|------|
| `No provider found` | Provider 树中缺少该 Provider | 检查 MultiProvider 配置 |
| `setState called after dispose` | Widget 被释放后仍在更新 | 使用 `if (mounted)` 检查 |
| `Infinite loop` | Provider 监听导致循环更新 | 检查 notifyListeners() 调用顺序 |
| `Auth token expired` | 令牌已过期 | 调用 `refreshToken()` 方法 |

---

## 📈 下一步里程碑

### **已完成** ✅
- [x] Provider 层建立
- [x] HomePage 改进
- [x] main.dart 配置

### **本周** (优先级 1)
- [ ] 编译通过并基本运行
- [ ] 连接登录页
- [ ] 手动测试认证流程
- [ ] 验证统计数据加载

### **下周** (优先级 2)
- [ ] Repository 层建立
- [ ] 服务层模块化
- [ ] 单元测试添加

---

**祝贺！您已成功构建应用的状态管理层！** 🎊

