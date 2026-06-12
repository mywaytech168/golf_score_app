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

/// AI 分析產生的單則訓練建議，附帶「是否已完成」標記
/// 對應後端 practice_suggestions[]，外加本地 [done] 供使用者勾選
@immutable
class PracticeSuggestionItem {
  /// 練習名稱
  final String drill;

  /// 具體做法
  final String instruction;

  /// 建議次數/組數
  final String reps;

  /// 使用者是否已標記完成
  final bool done;

  const PracticeSuggestionItem({
    required this.drill,
    required this.instruction,
    required this.reps,
    this.done = false,
  });

  PracticeSuggestionItem copyWith({
    String? drill,
    String? instruction,
    String? reps,
    bool? done,
  }) {
    return PracticeSuggestionItem(
      drill:       drill       ?? this.drill,
      instruction: instruction ?? this.instruction,
      reps:        reps        ?? this.reps,
      done:        done        ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
        'drill':       drill,
        'instruction': instruction,
        'reps':        reps,
        'done':        done,
      };

  factory PracticeSuggestionItem.fromJson(Map<String, dynamic> j) =>
      PracticeSuggestionItem(
        drill:       j['drill']       as String? ?? '',
        instruction: j['instruction'] as String? ?? '',
        reps:        j['reps']        as String? ?? '',
        done:        j['done']        as bool?   ?? false,
      );
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

  /// 使用者影片備註（練習心得、場地、桿型…），空字串視為無備註
  final String? note;

  /// 錄製來源平台（'android' | 'ios'）。跨平台分享後切片時，
  /// 前鏡頭翻轉等邏輯必須依「錄製平台」而非「當前執行平台」判斷。
  /// null = 舊資料（視為本機平台錄製）。
  final String? recordedPlatform;

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

  /// 5 項音訊特徵通過數（0~5）；≥ 3 表示命中
  final int? audioPassCount;

  /// 各特徵是否通過閾值：key = 特徵名稱，value = 是否通過
  final Map<String, bool>? audioPasses;

  /// 各特徵實際值：key = 特徵名稱，value = 實際數值（用於圖表顯示）
  final Map<String, double>? audioFeatureValues;

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

  /// 擊球偵測後計算的最高速度峰值（speedValue），用於「最佳速度」排序
  /// 來自 hits.json 中所有 SwingHit.speedValue 的最大值
  final double? bestSpeedValue;

  /// 錄製時的影片尺寸名稱；固定為 'wide'（16:9）
  final String? recordedAspectRatio;

  /// 是否為前鏡頭錄製（true → 切片時自動水平翻轉）
  final bool isFrontCamera;

  /// 揮桿姿勢分類 label（來自後端 ONNX 骨架模型推論）
  /// '' = 完美(Good)；其餘對應 SwingPosture 5 種錯誤常數
  /// null = 尚未分析
  final String? swingPostureLabel;

  /// 揮桿姿勢分類 label（來自 Gemini AI Coach 分析）
  /// '' = 完美(Good)；其餘對應 SwingPosture 5 種錯誤常數
  /// null = 尚未有 Gemini 分析結果
  final String? geminiPostureLabel;

  /// posture_only 後端分析記錄 ID（ai_coach_analyses.id）
  /// null = 尚未觸發或尚未完成
  final String? postureAnalysisId;

  /// 最後一次 AI Coach 分析使用的 Gemini prompt 版本："v1" | "v2" | "v3"
  /// null = 尚未分析或舊資料（版本不明）
  final String? aiPromptVersion;

  /// AI 分析產生的訓練建議清單（含已完成標記）
  /// null 或空 = 尚無建議
  final List<PracticeSuggestionItem>? practiceSuggestions;

  /// AI 分析建議的下一次訓練目標；null = 尚無
  final String? nextTrainingGoal;

  const RecordingHistoryEntry({
    required this.filePath,
    required this.roundIndex,
    required this.recordedAt,
    this.createdAt,
    required this.durationSeconds,
    this.customName,
    this.note,
    this.recordedPlatform,
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
    this.audioPassCount,
    this.audioPasses,
    this.audioFeatureValues,
    this.shareCode,
    this.shareExpiresAt,
    this.sharerName,
    this.hasAiCoachAnalysis = false,
    this.isUploaded = false,
    this.bestSpeedValue,
    this.recordedAspectRatio,
    this.isFrontCamera = false,
    this.swingPostureLabel,
    this.geminiPostureLabel,
    this.postureAnalysisId,
    this.aiPromptVersion,
    this.practiceSuggestions,
    this.nextTrainingGoal,
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
    String? note,
    String? recordedPlatform,
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
    int? audioPassCount,
    Map<String, bool>? audioPasses,
    Map<String, double>? audioFeatureValues,
    String? shareCode,
    DateTime? shareExpiresAt,
    DateTime? createdAt,
    String? sharerName,
    bool? hasAiCoachAnalysis,
    bool? isUploaded,
    double? bestSpeedValue,
    String? recordedAspectRatio,
    bool? isFrontCamera,
    String? swingPostureLabel,
    String? geminiPostureLabel,
    String? postureAnalysisId,
    String? aiPromptVersion,
    List<PracticeSuggestionItem>? practiceSuggestions,
    String? nextTrainingGoal,
  }) {
    return RecordingHistoryEntry(
      filePath: filePath ?? this.filePath,
      roundIndex: roundIndex ?? this.roundIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      customName: customName ?? this.customName,
      note: note ?? this.note,
      recordedPlatform: recordedPlatform ?? this.recordedPlatform,
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
      audioPassCount: audioPassCount ?? this.audioPassCount,
      audioPasses: audioPasses ?? this.audioPasses,
      audioFeatureValues: audioFeatureValues ?? this.audioFeatureValues,
      shareCode: shareCode ?? this.shareCode,
      shareExpiresAt: shareExpiresAt ?? this.shareExpiresAt,
      sharerName: sharerName ?? this.sharerName,
      hasAiCoachAnalysis: hasAiCoachAnalysis ?? this.hasAiCoachAnalysis,
      isUploaded: isUploaded ?? this.isUploaded,
      bestSpeedValue: bestSpeedValue ?? this.bestSpeedValue,
      recordedAspectRatio: recordedAspectRatio ?? this.recordedAspectRatio,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      swingPostureLabel: swingPostureLabel ?? this.swingPostureLabel,
      geminiPostureLabel: geminiPostureLabel ?? this.geminiPostureLabel,
      postureAnalysisId: postureAnalysisId ?? this.postureAnalysisId,
      aiPromptVersion: aiPromptVersion ?? this.aiPromptVersion,
      practiceSuggestions: practiceSuggestions ?? this.practiceSuggestions,
      nextTrainingGoal: nextTrainingGoal ?? this.nextTrainingGoal,
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
      'note': note,
      'recordedPlatform': recordedPlatform,
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
      'audioPassCount': audioPassCount,
      'audioPasses': audioPasses,
      'audioFeatureValues': audioFeatureValues,
      'shareCode': shareCode,
      'shareExpiresAt': shareExpiresAt?.toUtc().toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'sharerName': sharerName,
      'hasAiCoachAnalysis': hasAiCoachAnalysis,
      'isUploaded': isUploaded,
      'bestSpeedValue': bestSpeedValue,
      'recordedAspectRatio': recordedAspectRatio,
      'isFrontCamera':       isFrontCamera,
      'swingPostureLabel':   swingPostureLabel,
      'geminiPostureLabel':  geminiPostureLabel,
      'postureAnalysisId':   postureAnalysisId,
      'aiPromptVersion':     aiPromptVersion,
      'practiceSuggestions': practiceSuggestions?.map((e) => e.toJson()).toList(),
      'nextTrainingGoal':    nextTrainingGoal,
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

    // 還原訓練建議清單
    final rawSuggestions = json['practiceSuggestions'];
    List<PracticeSuggestionItem>? practiceSuggestions;
    if (rawSuggestions is List) {
      practiceSuggestions = rawSuggestions
          .whereType<Map>()
          .map((e) => PracticeSuggestionItem.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    }

    return RecordingHistoryEntry(
      filePath: (json['filePath'] as String?) ?? '',
      roundIndex: (json['roundIndex'] as int?) ?? 1,
      recordedAt:
          DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.now(),
      durationSeconds: (json['durationSeconds'] as int?) ?? 0,
      customName: (json['customName'] as String?) ?? '',
      note: json['note'] as String?,
      recordedPlatform: json['recordedPlatform'] as String?,
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
      audioPassCount: (json['audioPassCount'] as int?),
      audioPasses: (json['audioPasses'] as Map?)?.map(
          (k, v) => MapEntry(k as String, (v as bool?) ?? false)),
      audioFeatureValues: (json['audioFeatureValues'] as Map?)?.map(
          (k, v) => MapEntry(k as String, (v as num).toDouble())),
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
      bestSpeedValue:     (json['bestSpeedValue']     as num?)?.toDouble(),
      recordedAspectRatio: json['recordedAspectRatio'] as String?,
      isFrontCamera:       (json['isFrontCamera']      as bool?) ?? false,
      swingPostureLabel:   json['swingPostureLabel']   as String?,
      geminiPostureLabel:  json['geminiPostureLabel']  as String?,
      postureAnalysisId:   json['postureAnalysisId']   as String?,
      aiPromptVersion:     json['aiPromptVersion']     as String?,
      practiceSuggestions: practiceSuggestions,
      nextTrainingGoal:    json['nextTrainingGoal']    as String?,
    );
  }
}
