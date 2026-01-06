import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import 'imu_data_logger.dart';

/// 外部影片匯入工具：集中處理複製、秒數解析與紀錄建立流程
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 匯入指定影片並回傳建立完成的歷史紀錄實例
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,
    String? imuCsvPath,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null; // 找不到來源檔案時直接結束
    }

    final timestamp = DateTime.now();
    final baseName = _buildBaseName(timestamp);

    // 透過既有的儲存服務複製檔案，確保影片集中存放於 imu_records 資料夾
    final persistedPath = await ImuDataLogger.instance.persistVideoFile(
      sourcePath: sourcePath,
      baseName: baseName,
    );

    final durationSeconds = await _resolveDurationSeconds(persistedPath);
    final sanitizedName = _normalizeName(originalName);

    final Map<String, String> imuCsvPaths = {};
    final String? csvDetected = imuCsvPath ?? _detectCsvForVideo(sourcePath);
    if (csvDetected != null && csvDetected.isNotEmpty && await File(csvDetected).exists()) {
      // 嘗試用來源檔案所在的 CSV
      imuCsvPaths['AUTO'] = csvDetected;
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

  /// 依據歷史紀錄推算下一個輪次編號，避免與既有資料重複
  static int calculateNextRoundIndex(List<RecordingHistoryEntry> entries) {
    if (entries.isEmpty) {
      return 1;
    }
    final maxRound = entries.map((item) => item.roundIndex).fold<int>(0, math.max);
    return maxRound + 1;
  }

  /// 以毫秒時間戳產生唯一檔名，避免與原始錄影衝突
  String _buildBaseName(DateTime timestamp) {
    return 'import_${timestamp.millisecondsSinceEpoch}';
  }

  /// 嘗試依影片路徑偵測同名 CSV
  String? _detectCsvForVideo(String videoPath) {
    final File videoFile = File(videoPath);
    if (!videoFile.existsSync()) return null;
    final dir = videoFile.parent;
    final base = p.basenameWithoutExtension(videoPath);

    // 先試完全同名 .csv
    final String sameName = p.join(dir.path, '$base.csv');
    if (File(sameName).existsSync()) return sameName;

    // 再試常見的 IMU 命名（CHEST / RIGHT_WRIST 等）
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

  /// 掃描影片長度並至少回傳 1 秒，避免出現 0 秒造成 UI 顯示異常
  Future<int> _resolveDurationSeconds(String videoPath) async {
    final controller = VideoPlayerController.file(File(videoPath));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      final seconds = duration.inSeconds;
      return math.max(seconds, 1);
    } catch (_) {
      return 1; // 初始化失敗時以 1 秒作為保底
    } finally {
      await controller.dispose();
    }
  }

  /// 取出原始檔名並移除副檔名，限制長度避免 UI 爆版
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
