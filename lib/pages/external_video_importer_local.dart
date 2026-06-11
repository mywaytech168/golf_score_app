import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/recording_history_entry.dart';
import '../services/analysis_progress_service.dart';

/// 外部影片導入工具：只複製影片、驗證時長、建立歷史紀錄
/// 
/// 生成與 RecordScreen 相同的文件結構：
/// golf_recordings/{sessionId}/
///   ├─ swing.mp4 (導入的視頻)
///   ├─ pose_landmarks.csv (分析後產生)
///   ├─ audio.pcm (分析後產生)
///   └─ thumbnail.jpg (視頻封面)
/// 
/// 驗證規則：只接受 1-600 秒的影片
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 匯入單支影片：只複製影片、驗證時長、建立歷史紀錄
  /// 分析（骨架、音訊、擊球偵測）在歷史頁面按鈕觸發時執行
  /// 
  /// 時長驗證：
  ///   - < 1秒：拒絕
  ///   - 1-600秒：接受
  ///   - > 600秒：拒絕
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,
    void Function(double progress, String label)? onProgress,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      debugPrint('[Importer] ❌ 來源檔案不存在: $sourcePath');
      return null;
    }

    try {
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final appDir = await getApplicationDocumentsDirectory();
      final sessionDir = p.join(appDir.path, 'golf_recordings', sessionId);
      await Directory(sessionDir).create(recursive: true);

      // iOS：直接複製 .mov，不轉檔（iOS 原生支援，轉檔太慢）
      // Android：轉檔為標準 MP4（H.264 + AAC）
      // 其他平台：直接複製
      final String videoPath;
      if (Platform.isIOS) {
        videoPath = p.join(sessionDir, 'swing.mov');
        onProgress?.call(0.0, '複製影片中...');
        await File(sourcePath).copy(videoPath);
      } else if (Platform.isAndroid) {
        videoPath = p.join(sessionDir, 'swing.mp4');
        onProgress?.call(0.0, '轉檔準備中...');

        // 監聽 Kotlin sendProgress("transcode") → EventChannel → 更新進度 Dialog
        final progressSvc = AnalysisProgressService.instance;
        void onTranscodeProgress() {
          if (progressSvc.currentOp == 'transcode') {
            final (prog, label) = progressSvc.progress.value;
            onProgress?.call(prog, label);
          }
        }
        progressSvc.progress.addListener(onTranscodeProgress);

        try {
          const channel = MethodChannel('com.example.golf_score_app/video_transcoder');
          final transcoded = await channel.invokeMethod<String>(
            'transcodeToMp4',
            {'srcPath': sourcePath, 'dstPath': videoPath},
          );
          if (transcoded == null) throw Exception('transcodeToMp4 未回傳路徑');
        } finally {
          progressSvc.progress.removeListener(onTranscodeProgress);
        }
      } else {
        videoPath = p.join(sessionDir, 'swing.mp4');
        onProgress?.call(0.0, '複製影片中...');
        await File(sourcePath).copy(videoPath);
      }

      // 取得時長並驗證
      final durationSeconds = await _resolveDurationSeconds(videoPath);
      if (durationSeconds < 1 || durationSeconds > 600) {
        debugPrint('[Importer] ❌ 影片時長不符：$durationSeconds 秒 (需 1-600 秒)');
        await File(videoPath).delete();
        await Directory(sessionDir).delete();
        onProgress?.call(1.0, '影片時長不符 (需 1-600 秒)');
        return null;
      }

      // 生成縮圖
      onProgress?.call(0.5, '生成縮圖中...');
      final thumbnailPath = await _generateThumbnail(videoPath);
      final sanitizedName = _normalizeImportName(originalName);

      onProgress?.call(1.0, '匯入完成 ✅');
      debugPrint('[Importer] ✅ 導入完成: sessionId=$sessionId, '
          'duration=$durationSeconds秒, thumbnail=$thumbnailPath');

      return RecordingHistoryEntry(
        filePath: videoPath,
        roundIndex: math.max(nextRoundIndex, 1),
        recordedAt: DateTime.now(),
        durationSeconds: durationSeconds,
        customName: sanitizedName,
        thumbnailPath: thumbnailPath,
      );
    } catch (e) {
      debugPrint('[Importer] ❌ 導入失敗: $e');
      return null;
    }
  }

  /// 依現有歷史推算下一個 round index
  static int calculateNextRoundIndex(List<RecordingHistoryEntry> entries) {
    if (entries.isEmpty) {
      return 1;
    }
    final maxRound = entries.map((item) => item.roundIndex).fold<int>(0, math.max);
    return maxRound + 1;
  }

  /// 生成視頻封面
  ///
  /// Android HEVC-in-MOV 支援差，採多策略 fallback：
  ///   1. thumbnailFile at 0ms with maxHeight:256
  ///   2. thumbnailFile at 1000ms with maxHeight:256
  ///   3. thumbnailData at 0ms → 手動寫檔
  Future<String?> _generateThumbnail(String videoPath) async {
    final sessionDir = File(videoPath).parent.path;
    final outPath = p.join(sessionDir, 'thumbnail.jpg');

    for (final timeMs in [0, 1000, 3000]) {
      try {
        final path = await vt.VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: outPath,
          imageFormat: vt.ImageFormat.JPEG,
          maxHeight: 256,
          timeMs: timeMs,
          quality: 75,
        );
        if (path != null && path.isNotEmpty) {
          debugPrint('[Importer] ✅ 縮圖 (${timeMs}ms): $path');
          return path;
        }
      } catch (e) {
        debugPrint('[Importer] ⚠️ thumbnailFile ${timeMs}ms 失敗: $e');
      }
    }

    // 最後手段：thumbnailData → 手動寫檔
    try {
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: vt.ImageFormat.JPEG,
        maxHeight: 256,
        timeMs: 0,
        quality: 75,
      );
      if (bytes != null && bytes.isNotEmpty) {
        await File(outPath).writeAsBytes(bytes);
        debugPrint('[Importer] ✅ 縮圖 (thumbnailData fallback): $outPath');
        return outPath;
      }
    } catch (e) {
      debugPrint('[Importer] ⚠️ thumbnailData 失敗: $e');
    }

    debugPrint('[Importer] ❌ 所有縮圖策略失敗: $videoPath');
    return null;
  }

  /// 解析影片長度，至少回傳 1 秒避免 UI 顯示為 0
  Future<int> _resolveDurationSeconds(String videoPath) async {
    final controller = VideoPlayerController.file(File(videoPath));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      final seconds = duration.inSeconds;
      return math.max(seconds, 1);
    } catch (_) {
      return 1; // 失敗就給預設 1 秒
    } finally {
      await controller.dispose();
    }
  }

  /// 清理導入的名稱並限制長度
  String? _normalizeImportName(String? originalName) {
    final raw = originalName?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final withoutExtension = p.basenameWithoutExtension(raw);
    if (withoutExtension.isEmpty) {
      return null;
    }
    return withoutExtension.length > 40
        ? withoutExtension.substring(0, 40)
        : withoutExtension;
  }
}
