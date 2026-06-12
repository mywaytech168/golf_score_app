import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import 'clip_pipeline_service.dart';
import 'golf_analysis_service.dart';
import 'recording_history_storage.dart';
import 'swing_impact_detector.dart';
import 'video_analysis_pipeline_service.dart';

/// 擊球事件驅動的自動切片：分析成本 = O(揮桿數)，與影片長度無關。
///
/// 流程（錄影結束後背景執行）：
///   1. 候選切點 = 錄影中 LiveSwingDetector 的擊球時刻 ∪ 音訊峰值
///   2. 以候選為中心切 5 秒 clip（不需要骨架）
///   3. 只對每個 5 秒 clip 跑逐幀骨架分析（~150 幀，每 clip 數秒）
///   4. clip CSV 上重跑 SwingImpactDetector → 精確 hitSecond + 8 階段 + phases.json
///
/// 全片逐幀分析完全跳過 —— 長影片不再有「分析跑很久」的問題。
class SwingAutoClipService {
  /// 候選去重窗口：兩候選相距小於此值視為同一桿（優先保留音訊峰值）
  static const double _dedupeWindowSec = 2.5;

  /// 進行中的 session（防重入：背景任務與手動觸發不重複跑）
  static final Set<String> _running = {};

  static bool isRunning(String sessionDir) => _running.contains(sessionDir);

  /// 回傳成功建立並完成分析的 clip entries。
  static Future<List<RecordingHistoryEntry>> run({
    required String videoPath,
    required RecordingHistoryEntry sourceEntry,
    List<double> liveImpacts = const [],
    void Function(String label)? onProgress,
  }) async {
    final sessionDir = p.dirname(videoPath);
    if (!_running.add(sessionDir)) {
      debugPrint('[AutoClip] 已在處理中，跳過: $sessionDir');
      return [];
    }
    try {
      return await _runImpl(
        videoPath: videoPath,
        sourceEntry: sourceEntry,
        liveImpacts: liveImpacts,
        onProgress: onProgress,
      );
    } finally {
      _running.remove(sessionDir);
    }
  }

  static Future<List<RecordingHistoryEntry>> _runImpl({
    required String videoPath,
    required RecordingHistoryEntry sourceEntry,
    required List<double> liveImpacts,
    void Function(String label)? onProgress,
  }) async {
    final totalDur = sourceEntry.durationSeconds.toDouble();

    // ── 1. 候選切點：live impacts ∪ 音訊峰值 ─────────────────────────────
    onProgress?.call('偵測擊球聲...');
    var audioPeaks = const <double>[];
    try {
      final peakMs = await getOrComputeAudioPeaks(videoPath: videoPath);
      audioPeaks = peakMs.map((ms) => ms / 1000.0).toList();
    } catch (e) {
      debugPrint('[AutoClip] 音訊峰值偵測失敗（無音軌？）: $e');
    }
    final candidates = mergeCandidates(
      audioPeaks: audioPeaks,
      liveImpacts: liveImpacts,
    );
    debugPrint('[AutoClip] 候選: audio=${audioPeaks.length} '
        'live=${liveImpacts.length} → 合併 ${candidates.length} 桿');
    if (candidates.isEmpty) return [];

    // ── 2. 切 5 秒 clip（V2 式，不需要骨架）────────────────────────────
    onProgress?.call('切片中...');
    final hits = <SwingHit>[];
    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final (s, e) = SwingImpactDetector.calculateClipBoundaries(
        hitSec: c.sec, totalDurationSec: totalDur);
      hits.add(SwingHit(
        hitIndex:   i + 1,
        hitFrame:   (c.sec * 30).round(),
        hitSec:     c.sec,
        startSec:   s,
        endSec:     e,
        speedValue: 0.0,
        audioValue: c.fromAudio ? 1.0 : 0.0,
      ));
    }
    final clips = await ClipPipelineService.run(
      hits: hits, srcVideoPath: videoPath, sourceEntry: sourceEntry,
    );
    if (clips.isEmpty) return [];

