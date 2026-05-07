import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';

/// 外部影片導入工具：複製、解析、紀錄建立歷史
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// 導入外部影片並建立對應的歷史紀錄實例
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null;
    }

    final timestamp = DateTime.now();
    final baseName = _buildBaseName(timestamp);

    // 複製影片檔案到應用程式的暫存目錄
    final cacheDir = await getTemporaryDirectory();
    final fileName = '$baseName${p.extension(sourcePath)}';
    final persistedPath = p.join(cacheDir.path, fileName);
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

  /// 依歷史紀錄推算下一輪次編號，避免既存編號衝突
  static int calculateNextRoundIndex(List<RecordingHistoryEntry> entries) {
    if (entries.isEmpty) {
      return 1;
    }
    final maxRound = entries.map((item) => item.roundIndex).fold<int>(0, math.max);
    return maxRound + 1;
  }

  /// 以毫秒時戳建構檔案名，避免影片名衝突
  String _buildBaseName(DateTime timestamp) {
    return 'import_${timestamp.millisecondsSinceEpoch}';
  }

  /// 讀取影片時長並至少回傳 1 秒，避免顯示 0 秒造成 UI 異常
  Future<int> _resolveDurationSeconds(String videoPath) async {
    final controller = VideoPlayerController.file(File(videoPath));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      final seconds = duration.inSeconds;
      return math.max(seconds, 1);
    } catch (_) {
      return 1;
    } finally {
      await controller.dispose();
    }
  }

  /// 抽出原檔名並移除副檔名，限制長度避免 UI 過寬
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
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';

/// 外部影�??�入工具：�?中�??��?製、�??�解?��?紀?�建立�?�?
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// ?�入?��?影�?並�??�建立�??��?歷史紀?�實�?
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null; // ?��??��?源�?案�??�接結�?
    }

    final timestamp = DateTime.now();
    final baseName = _buildBaseName(timestamp);

    // 複製影片檔案到應用程式的暫存目錄
    final cacheDir = await getTemporaryDirectory();
    final fileName = '$baseName${p.extension(sourcePath)}';
    final persistedPath = p.join(cacheDir.path, fileName);
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

  /// 依�?歷史紀?�推算�?一?�輪次編?��??��??�既?��??��?�?
  static int calculateNextRoundIndex(List<RecordingHistoryEntry> entries) {
    if (entries.isEmpty) {
      return 1;
    }
    final maxRound = entries.map((item) => item.roundIndex).fold<int>(0, math.max);
    return maxRound + 1;
  }

  /// 以毫秒�??�戳?��??��?檔�?，避?��??��??�影衝�?
  String _buildBaseName(DateTime timestamp) {
    return 'import_${timestamp.millisecondsSinceEpoch}';
  }

  /// ?�試依影?�路徑偵測�???CSV
  String? _detectCsvForVideo(String videoPath) {
    final File videoFile = File(videoPath);
    if (!videoFile.existsSync()) return null;
    final dir = videoFile.parent;
    final base = p.basenameWithoutExtension(videoPath);

    // ?�試完全?��? .csv
    final String sameName = p.join(dir.path, '$base.csv');
    if (File(sameName).existsSync()) return sameName;

    // ?�試常�???IMU ?��?（CHEST / RIGHT_WRIST 等�?
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

  /// ?��?影�??�度並至少�???1 秒�??��??�現 0 秒造�? UI 顯示?�常
  Future<int> _resolveDurationSeconds(String videoPath) async {
    final controller = VideoPlayerController.file(File(videoPath));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      final seconds = duration.inSeconds;
      return math.max(seconds, 1);
    } catch (_) {
      return 1; // ?��??�失?��?�?1 秒�??��?�?
    } finally {
      await controller.dispose();
    }
  }

  /// ?�出?��?檔�?並移?�副檔�?，�??�長度避??UI ?��?
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

