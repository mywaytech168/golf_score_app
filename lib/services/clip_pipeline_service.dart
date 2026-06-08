import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/export_quality.dart';
import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import '../recording/pose_csv_writer.dart';
import 'analysis_progress_service.dart';
import 'audio_extraction_service.dart';
import 'ball_detection_prefs.dart';
import 'ball_tracker.dart';
import 'ball_trajectory_service.dart';
import 'golf_analysis_service.dart';
import 'server_ball_trajectory_service.dart';
import 'skeleton_overlay_service.dart';
import 'video_analysis_service.dart';
import 'video_clip_service.dart';

/// 骨架分析模式。
///
/// - [v1]：全影片逐幀 ML Kit → CSV → 骨架疊加影片（完整，較慢）
/// - [v2]：音訊峰值直接切片，不做骨架（最快）
/// - [v3]：音訊找候選時間點（±3s）→ 局部 ML Kit 精準定位擊球（±2.5s 切片）
enum SkeletonAnalysisMode { v1, v2, v3 }

/// 單一擊球片段的裁切結果
class ClipResult {
  final RecordingHistoryEntry entry;

  const ClipResult({required this.entry});
}

/// 影片分析結果（骨架 + 球軌跡）
class AnalysisResult {
  final String finalPath;
  final bool hasSkeleton;
  final bool hasBallTrack;
  final bool hasSilence;

  /// v2 專用：精準擊球時間（毫秒）；v1 模式下為 null
  final int? impactTimeMs;

  /// v2 專用：骨架 JSON 字串；v1 模式下為 null
  final String? skeletonJson;

  const AnalysisResult({
    required this.finalPath,
    required this.hasSkeleton,
    required this.hasBallTrack,
    this.hasSilence = false,
    this.impactTimeMs,
    this.skeletonJson,
  });
}

/// 裁切流程進度
class ClipProgress {
  final int current;
  final int total;

  const ClipProgress(this.current, this.total);
}

/// 切片 + 按需分析（骨架 + 球軌跡）的流程服務。
///
/// 每顆球的切片存入 golf_recordings 底下的獨立目錄：
///   {golf_recordings}/{session_name}_hit_{n}/clip.mp4
///   {golf_recordings}/{session_name}_hit_{n}/thumbnail.jpg
///   {golf_recordings}/{session_name}_hit_{n}/pose_landmarks.csv  ← 切片時即從原始 CSV 擷取
///   （分析後）{...}/skeleton.mp4
///             {...}/final.mp4
class ClipPipelineService {
  const ClipPipelineService._();

  // ──────────────────────────────────────────────────────────────
  // 切片流程：裁切 + 縮圖 + 繼承 CSV，每球建立獨立 session 目錄
  // ──────────────────────────────────────────────────────────────

  static Future<List<ClipResult>> run({
    required List<SwingHit> hits,
    required String srcVideoPath,
    required RecordingHistoryEntry sourceEntry,
    void Function(ClipProgress)? onProgress,
  }) async {
    // srcVideoPath = .../golf_recordings/{session_name}/swing.mp4
    final srcSessionDir = p.dirname(srcVideoPath);
    final sessionName   = p.basename(srcSessionDir);
    final golfRecDir    = p.dirname(srcSessionDir);
    final srcCsvPath    = p.join(srcSessionDir, 'pose_landmarks.csv');
    // 優先使用 audio.wav（VideoAnalysisService 從影片提取），
    // 若不存在則退回 audio.pcm（原始錄製的即時 float32 PCM）
    // 若兩者都不存在（V2/V3 跳過全片分析），從影片提取 audio.wav
    final srcWavPath = p.join(srcSessionDir, 'audio.wav');
    final srcPcmPath = p.join(srcSessionDir, 'audio.pcm');
    if (!await File(srcWavPath).exists() && !await File(srcPcmPath).exists()) {
      debugPrint('[Pipeline.run] audio.wav/pcm 不存在，從影片提取...');
      await AudioExtractionService.extractAudioFromVideo(
        videoPath: srcVideoPath,
        outputWavPath: srcWavPath,
      );
    }
    final srcAudioPath = await File(srcWavPath).exists() ? srcWavPath : srcPcmPath;

    final results = <ClipResult>[];
    for (int i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final result = await _trimHit(
        hit: hit,
        srcVideoPath: srcVideoPath,
        srcSessionDir: srcSessionDir,
        golfRecDir: golfRecDir,
        sessionName: sessionName,
        srcCsvPath: srcCsvPath,
        srcAudioPath: srcAudioPath,
        sourceEntry: sourceEntry,
      );
      if (result != null) results.add(result);
      onProgress?.call(ClipProgress(i + 1, hits.length));
    }
    return results;
  }

