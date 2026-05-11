import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ball_tracker.dart';

/// 幀偵測結果（Kotlin extractBlobs 回傳）
class FrameExtractionResult {
  final double fps;
  final int width;
  final int height;
  final List<FrameBlobs> frames;

  const FrameExtractionResult({
    required this.fps,
    required this.width,
    required this.height,
    required this.frames,
  });

  factory FrameExtractionResult._fromMap(Map<Object?, Object?> m) {
    final rawFrames = m['frames'] as List<Object?>;
    return FrameExtractionResult(
      fps:    (m['fps']    as num).toDouble(),
      width:  (m['width']  as num).toInt(),
      height: (m['height'] as num).toInt(),
      frames: rawFrames
          .map((f) => FrameBlobs.fromMap(f as Map<Object?, Object?>))
          .toList(),
    );
  }
}

/// 球軌跡服務：
///   1. [extractBlobs]   → Kotlin 像素層：解碼影片，輸出每幀候選 blob
///   2. [renderOverlay]  → Kotlin I/O 層：把 Dart 算好的軌跡點疊加到影片
class BallTrajectoryService {
  static const _channel =
      MethodChannel('com.example.golf_score_app/ball_trajectory');

  // ──────────────────────────────────────────────────────────────
  // Step 1：Kotlin 像素層 → 每幀 blob
  // ──────────────────────────────────────────────────────────────

  /// 對 [inputPath]（含骨架的 mp4）做逐幀幀差偵測。
  /// 回傳 [FrameExtractionResult]（fps / 解析度 / 每幀 blob 列表）；
  /// 失敗回傳 null。
  static Future<FrameExtractionResult?> extractBlobs({
    required String inputPath,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'extractBlobs',
        {'inputPath': inputPath},
      );
      if (raw == null) return null;
      return FrameExtractionResult._fromMap(raw);
    } catch (e) {
      debugPrint('[BallTraj] extractBlobs error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Step 2：Kotlin I/O 層 → 疊加軌跡
  // ──────────────────────────────────────────────────────────────

  /// 在 [inputPath]（含骨架的 mp4）上疊加 [trackPts] 軌跡，
  /// 輸出到 [outputPath]。
  ///
  /// [trackPts] 由 [TrackPoint.toMap] 序列化而來：
  ///   [{'x': int, 'y': int, 'pts': int (μs)}, ...]
  ///
  /// 成功回傳 [outputPath]，失敗回傳 null。
  static Future<String?> renderOverlay({
    required String inputPath,
    required String outputPath,
    required List<Map<String, dynamic>> trackPts,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'renderOverlay',
        {
          'inputPath':  inputPath,
          'outputPath': outputPath,
          'trackPts':   trackPts,
        },
      );
      return ok == true ? outputPath : null;
    } catch (e) {
      debugPrint('[BallTraj] renderOverlay error: $e');
      return null;
    }
  }
}
