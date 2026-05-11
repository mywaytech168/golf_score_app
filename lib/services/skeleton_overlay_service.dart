import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 骨架疊加服務：呼叫 Android 原生渲染器，將 pose CSV 骨架疊加到裁切片段上。
class SkeletonOverlayService {
  static const _channel =
      MethodChannel('com.example.golf_score_app/skeleton_overlay');

  /// 在 [clipPath] 上渲染 [csvPath] 的骨架，輸出到 [outputPath]。
  ///
  /// [startSec] 為片段在原始影片中的起始秒數，用於對齊 CSV 幀索引。
  ///
  /// 成功回傳 [outputPath]，失敗回傳 null。
  static Future<String?> render({
    required String clipPath,
    required String csvPath,
    required double startSec,
    required String outputPath,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('render', {
        'clipPath': clipPath,
        'csvPath': csvPath,
        'startSec': startSec,
        'outputPath': outputPath,
      });
      return ok == true ? outputPath : null;
    } catch (e) {
      debugPrint('[SkeletonOverlay] render error: $e');
      return null;
    }
  }
}
