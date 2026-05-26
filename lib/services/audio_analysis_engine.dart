import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'audio_analyzer.dart' show analyzeFromSamples;
import 'audio_analysis_service.dart';
import 'audio_export_models.dart';

/// 音频分析状态枚举（参考 Ball Tracker 的状态）
enum _AudioAnalysisState {
  idle,
  detecting,     // 检测击球峰值
  analyzing,     // 提取特徵
  classifying,   // 分类
  outputting,    // 导出 CSV/TXT
}

/// 音频分析引擎（对标 BallTracker 的结构）
class AudioAnalysisEngine {
  final AudioAnalysisConfig config;
  final List<double> pcmSamples;

  // ignore: unused_field
  _AudioAnalysisState _state = _AudioAnalysisState.idle;
  final List<AudioFeatureFrame> _features = [];
  AudioClassResult? _classification;
  final Stopwatch _timer = Stopwatch();

  AudioAnalysisEngine({
    required this.config,
    required this.pcmSamples,
  });

  /// 执行完整分析流程（类似 BallTracker.track()）
  Future<AudioAnalysisResult?> analyze({
    required void Function(AudioAnalysisProgress progress)? onProgress,
  }) async {
    _timer.start();
    _state = _AudioAnalysisState.idle;
    _features.clear();
    _classification = null;

    try {
      // Stage 1: 检测峰值
      onProgress?.call(AudioAnalysisProgress(
        progress: 0.1,
        message: '检测击球峰值中...',
      ));
      _state = _AudioAnalysisState.detecting;
      debugPrint('[AudioEngine] 🔍 开始峰值检测...');
      final peaks = _detectPeaks();
      debugPrint('[AudioEngine] ✅ 峰值检测完成，共 ${peaks.length} 个');

      if (peaks.isEmpty) {
        onProgress?.call(AudioAnalysisProgress(
          progress: 0.3,
          message: '未检测到击球',
        ));
        _state = _AudioAnalysisState.idle;
        return null;
      }

      debugPrint('[AudioEngine] 检测到 ${peaks.length} 个峰值');

      // Stage 2: 提取特徵
      onProgress?.call(AudioAnalysisProgress(
        progress: 0.3,
        message: '提取音频特徵中...',
      ));
      _state = _AudioAnalysisState.analyzing;
      debugPrint('[AudioEngine] 🎵 开始特徵提取...');
      final features = await _extractFeatures(peaks, onProgress);
      debugPrint('[AudioEngine] ✅ 特徵提取完成，共 ${features.length} 个');
      _features.addAll(features);

      if (_features.isEmpty) {
        onProgress?.call(AudioAnalysisProgress(
          progress: 0.5,
          message: '特徵提取失败',
        ));
        _state = _AudioAnalysisState.idle;
        return null;
      }

      // Stage 3: 分类评分
      onProgress?.call(AudioAnalysisProgress(
        progress: 0.7,
        message: '分类评分中...',
      ));
      _state = _AudioAnalysisState.classifying;
      debugPrint('[AudioEngine] 🤖 开始分类评分...');
      
      final audioScore = await AudioAnalysisService.scoreSummary(
        _features.last.toJson(),
      );
      debugPrint('[AudioEngine] ✅ 分类完成: ${audioScore?.predictedClass ?? "失败"}');

      if (audioScore != null) {
        _classification = AudioClassResult(
          predictedClass: audioScore.predictedClass,
          feedbackLabel: audioScore.feedbackLabel,
          distances: audioScore.distances,
          featureValues: audioScore.featureValues,
        );
      } else {
        onProgress?.call(AudioAnalysisProgress(
          progress: 0.8,
          message: '分类失败，使用默认值',
        ));
        _classification = const AudioClassResult(
          predictedClass: 'bad',
          feedbackLabel: 'Unknown',
          distances: {},
          featureValues: {},
        );
      }

      // Stage 4: 导出结果
      onProgress?.call(AudioAnalysisProgress(
        progress: 0.9,
        message: '导出结果中...',
      ));
      _state = _AudioAnalysisState.outputting;
      debugPrint('[AudioEngine] 💾 开始导出 CSV...');
      if (config.saveCsv) await _exportCsv();
      debugPrint('[AudioEngine] 💾 开始导出 TXT...');
      if (config.saveTxt) await _exportTxt();
      debugPrint('[AudioEngine] ✅ 导出完成');

      onProgress?.call(AudioAnalysisProgress(
        progress: 1.0,
        message: '完成',
      ));

      _state = _AudioAnalysisState.idle;
      _timer.stop();

      debugPrint('[AudioEngine] 分析完成，耗时 ${_timer.elapsedMilliseconds}ms');

      return AudioAnalysisResult(
        predictedClass: _classification!.predictedClass,
        feedbackLabel: _classification!.feedbackLabel,
        csvPath: config.csvPath,
        txtPath: config.txtPath,
        features: List.unmodifiable(_features),
      );
    } catch (e) {
      debugPrint('[AudioEngine] 错误: $e');
      _state = _AudioAnalysisState.idle;
      return null;
    }
  }

