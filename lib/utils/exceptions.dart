/// 自定义异常定义
/// 
/// 统一的异常处理系统，便于错误分类和处理

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
  String toString() => '${this.runtimeType}: $message${code != null ? ' ($code)' : ''}';
}

/// 網絡異常
class NetworkException extends AppException {
  NetworkException({
    String message = '網絡連接失敗',
    String? code,
    Exception? originalException,
  }) : super(
    message: message,
    code: code ?? 'NETWORK_ERROR',
    originalException: originalException,
  );
}

/// 認證異常
class AuthException extends AppException {
  AuthException({
    String message = '認證失敗',
    String? code,
    Exception? originalException,
  }) : super(
    message: message,
    code: code ?? 'AUTH_ERROR',
    originalException: originalException,
  );
}

/// 無效令牌異常
class InvalidTokenException extends AuthException {
  InvalidTokenException({
    String message = '令牌無效或已過期',
    Exception? originalException,
  }) : super(
    message: message,
    code: 'INVALID_TOKEN',
    originalException: originalException,
  );
}

/// 未授權異常
class UnauthorizedException extends AuthException {
  UnauthorizedException({
    String message = '無權訪問此資源',
    Exception? originalException,
  }) : super(
    message: message,
    code: 'UNAUTHORIZED',
    originalException: originalException,
  );
}

/// 數據異常
class DataException extends AppException {
  DataException({
    String message = '數據處理失敗',
    String? code,
    Exception? originalException,
  }) : super(
    message: message,
    code: code ?? 'DATA_ERROR',
    originalException: originalException,
  );
}

/// 數據不存在異常
class DataNotFoundException extends DataException {
  DataNotFoundException({
    String message = '數據不存在',
    Exception? originalException,
  }) : super(
    message: message,
    code: 'DATA_NOT_FOUND',
    originalException: originalException,
  );
}

/// 序列化異常
class SerializationException extends DataException {
  SerializationException({
    String message = '數據序列化失敗',
    Exception? originalException,
  }) : super(
    message: message,
    code: 'SERIALIZATION_ERROR',
    originalException: originalException,
  );
}

/// 存儲異常
class StorageException extends AppException {
  StorageException({
    String message = '本地存儲操作失敗',
    String? code,
    Exception? originalException,
  }) : super(
    message: message,
    code: code ?? 'STORAGE_ERROR',
    originalException: originalException,
  );
}

/// 服務器異常
class ServerException extends AppException {
  final int? statusCode;

  ServerException({
    String message = '服務器錯誤',
    String? code,
    this.statusCode,
    Exception? originalException,
  }) : super(
    message: message,
    code: code ?? 'SERVER_ERROR',
    originalException: originalException,
  );
}

/// 未實現異常
class NotImplementedException extends AppException {
  NotImplementedException({
    String message = '此功能尚未實現',
    Exception? originalException,
  }) : super(
    message: message,
    code: 'NOT_IMPLEMENTED',
    originalException: originalException,
  );
}

/// 驗證異常
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException({
    String message = '驗證失敗',
    this.fieldErrors,
    Exception? originalException,
  }) : super(
    message: message,
    code: 'VALIDATION_ERROR',
    originalException: originalException,
  );
}
