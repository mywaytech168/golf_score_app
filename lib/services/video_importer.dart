import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import 'imu_data_logger.dart';

/// å¤–éƒ¨å½±ç??¯å…¥å·¥å…·ï¼šé?ä¸­è??†è?è£½ã€ç??¸è§£?è?ç´€?„å»ºç«‹æ?ç¨?
class ExternalVideoImporter {
  const ExternalVideoImporter();

  /// ?¯å…¥?‡å?å½±ç?ä¸¦å??³å»ºç«‹å??ç?æ­·å²ç´€?„å¯¦ä¾?
  Future<RecordingHistoryEntry?> importVideo({
    required String sourcePath,
    required int nextRoundIndex,
    String? originalName,
    String? imuCsvPath,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null; // ?¾ä??°ä?æºæ?æ¡ˆæ??´æ¥çµæ?
    }

    final timestamp = DateTime.now();
    final baseName = _buildBaseName(timestamp);

    // ?é??¢æ??„å„²å­˜æ??™è?è£½æ?æ¡ˆï?ç¢ºä?å½±ç??†ä¸­å­˜æ”¾??imu_records è³‡æ?å¤?
    final persistedPath = await ImuDataLogger.instance.persistVideoFile(
      sourcePath: sourcePath,
      baseName: baseName,
    );

    final durationSeconds = await _resolveDurationSeconds(persistedPath);
    final sanitizedName = _normalizeName(originalName);

    final Map<String, String> imuCsvPaths = {};
    final String? csvDetected = imuCsvPath ?? _detectCsvForVideo(sourcePath);
    if (csvDetected != null && csvDetected.isNotEmpty && await File(csvDetected).exists()) {
      // ?—è©¦?¨ä?æºæ?æ¡ˆæ??¨ç? CSV
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

  /// ä¾æ?æ­·å²ç´€?„æ¨ç®—ä?ä¸€?‹è¼ªæ¬¡ç·¨?Ÿï??¿å??‡æ—¢?‰è??™é?è¤?
  static int calculateNextRoundIndex(List<RecordingHistoryEntry> entries) {
    if (entries.isEmpty) {
      return 1;
    }
    final maxRound = entries.map((item) => item.roundIndex).fold<int>(0, math.max);
    return maxRound + 1;
  }

  /// ä»¥æ¯«ç§’æ??“æˆ³?¢ç??¯ä?æª”å?ï¼Œé¿?è??Ÿå??„å½±è¡ç?
  String _buildBaseName(DateTime timestamp) {
    return 'import_${timestamp.millisecondsSinceEpoch}';
  }

  /// ?—è©¦ä¾å½±?‡è·¯å¾‘åµæ¸¬å???CSV
  String? _detectCsvForVideo(String videoPath) {
    final File videoFile = File(videoPath);
    if (!videoFile.existsSync()) return null;
    final dir = videoFile.parent;
    final base = p.basenameWithoutExtension(videoPath);

    // ?ˆè©¦å®Œå…¨?Œå? .csv
    final String sameName = p.join(dir.path, '$base.csv');
    if (File(sameName).existsSync()) return sameName;

    // ?è©¦å¸¸è???IMU ?½å?ï¼ˆCHEST / RIGHT_WRIST ç­‰ï?
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

  /// ?ƒæ?å½±ç??·åº¦ä¸¦è‡³å°‘å???1 ç§’ï??¿å??ºç¾ 0 ç§’é€ æ? UI é¡¯ç¤º?°å¸¸
  Future<int> _resolveDurationSeconds(String videoPath) async {
    final controller = VideoPlayerController.file(File(videoPath));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      final seconds = duration.inSeconds;
      return math.max(seconds, 1);
    } catch (_) {
      return 1; // ?å??–å¤±?—æ?ä»?1 ç§’ä??ºä?åº?
    } finally {
      await controller.dispose();
    }
  }

  /// ?–å‡º?Ÿå?æª”å?ä¸¦ç§»?¤å‰¯æª”å?ï¼Œé??¶é•·åº¦é¿??UI ?†ç?
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

