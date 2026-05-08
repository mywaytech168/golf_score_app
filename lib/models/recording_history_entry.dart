import 'package:flutter/foundation.dart';

/// 影片類型枚舉
enum VideoType {
  /// 本地原始影片
  original,
  /// 本地切片
  localClip;

  /// 中文標籤
  String get label {
    switch (this) {
      case VideoType.original:
        return '本地原始影片';
      case VideoType.localClip:
        return '本地切片';
    }
  }

  /// 圖標表示
  String get icon {
    switch (this) {
      case VideoType.original:
        return '🎥';
      case VideoType.localClip:
        return '✂️';
    }
  }
}

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

  /// 允許使用者自訂的影片名稱，空字串視為未命名
  final String? customName;

  /// 影片縮圖的完整路徑，供首頁與歷史頁顯示預覽畫面
  final String? thumbnailPath;

  /// 影片類型（原始/本地切片）
  final VideoType videoType;

  /// 如果是原始影片，標記是否已被切片（只對 VideoType.original 有效）
  final bool isClipped;

  /// 擊球時刻（秒數），用於切片標識
  final double? hitSecond;

  /// 切片開始秒數
  final double? startSecond;

  /// 切片結束秒數
  final double? endSecond;

  /// 聲音清脆度評分（0-100），來自本地音頻分析
  final double? audioCrispness;

  /// 是否為好球
  final bool? goodShot;

  /// 即時音頻分析評分標籤（Pro / Sweet / Keep going!）
  final String? audioLabel;

  const RecordingHistoryEntry({
    required this.filePath,
    required this.roundIndex,
    required this.recordedAt,
    required this.durationSeconds,
    this.customName,
    this.thumbnailPath,
    this.videoType = VideoType.original,
    this.isClipped = false,
    this.hitSecond,
    this.startSecond,
    this.endSecond,
    this.audioCrispness,
    this.goodShot,
    this.audioLabel,
  });

  /// 建立更新後的新實例，方便調整時長或其他欄位
  RecordingHistoryEntry copyWith({
    String? filePath,
    int? roundIndex,
    DateTime? recordedAt,
    int? durationSeconds,
    String? customName,
    String? thumbnailPath,
    VideoType? videoType,
    bool? isClipped,
    double? hitSecond,
    double? startSecond,
    double? endSecond,
    double? audioCrispness,
    bool? goodShot,
    String? audioLabel,
  }) {
    return RecordingHistoryEntry(
      filePath: filePath ?? this.filePath,
      roundIndex: roundIndex ?? this.roundIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      customName: customName ?? this.customName,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      videoType: videoType ?? this.videoType,
      isClipped: isClipped ?? this.isClipped,
      hitSecond: hitSecond ?? this.hitSecond,
      startSecond: startSecond ?? this.startSecond,
      endSecond: endSecond ?? this.endSecond,
      audioCrispness: audioCrispness ?? this.audioCrispness,
      goodShot: goodShot ?? this.goodShot,
      audioLabel: audioLabel ?? this.audioLabel,
    );
  }

  /// 提供統一的顯示標題，例如「第 3 輪錄影」
  String get displayTitle {
    final name = customName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return '第 $roundIndex 輪錄影';
  }

  /// 取得檔案名稱，透過正規式切割避免不同系統分隔符差異
  String get fileName {
    final segments = filePath.split(RegExp(r'[\\/]'));
    return segments.isNotEmpty ? segments.last : filePath;
  }

  /// 將資料轉為 JSON，方便持久化儲存與還原
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'roundIndex': roundIndex,
      'recordedAt': recordedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'customName': customName,
      'thumbnailPath': thumbnailPath,
      'videoType': videoType.name,
      'isClipped': isClipped,
      'hitSecond': hitSecond,
      'startSecond': startSecond,
      'endSecond': endSecond,
      'audioCrispness': audioCrispness,
      'goodShot': goodShot,
      'audioLabel': audioLabel,
    };
  }

  /// 從 JSON 還原歷史紀錄，並對缺漏欄位提供預設值
  factory RecordingHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawThumbnail = (json['thumbnailPath'] as String?)?.trim();

    // 從字串恢復影片類型，預設為原始影片
    VideoType videoType = VideoType.original;
    final videoTypeStr = json['videoType'] as String?;
    if (videoTypeStr != null) {
      try {
        videoType = VideoType.values.byName(videoTypeStr);
      } catch (_) {
        // 舊資料可能含 cloudOriginal / cloudClip，一律回退為 original
      }
    }

    return RecordingHistoryEntry(
      filePath: (json['filePath'] as String?) ?? '',
      roundIndex: (json['roundIndex'] as int?) ?? 1,
      recordedAt:
          DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.now(),
      durationSeconds: (json['durationSeconds'] as int?) ?? 0,
      customName: (json['customName'] as String?) ?? '',
      thumbnailPath:
          rawThumbnail == null || rawThumbnail.isEmpty ? null : rawThumbnail,
      videoType: videoType,
      isClipped: (json['isClipped'] as bool?) ?? false,
      hitSecond: (json['hitSecond'] as num?)?.toDouble(),
      startSecond: (json['startSecond'] as num?)?.toDouble(),
      endSecond: (json['endSecond'] as num?)?.toDouble(),
      audioCrispness: (json['audioCrispness'] as num?)?.toDouble(),
      goodShot: (json['goodShot'] as bool?),
      audioLabel: (json['audioLabel'] as String?),
    );
  }
}
