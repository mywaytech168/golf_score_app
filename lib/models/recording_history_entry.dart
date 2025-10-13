import 'package:flutter/foundation.dart';

/// 記錄單次錄影完成後的資料，方便首頁與歷史列表顯示
@immutable
class RecordingHistoryEntry {
  /// 錄影檔案儲存的完整路徑
  final String filePath;

  /// 第幾輪錄影完成，從 1 開始編號
  final int roundIndex;

  /// 錄影完成的時間戳記，提供排序與顯示
  final DateTime recordedAt;

  /// 本輪錄影的設定秒數，供提示與說明使用
  final int durationSeconds;

  /// 是否在錄影當下有連線 IMU，可用於顯示模式標籤
  final bool imuConnected;

  /// 允許使用者自訂的影片名稱，空字串視為未命名
  final String? customName;

  /// 對應本輪錄影的 IMU 原始資料 CSV 清單（deviceId -> 路徑）
  final Map<String, String> imuCsvPaths;

  const RecordingHistoryEntry({
    required this.filePath,
    required this.roundIndex,
    required this.recordedAt,
    required this.durationSeconds,
    required this.imuConnected,
    this.customName,
    this.imuCsvPaths = const {},
  });

  /// 建立更新後的新實例，方便調整時長或其他欄位
  RecordingHistoryEntry copyWith({
    String? filePath,
    int? roundIndex,
    DateTime? recordedAt,
    int? durationSeconds,
    bool? imuConnected,
    String? customName,
    Map<String, String>? imuCsvPaths,
  }) {
    return RecordingHistoryEntry(
      filePath: filePath ?? this.filePath,
      roundIndex: roundIndex ?? this.roundIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      imuConnected: imuConnected ?? this.imuConnected,
      customName: customName ?? this.customName,
      imuCsvPaths: imuCsvPaths ?? this.imuCsvPaths,
    );
  }

  /// 提供統一的顯示標題，例如「第 3 輪錄影」
  String get displayTitle {
    final name = customName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return '第\u0020${roundIndex}\u0020輪錄影';
  }

  /// 依據是否連線 IMU 回傳中文標籤，顯示當時的錄影模式
  String get modeLabel => imuConnected ? '含 IMU 資料' : '純錄影';

  /// 取得檔案名稱，透過正規式切割避免不同系統分隔符差異
  String get fileName {
    final segments = filePath.split(RegExp(r'[\\/]'));
    return segments.isNotEmpty ? segments.last : filePath;
  }

  /// 回傳所有 CSV 檔名，方便列表顯示或除錯
  List<String> get csvFileNames => imuCsvPaths.values
      .map((path) => path.split(RegExp(r'[\\/]')).last)
      .toList();

  /// 是否有對應的感測資料可供下載
  bool get hasImuCsv => imuCsvPaths.isNotEmpty;

  /// 將資料轉為 JSON，方便持久化儲存與還原
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'roundIndex': roundIndex,
      'recordedAt': recordedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'imuConnected': imuConnected,
      'customName': customName,
      'imuCsvPaths': imuCsvPaths,
    };
  }

  /// 從 JSON 還原歷史紀錄，並對缺漏欄位提供預設值
  factory RecordingHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawCsv = json['imuCsvPaths'];
    final parsedCsv = <String, String>{};
    if (rawCsv is Map) {
      // 將任何型別的鍵值轉為字串，避免類型不一致導致轉換失敗
      rawCsv.forEach((key, value) {
        parsedCsv[key.toString()] = value?.toString() ?? '';
      });
    }

    return RecordingHistoryEntry(
      filePath: (json['filePath'] as String?) ?? '',
      roundIndex: (json['roundIndex'] as int?) ?? 1,
      recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
          DateTime.now(),
      durationSeconds: (json['durationSeconds'] as int?) ?? 0,
      imuConnected: (json['imuConnected'] as bool?) ?? false,
      customName: (json['customName'] as String?) ?? '',
      imuCsvPaths: parsedCsv,
    );
  }
}
