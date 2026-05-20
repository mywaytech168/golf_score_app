import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_token_storage.dart';

const _baseUrl = 'https://tekswing.api.atk.tw';

// ── 資料模型 ──────────────────────────────────────────────────

class AnalysisRequestResult {
  final String analysisId;
  final String clipUploadUrl;
  AnalysisRequestResult({required this.analysisId, required this.clipUploadUrl});
  factory AnalysisRequestResult.fromJson(Map<String, dynamic> j) =>
      AnalysisRequestResult(
        analysisId:    j['analysisId']    as String,
        clipUploadUrl: j['clipUploadUrl'] as String,
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
  factory CoachPrimaryError.fromJson(Map<String, dynamic> j) => CoachPrimaryError(
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
  PracticeSuggestion({required this.drill, required this.instruction, required this.reps});
  factory PracticeSuggestion.fromJson(Map<String, dynamic> j) => PracticeSuggestion(
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
    summary:           j['summary']            as String? ?? '',
    primaryError:      CoachPrimaryError.fromJson((j['primary_error'] as Map<String, dynamic>?) ?? {}),
    coachFeedback:     (j['coach_feedback']    as List<dynamic>? ?? []).cast<String>(),
    practiceSuggestions: (j['practice_suggestions'] as List<dynamic>? ?? [])
        .map((e) => PracticeSuggestion.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextTrainingGoal:  j['next_training_goal'] as String? ?? '',
  );
}

class AnalysisStatus {
  final String analysisId;
  final String status; // pending | queued | processing | completed | failed
  final String? summary;
  final String? severity;
  final CoachResult? result;

  AnalysisStatus({
    required this.analysisId,
    required this.status,
    this.summary,
    this.severity,
    this.result,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed    => status == 'failed';
  bool get isDone      => isCompleted || isFailed;

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
      status:     j['status']     as String? ?? 'unknown',
      summary:    j['summary']    as String?,
      severity:   j['severity']   as String?,
      result:     result,
    );
  }
}

// ── Service ───────────────────────────────────────────────────

class AnalysisService {
  static final AnalysisService _instance = AnalysisService._internal();
  factory AnalysisService() => _instance;
  static AnalysisService get instance => _instance;
  AnalysisService._internal();

  final _dio = Dio(BaseOptions(
    baseUrl:        _baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthTokenStorage.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 步驟 1：向 Server 請求分析，取得 clip 上傳 URL
  Future<AnalysisRequestResult> requestAnalysis({
    required String videoId,
    String? errorTypeHint,
  }) async {
    final resp = await _dio.post(
      '/api/analysis/request',
      data: {'videoId': videoId, if (errorTypeHint != null) 'errorTypeHint': errorTypeHint},
      options: Options(headers: await _authHeaders()),
    );
    return AnalysisRequestResult.fromJson(resp.data as Map<String, dynamic>);
  }

  /// 步驟 2：直傳 clip.mp4 到 B2（Presigned PUT）
  Future<void> uploadClip({
    required String clipUploadUrl,
    required String clipPath,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(clipPath);
    final bytes = await file.readAsBytes();

    await _dio.put(
      clipUploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': bytes.length.toString(),
        },
        sendTimeout:    const Duration(minutes: 3),
        receiveTimeout: const Duration(minutes: 3),
      ),
      onSendProgress: onProgress,
    );
    debugPrint('✅ Clip 上傳完成: ${bytes.length ~/ 1024}KB');
  }

  /// 步驟 3：通知 Server clip 已上傳，觸發 Worker
  Future<void> notifyReady(String analysisId) async {
    await _dio.post(
      '/api/analysis/$analysisId/ready',
      options: Options(headers: await _authHeaders()),
    );
    debugPrint('✅ 已通知 Server 開始分析: $analysisId');
  }

  /// 步驟 4：輪詢分析狀態（呼叫端用 Timer 或 Stream 控制間隔）
  Future<AnalysisStatus> getStatus(String analysisId) async {
    final resp = await _dio.get(
      '/api/analysis/$analysisId',
      options: Options(headers: await _authHeaders()),
    );
    return AnalysisStatus.fromJson(resp.data as Map<String, dynamic>);
  }

  /// 一次完成步驟 1～3，回傳 analysisId 供輪詢
  Future<String> submitForAnalysis({
    required String videoId,
    required String clipPath,
    String? errorTypeHint,
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    final req = await requestAnalysis(videoId: videoId, errorTypeHint: errorTypeHint);
    await uploadClip(
      clipUploadUrl: req.clipUploadUrl,
      clipPath:      clipPath,
      onProgress:    onUploadProgress,
    );
    await notifyReady(req.analysisId);
    return req.analysisId;
  }

  /// 查詢某影片的所有分析記錄
  Future<List<AnalysisStatus>> getVideoAnalyses(String videoId) async {
    final resp = await _dio.get(
      '/api/analysis/video/$videoId',
      options: Options(headers: await _authHeaders()),
    );
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => AnalysisStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
