import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// V2 高爾夫揮桿分析結果。
///
/// 由 Android 原生完成「音訊峰值偵測 + 局部 ML Kit 骨架分析」後回傳，
/// 比全影片逐幀分析快 10-20 倍。
class GolfAnalysisResult {
  /// 精準擊球時間（毫秒）
  final int impactTimeMs;

  /// 原始音訊峰值時間（毫秒）；無音訊軌時為 -1
  final int audioPeakMs;

  /// 是否有音訊軌
  final bool hasAudio;

  /// 骨架幀數（在擊球窗口內成功偵測的幀數）
  final int frameCount;

  /// 骨架 JSON 字串，結構：
  /// ```json
  /// [
  ///   {
  ///     "timeMs": 1234,
  ///     "landmarks": [
  ///       {
  ///         "type": 0,
  ///         "x":    340.5,   // 還原至原始全幅畫面的像素 x（已加回裁切 offset）
  ///         "y":    210.3,   // 裁切後小圖的像素 y（等同全幅 y，因為只裁寬度）
  ///         "z":   -0.1,
  ///         "vis":  0.98,
  ///         "xNorm": 0.315,  // x / 原始全幅寬，Flutter 疊圖直接乘以 widget 寬
  ///         "yNorm": 0.430   // y / 裁切小圖高（= 全幅高），Flutter 疊圖直接乘以 widget 高
  ///       },
  ///       ...
  ///     ]
  ///   }
  /// ]
  /// ```
  final String skeletonJson;

  /// 分析的影片路徑（方便呼叫端直接使用）
  final String videoPath;

  const GolfAnalysisResult({
    required this.impactTimeMs,
    required this.audioPeakMs,
    required this.hasAudio,
    required this.frameCount,
    required this.skeletonJson,
    required this.videoPath,
  });

  /// 解析 [skeletonJson] 為 Dart List
  List<Map<String, dynamic>> get skeletonFrames =>
      (jsonDecode(skeletonJson) as List).cast<Map<String, dynamic>>();

  @override
  String toString() =>
      'GolfAnalysisResult(impactTimeMs=$impactTimeMs, hasAudio=$hasAudio, frames=$frameCount)';
}

/// V2 骨架分析服務：呼叫 Android 原生管線，結合音訊峰值與局部 ML Kit。
///
/// 使用方式：
/// ```dart
/// final result = await GolfAnalysisService.analyzeVideo(videoPath: path);
/// if (result != null) {
///   await controller.seekTo(Duration(milliseconds: result.impactTimeMs - 1000));
///   await controller.setPlaybackSpeed(0.25);
/// }
/// ```
class GolfAnalysisService {
  static const _channel =
      MethodChannel('com.example.golf_score_app/golf_analysis');

  /// 快速從音訊軌找出所有擊球時間點（毫秒列表），按時間升序排列。
  ///
  /// 適合長影片「偵測擊球 V2」路徑：不需要跑全幀 ML Kit，數秒內完成。
  ///
  /// - [searchStartMs]：跳過開頭靜音，預設 500ms
  /// - [minGapMs]：兩擊球最小間距，預設 2000ms（防重複）
  /// - [topN]：最多回傳幾個峰值，預設 20
  ///
  /// 無音訊軌或失敗時回傳空 List。
  static Future<List<int>> findAudioPeaks({
    required String videoPath,
    int searchStartMs = 500,
    int minGapMs = 2000,
    int topN = 20,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'findAudioPeaks',
        {
          'videoPath': videoPath,
          'searchStartMs': searchStartMs,
          'minGapMs': minGapMs,
          'topN': topN,
        },
      );
      return raw?.map((e) => (e as num).toInt()).toList() ?? [];
    } catch (e) {
      debugPrint('[GolfAnalysis] findAudioPeaks 失敗: $e');
      return [];
    }
  }

  /// V3 專用：直接用已知的 [candidateMs]（音訊峰值）做局部骨架分析。
  /// 跳過 analyzeVideo 內部的重複音訊偵測，更乾淨高效。
  ///
  /// 骨架分析窗口：[candidateMs - windowMs, candidateMs + windowMs]（共 2×windowMs）
  /// 右腕 Y 最高（螢幕 Y 最大 = 最低點）= 精確 impactTimeMs。
  static Future<GolfAnalysisResult?> analyzeVideoAtCandidate({
    required String videoPath,
    required int candidateMs,
    int windowMs = 3000,
    int maxWidth = 720,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeVideoAtCandidate',
        {
          'videoPath':   videoPath,
          'candidateMs': candidateMs,
          'windowMs':    windowMs,
          'maxWidth':    maxWidth,
        },
      );
      if (raw == null) return null;
      return GolfAnalysisResult(
        impactTimeMs: (raw['impactTimeMs'] as num).toInt(),
        audioPeakMs:  (raw['audioPeakMs']  as num).toInt(),
        hasAudio:     raw['hasAudio']  as bool,
        frameCount:   (raw['frameCount'] as num).toInt(),
        skeletonJson: raw['skeletonJson'] as String,
        videoPath:    raw['videoPath']   as String,
      );
    } on PlatformException catch (e) {
      debugPrint('[GolfAnalysis.V3] analyzeVideoAtCandidate 失敗: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[GolfAnalysis.V3] 未預期錯誤: $e');
      return null;
    }
  }

  /// 分析影片，回傳 [GolfAnalysisResult]；找不到擊球動作或分析失敗時回傳 null。
  ///
  /// - [searchStartMs]：跳過前幾毫秒（排除錄影開始的靜音），預設 500ms
  /// - [searchEndMs]：搜尋到幾毫秒結束，-1 = 搜到結尾
  /// - [windowMs]：在音訊峰值前後各分析幾毫秒，預設 1000ms（共 ≈60 幀 @ 30fps）
  /// - [maxWidth]：ML Kit 輸入最大寬度，預設 720px
  static Future<GolfAnalysisResult?> analyzeVideo({
    required String videoPath,
    int searchStartMs = 500,
    int searchEndMs = -1,
    int windowMs = 1000,
    int maxWidth = 720,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeVideo',
        {
          'videoPath': videoPath,
          'searchStartMs': searchStartMs,
          'searchEndMs': searchEndMs,
          'windowMs': windowMs,
          'maxWidth': maxWidth,
        },
      );
      if (raw == null) return null;

      return GolfAnalysisResult(
        impactTimeMs: (raw['impactTimeMs'] as num).toInt(),
        audioPeakMs:  (raw['audioPeakMs']  as num).toInt(),
        hasAudio:     raw['hasAudio']  as bool,
        frameCount:   (raw['frameCount'] as num).toInt(),
        skeletonJson: raw['skeletonJson'] as String,
        videoPath:    raw['videoPath']   as String,
      );
    } on PlatformException catch (e) {
      if (e.code == 'not_found') {
        debugPrint('[GolfAnalysis] 找不到擊球動作: ${e.message}');
      } else {
        debugPrint('[GolfAnalysis] 分析失敗 (${e.code}): ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('[GolfAnalysis] 未預期錯誤: $e');
      return null;
    }
  }
}
