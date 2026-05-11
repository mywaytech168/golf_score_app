import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import 'ball_tracker.dart';
import 'ball_trajectory_service.dart';
import 'skeleton_overlay_service.dart';
import 'video_analysis_service.dart';
import 'video_clip_service.dart';

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

  const AnalysisResult({
    required this.finalPath,
    required this.hasSkeleton,
    required this.hasBallTrack,
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

    final results = <ClipResult>[];
    for (int i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final result = await _trimHit(
        hit: hit,
        srcVideoPath: srcVideoPath,
        golfRecDir: golfRecDir,
        sessionName: sessionName,
        srcCsvPath: srcCsvPath,
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
    required String golfRecDir,
    required String sessionName,
    required String srcCsvPath,
    required RecordingHistoryEntry sourceEntry,
  }) async {
    // 每球獨立目錄：golf_recordings/{session_name}_hit_{n}/
    final sessionDir = p.join(golfRecDir, '${sessionName}_hit_${hit.hitIndex}');
    await Directory(sessionDir).create(recursive: true);

    final clipPath = p.join(sessionDir, 'clip.mp4');
    final trimmed = await VideoClipService.trimClip(
      srcPath: srcVideoPath,
      dstPath: clipPath,
      startSec: hit.startSec,
      endSec: hit.endSec,
    );
    if (trimmed == null) {
      debugPrint('[Pipeline] hit ${hit.hitIndex} → ❌ 裁切失敗');
      return null;
    }

    // 縮圖定位到擊球瞬間
    String? thumbPath;
    try {
      final hitInClipMs = ((hit.hitSec - hit.startSec) * 1000).round().clamp(0, 999999);
      thumbPath = await vt.VideoThumbnail.thumbnailFile(
        video: trimmed,
        thumbnailPath: p.join(sessionDir, 'thumbnail.jpg'),
        imageFormat: vt.ImageFormat.JPEG,
        timeMs: hitInClipMs,
        quality: 75,
      );
    } catch (e) {
      debugPrint('[Pipeline] hit ${hit.hitIndex} → 縮圖生成失敗: $e');
    }

    // 從原始 CSV 擷取此球的骨架資料，存入 clip session 目錄
    final dstCsvPath = p.join(sessionDir, 'pose_landmarks.csv');
    await _sliceCsv(
      srcCsvPath: srcCsvPath,
      dstCsvPath: dstCsvPath,
      startSec: hit.startSec,
      endSec: hit.endSec,
    );

    debugPrint('[Pipeline] hit ${hit.hitIndex} → ✅ 裁切完成：$trimmed');

    final clipDuration = math.max(1, (hit.endSec - hit.startSec).round());
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
        hitSecond: hit.hitSec - hit.startSec,
        startSecond: hit.startSec,
        endSecond: hit.endSec,
      ),
    );
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

  // ──────────────────────────────────────────────────────────────
  // 影片分析：骨架疊加 → 球軌跡
  //
  // 若切片時已繼承 pose_landmarks.csv，直接跳過 VideoAnalysisService。
  // ──────────────────────────────────────────────────────────────

  static Future<AnalysisResult?> analyze({
    required String clipPath,
    required String sessionDir,
    required int durationSeconds,
    void Function(String label)? onProgress,
  }) async {
    final csvPath = p.join(sessionDir, 'pose_landmarks.csv');

    // 1. Pose 分析（若 CSV 已由切片繼承則略過，節省重複 ML Kit 推理）
    if (await File(csvPath).exists()) {
      onProgress?.call('使用骨架資料...');
      debugPrint('[Pipeline.analyze] ✅ CSV 已繼承，略過 VideoAnalysis：$csvPath');
    } else {
      onProgress?.call('分析骨架中...');
      try {
        await VideoAnalysisService().analyze(
          videoPath: clipPath,
          sessionDir: sessionDir,
          durationSeconds: durationSeconds,
          onProgress: (_, label) => onProgress?.call(label),
        );
      } catch (e) {
        debugPrint('[Pipeline.analyze] VideoAnalysis 失敗: $e');
        return null;
      }
      if (!await File(csvPath).exists()) {
        debugPrint('[Pipeline.analyze] ❌ VideoAnalysis 完成但 CSV 不存在：$csvPath');
        return null;
      }
    }

    // 2. 疊加骨架（startSec=0，CSV 已相對於切片）
    onProgress?.call('疊加骨架中...');
    bool hasSkeleton = false;
    String? skeletonPath;
    final skelOut = p.join(sessionDir, 'skeleton.mp4');

    String? overlaid = await SkeletonOverlayService.render(
      clipPath: clipPath,
      csvPath: csvPath,
      startSec: 0,
      outputPath: skelOut,
    );
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

    // 3. 球軌跡（Phase1 blob → Phase2 Kalman → Phase3 疊加）
    bool hasBallTrack = false;
    String? finalPath;
    if (skeletonPath != null) {
      onProgress?.call('追蹤球軌跡中...');
      final trajOut = p.join(sessionDir, 'final.mp4');
      final extraction = await BallTrajectoryService.extractBlobs(inputPath: skeletonPath);
      if (extraction == null) {
        debugPrint('[Pipeline.analyze] ❌ blob 提取失敗');
      } else {
        debugPrint('[Pipeline.analyze] ✅ blob 提取完成：'
            '${extraction.frames.length} 幀，'
            'fps=${extraction.fps.toStringAsFixed(1)}，'
            '${extraction.width}×${extraction.height}');

        final trackPts = BallTracker().track(
          frames: extraction.frames,
          fps: extraction.fps,
          videoW: extraction.width,
          videoH: extraction.height,
        );
        debugPrint('[Pipeline.analyze] ✅ 追蹤完成：${trackPts.length} 個軌跡點');

        if (trackPts.length >= 2) {
          final withTraj = await BallTrajectoryService.renderOverlay(
            inputPath: skeletonPath,
            outputPath: trajOut,
            trackPts: trackPts.map((pt) => pt.toMap()).toList(),
          );
          if (withTraj != null) {
            hasBallTrack = true;
            finalPath = withTraj;
            debugPrint('[Pipeline.analyze] ✅ 球軌跡疊加成功');
          } else {
            debugPrint('[Pipeline.analyze] ❌ 球軌跡疊加失敗');
            final bad = File(trajOut);
            if (await bad.exists()) await bad.delete();
          }
        } else {
          debugPrint('[Pipeline.analyze] ⚠️ 軌跡點不足（${trackPts.length}），略過疊加');
        }
      }
    } else {
      debugPrint('[Pipeline.analyze] ⚠️ 骨架失敗，略過球軌跡');
    }

    return AnalysisResult(
      finalPath: finalPath ?? skeletonPath ?? clipPath,
      hasSkeleton: hasSkeleton,
      hasBallTrack: hasBallTrack,
    );
  }
}
