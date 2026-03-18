import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'audio_analyzer.dart';

class AudioAnalysisService {
  const AudioAnalysisService();

  // ------------------- MODEL CONFIG (Python 同步版) -------------------
  static const Map<String, double> _featureWeights = <String, double>{
    'rms_dbfs': 2.0,
    'spectral_centroid': 1.0,
    'sharpness_hfxloud': 2.0,
    'highband_amp': 1.0,
    'peak_dbfs': 1.0,
  };

  static const double _stage1NonbadRelax = 1.5;
  static const bool _stage2UseThreshold = true;
  static const double _stage2ProZ2Thresh = 10.0;
  static const double _epsilon = 1e-12;
  // Approximate Python's PEAK_REL_STRENGTH; used for simple peak counting on waveform envelope.
  static const double _peakRelStrength = 1.0;

  static Map<String, dynamic>? _modelStats;

  static Future<void> _loadModelStats() async {
    if (_modelStats != null) return;
    final String jsonString = await rootBundle.loadString('assets/audio/audio_class_stats.json');
    _modelStats = json.decode(jsonString) as Map<String, dynamic>;
  }

  static Map<String, double> _castStats(Map<String, dynamic> src) {
    return src.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  static Future<_AudioScore?> scoreSummary(Map<String, dynamic> summary) async {
    await _loadModelStats();
    if (_modelStats == null) return null;

    // --- Extract target features ---
    final Map<String, double> x = {};
    for (final feature in _featureWeights.keys) {
      final v = _extractFeatureValue(feature, summary);
      if (v != null && v.isFinite) x[feature] = v;
    }
    if (x.isEmpty) return null;

    // --- Load model means & std ---
    final muPro = _castStats(_modelStats!['mu']['pro']);
    final sdPro = _castStats(_modelStats!['sd']['pro']);
    final muGood = _castStats(_modelStats!['mu']['good']);
    final sdGood = _castStats(_modelStats!['sd']['good']);
    final muBad = _castStats(_modelStats!['mu']['bad']);
    final sdBad = _castStats(_modelStats!['sd']['bad']);
    final muNonbad = _castStats(_modelStats!['mu']['nonbad']);
    final rawSdNonbad = _castStats(_modelStats!['sd']['nonbad']);

    // Relax nonbad sd
    final Map<String, double> sdNonbadRelax = {
      for (final e in rawSdNonbad.entries) e.key: e.value * _stage1NonbadRelax
    };

    // --- STAGE 1: bad vs nonbad ---
    final double dBad = _computeWeightedDistance(x, muBad, sdBad);
    final double dNonbadR = _computeWeightedDistance(x, muNonbad, sdNonbadRelax);

    String finalClass;
    double? dPro, dGood, z2Pro;

    if (dNonbadR < dBad) {
      // --- STAGE 2: good vs pro ---
      dPro = _computeWeightedDistance(x, muPro, sdPro);
      dGood = _computeWeightedDistance(x, muGood, sdGood);
      z2Pro = dPro;

      if (_stage2UseThreshold) {
        finalClass = (z2Pro <= _stage2ProZ2Thresh) ? 'pro' : 'good';
      } else {
        finalClass = (dPro < dGood) ? 'pro' : 'good';
      }
    } else {
      finalClass = 'bad';
    }

    return _AudioScore(
      predictedClass: finalClass,
      feedbackLabel: _classFeedbackLabels[finalClass] ?? finalClass.toUpperCase(),
      featureValues: x,
      distances: {
        'd_bad': dBad,
        'd_nonbad_relaxed': dNonbadR,
        if (dPro != null) 'd_pro': dPro,
        if (dGood != null) 'd_good': dGood,
        if (z2Pro != null) 'z2_pro': z2Pro,
      },
    );
  }

  static const Map<String, String> _classFeedbackLabels = {
  'pro': 'Pro',
  'good': 'Sweet',
  'bad': 'Keep going!',
  };

  // --- Weighted z² distance ----
  static double _computeWeightedDistance(Map<String, double> x, Map<String, double> mu, Map<String, double> sd) {
    double sum = 0.0;
    bool used = false;
    _featureWeights.forEach((feat, w) {
      final xv = x[feat];
      final mv = mu[feat];
      final sv = sd[feat];
      if (xv == null || mv == null || sv == null) return;
      final s = (sv.abs() < _epsilon) ? _epsilon : sv;
      final z = (xv - mv) / s;
      sum += w * z * z;
      used = true;
    });
    return used ? sum : double.infinity;
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

  // ================================================================
  // 🔽 下面所有函式 **完全保留你的原始版本**（不要改）
  // ================================================================

  // (你原本的 detectPeaks, FFT, spectrum, _readWav, analyzeVideo 全部保留不動)
  // ↓↓↓↓↓ 直接把你原本底下的程式碼接上即可 ↓↓↓↓↓

  // Minimal analyzeVideo stub to satisfy callers in UI while a full
  // implementation (audio extraction + segment analysis) is present or
  // being integrated. Returns a safe placeholder structure.
  static Future<Map<String, dynamic>> analyzeVideo(String videoPath) async {
    final Stopwatch sw = Stopwatch()..start();
    String? wavPath;
    try {
      final MethodChannel ch = const MethodChannel('audio_extractor_channel');
      final Map<dynamic, dynamic>? resp =
          await ch.invokeMapMethod<dynamic, dynamic>('extractAudio', <String, dynamic>{'videoPath': videoPath});
      wavPath = resp?['path'] as String?;
    } catch (e) {
      print('Error extracting audio: $e');
    }

    if ((wavPath == null || wavPath.isEmpty) && videoPath.toLowerCase().endsWith('.wav')) {
      wavPath = videoPath;
    }

    if (wavPath == null || wavPath.isEmpty) {
      print('No valid WAV path found.');
      return <String, dynamic>{'summary': {}, 'segments': <Map<String, dynamic>>[]};
    }

    try {
      final _WavData wav = await _readWav(wavPath);
      if (wav.samples.isEmpty) {
        print('WAV file contains no samples.');
        return <String, dynamic>{'summary': {}, 'segments': <Map<String, dynamic>>[]};
      }

      // Detect peaks and segment audio
      final List<int> peakIndices = _detectPeaks(wav.samples, wav.sampleRate);
      print('Detected ${peakIndices.length} peaks.');

      final List<Map<String, dynamic>> segments = _segmentAudio(wav.samples, wav.sampleRate, peakIndices);
      print('Created ${segments.length} segments.');

      // Analyze each segment and find the best hit
      Map<String, dynamic>? bestSegment;
      double bestScore = double.infinity; // lower distance is better

      for (final segment in segments) {
        final List<double> segmentSamples = segment['samples'];
        final AudioFeatures features = analyzeFromSamples(segmentSamples, wav.sampleRate);
        final Map<String, dynamic> summary = features.toMap();
        print('Extracted features: $summary');

        final _AudioScore? score = await scoreSummary(summary);

        if (score != null) {
          print('Segment score: ${score.distances}, Predicted class: ${score.predictedClass}');
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
            };
          }
        } else {
          print('Score for segment is null.');
        }
      }

      final double elapsedSeconds = sw.elapsedMilliseconds / 1000.0;
      return <String, dynamic>{
        'summary': bestSegment ??
            {
              'audio_class': 'unknown',
              'audio_feedback': 'No valid hits detected',
            },
        'segments': segments,
        'analysis_seconds': elapsedSeconds,
      };
    } catch (e) {
      print('Error during analysis: $e');
      return <String, dynamic>{'summary': {}, 'segments': <Map<String, dynamic>>[]};
    }
  }

