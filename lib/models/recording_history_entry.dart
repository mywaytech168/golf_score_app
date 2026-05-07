import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';

/// 影片類型枚舉
enum VideoType {
  /// 本地原始影片
  original,
  /// 本地切片
  localClip,
  /// 雲端原始影片
  cloudOriginal,
  /// 雲端切片
  cloudClip;

  /// 中文標籤
  String get label {
    switch (this) {
      case VideoType.original:
        return '本地原始影片';
      case VideoType.localClip:
        return '本地切片';
      case VideoType.cloudOriginal:
        return '雲端原始影片';
      case VideoType.cloudClip:
        return '雲端切片';
    }
  }

  /// 圖標表示
  String get icon {
    switch (this) {
      case VideoType.original:
        return '🎥';
      case VideoType.localClip:
        return '✂️';
      case VideoType.cloudOriginal:
        return '☁️';
      case VideoType.cloudClip:
        return '☁️✂️';
    }
  }
}

/// 檔案處理狀態枚舉（服務器端的隊列狀態）
enum ProcessingStatus {
  /// 準備中
  ready,
  /// 排隊中
  queued,
  /// 處理中
  processing,
  /// 已處理
  completed,
  /// 失敗
  failed,
  /// 未開始
  notStarted;

  /// 中文標籤
  String get label {
    switch (this) {
      case ProcessingStatus.ready:
        return '準備中';
      case ProcessingStatus.queued:
        return '排隊中';
      case ProcessingStatus.processing:
        return '處理中';
      case ProcessingStatus.completed:
        return '✓ 完成';
      case ProcessingStatus.failed:
        return '✗ 失敗';
      case ProcessingStatus.notStarted:
        return '未開始';
    }
  }

  /// 徽章顏色
  Color get badgeColor {
    switch (this) {
      case ProcessingStatus.ready:
        return const Color(0xFF90CAF9); // 淺藍色
      case ProcessingStatus.queued:
        return const Color(0xFFFBC02D); // 黃色
      case ProcessingStatus.processing:
        return const Color(0xFF1976D2); // 藍色
      case ProcessingStatus.completed:
        return const Color(0xFF388E3C); // 綠色
      case ProcessingStatus.failed:
        return const Color(0xFFC62828); // 紅色
      case ProcessingStatus.notStarted:
        return const Color(0xFF757575); // 灰色
    }
  }

  /// 從服務器狀態字符串轉換
  static ProcessingStatus fromString(String? status) {
    switch (status?.toLowerCase()) {
      case 'ready':
        return ProcessingStatus.ready;
      case 'queued':
        return ProcessingStatus.queued;
      case 'processing':
        return ProcessingStatus.processing;
      case 'completed':
        return ProcessingStatus.completed;
      case 'failed':
        return ProcessingStatus.failed;
      default:
        return ProcessingStatus.notStarted;
    }
  }
}

/// 同步狀態枚舉
enum SyncStatus {
  /// 已同步到雲端
  synced,
  /// 未同步到雲端
  notSynced,
  /// 同步中
  syncing,
  /// 同步失敗
  failed;

  /// 中文標籤
  String get label {
    switch (this) {
      case SyncStatus.synced:
        return '✓ 已同步';
      case SyncStatus.notSynced:
        return '↻ 未同步';
      case SyncStatus.syncing:
        return '⟳ 同步中';
      case SyncStatus.failed:
        return '✗ 失敗';
    }
  }

  /// 徽章顏色
  Color get badgeColor {
    switch (this) {
      case SyncStatus.synced:
        return const Color(0xFF1E8E5A); // 綠色
      case SyncStatus.notSynced:
        return const Color(0xFF1E88E5); // 藍色
      case SyncStatus.syncing:
        return const Color(0xFFFF9800); // 橙色
      case SyncStatus.failed:
        return const Color(0xFFD32F2F); // 紅色
    }
  }
}

/// 上傳狀態枚舉
enum UploadStatus {
  /// 本地只 - 未上傳
  local,
  /// 上傳中
  uploading,
  /// 已上傳
  uploaded,
  /// 上傳失敗
  failed;

  /// 轉為使用者可讀的中文標籤
  String get label {
    switch (this) {
      case UploadStatus.local:
        return '本地';
      case UploadStatus.uploading:
        return '上傳中...';
      case UploadStatus.uploaded:
        return '已上傳';
      case UploadStatus.failed:
        return '上傳失敗';
    }
  }

