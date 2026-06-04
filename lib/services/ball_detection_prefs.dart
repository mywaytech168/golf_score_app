import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// 球偵測模式
// ============================================================

/// 球偵測演算法模式
enum BallDetectionMode {
  /// 原版算法：幀差 + BFS blob 偵測 + Dart Kalman 追蹤
  original,

  /// TFLite 模式：幀差 + BFS + TFLite 分類器過濾 + Dart Kalman 追蹤
  tflite,

  /// 後端模式：上傳 clip 到伺服器，由 Python worker 追蹤後回傳 track_pts，
  /// Flutter 本地 renderOverlay 合成（計算在後端，渲染在本機）
  server,
}

extension BallDetectionModeExt on BallDetectionMode {
  String get label {
    switch (this) {
      case BallDetectionMode.original:
        return '原版算法';
      case BallDetectionMode.tflite:
        return 'TFLite';
      case BallDetectionMode.server:
        return '伺服器追蹤';
    }
  }

  String get description {
    switch (this) {
      case BallDetectionMode.original:
        return '幀差 + BFS 連通域偵測';
      case BallDetectionMode.tflite:
        return 'TFLite 分類器輔助過濾';
      case BallDetectionMode.server:
        return '後端 Python 演算法追蹤，本機渲染';
    }
  }

  static BallDetectionMode fromKey(String? key) {
    return BallDetectionMode.values.firstWhere(
      (m) => m.name == key,
      orElse: () => BallDetectionMode.original,
    );
  }
}

// ============================================================
// SharedPreferences 工具
// ============================================================

class BallDetectionPrefs {
  BallDetectionPrefs._();

  static const _kMode = 'ball_detection_mode';

  static Future<BallDetectionMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return BallDetectionModeExt.fromKey(prefs.getString(_kMode));
  }

  static Future<void> setMode(BallDetectionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
  }
}
