import 'package:flutter/foundation.dart';

/// 日誌級別
enum LogLevel {
  debug,   // 調試信息
  info,    // 一般信息
  warning, // 警告
  error,   // 錯誤
  fatal,   // 致命錯誤
}

/// 統一的日誌系統
/// 
/// 提供結構化的日誌記錄，便於調試和分析
class Logger {
  static const String _prefix = '[GolfApp]';
  static LogLevel _minLevel = LogLevel.debug;
  static bool _enableStackTrace = true;

  /// 設置最小日誌級別
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// 設置是否顯示堆棧跟踪
  static void setEnableStackTrace(bool enable) {
    _enableStackTrace = enable;
  }

  /// 調試日誌
  static void debug(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (_shouldLog(LogLevel.debug)) {
      _log(
        level: LogLevel.debug,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 一般信息
  static void info(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (_shouldLog(LogLevel.info)) {
      _log(
        level: LogLevel.info,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 警告日誌
  static void warning(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (_shouldLog(LogLevel.warning)) {
      _log(
        level: LogLevel.warning,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 錯誤日誌
  static void error(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (_shouldLog(LogLevel.error)) {
      _log(
        level: LogLevel.error,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 致命錯誤
  static void fatal(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _log(
      level: LogLevel.fatal,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 記錄 HTTP 請求
  static void logHttpRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic body,
  }) {
    debug(
      'HTTP $method $url',
      tag: 'HTTP_REQUEST',
    );
    if (headers != null && headers.isNotEmpty) {
      debug('Headers: $headers', tag: 'HTTP_REQUEST');
    }
    if (body != null) {
      debug('Body: $body', tag: 'HTTP_REQUEST');
    }
  }

  /// 記錄 HTTP 響應
  static void logHttpResponse({
    required int statusCode,
    required String url,
    dynamic body,
    Duration? duration,
  }) {
    final emoji = statusCode < 400 ? '✓' : '✗';
    info(
      '$emoji HTTP $statusCode $url${duration != null ? ' (${duration.inMilliseconds}ms)' : ''}',
      tag: 'HTTP_RESPONSE',
    );
    if (body != null) {
      debug('Response: $body', tag: 'HTTP_RESPONSE');
    }
  }

  /// 內部日誌方法
  static void _log({
    required LogLevel level,
    required String message,
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final timestamp = DateTime.now().toString().split('.').first;
    final levelStr = _getLevelString(level);
    final tagStr = tag != null ? '[$tag] ' : '';

    // 構建日誌消息
    final logMessage = '$_prefix [$timestamp] $levelStr $tagStr$message';

    // 輸出日誌
    debugPrint(logMessage);

    // 如果有錯誤，追加錯誤信息
    if (error != null) {
      debugPrint('$_prefix Error: $error');
    }

    // 如果啟用堆棧跟踪並有 StackTrace
    if (_enableStackTrace && stackTrace != null && kDebugMode) {
      debugPrint('$_prefix StackTrace:\n$stackTrace');
    }
  }

  /// 獲取日誌級別字符串
  static String _getLevelString(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍 DEBUG';
      case LogLevel.info:
        return 'ℹ️ INFO';
      case LogLevel.warning:
        return '⚠️ WARNING';
      case LogLevel.error:
        return '❌ ERROR';
      case LogLevel.fatal:
        return '🔴 FATAL';
    }
  }

  /// 判斷是否應該記錄此級別的日誌
  static bool _shouldLog(LogLevel level) {
    return level.index >= _minLevel.index;
  }
}

/// 便捷擴展：在任何地方使用 logger
extension LoggerExtension on Object {
  /// 調試此對象
  void debugLog({String? prefix}) {
    Logger.debug(
      '${prefix != null ? '$prefix: ' : ''}$this',
    );
  }
}
