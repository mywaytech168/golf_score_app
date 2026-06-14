import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'auth_token_storage.dart';
import 'swing_auto_clip_service.dart';
import 'v3_analysis_service.dart';

const _baseUrl = 'https://orvia.api.atk.tw';

// ── 資料模型 ──────────────────────────────────────────────────

/// 步驟 1 回傳：分析 ID + 上傳 URL
class AnalysisRequestResult {
  final String analysisId;
  final String clipUploadUrl;
  /// HasCsv=true 時才有值；Worker 用此 CSV 執行 ONNX 推論
  final String? csvUploadUrl;
  /// HasAudio=true 時才有值；V3 用此 URL 上傳 audio.wav
  final String? audioUploadUrl;
  /// keyframeCount>0 時才有值；依序上傳 keyframe_0.jpg ... keyframe_N.jpg
  final List<String>? keyframeUploadUrls;
  /// 診斷 meta.json 上傳 URL（偵測 log/錨點/即時擊球等）
  final String? metaUploadUrl;

  AnalysisRequestResult({
    required this.analysisId,
    required this.clipUploadUrl,
    this.csvUploadUrl,
    this.audioUploadUrl,
    this.keyframeUploadUrls,
    this.metaUploadUrl,
  });

  factory AnalysisRequestResult.fromJson(Map<String, dynamic> j) =>
      AnalysisRequestResult(
        analysisId:         j['analysisId']     as String,
        clipUploadUrl:      j['clipUploadUrl']  as String,
        csvUploadUrl:       j['csvUploadUrl']   as String?,
        audioUploadUrl:     j['audioUploadUrl'] as String?,
        keyframeUploadUrls: (j['keyframeUploadUrls'] as List<dynamic>?)?.cast<String>(),
        metaUploadUrl:      j['metaUploadUrl']  as String?,
      );
}

/// 模型推論結果（後端 Worker 執行，前端顯示原始分數）
class OnnxResult {
  /// 各錯誤類型的機率分數（0.0–1.0），按分數降冪排序
  final Map<String, double> scores;
  /// 確認的錯誤列表（confidence >= 0.75）
  final List<String> officialErrors;
  /// 需複審列表（0.75–0.85，official 但信心不足）
  final List<String> reviewErrors;
  /// 可疑錯誤列表（0.60–0.75，未列入 official）
  final List<String> suspectErrors;
  /// 各 label 的信心帶：high_confidence | acceptable_review | suspect_not_official | low_ignore
  final Map<String, String> bands;

  const OnnxResult({
    required this.scores,
    required this.officialErrors,
    required this.reviewErrors,
    required this.suspectErrors,
    required this.bands,
  });

  /// 完美揮桿：無任何 official / suspect 錯誤，全部分數都在 low_ignore 帶
  bool get isPerfect =>
      officialErrors.isEmpty &&
      suspectErrors.isEmpty &&
      bands.values.every((b) => b == 'low_ignore');

  factory OnnxResult.fromJson(Map<String, dynamic> j) {
    // 後端 key 為 PascalCase（OfficialErrors / Scores / Bands …）
    // 同時相容 snake_case（official_errors / scores / bands）以防日後調整
    Map<String, double> parseScores() {
      final raw = j['Scores'] ?? j['scores'];
      return (raw as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    List<String> parseList(String pascal, String snake) {
      final raw = j[pascal] ?? j[snake];
      return (raw as List<dynamic>? ?? []).cast<String>();
    }

    Map<String, String> parseBands() {
      final raw = j['Bands'] ?? j['bands'];
      return (raw as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String));
    }

    return OnnxResult(
      scores:        parseScores(),
      officialErrors: parseList('OfficialErrors', 'official_errors'),
      reviewErrors:   parseList('ReviewErrors',   'review_errors'),
      suspectErrors:  parseList('SuspectErrors',  'suspect_errors'),
      bands:          parseBands(),
    );
  }
}

class CoachPrimaryError {
  final String errorType;
  final String zhName;
  final String severity;
  final List<String> evidence;

  CoachPrimaryError({
    required this.errorType,
    required this.zhName,
    required this.severity,
    required this.evidence,
  });

  /// Good class：後端 error_type 為空字串時表示完美揮桿
  bool get isPerfect => errorType.isEmpty;

