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
      final peakMs = await GolfAnalysisService.findAudioPeaks(
        videoPath: videoPath,
      );
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

  // ── 候選合併：±_dedupeWindowSec 內視為同一桿，優先音訊峰值 ──────────────

  static List<({double sec, bool fromAudio})> mergeCandidates({
    required List<double> audioPeaks,
    required List<double> liveImpacts,
  }) {
    final merged = <({double sec, bool fromAudio})>[
      for (final s in audioPeaks) (sec: s, fromAudio: true),
    ];
    for (final s in liveImpacts) {
      final nearAudio =
          audioPeaks.any((a) => (a - s).abs() <= _dedupeWindowSec);
      if (!nearAudio) merged.add((sec: s, fromAudio: false));
    }
    merged.sort((a, b) => a.sec.compareTo(b.sec));
    // 同來源相鄰過近也去重（保留前者）
    final out = <({double sec, bool fromAudio})>[];
    for (final c in merged) {
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