  /// 击球峰值检测（对标 BallTracker 的 blob 检测）
  List<int> _detectPeaks() {
    if (pcmSamples.isEmpty) return [];

    // 计算 RMS
    final rmsFrameSec = 0.02;
    final rmsHopSec = 0.01;
    final rmsFrameLen = (rmsFrameSec * config.sampleRate).toInt();
    final rmsHop = (rmsHopSec * config.sampleRate).toInt();

    final rmsSeries = <double>[];
    for (int i = 0; i < pcmSamples.length - rmsFrameLen; i += rmsHop) {
      double sum = 0;
      for (int j = 0; j < rmsFrameLen; j++) {
        sum += pcmSamples[i + j] * pcmSamples[i + j];
      }
      rmsSeries.add(sqrt(sum / rmsFrameLen));
    }

    if (rmsSeries.isEmpty) return [];

    // RMS + MAD 阈值
    final median = _median(rmsSeries);
    final mad = _median(
      rmsSeries.map((x) => (x - median).abs()).toList(),
    );
    final threshold = median + config.madK * mad;

    debugPrint(
      '[AudioEngine] RMS 统计: median=$median, mad=$mad, threshold=$threshold',
    );

    // 检测候选峰值
    final peaks = <int>[];
    final minDist = (config.minDistSec / rmsHopSec).toInt();

    int lastPeakIdx = -minDist;
    for (int i = 1; i < rmsSeries.length - 1; i++) {
      if (rmsSeries[i] > threshold &&
          rmsSeries[i] >= rmsSeries[i - 1] &&
          rmsSeries[i] >= rmsSeries[i + 1] &&
          i - lastPeakIdx >= minDist) {
        peaks.add(i * rmsHop);
        lastPeakIdx = i;
      }
    }

    return peaks;
  }

  /// 特徵提取（对标骨架的特徵计算）
  Future<List<AudioFeatureFrame>> _extractFeatures(
    List<int> peaks,
    void Function(AudioAnalysisProgress progress)? onProgress,
  ) async {
    final features = <AudioFeatureFrame>[];
    final preLen = (config.preSec * config.sampleRate).toInt();
    final postLen = (config.postSec * config.sampleRate).toInt();
    debugPrint('[AudioEngine] 🔍 开始遍历 ${peaks.length} 个峰值');

    for (int i = 0; i < peaks.length; i++) {
      final peakIdx = peaks[i];
      final startIdx = max(0, peakIdx - preLen);
      final endIdx = min(pcmSamples.length, peakIdx + postLen);

      if (endIdx - startIdx < 100) continue;

      final segment = pcmSamples.sublist(startIdx, endIdx);

      // 提取特徵
      final audioFeatures = analyzeFromSamples(segment, config.sampleRate);
      debugPrint('[AudioEngine] ✅ 峰值 $i/${peaks.length} - 特徵提取完成');

      features.add(AudioFeatureFrame(
        frameIndex: i,
        timeSec: peakIdx / config.sampleRate,
        rmsDbfs: audioFeatures.rmsDbfs,
        peakDbfs: audioFeatures.peakDbfs,
        spectralCentroid: audioFeatures.spectralCentroid,
        sharpnessHfxLoud: audioFeatures.sharpnessHfxLoud,
        highbandAmp: audioFeatures.highbandAmp,
        bandPeaks: audioFeatures.bandPeaks,
      ));

      // 进度更新
      onProgress?.call(AudioAnalysisProgress(
        progress: 0.3 + (i / peaks.length) * 0.4,
        message: '提取特徵中... ${i + 1}/${peaks.length}',
        currentFrame: i + 1,
        totalFrames: peaks.length,
      ));

      await Future.delayed(Duration.zero); // 让出控制权
    }

    return features;
  }

