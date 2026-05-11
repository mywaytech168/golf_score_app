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
import 'video_clip_service.dart';

/// 單一擊球片段的處理結果
class ClipResult {
  final RecordingHistoryEntry entry;
  final bool hasSkeleton;
  final bool hasBallTrack;

  const ClipResult({
    required this.entry,
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

/// 完整的切片 + 骨架 + 球軌跡流程。
///
/// 每顆球完成時呼叫 [onProgress]，讓 UI 可即時更新。
class ClipPipelineService {
  const ClipPipelineService._();

  /// 對 [hits] 中每顆擊球依序執行：
  ///   1. 裁切片段
  ///   2. 疊加骨架
  ///   3. 球軌跡追蹤 + 疊加
  ///
  /// 每顆球完成（或失敗）後呼叫 [onProgress]。
  /// 回傳所有成功的 [ClipResult]。
  static Future<List<ClipResult>> run({
    required List<SwingHit> hits,
    required String srcVideoPath,
    required String csvPath,
    required String clipsDir,
    required RecordingHistoryEntry sourceEntry,
    void Function(ClipProgress)? onProgress,
  }) async {
    final dir = Directory(clipsDir);
    await dir.create(recursive: true);

    final results = <ClipResult>[];

    for (int i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final result = await _processHit(
        hit: hit,
        srcVideoPath: srcVideoPath,
        csvPath: csvPath,
        clipsDir: clipsDir,
        sourceEntry: sourceEntry,
      );
      if (result != null) results.add(result);
      onProgress?.call(ClipProgress(i + 1, hits.length));
    }

    return results;
  }

  static Future<ClipResult?> _processHit({
    required SwingHit hit,
    required String srcVideoPath,
    required String csvPath,
    required String clipsDir,
    required RecordingHistoryEntry sourceEntry,
  }) async {
    // 1. 裁切原始片段
    final rawPath = p.join(clipsDir, 'hit_${hit.hitIndex}.mp4');
    final trimmed = await VideoClipService.trimClip(
      srcPath: srcVideoPath,
      dstPath: rawPath,
      startSec: hit.startSec,
      endSec: hit.endSec,
    );
    if (trimmed == null) {
      debugPrint('[Pipeline] hit ${hit.hitIndex} → 裁切失敗');
      return null;
    }

    // 2. 疊加骨架
    bool hasSkeleton = false;
    String? skeletonPath;
    final skelOut = p.join(clipsDir, 'hit_${hit.hitIndex}_skeleton.mp4');
    final overlaid = await SkeletonOverlayService.render(
      clipPath: trimmed,
      csvPath: csvPath,
      startSec: hit.startSec,
      outputPath: skelOut,
    );
    if (overlaid != null) {
      hasSkeleton = true;
      skeletonPath = overlaid;
      debugPrint('[Pipeline] hit ${hit.hitIndex} → 骨架疊加成功');
    } else {
      debugPrint('[Pipeline] hit ${hit.hitIndex} → 骨架疊加失敗');
    }

    // 3. 球軌跡：Phase1 blob → Phase2 Kalman → Phase3 疊加
    bool hasBallTrack = false;
    String? finalPath;
    if (skeletonPath != null) {
      final trajOut = p.join(clipsDir, 'hit_${hit.hitIndex}_final.mp4');
      final extraction = await BallTrajectoryService.extractBlobs(inputPath: skeletonPath);
      if (extraction == null) {
        debugPrint('[Pipeline] hit ${hit.hitIndex} → blob 提取失敗');
      } else {
        debugPrint('[Pipeline] hit ${hit.hitIndex} → '
            'blob 提取完成：${extraction.frames.length} 幀，'
            'fps=${extraction.fps.toStringAsFixed(1)}，'
            '${extraction.width}×${extraction.height}');

        final trackPts = BallTracker().track(
          frames: extraction.frames,
          fps: extraction.fps,
          videoW: extraction.width,
          videoH: extraction.height,
        );
        debugPrint('[Pipeline] hit ${hit.hitIndex} → 追蹤完成：${trackPts.length} 個軌跡點');

        if (trackPts.length >= 2) {
          final withTraj = await BallTrajectoryService.renderOverlay(
            inputPath: skeletonPath,
            outputPath: trajOut,
            trackPts: trackPts.map((pt) => pt.toMap()).toList(),
          );
          if (withTraj != null) {
            hasBallTrack = true;
            finalPath = withTraj;
            debugPrint('[Pipeline] hit ${hit.hitIndex} → 球軌跡疊加成功');
          } else {
            debugPrint('[Pipeline] hit ${hit.hitIndex} → 球軌跡疊加失敗');
          }
        } else {
          debugPrint('[Pipeline] hit ${hit.hitIndex} → 軌跡點不足（${trackPts.length}），略過疊加');
        }
      }
    }

    // 最終影片：依序取第一個成功的結果
    final clipPath = finalPath ?? skeletonPath ?? trimmed;

    // 縮圖定位到擊球瞬間（相對片段時間）
    String? thumbPath;
    try {
      final thumbOut = p.join(clipsDir, 'hit_${hit.hitIndex}.jpg');
      final hitInClipMs =
          ((hit.hitSec - hit.startSec) * 1000).round().clamp(0, 999999);
      thumbPath = await vt.VideoThumbnail.thumbnailFile(
        video: clipPath,
        thumbnailPath: thumbOut,
        imageFormat: vt.ImageFormat.JPEG,
        timeMs: hitInClipMs,
        quality: 75,
      );
    } catch (e) {
      debugPrint('[Pipeline] hit ${hit.hitIndex} → 縮圖生成失敗: $e');
    }

    final clipDuration = math.max(1, (hit.endSec - hit.startSec).round());
    final entry = RecordingHistoryEntry(
      filePath: clipPath,
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
    );

    return ClipResult(
      entry: entry,
      hasSkeleton: hasSkeleton,
      hasBallTrack: hasBallTrack,
    );
  }
}
