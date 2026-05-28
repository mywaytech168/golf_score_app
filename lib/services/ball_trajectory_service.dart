import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/export_quality.dart';
import 'ball_tracker.dart';
import 'detection_config.dart';  // [新增] 動態配置

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

  // ──────────────────────────────────────────────────────────────
  // Step 1c：TFLite 模式 → Kotlin YOLOv8n 偵測
  // ──────────────────────────────────────────────────────────────

  /// TFLite 模式：呼叫 Kotlin 端 YOLOv8n int8 模型直接偵測每幀中的高爾夫球。
  ///
  /// 與原版 extractBlobs 不同，此方法不做幀差——每幀獨立推論，
  /// 適合場景變化大或背景複雜的情況。
  ///
  /// 當 Kotlin 回傳 error（模型未載入或推論失敗），自動 fallback 至原版 extractBlobs。
  /// 失敗回傳 null。
  static Future<FrameExtractionResult?> extractBlobsTflite({
    required String inputPath,
    double? hitSec,
  }) async {
    debugPrint('[BallTraj] ▶ TFLite 模式啟動：呼叫 Kotlin YOLOv8 偵測器 hitSec=${hitSec?.toStringAsFixed(2) ?? 'null'}');
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'extractBlobsYolo',
        {
          'inputPath': inputPath,
          if (hitSec != null) 'hitSec': hitSec,
        },
      );
      if (raw == null) {
        debugPrint('[BallTraj] ❌ TFLite: Kotlin 回傳 null（模型未載入），fallback 至原版');
        return extractBlobs(inputPath: inputPath);
      }
      final result = FrameExtractionResult._fromMap(raw);
      final totalDets = result.frames.fold<int>(0, (s, f) => s + f.blobs.length);
      final framesWithHits = result.frames.where((f) => f.blobs.isNotEmpty).length;
      debugPrint('[BallTraj] ✅ TFLite YOLOv8 完成：${result.frames.length} 幀，'
          '$totalDets 偵測，$framesWithHits 幀有球 '
          '(${result.frames.isEmpty ? 0 : (framesWithHits * 100 ~/ result.frames.length)}%)');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[BallTraj] ⚠ TFLite 失敗 → FALLBACK 至原版 BFS');
      debugPrint('[BallTraj]   code=${e.code}  msg=${e.message}');
      return extractBlobs(inputPath: inputPath);
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
      // 🔍 DEBUG: 打印即將渲製的軌跡信息
      debugPrint('[BallTraj] 開始渲製軌跡疊加...');
      debugPrint('[BallTraj] 軌跡點數: ${trackPts.length}');
      debugPrint('[BallTraj] ROI 尺寸: $roiSize px');
      if (trackPts.isNotEmpty) {
        debugPrint('[BallTraj] 首點: ${trackPts.first}');
        debugPrint('[BallTraj] 末點: ${trackPts.last}');
      }
      
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