  /// 轉為簡短標籤（UI 顯示用）
  String get badge {
    switch (this) {
      case UploadStatus.local:
        return '📱 本地';
      case UploadStatus.uploading:
        return '⬆️ 上傳中';
      case UploadStatus.uploaded:
        return '☁️ 已上傳';
      case UploadStatus.failed:
        return '❌ 失敗';
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

  /// 上傳狀態：本地 | 上傳中 | 已上傳 | 上傳失敗
  final UploadStatus uploadStatus;

  /// 上傳到雲端的影片 ID（已上傳時有值）
  final String? cloudVideoId;

  /// 上傳失敗的原因（uploadStatus=failed 時有值）
  final String? uploadError;

  /// 最後一次上傳嘗試的時間
  final DateTime? lastUploadAttempt;

  /// 影片類型（原始/本地切片/雲端切片）
  final VideoType videoType;

  /// 同步狀態
  final SyncStatus syncStatus;

  /// 服務器處理狀態（隊列狀態）
  final ProcessingStatus processingStatus;

  /// 服務器處理是否成功
  final bool? processingSuccess;

  /// 後端返回的主要文件類型（pose_phase_trajectory_video / clip / original）
  final String? mainFileType;

  /// 如果是原始影片，標記是否已被切片（只對 VideoType.original 有效）
  final bool isClipped;

  /// 對應的本地檔案路徑（當影片上傳到雲端時，記錄本地檔案的路徑，用於追踪來源）
  final String? sourceLocalFilePath;

  /// 擊球時刻（秒數），用於切片標識
  final double? hitSecond;

  /// 切片開始秒數
  final double? startSecond;

  /// 切片結束秒數
  final double? endSecond;



  /// 聲音清脆度評分（0-100），來自後端音頻分析
  final double? audioCrispness;

  /// 是否為好球，來自後端分析（基於多重指標）
  final bool? goodShot;

  const RecordingHistoryEntry({
    required this.filePath,
    required this.roundIndex,
    required this.recordedAt,
    required this.durationSeconds,
    this.customName,
    this.thumbnailPath,
    this.uploadStatus = UploadStatus.local,
    this.cloudVideoId,
    this.uploadError,
    this.lastUploadAttempt,
    this.videoType = VideoType.original,
    this.syncStatus = SyncStatus.notSynced,
    this.processingStatus = ProcessingStatus.notStarted,
    this.processingSuccess,
    this.mainFileType,
    this.isClipped = false,
    this.sourceLocalFilePath,
    this.hitSecond,
    this.startSecond,
    this.endSecond,
    this.audioCrispness,
    this.goodShot,
  });

  /// 建立更新後的新實例，方便調整時長或其他欄位
  RecordingHistoryEntry copyWith({
    String? filePath,
    int? roundIndex,
    DateTime? recordedAt,
    int? durationSeconds,
    String? customName,
    String? thumbnailPath,
    UploadStatus? uploadStatus,
    String? cloudVideoId,
    bool clearCloudVideoId = false,
    String? uploadError,
    DateTime? lastUploadAttempt,
    VideoType? videoType,
    SyncStatus? syncStatus,
    ProcessingStatus? processingStatus,
    bool? processingSuccess,
    String? mainFileType,
    bool? isClipped,
    String? sourceLocalFilePath,
    double? hitSecond,
    double? startSecond,
    double? endSecond,
    double? audioCrispness,
    bool? goodShot,
  }) {
    return RecordingHistoryEntry(
      filePath: filePath ?? this.filePath,
      roundIndex: roundIndex ?? this.roundIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      customName: customName ?? this.customName,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      cloudVideoId: clearCloudVideoId ? null : (cloudVideoId ?? this.cloudVideoId),
      uploadError: uploadError ?? this.uploadError,
      lastUploadAttempt: lastUploadAttempt ?? this.lastUploadAttempt,
      videoType: videoType ?? this.videoType,
      syncStatus: syncStatus ?? this.syncStatus,
      processingStatus: processingStatus ?? this.processingStatus,
      processingSuccess: processingSuccess ?? this.processingSuccess,
      mainFileType: mainFileType ?? this.mainFileType,
      isClipped: isClipped ?? this.isClipped,
      sourceLocalFilePath: sourceLocalFilePath ?? this.sourceLocalFilePath,
      hitSecond: hitSecond ?? this.hitSecond,
      startSecond: startSecond ?? this.startSecond,
      endSecond: endSecond ?? this.endSecond,
      audioCrispness: audioCrispness ?? this.audioCrispness,
      goodShot: goodShot ?? this.goodShot,
    );
  }

  /// 提供統一的顯示標題，例如「第 3 輪錄影」
  String get displayTitle {
    final name = customName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
  return '第 ${roundIndex} 輪錄影';
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
      'uploadStatus': uploadStatus.name,
      'cloudVideoId': cloudVideoId,
      'uploadError': uploadError,
      'lastUploadAttempt': lastUploadAttempt?.toIso8601String(),
      'videoType': videoType.name,
      'syncStatus': syncStatus.name,
      'processingStatus': processingStatus.name,
      'processingSuccess': processingSuccess,
      'mainFileType': mainFileType,
      'isClipped': isClipped,
      'sourceLocalFilePath': sourceLocalFilePath,
      'hitSecond': hitSecond,
      'startSecond': startSecond,
      'endSecond': endSecond,
      'audioCrispness': audioCrispness,
      'goodShot': goodShot,
    };
  }

  /// 從 JSON 還原歷史紀錄，並對缺漏欄位提供預設值
  factory RecordingHistoryEntry.fromJson(Map<String, dynamic> json) {

    final rawThumbnail = (json['thumbnailPath'] as String?)?.trim();
    
    // 從字串恢復上傳狀態，預設為本地
    UploadStatus uploadStatus = UploadStatus.local;
    final statusStr = json['uploadStatus'] as String?;
    if (statusStr != null) {
      try {
        uploadStatus = UploadStatus.values.byName(statusStr);
      } catch (e) {
        debugPrint('Unknown uploadStatus: $statusStr, defaulting to local');
      }
    }

    // 從字串恢復影片類型，預設為原始影片
    VideoType videoType = VideoType.original;
    final videoTypeStr = json['videoType'] as String?;
    if (videoTypeStr != null) {
      try {
        videoType = VideoType.values.byName(videoTypeStr);
      } catch (e) {
        debugPrint('Unknown videoType: $videoTypeStr, defaulting to original');
      }
    }

    // 從字串恢復同步狀態，預設為未同步
    SyncStatus syncStatus = SyncStatus.notSynced;
    final syncStatusStr = json['syncStatus'] as String?;
    if (syncStatusStr != null) {
      try {
        syncStatus = SyncStatus.values.byName(syncStatusStr);
      } catch (e) {
        debugPrint('Unknown syncStatus: $syncStatusStr, defaulting to notSynced');
      }
    }

    return RecordingHistoryEntry(
      filePath: (json['filePath'] as String?) ?? '',
      roundIndex: (json['roundIndex'] as int?) ?? 1,
      recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
          DateTime.now(),
      durationSeconds: (json['durationSeconds'] as int?) ?? 0,
      customName: (json['customName'] as String?) ?? '',
      thumbnailPath:
          rawThumbnail == null || rawThumbnail.isEmpty ? null : rawThumbnail,
      uploadStatus: uploadStatus,
      cloudVideoId: (json['cloudVideoId'] as String?),
      uploadError: (json['uploadError'] as String?),
      lastUploadAttempt: json['lastUploadAttempt'] != null
          ? DateTime.tryParse(json['lastUploadAttempt'] as String)
          : null,
      videoType: videoType,
      syncStatus: syncStatus,
      processingStatus: ProcessingStatus.fromString(json['processingStatus'] as String?),
      processingSuccess: (json['processingSuccess'] as bool?),
      mainFileType: (json['mainFileType'] as String?),
      isClipped: (json['isClipped'] as bool?) ?? false,
      sourceLocalFilePath: (json['sourceLocalFilePath'] as String?),
      hitSecond: (json['hitSecond'] as num?)?.toDouble(),
      startSecond: (json['startSecond'] as num?)?.toDouble(),
      endSecond: (json['endSecond'] as num?)?.toDouble(),
      audioCrispness: (json['audioCrispness'] as num?)?.toDouble(),
      goodShot: (json['goodShot'] as bool?),
    );
  }
}
