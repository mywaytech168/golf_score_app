import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'video_analysis_service.dart';

/// 影片分析管線服務：根據影片時長執行不同的分析流程
/// 
/// 流程說明：
/// - 短影片 (5-60s)：直接進行完整分析 (骨架 + 音訊 + 球軌跡)
/// - 長影片 (60-120s)：先進行基礎分析 (骨架 + 音訊)，後續可選偵測擊球或球軌跡
class VideoAnalysisPipelineService {
  /// 執行基礎分析：骨架提取 + 音訊提取（不含球軌跡追蹤）
  /// 用於長影片的初始階段，為後續擊球偵測或詳細分析準備數據
  static Future<BasicAnalysisResult?> analyzeBasic({
    required String videoPath,
    required String sessionDir,
    required int durationSeconds,
    void Function(String label)? onProgress,
  }) async {
    try {
      final csvPath    = p.join(sessionDir, 'pose_landmarks.csv');
      // 兩種音訊格式皆可視為「已就緒」：
      //   audio.wav — VideoAnalysisService 從影片提取（int16 WAV）
      //   audio.pcm — RealtimeAudioService 即時錄製（raw float32）
      // ClipPipelineService._sliceAudio() 已能處理這兩種格式。
      final audioWavPath = p.join(sessionDir, 'audio.wav');
      final audioPcmPath = p.join(sessionDir, 'audio.pcm');
      final csvExists   = await File(csvPath).exists();
      final wavExists   = await File(audioWavPath).exists();
      final pcmExists   = await File(audioPcmPath).exists();

      // 若 CSV 存在，且至少有一種音訊檔，直接跳過分析
      if (csvExists && (wavExists || pcmExists)) {
        final existingAudioPath = wavExists ? audioWavPath : audioPcmPath;
        debugPrint('[VideoAnalysisPipeline] ✅ 骨架與音訊已存在 '
            '(audio=${wavExists ? "wav" : "pcm"})，略過分析');
        onProgress?.call('使用既有分析資料...');
        return BasicAnalysisResult(
          csvPath: csvPath,
          audioPath: existingAudioPath,
          isComplete: true,
        );
      }

      // 執行分析（骨架 + 音訊）
      onProgress?.call('分析骨架中...');
      final analysis = await VideoAnalysisService().analyze(
        videoPath: videoPath,
        sessionDir: sessionDir,
        durationSeconds: durationSeconds,
        onProgress: (progress, label) => onProgress?.call(label),
      );

      final hasCSV = await File(csvPath).exists();
      final hasAudio = analysis.audioPath.isNotEmpty && await File(analysis.audioPath).exists();

      debugPrint('[VideoAnalysisPipeline] ✅ 基礎分析完成: CSV=$hasCSV, Audio=$hasAudio');

      return BasicAnalysisResult(
        csvPath: csvPath,
        audioPath: analysis.audioPath,
        isComplete: hasCSV && hasAudio,
      );
    } catch (e) {
      debugPrint('[VideoAnalysisPipeline] ❌ 基礎分析錯誤: $e');
      return null;
    }
  }
}

/// 基礎分析結果（骨架 + 音訊）
class BasicAnalysisResult {
  final String csvPath;
  final String audioPath;
  final bool isComplete;

  BasicAnalysisResult({
    required this.csvPath,
    required this.audioPath,
    required this.isComplete,
  });
}

/// 完整分析結果（骨架 + 音訊 + 球軌跡）
class FullAnalysisResult {
  final String csvPath;
  final String audioPath;
  final bool hasPose;
  final bool hasAudio;
  final bool hasBallTrack;

  FullAnalysisResult({
    required this.csvPath,
    required this.audioPath,
    required this.hasPose,
    required this.hasAudio,
    required this.hasBallTrack,
  });
}