  static Future<ClipResult?> _trimHit({
    required SwingHit hit,
    required String srcVideoPath,
    required String srcSessionDir,
    required String golfRecDir,
    required String sessionName,
    required String srcCsvPath,
    required String srcAudioPath,
    required RecordingHistoryEntry sourceEntry,
  }) async {
    // 每球獨立目錄：golf_recordings/{session_name}_hit_{n}/
    final sessionDir = p.join(golfRecDir, '${sessionName}_hit_${hit.hitIndex}');
    await Directory(sessionDir).create(recursive: true);

    final clipPath = p.join(sessionDir, 'clip.mp4');
    final trimResult = await VideoClipService.trimClip(
      srcPath: srcVideoPath,
      dstPath: clipPath,
      startSec: hit.startSec,
      endSec: hit.endSec,
    );
    if (trimResult == null) {
      debugPrint('[Pipeline] hit ${hit.hitIndex} → ❌ 裁切失敗');
      return null;
    }
    final trimmed = trimResult.path;
    // clip 實際從 key frame 開始，可能略早於 hit.startSec，用 actualStartSec 對齊 CSV
    final clipActualStartSec = trimResult.actualStartSec;

    // 縮圖定位到擊球瞬間，使用多策略 fallback 處理 HEVC/MOV 相容性
    String? thumbPath;
    final thumbOutPath = p.join(sessionDir, 'thumbnail.jpg');
    final hitInClipMs = ((hit.hitSec - clipActualStartSec) * 1000).round().clamp(0, 999999);
    final timeCandidates = {hitInClipMs, 0, 1000}.toList();
    for (final timeMs in timeCandidates) {
      try {
        final path = await vt.VideoThumbnail.thumbnailFile(
          video: trimmed,
          thumbnailPath: thumbOutPath,
          imageFormat: vt.ImageFormat.JPEG,
          maxHeight: 256,
          timeMs: timeMs,
          quality: 75,
        );
        if (path != null && path.isNotEmpty) {
          thumbPath = path;
          break;
        }
      } catch (e) {
        debugPrint('[Pipeline] hit ${hit.hitIndex} → 縮圖 ${timeMs}ms 失敗: $e');
      }
    }
    if (thumbPath == null) {
      try {
        final bytes = await vt.VideoThumbnail.thumbnailData(
          video: trimmed,
          imageFormat: vt.ImageFormat.JPEG,
          maxHeight: 256,
          timeMs: 0,
          quality: 75,
        );
        if (bytes != null && bytes.isNotEmpty) {
          await File(thumbOutPath).writeAsBytes(bytes);
          thumbPath = thumbOutPath;
        }
      } catch (e) {
        debugPrint('[Pipeline] hit ${hit.hitIndex} → thumbnailData 失敗: $e');
      }
    }

    // 從原始 CSV 擷取此球的骨架資料，存入 clip session 目錄
    // V3：hit 已攜帶局部骨架 JSON，直接寫成 CSV（不需全片 CSV）
    // V1/V2：從全片 CSV 切片（clipActualStartSec 對齊 clip 真實 key frame 起點）
    final dstCsvPath = p.join(sessionDir, 'pose_landmarks.csv');
    if (hit.skeletonJson != null) {
      await _writeCsvFromSkeletonJson(
        skeletonJson:  hit.skeletonJson!,
        dstCsvPath:    dstCsvPath,
        clipStartSec:  clipActualStartSec,
        clipEndSec:    hit.endSec,
      );
    } else {
      await _sliceCsv(
        srcCsvPath: srcCsvPath,
        dstCsvPath: dstCsvPath,
        startSec: clipActualStartSec,
        endSec: hit.endSec,
      );
    }

    // 從原始音頻切分此球的音頻片段，存入 clip session 目錄
    final dstAudioPath = p.join(sessionDir, 'audio.wav');
    await _sliceAudio(
      srcAudioPath: srcAudioPath,
      dstAudioPath: dstAudioPath,
      startSec: clipActualStartSec,
      endSec: hit.endSec,
    );

    // 補產生 audio_features.csv（時序 RMS dBFS），供播放器多模態時間軸波形使用
    await _writeAudioFeaturesCsv(sessionDir);

    // 儲存 8 階段時間點（phases.json），供影片播放器關鍵禎跳轉使用
    // ⚠️ 只在 V1 骨架偵測時寫入（hit 含完整 8 階段資料）。
    // V2 音訊偵測的 SwingHit 只有 hitSec，其他階段均為 0.0，
    // 若強行寫入會讓 address/takeaway 等全顯示 0，誤導使用者。
    // V2 clip 不寫 phases.json → UI 顯示「生成階段」按鈕供使用者手動觸發。
    final hasPhaseData = hit.addressSec > 0.0 ||
        hit.takeawaySec > 0.0 ||
        hit.backswingSec > 0.0 ||
        hit.followThroughSec > 0.0;
    if (hasPhaseData) {
      await _savePhasesJson(
        sessionDir: sessionDir,
        hit: hit,
        clipActualStartSec: clipActualStartSec,
      );
    }

    debugPrint('[Pipeline] hit ${hit.hitIndex} → ✅ 裁切完成：$trimmed');

    // Surface trim path：clip 精確從 startSec 到 endSec（= 5 秒）
    // Fallback raw mux path：clip 從 I-frame 到 endSec（可能更長）
    final clipDuration = math.max(1, (hit.endSec - clipActualStartSec).round());
    return ClipResult(
      entry: RecordingHistoryEntry(
        filePath: trimmed,
        roundIndex: sourceEntry.roundIndex,
        recordedAt: sourceEntry.recordedAt,
        durationSeconds: clipDuration,
        customName: '${sourceEntry.displayTitle} 第${hit.hitIndex}球',
        thumbnailPath: thumbPath,
        videoType: VideoType.localClip,
        sourceVideoPath: sourceEntry.filePath,
        hitSecond: hit.hitSec - clipActualStartSec,
        startSecond: clipActualStartSec,
        endSecond: hit.endSec,
        bestSpeedValue: hit.speedValue > 0 ? hit.speedValue : null,
      ),
    );
  }

