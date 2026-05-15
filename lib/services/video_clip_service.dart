import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TrimResult {
  final String path;
  /// clip 實際起始秒數（來自 key frame PTS，可能略早於請求的 startSec）
  final double actualStartSec;

  const TrimResult({required this.path, required this.actualStartSec});
}

/// 影片裁切服務：透過 VideoTrimmer (MediaExtractor+MediaMuxer) 裁出指定時間範圍的片段
class VideoClipService {
  static const _channel = MethodChannel('com.example.golf_score_app/trimmer');

  /// 裁切 [srcPath] 的 [startSec]–[endSec] 範圍，輸出到 [dstPath]。
  /// 成功回傳 [TrimResult]，失敗回傳 null。
  /// [TrimResult.actualStartSec] 是 clip 實際的起始時間（key frame PTS），
  /// 用來對齊 CSV 切分，確保骨架疊加時間正確。
  static Future<TrimResult?> trimClip({
    required String srcPath,
    required String dstPath,
    required double startSec,
    required double endSec,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map>('trim', {
        'srcPath': srcPath,
        'dstPath': dstPath,
        'startMs': (startSec * 1000).round(),
        'endMs': (endSec * 1000).round(),
      });
      if (res == null || res['ok'] != true) return null;
      final baseTimeMs = (res['baseTimeMs'] as num?)?.toDouble() ?? (startSec * 1000);
      return TrimResult(path: dstPath, actualStartSec: baseTimeMs / 1000.0);
    } catch (e) {
      debugPrint('[VideoClip] trim error: $e');
      return null;
    }
  }
}
