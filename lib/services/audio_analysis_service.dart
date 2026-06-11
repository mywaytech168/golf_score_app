import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'audio_analyzer.dart';

class AudioAnalysisService {
  const AudioAnalysisService();

  // ------------------- 規則式分類配置 (與 Python classify_golf_audio_score_demo.py 同步) ---
  // 5 個音訊特徵的好球區間 [low, high]
  static const Map<String, List<double>> ruleIntervals = {
    'rms_dbfs':          [-30.0, -24.0],   // dBFS；好球主體在 -30 ~ -24
    'spectral_centroid': [3800.0, 4350.0], // Hz；好球約落在 3.8k ~ 4.35k
    'sharpness_hfxloud': [2.0, 3.0],       // 尖銳度 × 音量
    'highband_amp':      [11.0, 32.0],     // (2k~3k + 3k~4k) 平均幅度
    'peak_dbfs':         [-10.0, -4.0],    // dBFS 峰值
  };
  // Keep private alias for internal use
  static const Map<String, List<double>> _ruleIntervals = ruleIntervals;

  /// 各特徵的中文顯示名稱
  static const Map<String, String> featureLabels = {
    'rms_dbfs':          '音量',
    'spectral_centroid': '頻率',
    'sharpness_hfxloud': '清脆',
    'highband_amp':      '高頻',
    'peak_dbfs':         '峰值',
  };