  /// 公開入口：供 UI 頁面對已存在的 clip 補存 phases.json。
  ///
  /// [hit] 的時間欄位（addressSec 等）應為相對於 clip 起點的秒數（clipActualStartSec=0）。
  static Future<void> savePhasesJson({
    required String sessionDir,
    required SwingHit hit,
    double clipActualStartSec = 0.0,
  }) =>
      _savePhasesJson(
        sessionDir: sessionDir,
        hit: hit,
        clipActualStartSec: clipActualStartSec,
      );

  /// 儲存 8 階段時間點到 phases.json（clip 相對秒數），供影片播放器快速讀取。
  static Future<void> _savePhasesJson({
    required String sessionDir,
    required SwingHit hit,
    required double clipActualStartSec,
  }) async {
    double clip(double srcSec) => (srcSec - clipActualStartSec).clamp(0.0, 3600.0);
    final map = {
      'address':       clip(hit.addressSec),
      'takeaway':      clip(hit.takeawaySec),
      'backswing':     clip(hit.backswingSec),
      'top':           clip(hit.backswingTopSec),
      'downswing':     clip(hit.downswingSec),
      'impact':        clip(hit.hitSec),
      'followthrough': clip(hit.followThroughSec),
      'finish':        clip(hit.finishSec),
    };
    try {
      await File(p.join(sessionDir, 'phases.json'))
          .writeAsString(jsonEncode(map));
    } catch (e) {
      debugPrint('[Pipeline] phases.json 儲存失敗: $e');
    }
  }

  /// 從原始 CSV 擷取 [startSec, endSec] 範圍的骨架幀，重新以 0 為起點編號寫出。
  ///
  /// SkeletonOverlayRenderer 以 csvFrameIdx = (clipTimeSec * 1000 / 67).round() 查表，
  /// 所以 clip CSV 的 frame 欄位必須是 0-based 的連續整數，time_sec 也重置為 0-based。
  static Future<void> _sliceCsv({
    required String srcCsvPath,
    required String dstCsvPath,
    required double startSec,
    required double endSec,
  }) async {
    final src = File(srcCsvPath);
    if (!await src.exists()) {
      debugPrint('[Pipeline] _sliceCsv: 原始 CSV 不存在，略過');
      return;
    }

    final lines = await src.readAsLines();
    if (lines.isEmpty) return;

    final buffer = StringBuffer()..writeln(lines.first); // header

    const double eps = 0.1; // 100ms 緩衝，確保邊界幀不被截掉
    int newFrameIdx = 0;

    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;

      // 快速解析 time_sec（第 2 欄），不做完整 CSV parse
      final firstComma  = line.indexOf(',');
      if (firstComma < 0) continue;
      final secondComma = line.indexOf(',', firstComma + 1);
      if (secondComma < 0) continue;

      final timeSec = double.tryParse(line.substring(firstComma + 1, secondComma).trim());
      if (timeSec == null) continue;
      if (timeSec < startSec - eps) continue;
      if (timeSec > endSec + eps) break;

      final relTime = (timeSec - startSec).clamp(0.0, double.infinity);
      // 只替換前兩欄（frame, time_sec），其餘原樣保留
      buffer
        ..write(newFrameIdx)
        ..write(',')
        ..write(relTime.toStringAsFixed(6))
        ..write(line.substring(secondComma)) // 從第二個逗號開始（含），保留後續所有欄位
        ..writeln();
      newFrameIdx++;
    }

    if (newFrameIdx == 0) {
      debugPrint('[Pipeline] _sliceCsv: 範圍內無資料（startSec=$startSec endSec=$endSec）');
      return;
    }

