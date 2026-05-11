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
/// 每顆球的切片存入獨立 session 子目錄：
///   {clipsDir}/hit_{n}/clip.mp4
///   {clipsDir}/hit_{n}/thumbnail.jpg
///   （分析後）{clipsDir}/hit_{n}/pose_landmarks.csv
///             {clipsDir}/hit_{n}/skeleton.mp4
///             {clipsDir}/hit_{n}/final.mp4
class ClipPipelineService {
  const ClipPipelineService._();

  // ──────────────────────────────────────────────────────────────
  // 切片流程：只裁切 + 縮圖，每球建立獨立 session 目錄
  // ──────────────────────────────────────────────────────────────

  static Future<List<ClipResult>> run({
    required List<SwingHit> hits,
    required String srcVideoPath,
    required String clipsDir,
    required RecordingHistoryEntry sourceEntry,
    void Function(ClipProgress)? onProgress,
  }) async {
    await Directory(clipsDir).create(recursive: true);

    final results = <ClipResult>[];
    for (int i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final result = await _trimHit(
        hit: hit,
        srcVideoPath: srcVideoPath,
        clipsDir: clipsDir,
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
    required String clipsDir,
    required RecordingHistoryEntry sourceEntry,
  }) async {
    // 每球獨立 session 目錄
    final sessionDir = p.join(clipsDir, 'hit_${hit.hitIndex}');
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

  // ──────────────────────────────────────────────────────────────
  // 影片分析：對已裁切的短片執行 pose 分析 → 骨架 → 球軌跡
  //
  // [clipPath]    短片路徑（clip.mp4）
  // [sessionDir]  = p.dirname(clipPath)，即切片的 session 目錄
  // ──────────────────────────────────────────────────────────────

  static Future<AnalysisResult?> analyze({
    required String clipPath,
    required String sessionDir,
    required int durationSeconds,
    void Function(String label)? onProgress,
  }) async {
    // 1. Pose 分析 → pose_landmarks.csv + audio.pcm
    onProgress?.call('分析骨架中...');
    VideoAnalysisResult? analysisResult;
    try {
      analysisResult = await VideoAnalysisService().analyze(
        videoPath: clipPath,
        sessionDir: sessionDir,
        durationSeconds: durationSeconds,
        onProgress: (_, label) => onProgress?.call(label),
      );
    } catch (e) {
      debugPrint('[Pipeline.analyze] VideoAnalysis 失敗: $e');
      return null;
    }

    final csvPath = analysisResult.csvPath;

    // 2. 疊加骨架（startSec=0，CSV 已相對於切片）
    onProgress?.call('疊加骨架中...');
    bool hasSkeleton = false;
    String? skeletonPath;
    final skelOut = p.join(sessionDir, 'skeleton.mp4');

    if (!await File(csvPath).exists()) {
      debugPrint('[Pipeline.analyze] ❌ CSV 不存在：$csvPath');
    } else {
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
