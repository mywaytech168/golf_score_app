import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;

import '../recording/pose_csv_writer.dart';
import '../recording/pose_detector_service.dart';
import '../recording/pose_frame_model.dart';
import 'analysis_progress_service.dart';

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
        // 無論音軌提取是否成功都跑靜默偵測：
        // - 提取失敗 → WAV 不存在 → _detectSilence 回傳 true（無音軌 = 靜默）
        // - 提取成功 → 分析 WAV 振幅
        hasSilence = await _detectSilence(audioPath: audioPath);
        if (hasSilence) {
          debugPrint('[VideoAnalysis] ⚠️ 【無聲音】${hasAudio ? "音訊靜默" : "無音軌"}');
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
    final progressSvc = AnalysisProgressService.instance;
    progressSvc.reset('分析骨架中...');
    void _listenPose() {
      final (pct, label) = progressSvc.progress.value;
      if (progressSvc.currentOp == 'analyzePose') {
        onProgress?.call(pct * 0.7, label); // scale to 5%–70% of outer range
      }
    }
    progressSvc.progress.addListener(_listenPose);
    try {
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
    } finally {
      progressSvc.progress.removeListener(_listenPose);
    }
    onProgress?.call(0.75, '骨架分析完成');
  }

  // ignore: unused_element — 保留供日後 fallback 使用
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
    const double imgW = 720, imgH = 1280;
    const batchSize = 4;

    final overallSw = Stopwatch()..start();
    var processedFrames = 0;
    var successFrames = 0;
    var successBatches = 0;
    int poseUpdateId = 0;
    // 只保留「上一幀」用於比對 pose 是否更新，不累積全部幀
    PoseFrameModel? prevFrame;

    // 步驟 1️⃣: 收集所有幀時間戳
    final frameTimestamps = <int>[];
    for (var ms = 0; ms < totalMs; ms += _frameIntervalMs) {
      frameTimestamps.add(ms);
    }

    debugPrint('[VideoAnalysis] 配置: ${frameTimestamps.length} 幀, ${_frameIntervalMs}ms 間隔, $batchSize 幀/批次');

    for (int batchStart = 0; batchStart < frameTimestamps.length; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize).clamp(0, frameTimestamps.length);
      final batchFrames = frameTimestamps.sublist(batchStart, batchEnd);

      final futures = <Future<PoseFrameModel>>[];
      for (int i = 0; i < batchFrames.length; i++) {
        futures.add(_processFrameAsync(
          videoPath: videoPath,
          timeMs: batchFrames[i],
          frameIndex: batchStart + i,
          imgW: imgW,
          imgH: imgH,
          poseService: poseService,
          poseUpdateId: poseUpdateId,
        ));
      }

      try {
        final batchResults = await Future.wait(futures);
        // 逐幀比對後立即寫入 CSV，不累積到 List
        for (final frame in batchResults) {
          bool isSamePose = false;
          if (prevFrame != null) {
            isSamePose = true;
            for (int i = 0; i < 33; i++) {
              final pa = prevFrame!.landmarks[i];
              final pb = frame.landmarks[i];
              if ((pa.xPx - pb.xPx).abs() > 0.01 ||
                  (pa.yPx - pb.yPx).abs() > 0.01 ||
                  (pa.z - pb.z).abs() > 0.01) {
                isSamePose = false;
                break;
              }
            }
          }
          if (!isSamePose) poseUpdateId++;
          prevFrame = frame;
          writer.addFrame(frame);
          successFrames++;
        }
        successBatches++;
        processedFrames += batchFrames.length;
        onProgress?.call(processedFrames / totalSteps);
      } catch (e) {
        debugPrint('[VideoAnalysis] 批次 $batchStart-$batchEnd 失敗: $e');
      }
    }
    await writer.flush();
    overallSw.stop();

    final framesPerSec = successFrames > 0 && overallSw.elapsedMilliseconds > 0
        ? (successFrames * 1000 / overallSw.elapsedMilliseconds).toStringAsFixed(2)
        : 'N/A';
    debugPrint(
      '[VideoAnalysis] 統計:\n'
      '  總時間: ${overallSw.elapsedMilliseconds}ms\n'
      '  成功幀: $successFrames/${frameTimestamps.length}\n'
      '  批次: $successBatches 成功\n'
      '  吞吐率: $framesPerSec fps',
    );
    debugPrint('[VideoAnalysis] 並行分析完成: $successFrames 幀 → $csvPath');
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

  /// 從已存在的 WAV 路徑直接檢測靜默（供外部在跳過 pose 分析時使用）
  Future<bool> checkSilence({required String wavPath}) => _detectSilence(audioPath: wavPath);

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

      Uint8List? wavBytes = await wavFile.readAsBytes();
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

      if (dataStart >= wavBytes.length) {
        debugPrint('[VideoAnalysis] ⚠️ 【無聲音】WAV data 為空');
        return true;
      }

      // 分析音訊幅度：計算 RMS 和峰值（直接索引，不建立 sublist 副本）
      double rmsSum = 0.0;
      double peakVal = 0.0;
      int sampleCount = 0;
      final wavLen = wavBytes.length;

      for (int i = dataStart; i + 1 < wavLen; i += 2) {
        final int16 = wavBytes[i] | (wavBytes[i + 1] << 8);
        final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
        final normalized = signedInt16 / 32768.0;
        rmsSum += normalized * normalized;
        if (normalized.abs() > peakVal) peakVal = normalized.abs();
        sampleCount++;
      }

      // 釋放 WAV 原始資料
      wavBytes = null;

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