  static List<int> _detectPeaks(List<double> samples, int sampleRate) {
    final List<int> peaks = [];
    if (samples.isEmpty) return peaks;
    final double maxAbs = samples.map((e) => e.abs()).reduce(max);
    final double threshold = max(_peakRelStrength * maxAbs, _epsilon);
    // simple local-max detector with min distance ~0.35s
    final int minDist = (0.35 * sampleRate).toInt();
    int lastPeak = -minDist;
    print('Peak detection threshold: $threshold');
    for (int i = 1; i < samples.length - 1; i++) {
      final double v = samples[i].abs();
      if (v >= threshold && v >= samples[i - 1].abs() && v >= samples[i + 1].abs()) {
        if (i - lastPeak >= minDist) {
          peaks.add(i);
          lastPeak = i;
          print('Detected peak at index $i with value ${samples[i]}');
        }
      }
    }
    if (peaks.isEmpty) {
      print('No peaks detected. Max sample value: $maxAbs');
    }
    return peaks;
  }

  static List<Map<String, dynamic>> _segmentAudio(List<double> samples, int sampleRate, List<int> peakIndices) {
    final List<Map<String, dynamic>> segments = [];
    const double segmentDuration = 0.5; // seconds
    final int segmentSamples = (segmentDuration * sampleRate).toInt();

    for (final int peak in peakIndices) {
      final int start = max(0, peak - segmentSamples ~/ 2);
      final int end = min(samples.length, peak + segmentSamples ~/ 2);
      segments.add({
        'start_time': start / sampleRate,
        'end_time': end / sampleRate,
        'samples': samples.sublist(start, end),
      });
    }

    return segments;
  }

}
class _AudioScore {
  const _AudioScore({
    required this.predictedClass,
    required this.feedbackLabel,
    required this.featureValues,
    required this.distances,
  });

  final String predictedClass;
  final String feedbackLabel;
  final Map<String, double> featureValues;
  final Map<String, double> distances;
}

class _WavData {
  _WavData(this.sampleRate, this.samples);
  final int sampleRate;
  final List<double> samples;
}

// Simple WAV reader (supports 16-bit PCM little-endian mono/stereo)
Future<_WavData> _readWav(String path) async {
    final File f = File(path);
    final List<int> bytes = await f.readAsBytes();
    if (bytes.length < 44) return _WavData(0, <double>[]);
    // little-endian helper
    int u32(int offset) => bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
    int u16(int offset) => bytes[offset] | (bytes[offset + 1] << 8);
    final int fmtChunkOffset = 12;
    final int numChannels = u16(fmtChunkOffset + 10);
    final int sampleRate = u32(fmtChunkOffset + 12);
    final int bitsPerSample = u16(fmtChunkOffset + 22);

    // find data chunk
    int idx = 12;
    while (idx + 8 < bytes.length) {
      final String chunkId = String.fromCharCodes(bytes.sublist(idx, idx + 4));
      final int chunkSize = u32(idx + 4);
      if (chunkId == 'data') {
        final int dataStart = idx + 8;
        final int dataEnd = min(bytes.length, dataStart + chunkSize);
        final List<double> samples = <double>[];
        if (bitsPerSample == 16) {
          for (int i = dataStart; i + 1 < dataEnd; i += 2 * numChannels) {
            // read first channel only
            final int lo = bytes[i];
            final int hi = bytes[i + 1];
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
