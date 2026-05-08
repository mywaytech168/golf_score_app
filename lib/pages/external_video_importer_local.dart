import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/recording_history_entry.dart';

/// 外部影片對入工具：複複影片、建立歷史紀錄
/// 
/// 生成與 RecordScreen 相同的文件結構：
/// golf_recordings/{sessionId}/
///   ├─ swing.mp4 (導入的視頻)
///   ├─ pose_landmarks.csv (元數據 - 導入時為空)
///   ├─ audio.pcm (音頻 - 導入時為空)
///   └─ thumbnail.jpg (視頻封面)
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 匯入單支影片並回傳建立好的歷史紀錄條目
  /// 生成與錄製相同的目錄結構，確保導入與錄製的文件格式一致
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,

  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null; // 找不到來源檔案就結束
    }

    try {
      // 生成與 RecordScreen 相同的 sessionId
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // 創建 golf_recordings/{sessionId}/ 目錄結構
      final appDir = await getApplicationDocumentsDirectory();
      final sessionDir = p.join(appDir.path, 'golf_recordings', sessionId);
      final sessionDirectory = Directory(sessionDir);
      if (!await sessionDirectory.exists()) {
        await sessionDirectory.create(recursive: true);
      }

      // 複製視頻為 swing.mp4（與錄製產生的名稱一致）
      final videoPath = p.join(sessionDir, 'swing.mp4');
      await File(sourcePath).copy(videoPath);

      // 建立空的 pose_landmarks.csv（導入時無實時姿態數據）
      final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
      final csvFile = File(csvPath);
      await csvFile.writeAsString('frame,time_sec,landmarks\n'); // CSV 標題行

      // 建立空的 audio.pcm（導入時不進行實時音頻捕獲）
      final audioPath = p.join(sessionDir, 'audio.pcm');
      final audioFile = File(audioPath);
      await audioFile.writeAsBytes([]);

      // 生成視頻封面（與錄製方式相同）
      final thumbnailPath = await _generateThumbnail(videoPath);

      // 解析視頻時長
      final durationSeconds = await _resolveDurationSeconds(videoPath);
      final sanitizedName = _normalizeImportName(originalName);

      debugPrint('[Importer] ✅ 導入完成: sessionId=$sessionId, video=$videoPath, thumbnail=$thumbnailPath');

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
