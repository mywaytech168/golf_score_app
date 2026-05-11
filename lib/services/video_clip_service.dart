import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 影片裁切服務：透過 VideoTrimmer (Media3 Transformer) 裁出指定時間範圍的片段
class VideoClipService {
  static const _channel = MethodChannel('com.example.golf_score_app/trimmer');

  /// 裁切 [srcPath] 的 [startSec]–[endSec] 範圍，輸出到 [dstPath]。
  /// 成功回傳 [dstPath]，失敗回傳 null。
  static Future<String?> trimClip({
    required String srcPath,
    required String dstPath,
    required double startSec,
    required double endSec,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('trim', {
        'srcPath': srcPath,
        'dstPath': dstPath,
        'startMs': (startSec * 1000).round(),
        'endMs': (endSec * 1000).round(),
      });
      return ok == true ? dstPath : null;
    } catch (e) {
      debugPrint('[VideoClip] trim error: $e');
      return null;
    }
  }
}