    // ── 3+4. 逐 clip 局部分析（150 幀）→ 精確 hitSecond + 8 階段 ─────────
    final entries = <RecordingHistoryEntry>[];
    for (int i = 0; i < clips.length; i++) {
      onProgress?.call('分析第 ${i + 1}/${clips.length} 桿...');
      var entry = clips[i].entry;
      try {
        entry = await analyzeClipEntry(entry);
      } catch (e) {
        debugPrint('[AutoClip] clip ${i + 1} 分析失敗（保留切片）: $e');
      }
      await RecordingHistoryStorage.instance.upsertEntry(entry);
      entries.add(entry);
    }
    debugPrint('[AutoClip] ✅ 完成 ${entries.length} 桿');
    return entries;
  }

  /// 對單一 5 秒 clip 跑逐幀骨架分析，並以 clip CSV 重新定位精確擊球點與 8 階段。
  /// （公開供「偵測擊球」V2 流程於切片後背景補分析）
  static Future<RecordingHistoryEntry> analyzeClipEntry(
      RecordingHistoryEntry entry) async {
    final clipDir = p.dirname(entry.filePath);
    final csvPath = p.join(clipDir, 'pose_landmarks.csv');

    final basic = await VideoAnalysisPipelineService.analyzeBasic(
      videoPath: entry.filePath,
      sessionDir: clipDir,
      durationSeconds: entry.durationSeconds.clamp(1, 30),
    );
    if (basic == null || !File(csvPath).existsSync()) return entry;

    final phaseHits = await SwingImpactDetector.detect(csvPath: csvPath);
    if (phaseHits.isEmpty) {
      return entry.copyWith(isAnalyzed: true);
    }
    final hit = phaseHits.first;
    await ClipPipelineService.savePhasesJson(
      sessionDir: clipDir,
      hit: hit,
      clipActualStartSec: 0.0,  // clip CSV 為 clip 相對時間
    );
    return entry.copyWith(hitSecond: hit.hitSec, isAnalyzed: true);
  }

  // ── 候選合併：骨架偵測為主，音訊峰值僅做時間精修 ─────────────────────────
  //
  // 設計（2026-06-12 定案）：桿數判定以 LiveSwingDetector（骨架腕速）為準；
  // 音訊峰值只用來把時間修到真正擊球瞬間，**不能自己成為一桿**——
  // 練習場環境音（隔壁打位擊球聲）會產生大量假峰值。
  //
  // 時間關係：腕速偵測要等峰值「確認下降」才開火，比真實擊球晚 0.3~3 秒；
  // 音訊峰值≈真實擊球瞬間 → 在 live impact 前 4 秒 ~ 後 1 秒內找最近峰值精修。

  /// live impact 往前找音訊峰值的窗口（偵測延遲最大觀測值 ~2.9s，留裕度）
  static const double _audioRefineEarlySec = 4.0;

  /// live impact 往後容許的音訊峰值窗口
  static const double _audioRefineLateSec = 1.0;

  static List<({double sec, bool fromAudio})> mergeCandidates({
    required List<double> audioPeaks,
    required List<double> liveImpacts,
  }) {
    // 無骨架即時偵測（匯入影片、低端機暫停分析）→ 退回音訊峰值
    if (liveImpacts.isEmpty) {
      final sorted = [...audioPeaks]..sort();
      return [for (final s in sorted) (sec: s, fromAudio: true)];
    }

    // 骨架為主：每個 live impact 為一桿，窗口內有音訊峰值就取峰值時間
    final refined = <({double sec, bool fromAudio})>[];
    for (final s in liveImpacts) {
      double? best;
      for (final a in audioPeaks) {
        if (a < s - _audioRefineEarlySec || a > s + _audioRefineLateSec) {
          continue;
        }
        if (best == null || (a - s).abs() < (best - s).abs()) best = a;
      }
      refined.add(best != null
          ? (sec: best, fromAudio: true)
          : (sec: s, fromAudio: false));
    }
    refined.sort((a, b) => a.sec.compareTo(b.sec));

    // 兩個 live impact 精修到同一峰值（或相鄰過近）時去重，保留前者
    final out = <({double sec, bool fromAudio})>[];
    for (final c in refined) {
      if (out.isEmpty || c.sec - out.last.sec > _dedupeWindowSec) out.add(c);
    }
    return out;
  }

  // ── live_impacts.json 讀寫 ────────────────────────────────────────────────

  static Future<void> saveLiveImpacts(
      String sessionDir, List<double> impacts) async {
    try {
      final f = File(p.join(sessionDir, 'live_impacts.json'));
      await f.writeAsString(jsonEncode({'impacts': impacts}));
    } catch (e) {
      debugPrint('[AutoClip] live_impacts.json 寫入失敗: $e');
    }
  }

  // ── audio_peaks.json 快取 ────────────────────────────────────────────────
  //
  // 錄影結束的背景自動切片會先算一次音訊峰值並存檔；之後歷史頁的
  // 偵測擊球 V2/V3 直接讀快取，免去重掃整段音軌。
  // 快取以偵測參數為 key：參數不同（含預設值改版）即重算。

  /// 讀快取（參數一致）→ 否則跑原生偵測並寫入快取。回傳毫秒峰值列表。
  static Future<List<int>> getOrComputeAudioPeaks({
    required String videoPath,
    int searchStartMs = 500,
    int minGapMs = 2000,
    int topN = 20,
  }) async {
    final sessionDir = p.dirname(videoPath);
    final cached = await _loadAudioPeaks(
      sessionDir,
      searchStartMs: searchStartMs, minGapMs: minGapMs, topN: topN,
    );
    if (cached != null) {
      debugPrint('[AutoClip] 音訊峰值快取命中: ${cached.length} 峰');
      return cached;
    }
    final peakMs = await GolfAnalysisService.findAudioPeaks(
      videoPath: videoPath,
      searchStartMs: searchStartMs, minGapMs: minGapMs, topN: topN,
    );
    await _saveAudioPeaks(
      sessionDir, peakMs,
      searchStartMs: searchStartMs, minGapMs: minGapMs, topN: topN,
    );
    return peakMs;
  }

  static Future<void> _saveAudioPeaks(
    String sessionDir,
    List<int> peakMs, {
    required int searchStartMs,
    required int minGapMs,
    required int topN,
  }) async {
    try {
      final f = File(p.join(sessionDir, 'audio_peaks.json'));
      await f.writeAsString(jsonEncode({
        'peaksMs': peakMs,
        'searchStartMs': searchStartMs,
        'minGapMs': minGapMs,
        'topN': topN,
      }));
    } catch (e) {
      debugPrint('[AutoClip] audio_peaks.json 寫入失敗: $e');
    }
  }

  static Future<List<int>?> _loadAudioPeaks(
    String sessionDir, {
    required int searchStartMs,
    required int minGapMs,
    required int topN,
  }) async {
    try {
      final f = File(p.join(sessionDir, 'audio_peaks.json'));
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (m['searchStartMs'] != searchStartMs ||
          m['minGapMs'] != minGapMs ||
          m['topN'] != topN) {
        return null;
      }
      return (m['peaksMs'] as List).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<double>> loadLiveImpacts(String sessionDir) async {
    try {
      final f = File(p.join(sessionDir, 'live_impacts.json'));
      if (!await f.exists()) return [];
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (m['impacts'] as List).map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return [];
    }
  }
}
