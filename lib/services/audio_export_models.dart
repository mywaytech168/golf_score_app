import 'package:flutter/foundation.dart';

/// 音频特徵帧数据模型（对标 PoseFrameModel）
@immutable
class AudioFeatureFrame {
  final int frameIndex;
  final double timeSec;
  final double rmsDbfs;
  final double peakDbfs;
  final double spectralCentroid;
  final double sharpnessHfxLoud;
  final double highbandAmp;
  final Map<String, double> bandPeaks;

  const AudioFeatureFrame({
    required this.frameIndex,
    required this.timeSec,
    required this.rmsDbfs,
    required this.peakDbfs,
    required this.spectralCentroid,
    required this.sharpnessHfxLoud,
    required this.highbandAmp,
    required this.bandPeaks,
  });

  Map<String, dynamic> toJson() => {
    'frame_index': frameIndex,
    'time_sec': timeSec,
    'rms_dbfs': rmsDbfs,
    'peak_dbfs': peakDbfs,
    'spectral_centroid': spectralCentroid,
    'sharpness_hfxloud': sharpnessHfxLoud,
    'highband_amp': highbandAmp,
    ...bandPeaks,
  };

  @override
  String toString() =>
      'AudioFeatureFrame(frame=$frameIndex, time=${timeSec.toStringAsFixed(2)}s, '
      'rms=$rmsDbfs, peak=$peakDbfs, centroid=${spectralCentroid.toStringAsFixed(0)}Hz)';
}

/// 音频分类结果（对标 BallTrackPoint）
@immutable
class AudioClassResult {
  final String predictedClass;
  final String feedbackLabel;
  final Map<String, double> distances;
  final Map<String, double> featureValues;
  final int passCount;
  final Map<String, bool> passes;

  const AudioClassResult({
    required this.predictedClass,
    required this.feedbackLabel,
    required this.distances,
    required this.featureValues,
    this.passCount = 0,
    this.passes = const {},
  });

  bool get isGood => passCount >= 3;
  bool get isPro => false;

  @override
  String toString() =>
      'AudioClassResult($predictedClass: "$feedbackLabel" $passCount/5)';
}

/// 统一的音频分析配置（对标 MediaPoseConfig）
@immutable
class AudioAnalysisConfig {
  final String sessionDir;
  final int sampleRate;
  final double targetHitTime;
  final double targetTolTime;

  // 特徵参数
  final double peakRelStrength;
  final double madK;
  final double minDistSec;
  final double preSec;
  final double postSec;

  // 背景/去噪参数
  final int bgPercentile;
  final double ssBeta;
  final double ssFloor;

  // 输出参数
  final bool saveCsv;
  final bool saveTxt;

  const AudioAnalysisConfig({
    required this.sessionDir,
    required this.sampleRate,
    this.targetHitTime = 3.0,
    this.targetTolTime = 0.5,
    this.peakRelStrength = 0.8,
    this.madK = 4.0,
    this.minDistSec = 0.35,
    this.preSec = 0.1,
    this.postSec = 0.1,
    this.bgPercentile = 25,
    this.ssBeta = 1.0,
    this.ssFloor = 1e-6,
    this.saveCsv = true,
    this.saveTxt = true,
  });

  String get csvPath => '$sessionDir/audio_features.csv';
  String get txtPath => '$sessionDir/audio_analysis.txt';
}

/// 统一的分析结果（对标 VideoAnalysisResult）
@immutable
class AudioAnalysisResult {
  final String predictedClass;
  final String feedbackLabel;
  final String csvPath;
  final String txtPath;
  final List<AudioFeatureFrame> features;
  final DateTime timestamp;
  final int passCount;
  final Map<String, bool> passes;
  final Map<String, double> featureValues;

  AudioAnalysisResult({
    required this.predictedClass,
    required this.feedbackLabel,
    required this.csvPath,
    required this.txtPath,
    required this.features,
    DateTime? timestamp,
    this.passCount = 0,
    this.passes = const {},
    this.featureValues = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isValid => features.isNotEmpty;
  int get featureCount => features.length;

  @override
  String toString() =>
      'AudioAnalysisResult($predictedClass: $feedbackLabel, '
      'features=$featureCount, csv=$csvPath)';
}

/// 音频分析进度模型
@immutable
class AudioAnalysisProgress {
  final double progress; // 0.0 - 1.0
  final String message;
  final int? currentFrame;
  final int? totalFrames;

  const AudioAnalysisProgress({
    required this.progress,
    required this.message,
    this.currentFrame,
    this.totalFrames,
  });

  @override
  String toString() => 'Progress(${(progress * 100).toStringAsFixed(0)}%, $message)';
}
