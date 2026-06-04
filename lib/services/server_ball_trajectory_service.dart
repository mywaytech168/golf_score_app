import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_token_storage.dart';
import 'ball_tracker.dart'; // TrackPoint

const _baseUrl = 'https://tekswing.api.atk.tw';

/// 後端球軌跡追蹤服務。
///
/// 流程：
///   1. POST /api/ball-trajectory/request  → 取得 presigned clip 上傳 URL
///   2. PUT clip.mp4 → B2（直傳）
///   3. POST /api/ball-trajectory/{id}/ready → 觸發 Worker
///   4. Poll GET /api/ball-trajectory/{id}  → 等待 completed / failed
///   5. 回傳 [ServerTrajectoryResult]，Flutter 再用本地 renderOverlay 合成
class ServerBallTrajectoryService {
  static final _instance = ServerBallTrajectoryService._();
  factory ServerBallTrajectoryService() => _instance;
  static ServerBallTrajectoryService get instance => _instance;
  ServerBallTrajectoryService._() {
    _dio = Dio(BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(_TokenRefreshInterceptor(_dio));
  }

  late final Dio _dio;

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthTokenStorage.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // 公開入口：一次完成上傳 + 等待結果
  // ─────────────────────────────────────────────────────────────

  /// 上傳 [clipPath] 到後端，等待 Python worker 執行球軌跡追蹤。
  ///
  /// - [videoId]     : Flutter 本地 session ID（純參考）
  /// - [hitSec]      : 擊球秒數（傳 null = 全影片搜尋）
  /// - [flipMode]    : 0 = Android coded-space（預設）
  /// - [pollInterval]: 輪詢間隔（預設 3 秒）
  /// - [timeout]     : 最長等待時間（預設 3 分鐘）
  ///
  /// 成功回傳 [ServerTrajectoryResult]；失敗拋出例外。
  Future<ServerTrajectoryResult> runAndWait({
    required String clipPath,
    String? videoId,
    double? hitSec,
    int flipMode = 0,
    double roiCxRatio = 1149.0 / 1920,
    double roiCyRatio = 406.0  / 1080,
    int    roiRadius  = 200,
    void Function(String)? onStatus,
    Duration pollInterval = const Duration(seconds: 3),
    Duration timeout      = const Duration(minutes: 3),
  }) async {
    // 1. 建立請求
    onStatus?.call('上傳影片中...');
    final requestResult = await _requestAnalysis(
      videoId:    videoId,
      hitSec:     hitSec,
      flipMode:   flipMode,
      roiCxRatio: roiCxRatio,
      roiCyRatio: roiCyRatio,
      roiRadius:  roiRadius,
    );

    // 2. PUT clip 直傳到 B2
    await _uploadClip(
      uploadUrl: requestResult['clipUploadUrl'] as String,
      clipPath:  clipPath,
    );

    // 3. 通知 Worker 開始
    final analysisId = requestResult['analysisId'] as String;
    await _notifyReady(analysisId);
    debugPrint('[ServerBallTraj] 已通知 server: $analysisId');

    // 4. 輪詢等結果
    onStatus?.call('伺服器分析中...');
    return await _pollUntilDone(
      analysisId:   analysisId,
      pollInterval: pollInterval,
      timeout:      timeout,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 步驟 1
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _requestAnalysis({
    String? videoId,
    double? hitSec,
    int flipMode = 0,
    double roiCxRatio = 1149.0 / 1920,
    double roiCyRatio = 406.0  / 1080,
    int    roiRadius  = 200,
  }) async {
    final resp = await _dio.post(
      '/api/ball-trajectory/request',
      options: Options(headers: await _authHeaders()),
      data: {
        if (videoId != null) 'videoId': videoId,
        if (hitSec  != null) 'hitSec':  hitSec,
        'flipMode':   flipMode,
        'roiCxRatio': roiCxRatio,
        'roiCyRatio': roiCyRatio,
        'roiRadius':  roiRadius,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────────────────────────
  // 步驟 2：PUT clip 直傳 B2
  // ─────────────────────────────────────────────────────────────

  Future<void> _uploadClip({
    required String uploadUrl,
    required String clipPath,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file      = File(clipPath);
    final fileBytes = await file.readAsBytes();

    await _dio.put(
      uploadUrl,
      data: Stream.fromIterable([fileBytes]),
      options: Options(
        headers: {
          'Content-Type':   'video/mp4',
          'Content-Length': fileBytes.length,
        },
        sendTimeout:    const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 2),
      ),
      onSendProgress: onProgress != null
          ? (sent, total) => onProgress(sent, total)
          : null,
    );
    debugPrint('[ServerBallTraj] clip 上傳完成 ${fileBytes.length ~/ 1024}KB');
  }

  // ─────────────────────────────────────────────────────────────
  // 步驟 3
  // ─────────────────────────────────────────────────────────────

  Future<void> _notifyReady(String analysisId) async {
    await _dio.post(
      '/api/ball-trajectory/$analysisId/ready',
      options: Options(headers: await _authHeaders()),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 步驟 4：輪詢
  // ─────────────────────────────────────────────────────────────

  Future<ServerTrajectoryResult> _pollUntilDone({
    required String   analysisId,
    required Duration pollInterval,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);

      final resp = await _dio.get(
        '/api/ball-trajectory/$analysisId',
        options: Options(headers: await _authHeaders()),
      );
      final body   = resp.data as Map<String, dynamic>;
      final status = body['status'] as String? ?? '';

      debugPrint('[ServerBallTraj] poll $analysisId → $status');

      if (status == 'completed') {
        return ServerTrajectoryResult.fromJson(body);
      }
      if (status == 'failed') {
        final msg = body['errorMessage'] as String? ?? '未知錯誤';
        throw Exception('球軌跡後端分析失敗: $msg');
      }
      // pending / queued / processing → 繼續等待
    }
    throw TimeoutException('球軌跡後端分析逾時（$timeout）');
  }
}

// ─────────────────────────────────────────────────────────────
// 資料模型
// ─────────────────────────────────────────────────────────────

/// 後端回傳的原始軌跡結果。
class ServerTrajectoryResult {
  final List<TrackPoint> trackPts;  // 已轉為 TrackPoint，可直接給 renderOverlay
  final double fps;
  final int    width;
  final int    height;
  final int    rotation;

  const ServerTrajectoryResult({
    required this.trackPts,
    required this.fps,
    required this.width,
    required this.height,
    required this.rotation,
  });

  factory ServerTrajectoryResult.fromJson(Map<String, dynamic> json) {
    final resultJson = json['result'] as Map<String, dynamic>?;
    if (resultJson == null) {
      throw const FormatException('server response 缺少 result 欄位');
    }

    final fps    = (resultJson['fps']      as num?)?.toDouble() ?? 30.0;
    final width  = (resultJson['width']    as num?)?.toInt()   ?? 0;
    final height = (resultJson['height']   as num?)?.toInt()   ?? 0;
    final rot    = (resultJson['rotation'] as num?)?.toInt()   ?? 0;

    final rawPts = resultJson['trackPts'] as List<dynamic>? ?? [];
    final trackPts = rawPts.asMap().entries.map((e) {
      final pt       = e.value as Map<String, dynamic>;
      final x        = (pt['x']        as num).toInt();
      final y        = (pt['y']        as num).toInt();
      final frameIdx = (pt['frameIdx'] as num).toInt();
      final ptsUs    = (pt['ptsUs']    as num).toInt();
      return TrackPoint(
        x:        x,
        y:        y,
        rawX:     x,
        rawY:     y,
        frameIdx: frameIdx,
        ptsUs:    ptsUs,
      );
    }).toList();

    return ServerTrajectoryResult(
      trackPts: trackPts,
      fps:      fps,
      width:    width,
      height:   height,
      rotation: rot,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Token 自動刷新攔截器（與 analysis_service.dart 相同模式）
// ─────────────────────────────────────────────────────────────

class _TokenRefreshInterceptor extends Interceptor {
  final Dio _dio;
  _TokenRefreshInterceptor(this._dio);

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final refreshed = await AuthTokenStorage.instance.tryRefreshToken();
      if (refreshed) {
        final token   = await AuthTokenStorage.instance.getAccessToken();
        final opts    = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer $token';
        try {
          final resp = await _dio.fetch(opts);
          return handler.resolve(resp);
        } catch (_) {}
      }
    }
    handler.next(err);
  }
}
