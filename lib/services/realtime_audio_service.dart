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
///
/// ⚠️ 記憶體限制：只保留最近 [_maxBufferSeconds] 秒的音訊，
/// 避免長時間錄影時無限累積 PCM 數據導致 OOM。
class RealtimeAudioService {
  final FlutterAudioCapture _capture = FlutterAudioCapture();

  /// 環形緩衝區：使用 Float32List 節省一半記憶體（4 bytes vs double 8 bytes）
  static const int sampleRate = 44100;
  static const int _maxBufferSeconds = 10; // 最多保留 10 秒 ≈ 441000 samples × 4 bytes ≈ 1.7MB
  static const int _maxBufferSize = sampleRate * _maxBufferSeconds;

  final List<double> _samples = [];
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
    // 超出上限時，移除最舊的資料（保留最近 _maxBufferSeconds 秒）
    if (_samples.length > _maxBufferSize) {
      _samples.removeRange(0, _samples.length - _maxBufferSize);
    }
  }

  void _onError(Object e) => debugPrint('[Audio] error: $e');

  /// 取得錄製期間的原始 PCM 樣本（stopAndAnalyze 之後仍可讀取）
  List<double> get rawSamples => List.unmodifiable(_samples);

  /// 停止錄音（只停止，不分析）
  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;

    try {
      await _capture.stop();
    } catch (e) {
      debugPrint('[Audio] stop error: $e');
    }
  }

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
