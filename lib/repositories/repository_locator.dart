import 'auth_repository.dart';
import 'statistics_repository.dart';
import 'recording_repository.dart';
import 'user_repository.dart';
import 'data_sources.dart';

/// Repository 注册表/提供者
/// 
/// 统一管理所有 Repository 实例的生命周期和访问
class RepositoryLocator {
  static final RepositoryLocator _instance = RepositoryLocator._internal();

  late LocalDataSource _localDataSource;
  late RemoteDataSource _remoteDataSource;

  late AuthRepository _authRepository;
  late StatisticsRepository _statisticsRepository;
  late RecordingRepository _recordingRepository;
  late UserRepository _userRepository;

  RepositoryLocator._internal();

  factory RepositoryLocator() {
    return _instance;
  }

  /// 初始化所有 Repository
  /// 应该在应用启动时调用
  Future<void> initialize({
    required LocalDataSource localDataSource,
    required RemoteDataSource remoteDataSource,
  }) async {
    _localDataSource = localDataSource;
    _remoteDataSource = remoteDataSource;

    // 初始化所有 Repository
    _authRepository = AuthRepository(
      localDataSource: _localDataSource,
      remoteDataSource: _remoteDataSource,
    );

    _statisticsRepository = StatisticsRepository(
      localDataSource: _localDataSource,
      remoteDataSource: _remoteDataSource,
    );

    _recordingRepository = RecordingRepository(
      localDataSource: _localDataSource,
      remoteDataSource: _remoteDataSource,
    );

    _userRepository = UserRepository(
      localDataSource: _localDataSource,
      remoteDataSource: _remoteDataSource,
    );
  }

  // Getters
  AuthRepository get auth => _authRepository;
  StatisticsRepository get statistics => _statisticsRepository;
  RecordingRepository get recording => _recordingRepository;
  UserRepository get user => _userRepository;

  /// 销毁所有 Repository（应用关闭时调用）
  Future<void> dispose() async {
    _authRepository.dispose();
    _statisticsRepository.dispose();
    _recordingRepository.dispose();
    _userRepository.dispose();
  }

  /// 检查是否已初始化
  bool get isInitialized {
    try {
      _ = _authRepository;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 便捷访问函数
AuthRepository getAuthRepository() => RepositoryLocator().auth;
StatisticsRepository getStatisticsRepository() => RepositoryLocator().statistics;
RecordingRepository getRecordingRepository() => RepositoryLocator().recording;
UserRepository getUserRepository() => RepositoryLocator().user;
