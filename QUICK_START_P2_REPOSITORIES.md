## 🚀 P2 Repository 层快速开始指南

**本指南说明如何在 Flutter 应用中集成和使用新的 Repository 层**

---

## 📦 架构快速回顾

```
main.dart (应用入口)
  │
  ├─ ServiceLocator.initialize() ← 全局 DI 容器
  │   │
  │   └─ RepositoryLocator
  │       ├─ AuthRepository
  │       ├─ StatisticsRepository
  │       ├─ RecordingRepository
  │       ├─ UserRepository
  │       └─ (+ ConfigRepository 待建)
  │
  ├─ MultiProvider
  │   ├─ AuthProvider ← 使用 AuthRepository
  │   ├─ StatisticsProvider ← 使用 StatisticsRepository
  │   ├─ UserProvider ← 使用 UserRepository
  │   └─ RecordingProvider ← 使用 RecordingRepository
  │
  └─ MyApp
      └─ UI Widgets (Consumer → Providers → Repositories)
```

---

## 1️⃣ 步骤 1: 配置 ServiceLocator（main.dart）

### 当前代码结构
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 现有初始化...
  await GoogleStaticMapsFlutter.initialize(
    apiKey: googleMapsApiKey,
  );
  // ... 其他初始化
  
  runApp(const MyApp());
}
```

### 更新为:
```dart
import 'package:golf_score_app/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔴 在任何其他初始化之前，初始化 ServiceLocator
  try {
    await ServiceLocator().initialize(
      apiBaseUrl: 'https://your-api.com', // 替换为实际的后端 URL
    );
    Logger.info('✅ ServiceLocator 初始化成功');
  } catch (e) {
    Logger.fatal('❌ ServiceLocator 初始化失败: $e');
    rethrow;
  }
  
  // 现有初始化（按原有顺序）
  await GoogleStaticMapsFlutter.initialize(
    apiKey: googleMapsApiKey,
  );
  // ... 其他初始化
  
  runApp(const MyApp());
}
```

---

## 2️⃣ 步骤 2: 连接 Providers 到 Repositories

### 当前 AuthProvider（需要更新）
```dart
class AuthProvider extends ChangeNotifier {
  // 当前：直接使用服务
  final _tokenStorage = TokenStorage();
  
  Future<void> signInWithGoogle(String googleToken) async {
    // 直接调用服务...
  }
}
```

### 更新为:
```dart
import 'package:golf_score_app/repositories/auth_repository.dart';
import 'package:golf_score_app/service_locator.dart';

class AuthProvider extends ChangeNotifier {
  // 使用 Repository 而非服务
  final AuthRepository _authRepository;
  
  String? _accessToken;
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;
  
  // 构造函数：接收 Repository 依赖
  AuthProvider({AuthRepository? authRepository})
    : _authRepository = authRepository ?? getRepositories().auth;
  
  // Getters
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  
  /// 使用 Google 登录
  Future<void> signInWithGoogle(String googleToken) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // 调用 Repository（返回 Result<T>）
      final result = await _authRepository.signInWithGoogle(googleToken);
      
      if (result.isSuccess) {
        final authData = result.getOrNull();
        _accessToken = authData?['accessToken'];
        _userId = authData?['userId'];
        Logger.info('✅ Google 登录成功', tag: 'AuthProvider');
      } else {
        // 错误处理
        final error = result.getErrorOrNull();
        _errorMessage = error?.message ?? '登录失败';
        Logger.error('❌ Google 登录失败: $_errorMessage', tag: 'AuthProvider');
      }
    } catch (e) {
      _errorMessage = '登录异常: $e';
      Logger.error(_errorMessage, tag: 'AuthProvider');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// 刷新令牌
  Future<void> refreshToken(String refreshToken) async {
    try {
      final result = await _authRepository.refreshToken(refreshToken);
      
      if (result.isSuccess) {
        _accessToken = result.getOrNull();
        Logger.info('✅ 令牌刷新成功', tag: 'AuthProvider');
      } else {
        _errorMessage = result.getErrorOrNull()?.message ?? '刷新失败';
      }
    } catch (e) {
      _errorMessage = '刷新异常: $e';
    }
    notifyListeners();
  }
  
  /// 登出
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final result = await _authRepository.signOut();
      
      if (result.isSuccess) {
        _accessToken = null;
        _userId = null;
        _errorMessage = null;
        Logger.info('✅ 登出成功', tag: 'AuthProvider');
      } else {
        _errorMessage = result.getErrorOrNull()?.message ?? '登出失败';
      }
    } catch (e) {
      _errorMessage = '登出异常: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// 检查登录状态
  Future<bool> checkLoginStatus() async {
    try {
      final result = await _authRepository.isLoggedIn();
      return result.isSuccess ? result.getOrNull() ?? false : false;
    } catch (e) {
      Logger.error('检查登录状态失败: $e', tag: 'AuthProvider');
      return false;
    }
  }
}
```

### 在 main.dart 中配置 AuthProvider
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => AuthProvider(
        // AuthRepository 会自动从 ServiceLocator 获取
        // 也可以显式传入：
        // authRepository: getRepositories().auth,
      ),
    ),
    // ... 其他 Providers
  ],
  child: MyApp(),
)
```

