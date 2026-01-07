import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../services/imu_data_logger.dart';

/// 外部影片匯入工具：負責複製影片、嘗試找 IMU CSV 並建立歷史紀錄
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 匯入單支影片並回傳建立好的歷史紀錄條目
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,
    String? imuCsvPath,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null; // 找不到來源檔案就結束
    }

    final timestamp = DateTime.now();
    final baseName = _buildBaseName(timestamp);

    // 影片複製到 app 的資料夾（由 ImuDataLogger 管理）
    final persistedPath = await ImuDataLogger.instance.persistVideoFile(
      sourcePath: sourcePath,
      baseName: baseName,
    );

    final durationSeconds = await _resolveDurationSeconds(persistedPath);
    final sanitizedName = _normalizeName(originalName);

    // 盡量幫忙找 CSV，若有則複製到同資料夾
    final Map<String, String> imuCsvPaths = {};
    final String? csvDetected = imuCsvPath ?? _detectCsvForVideo(sourcePath);
    if (csvDetected != null &&
        csvDetected.isNotEmpty &&
        await File(csvDetected).exists()) {
      final String csvName = '_IMU.csv';
      final String csvTarget = p.join(File(persistedPath).parent.path, csvName);
      await File(csvDetected).copy(csvTarget);
      imuCsvPaths['IMPORTED'] = csvTarget;
    }

    return RecordingHistoryEntry(
      filePath: persistedPath,
      roundIndex: math.max(nextRoundIndex, 1),
      recordedAt: timestamp,
      durationSeconds: durationSeconds,
      imuConnected: false,
      customName: sanitizedName,
      imuCsvPaths: imuCsvPaths,
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

  /// 嘗試依影片路徑推測附近的 CSV
  String? _detectCsvForVideo(String videoPath) {
    final File videoFile = File(videoPath);
    if (!videoFile.existsSync()) return null;
    final dir = videoFile.parent;
    final base = p.basenameWithoutExtension(videoPath);

    final String sameName = p.join(dir.path, '$base.csv');
    if (File(sameName).existsSync()) return sameName;

    final candidates = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.csv'))
        .where((f) {
          final name = p.basenameWithoutExtension(f.path);
          return name.startsWith(base) || base.startsWith(name);
        })
        .map((f) => f.path)
        .toList();

    return candidates.isNotEmpty ? candidates.first : null;
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
