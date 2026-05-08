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
          .isVideoRecordingAndImageAnalysisSupported(SensorPosition.back);
      debugPrint('[DeviceCapability] 並行支持: $_cachedResult');
      return _cachedResult!;
    } catch (e) {
      debugPrint('[DeviceCapability] 檢查失敗 (預設允許): $e');
      _cachedResult = true;
      return _cachedResult!;
    }
  }

  /// 重置快取（用於測試或重新初始化）
  static void resetCache() {
    _cachedResult = null;
  }
}
