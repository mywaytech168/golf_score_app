import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_token_storage.dart';

const _baseUrl = 'https://tekswing.api.atk.tw';

// ── 資料模型 ──────────────────────────────────────────────────

/// 步驟 1 回傳：分析 ID + 上傳 URL
class AnalysisRequestResult {
  final String analysisId;
  final String clipUploadUrl;
  /// HasCsv=true 時才有值；Worker 用此 CSV 執行 ONNX 推論
  final String? csvUploadUrl;

  AnalysisRequestResult({
    required this.analysisId,
    required this.clipUploadUrl,
    this.csvUploadUrl,
  });

  factory AnalysisRequestResult.fromJson(Map<String, dynamic> j) =>
      AnalysisRequestResult(
        analysisId:    j['analysisId']    as String,
        clipUploadUrl: j['clipUploadUrl'] as String,
        csvUploadUrl:  j['csvUploadUrl']  as String?,
      );
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

  factory CoachPrimaryError.fromJson(Map<String, dynamic> j) =>
      CoachPrimaryError(
        errorType: j['error_type'] as String? ?? '',
        zhName:    j['zh_name']    as String? ?? '',
        severity:  j['severity']   as String? ?? 'medium',
        evidence:  (j['evidence']  as List<dynamic>? ?? []).cast<String>(),
      );
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

class CoachResult {
  final String summary;
  final CoachPrimaryError primaryError;
  final List<String> coachFeedback;
  final List<PracticeSuggestion> practiceSuggestions;
  final String nextTrainingGoal;

  CoachResult({
    required this.summary,
    required this.primaryError,
    required this.coachFeedback,
    required this.practiceSuggestions,
    required this.nextTrainingGoal,
  });

  factory CoachResult.fromJson(Map<String, dynamic> j) => CoachResult(
    summary:      j['summary']         as String? ?? '',
    primaryError: CoachPrimaryError.fromJson(
        (j['primary_error'] as Map<String, dynamic>?) ?? {}),
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
  final String status; // pending | queued | processing | completed | failed
  final String? summary;
  final String? severity;
  final CoachResult? result;

  AnalysisStatus({
    required this.analysisId,
    this.videoId,
    required this.status,
    this.summary,
    this.severity,
    this.result,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed    => status == 'failed';
  bool get isDone      => isCompleted || isFailed;
  bool get isActive    => !isDone; // pending / queued / processing

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
    return AnalysisStatus(
      analysisId: j['analysisId'] as String? ?? '',
      videoId:    j['videoId']    as String?,
      status:     j['status']     as String? ?? 'unknown',
      summary:    j['summary']    as String?,
      severity:   j['severity']   as String?,
      result:     result,
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
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(_TokenRefreshInterceptor(_dio));
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
  /// [hasCsv]=true 時同時回傳 [csvUploadUrl]，供後端 Worker 執行 ONNX 推論。
  Future<AnalysisRequestResult> requestAnalysis({
    required String videoId,
    bool hasCsv = false,
  }) async {
    final resp = await _dio.post(
      '/api/analysis/request',
      data: {
        'videoId': videoId,
        'hasCsv':  hasCsv,
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
  /// - [csvPath]：若提供且檔案存在，一併上傳骨架 CSV。
  ///   Worker 收到後在後端自動執行 ONNX，結果存入 DB，
  ///   不需使用者在客戶端中繼。
  Future<String> submitForAnalysis({
    required String videoId,
    required String clipPath,
    String? csvPath,
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    final hasCsv = csvPath != null && File(csvPath).existsSync();

    final req = await requestAnalysis(videoId: videoId, hasCsv: hasCsv);

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

    await notifyReady(req.analysisId);
    return req.analysisId;
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

  /// 取得最新一筆可用分析（completed 優先，其次進行中，最後 failed）
  Future<AnalysisStatus?> getLatestAnalysisForVideo(String videoId) async {
    try {
      final list = await getVideoAnalyses(videoId);
      if (list.isEmpty) return null;
      final completed = list.where((a) => a.isCompleted).toList();
      if (completed.isNotEmpty) return completed.first;
      final active = list.where((a) => a.isActive).toList();
      if (active.isNotEmpty) return active.first;
      return list.first; // failed
    } catch (_) {
      return null;
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
