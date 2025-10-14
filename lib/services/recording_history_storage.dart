import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/recording_history_entry.dart';

/// 錄影歷史儲存工具：負責將紀錄寫入 JSON 並在啟動時還原
class RecordingHistoryStorage {
  RecordingHistoryStorage._();

  /// 提供單例呼叫，避免重複建立檔案 IO 資源
  static final RecordingHistoryStorage instance = RecordingHistoryStorage._();

  static const String _folderName = 'imu_records'; // 與影片、CSV 相同的資料夾
  static const String _fileName = 'recording_history.json'; // 歷史紀錄檔案名稱

  /// 讀取歷史紀錄，失敗時回傳空陣列避免打斷 UI
  Future<List<RecordingHistoryEntry>> loadHistory() async {
    try {
      final file = await _resolveHistoryFile();
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }

      final decoded = jsonDecode(content);
      if (decoded is! List) {
        return [];
      }

      final entries = <RecordingHistoryEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          entries.add(RecordingHistoryEntry.fromJson(item));
        } else if (item is Map) {
          // 將動態 Map 轉為字串鍵值，避免型別轉換問題
          entries.add(
            RecordingHistoryEntry.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }

      // 依照時間新到舊排序，確保 UI 顯示一致
      entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      // 過濾掉已經不存在的影片，避免點擊後找不到檔案
      return entries
          .where((entry) => File(entry.filePath).existsSync())
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  /// 將最新歷史寫入檔案，若資料夾不存在會自動建立
  Future<void> saveHistory(List<RecordingHistoryEntry> entries) async {
    try {
      final file = await _resolveHistoryFile();
      final payload = entries.map((e) => e.toJson()).toList(growable: false);
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {
      // 寫入失敗時保持靜默，避免影響錄影流程
    }
  }

  /// 取得紀錄檔案路徑，並確保資料夾已建立
  Future<File> _resolveHistoryFile() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(baseDir.path, _folderName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return File(p.join(targetDir.path, _fileName));
  }
}
