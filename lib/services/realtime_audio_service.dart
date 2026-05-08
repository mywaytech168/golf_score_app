import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';

import 'audio_analysis_service.dart';
import 'audio_analyzer.dart';

/// 即時錄音與揮桿聲音分析服務
///
/// 錄影期間同步收集 PCM 樣本，停止後找到最強撞擊點，
/// 截取 0.5 秒片段進行特徵提取與兩段式分類。
class RealtimeAudioService {
  final FlutterAudioCapture _capture = FlutterAudioCapture();
  final List<double> _samples = [];
  static const int sampleRate = 44100;
  bool _isActive = false;

  Future<void> start() async {
    _samples.clear();
    try {
      await _capture.start(
        _onAudioData,
        _onError,
        sampleRate: sampleRate,
        bufferSize: 4096,
      );
      _isActive = true;
    } catch (e) {
      debugPrint('[Audio] start error: $e');
    }
  }

  void _onAudioData(Float32List samples) {
    for (final s in samples) {
      _samples.add(s.toDouble());
    }
  }

  void _onError(Object e) => debugPrint('[Audio] error: $e');

  /// 取得錄製期間的原始 PCM 樣本（stopAndAnalyze 之後仍可讀取）
  List<double> get rawSamples => List.unmodifiable(_samples);

  /// 停止錄音並分析，回傳評分標籤（Pro / Sweet / Keep going!）
  Future<String?> stopAndAnalyze() async {
    if (!_isActive) return null;
    _isActive = false;

    try {
      await _capture.stop();
    } catch (e) {
      debugPrint('[Audio] stop error: $e');
    }

    if (_samples.length < sampleRate ~/ 2) return null; // 太短，不分析

    try {
      final peakIdx = _findBestPeak(_samples);
      if (peakIdx == null) return 'Keep going!';

      final halfSeg = (sampleRate * 0.25).toInt(); // 前後各 0.25s
      final start = max(0, peakIdx - halfSeg);
      final end = min(_samples.length, peakIdx + halfSeg);
      final segment = _samples.sublist(start, end);

      final features = analyzeFromSamples(segment, sampleRate);
      final score = await AudioAnalysisService.scoreSummary(features.toMap());
      return score?.feedbackLabel;
    } catch (e) {
      debugPrint('[Audio] analyze error: $e');
      return null;
    }
  }

  /// 找能量最強的撞擊峰值 index
  int? _findBestPeak(List<double> samples) {
    final maxAbs = samples.map((e) => e.abs()).reduce(max);
    if (maxAbs < 0.01) return null; // 環境噪音，無有效撞擊

    final threshold = maxAbs * 0.80;
    final minDist = (sampleRate * 0.35).toInt();

    int? bestIdx;
    double bestVal = 0;
    int lastPeak = -minDist;

    for (int i = 1; i < samples.length - 1; i++) {
      final v = samples[i].abs();
      if (v >= threshold &&
          v >= samples[i - 1].abs() &&
          v >= samples[i + 1].abs() &&
          i - lastPeak >= minDist) {
        if (v > bestVal) {
          bestVal = v;
          bestIdx = i;
        }
        lastPeak = i;
      }
    }
    return bestIdx;
  }

  void dispose() {
    if (_isActive) {
      _capture.stop().catchError((_) {});
      _isActive = false;
    }
  }
}
