import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../recording/pose_csv_writer.dart';
import '../recording/pose_detector_service.dart';
import '../recording/pose_frame_model.dart';

class VideoAnalysisService {
  static const _audioChannel = MethodChannel('audio_extractor_channel');
  static const _poseAnalyzerChannel = MethodChannel('com.example.golf_score_app/pose_analyzer');
  static const _frameExtractorChannel = MethodChannel('com.example.golf_score_app/frame_extractor');
  static const _frameIntervalMs = 33; // ~30fps（與 SkeletonOverlayRenderer.ANALYSIS_INTERVAL_MS 一致）

  Future<VideoAnalysisResult> analyze({
    required String videoPath,
    required String sessionDir,
    required int durationSeconds,
    void Function(double progress, String label)? onProgress,
  }) async {
    final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
    final audioPath = p.join(sessionDir, 'audio.wav');
    final overallSw = Stopwatch()..start();

    try {
      await _analyzePoseNative(
        videoPath: videoPath,
        csvPath: csvPath,
        onProgress: onProgress,
      );

      onProgress?.call(0.75, '提取音訊中...');
      bool hasAudio = false;
      bool hasSilence = false;
      try {
        hasAudio = await _extractAudio(videoPath: videoPath, audioPath: audioPath);
        if (hasAudio) {
          hasSilence = await _detectSilence(audioPath: audioPath);
          if (hasSilence) {
            debugPrint('[VideoAnalysis] ⚠️ 【無聲音】音訊檔案存在但無聲音數據');
          }
        }
      } catch (e) {
        debugPrint('[VideoAnalysis] audio extraction failed: $e');
      }

      onProgress?.call(1.0, '完成');
      
      // 📊 收集骨架統計
      final (validFrames, totalFrames) = await _analyzeSkeletonStats(csvPath);
      
      overallSw.stop();
      
      // 📊 總結報告
      final fps = totalFrames > 0 && overallSw.elapsedMilliseconds > 0
        ? (totalFrames * 1000 / overallSw.elapsedMilliseconds).toStringAsFixed(2)
        : 'N/A';
      
      debugPrint(
        '[VideoAnalysis] 📊 完成統計:\n'
        '  骨架: $validFrames/$totalFrames 幀有效\n'
        '  音訊: ${hasAudio ? "✅ 已提取" : "❌ 無音訊"}${hasSilence ? " ⚠️ 無聲音" : ""}\n'
        '  總時間: ${overallSw.elapsedMilliseconds}ms\n'
        '  吞吐率: $fps fps'
      );
      
      return VideoAnalysisResult(
        csvPath: csvPath,
        audioPath: hasAudio ? audioPath : '',
        totalFrames: totalFrames,
        validFrames: validFrames,
        totalTimeMs: overallSw.elapsedMilliseconds,
        framesPerSecond: double.tryParse(fps) ?? 0.0,
        hasAudio: hasAudio,
        hasSilence: hasSilence,
      );
    } catch (e) {
      overallSw.stop();
      debugPrint('[VideoAnalysis] ❌ 分析失敗: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────
  // Kotlin 原生分析路徑（單一 MethodChannel 呼叫）
  // 比舊的 per-frame extractFrameRgb 快 3-5x：
  //   舊：152 次 JNI 呼叫 × (150ms open + 30ms 轉換 + 15ms 傳輸 + 100ms ML Kit) ≈ 45s
  //   新：1 次呼叫，Kotlin 內部 sequential decode → NV21 → ML Kit，全程無 JNI 往返 ≈ 10-15s
  // ──────────────────────────────────────────────────────
  Future<void> _analyzePoseNative({
    required String videoPath,
    required String csvPath,
    void Function(double progress, String label)? onProgress,
  }) async {
    onProgress?.call(0.05, '分析骨架中...');
    final result = await _poseAnalyzerChannel.invokeMethod<Map>(
      'analyzePoseVideo',
      {
        'videoPath': videoPath,
        'outputCsvPath': csvPath,
        'targetFps': 1000 ~/ _frameIntervalMs, // 30fps
        'maxWidth': 720,
      },
    );
    if (result == null || result['status'] != 'completed') {
      throw Exception('Kotlin 骨架分析失敗: $result');
    }
    onProgress?.call(0.75, '骨架分析完成');
  }

  // ── 以下保留供相容，已不被 analyze() 呼叫 ──────────────
  Future<void> _analyzePose({
    required String videoPath,
    required String csvPath,
    required int durationSeconds,
    required PoseDetectorService poseService,
    void Function(double)? onProgress,
  }) async {
    final writer = PoseCsvWriter(csvPath);
    final totalMs = durationSeconds * 1000;
    final totalSteps = (totalMs / _frameIntervalMs).ceil().clamp(1, 99999);
    double imgW = 720, imgH = 1280;

    // 📊 並行優化: 同時處理多幀以提升性能 (預期 3x 改進: 20-32s → 7-11s)
    const batchSize = 4; // 同時處理 4 幀
    final List<PoseFrameModel> allFrames = [];
    var processedFrames = 0;

    // ⏱️ 性能統計
    final overallSw = Stopwatch()..start();
    final batchTimings = <int, Duration>{};
    var successBatches = 0;

    // 步驟 1️⃣: 收集所有幀時間戳
    final frameTimestamps = <int>[];
    for (var ms = 0; ms < totalMs; ms += _frameIntervalMs) {
      frameTimestamps.add(ms);
    }

    debugPrint('[VideoAnalysis] 📊 配置: ${frameTimestamps.length} 幀, ${_frameIntervalMs}ms 間隔, $batchSize 幀/批次');
    // 步驟 2️⃣: 並行批量處理幀
    debugPrint('[VideoAnalysis] 開始並行分析 ($batchSize 幀/批次, ${frameTimestamps.length} 幀總數)');

    int poseUpdateId = 0;  // ✅ 追踪骨架是否真正更新

    for (int batchStart = 0; batchStart < frameTimestamps.length; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize).clamp(0, frameTimestamps.length);
      final batchFrames = frameTimestamps.sublist(batchStart, batchEnd);

      // ⏱️ 批次計時
      final batchSw = Stopwatch()..start();

      // 並行處理這批幀
      final futures = <Future<PoseFrameModel>>[];
      for (int i = 0; i < batchFrames.length; i++) {
        final ms = batchFrames[i];
        final frameIndex = batchStart + i;

        futures.add(_processFrameAsync(
          videoPath: videoPath,
          timeMs: ms,
          frameIndex: frameIndex,
          imgW: imgW,
          imgH: imgH,
          poseService: poseService,
          poseUpdateId: poseUpdateId,  // ✅ 傳遞
        ));
      }

      // 等待批次完成
      try {
        final batchResults = await Future.wait(futures);
        for (final frame in batchResults) {
          // ✅ 改進：只在「完整骨架真的變」時才增加 poseUpdateId
          bool isSamePose = false;
          if (allFrames.isNotEmpty) {
            final prev = allFrames.last;
            // 比較完整 33 點骨架
            isSamePose = true;
            for (int i = 0; i < 33; i++) {
              final pa = prev.landmarks[i];
              final pb = frame.landmarks[i];
              
              if ((pa.xPx - pb.xPx).abs() > 0.01 ||
                  (pa.yPx - pb.yPx).abs() > 0.01 ||
                  (pa.z - pb.z).abs() > 0.01) {
                isSamePose = false;
                break;
              }
            }
          } else {
            isSamePose = false;  // 第一幀總是新的
          }
          
          if (!isSamePose) {
            poseUpdateId++;  // 只在真的變時才加
          }
          
          allFrames.add(frame);
        }

        batchSw.stop();
        batchTimings[batchStart] = batchSw.elapsed;
        successBatches++;
        final avgMs = batchSw.elapsedMilliseconds / batchFrames.length;
        debugPrint('[Batch ${batchStart ~/ batchSize + 1}] ✅ ${batchFrames.length} 幀完成: ${batchSw.elapsedMilliseconds}ms (平均 ${avgMs.toStringAsFixed(1)}ms/幀)');

        processedFrames += batchFrames.length;
        onProgress?.call(processedFrames / totalSteps);
      } catch (e) {
        batchSw.stop();
        debugPrint('[VideoAnalysis] 批次 $batchStart-$batchEnd 失敗: $e');
        // 繼續處理下一批
      }
    }

    // 步驟 3️⃣: 按順序寫入 CSV
    debugPrint('[VideoAnalysis] 寫入 ${allFrames.length} 幀到 CSV...');
    for (final frame in allFrames) {
      writer.addFrame(frame);
    }

    await writer.flush();
    overallSw.stop();

    // � 骨架數據驗證 - 檢測是否所有幀相同
    if (allFrames.isNotEmpty) {
      final firstLm16X = allFrames.first.landmarks[16].xPx;
      final firstLm16Y = allFrames.first.landmarks[16].yPx;
      
      int unchangedCount = 0;
      for (final frame in allFrames) {
        if (frame.landmarks[16].xPx == firstLm16X && frame.landmarks[16].yPx == firstLm16Y) {
          unchangedCount++;
        }
      }
      
      if (unchangedCount == allFrames.length) {
        debugPrint('[VideoAnalysis] 🚨 警告：所有 ${allFrames.length} 幀的右手腕坐標完全相同！');
        debugPrint('[VideoAnalysis]   右手腕 (${firstLm16X.toStringAsFixed(1)}, ${firstLm16Y.toStringAsFixed(1)})');
        debugPrint('[VideoAnalysis]   💡 可能的原因：');
        debugPrint('[VideoAnalysis]      1. 幀提取失敗，所有幀都是相同的圖像');
        debugPrint('[VideoAnalysis]      2. ML Kit Pose 檢測返回相同結果');
        debugPrint('[VideoAnalysis]      3. 視頻本身是靜止畫面');
      } else {
        final minX = allFrames.map((f) => f.landmarks[16].xPx).reduce((a, b) => a < b ? a : b);
        final maxX = allFrames.map((f) => f.landmarks[16].xPx).reduce((a, b) => a > b ? a : b);
        final minY = allFrames.map((f) => f.landmarks[16].yPx).reduce((a, b) => a < b ? a : b);
        final maxY = allFrames.map((f) => f.landmarks[16].yPx).reduce((a, b) => a > b ? a : b);
        debugPrint('[VideoAnalysis] ✅ 骨架正常：右手腕移動範圍 X=[${minX.toStringAsFixed(1)}, ${maxX.toStringAsFixed(1)}], Y=[${minY.toStringAsFixed(1)}, ${maxY.toStringAsFixed(1)}]');
      }
      
      // ✅ 新增：檢查完整骨架（33點）是否重複
      int repeatedFullPoseCount = 0;
      int changedFullPoseCount = 0;
      
      bool isSameFullPose(int frameA, int frameB) {
        for (int i = 0; i < 33; i++) {
          final pa = allFrames[frameA].landmarks[i];
          final pb = allFrames[frameB].landmarks[i];
          
          if ((pa.xPx - pb.xPx).abs() > 0.01 ||
              (pa.yPx - pb.yPx).abs() > 0.01 ||
              (pa.z - pb.z).abs() > 0.01) {
            return false;
          }
        }
        return true;
      }
      
      for (int i = 1; i < allFrames.length; i++) {
        if (isSameFullPose(i - 1, i)) {
          repeatedFullPoseCount++;
        } else {
          changedFullPoseCount++;
        }
      }
      
      final repeatRate = repeatedFullPoseCount / math.max(1, allFrames.length - 1);
      debugPrint('[VideoAnalysis] 📊 完整骨架重複幀比例: ${(repeatRate * 100).toStringAsFixed(1)}%');
      debugPrint('[VideoAnalysis]   changed=$changedFullPoseCount, repeated=$repeatedFullPoseCount');
      
      if (repeatRate > 0.5) {
        debugPrint('[VideoAnalysis] ⚠️ 骨架更新頻率異常，可能是重複使用上一幀 landmarks');
      }
      
      // ✅ 新增：pose_update_id 統計
      final uniqueUpdateIds = allFrames.map((f) => f.poseUpdateId).toSet().length;
      debugPrint('[VideoAnalysis] 📊 骨架更新次數: $uniqueUpdateIds (${allFrames.length} 幀)');
    }

    // �📊 統計報告
    final avgBatchMs = batchTimings.isNotEmpty
        ? batchTimings.values.fold<int>(0, (s, d) => s + d.inMilliseconds) / batchTimings.length
        : 0;
    final framesPerSec = allFrames.length > 0 && overallSw.elapsedMilliseconds > 0
        ? (allFrames.length * 1000 / overallSw.elapsedMilliseconds).toStringAsFixed(2)
        : 'N/A';

    debugPrint(
      '[VideoAnalysis] 📊 統計:\n'
      '  總時間: ${overallSw.elapsedMilliseconds}ms\n'
      '  成功幀: ${allFrames.length}/${frameTimestamps.length}\n'
      '  批次: $successBatches 成功\n'
      '  平均批次時間: ${avgBatchMs.toStringAsFixed(1)}ms\n'
      '  吞吐率: $framesPerSec fps',
    );
    debugPrint('[VideoAnalysis] ✅ 並行分析完成: ${allFrames.length} 幀 → $csvPath');
  }

  /// 讀取 CSV 並統計有效的骨架幀
  Future<(int validFrames, int totalFrames)> _analyzeSkeletonStats(String csvPath) async {
    try {
      final file = File(csvPath);
      if (!file.existsSync()) {
        return (0, 0);
      }
      
      final lines = await file.readAsLines();
      int validCount = 0;
      int totalCount = 0;
      
      // 跳過 header
      for (int i = 1; i < lines.length; i++) {
        final parts = lines[i].split(',');
        if (parts.length < 3) continue;
        
        totalCount++;
        try {
          final meanConf = double.tryParse(parts[2]) ?? 0.0;
          if (meanConf > 0.0) {
            validCount++;
          }
        } catch (e) {
          continue;
        }
      }
      
      debugPrint('[VideoAnalysis] 骨架統計: $validCount/$totalCount 幀有效');
      return (validCount, totalCount);
    } catch (e) {
      debugPrint('[VideoAnalysis] 骨架統計讀取失敗: $e');
      return (0, 0);
    }
  }

  /// 異步處理單個幀 (供並行調用)
  Future<PoseFrameModel> _processFrameAsync({
    required String videoPath,
    required int timeMs,
    required int frameIndex,
    required double imgW,
    required double imgH,
    required PoseDetectorService poseService,
    required int poseUpdateId,
  }) async {
    try {
      // 1️⃣ 呼叫 Kotlin VideoFrameExtractor 直接解碼為 RGB
      final result = await _frameExtractorChannel.invokeMethod(
        'extractFrameRgb',
        {
          'videoPath': videoPath,
          'timeMs': timeMs,
          'maxWidth': 720,
        },
      ) as Map<dynamic, dynamic>?;

      if (result == null) {
        debugPrint('[Frame] ❌ 幀 $frameIndex: 提取失敗 (null)');
        return PoseFrameModel.empty(
          frame: frameIndex,
          timeSec: timeMs / 1000.0,
          poseUpdateId: poseUpdateId,
        );
      }

      final width = result['width'] as int;
      final height = result['height'] as int;
      final pixelBytes = result['pixels'] as Uint8List;

      // ✅ 檢查 NV21 字節數
      final expectedBytes = (width * height * 1.5).toInt();
      if (pixelBytes.length != expectedBytes) {
        debugPrint('[Frame] ❌ 幀 $frameIndex: NV21 字節數不匹配');
        debugPrint('  期望: $expectedBytes bytes');
        debugPrint('  實際: ${pixelBytes.length} bytes');
        return PoseFrameModel.empty(
          frame: frameIndex,
          timeSec: timeMs / 1000.0,
          poseUpdateId: poseUpdateId,
        );
      }

      // ✅ 診斷：計算 pixelBytes checksum（檢查資料是否重複）
      int checksum = 0;
      final step = math.max(1, pixelBytes.length ~/ 1000);
      for (int i = 0; i < pixelBytes.length; i += step) {
        checksum = (checksum + pixelBytes[i]) & 0xFFFFFFFF;
      }
      debugPrint('[FrameCheck] frame=$frameIndex timeMs=$timeMs checksum=$checksum');

      debugPrint('[Frame] 🎬 幀 $frameIndex (${timeMs}ms): ${width}x${height}, ${pixelBytes.length} bytes ✓');

      // 2️⃣ 將 byte array 轉為 InputImage (使用 NV21 YUV 格式)
      InputImage inputImage;
      try {
        inputImage = InputImage.fromBytes(
          bytes: pixelBytes,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: width,
          ),
        );
      } catch (e) {
        debugPrint('[Frame] ❌ 幀 $frameIndex: InputImage 轉換失敗 - $e');
        return PoseFrameModel.empty(
          frame: frameIndex,
          timeSec: timeMs / 1000.0,
          poseUpdateId: poseUpdateId,
        );
      }

      // 3️⃣ ML Kit 推理
      final poses = await poseService.detect(inputImage);

      if (poses.isEmpty) {
        debugPrint('[Frame] ⚠️ 幀 $frameIndex: Pose 推理無結果');
        return PoseFrameModel.empty(
          frame: frameIndex,
          timeSec: timeMs / 1000.0,
          poseUpdateId: poseUpdateId,
        );
      }

      // 驗證骨架是否正常
      final pose = poses.first;
      final lm16 = pose.landmarks[PoseLandmarkType.rightWrist];
      if (lm16 != null) {
        debugPrint('[Frame] ✅ 幀 $frameIndex: 右手腕 (${lm16.x.toStringAsFixed(1)}, ${lm16.y.toStringAsFixed(1)}), 信心=${lm16.likelihood.toStringAsFixed(3)}');
      }

      return PoseFrameModel.fromPose(
        frame: frameIndex,
        timeSec: timeMs / 1000.0,
        poseUpdateId: poseUpdateId,
        pose: pose,
        imgWidth: imgW,
        imgHeight: imgH,
      );
    } catch (e) {
      debugPrint('[Frame] ❌ 幀 $frameIndex: 異常 - $e');
      return PoseFrameModel.empty(
        frame: frameIndex,
        timeSec: timeMs / 1000.0,
        poseUpdateId: poseUpdateId,
      );
    }
  }

  /// 提取音訊並保存為 WAV
  Future<bool> _extractAudio({
    required String videoPath,
    required String audioPath,
  }) async {
    final result = await _audioChannel.invokeMethod<Map>('extractAudio', {
      'videoPath': videoPath,
    });
    if (result == null) return false;

    final wavPath = result['path'] as String?;
    if (wavPath == null) return false;

    final wavFile = File(wavPath);
    if (!await wavFile.exists()) return false;

    // 直接复制 WAV 文件（改为 .wav 扩展名）
    try {
      await wavFile.copy(audioPath);
      debugPrint('[VideoAnalysis] audio done: $audioPath');
      return true;
    } catch (e) {
      debugPrint('[VideoAnalysis] audio copy failed: $e');
      return false;
    } finally {
      try { await wavFile.delete(); } catch (_) {}
    }
  }

  /// 檢測音訊是否為無聲音（靜默）
  Future<bool> _detectSilence({
    required String audioPath,
  }) async {
    try {
      final wavFile = File(audioPath);
      if (!await wavFile.exists()) {
        debugPrint('[VideoAnalysis] ⚠️ 音訊檔案不存在: $audioPath');
        return true; // 無檔案 = 無聲音
      }

      final wavBytes = await wavFile.readAsBytes();
      debugPrint('[VideoAnalysis] 🔊 檢測音訊: ${wavBytes.length} bytes');

      if (wavBytes.length < 44) {
        debugPrint('[VideoAnalysis] ⚠️ 【無聲音】WAV 檔案過小 (${wavBytes.length} < 44 bytes)');
        return true;
      }

      // 尋找 data chunk
      int dataStart = 44;
      for (int i = 36; i < wavBytes.length - 8; i++) {
        if (wavBytes[i] == 100 && wavBytes[i + 1] == 97 &&
            wavBytes[i + 2] == 116 && wavBytes[i + 3] == 97) {
          dataStart = i + 8;
          break;
        }
      }

      final audioDataBytes = wavBytes.sublist(dataStart);
      if (audioDataBytes.isEmpty) {
        debugPrint('[VideoAnalysis] ⚠️ 【無聲音】WAV data 為空');
        return true;
      }

      // 分析音訊幅度：計算 RMS 和峰值
      double rmsSum = 0.0;
      double peakVal = 0.0;
      int sampleCount = 0;

      for (int i = 0; i < audioDataBytes.length - 1; i += 2) {
        final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);
        final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
        final normalized = signedInt16 / 32768.0;
        rmsSum += normalized * normalized;
        if (normalized.abs() > peakVal) peakVal = normalized.abs();
        sampleCount++;
      }

      final rms = math.sqrt(rmsSum / sampleCount);
      debugPrint('[VideoAnalysis] 🔊 音訊分析: RMS=${rms.toStringAsFixed(4)}, Peak=${peakVal.toStringAsFixed(4)}, Samples=$sampleCount');

      // 判定無聲音閾值：RMS < 0.01 且峰值 < 0.05
      final isSilent = rms < 0.01 && peakVal < 0.05;
      if (isSilent) {
        debugPrint('[VideoAnalysis] ⚠️ 【無聲音】RMS=${rms.toStringAsFixed(4)} < 0.01, Peak=${peakVal.toStringAsFixed(4)} < 0.05');
      }
      return isSilent;
    } catch (e) {
      debugPrint('[VideoAnalysis] ❌ 無聲音檢測失敗: $e');
      return false;
    }
  }
}

class VideoAnalysisResult {
  final String csvPath;
  final String audioPath;
  final int totalFrames;
  final int validFrames;
  final int totalTimeMs;
  final int poseProcessTimeMs;
  final double framesPerSecond;
  final bool hasAudio;
  final bool hasSilence;
  
  const VideoAnalysisResult({
    required this.csvPath,
    required this.audioPath,
    this.totalFrames = 0,
    this.validFrames = 0,
    this.totalTimeMs = 0,
    this.poseProcessTimeMs = 0,
    this.framesPerSecond = 0.0,
    this.hasAudio = false,
    this.hasSilence = false,
  });
}