---

## 3️⃣ 步骤 3: 在 Widget 中使用

### LoginPage 示例
```dart
class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          // 显示加载状态
          if (authProvider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }
          
          // 显示错误信息
          if (authProvider.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(authProvider.errorMessage!)),
            );
          }
          
          return Center(
            child: ElevatedButton(
              onPressed: () => authProvider.signInWithGoogle(googleToken),
              child: Text('使用 Google 登录'),
            ),
          );
        },
      ),
    );
  }
}
```

---

## 4️⃣ 步骤 4: Result<T> 错误处理模式

### 理解 Result 类型
```dart
// Repository 返回 Result<T>
Future<Result<Map<String, dynamic>>> signInWithGoogle(String token) async {
  try {
    final data = await _remoteDataSource.signInWithGoogle(token);
    await _localDataSource.saveAccessToken(...);
    return Success(data);  // 成功情况
  } catch (e) {
    return Failure(AuthException(...), stackTrace);  // 失败情况
  }
}
```

### 在 Provider 中处理 Result
```dart
// ✅ 正确的方式：检查 isSuccess
final result = await _repository.signInWithGoogle(token);

if (result.isSuccess) {
  // ✅ 成功：获取值
  final data = result.getOrNull();
  _token = data?['accessToken'];
} else {
  // ❌ 失败：获取错误
  final error = result.getErrorOrNull();
  _errorMessage = error?.message;
}

// ✅ 函数式方式：使用 when()
result.when(
  onSuccess: (data) {
    _token = data['accessToken'];
  },
  onFailure: (error) {
    _errorMessage = error.message;
  },
);

// ✅ 避免异常：
// ❌ final value = result.getOrThrow();  // 可能 throw
// ✅ final value = result.getOrNull();   // 返回 null
// ✅ final value = result.getOrElse('default');  // 用默认值
```

---

## 5️⃣ 步骤 5: 同步应用所有 Providers

### 应该更新的 Providers（优先级排序）

| Provider | Repository | 优先级 | 预计工作量 |
|----------|-----------|--------|----------|
| AuthProvider | AuthRepository | 🔴 最高 | 1-2 小时 |
| StatisticsProvider | StatisticsRepository | 🔴 最高 | 1-2 小时 |
| UserProvider | UserRepository | 🟠 高 | 30 分钟 |
| RecordingProvider | RecordingRepository | 🟠 高 | 30 分钟 |
| AppStateProvider | ConfigRepository | 🟡 中 | 20 分钟 |
| VideoProvider | (可选暂不改) | 🟡 中 | 待定 |

