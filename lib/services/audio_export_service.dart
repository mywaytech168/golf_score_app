import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_analysis_engine.dart';
import 'audio_export_models.dart';

/// 音频导出服务（对标 VideoAnalysisService）
class AudioExportService {
  static const String _logTag = '[AudioExport]';

  /// 从 PCM 样本进行完整分析（简化 API）
  static Future<AudioAnalysisResult?> analyzeFromPcm({
    required List<double> pcmSamples,
    required String sessionDir,
    required int sampleRate,
    required void Function(AudioAnalysisProgress progress)? onProgress,
    double targetHitTime = 3.0,
  }) async {
    try {
      debugPrint('$_logTag 🎵 analyzeFromPcm 開始');
      debugPrint('$_logTag PCM 樣本: ${pcmSamples.length}, 採樣率: $sampleRate, sessionDir: $sessionDir');
      
      if (pcmSamples.isEmpty) {
        debugPrint('$_logTag ❌ PCM 样本为空');
        onProgress?.call(const AudioAnalysisProgress(
          progress: 0,
          message: 'PCM 样本为空',
        ));
        return null;
      }

      final config = AudioAnalysisConfig(
        sessionDir: sessionDir,
        sampleRate: sampleRate,
        targetHitTime: targetHitTime,
        targetTolTime: 0.5,
        peakRelStrength: 0.8,
        madK: 4.0,
        minDistSec: 0.35,
        preSec: 0.1,
        postSec: 0.1,
        bgPercentile: 25,
        ssBeta: 1.0,
        ssFloor: 1e-6,
        saveCsv: true,
        saveTxt: true,
      );

      debugPrint('$_logTag 📋 設定已創建，CSV路徑: ${config.csvPath}');
      debugPrint('$_logTag 📋 TXT路徑: ${config.txtPath}');

      final engine = AudioAnalysisEngine(
        config: config,
        pcmSamples: pcmSamples,
      );

      debugPrint('$_logTag 🔧 引擎已初始化');
      final result = await engine.analyze(onProgress: onProgress);
      debugPrint('$_logTag ✅ 引擎.analyze() 返回: ${result != null ? "結果" : "null"}');

      if (result != null) {
        debugPrint(
          '$_logTag 📊 分析完成: ${result.predictedClass} (${result.feedbackLabel})',
        );
      } else {
        debugPrint('$_logTag ❌ 分析返回空结果');
      }

      return result;
    } catch (e) {
      debugPrint('$_logTag 分析异常: $e');
      onProgress?.call(AudioAnalysisProgress(
        progress: 0,
        message: '分析失败: $e',
      ));
      return null;
    }
  }

  /// 从录制会话导出音频（集成到 RecordingHistoryPage）
  static Future<AudioAnalysisResult?> exportRecordingAudio({
    required String sessionDir,
    required void Function(AudioAnalysisProgress progress)? onProgress,
  }) async {
    try {
      onProgress?.call(const AudioAnalysisProgress(
        progress: 0.1,
        message: '加载音频数据中...',
      ));

      // 1. 加载 PCM
      final pcmFile = File('$sessionDir/audio.pcm');
      if (!await pcmFile.exists()) {
        debugPrint('$_logTag PCM 文件不存在: ${pcmFile.path}');
        onProgress?.call(const AudioAnalysisProgress(
          progress: 0,
          message: 'PCM 文件不存在',
        ));
        return null;
      }

      final bytes = await pcmFile.readAsBytes();
      final pcmSamples = _bytesToSamples(bytes);

      if (pcmSamples.isEmpty) {
        debugPrint('$_logTag 无法转换 PCM 数据');
        onProgress?.call(const AudioAnalysisProgress(
          progress: 0.15,
          message: 'PCM 数据无效',
        ));
        return null;
      }

      debugPrint('$_logTag 加载 PCM: ${bytes.length} 字节 → ${pcmSamples.length} 样本');

      // 2. 分析
      onProgress?.call(const AudioAnalysisProgress(
        progress: 0.2,
        message: '开始分析...',
      ));

      return analyzeFromPcm(
        pcmSamples: pcmSamples,
        sessionDir: sessionDir,
        sampleRate: 44100,
        onProgress: (progress) {
          // 调整进度范围：0.2-1.0
          final adjustedProgress = 0.2 + progress.progress * 0.8;
          onProgress?.call(AudioAnalysisProgress(
            progress: adjustedProgress,
            message: progress.message,
            currentFrame: progress.currentFrame,
            totalFrames: progress.totalFrames,
          ));
        },
      );
    } catch (e) {
      debugPrint('$_logTag 导出异常: $e');
      rethrow;
    }
  }

  /// 将字节转换为浮点样本
  static List<double> _bytesToSamples(Uint8List bytes) {
    try {
      final byteData = bytes.buffer.asByteData();
      final sampleCount = bytes.length ~/ 4;
      final samples = <double>[];

      for (int i = 0; i < sampleCount; i++) {
        final float32 = byteData.getFloat32(i * 4, Endian.little);
        samples.add(float32.toDouble());
      }

      return samples;
    } catch (e) {
      debugPrint('$_logTag 字节转换失败: $e');
      return [];
    }
  }

  /// 清理旧的分析文件
  static Future<void> cleanupOldAnalysis(String sessionDir) async {
    try {
      final csvFile = File('$sessionDir/audio_features.csv');
      final txtFile = File('$sessionDir/audio_analysis.txt');

      if (await csvFile.exists()) await csvFile.delete();
      if (await txtFile.exists()) await txtFile.delete();

      debugPrint('$_logTag 已清理旧分析文件');
    } catch (e) {
      debugPrint('$_logTag 清理失败: $e');
    }
  }
}
