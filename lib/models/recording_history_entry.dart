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

  const RecordingHistoryEntry({
    required this.filePath,
    required this.roundIndex,
    required this.recordedAt,
    required this.durationSeconds,
    required this.imuConnected,
  });

  /// 提供統一的顯示標題，例如「第 3 輪錄影」
  String get displayTitle => '第\u0020${roundIndex}\u0020輪錄影';

  /// 依據是否連線 IMU 回傳中文標籤，顯示當時的錄影模式
  String get modeLabel => imuConnected ? '含 IMU 資料' : '純錄影';

  /// 取得檔案名稱，透過正規式切割避免不同系統分隔符差異
  String get fileName {
    final segments = filePath.split(RegExp(r'[\\/]'));
    return segments.isNotEmpty ? segments.last : filePath;
  }
}
