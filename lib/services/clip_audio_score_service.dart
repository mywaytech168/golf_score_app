import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import 'audio_export_models.dart';
import 'audio_export_service.dart';
import 'audio_extraction_service.dart';

/// 切片音訊 5 特徵評分共用服務。
///
/// 由 recording_history_page 的 _analyzeWavFile 抽出，供三處共用：
///   1. 歷史頁「完整分析」Stage 2
///   2. SHOT 模式每桿切片後即時評分
///   3. 偵測擊球 / 錄影自動切片（SwingAutoClipService.analyzeClipEntry）
class ClipAudioScoreService {
  /// 讀取 sessionDir/audio.wav（不存在則從 clipPath 萃取），解析 PCM 並回傳音訊分析結果。
  /// [targetHitTime] 為擊球時刻相對 clip 起點的秒數，傳入可提升分析精度。
  /// 失敗或無音訊時回傳 null，內部捕捉例外不向外拋。
  static Future<AudioAnalysisResult?> analyzeWav({
    required String sessionDir,
    required String clipPath,
    double? targetHitTime,
    void Function(double progress, String message)? onProgress,
  }) async {
    final wavFile = File(p.join(sessionDir, 'audio.wav'));
    var wavExists = await wavFile.exists();

    if (!wavExists) {
      onProgress?.call(0.72, '提取音頻中...');
      final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
        videoPath: clipPath,
        outputWavPath: wavFile.path,
        onProgress: (progress, message) {
          onProgress?.call(0.72 + progress * 0.08, message);
        },
      );
      if (samplesExtracted > 0) wavExists = await wavFile.exists();
    }

    if (!wavExists) return null;

    try {
      final bytes = await wavFile.readAsBytes();
      if (bytes.length < 44) return null;

      final wavHd         = bytes.buffer.asByteData();
      final wavChannels   = wavHd.getUint16(22, Endian.little);
      final wavSampleRate = wavHd.getUint32(24, Endian.little);
      final wavBlockAlign = wavHd.getUint16(32, Endian.little);
      final wavBits       = wavHd.getUint16(34, Endian.little);

      // 下方 PCM 解析以 16-bit 寫死（每 channel 2 bytes）；原生提取器兩平台
      // 皆保證輸出 16-bit，此防呆攔截未來換實作或外部 WAV 流入的情況。
      if (wavBits != 16) {
        debugPrint('[音頻分析] 不支援的位深 $wavBits-bit（僅 16-bit PCM），略過評分');
        return null;
      }

      // 掃描 'data' chunk，跳過可能的中繼 chunks
      int dataStart = 44;
      for (int i = 36; i < bytes.length - 8; i++) {
        if (bytes[i] == 100 && bytes[i+1] == 97 && bytes[i+2] == 116 && bytes[i+3] == 97) {
          dataStart = i + 8;
          break;
        }
      }

      final stride = wavBlockAlign > 0 ? wavBlockAlign : 2;
      final audioDataLen = bytes.length - dataStart;
      final pcmSamples = <double>[];
      for (int i = 0; i + stride <= audioDataLen; i += stride) {
        double frameVal = 0.0;
        for (int ch = 0; ch < wavChannels; ch++) {
          final offset = dataStart + i + ch * 2;
          if (offset + 1 >= bytes.length) break;
          final raw    = bytes[offset] | (bytes[offset + 1] << 8);
          final signed = (raw > 32767) ? raw - 65536 : raw;
          frameVal += signed / 32768.0;
        }
        pcmSamples.add(frameVal / wavChannels);
      }

      if (pcmSamples.isEmpty) return null;

      return await AudioExportService.analyzeFromPcm(
        pcmSamples: pcmSamples,
        sessionDir: sessionDir,
        sampleRate: wavSampleRate,
        targetHitTime: targetHitTime?.clamp(0.0, 300.0) ?? 3.0,
        onProgress: (progress) {
          onProgress?.call(0.8 + progress.progress * 0.2, progress.message);
        },
      );
    } catch (e) {
      debugPrint('[音頻分析] 異常：$e');
      return null;
    }
  }

  /// 把音訊分析結果寫入 entry 的音訊欄位（與歷史頁完整分析寫法一致）。
  /// result 為 null 時原樣回傳。
  static RecordingHistoryEntry applyToEntry(
      RecordingHistoryEntry entry, AudioAnalysisResult? result) {
    if (result == null) return entry;
    return entry.copyWith(
      audioCrispness: result.features.isNotEmpty
          ? result.features.first.sharpnessHfxLoud
          : null,
      goodShot: result.predictedClass == 'good',
      audioLabel: result.feedbackLabel,
      audioPassCount: result.passCount,
      audioPasses: result.passes.isNotEmpty ? result.passes : null,
      audioFeatureValues:
          result.featureValues.isNotEmpty ? result.featureValues : null,
    );
  }
}
