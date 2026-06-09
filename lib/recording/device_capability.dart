import 'package:flutter/foundation.dart';

/// 檢查裝置能力（視頻錄製 + 實時分析同步支持）
class DeviceCapability {
  static bool? _cachedResult;

  /// 現代裝置（Android CameraX / iOS AVFoundation）均支援同時錄影 + image stream。
  static Future<bool> supportsVideoAndAnalysis() async {
    _cachedResult ??= true;
    debugPrint('[DeviceCapability] 並行支持: $_cachedResult');
    return _cachedResult!;
  }

  static void resetCache() {
    _cachedResult = null;
  }
}
