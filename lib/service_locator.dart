import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'repositories/repository_locator.dart';
import 'repositories/local_data_source_impl.dart';
import 'repositories/remote_data_source_impl.dart';
import 'utils/logger.dart';

/// 服务定位器和依赖注入容器
/// 
/// 统一配置和管理应用所有的依赖关系
/// 应该在 main() 中最早调用 initialize()
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();

  late SharedPreferences _sharedPreferences;
  late http.Client _httpClient;
  late RepositoryLocator _repositoryLocator;

  // 配置参数
  String _apiBaseUrl = 'https://api.example.com';

  ServiceLocator._internal();

  factory ServiceLocator() {
    return _instance;
  }

  /// 初始化所有服务
  /// 必须在应用启动时调用，在 runApp() 之前
  Future<void> initialize({
    String apiBaseUrl = 'https://api.example.com',
    http.Client? httpClientOverride,
  }) async {
    try {
      Logger.info('🚀 初始化服务定位器...', tag: 'ServiceLocator');

      _apiBaseUrl = apiBaseUrl;

      // 1. 初始化 SharedPreferences
      Logger.debug('正在初始化本地存储...', tag: 'ServiceLocator');
      _sharedPreferences = await SharedPreferences.getInstance();
      Logger.debug('✓ SharedPreferences 已初始化', tag: 'ServiceLocator');

      // 2. 初始化 HTTP 客户端
      Logger.debug('正在初始化 HTTP 客户端...', tag: 'ServiceLocator');
      _httpClient = httpClientOverride ?? http.Client();
      Logger.debug('✓ HTTP 客户端已初始化 ($_apiBaseUrl)', tag: 'ServiceLocator');

      // 3. 创建数据源实现
      Logger.debug('正在创建数据源...', tag: 'ServiceLocator');
      final localDataSource = LocalDataSourceImpl(prefs: _sharedPreferences);
      final remoteDataSource = RemoteDataSourceImpl(
        httpClient: _httpClient,
        baseUrl: _apiBaseUrl,
      );
      Logger.debug('✓ 数据源已创建', tag: 'ServiceLocator');

      // 4. 初始化 Repository 定位器
      Logger.debug('正在初始化仓库层...', tag: 'ServiceLocator');
      _repositoryLocator = RepositoryLocator();
      await _repositoryLocator.initialize(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
      Logger.debug('✓ 仓库层已初始化', tag: 'ServiceLocator');

      // 5. 健康检查
      Logger.debug('执行后端健康检查...', tag: 'ServiceLocator');
      final isHealthy = await remoteDataSource.healthCheck();
      if (isHealthy) {
        Logger.info('✓ 后端服务运行正常', tag: 'ServiceLocator');
      } else {
        Logger.warning('⚠ 后端服务暂时无法访问', tag: 'ServiceLocator');
      }

      Logger.info('✅ 服务定位器初始化完成', tag: 'ServiceLocator');
    } catch (e, st) {
      Logger.fatal('❌ 服务定位器初始化失败: $e', tag: 'ServiceLocator');
      rethrow;
    }
  }

  /// 获取 SharedPreferences 实例
  SharedPreferences get sharedPreferences => _sharedPreferences;

  /// 获取 HTTP 客户端
  http.Client get httpClient => _httpClient;

  /// 获取 Repository 定位器
  RepositoryLocator get repositories => _repositoryLocator;

  /// 获取 API 基础 URL
  String get apiBaseUrl => _apiBaseUrl;

  /// 销毁所有服务
  /// 应在应用关闭时调用
  Future<void> dispose() async {
    try {
      Logger.info('🛑 销毁服务定位器...', tag: 'ServiceLocator');

      // 销毁仓库
      await _repositoryLocator.dispose();
      Logger.debug('✓ 仓库已销毁', tag: 'ServiceLocator');

      // 关闭 HTTP 客户端
      _httpClient.close();
      Logger.debug('✓ HTTP 客户端已关闭', tag: 'ServiceLocator');

      Logger.info('✅ 服务定位器已销毁', tag: 'ServiceLocator');
    } catch (e) {
      Logger.error('销毁服务定位器失败: $e', tag: 'ServiceLocator');
    }
  }

  /// 检查是否已初始化
  bool get isInitialized {
    try {
      _ = _sharedPreferences;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 重新初始化（用于测试）
  Future<void> reset() async {
    try {
      Logger.warning('重置服务定位器', tag: 'ServiceLocator');
      await dispose();
      // 注意：这里不能直接重新初始化，因为需要参数
      // 调用者应该再次调用 initialize()
    } catch (e) {
      Logger.error('重置服务定位器失败: $e', tag: 'ServiceLocator');
    }
  }
}

/// 全局访问函数
ServiceLocator getServiceLocator() => ServiceLocator();

/// 快捷访问仓库
RepositoryLocator getRepositories() => getServiceLocator().repositories;

/// 快捷访问 SharedPreferences
SharedPreferences getSharedPreferences() => getServiceLocator().sharedPreferences;

/// 快捷访问 HTTP 客户端
http.Client getHttpClient() => getServiceLocator().httpClient;

/// 快捷访问 API 基础 URL
String getApiBaseUrl() => getServiceLocator().apiBaseUrl;
