import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import 'clip_audio_score_service.dart';
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
    final sessionDir = p.dirname(videoPath);

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

    // 每輪診斷 log（寫進 session 資料夾，供比對「即時判斷 vs session 最終」）
    final log = StringBuffer()
      ..writeln('=== AutoClip 偵測診斷 @ ${DateTime.now().toIso8601String()} ===')
      ..writeln('video=$videoPath  totalDur=${totalDur.toStringAsFixed(2)}s')
      ..writeln('即時擊球 liveImpacts (${liveImpacts.length}): '
          '${liveImpacts.map((t) => t.toStringAsFixed(2)).join(", ")}')
      ..writeln('音訊峰值 audioPeaks (${audioPeaks.length}): '
          '${audioPeaks.map((t) => t.toStringAsFixed(2)).join(", ")}')
      ..writeln('合併候選 candidates (${candidates.length}): '
          '${candidates.map((c) => "${c.sec.toStringAsFixed(2)}${c.fromAudio ? "(音)" : "(骨)"}").join(", ")}');
    if (candidates.isEmpty) {
      log.writeln('→ 無候選，不切片');
      await _writeDetectLog(sessionDir, log.toString());
      return [];
    }

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
        entry = await analyzeClipEntry(entry, preserveHitSec: true);
      } catch (e) {
        debugPrint('[AutoClip] clip ${i + 1} 分析失敗（保留切片）: $e');
      }
      await RecordingHistoryStorage.instance.upsertEntry(entry);
      entries.add(entry);
      // 比對：候選（即時判斷）秒數 vs 離線 SwingImpactDetector 重算的 clip 內 hitSec
      final candSec = i < candidates.length ? candidates[i].sec : double.nan;
      log.writeln('桿 ${i + 1}: 候選=${candSec.toStringAsFixed(2)}s '
          '(${i < candidates.length && candidates[i].fromAudio ? "音訊精修" : "骨架/即時"}) '
          '→ 採用即時判定 clip 內 hitSec=${entry.hitSecond?.toStringAsFixed(2) ?? "—"}s '
          '${entry.goodShot == true ? "甜蜜點" : ""}');
    }
    debugPrint('[AutoClip] ✅ 完成 ${entries.length} 桿');
    log.writeln('→ 完成 ${entries.length} 桿（最終 hitSec 採即時判定，離線只供 8 階段）');
    await _writeDetectLog(sessionDir, log.toString());
    return entries;
  }

  /// 寫每輪偵測診斷 log 到 session 資料夾（detect_log.txt，附加模式保留歷次）。
  static Future<void> _writeDetectLog(String sessionDir, String content) async {
    try {
      final f = File(p.join(sessionDir, 'detect_log.txt'));
      await f.writeAsString('$content\n', mode: FileMode.append);
      debugPrint('[AutoClip] 診斷 log → ${f.path}');
    } catch (e) {
      debugPrint('[AutoClip] detect_log.txt 寫入失敗: $e');
    }
  }

  /// 對單一 5 秒 clip 跑逐幀骨架分析，並以 clip CSV 重新定位精確擊球點與 8 階段。
  /// 之後對 clip 的 audio.wav 跑 5 特徵音訊評分（甜蜜點），結果寫入 entry。
  /// （公開供「偵測擊球」V2 流程於切片後背景補分析）
  ///
  /// [preserveHitSec]：true 時**保留 entry 既有的擊球時刻**（＝即時 LiveSwingDetector
  /// 的判定，已含嚴格雙手/門檻/錨點 V4），離線偵測只用來產生 8 階段，不覆蓋 hitSecond。
  /// 錄影自動切片走此路徑，讓 session 結果與即時光暈一致；手動「偵測揮桿」維持離線精修。
  static Future<RecordingHistoryEntry> analyzeClipEntry(
      RecordingHistoryEntry entry, {bool preserveHitSec = false}) async {
    final clipDir = p.dirname(entry.filePath);
    final csvPath = p.join(clipDir, 'pose_landmarks.csv');

    final basic = await VideoAnalysisPipelineService.analyzeBasic(
      videoPath: entry.filePath,
      sessionDir: clipDir,
      durationSeconds: entry.durationSeconds.clamp(1, 30),
    );
    if (basic == null || !File(csvPath).existsSync()) {
      return scoreClipAudio(entry);
    }

    final phaseHits = await SwingImpactDetector.detect(csvPath: csvPath);
    if (phaseHits.isEmpty) {
      return scoreClipAudio(entry.copyWith(isAnalyzed: true));
    }
    final hit = phaseHits.first;
    await ClipPipelineService.savePhasesJson(
      sessionDir: clipDir,
      hit: hit,
      clipActualStartSec: 0.0,  // clip CSV 為 clip 相對時間
    );
    // 即時判定為準：保留 entry.hitSecond（不採離線 hit.hitSec）；否則用離線精修
    return scoreClipAudio(preserveHitSec
        ? entry.copyWith(isAnalyzed: true)
        : entry.copyWith(hitSecond: hit.hitSec, isAnalyzed: true));
  }

  /// 對 clip 的 audio.wav 跑 5 特徵音訊評分並寫入 entry（失敗回傳原 entry）。
  static Future<RecordingHistoryEntry> scoreClipAudio(
      RecordingHistoryEntry entry) async {
    try {
      final clipDir = p.dirname(entry.filePath);
      final result = await ClipAudioScoreService.analyzeWav(
        sessionDir: clipDir,
        clipPath: entry.filePath,
        targetHitTime: entry.hitSecond,
      );
      return ClipAudioScoreService.applyToEntry(entry, result);
    } catch (e) {
      debugPrint('[AutoClip] 音訊評分失敗（略過）: $e');
      return entry;
    }
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

    // 骨架為主：每個 live impact 為一桿。音訊峰值精修採「自適應對稱窗 + 全域一對一指派」：
    //  ・前窗自適應：min(4.0, 與前一桿間隔×0.45) → 連續打球（間隔<4s）不會把前一桿的
    //    音峰誤配給當前桿（原固定 4s 前窗在快速連擊時誤配）。
    //  ・一對一指派：所有 (live,peak) 配對依距離排序貪婪指派，禁止一個峰值被兩桿共用
    //    （原邏輯兩桿可吃同一峰 → 事後去重把兩桿併成一桿、漏掉一桿）。
    final lives = [...liveImpacts]..sort();
    final peaks = [...audioPeaks]..sort();

    final pairs = <({int li, int pj, double dist})>[];
    for (int i = 0; i < lives.length; i++) {
      final s = lives[i];
      final gapPrev = i > 0 ? s - lives[i - 1] : double.infinity;
      final frontWin = math.min(_audioRefineEarlySec, gapPrev * 0.45);
      for (int j = 0; j < peaks.length; j++) {
        final a = peaks[j];
        if (a < s - frontWin || a > s + _audioRefineLateSec) continue;
        pairs.add((li: i, pj: j, dist: (a - s).abs()));
      }
    }
    pairs.sort((x, y) => x.dist.compareTo(y.dist));

    final liveToPeak = <int, int>{};
    final usedPeak = <int>{};
    for (final pr in pairs) {
      if (liveToPeak.containsKey(pr.li) || usedPeak.contains(pr.pj)) continue;
      liveToPeak[pr.li] = pr.pj;
      usedPeak.add(pr.pj);
    }

    final refined = <({double sec, bool fromAudio})>[];
    for (int i = 0; i < lives.length; i++) {
      final pj = liveToPeak[i];
      refined.add(pj != null
          ? (sec: peaks[pj], fromAudio: true)
          : (sec: lives[i], fromAudio: false));
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

  // ── anchor.json：錄製時使用的擊球錨點（歸一化），供離線 V4 偵測 ──────────────

  /// 存錄製時的擊球錨點到 session（離線 V4 用）。x/y 任一為 null 則不寫。
  static Future<void> saveAnchor(
      String sessionDir, double? x, double? y) async {
    if (x == null || y == null) return;
    try {
      final f = File(p.join(sessionDir, 'anchor.json'));
      await f.writeAsString(jsonEncode({'x': x, 'y': y}));
    } catch (e) {
      debugPrint('[AutoClip] anchor.json 寫入失敗: $e');
    }
  }

  /// 把 session 內的診斷小檔（detect_log.txt / anchor.json / live_impacts.json /
  /// audio_peaks.json / phases.json）打包成單一 meta.json 字串，供上傳。
  /// 各檔不存在則略過；全無則回傳僅含基本資訊的 JSON。
  static Future<String> buildSessionMetaJson(String sessionDir) async {
    final meta = <String, dynamic>{
      'sessionDir': p.basename(sessionDir),
    };
    Future<void> addJson(String name, String key) async {
      try {
        final f = File(p.join(sessionDir, name));
        if (await f.exists()) meta[key] = jsonDecode(await f.readAsString());
      } catch (_) {/* 損壞略過 */}
    }
    Future<void> addText(String name, String key) async {
      try {
        final f = File(p.join(sessionDir, name));
        if (await f.exists()) meta[key] = await f.readAsString();
      } catch (_) {}
    }
    await addJson('anchor.json', 'anchor');
    await addJson('live_impacts.json', 'liveImpacts');
    await addJson('audio_peaks.json', 'audioPeaks');
    await addJson('phases.json', 'phases');
    await addText('detect_log.txt', 'detectLog');
    return jsonEncode(meta);
  }

  /// 讀 session 的擊球錨點（歸一化）；無則回 null（→ 該影片不顯示離線 V4）。
  static Future<(double, double)?> loadAnchor(String sessionDir) async {
    try {
      final f = File(p.join(sessionDir, 'anchor.json'));
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final x = (m['x'] as num?)?.toDouble(), y = (m['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      return (x, y);
    } catch (e) {
      debugPrint('[AutoClip] anchor.json 讀取失敗: $e');
      return null;
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
