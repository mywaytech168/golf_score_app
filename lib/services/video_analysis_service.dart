import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'analysis_progress_service.dart';

class VideoAnalysisService {
  static const _audioChannel = MethodChannel('audio_extractor_channel');
  static const _poseAnalyzerChannel = MethodChannel('com.example.golf_score_app/pose_analyzer');
  // 採樣率由原生端自主從影片元數據讀取（nominalFrameRate / KEY_FRAME_RATE），
  // Dart 側不再指定 targetFps，避免硬編 30fps 誤導實際採樣行為。

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
        '  音訊: ${hasAudio ? "✅ 已提取" : "ℹ️ 無音訊，略過音訊分析"}${hasSilence ? " ⚠️ 無聲音" : ""}\n'
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
    void listenPose() {
      final (pct, label) = progressSvc.progress.value;
      if (progressSvc.currentOp == 'analyzePose') {
        onProgress?.call(pct * 0.7, label); // scale to 5%–70% of outer range
      }
    }
    progressSvc.progress.addListener(listenPose);
    try {
      final result = await _poseAnalyzerChannel.invokeMethod<Map>(
        'analyzePoseVideo',
        {
          'videoPath': videoPath,
          'outputCsvPath': csvPath,
          // targetFps 不傳：原生端自主從影片 nominalFrameRate/KEY_FRAME_RATE 讀取，
          // 確保 60fps 影片以 60fps 採樣、30fps 影片以 30fps 採樣。
          'maxWidth': 720,
        },
      );
      if (result == null || result['status'] != 'completed') {
        throw Exception('骨架分析失敗: $result');
      }
    } finally {
      progressSvc.progress.removeListener(listenPose);
    }
    onProgress?.call(0.75, '骨架分析完成');
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

  /// 提取音訊並保存為 WAV。
  /// 影片無音訊軌時回傳 false（不拋例外）。
  Future<bool> _extractAudio({
    required String videoPath,
    required String audioPath,
  }) async {
    final result = await _audioChannel.invokeMethod<Map>('extractAudio', {
      'videoPath': videoPath,
    });
    if (result == null) return false;

    // 無音訊軌 — native 回傳 no_audio:true，屬正常情況，非錯誤
    if (result['no_audio'] == true) {
      debugPrint('[VideoAnalysis] ℹ️ 影片無音訊軌，略過音訊提取');
      return false;
    }

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