### 更新模板（以 StatisticsProvider 为例）
```dart
import 'package:golf_score_app/repositories/statistics_repository.dart';
import 'package:golf_score_app/service_locator.dart';

class StatisticsProvider extends ChangeNotifier {
  final StatisticsRepository _repository;
  
  Map<String, dynamic>? _todayStats;
  Map<String, dynamic>? _allTimeStats;
  bool _isLoading = false;
  String? _errorMessage;
  
  StatisticsProvider({StatisticsRepository? repository})
    : _repository = repository ?? getRepositories().statistics;
  
  // Getters
  Map<String, dynamic>? get todayStats => _todayStats;
  Map<String, dynamic>? get allTimeStats => _allTimeStats;
  bool get isLoading => _isLoading;
  
  /// 刷新统计数据
  Future<void> refreshStatistics(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final result = await _repository.refreshAll(userId);
      
      if (result.isSuccess) {
        final data = result.getOrNull();
        _todayStats = data?['today'];
        _allTimeStats = data?['allTime'];
        Logger.info('✅ 统计数据已刷新', tag: 'StatisticsProvider');
      } else {
        _errorMessage = result.getErrorOrNull()?.message;
      }
    } catch (e) {
      _errorMessage = '获取统计数据失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

---

## 6️⃣ 调试技巧

### 启用详细日志
```dart
// 在 main() 中设置日志级别
Logger.setLogLevel(LogLevel.debug);  // 显示所有日志

// 查看 ServiceLocator 日志
// 搜索 tag: 'ServiceLocator'

// 查看 Repository 操作
// 搜索 tag: 'AuthRepository', 'StatisticsRepository' 等

// 查看数据源操作
// 搜索 tag: 'LocalDataSource', 'RemoteDataSource'

// 查看 HTTP 请求/响应
// 搜索 tag: 'RemoteDataSource.HTTP'
```

### 检查编译错误
```bash
# 运行编译检查
flutter pub get
flutter analyze

# 检查特定文件
dart analyze lib/repositories/
dart analyze lib/service_locator.dart
dart analyze lib/providers/
```

### 测试数据流
```dart
// 简单的集成测试
void testDataFlow() async {
  // 1. 初始化
  await ServiceLocator().initialize();
  
  // 2. 获取 Repository
  final authRepo = getRepositories().auth;
  
  // 3. 测试调用
  final result = await authRepo.getAccessToken();
  assert(result.isSuccess);
  
  // 4. 验证错误处理
  final result2 = await authRepo.signInWithGoogle('invalid');
  assert(result2.isFailure);
  assert(result2.getErrorOrNull() is AuthException);
}
```

---

## 🔗 文件导入参考

### 快捷导入
```dart
// ServiceLocator
import 'package:golf_score_app/service_locator.dart';

// Repositories（按需）
import 'package:golf_score_app/repositories/auth_repository.dart';
import 'package:golf_score_app/repositories/statistics_repository.dart';
import 'package:golf_score_app/repositories/result.dart';

// 工具类
import 'package:golf_score_app/utils/exceptions.dart';
import 'package:golf_score_app/utils/logger.dart';
```

---

## ✅ 检查清单

在开始 P3 工作前，验证以下事项：

- [ ] `service_locator.dart` 已创建并无编译错误
- [ ] `repository_locator.dart` 已创建
- [ ] 4 个核心 Repository 已创建：
  - [ ] `auth_repository.dart`
  - [ ] `statistics_repository.dart`
  - [ ] `recording_repository.dart`
  - [ ] `user_repository.dart`
- [ ] 数据源实现已创建：
  - [ ] `local_data_source_impl.dart`
  - [ ] `remote_data_source_impl.dart`
- [ ] 工具类已创建：
  - [ ] `result.dart`
  - [ ] `data_sources.dart`
  - [ ] `exceptions.dart`（util 层）
  - [ ] `logger.dart`（util 层）
  - [ ] `extensions.dart`（util 层）
- [ ] 编译无错误：`flutter pub get && flutter analyze`
- [ ] 可选：运行应用验证 ServiceLocator 初始化成功

---

## 📞 后续 P3 工作

按优先级：

1. **AuthProvider + AuthRepository 集成** (最重要)
   - 更新登录页面
   - 测试 Google Sign-In 流程
   - 验证令牌存储和检索

2. **StatisticsProvider + StatisticsRepository 集成** (重要)
   - HomePage 数据绑定
   - 缓存验证（5 分钟策略）

3. **UserProvider + UserRepository 集成**
   - 个人资料页面
   - 头像和昵称更新

4. **配置 RemoteDataSourceImpl 的实际端点**
   - 替换示例 URL
   - 验证认证 header
   - 测试错误处理

5. **可选：服务层模块化**
   - 组织现有 24 个服务
   - 但不阻塞 P3 其他任务

---

**准备好开始 P3 了吗？** 🚀
