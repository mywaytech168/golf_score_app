import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';

/// 外部影片對入工具：複複影片、建立歷史紀錄
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 匯入單支影片並回傳建立好的歷史紀錄條目
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,

  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null; // 找不到來源檔案就結束
    }

    final timestamp = DateTime.now();
    final baseName = _buildBaseName(timestamp);

    // 影片複製到 app 的資料夾
final Directory videoDir = await getTemporaryDirectory();
    final targetDir = Directory(p.join(videoDir.path, 'videos'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final persistedPath = p.join(targetDir.path, '$baseName.mp4');
    await File(sourcePath).copy(persistedPath);

    final durationSeconds = await _resolveDurationSeconds(persistedPath);
    final sanitizedName = _normalizeName(originalName);


    return RecordingHistoryEntry(
      filePath: persistedPath,
      roundIndex: math.max(nextRoundIndex, 1),
      recordedAt: timestamp,
      durationSeconds: durationSeconds,
      customName: sanitizedName,
      thumbnailPath: null,
    );
  }

  /// 依現有歷史推算下一個 round index
  static int calculateNextRoundIndex(List<RecordingHistoryEntry> entries) {
    if (entries.isEmpty) {
      return 1;
    }
    final maxRound = entries.map((item) => item.roundIndex).fold<int>(0, math.max);
    return maxRound + 1;
  }

  String _buildBaseName(DateTime timestamp) {
    return 'import_${timestamp.millisecondsSinceEpoch}';
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

  /// 清理名稱並限制長度
  String? _normalizeName(String? originalName) {
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
