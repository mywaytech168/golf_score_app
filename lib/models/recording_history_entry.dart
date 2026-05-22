import 'package:flutter/foundation.dart';

/// 影片類型枚舉
enum VideoType {
  /// 原始影片
  original,
  /// 切片
  localClip;

  /// 中文標籤
  String get label {
    switch (this) {
      case VideoType.original:
        return '原始影片';
      case VideoType.localClip:
        return '切片';
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

  /// 影片原始錄製時間（顯示用）
  final DateTime recordedAt;

  /// 加入本機歷史的時間（排序用）；null 時 fallback 到 recordedAt
  /// 首次錄製時等於 recordedAt，從分享連結匯入時等於匯入時刻
  final DateTime? createdAt;

  /// 本輪錄影的設定秒數，供提示與說明使用
  final int durationSeconds;

  /// 允許使用者自訂的影片名稱，空字串視為未命名
  final String? customName;

  /// 影片縮圖的完整路徑，供首頁與歷史頁顯示預覽畫面
  final String? thumbnailPath;

  /// 影片類型（原始/切片）
  final VideoType videoType;

  /// 如果是原始影片，標記是否已被切片（只對 VideoType.original 有效）
  final bool isClipped;

  /// 標記是否已完成骨架分析（分析完後不再顯示「影片分析」選項）
  final bool isAnalyzed;

  /// 擊球時刻（秒數），用於切片標識
  final double? hitSecond;

  /// 切片開始秒數
  final double? startSecond;

  /// 切片結束秒數
  final double? endSecond;

  /// 聲音清脆度評分（0-100），來自音頻分析
  final double? audioCrispness;

  /// 是否為好球
  final bool? goodShot;

  /// 即時音頻分析評分標籤（Pro / Sweet / Keep going!）
  final String? audioLabel;

  /// 切片來源影片路徑（videoType == localClip 時有值）
  final String? sourceVideoPath;

  /// 音訊分析標籤（無聲音、無有效擊球等）
  /// 例如：['no_audio']、['no_valid_hits']、['pro']
  final List<String>? audioTags;

  /// 分享碼（16 碼）；null 表示從未分享過
  final String? shareCode;

  /// 分享碼到期時間（UTC）；null 或過去時間代表已過期
  final DateTime? shareExpiresAt;

  /// 從分享連結匯入時，記錄分享者的顯示名稱
  final String? sharerName;

  /// 是否已送出 AI Coach 分析（至少提交過一次，不論結果）
  final bool hasAiCoachAnalysis;

  /// 是否已透過「上傳分析資料」功能上傳至伺服器
  /// hasAiCoachAnalysis == true 亦視為已上傳
  final bool isUploaded;

  const RecordingHistoryEntry({
    required this.filePath,
    required this.roundIndex,
    required this.recordedAt,
    this.createdAt,
    required this.durationSeconds,
    this.customName,
    this.thumbnailPath,
    this.videoType = VideoType.original,
    this.isClipped = false,
    this.isAnalyzed = false,
    this.hitSecond,
    this.startSecond,
    this.endSecond,
    this.audioCrispness,
    this.goodShot,
    this.audioLabel,
    this.sourceVideoPath,
    this.audioTags,
    this.shareCode,
    this.shareExpiresAt,
    this.sharerName,
    this.hasAiCoachAnalysis = false,
    this.isUploaded = false,
  });

  /// 是否已上傳（明確標記 或 AI Coach 分析過）
  bool get isEffectivelyUploaded => isUploaded || hasAiCoachAnalysis;

  /// 排序用時間：優先用 createdAt，若無則 fallback 到 recordedAt
  DateTime get sortTime => createdAt ?? recordedAt;

  /// 分享碼是否仍在有效期內
  bool get isShareValid =>
      shareCode != null &&
      shareExpiresAt != null &&
      shareExpiresAt!.isAfter(DateTime.now().toUtc());

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
    bool? isAnalyzed,
    double? hitSecond,
    double? startSecond,
    double? endSecond,
    double? audioCrispness,
    bool? goodShot,
    String? audioLabel,
    String? sourceVideoPath,
    List<String>? audioTags,
    String? shareCode,
    DateTime? shareExpiresAt,
    DateTime? createdAt,
    String? sharerName,
    bool? hasAiCoachAnalysis,
    bool? isUploaded,
  }) {
    return RecordingHistoryEntry(
      filePath: filePath ?? this.filePath,
      roundIndex: roundIndex ?? this.roundIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      customName: customName ?? this.customName,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      videoType: videoType ?? this.videoType,
      isClipped: isClipped ?? this.isClipped,
      isAnalyzed: isAnalyzed ?? this.isAnalyzed,
      hitSecond: hitSecond ?? this.hitSecond,
      startSecond: startSecond ?? this.startSecond,
      endSecond: endSecond ?? this.endSecond,
      audioCrispness: audioCrispness ?? this.audioCrispness,
      goodShot: goodShot ?? this.goodShot,
      audioLabel: audioLabel ?? this.audioLabel,
      sourceVideoPath: sourceVideoPath ?? this.sourceVideoPath,
      audioTags: audioTags ?? this.audioTags,
      shareCode: shareCode ?? this.shareCode,
      shareExpiresAt: shareExpiresAt ?? this.shareExpiresAt,
      sharerName: sharerName ?? this.sharerName,
      hasAiCoachAnalysis: hasAiCoachAnalysis ?? this.hasAiCoachAnalysis,
      isUploaded: isUploaded ?? this.isUploaded,
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
      'isAnalyzed': isAnalyzed,
      'hitSecond': hitSecond,
      'startSecond': startSecond,
      'endSecond': endSecond,
      'audioCrispness': audioCrispness,
      'goodShot': goodShot,
      'audioLabel': audioLabel,
      'sourceVideoPath': sourceVideoPath,
      'audioTags': audioTags,
      'shareCode': shareCode,
      'shareExpiresAt': shareExpiresAt?.toUtc().toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'sharerName': sharerName,
      'hasAiCoachAnalysis': hasAiCoachAnalysis,
      'isUploaded': isUploaded,
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

    // 從 JSON 還原標籤列表
    final rawTags = json['audioTags'];
    List<String>? audioTags;
    if (rawTags is List) {
      audioTags = rawTags.whereType<String>().toList();
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
      isAnalyzed: (json['isAnalyzed'] as bool?) ?? false,
      hitSecond: (json['hitSecond'] as num?)?.toDouble(),
      startSecond: (json['startSecond'] as num?)?.toDouble(),
      endSecond: (json['endSecond'] as num?)?.toDouble(),
      audioCrispness: (json['audioCrispness'] as num?)?.toDouble(),
      goodShot: (json['goodShot'] as bool?),
      audioLabel: (json['audioLabel'] as String?),
      sourceVideoPath: (json['sourceVideoPath'] as String?),
      audioTags: audioTags,
      shareCode: json['shareCode'] as String?,
      shareExpiresAt: json['shareExpiresAt'] != null
          ? DateTime.tryParse(json['shareExpiresAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      sharerName: json['sharerName'] as String?,
      hasAiCoachAnalysis: (json['hasAiCoachAnalysis'] as bool?) ?? false,
      isUploaded:         (json['isUploaded']         as bool?) ?? false,
    );
  }
}