    await File(dstCsvPath).writeAsString(buffer.toString());
    debugPrint('[Pipeline] _sliceCsv: $newFrameIdx 幀 → $dstCsvPath');
  }

  /// V3 專用：將 [skeletonJson]（Kotlin 局部骨架）直接轉成 clip 的 pose_landmarks.csv。
  ///
  /// skeletonJson 格式（每幀）：
  /// ```json
  /// { "timeMs": 1234, "landmarks": [
  ///   { "type": 0, "x": 340.5, "y": 210.3, "z": -0.1,
  ///     "vis": 0.98, "xNorm": 0.315, "yNorm": 0.430 }, ... ] }
  /// ```
  ///
  /// [clipStartSec] 為 clip 真實起始秒數（`trimResult.actualStartSec`），
  /// 用於把 timeMs 轉成 clip 內 0-based 相對時間，與 _sliceCsv 邏輯一致。
  static Future<void> _writeCsvFromSkeletonJson({
    required String skeletonJson,
    required String dstCsvPath,
    required double clipStartSec,
    required double clipEndSec,
  }) async {
    final allFrames =
        (jsonDecode(skeletonJson) as List).cast<Map<String, dynamic>>();
    final clipDur = clipEndSec - clipStartSec;
    const double eps = 0.1;

    final rows = <List<dynamic>>[PoseCsvWriter.header];
    int frameIdx = 0;

    for (final frame in allFrames) {
      final absTimeSec = (frame['timeMs'] as num).toDouble() / 1000.0;
      final relTimeSec = absTimeSec - clipStartSec;
      // 只保留 clip 時間範圍內的幀
      if (relTimeSec < -eps || relTimeSec > clipDur + eps) continue;
      final clampedTime = relTimeSec.clamp(0.0, clipDur);

      final landmarks =
          (frame['landmarks'] as List).cast<Map<String, dynamic>>();
      final byType = <int, Map<String, dynamic>>{
        for (final lm in landmarks) (lm['type'] as num).toInt(): lm,
      };

      final row = <dynamic>[
        frameIdx,
        clampedTime.toStringAsFixed(6),
        frameIdx, // pose_update_id = frameIdx（連續）
      ];
      for (int i = 0; i < 33; i++) {
        final lm = byType[i];
        if (lm == null) {
          row.addAll([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
        } else {
          row.addAll([
            (lm['xNorm'] as num?)?.toDouble() ?? 0.0,
            (lm['yNorm'] as num?)?.toDouble() ?? 0.0,
            (lm['z']     as num?)?.toDouble() ?? 0.0,
            (lm['vis']   as num?)?.toDouble() ?? 0.0,
            (lm['x']     as num?)?.toDouble() ?? 0.0,
            (lm['y']     as num?)?.toDouble() ?? 0.0,
          ]);
        }
      }
      rows.add(row);
      frameIdx++;
    }

    if (frameIdx == 0) {
      debugPrint('[Pipeline] _writeCsvFromSkeletonJson: 範圍內無幀資料');
      return;
    }

    await File(dstCsvPath).writeAsString(
      const ListToCsvConverter().convert(rows),
    );
    debugPrint('[Pipeline] V3 skeletonJson → CSV: $frameIdx 幀 → $dstCsvPath');
  }

  // ──────────────────────────────────────────────────────────────
  // 影片分析：骨架疊加 → 球軌跡
  //
  // 若切片時已繼承 pose_landmarks.csv，直接跳過 VideoAnalysisService。
  // ──────────────────────────────────────────────────────────────

  static Future<AnalysisResult?> analyze({
    required String clipPath,
    required String sessionDir,
    required int durationSeconds,
    double? hitSec,
    ExportQuality quality = ExportQuality.standard,
    SkeletonAnalysisMode mode = SkeletonAnalysisMode.v1,
    void Function(String label)? onProgress,
  }) async {
    // ── V2 快速分析分支 ─────────────────────────────────────────────
    if (mode == SkeletonAnalysisMode.v2) {
      return _analyzeV2(
        clipPath: clipPath,
        sessionDir: sessionDir,
        hitSec: hitSec,
        quality: quality,
        onProgress: onProgress,
      );
    }
    // ── V1 完整分析繼續往下 ──────────────────────────────────────────
    final csvPath = p.join(sessionDir, 'pose_landmarks.csv');

    final progressSvc = AnalysisProgressService.instance;
    bool hasSilence = false;

    // 1. Pose 分析（若 CSV 已由切片繼承則略過，節省重複 ML Kit 推理）
    final wavPath = p.join(sessionDir, 'audio.wav');
    if (await File(csvPath).exists()) {
      onProgress?.call('使用骨架資料...');
      debugPrint('[Pipeline.analyze] ✅ CSV 已繼承，略過 VideoAnalysis：$csvPath');
      // Pose 分析跳過，但靜默偵測仍需執行（WAV 不存在也視為靜默）
      hasSilence = await VideoAnalysisService().checkSilence(wavPath: wavPath);
      debugPrint('[Pipeline.analyze] 靜默偵測（WAV 獨立）: hasSilence=$hasSilence');
    } else {
      onProgress?.call('分析骨架中...');
      progressSvc.reset('分析骨架中...');
      void _listenPose() => onProgress?.call(progressSvc.progress.value.$2);
      progressSvc.progress.addListener(_listenPose);
      try {
        final vaResult = await VideoAnalysisService().analyze(
          videoPath: clipPath,
          sessionDir: sessionDir,
          durationSeconds: durationSeconds,
          onProgress: (_, label) => onProgress?.call(label),
        );
        hasSilence = vaResult.hasSilence;
      } catch (e) {
        progressSvc.progress.removeListener(_listenPose);
        debugPrint('[Pipeline.analyze] VideoAnalysis 失敗: $e');
        return null;
      }
      progressSvc.progress.removeListener(_listenPose);
      if (!await File(csvPath).exists()) {
        debugPrint('[Pipeline.analyze] ❌ VideoAnalysis 完成但 CSV 不存在：$csvPath');
        return null;
      }
    }

    // 2. 疊加骨架（startSec=0，CSV 已相對於切片）
    onProgress?.call('疊加骨架中...');
    progressSvc.reset('疊加骨架中...');
    void _listenSkeleton() => onProgress?.call(progressSvc.progress.value.$2);
    progressSvc.progress.addListener(_listenSkeleton);
    bool hasSkeleton = false;
    String? skeletonPath;
    final skelOut = p.join(sessionDir, 'skeleton.mp4');

    String? overlaid = await SkeletonOverlayService.render(
      clipPath: clipPath,
      csvPath: csvPath,
      startSec: 0,
      outputPath: skelOut,
      quality: quality,
    );
    progressSvc.progress.removeListener(_listenSkeleton);
    if (overlaid != null && !await File(overlaid).exists()) {
      debugPrint('[Pipeline.analyze] ❌ 骨架輸出檔不存在，視為失敗');
      overlaid = null;
    }
    if (overlaid != null) {
      hasSkeleton = true;
      skeletonPath = overlaid;
      debugPrint('[Pipeline.analyze] ✅ 骨架疊加成功');
    } else {
      debugPrint('[Pipeline.analyze] ❌ 骨架疊加失敗');
      final bad = File(skelOut);
      if (await bad.exists()) await bad.delete();
    }

    // 3. 球軌跡（Phase1 blob/server → Phase2 Kalman/後端 → Phase3 本地疊加）
    bool hasBallTrack = false;
    String? finalPath;
    if (skeletonPath != null) {
      final trajOut  = p.join(sessionDir, 'final.mp4');
      final ballMode = await BallDetectionPrefs.getMode();
      debugPrint('[Pipeline.analyze] 球偵測模式: ${ballMode.label}');

      List<TrackPoint>? trackPts;

      if (ballMode == BallDetectionMode.server) {
        // ── 後端模式：上傳 clip → Python worker → 回傳 track_pts ──
        onProgress?.call('上傳至伺服器中...');
        try {
          final serverResult = await ServerBallTrajectoryService.instance.runAndWait(
            clipPath: clipPath,
            hitSec:  hitSec,
            onStatus: onProgress,
          );
          trackPts = serverResult.trackPts;
          debugPrint('[Pipeline.analyze] ✅ 後端追蹤完成：${trackPts.length} 點 '
              '(${serverResult.width}×${serverResult.height} fps=${serverResult.fps.toStringAsFixed(1)})');
        } catch (e) {
          debugPrint('[Pipeline.analyze] ❌ 後端球軌跡失敗: $e');
        }
      } else {
        // ── 本地模式：blob / tflite + Dart Kalman ──────────────────
        onProgress?.call('追蹤球軌跡中...');
        progressSvc.reset('球追蹤分析中...');
        void listenBlobs() => onProgress?.call(progressSvc.progress.value.$2);
        progressSvc.progress.addListener(listenBlobs);

        final extraction = ballMode == BallDetectionMode.tflite
            ? await BallTrajectoryService.extractBlobsTflite(inputPath: clipPath, hitSec: hitSec)
            : await BallTrajectoryService.extractBlobs(inputPath: clipPath);
        progressSvc.progress.removeListener(listenBlobs);

        if (extraction == null) {
          debugPrint('[Pipeline.analyze] ❌ blob 提取失敗');
        } else {
          debugPrint('[Pipeline.analyze] ✅ blob 提取完成：'
              '${extraction.frames.length} 幀，'
              'fps=${extraction.fps.toStringAsFixed(1)}，'
              '${extraction.width}×${extraction.height}');

          final tracker = BallTracker();
          trackPts = tracker.track(
            frames:   extraction.frames,
            fps:      extraction.fps,
            videoW:   extraction.width,
            videoH:   extraction.height,
            rotation: extraction.rotation,
            hitSec:   hitSec,
          );
          debugPrint('[Pipeline.analyze] ✅ 追蹤完成：${trackPts.length} 個軌跡點'
              ' (成功率 ${extraction.frames.isEmpty ? 0 : (trackPts.length * 100 ~/ extraction.frames.length)}%)');
        }
      }

      // ── 本地 renderOverlay（無論哪個模式都走這裡）─────────────────
      if (trackPts != null && trackPts.length >= 2) {
        const int roiSize = 400;
        onProgress?.call('軌跡渲染中...');
        progressSvc.reset('軌跡渲染中...');
        void listenOverlay() => onProgress?.call(progressSvc.progress.value.$2);
        progressSvc.progress.addListener(listenOverlay);
        final withTraj = await BallTrajectoryService.renderOverlay(
          inputPath:  skeletonPath,
          outputPath: trajOut,
          trackPts:   trackPts.map((pt) => pt.toMap()).toList(),
          roiSize:    roiSize,
          quality:    quality,
        );
        progressSvc.progress.removeListener(listenOverlay);
        if (withTraj != null) {
          hasBallTrack = true;
          finalPath    = withTraj;
          debugPrint('[Pipeline.analyze] ✅ 球軌跡疊加成功 (ROI=$roiSize px，${trackPts.length} 點)');
        } else {
          debugPrint('[Pipeline.analyze] ❌ 球軌跡疊加失敗');
          final bad = File(trajOut);
          if (await bad.exists()) await bad.delete();
        }
      } else {
        debugPrint('[Pipeline.analyze] ⚠️ 軌跡點不足（${trackPts?.length ?? 0}），略過疊加');
      }
    } else {
      debugPrint('[Pipeline.analyze] ⚠️ 骨架失敗，略過球軌跡');
    }

    return AnalysisResult(
      finalPath: finalPath ?? skeletonPath ?? clipPath,
      hasSkeleton: hasSkeleton,
      hasBallTrack: hasBallTrack,
      hasSilence: hasSilence,
    );
  }

  /// 從原始音頻切分出指定時間範圍的片段，輸出為 WAV（int16 LE）。
  ///
  /// 支援兩種輸入格式：
  ///   • audio.wav  — WAV 容器 + int16 PCM（VideoAnalysisService 從影片提取）
  ///                  從 header 讀取真實 sampleRate / channelCount，輸出保留原始格式。
  ///   • audio.pcm  — raw float32 LE，無標頭（RealtimeAudioService 即時錄製）
  ///                  固定 mono 44100 Hz，轉換為 int16 LE 輸出。
  static Future<void> _sliceAudio({
    required String srcAudioPath,
    required String dstAudioPath,
    required double startSec,
    required double endSec,
  }) async {
    final src = File(srcAudioPath);
    if (!await src.exists()) {
      debugPrint('[Pipeline._sliceAudio] 原始音頻不存在，略過：$srcAudioPath');
      return;
    }

    try {
      final isWav = srcAudioPath.endsWith('.wav');
      final fileLen = await src.length();

      int outSampleRate;
      int outNumChannels;
      int outBlockAlign;
      int dataStart;
      Uint8List slicedInt16Bytes;

      if (isWav) {
        if (fileLen < 44) {
          debugPrint('[Pipeline._sliceAudio] WAV 檔案過小: $fileLen bytes');
          return;
        }
        // 只讀 header（前 128 bytes，足夠找 "data" chunk）
        final raf = await src.open();
        try {
          final header = Uint8List(math.min(128, fileLen));
          await raf.readInto(header);
          final hd = header.buffer.asByteData();
          outNumChannels = hd.getUint16(22, Endian.little);
          outSampleRate  = hd.getUint32(24, Endian.little);
          outBlockAlign  = hd.getUint16(32, Endian.little);

          // 搜尋 "data" chunk（ASCII: d=100 a=97 t=116 a=97）
          dataStart = 44;
          for (int i = 36; i < header.length - 8; i++) {
            if (header[i] == 100 && header[i + 1] == 97 &&
                header[i + 2] == 116 && header[i + 3] == 97) {
              dataStart = i + 8;
              break;
            }
          }
        } finally {
          await raf.close();
        }

        if (outBlockAlign <= 0 || outSampleRate <= 0) {
          debugPrint('[Pipeline._sliceAudio] WAV header 無效 (ba=$outBlockAlign sr=$outSampleRate)');
          return;
        }

        final totalFrames = (fileLen - dataStart) ~/ outBlockAlign;
        final startFrame  = (startSec * outSampleRate).toInt().clamp(0, totalFrames);
        final endFrame    = (endSec   * outSampleRate).toInt().clamp(0, totalFrames);
        if (startFrame >= endFrame) {
          debugPrint('[Pipeline._sliceAudio] WAV 無效範圍：$startFrame-$endFrame');
          return;
        }

        // 只讀需要的範圍，不載入整個檔案
        final sliceStart = dataStart + startFrame * outBlockAlign;
        final sliceLen   = (endFrame - startFrame) * outBlockAlign;
        final sliceBuf   = Uint8List(sliceLen);
        final rafSlice   = await src.open();
        try {
          await rafSlice.setPosition(sliceStart);
          await rafSlice.readInto(sliceBuf);
        } finally {
          await rafSlice.close();
        }
        slicedInt16Bytes = sliceBuf;

        debugPrint('[Pipeline._sliceAudio] WAV 切分: $startFrame-$endFrame '
            '(rate=$outSampleRate ch=$outNumChannels ba=$outBlockAlign '
            '${slicedInt16Bytes.length ~/ outBlockAlign} 幀 dataStart=$dataStart)');
      } else {
        // raw float32 LE PCM：固定 mono 44100 Hz，逐塊讀取轉換 float32→int16
        outSampleRate  = 44100;
        outNumChannels = 1;
        outBlockAlign  = 2;
        if (fileLen < 4) {
          debugPrint('[Pipeline._sliceAudio] PCM 檔案過小: $fileLen bytes');
          return;
        }

        final totalSamples = fileLen ~/ 4;
        final startSample  = (startSec * outSampleRate).toInt().clamp(0, totalSamples);
        final endSample    = (endSec   * outSampleRate).toInt().clamp(0, totalSamples);
        if (startSample >= endSample) {
          debugPrint('[Pipeline._sliceAudio] PCM 無效範圍：$startSample-$endSample');
          return;
        }

        // 只讀需要的 float32 範圍
        final readLen = (endSample - startSample) * 4;
        final float32Buf = Uint8List(readLen);
        final rafPcm = await src.open();
        try {
          await rafPcm.setPosition(startSample * 4);
          await rafPcm.readInto(float32Buf);
        } finally {
          await rafPcm.close();
        }

        final byteData = float32Buf.buffer.asByteData();
        final sampleCount = endSample - startSample;
        final int16Buf = Uint8List(sampleCount * 2);
        for (int i = 0; i < sampleCount; i++) {
          final f = byteData.getFloat32(i * 4, Endian.little);
          final clamped = f.isFinite ? f.clamp(-1.0, 1.0) : 0.0;
          final int16Val = (clamped * 32767.0).round().clamp(-32768, 32767);
          final unsigned = int16Val < 0 ? int16Val + 65536 : int16Val;
          int16Buf[i * 2]     = unsigned & 0xFF;
          int16Buf[i * 2 + 1] = (unsigned >> 8) & 0xFF;
        }
        slicedInt16Bytes = int16Buf;
        debugPrint('[Pipeline._sliceAudio] PCM→int16 切分: $startSample-$endSample '
            '(${slicedInt16Bytes.length ~/ 2} 樣本)');
      }

      if (slicedInt16Bytes.isEmpty) {
        debugPrint('[Pipeline._sliceAudio] 切片結果為空，略過寫出');
        return;
      }

      // ── 包裝成 WAV 標頭並寫出（使用來源的真實格式）────────────────
      final dataSize = slicedInt16Bytes.length;
      final fileSize = 36 + dataSize;
      final byteRate = outSampleRate * outBlockAlign;

      final wavHeader = BytesBuilder();
      // "RIFF"
      wavHeader.addByte(82); wavHeader.addByte(73);
      wavHeader.addByte(70); wavHeader.addByte(70);
      // ChunkSize
      wavHeader.addByte(fileSize & 0xFF);
      wavHeader.addByte((fileSize >> 8)  & 0xFF);
      wavHeader.addByte((fileSize >> 16) & 0xFF);
      wavHeader.addByte((fileSize >> 24) & 0xFF);
      // "WAVE"
      wavHeader.addByte(87); wavHeader.addByte(65);
      wavHeader.addByte(86); wavHeader.addByte(69);
      // "fmt " + subchunk1Size=16
      wavHeader.addByte(102); wavHeader.addByte(109);
      wavHeader.addByte(116); wavHeader.addByte(32);
      wavHeader.addByte(16); wavHeader.addByte(0);
      wavHeader.addByte(0);  wavHeader.addByte(0);
      // AudioFormat=1 (PCM)
      wavHeader.addByte(1); wavHeader.addByte(0);
      // NumChannels
      wavHeader.addByte(outNumChannels & 0xFF);
      wavHeader.addByte((outNumChannels >> 8) & 0xFF);
      // SampleRate
      wavHeader.addByte(outSampleRate & 0xFF);
      wavHeader.addByte((outSampleRate >> 8)  & 0xFF);
      wavHeader.addByte((outSampleRate >> 16) & 0xFF);
      wavHeader.addByte((outSampleRate >> 24) & 0xFF);
      // ByteRate = sampleRate * blockAlign
      wavHeader.addByte(byteRate & 0xFF);
      wavHeader.addByte((byteRate >> 8)  & 0xFF);
      wavHeader.addByte((byteRate >> 16) & 0xFF);
      wavHeader.addByte((byteRate >> 24) & 0xFF);
      // BlockAlign
      wavHeader.addByte(outBlockAlign & 0xFF);
      wavHeader.addByte((outBlockAlign >> 8) & 0xFF);
      // BitsPerSample=16
      wavHeader.addByte(16); wavHeader.addByte(0);
      // "data"
      wavHeader.addByte(100); wavHeader.addByte(97);
      wavHeader.addByte(116); wavHeader.addByte(97);
      // Subchunk2Size
      wavHeader.addByte(dataSize & 0xFF);
      wavHeader.addByte((dataSize >> 8)  & 0xFF);
      wavHeader.addByte((dataSize >> 16) & 0xFF);
      wavHeader.addByte((dataSize >> 24) & 0xFF);

      final out = await File(dstAudioPath).open(mode: FileMode.write);
      try {
        await out.writeFrom(wavHeader.toBytes());
        await out.writeFrom(slicedInt16Bytes);
      } finally {
        await out.close();
      }
      debugPrint('[Pipeline._sliceAudio] ✅ 寫出完成 → $dstAudioPath');
    } catch (e) {
      debugPrint('[Pipeline._sliceAudio] 錯誤: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // audio_features.csv 產生器
  // 從 session 目錄的 audio.wav 計算時序 RMS dBFS（每 50ms 一個點），
  // 寫出 audio_features.csv，供 ChartDataService 繪製音訊波形使用。
  // 不依賴 Python 或外部引擎，純 Dart 計算。
  // ──────────────────────────────────────────────────────────────

  static Future<void> _writeAudioFeaturesCsv(String sessionDir) async {
    const tag = '[Pipeline._writeAudioFeaturesCsv]';
    try {
      final wavFile = File(p.join(sessionDir, 'audio.wav'));
      if (!await wavFile.exists()) {
        debugPrint('$tag audio.wav 不存在，略過');
        return;
      }

      final bytes = await wavFile.readAsBytes();
      if (bytes.length < 44) {
        debugPrint('$tag WAV 過小 (${bytes.length} bytes)，略過');
        return;
      }

      // ── 解析 WAV header ──────────────────────────────────────
      final hd          = bytes.buffer.asByteData();
      final sampleRate  = hd.getUint32(24, Endian.little);
      final blockAlign  = hd.getUint16(32, Endian.little); // bytes per frame

      // 搜尋 "data" chunk（與 _sliceAudio 同邏輯）
      int dataStart = 44;
      for (int i = 36; i < bytes.length - 8; i++) {
        if (bytes[i] == 100 && bytes[i + 1] == 97 &&
            bytes[i + 2] == 116 && bytes[i + 3] == 97) {
          dataStart = i + 8;
          break;
        }
      }
      if (dataStart >= bytes.length || blockAlign == 0) {
        debugPrint('$tag WAV 解析失敗（dataStart=$dataStart）');
        return;
      }

      final dataBytes   = ByteData.sublistView(bytes, dataStart);
      final totalFrames = (bytes.length - dataStart) ~/ blockAlign;
      if (totalFrames == 0) return;

      // ── 每 hopMs 毫秒計算一次 RMS dBFS ──────────────────────
      const hopMs   = 50; // 時間解析度 50ms
      final hopFrames = math.max(1, (sampleRate * hopMs / 1000).toInt());
      const eps = 1e-10;

      final lines = StringBuffer('time_sec,rms_dbfs\n');

      for (int fStart = 0; fStart < totalFrames; fStart += hopFrames) {
        final fEnd = math.min(fStart + hopFrames, totalFrames);
        double sumSq = 0.0;
        int count    = 0;

        for (int f = fStart; f < fEnd; f++) {
          final byteOff = f * blockAlign;
          if (byteOff + 1 >= dataBytes.lengthInBytes) break;
          // int16 LE，只取第一聲道
          final int16  = dataBytes.getInt16(byteOff, Endian.little);
          final norm   = int16 / 32768.0;
          sumSq += norm * norm;
          count++;
        }
        if (count == 0) continue;

        final rms     = math.sqrt(sumSq / count);
        final rmsDbfs = rms > eps
            ? 20.0 * (math.log(rms) / math.ln10)
            : -80.0;
        final timeSec = fStart / sampleRate;
        lines.write('${timeSec.toStringAsFixed(4)},'
            '${rmsDbfs.toStringAsFixed(2)}\n');
      }

      final csvFile = File(p.join(sessionDir, 'audio_features.csv'));
      await csvFile.writeAsString(lines.toString());
      debugPrint('$tag ✅ 寫出完成 (${totalFrames ~/ hopFrames} 行) → ${csvFile.path}');
    } catch (e) {
      debugPrint('$tag 錯誤: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // V2 快速分析：音訊峰值 + 局部 ML Kit，不產生 skeleton.mp4，
  // 直接回傳 impactTimeMs + skeletonJson 供 Flutter 即時疊圖。
  // ──────────────────────────────────────────────────────────────

  static Future<AnalysisResult?> _analyzeV2({
    required String clipPath,
    required String sessionDir,
    double? hitSec,
    ExportQuality quality = ExportQuality.standard,
    void Function(String label)? onProgress,
  }) async {
    onProgress?.call('V2 骨架分析中...');
    debugPrint('[Pipeline.analyzeV2] 開始 V2: $clipPath');

    final searchStartMs = hitSec != null
        ? ((hitSec - 3.0).clamp(0.0, double.infinity) * 1000).toInt()
        : 500;
    final searchEndMs = hitSec != null
        ? ((hitSec + 3.0) * 1000).toInt()
        : -1;

    final result = await GolfAnalysisService.analyzeVideo(
      videoPath: clipPath,
      searchStartMs: searchStartMs,
      searchEndMs: searchEndMs,
      windowMs: 1000,
    );

    if (result == null) {
      debugPrint('[Pipeline.analyzeV2] ❌ GolfAnalysisService 回傳 null');
      return null;
    }

    debugPrint('[Pipeline.analyzeV2] ✅ impactTimeMs=${result.impactTimeMs}, frames=${result.frameCount}');
    onProgress?.call('V2 分析完成');

    return AnalysisResult(
      finalPath:    clipPath,
      hasSkeleton:  false,   // v2 不產生 skeleton.mp4，由 Flutter 即時繪製
      hasBallTrack: false,
      hasSilence:   !result.hasAudio,
      impactTimeMs: result.impactTimeMs,
      skeletonJson: result.skeletonJson,
    );
  }
}
