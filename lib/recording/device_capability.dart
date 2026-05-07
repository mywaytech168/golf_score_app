import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';

/// 檢查裝置能力（視頻錄製 + 實時分析同步支持）
class DeviceCapability {
  static bool? _cachedResult;

  /// 檢查裝置是否支援同時錄影 + image analysis
  static Future<bool> supportsVideoAndAnalysis() async {
    if (_cachedResult != null) return _cachedResult!;

    try {
      _cachedResult = await CameraCharacteristics
          .isVideoRecordingAndImageAnalysisSupported(Sensors.back);
      debugPrint('[DeviceCapability] 並行支持: $_cachedResult');
      return _cachedResult!;
    } catch (e) {
      debugPrint('[DeviceCapability] 檢查失敗 (預設允許): $e');
      // 若檢查失敗，預設為 true（某些舊裝置可能不支援檢查 API）
      _cachedResult = true;
      return _cachedResult!;
    }
  }

  /// 重置快取（用於測試或重新初始化）
  static void resetCache() {
    _cachedResult = null;
  }
}
