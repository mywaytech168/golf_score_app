import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/export_quality.dart';
import 'ball_tracker.dart';
import 'detection_config.dart';  // [新增] 動態配置

/// 幀偵測結果（Kotlin extractBlobs 回傳）
/// 幀偵測結果（Kotlin extractBlobs 回傳）
/// width/height = coded 空間尺寸（對應 Python 演算法空間），rotation 供 Dart 計算 coded-space ROI 中心
class FrameExtractionResult {
  final double fps;
  final int width;    // coded width  (e.g. 1920 for portrait rotation=90)
  final int height;   // coded height (e.g. 1080 for portrait rotation=90)
  final int rotation; // 影片 rotation metadata (0 / 90 / 180 / 270)
  final List<FrameBlobs> frames;

  const FrameExtractionResult({
    required this.fps,
    required this.width,
    required this.height,
    required this.rotation,
    required this.frames,
  });

  factory FrameExtractionResult._fromMap(Map<Object?, Object?> m) {
    final rawFrames = m['frames'] as List<Object?>;
    return FrameExtractionResult(
      fps:      (m['fps']      as num).toDouble(),
      width:    (m['width']    as num).toInt(),
      height:   (m['height']   as num).toInt(),
      rotation: (m['rotation'] as num?)?.toInt() ?? 0,
      frames:   rawFrames
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

  /// 動態配置版本：對 [inputPath] 做逐幀偵測，使用 [config] 動態參數
  /// [新增 Week 3] 此方法調用 Kotlin 的 'extractBlobsWithConfig'
  /// 
  /// 參數:
  /// - inputPath: 影片路徑
  /// - config: 動態檢測配置（diffThresh, areaLo, areaHi, circMin）
  /// - roiSize: 搜尋區域大小（用於後續 ROI 擴大）
  static Future<FrameExtractionResult?> extractBlobsWithConfig({
    required String inputPath,
    required DetectionConfig config,
    required int roiSize,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'extractBlobsWithConfig',
        {
          'inputPath': inputPath,
          'config': config.toMap(),
          'roiSize': roiSize,
        },
      );
      if (raw == null) return null;
      return FrameExtractionResult._fromMap(raw);
    } catch (e) {
      debugPrint('[BallTraj] extractBlobsWithConfig error: $e');
      return null;
    }
  }

  /// p0-SAHI：呼叫 Kotlin 端對擊球前數幀做整幀多-tile YOLO 掃描，回傳最穩定的靜止
  /// 球 P0（coded 空間）。供 BallTracker 當種子(seedP0)，飛行段仍走幀差+Kalman。
  /// 回傳 {cx, cy, frame} 或 null（未找到 → 不種子，tracker 退回幀差找 p0）。
  static Future<({int cx, int cy, int frame})?> findBallP0({
    required String inputPath,
    double? hitSec,
    List<int>? golferBox, // coded 空間 [x1,y1,x2,y2]，提供時掃描範圍縮小到打者附近
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'findBallP0',
        {
          'inputPath': inputPath,
          if (hitSec != null) 'hitSec': hitSec,
          if (golferBox != null) 'golferBox': golferBox,
        },
      );
      if (raw == null) return null;
      final cx = (raw['cx'] as num?)?.toInt();
      final cy = (raw['cy'] as num?)?.toInt();
      final frame = (raw['frame'] as num?)?.toInt();
      if (cx == null || cy == null || frame == null) return null;
      debugPrint('[BallTraj] ✅ p0-SAHI P0=($cx,$cy) frame=$frame '
          'count=${raw['count']} conf=${raw['conf']}');
      return (cx: cx, cy: cy, frame: frame);
    } catch (e) {
      debugPrint('[BallTraj] findBallP0 error: $e');
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
  /// [roiSize] - 可選，ROI 尺寸（像素），若 > 0 則繪製 ROI 邊界框，預設 = 0（不繪製）
  /// [quality] - 輸出品質模式，控制 Kotlin 編碼位元率
  ///
  /// 成功回傳 [outputPath]，失敗回傳 null。
  static Future<String?> renderOverlay({
    required String inputPath,
    required String outputPath,
    required List<Map<String, dynamic>> trackPts,
    int roiSize = 0,
    ExportQuality quality = ExportQuality.standard,
  }) async {
    try {
      debugPrint('[BallTraj] renderOverlay pts=${trackPts.length} roi=$roiSize');
      final ok = await _channel.invokeMethod<bool>(
        'renderOverlay',
        {
          'inputPath':  inputPath,
          'outputPath': outputPath,
          'trackPts':   trackPts,
          'roiSize':    roiSize,
          'quality':    quality.channelKey,
        },
      );
      return ok == true ? outputPath : null;
    } catch (e) {
      debugPrint('[BallTraj] renderOverlay error: $e');
      return null;
    }
  }
}
