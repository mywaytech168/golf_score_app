/// 自定义异常定义
/// 
/// 统一的异常处理系统，便于错误分类和处理
library;

/// 基础异常
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  AppException({
    required this.message,
    this.code,
    this.originalException,
  });

  @override
  String toString() => '$runtimeType: $message${code != null ? ' ($code)' : ''}';
}

/// 網絡異常
class NetworkException extends AppException {
  NetworkException({
    super.message = '網絡連接失敗',
    String? code,
    super.originalException,
  }) : super(
    code: code ?? 'NETWORK_ERROR',
  );
}

/// 認證異常
class AuthException extends AppException {
  AuthException({
    super.message = '認證失敗',
    String? code,
    super.originalException,
  }) : super(
    code: code ?? 'AUTH_ERROR',
  );
}

/// 無效令牌異常
class InvalidTokenException extends AuthException {
  InvalidTokenException({
    super.message = '令牌無效或已過期',
    super.originalException,
  }) : super(
    code: 'INVALID_TOKEN',
  );
}

/// 未授權異常
class UnauthorizedException extends AuthException {
  UnauthorizedException({
    super.message = '無權訪問此資源',
    super.originalException,
  }) : super(
    code: 'UNAUTHORIZED',
  );
}

/// 數據異常
class DataException extends AppException {
  DataException({
    super.message = '數據處理失敗',
    String? code,
    super.originalException,
  }) : super(
    code: code ?? 'DATA_ERROR',
  );
}

/// 數據不存在異常
class DataNotFoundException extends DataException {
  DataNotFoundException({
    super.message = '數據不存在',
    super.originalException,
  }) : super(
    code: 'DATA_NOT_FOUND',
  );
}

/// 序列化異常
class SerializationException extends DataException {
  SerializationException({
    super.message = '數據序列化失敗',
    super.originalException,
  }) : super(
    code: 'SERIALIZATION_ERROR',
  );
}

/// 存儲異常
class StorageException extends AppException {
  StorageException({
    super.message = '本地存儲操作失敗',
    String? code,
    super.originalException,
  }) : super(
    code: code ?? 'STORAGE_ERROR',
  );
}

/// 服務器異常
class ServerException extends AppException {
  final int? statusCode;

  ServerException({
    super.message = '服務器錯誤',
    String? code,
    this.statusCode,
    super.originalException,
  }) : super(
    code: code ?? 'SERVER_ERROR',
  );
}

/// 未實現異常
class NotImplementedException extends AppException {
  NotImplementedException({
    super.message = '此功能尚未實現',
    super.originalException,
  }) : super(
    code: 'NOT_IMPLEMENTED',
  );
}

/// 驗證異常
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException({
    super.message = '驗證失敗',
    this.fieldErrors,
    super.originalException,
  }) : super(
    code: 'VALIDATION_ERROR',
  );
}
