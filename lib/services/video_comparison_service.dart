import 'package:flutter/services.dart';

class VideoComparisonService {
  static const _channel = MethodChannel('com.example.golf_score_app/comparison');

  /// 預渲染並排比較影片。
  ///
  /// [pathA] / [pathB]    兩段輸入影片
  /// [outputPath]         輸出合成 MP4 路徑
  /// [hitSecA] / [hitSecB] 各影片的擊球時刻（秒），用於對軸對齊，預設 0
  ///
  /// 回傳 true 表示成功，false 或拋出例外表示失敗。
  Future<bool> renderComparison({
    required String pathA,
    required String pathB,
    required String outputPath,
    double hitSecA = 0.0,
    double hitSecB = 0.0,
  }) async {
    final result = await _channel.invokeMethod<bool>('renderComparison', {
      'pathA': pathA,
      'pathB': pathB,
      'outputPath': outputPath,
      'hitSecA': hitSecA,
      'hitSecB': hitSecB,
    });
    return result ?? false;
  }
}