  factory CoachPrimaryError.fromJson(Map<String, dynamic> j) {
    final errorType = j['error_type'] as String? ?? '';
    return CoachPrimaryError(
      errorType: errorType,
      zhName:    j['zh_name']  as String? ?? '',
      // Good class（errorType 為空）→ severity 預設 'low'；其餘預設 'medium'
      severity:  j['severity'] as String? ?? (errorType.isEmpty ? 'low' : 'medium'),
      evidence:  (j['evidence'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class PracticeSuggestion {
  final String drill;
  final String instruction;
  final String reps;

  PracticeSuggestion({
    required this.drill,
    required this.instruction,
    required this.reps,
  });

  factory PracticeSuggestion.fromJson(Map<String, dynamic> j) =>
      PracticeSuggestion(
        drill:       j['drill']       as String? ?? '',
        instruction: j['instruction'] as String? ?? '',
        reps:        j['reps']        as String? ?? '',
      );
}

class ImpactQuality {
  final bool audioSweetSpot;
  final int passCount;
  final int totalFeatures;
  /// poor | fair | near_sweet_spot | sweet_spot | premium_sweet_spot
  final String qualityLevel;
  final String audioFeedback;

  ImpactQuality({
    required this.audioSweetSpot,
    required this.passCount,
    required this.totalFeatures,
    required this.qualityLevel,
    required this.audioFeedback,
  });

  factory ImpactQuality.fromJson(Map<String, dynamic> j) => ImpactQuality(
    audioSweetSpot: j['audio_sweet_spot'] as bool? ?? false,
    passCount:      j['pass_count']       as int?  ?? 0,
    totalFeatures:  j['total_features']   as int?  ?? 5,
    qualityLevel:   j['quality_level']    as String? ?? 'poor',
    audioFeedback:  j['audio_feedback']   as String? ?? '',
  );

  static ImpactQuality unavailable() => ImpactQuality(
    audioSweetSpot: false,
    passCount: 0,
    totalFeatures: 5,
    qualityLevel: 'poor',
    audioFeedback: '無音訊分析資料',
  );
}

class CoachResult {
  final String summary;
  final CoachPrimaryError primaryError;
  final ImpactQuality? impactQuality;
  final List<String> coachFeedback;
  final List<PracticeSuggestion> practiceSuggestions;
  final String nextTrainingGoal;

  CoachResult({
    required this.summary,
    required this.primaryError,
    this.impactQuality,
    required this.coachFeedback,
    required this.practiceSuggestions,
    required this.nextTrainingGoal,
  });

  factory CoachResult.fromJson(Map<String, dynamic> j) => CoachResult(
    summary:      j['summary']         as String? ?? '',
    // primary_error 為 null → Good class（完美揮桿），直接給完美預設值
    primaryError: j['primary_error'] != null
        ? CoachPrimaryError.fromJson(j['primary_error'] as Map<String, dynamic>)
        : CoachPrimaryError(errorType: '', zhName: '', severity: 'low', evidence: []),
    impactQuality: j['impact_quality'] != null
        ? ImpactQuality.fromJson(j['impact_quality'] as Map<String, dynamic>)
        : null,
    coachFeedback: (j['coach_feedback'] as List<dynamic>? ?? []).cast<String>(),
    practiceSuggestions: (j['practice_suggestions'] as List<dynamic>? ?? [])
        .map((e) => PracticeSuggestion.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextTrainingGoal: j['next_training_goal'] as String? ?? '',
  );
}

/// 分析任務狀態（輪詢用）
class AnalysisStatus {
  final String analysisId;
  final String? videoId;
  final String status; // pending | queued | processing | idle | completed | failed
  /// "posture_only" | "full"
  final String? mode;
  /// "v1" | "v2" | "v3"
  final String? promptVersion;
  final String? summary;
  final String? severity;
  final CoachResult? result;
  /// ONNX 原始推論分數（後端 Worker 產生，供進階顯示）
  final OnnxResult? onnxResult;
  /// Gemini 輸入 token 數
  final int? inputTokens;
  /// Gemini 輸出 token 數
  final int? outputTokens;

  AnalysisStatus({
    required this.analysisId,
    this.videoId,
    required this.status,
    this.mode,
    this.promptVersion,
    this.summary,
    this.severity,
    this.result,
    this.onnxResult,
    this.inputTokens,
    this.outputTokens,
  });

  bool get isCompleted       => status == 'completed';
  bool get isFailed          => status == 'failed';
  /// idle = ONNX 完成，尚未呼叫 Gemini
  bool get isIdle            => status == 'idle';
  bool get isDone            => isCompleted || isFailed || isIdle;
  bool get isActive          => !isDone; // pending / queued / processing
  bool get hasPostureResult  => onnxResult != null;

  factory AnalysisStatus.fromJson(Map<String, dynamic> j) {
    CoachResult? result;
    final rawResult = j['result'];
    if (rawResult != null) {
      try {
        final Map<String, dynamic> resultMap = rawResult is String
            ? jsonDecode(rawResult) as Map<String, dynamic>
            : rawResult as Map<String, dynamic>;
        result = CoachResult.fromJson(resultMap);
      } catch (e) {
        debugPrint('⚠️ 解析 CoachResult 失敗: $e');
      }
    }

    OnnxResult? onnxResult;
    // 後端可能用 PascalCase（OnnxResult）或 camelCase（onnxResult）
    final rawOnnx = j['OnnxResult'] ?? j['onnxResult'];
    if (rawOnnx != null) {
      try {
        final Map<String, dynamic> onnxMap = rawOnnx is String
            ? jsonDecode(rawOnnx) as Map<String, dynamic>
            : rawOnnx as Map<String, dynamic>;
        onnxResult = OnnxResult.fromJson(onnxMap);
      } catch (e) {
        debugPrint('⚠️ 解析 OnnxResult 失敗: $e');
      }
    }

    return AnalysisStatus(
      analysisId:    j['analysisId']    as String? ?? '',
      videoId:       j['videoId']       as String?,
      status:        j['status']        as String? ?? 'unknown',
      mode:          j['mode']          as String?,
      promptVersion: j['promptVersion'] as String?,
      summary:       j['summary']       as String?,
      severity:      j['severity']      as String?,
      result:        result,
      onnxResult:    onnxResult,
      inputTokens:   j['inputTokens']   as int?,
      outputTokens:  j['outputTokens']  as int?,
    );
  }
}

// ── Service ───────────────────────────────────────────────────
//
// 完整 AI Coach 提交流程（使用者只需提供骨架 CSV，ONNX 推論在後端完成）：
//
//   1. requestAnalysis()   → 建立任務，取得 B2 presigned URL
//   2. uploadClip()        → 直傳 clip.mp4 到 B2
//   2b. uploadCsv()        → 直傳 pose_landmarks.csv 到 B2（若有）
//   3. notifyReady()       → 觸發 Worker
//
//   Worker 流程（後端自動執行，無需使用者中繼）：
//     下載 clip + CSV → ONNX 推論 → OnnxResultJson 存 DB
//                     → effectiveHint → Gemini → ResultJson 存 DB
//
//   4. getStatus()         → 輪詢結果
// ─────────────────────────────────────────────────────────────

class AnalysisService {
  static final AnalysisService _instance = AnalysisService._internal();
  factory AnalysisService() => _instance;
  static AnalysisService get instance => _instance;

  late final Dio _dio;

  AnalysisService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(_ConnectRetryInterceptor(_dio));
    _dio.interceptors.add(_TokenRefreshInterceptor(_dio));
  }

  /// 把 Dio 連線類錯誤轉成使用者看得懂的訊息（其餘原樣回傳）。
  static String friendlyError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.connectionError:
          return '無法連線到伺服器，請確認網路後再試';
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '伺服器回應逾時，請稍後再試';
        default:
          break;
      }
    }
    return e.toString();
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthTokenStorage.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── 步驟 1 ────────────────────────────────────────────────────

  /// 向 Server 建立分析任務，回傳 B2 presigned 上傳 URL。
  ///
  /// - [hasCsv]=true 時同時回傳 [csvUploadUrl]，供後端 Worker 執行 ONNX 推論。
  /// - [hasAudio]=true 時同時回傳 [audioUploadUrl]（V3 用）。
  /// - [keyframeCount]：V3 時傳入要上傳的關鍵禎數量，Server 回傳對應 presigned URL 陣列。
  /// - [mode]："posture_only"（只跑 ONNX → idle）或 "full"（ONNX + Gemini）。
  /// - [promptVersion]："v1" | "v2" | "v3"（僅 mode="full" 有效）。
  Future<AnalysisRequestResult> requestAnalysis({
    required String videoId,
    bool hasCsv = false,
    bool hasAudio = false,
    int keyframeCount = 0,
    String mode = 'full',
    String promptVersion = 'v1',
    Map<String, double>? phaseTimestamps,
    String? audioAnalysisJson,
    String? swingMetricsJson,
    int? v2Fps,
    String? v2Resolution,
  }) async {
    final resp = await _dio.post(
      '/api/analysis/request',
      data: {
        'videoId':        videoId,
        'hasCsv':         hasCsv,
        'hasAudio':       hasAudio,
        'keyframeCount':  keyframeCount,
        'mode':           mode,
        'promptVersion':  promptVersion,
        if (phaseTimestamps != null)   'phaseTimestamps':  phaseTimestamps,
        if (audioAnalysisJson != null) 'audioAnalysisJson': audioAnalysisJson,
        if (swingMetricsJson != null)  'swingMetricsJson':  swingMetricsJson,
        if (v2Fps != null)             'v2Fps':            v2Fps,
        if (v2Resolution != null)      'v2Resolution':     v2Resolution,
      },
      options: Options(headers: await _authHeaders()),
    );
    return AnalysisRequestResult.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── 步驟 2a ───────────────────────────────────────────────────

  /// 直傳 clip.mp4 到 B2（Presigned PUT）
  Future<void> uploadClip({
    required String clipUploadUrl,
    required String clipPath,
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await File(clipPath).readAsBytes();
    await _dio.put(
      clipUploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type':   'video/mp4',
          'Content-Length': bytes.length.toString(),
        },
        sendTimeout:    const Duration(minutes: 3),
        receiveTimeout: const Duration(minutes: 3),
      ),
      onSendProgress: onProgress,
    );
    debugPrint('✅ Clip 上傳完成: ${bytes.length ~/ 1024}KB');
  }

  // ── 步驟 2b ───────────────────────────────────────────────────

  /// 直傳 pose_landmarks.csv 到 B2（Presigned PUT）。
  /// Worker 收到後自行執行 ONNX 推論，不需使用者中繼。
  Future<void> uploadCsv({
    required String csvUploadUrl,
    required String csvPath,
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await File(csvPath).readAsBytes();
    await _dio.put(
      csvUploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type':   'text/csv',
          'Content-Length': bytes.length.toString(),
        },
        sendTimeout:    const Duration(minutes: 3),
        receiveTimeout: const Duration(minutes: 3),
      ),
      onSendProgress: onProgress,
    );
    debugPrint('✅ CSV 上傳完成: ${bytes.length ~/ 1024}KB');
  }

  /// 直傳診斷 meta.json（偵測 log/錨點/即時擊球等）到 B2（Presigned PUT）。
  Future<void> uploadMeta({
    required String metaUploadUrl,
    required String metaJson,
  }) async {
    final bytes = utf8.encode(metaJson);
    await _dio.put(
      metaUploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type':   'application/json',
          'Content-Length': bytes.length.toString(),
        },
        sendTimeout:    const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    debugPrint('✅ meta 上傳完成: ${bytes.length} bytes');
  }

  // ── 步驟 2c ───────────────────────────────────────────────────

  /// 直傳單一 keyframe JPEG（base64 bytes）到 B2（Presigned PUT）—— V3 專用
  Future<void> uploadKeyframe({
    required String uploadUrl,
    required Uint8List bytes,
  }) async {
    await _dio.put(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type':   'image/jpeg',
          'Content-Length': bytes.length.toString(),
        },
        sendTimeout:    const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
  }

  // ── 步驟 2d ───────────────────────────────────────────────────

  /// 直傳 audio.wav 到 B2（Presigned PUT）—— V3 專用
  Future<void> uploadAudio({
    required String audioUploadUrl,
    required String audioPath,
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await File(audioPath).readAsBytes();
    await _dio.put(
      audioUploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type':   'audio/wav',
          'Content-Length': bytes.length.toString(),
        },
        sendTimeout:    const Duration(minutes: 3),
        receiveTimeout: const Duration(minutes: 3),
      ),
      onSendProgress: onProgress,
    );
    debugPrint('✅ Audio 上傳完成: ${bytes.length ~/ 1024}KB');
  }

  // ── 步驟 3 ────────────────────────────────────────────────────

  /// 通知 Server clip（與 CSV）已上傳完畢，觸發 Worker 開始分析。
  Future<void> notifyReady(String analysisId) async {
    await _dio.post(
      '/api/analysis/$analysisId/ready',
      options: Options(headers: await _authHeaders()),
    );
    debugPrint('✅ 已通知 Server 開始分析: $analysisId');
  }

  // ── 步驟 4 ────────────────────────────────────────────────────

  /// 輪詢分析狀態（呼叫端用 Timer 或 Stream 控制間隔）
  Future<AnalysisStatus> getStatus(String analysisId) async {
    final resp = await _dio.get(
      '/api/analysis/$analysisId',
      options: Options(headers: await _authHeaders()),
    );
    return AnalysisStatus.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── 便利方法 ──────────────────────────────────────────────────

  /// 一次完成步驟 1～3，回傳 analysisId 供輪詢。
  ///
  /// - [csvPath]：若提供且檔案存在，一併上傳骨架 CSV（Worker 在後端執行 ONNX）。
  /// - [audioPath]：V3 時傳入 audio.wav 路徑（若存在則上傳到 B2）。
  /// - [mode]："posture_only" 或 "full"（預設）。
  /// - [promptVersion]："v1" | "v2" | "v3"（預設 "v1"）。
  /// - V3 時自動抽取關鍵禎並嵌入 request body。
  Future<String> submitForAnalysis({
    required String videoId,
    required String clipPath,
    String? csvPath,
    String? audioPath,
    String mode = 'full',
    String promptVersion = 'v1',
    Map<String, double>? phaseTimestamps,
    String? audioAnalysisJson,
    int? v2Fps,
    String? v2Resolution,
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    final hasCsv   = csvPath   != null && File(csvPath).existsSync();
    final hasAudio = audioPath != null && File(audioPath).existsSync()
        && promptVersion == 'v3';

    // V3：事先抽取關鍵禎 bytes（只取 bytes，不再嵌入 request body）
    List<Uint8List>? keyframeBytes;
    if (promptVersion == 'v3' && phaseTimestamps != null && phaseTimestamps.isNotEmpty) {
      try {
        keyframeBytes = await V3AnalysisService.instance.extractKeyframeBytes(
          clipPath:        clipPath,
          phaseTimestamps: phaseTimestamps,
        );
        debugPrint('✅ V3 關鍵禎抽取完成: ${keyframeBytes.length} 幀');
      } catch (e) {
        debugPrint('⚠️ V3 關鍵禎抽取失敗（略過）: $e');
      }
    }

    // 裝置端 P-System 角度量化（angles.json）→ inline 注入 Gemini 當客觀依據（失敗略過）
    String? swingMetricsJson;
    try {
      final af = File(p.join(p.dirname(clipPath), 'angles.json'));
      if (af.existsSync()) swingMetricsJson = await af.readAsString();
    } catch (_) {/* 無 angles.json（V2 切片/舊片）→ 略過 */}

    final req = await requestAnalysis(
      videoId:           videoId,
      hasCsv:            hasCsv,
      hasAudio:          hasAudio,
      keyframeCount:     keyframeBytes?.length ?? 0,
      mode:              mode,
      promptVersion:     promptVersion,
      phaseTimestamps:   phaseTimestamps,
      audioAnalysisJson: audioAnalysisJson,
      swingMetricsJson:  swingMetricsJson,
      v2Fps:             v2Fps,
      v2Resolution:      v2Resolution,
    );

    await uploadClip(
      clipUploadUrl: req.clipUploadUrl,
      clipPath:      clipPath,
      onProgress:    onUploadProgress,
    );

    if (hasCsv && req.csvUploadUrl != null) {
      await uploadCsv(
        csvUploadUrl: req.csvUploadUrl!,
        csvPath:      csvPath,
      );
    }

    if (hasAudio && req.audioUploadUrl != null) {
      await uploadAudio(
        audioUploadUrl: req.audioUploadUrl!,
        audioPath:      audioPath,
      );
    }

    // V3：依序上傳每個關鍵禎到 B2
    if (keyframeBytes != null && req.keyframeUploadUrls != null) {
      final urls = req.keyframeUploadUrls!;
      for (int i = 0; i < keyframeBytes.length && i < urls.length; i++) {
        try {
          await uploadKeyframe(uploadUrl: urls[i], bytes: keyframeBytes[i]);
          debugPrint('✅ Keyframe[$i] 上傳完成: ${keyframeBytes[i].length ~/ 1024}KB');
        } catch (e) {
          debugPrint('⚠️ Keyframe[$i] 上傳失敗（略過）: $e');
        }
      }
    }

    // 診斷 meta.json（偵測 log/錨點/即時擊球等；失敗略過不阻斷分析）
    if (req.metaUploadUrl != null) {
      try {
        final meta = await SwingAutoClipService.buildSessionMetaJson(
            p.dirname(clipPath));
        await uploadMeta(metaUploadUrl: req.metaUploadUrl!, metaJson: meta);
      } catch (e) {
        debugPrint('⚠️ meta 上傳失敗（略過）: $e');
      }
    }

    await notifyReady(req.analysisId);
    return req.analysisId;
  }

  // ── 升級 ──────────────────────────────────────────────────────

  /// 將 idle 記錄升級為完整 Gemini 分析（posture_only → full）。
  ///
  /// 可選擇性指定新的 [promptVersion]；不指定則沿用原始版本。
  Future<void> upgradeAnalysis(
    String analysisId, {
    String? promptVersion,
  }) async {
    await _dio.post(
      '/api/analysis/$analysisId/upgrade',
      data: {
        if (promptVersion != null) 'promptVersion': promptVersion,
      },
      options: Options(headers: await _authHeaders()),
    );
    debugPrint('✅ 升級分析: $analysisId → full (promptVersion=$promptVersion)');
  }

  // ── 查詢 ──────────────────────────────────────────────────────

  /// 查詢某影片的所有分析記錄（最多 10 筆，最新在前）
  Future<List<AnalysisStatus>> getVideoAnalyses(String videoId) async {
    final resp = await _dio.get(
      '/api/analysis/by-video/$videoId',
      options: Options(headers: await _authHeaders()),
    );
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => AnalysisStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 取得最新一筆可用分析（completed 優先，其次 idle，其次進行中，最後 failed）
  Future<AnalysisStatus?> getLatestAnalysisForVideo(String videoId) async {
    try {
      final list = await getVideoAnalyses(videoId);
      if (list.isEmpty) return null;
      final completed = list.where((a) => a.isCompleted).toList();
      if (completed.isNotEmpty) return completed.first;
      final idle = list.where((a) => a.isIdle).toList();
      if (idle.isNotEmpty) return idle.first;
      final active = list.where((a) => a.isActive).toList();
      if (active.isNotEmpty) return active.first;
      return list.first; // failed
    } catch (_) {
      return null;
    }
  }
}

// ── Dio 連線失敗自動重試攔截器 ────────────────────────────────
//
// connectionTimeout / connectionError 代表 TCP 連線根本沒建立、請求未送出，
// 任何 method 重試都安全（不會重複建立任務）。行動網路切換瞬間常見此類失敗，
// 退避 2 秒後重試一次。
class _ConnectRetryInterceptor extends Interceptor {
  final Dio _dio;
  _ConnectRetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final isConnectFailure = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError;
    final alreadyRetried = err.requestOptions.extra['connectRetried'] == true;
    if (!isConnectFailure || alreadyRetried) {
      handler.next(err);
      return;
    }
    debugPrint('[AnalysisService] 連線失敗（${err.type.name}），2 秒後重試一次: '
        '${err.requestOptions.path}');
    await Future.delayed(const Duration(seconds: 2));
    try {
      final opts = err.requestOptions..extra['connectRetried'] = true;
      final resp = await _dio.fetch(opts);
      handler.resolve(resp);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

// ── Dio 401 自動刷新攔截器 ────────────────────────────────────

class _TokenRefreshInterceptor extends Interceptor {
  final Dio _dio;
  _TokenRefreshInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null || response.statusCode != 401) {
      return handler.next(err);
    }

    debugPrint('[TokenRefreshInterceptor] 收到 401，嘗試刷新 Token...');
    final refreshed = await AuthTokenStorage.instance.tryRefreshToken();

    if (!refreshed) {
      debugPrint('[TokenRefreshInterceptor] 刷新失敗，放棄重試');
      return handler.next(err);
    }

    try {
      final opts     = err.requestOptions;
      final newToken = await AuthTokenStorage.instance.getAccessToken();
      opts.headers['Authorization'] = 'Bearer $newToken';
      final retryResp = await _dio.fetch(opts);
      return handler.resolve(retryResp);
    } catch (retryErr) {
      debugPrint('[TokenRefreshInterceptor] 重試失敗: $retryErr');
      return handler.next(err);
    }
  }
}
