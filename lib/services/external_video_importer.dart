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

    return RecordingHistoryEntry(
      filePath: persistedPath,
      roundIndex: math.max(nextRoundIndex, 1),
      recordedAt: timestamp,
      durationSeconds: durationSeconds,
      imuConnected: false,
      customName: sanitizedName,
      imuCsvPaths: const {},
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
