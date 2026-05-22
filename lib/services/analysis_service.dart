import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
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

  // ── ONNX 揮桿錯誤分析 ────────────────────────────────────────

  /// 從 pose_landmarks.csv 解析骨架幀（最多 600 幀，等距採樣）
  ///
  /// CSV 欄位佈局（從 col 3 起，每個 landmark 佔 6 欄）：
  ///   frame(0), time_sec(1), pose_update_id(2),
  ///   [lm_x_norm, lm_y_norm, lm_z, lm_vis, lm_x_px, lm_y_px] × 33
  static List<Map<String, dynamic>> parseCsvToFrames(
    String csvPath, {
    int maxFrames = 600,
  }) {
    final content = File(csvPath).readAsStringSync();
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    if (rows.length < 3) return []; // header + 至少 2 data rows

    final dataRows = rows.sublist(1); // 去掉 header

    // 等距採樣
    final List<List<dynamic>> sampled;
    if (dataRows.length <= maxFrames) {
      sampled = dataRows;
    } else {
      sampled = [];
      final step = (dataRows.length - 1) / (maxFrames - 1);
      for (int i = 0; i < maxFrames; i++) {
        sampled.add(dataRows[(i * step).round()]);
      }
    }

    final frames = <Map<String, dynamic>>[];
    for (int fi = 0; fi < sampled.length; fi++) {
      final row = sampled[fi];
      final landmarks = <Map<String, dynamic>>[];
      for (int lm = 0; lm < 33; lm++) {
        final base = 3 + lm * 6;
        if (row.length <= base + 3) continue;
        final x   = _csvDouble(row[base]);
        final y   = _csvDouble(row[base + 1]);
        final z   = _csvDouble(row[base + 2]);
        final vis = _csvDouble(row[base + 3]);
        // 忽略完全缺失的關鍵點（x 和 y 皆 NaN）
        if (x.isNaN && y.isNaN) continue;
        landmarks.add({
          'id':         lm,
          'x':          x.isNaN   ? 0.0 : x,
          'y':          y.isNaN   ? 0.0 : y,
          'z':          z.isNaN   ? 0.0 : z,
          'visibility': vis.isNaN ? 0.0 : vis,
        });
      }
      if (landmarks.isNotEmpty) {
        frames.add({'frameIndex': fi, 'landmarks': landmarks});
      }
    }
    return frames;
  }

  static double _csvDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? double.nan;
  }

  /// 呼叫後端 ONNX 端點 POST /api/golf/analyze-swing
  Future<GolfSwingResult?> analyzeSwing(
    List<Map<String, dynamic>> frames,
  ) async {
    if (frames.length < 2) return null;
    try {
      final resp = await _dio.post(
        '/api/golf/analyze-swing',
        data: {'frames': frames},
        options: Options(
          headers: await _authHeaders(),
          sendTimeout:    const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      return GolfSwingResult.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('⚠️ AnalyzeSwing 失敗（略過，繼續 Gemini）: $e');
      return null;
    }
  }

  /// 從 CSV 一次完成骨架解析 + ONNX 推論
  Future<GolfSwingResult?> analyzeSwingFromCsv(String csvPath) async {
    final frames = parseCsvToFrames(csvPath);
    if (frames.length < 2) {
      debugPrint('[AnalyzeSwing] CSV 幀數不足（${frames.length}），跳過');
      return null;
    }
    debugPrint('[AnalyzeSwing] 送出 ${frames.length} 幀 → /api/golf/analyze-swing');
    return analyzeSwing(frames);
  }
}

// ── ONNX 揮桿分析結果 DTO ────────────────────────────────────

class GolfSwingResult {
  /// 正式錯誤 (score >= 0.75)
  final List<String> officialErrors;
  /// 需複核 (0.75–0.85)
  final List<String> reviewErrors;
  /// 疑似錯誤 (0.60–0.75)
  final List<String> suspectErrors;
  /// 各標籤原始機率
  final Map<String, double> scores;
  /// 各標籤信心帶
  final Map<String, String> bands;

  GolfSwingResult({
    required this.officialErrors,
    required this.reviewErrors,
    required this.suspectErrors,
    required this.scores,
    required this.bands,
  });

  /// 最高優先錯誤類型：official 優先，次取 suspect，皆無則 null
  String? get topError =>
      officialErrors.isNotEmpty ? officialErrors.first :
      suspectErrors.isNotEmpty  ? suspectErrors.first  : null;

  factory GolfSwingResult.fromJson(Map<String, dynamic> j) => GolfSwingResult(
    officialErrors: (j['officialErrors'] as List<dynamic>? ?? []).cast<String>(),
    reviewErrors:   (j['reviewErrors']   as List<dynamic>? ?? []).cast<String>(),
    suspectErrors:  (j['suspectErrors']  as List<dynamic>? ?? []).cast<String>(),
    scores: (j['scores'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble())),
    bands:  (j['bands']  as Map<String, dynamic>? ?? {}).cast<String, String>(),
  );
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
      return handler.next(err); // 非 401，直接往上拋
    }

    debugPrint('[TokenRefreshInterceptor] 收到 401，嘗試刷新 Token...');
    final refreshed =
        await AuthTokenStorage.instance.tryRefreshToken();

    if (!refreshed) {
      debugPrint('[TokenRefreshInterceptor] 刷新失敗，放棄重試');
      return handler.next(err);
    }

    // 刷新成功 → 用新 token 重試原始請求
    try {
      final opts = err.requestOptions;
      final newToken =
          await AuthTokenStorage.instance.getAccessToken();
      opts.headers['Authorization'] = 'Bearer $newToken';

      final retryResp = await _dio.fetch(opts);
      return handler.resolve(retryResp);
    } catch (retryErr) {
      debugPrint('[TokenRefreshInterceptor] 重試失敗: $retryErr');
      return handler.next(err);
    }
  }
}
