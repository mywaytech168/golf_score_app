import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/export_quality.dart';
import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import 'analysis_progress_service.dart';
import 'audio_export_service.dart';
import 'ball_detection_prefs.dart';
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
  final bool hasSilence;

  const AnalysisResult({
    required this.finalPath,
    required this.hasSkeleton,
    required this.hasBallTrack,
    this.hasSilence = false,
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
    final srcWavPath = p.join(srcSessionDir, 'audio.wav');
    final srcPcmPath = p.join(srcSessionDir, 'audio.pcm');
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

    // 自動音頻分析：計算甜蜜點（goodShot）和清脆度（audioCrispness）
    final hitSecInClip = hit.hitSec - clipActualStartSec;
    final audioAnalysis = await _analyzeClipAudio(
      wavPath: dstAudioPath,
      sessionDir: sessionDir,
      hitSecInClip: hitSecInClip,
    );
    debugPrint('[Pipeline] hit ${hit.hitIndex} → 音頻分析: '
        'goodShot=${audioAnalysis?.goodShot}, '
        'crispness=${audioAnalysis?.crispness?.toStringAsFixed(3)}, '
        'label=${audioAnalysis?.audioLabel}');

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
        // 將此球的速度峰值存入切片，供統計使用
        bestSpeedValue: hit.speedValue > 0 ? hit.speedValue : null,
        // 自動音頻分析結果
        audioCrispness: audioAnalysis?.crispness,
        goodShot: audioAnalysis?.goodShot,
        audioLabel: audioAnalysis?.audioLabel,
      ),
    );
  }

  /// 從 WAV 檔案讀取 PCM，呼叫 AudioExportService 分析甜蜜點與清脆度。
  ///
  /// [wavPath]       — 已切分完成的 audio.wav
  /// [sessionDir]    — clip 的 session 目錄（AudioAnalysisConfig 需要）
  /// [hitSecInClip]  — 擊球時刻相對於 clip 起點的秒數（用作 targetHitTime）
  static Future<({double? crispness, bool? goodShot, String? audioLabel})?>
      _analyzeClipAudio({
    required String wavPath,
    required String sessionDir,
    required double hitSecInClip,
  }) async {
    try {
      final file = File(wavPath);
      if (!await file.exists()) return null;

      Uint8List? bytes = await file.readAsBytes();
      if (bytes.length < 44) return null;

      final bd = bytes.buffer.asByteData();
      final channels   = bd.getUint16(22, Endian.little);
      final sampleRate = bd.getUint32(24, Endian.little);
      final blockAlign = bd.getUint16(32, Endian.little);

      // 搜尋 "data" chunk（ASCII: d=100 a=97 t=116 a=97）
      int dataStart = 44;
      for (int i = 36; i < bytes.length - 8; i++) {
        if (bytes[i] == 100 && bytes[i + 1] == 97 &&
            bytes[i + 2] == 116 && bytes[i + 3] == 97) {
          dataStart = i + 8;
          break;
        }
      }

      final audioLen = bytes.length - dataStart;
      if (audioLen <= 0 || blockAlign <= 0) return null;

      // 解碼 int16 LE → float64，多聲道取平均
      final pcm = <double>[];
      for (int i = 0; i + blockAlign <= audioLen; i += blockAlign) {
        double v = 0;
        for (int ch = 0; ch < channels; ch++) {
          final offset = dataStart + i + ch * 2;
          if (offset + 1 >= bytes.length) break;
          final raw = bytes[offset] | (bytes[offset + 1] << 8);
          final signed = raw > 32767 ? raw - 65536 : raw;
          v += signed / 32768.0;
        }
        pcm.add(v / channels);
      }
      bytes = null; // 提早釋放，避免同時佔用兩份大記憶體

      if (pcm.isEmpty) return null;

      final result = await AudioExportService.analyzeFromPcm(
        pcmSamples: pcm,
        sessionDir: sessionDir,
        sampleRate: sampleRate,
        targetHitTime: hitSecInClip.clamp(0.0, 300.0),
        onProgress: null,
      );
      if (result == null) return null;

      return (
        crispness: result.features.isNotEmpty
            ? result.features.first.sharpnessHfxLoud
            : null,
        goodShot: result.predictedClass == 'pro' || result.predictedClass == 'good',
        audioLabel: result.feedbackLabel,
      );
    } catch (e) {
      debugPrint('[Pipeline._analyzeClipAudio] ❌ $e');
      return null;
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
    void Function(String label)? onProgress,
  }) async {
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

    // 3. 球軌跡（Phase1 blob → Phase2 Kalman → Phase3 疊加）
    bool hasBallTrack = false;
    String? finalPath;
    if (skeletonPath != null) {
      onProgress?.call('追蹤球軌跡中...');
      progressSvc.reset('球追蹤分析中...');
      void _listenBlobs() => onProgress?.call(progressSvc.progress.value.$2);
      progressSvc.progress.addListener(_listenBlobs);
      final trajOut = p.join(sessionDir, 'final.mp4');

      // 讀取球偵測模式（原版 or TFLite）
      final ballMode = await BallDetectionPrefs.getMode();
      debugPrint('[Pipeline.analyze] 球偵測模式: ${ballMode.label}');

      final extraction = ballMode == BallDetectionMode.tflite
          ? await BallTrajectoryService.extractBlobsTflite(inputPath: clipPath)
          : await BallTrajectoryService.extractBlobs(inputPath: clipPath);
      progressSvc.progress.removeListener(_listenBlobs);

      if (extraction == null) {
        debugPrint('[Pipeline.analyze] ❌ blob 提取失敗');
      } else {
        debugPrint('[Pipeline.analyze] ✅ blob 提取完成：'
            '${extraction.frames.length} 幀，'
            'fps=${extraction.fps.toStringAsFixed(1)}，'
            '${extraction.width}×${extraction.height}');

        // 使用新的 BallTracker（一次性處理所有幀）
        // hitSec 限制 waitP0 只在擊球前後的時間視窗搜尋，大幅降低白色衣物等假陽性
        final tracker = BallTracker();
        final trackPts = tracker.track(
          frames: extraction.frames,
          fps: extraction.fps,
          videoW: extraction.width,
          videoH: extraction.height,
          hitSec: hitSec,
        );
        
        debugPrint('[Pipeline.analyze] ✅ 追蹤完成：${trackPts.length} 個軌跡點');
        
        // 🔍 追蹤統計
        final successRate = extraction.frames.length > 0 
            ? (trackPts.length / extraction.frames.length * 100).toStringAsFixed(1)
            : '0.0';
        debugPrint('''[追蹤統計]
  • 總幀數: ${extraction.frames.length}
  • 成功追蹤: ${trackPts.length}
  • 成功率: $successRate%
''');

        if (trackPts.length >= 2) {
          const int roiSize = 400;
          
          // 🔍 DEBUG: 打印所有軌跡點位置
          debugPrint('[轨跡調試] 軌跡點詳細信息 (共 ${trackPts.length} 點)：');
          for (int i = 0; i < trackPts.length; i++) {
            final pt = trackPts[i];
            final x = pt.x as int? ?? 0;
            final y = pt.y as int? ?? 0;
            final frameIdx = pt.frameIdx as int? ?? 0;
            final ptsUs = pt.ptsUs as int? ?? 0;
            final timeMs = (ptsUs / 1000.0).toStringAsFixed(2);
            debugPrint('  [P$i] x=$x, y=$y, 幀=$frameIdx, 時間=${timeMs}ms');
          }
          
          onProgress?.call('軌跡渲染中...');
          progressSvc.reset('軌跡渲染中...');
          void _listenOverlay() => onProgress?.call(progressSvc.progress.value.$2);
          progressSvc.progress.addListener(_listenOverlay);
          final withTraj = await BallTrajectoryService.renderOverlay(
            inputPath: skeletonPath,
            outputPath: trajOut,
            trackPts: trackPts.map((pt) => pt.toMap()).toList(),
            roiSize: roiSize,
            quality: quality,
          );
          progressSvc.progress.removeListener(_listenOverlay);
          if (withTraj != null) {
            hasBallTrack = true;
            finalPath = withTraj;
            debugPrint('[Pipeline.analyze] ✅ 球軌跡疊加成功 (ROI=$roiSize px，${trackPts.length} 點)');
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
      final bytes = await src.readAsBytes();
      final isWav = srcAudioPath.endsWith('.wav');

      // ── 取得 int16 LE 的切片 bytes，並確定輸出格式 ─────────────────
      Uint8List slicedInt16Bytes;
      int outSampleRate;
      int outNumChannels;
      int outBlockAlign; // bytes per audio frame (= numChannels * 2 for int16)

      if (isWav) {
        // 從 WAV header 讀取真實格式（不假設 44100 Hz 或 mono）
        if (bytes.length < 44) {
          debugPrint('[Pipeline._sliceAudio] WAV 檔案過小: ${bytes.length} bytes');
          return;
        }
        final hd = bytes.buffer.asByteData();
        outNumChannels = hd.getUint16(22, Endian.little);
        outSampleRate  = hd.getUint32(24, Endian.little);
        outBlockAlign  = hd.getUint16(32, Endian.little);

        // 搜尋 "data" chunk（ASCII: d=100 a=97 t=116 a=97）
        int dataStart = 44;
        for (int i = 36; i < bytes.length - 8; i++) {
          if (bytes[i] == 100 && bytes[i + 1] == 97 &&
              bytes[i + 2] == 116 && bytes[i + 3] == 97) {
            dataStart = i + 8;
            break;
          }
        }
        final dataBytes   = bytes.sublist(dataStart);
        final totalFrames = dataBytes.length ~/ outBlockAlign;
        final startFrame  = (startSec * outSampleRate).toInt().clamp(0, totalFrames);
        final endFrame    = (endSec   * outSampleRate).toInt().clamp(0, totalFrames);
        if (startFrame >= endFrame) {
          debugPrint('[Pipeline._sliceAudio] WAV 無效範圍：$startFrame-$endFrame');
          return;
        }
        slicedInt16Bytes = Uint8List.fromList(
            dataBytes.sublist(startFrame * outBlockAlign, endFrame * outBlockAlign));
        debugPrint('[Pipeline._sliceAudio] WAV 切分: $startFrame-$endFrame '
            '(rate=$outSampleRate ch=$outNumChannels ba=$outBlockAlign '
            '${slicedInt16Bytes.length ~/ outBlockAlign} 幀 dataStart=$dataStart)');
      } else {
        // raw float32 LE PCM：RealtimeAudioService 固定為 mono 44100 Hz
        outSampleRate  = 44100;
        outNumChannels = 1;
        outBlockAlign  = 2; // mono int16 = 2 bytes/frame
        if (bytes.length < 4) {
          debugPrint('[Pipeline._sliceAudio] PCM 檔案過小: ${bytes.length} bytes');
          return;
        }
        final byteData     = bytes.buffer.asByteData();
        final totalSamples = bytes.length ~/ 4; // float32 = 4 bytes/sample
        final startSample  = (startSec * outSampleRate).toInt().clamp(0, totalSamples);
        final endSample    = (endSec   * outSampleRate).toInt().clamp(0, totalSamples);
        if (startSample >= endSample) {
          debugPrint('[Pipeline._sliceAudio] PCM 無效範圍：$startSample-$endSample');
          return;
        }
        // float32 → int16 LE
        final int16Builder = BytesBuilder();
        for (int i = startSample; i < endSample; i++) {
          final f = byteData.getFloat32(i * 4, Endian.little);
          final clamped = f.isFinite ? f.clamp(-1.0, 1.0) : 0.0;
          final int16 = (clamped * 32767.0).round().clamp(-32768, 32767);
          final unsigned = int16 < 0 ? int16 + 65536 : int16;
          int16Builder.addByte(unsigned & 0xFF);
          int16Builder.addByte((unsigned >> 8) & 0xFF);
        }
        slicedInt16Bytes = int16Builder.toBytes();
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

      final finalWav = BytesBuilder();
      finalWav.add(wavHeader.toBytes());
      finalWav.add(slicedInt16Bytes);

      await File(dstAudioPath).writeAsBytes(finalWav.toBytes());
      debugPrint('[Pipeline._sliceAudio] ✅ 寫出完成 → $dstAudioPath');
    } catch (e) {
      debugPrint('[Pipeline._sliceAudio] 錯誤: $e');
    }
  }
}
