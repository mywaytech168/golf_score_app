import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import 'ball_tracker.dart';
import 'enhanced_ball_tracker.dart';  // [新增 Week 3]
import 'detection_config.dart';        // [新增 Week 3]
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
    final srcAudioPath  = p.join(srcSessionDir, 'audio.wav');

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

    // 縮圖定位到擊球瞬間
    String? thumbPath;
    try {
      final hitInClipMs = ((hit.hitSec - clipActualStartSec) * 1000).round().clamp(0, 999999);
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
    // 用 clipActualStartSec 而非 hit.startSec，對齊 clip 真實的 key frame 起點
    final dstCsvPath = p.join(sessionDir, 'pose_landmarks.csv');
    await _sliceCsv(
      srcCsvPath: srcCsvPath,
      dstCsvPath: dstCsvPath,
      startSec: clipActualStartSec,
      endSec: hit.endSec,
    );

    // 從原始音頻切分此球的音頻片段，存入 clip session 目錄
    final dstAudioPath = p.join(sessionDir, 'audio.wav');
    await _sliceAudio(
      srcAudioPath: srcAudioPath,
      dstAudioPath: dstAudioPath,
      startSec: clipActualStartSec,
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
        hitSecond: hit.hitSec - clipActualStartSec,
        startSecond: clipActualStartSec,
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
    double? hitSec,
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
      
      // [Week 3] 使用 EnhancedBallTracker 替代 BallTracker
      final tracker = EnhancedBallTracker(dt: 1.0 / 30.0);
      final baseRoiSize = 400;
      
      // 第一階段：標準 blob 提取 (使用默認配置)
      FrameExtractionResult? extraction = 
          await BallTrajectoryService.extractBlobs(inputPath: clipPath);
      
      if (extraction == null) {
        debugPrint('[Pipeline.analyze] ❌ blob 提取失敗');
      } else {
        debugPrint('[Pipeline.analyze] ✅ blob 提取完成：'
            '${extraction.frames.length} 幀，'
            'fps=${extraction.fps.toStringAsFixed(1)}，'
            '${extraction.width}×${extraction.height}');

        // [Week 3] 使用 EnhancedBallTracker 替代 BallTracker.track()
        final List<TrackPoint> trackPts = [];
        
        for (int i = 0; i < extraction.frames.length; i++) {
          final frameBlobs = extraction.frames[i];
          var candidates = frameBlobs.blobs
              .map((b) => Offset(b.cx.toDouble(), b.cy.toDouble()))
              .toList();
          
          final ptsUs = (i * 1000000 ~/ extraction.fps).toInt();
          
          if (candidates.isEmpty) {
            tracker.recordNoCandidate();
            tracker.predictKalman();
            continue;
          }
          
          tracker.recordFoundCandidates();
          
          // [Week 3] 應用規則 1: 步距衛士
          candidates = candidates.where((c) {
            return tracker.stepDistanceGuardCheck(c);
          }).toList();
          
          // [Week 3] 應用規則 2: Y 方向約束
          candidates = tracker.filterByYDirection(candidates);
          
          if (candidates.isEmpty) {
            // [Week 3] 應用規則 5: 異常值檢測
            if (tracker.handleOutlierDetection()) {
              debugPrint('[Pipeline.analyze] ⚠️ 追蹤凍結於幀 $i');
              break;
            }
            continue;
          }
          
          // 選擇最佳候選
          final best = candidates.first;
          
          // [Week 3] 更新面積 EMA (用於規則 3)
          final blobArea = frameBlobs.blobs.isNotEmpty 
              ? (frameBlobs.blobs[0].area ?? 30) 
              : 30;
          tracker.updateAreaEmaFromBlob(blobArea);
          
          // 初始化 Kalman（P0 和 P1）
          if (trackPts.isEmpty) {
            // P0: 第一個點
            tracker.addTrackPoint(best.dx.toInt(), best.dy.toInt(), i, ptsUs);
          } else if (trackPts.length == 1) {
            // P1: 初始化 Kalman
            tracker.initKalman(
              trackPts[0].x.toDouble(),
              trackPts[0].y.toDouble(),
              best.dx,
              best.dy,
            );
            tracker.addTrackPoint(best.dx.toInt(), best.dy.toInt(), i, ptsUs);
          } else {
            // P2+: 正常追蹤
            tracker.predictKalman();
            tracker.updateKalman(best.dx, best.dy);
            tracker.addTrackPoint(best.dx.toInt(), best.dy.toInt(), i, ptsUs);
          }
          
          trackPts.add(TrackPoint(
            x: best.dx.toInt(),
            y: best.dy.toInt(),
            frameIdx: i,
            ptsUs: ptsUs,
          ));
        }
        
        debugPrint('[Pipeline.analyze] ✅ 追蹤完成：${trackPts.length} 個軌跡點');

        if (trackPts.length >= 2) {
          // 固定 ROI = 400px (符合 Python 版本)
          final roiSize = 400;
          
          // ── 計算 ROI 邊界（小屏幕在右邊，占寬度的一半）──
          final videoW = extraction.width;
          final videoH = extraction.height;
          final screenW = videoW / 2;
          final screenH = videoH;
          final screenX = videoW / 2;  // 右邊小屏幕的左邊界
          
          // ROI 中心相對位置
          const roiXFrac = 0.6519;
          const roiYFrac = 0.5646;
          const roiSizeRatioW = 400.0 / 1080.0;  // ≈ 0.3704
          const roiSizeRatioH = 400.0 / 1920.0;  // ≈ 0.2083
          
          final roiCenterX = screenX + screenW * roiXFrac;
          final roiCenterY = screenH * roiYFrac;
          final scaledRoiSize = ((videoW * roiSizeRatioW + videoH * roiSizeRatioH) / 2);
          final halfRoi = scaledRoiSize / 2;
          
          final roiLeft = (roiCenterX - halfRoi).clamp(0, videoW - 1);
          final roiTop = (roiCenterY - halfRoi).clamp(0, videoH - 1);
          final roiRight = (roiCenterX + halfRoi).clamp(0, videoW - 1);
          final roiBottom = (roiCenterY + halfRoi).clamp(0, videoH - 1);
          
          // ── 過濾軌跡點：只保留 ROI 內的點 ──
          final roiFilteredPts = trackPts.where((pt) {
            return pt.x >= roiLeft && pt.x <= roiRight && 
                   pt.y >= roiTop && pt.y <= roiBottom;
          }).toList();
          
          debugPrint('[Pipeline.analyze] 🎯 ROI 過濾：${trackPts.length} → ${roiFilteredPts.length} 點');
          
          final withTraj = await BallTrajectoryService.renderOverlay(
            inputPath: skeletonPath,
            outputPath: trajOut,
            trackPts: roiFilteredPts.map((pt) => pt.toMap()).toList(),
            roiSize: roiSize,  // 固定 400px
          );
          if (withTraj != null) {
            hasBallTrack = true;
            finalPath = withTraj;
            debugPrint('[Pipeline.analyze] ✅ 球軌跡疊加成功 (固定 ROI=$roiSize px，${roiFilteredPts.length} 點)');
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

  /// 從原始音頻（PCM）中切分出指定時間範圍的片段
  /// 
  /// PCM 格式：Float32，44.1kHz，每個樣本占 4 字節
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
      const int sampleRate = 44100;
      const int bytesPerSample = 2; // 16-bit PCM
      
      final bytes = await src.readAsBytes();
      
      // WAV 头最小 44 字节
      if (bytes.length < 44) {
        debugPrint('[Pipeline._sliceAudio] WAV 檔案太小: ${bytes.length} 字節');
        return;
      }

      // 查找 "data" chunk 的起始位置
      int dataStart = 44;
      for (int i = 36; i < bytes.length - 8; i++) {
        if (bytes[i] == 100 && bytes[i + 1] == 97 &&
            bytes[i + 2] == 116 && bytes[i + 3] == 97) {
          dataStart = i + 8;
          break;
        }
      }

      final dataBytes = bytes.sublist(dataStart);
      final totalSamples = dataBytes.length ~/ bytesPerSample;
      
      // 計算樣本範圍
      final startSample = (startSec * sampleRate).toInt().clamp(0, totalSamples);
      final endSample = (endSec * sampleRate).toInt().clamp(0, totalSamples);
      
      if (startSample >= endSample) {
        debugPrint('[Pipeline._sliceAudio] 無效範圍：$startSample-$endSample');
        return;
      }
      
      // 提取音頻數據
      final startByte = startSample * bytesPerSample;
      final endByte = endSample * bytesPerSample;
      final slicedAudioBytes = dataBytes.sublist(startByte, endByte);
      
      // 🔧 重新生成 WAV 頭
      final wavHeader = BytesBuilder();
      
      // ChunkID "RIFF"
      wavHeader.addByte(82); wavHeader.addByte(73); 
      wavHeader.addByte(70); wavHeader.addByte(70);
      
      // ChunkSize (44 - 8 + dataSize)
      final fileSize = 36 + slicedAudioBytes.length;
      wavHeader.addByte(fileSize & 0xFF);
      wavHeader.addByte((fileSize >> 8) & 0xFF);
      wavHeader.addByte((fileSize >> 16) & 0xFF);
      wavHeader.addByte((fileSize >> 24) & 0xFF);
      
      // Format "WAVE"
      wavHeader.addByte(87); wavHeader.addByte(65);
      wavHeader.addByte(86); wavHeader.addByte(69);
      
      // Subchunk1ID "fmt "
      wavHeader.addByte(102); wavHeader.addByte(109);
      wavHeader.addByte(116); wavHeader.addByte(32);
      
      // Subchunk1Size (16)
      wavHeader.addByte(16); wavHeader.addByte(0);
      wavHeader.addByte(0); wavHeader.addByte(0);
      
      // AudioFormat (1 = PCM)
      wavHeader.addByte(1); wavHeader.addByte(0);
      
      // NumChannels (1 = mono)
      wavHeader.addByte(1); wavHeader.addByte(0);
      
      // SampleRate (44100)
      wavHeader.addByte(0x44); wavHeader.addByte(0xAC);
      wavHeader.addByte(0); wavHeader.addByte(0);
      
      // ByteRate (44100 * 1 * 2 = 88200)
      wavHeader.addByte(0x88); wavHeader.addByte(0x58);
      wavHeader.addByte(1); wavHeader.addByte(0);
      
      // BlockAlign (1 * 2 = 2)
      wavHeader.addByte(2); wavHeader.addByte(0);
      
      // BitsPerSample (16)
      wavHeader.addByte(16); wavHeader.addByte(0);
      
      // Subchunk2ID "data"
      wavHeader.addByte(100); wavHeader.addByte(97);
      wavHeader.addByte(116); wavHeader.addByte(97);
      
      // Subchunk2Size (dataSize)
      wavHeader.addByte(slicedAudioBytes.length & 0xFF);
      wavHeader.addByte((slicedAudioBytes.length >> 8) & 0xFF);
      wavHeader.addByte((slicedAudioBytes.length >> 16) & 0xFF);
      wavHeader.addByte((slicedAudioBytes.length >> 24) & 0xFF);
      
      // 合併頭部 + 數據
      final finalWav = BytesBuilder();
      finalWav.add(wavHeader.toBytes());
      finalWav.add(slicedAudioBytes);
      
      // 寫入目標檔案
      await File(dstAudioPath).writeAsBytes(finalWav.toBytes());
      
      final slicedSamples = slicedAudioBytes.length ~/ bytesPerSample;
      debugPrint('[Pipeline._sliceAudio] 切分完成: $startSample-$endSample ($slicedSamples 樣本) → $dstAudioPath');
    } catch (e) {
      debugPrint('[Pipeline._sliceAudio] 錯誤: $e');
    }
  }
}