  /// 导出 CSV（对标 PoseCsvWriter）
  Future<void> _exportCsv() async {
    try {
      final file = File(config.csvPath);
      await file.parent.create(recursive: true);

      final lines = <String>[
        // 表头
        [
          'frame_index',
          'time_sec',
          'rms_dbfs',
          'peak_dbfs',
          'spectral_centroid',
          'sharpness_hfxloud',
          'highband_amp',
          ...(_features.isNotEmpty
              ? _features.first.bandPeaks.keys.toList()
              : []),
        ].join(','),
      ];

      // 数据行
      for (final frame in _features) {
        final values = <String>[
          frame.frameIndex.toString(),
          frame.timeSec.toStringAsFixed(4),
          frame.rmsDbfs.toStringAsFixed(2),
          frame.peakDbfs.toStringAsFixed(2),
          frame.spectralCentroid.toStringAsFixed(2),
          frame.sharpnessHfxLoud.toStringAsFixed(4),
          frame.highbandAmp.toStringAsFixed(2),
          ...(frame.bandPeaks.values.map((v) => v.toStringAsFixed(2))),
        ];
        lines.add(values.join(','));
      }

      // 统计行
      if (_features.isNotEmpty) {
        final avgRms =
            _features.map((f) => f.rmsDbfs).reduce((a, b) => a + b) /
                _features.length;
        final avgPeak =
            _features.map((f) => f.peakDbfs).reduce((a, b) => a + b) /
                _features.length;
        lines.add('');
        lines.add('平均值,,${avgRms.toStringAsFixed(2)},${avgPeak.toStringAsFixed(2)}');
      }

      await file.writeAsString(lines.join('\n'));
      debugPrint('[AudioEngine] CSV 已保存: ${config.csvPath}');
    } catch (e) {
      debugPrint('[AudioEngine] CSV 导出失败: $e');
    }
  }

  /// 导出 TXT（新增，对标骨架输出）
  Future<void> _exportTxt() async {
    try {
      final file = File(config.txtPath);
      await file.parent.create(recursive: true);

      final txt = '''
======================================
  高尔夫击球音频分析报告
======================================

生成时间: ${DateTime.now()}
分析耗时: ${_timer.elapsedMilliseconds}ms

[分类结果]
预测类别: ${_classification?.predictedClass ?? 'N/A'}
反馈: ${_classification?.feedbackLabel ?? 'N/A'}
${_classification?.distances.entries.map((e) => '${e.key}: ${e.value.toStringAsFixed(4)}').join('\n') ?? ''}

[特徵摘要]
样本数: ${_features.length}
${_features.isNotEmpty ? '''
平均 RMS: ${(_features.map((f) => f.rmsDbfs).reduce((a, b) => a + b) / _features.length).toStringAsFixed(2)} dBFS
平均 Peak: ${(_features.map((f) => f.peakDbfs).reduce((a, b) => a + b) / _features.length).toStringAsFixed(2)} dBFS
平均 Centroid: ${(_features.map((f) => f.spectralCentroid).reduce((a, b) => a + b) / _features.length).toStringAsFixed(0)} Hz
平均 Sharpness: ${(_features.map((f) => f.sharpnessHfxLoud).reduce((a, b) => a + b) / _features.length).toStringAsFixed(3)}
''' : '无数据'}

[详细特徵]
${_features.map((f) => '''
帧 ${f.frameIndex} @ ${f.timeSec.toStringAsFixed(2)}s:
  RMS=${f.rmsDbfs.toStringAsFixed(2)}dBFS, Peak=${f.peakDbfs.toStringAsFixed(2)}dBFS
  Centroid=${f.spectralCentroid.toStringAsFixed(0)}Hz, Sharpness=${f.sharpnessHfxLoud.toStringAsFixed(3)}
  HighbandAmp=${f.highbandAmp.toStringAsFixed(2)}
''').join('\n')}

======================================
''';

      await file.writeAsString(txt);
      debugPrint('[AudioEngine] TXT 已保存: ${config.txtPath}');
    } catch (e) {
      debugPrint('[AudioEngine] TXT 导出失败: $e');
    }
  }

  // ============================================================================
  // 辅助函数
  // ============================================================================

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length % 2 == 0
        ? (sorted[mid - 1] + sorted[mid]) / 2
        : sorted[mid];
  }
}
