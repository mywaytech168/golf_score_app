import 'dart:io';

/// App 配置管理
/// 根據環境自動選擇不同的設定
class AppConfig {
  AppConfig._();

  /// 是否為生產環境
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');

  /// Google Sign-In Client ID
  /// iOS 和 Android 需要使用不同的 Client ID
  static String get googleClientId {
    if (Platform.isIOS) {
      // iOS Client ID - 需要在 Google Cloud Console 創建 iOS 類型的 OAuth Client
      // TODO: 替換為你的 iOS Client ID
      return isProduction
          ? '446697241300-2o58ae8nku99m9ojs49upe1srfs6e75c.apps.googleusercontent.com'
          : '446697241300-2o58ae8nku99m9ojs49upe1srfs6e75c.apps.googleusercontent.com';
    } else if (Platform.isAndroid) {
      // Android Client ID
      return isProduction
          ? '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com'
          : '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com';
    }
    // Web Client ID (用於其他平台)
    return '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com';
  }

  /// Google Sign-In Server Client ID (用於後端驗證)
  static String get googleServerClientId {
    return '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com';
  }

  /// API 基礎 URL
  static String get apiBaseUrl {
    return isProduction
        ? 'https://tekswing.api.atk.tw'
        : 'https://tekswing.api.atk.tw'; // 開發和生產用同一個
  }

  /// 環境名稱
  static String get environmentName {
    return isProduction ? 'Production' : 'Development';
  }
}
