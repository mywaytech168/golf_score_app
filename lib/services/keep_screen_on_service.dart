import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 螢幕常亮控制服務：透過原生 MethodChannel 切換系統休眠設定
class KeepScreenOnService {
  // 使用固定頻道名稱，對應原生端的 wakelock 控制
  static const MethodChannel _channel = MethodChannel('keep_screen_on_channel');

  // 以記憶體旗標避免重複呼叫原生層
  static bool _isEnabled = false;

  /// 啟用螢幕常亮，錄影或長時間分析時避免裝置自動休眠
  static Future<void> enable() async {
    if (_isEnabled) return;
    try {
      await _channel.invokeMethod('enable');
      _isEnabled = true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('啟用螢幕常亮失敗：$error\n$stackTrace');
      }
    }
  }

  /// 關閉螢幕常亮，恢復系統預設的休眠策略
  static Future<void> disable() async {
    if (!_isEnabled) return;
    try {
      await _channel.invokeMethod('disable');
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('停用螢幕常亮失敗：$error\n$stackTrace');
      }
    } finally {
      _isEnabled = false;
    }
  }
}
