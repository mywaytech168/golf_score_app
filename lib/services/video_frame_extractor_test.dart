import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 簡單測試 VideoFrameExtractor 性能
class VideoFrameExtractorTest {
  static const _frameExtractorChannel =
      MethodChannel('com.example.golf_score_app/frame_extractor');

  /// 測試 VideoFrameExtractor 的幀提取性能
  static Future<void> testFrameExtraction({
    required String videoPath,
    required int numFrames,
    void Function(int frameNum, double timeMs)? onFrameExtracted,
  }) async {
    print('[Test] 開始測試 VideoFrameExtractor');
    print('[Test] 視頻路徑: $videoPath');
    print('[Test] 測試幀數: $numFrames');

    int successCount = 0;
    int failCount = 0;
    double totalTimeMs = 0;

    // 測試 5 幀 @ 67ms 間隔
    for (int i = 0; i < numFrames; i++) {
      final timeMs = i * 67;
      final sw = Stopwatch()..start();

      try {
        final result = await _frameExtractorChannel.invokeMethod(
          'extractFrameRgb',
          {
            'videoPath': videoPath,
            'timeMs': timeMs,
            'maxWidth': 720,
          },
        ) as Map<dynamic, dynamic>?;

        sw.stop();

        if (result != null) {
          final width = result['width'] as int;
          final height = result['height'] as int;
          final pixels = result['pixels'] as Uint8List;

          print('[Test] ✅ 幀 $i: ${sw.elapsedMilliseconds}ms | '
              '${width}x$height | ${pixels.length} bytes');
          totalTimeMs += sw.elapsedMilliseconds;
          successCount++;
          onFrameExtracted?.call(i, sw.elapsedMilliseconds.toDouble());
        } else {
          print('[Test] ❌ 幀 $i: 結果為 null');
          failCount++;
        }
      } catch (e) {
        sw.stop();
        print('[Test] ❌ 幀 $i: 錯誤 - $e');
        failCount++;
      }
    }

    final avgTimeMs = successCount > 0 ? totalTimeMs / successCount : 0;
    print('[Test] ━━━━━━━━━━━━━━━━━━━━━━');
    print('[Test] 成功: $successCount, 失敗: $failCount');
    print('[Test] 平均時間: ${avgTimeMs.toStringAsFixed(1)}ms/幀');
    print('[Test] 總時間: ${totalTimeMs.toStringAsFixed(1)}ms');
    print('[Test] ✅ 測試完成');
  }

  /// 測試完整的 ML Kit 推理流程
  static Future<void> testFullPipeline({
    required String videoPath,
    required int numFrames,
    void Function(int frameNum, double extractMs, double inferMs)?
        onProcessed,
  }) async {
    print('[Test] 開始測試完整推理流程 (幀提取 + ML Kit)');

    final poseDetector = PoseDetector(options: PoseDetectorOptions());

    try {
      int successCount = 0;
      double totalExtractMs = 0;
      double totalInferMs = 0;

      for (int i = 0; i < numFrames; i++) {
        final timeMs = i * 67;

        // 步驟 1: 提取幀
        final extractSw = Stopwatch()..start();
        final result = await _frameExtractorChannel.invokeMethod(
          'extractFrameRgb',
          {
            'videoPath': videoPath,
            'timeMs': timeMs,
            'maxWidth': 720,
          },
        ) as Map<dynamic, dynamic>?;
        extractSw.stop();

        if (result == null) {
          print('[Test] ❌ 幀 $i: 提取失敗');
          continue;
        }

        final width = result['width'] as int;
        final height = result['height'] as int;
        final pixels = result['pixels'] as Uint8List;

        // 步驟 2: 轉換為 InputImage
        final inputImage = InputImage.fromBytes(
          bytes: pixels,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: width * 4,
          ),
        );

        // 步驟 3: ML Kit 推理
        final inferSw = Stopwatch()..start();
        final poses = await poseDetector.processImage(inputImage);
        inferSw.stop();

        final extractMs = extractSw.elapsedMilliseconds;
        final inferMs = inferSw.elapsedMilliseconds;
        final totalMs = extractMs + inferMs;

        print('[Test] 幀 $i: 提取=${extractMs}ms + 推理=${inferMs}ms = ${totalMs}ms');

        if (poses.isNotEmpty) {
          print('[Test]   └─ 檢測到 ${poses.first.landmarks.length} 個關鍵點');
        }

        totalExtractMs += extractMs;
        totalInferMs += inferMs;
        successCount++;

        onProcessed?.call(i, extractMs.toDouble(), inferMs.toDouble());
      }

      if (successCount > 0) {
        final avgExtractMs = totalExtractMs / successCount;
        final avgInferMs = totalInferMs / successCount;
        final avgTotalMs = (totalExtractMs + totalInferMs) / successCount;

        print('[Test] ━━━━━━━━━━━━━━━━━━━━━━');
        print('[Test] 成功幀數: $successCount');
        print('[Test] 平均提取時間: ${avgExtractMs.toStringAsFixed(1)}ms');
        print('[Test] 平均推理時間: ${avgInferMs.toStringAsFixed(1)}ms');
        print('[Test] 平均總時間: ${avgTotalMs.toStringAsFixed(1)}ms');
        print('[Test] ✅ 完整流程測試完成');
      }
    } finally {
      await poseDetector.close();
    }
  }
}