  /// 格式化特徵值為簡短可讀字串（供 UI badge 顯示）
  /// 例如：formatFeatureValue('spectral_centroid', 4100) → '4.1k'
  static String formatFeatureValue(String key, double v) {
    if (key == 'spectral_centroid') {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    // 整數顯示 0 小數，小數值顯示 1 位
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  /// 通過 >= goodBadThreshold 項特徵即視為命中（好球）
  static const int goodBadThreshold = 3;
  // Keep private alias for internal use
  static const int _goodBadThreshold = goodBadThreshold;

  // Approximate Python's PEAK_REL_STRENGTH; used for simple peak counting on waveform envelope.
  static const double _peakRelStrength = 1.0;
  static const double _epsilon = 1e-12;

  // ------------------- 無聲音檢測閾值 -------------------
  static const double _silenceRmsThreshold = 0.01;    // RMS 閾值
  static const double _silencePeakThreshold = 0.05;   // 峰值閾值

  /// 規則式評分：對 5 個特徵逐一判斷是否落在好球區間（與 Python 同步）
  /// 通過 >= 3 項 → 'good'（命中）；否則 → 'bad'（未命中）
  static Future<AudioScore?> scoreSummary(Map<String, dynamic> summary) async {
    // 提取特徵值
    final Map<String, double> x = {};
    for (final feat in _ruleIntervals.keys) {
      final v = _extractFeatureValue(feat, summary);
      if (v != null && v.isFinite) x[feat] = v;
    }
    if (x.isEmpty) return null;

    // 逐特徵判斷是否通過區間
    final passes = <String, bool>{};
    for (final entry in _ruleIntervals.entries) {
      final feat = entry.key;
      final low  = entry.value[0];
      final high = entry.value[1];
      final val  = x[feat];
      passes[feat] = val != null && val >= low && val <= high;
    }

    final int passCount    = passes.values.where((p) => p).length;
    final bool isGood      = passCount >= _goodBadThreshold;
    final String predicted = isGood ? 'good' : 'bad';

    debugPrint('🎵 [AudioScore] passCount=$passCount/5 → $predicted | passes=$passes');

    return AudioScore(
      predictedClass: predicted,
      feedbackLabel: isGood ? '命中 $passCount/5' : '未命中 $passCount/5',
      featureValues: x,
      distances: {},
      passCount: passCount,
      passes: passes,
    );
  }

  static double? _extractFeatureValue(String key, Map<String, dynamic> summary) {
    if (key == 'highband_amp') {
      final v = summary['highband_amp'];
      if (v is num) return v.toDouble();
      if (summary['band_2k_3k_peak_amp'] is num && summary['band_3k_4k_peak_amp'] is num) {
        return ((summary['band_2k_3k_peak_amp'] + summary['band_3k_4k_peak_amp']) / 2.0).toDouble();
      }
      return null;
    }
    final v = summary[key];
    return (v is num) ? v.toDouble() : null;
  }

  static Future<Map<String, dynamic>> analyzeVideo(String videoPath) async {
    final Stopwatch sw = Stopwatch()..start();
    String? wavPath;
    try {
      final MethodChannel ch = const MethodChannel('audio_extractor_channel');
      final Map<dynamic, dynamic>? resp =
          await ch.invokeMapMethod<dynamic, dynamic>('extractAudio', <String, dynamic>{'videoPath': videoPath});
      wavPath = resp?['path'] as String?;
    } catch (e) {
      debugPrint('⚠️ [AudioAnalysis] Error extracting audio: $e');
    }

    if ((wavPath == null || wavPath.isEmpty) && videoPath.toLowerCase().endsWith('.wav')) {
      wavPath = videoPath;
    }

    if (wavPath == null || wavPath.isEmpty) {
      debugPrint('⚠️ [AudioAnalysis] No valid WAV path found.');
      return <String, dynamic>{
        'summary': {
          'audio_class': 'no_audio',
          'audio_feedback': '無聲音',
          'tags': ['no_audio'],
        },
        'segments': <Map<String, dynamic>>[],
        'analysis_seconds': sw.elapsedMilliseconds / 1000.0,
      };
    }

    try {
      final _WavData wav = await _readWav(wavPath);
      if (wav.samples.isEmpty) {
        debugPrint('⚠️ [AudioAnalysis] WAV file contains no samples.');
        return <String, dynamic>{
          'summary': {
            'audio_class': 'no_audio',
            'audio_feedback': '無聲音',
            'tags': ['no_audio'],
          },
          'segments': <Map<String, dynamic>>[],
          'analysis_seconds': sw.elapsedMilliseconds / 1000.0,
        };
      }

      // 檢測無聲音
      final bool isSilent = _isSilentAudio(wav.samples);
      if (isSilent) {
        debugPrint('🔇 [AudioAnalysis] Audio is silent (RMS < $_silenceRmsThreshold and Peak < $_silencePeakThreshold).');
        return <String, dynamic>{
          'summary': {
            'audio_class': 'no_audio',
            'audio_feedback': '無聲音',
            'tags': ['no_audio'],
          },
          'segments': <Map<String, dynamic>>[],
          'analysis_seconds': sw.elapsedMilliseconds / 1000.0,
        };
      }

      // Detect peaks and segment audio
      final List<int> peakIndices = _detectPeaks(wav.samples, wav.sampleRate);
      debugPrint('🎵 [AudioAnalysis] Detected ${peakIndices.length} peaks.');

      final List<Map<String, dynamic>> segments = _segmentAudio(wav.samples, wav.sampleRate, peakIndices);
      debugPrint('🎵 [AudioAnalysis] Created ${segments.length} segments.');

      // Analyze each segment and find the best hit
      Map<String, dynamic>? bestSegment;
      double bestScore = double.infinity; // lower distance is better

      for (final segment in segments) {
        final List<double> segmentSamples = segment['samples'];
        final AudioFeatures features = analyzeFromSamples(segmentSamples, wav.sampleRate);
        final Map<String, dynamic> summary = features.toMap();
        debugPrint('🎵 [AudioAnalysis] Extracted features: $summary');

        final AudioScore? score = await scoreSummary(summary);

        if (score != null) {
          debugPrint('🎵 [AudioAnalysis] Segment score: ${score.distances}, Predicted class: ${score.predictedClass}');
          final double segmentScore = score.distances.values.isEmpty
              ? double.infinity
              : score.distances.values.reduce((a, b) => a + b);
          if (segmentScore < bestScore) {
            bestScore = segmentScore;
            bestSegment = {
              'start_time': segment['start_time'],
              'end_time': segment['end_time'],
              'audio_class': score.predictedClass,
              'audio_feedback': score.feedbackLabel,
              'features': summary,
              'score': segmentScore,
              'distances': score.distances,
              'tags': [score.predictedClass],
            };
          }
        } else {
          debugPrint('⚠️ [AudioAnalysis] Score for segment is null.');
        }
      }

      final double elapsedSeconds = sw.elapsedMilliseconds / 1000.0;
      
      // 若未檢測到擊球但有聲音，標記為無有效擊球
      if (bestSegment == null) {
        return <String, dynamic>{
          'summary': {
            'audio_class': 'no_valid_hits',
            'audio_feedback': 'No valid hits detected',
            'tags': ['no_valid_hits'],
          },
          'segments': segments,
          'analysis_seconds': elapsedSeconds,
        };
      }

      return <String, dynamic>{
        'summary': bestSegment,
        'segments': segments,
        'analysis_seconds': elapsedSeconds,
      };
    } catch (e) {
      debugPrint('❌ [AudioAnalysis] Error during analysis: $e');
      return <String, dynamic>{
        'summary': {
          'audio_class': 'error',
          'audio_feedback': 'Analysis error',
          'tags': ['error'],
        },
        'segments': <Map<String, dynamic>>[],
        'analysis_seconds': sw.elapsedMilliseconds / 1000.0,
      };
    }
  }

  /// 檢測音訊是否為無聲音（靜默）
  /// RMS < 0.01 且峰值 < 0.05 表示無聲音
  static bool _isSilentAudio(List<double> samples) {
    if (samples.isEmpty) return true;

    double rmsSum = 0.0;
    double peakVal = 0.0;

    for (final sample in samples) {
      final normalized = sample.abs();
      rmsSum += normalized * normalized;
      if (normalized > peakVal) peakVal = normalized;
    }

    final double rms = math.sqrt(rmsSum / samples.length);
    final bool isSilent = rms < _silenceRmsThreshold && peakVal < _silencePeakThreshold;
    
    if (isSilent) {
      debugPrint('🔇 [AudioAnalysis] 無聲音檢測：RMS=${rms.toStringAsFixed(4)} < $_silenceRmsThreshold, Peak=${peakVal.toStringAsFixed(4)} < $_silencePeakThreshold');
    } else {
      debugPrint('🔊 [AudioAnalysis] 有聲音檢測：RMS=${rms.toStringAsFixed(4)}, Peak=${peakVal.toStringAsFixed(4)}');
    }

    return isSilent;
  }

  static List<int> _detectPeaks(List<double> samples, int sampleRate) {
    final List<int> peaks = [];
    if (samples.isEmpty) return peaks;
    final double maxAbs = samples.map((e) => e.abs()).reduce(math.max);
    final double threshold = math.max(_peakRelStrength * maxAbs, _epsilon);
    // simple local-max detector with min distance ~0.35s
    final int minDist = (0.35 * sampleRate).toInt();
    int lastPeak = -minDist;
    debugPrint('🎵 [AudioAnalysis] Peak detection threshold: $threshold');
    for (int i = 1; i < samples.length - 1; i++) {
      final double v = samples[i].abs();
      if (v >= threshold && v >= samples[i - 1].abs() && v >= samples[i + 1].abs()) {
        if (i - lastPeak >= minDist) {
          peaks.add(i);
          lastPeak = i;
          debugPrint('🎵 [AudioAnalysis] Detected peak at index $i with value ${samples[i]}');
        }
      }
    }
    if (peaks.isEmpty) {
      debugPrint('⚠️ [AudioAnalysis] No peaks detected. Max sample value: $maxAbs');
    }
    return peaks;
  }

  static List<Map<String, dynamic>> _segmentAudio(List<double> samples, int sampleRate, List<int> peakIndices) {
    final List<Map<String, dynamic>> segments = [];
    const double segmentDuration = 0.5; // seconds
    final int segmentSamples = (segmentDuration * sampleRate).toInt();

    for (final int peak in peakIndices) {
      final int start = math.max(0, peak - segmentSamples ~/ 2);
      final int end = math.min(samples.length, peak + segmentSamples ~/ 2);
      segments.add({
        'start_time': start / sampleRate,
        'end_time': end / sampleRate,
        'samples': samples.sublist(start, end),
      });
    }

    return segments;
  }

}
class AudioScore {
  const AudioScore({
    required this.predictedClass,
    required this.feedbackLabel,
    required this.featureValues,
    required this.distances,
    required this.passCount,
    required this.passes,
  });

  final String predictedClass;
  final String feedbackLabel;
  final Map<String, double> featureValues;
  final Map<String, double> distances;
  final int passCount;
  final Map<String, bool> passes;
}

class _WavData {
  _WavData(this.sampleRate, this.samples);
  final int sampleRate;
  final List<double> samples;
}

// Simple WAV reader (supports 16-bit PCM little-endian mono/stereo).
// Uses Uint8List (1 byte/element) instead of List<int> (8 bytes/element on 64-bit)
// to avoid ~8x memory amplification for large WAV files.
Future<_WavData> _readWav(String path) async {
    final Uint8List raw = await File(path).readAsBytes();
    if (raw.length < 44) return _WavData(0, <double>[]);
    // little-endian helpers
    int u32(int offset) => raw[offset] | (raw[offset + 1] << 8) | (raw[offset + 2] << 16) | (raw[offset + 3] << 24);
    int u16(int offset) => raw[offset] | (raw[offset + 1] << 8);
    final int fmtChunkOffset = 12;
    final int numChannels = u16(fmtChunkOffset + 10);
    final int sampleRate = u32(fmtChunkOffset + 12);
    final int bitsPerSample = u16(fmtChunkOffset + 22);

    // find data chunk
    int idx = 12;
    while (idx + 8 < raw.length) {
      final String chunkId = String.fromCharCodes(raw.sublist(idx, idx + 4));
      final int chunkSize = u32(idx + 4);
      if (chunkId == 'data') {
        final int dataStart = idx + 8;
        final int dataEnd = math.min(raw.length, dataStart + chunkSize);
        final List<double> samples = <double>[];
        if (bitsPerSample == 16) {
          for (int i = dataStart; i + 1 < dataEnd; i += 2 * numChannels) {
            // read first channel only
            final int lo = raw[i];
            final int hi = raw[i + 1];
            int val = (hi << 8) | lo;
            if (val & 0x8000 != 0) val = val - 0x10000;
            samples.add(val / 32768.0);
          }
        } else {
          // unsupported bits: return empty
        }
        return _WavData(sampleRate, samples);
      }
      idx += 8 + chunkSize;
    }
    return _WavData(0, <double>[]);
  }
