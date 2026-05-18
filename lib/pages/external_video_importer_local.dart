import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/recording_history_entry.dart';

/// 外部影片導入工具：只複製影片、驗證時長、建立歷史紀錄
/// 
/// 生成與 RecordScreen 相同的文件結構：
/// golf_recordings/{sessionId}/
///   ├─ swing.mp4 (導入的視頻)
///   ├─ pose_landmarks.csv (分析後產生)
///   ├─ audio.pcm (分析後產生)
///   └─ thumbnail.jpg (視頻封面)
/// 
/// 驗證規則：只接受 1-120 秒的影片
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 匯入單支影片：只複製影片、驗證時長、建立歷史紀錄
  /// 分析（骨架、音訊、擊球偵測）在歷史頁面按鈕觸發時執行
  /// 
  /// 時長驗證：
  ///   - < 1秒：拒絕
  ///   - 1-120秒：接受
  ///   - > 120秒：拒絕
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

      // 複製影片
      onProgress?.call(0.0, '複製影片中...');
      final videoPath = p.join(sessionDir, 'swing.mp4');
      await File(sourcePath).copy(videoPath);

      // 取得時長並驗證
      final durationSeconds = await _resolveDurationSeconds(videoPath);
      if (durationSeconds < 1 || durationSeconds > 120) {
        debugPrint('[Importer] ❌ 影片時長不符：$durationSeconds 秒 (需 1-120 秒)');
        await File(videoPath).delete();
        await Directory(sessionDir).delete();
        onProgress?.call(1.0, '影片時長不符 (需 1-120 秒)');
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

  /// 生成視頻封面（與 RecordScreen 的方式相同）
  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final sessionDir = File(videoPath).parent.path;
      return await vt.VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: sessionDir,
        imageFormat: vt.ImageFormat.JPEG,
        quality: 75,
      );
    } catch (e) {
      debugPrint('[Importer] ⚠️ 生成封面失敗: $e');
      return null;
    }
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
