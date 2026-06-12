import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recording_history_entry.dart';
import 'skeleton_csv_locator.dart';
import 'video_server_client.dart';

// ════════════════════════════════════════════════════════════════
// 獎勵類型
// ════════════════════════════════════════════════════════════════

enum RewardType { watchAd, inviteFriend, submitFeedback, uploadData }

extension RewardTypeX on RewardType {
  String get label {
    switch (this) {
      case RewardType.watchAd:        return '看廣告';
      case RewardType.inviteFriend:   return '邀請好友';
      case RewardType.submitFeedback: return '問題回饋';
      case RewardType.uploadData:     return '上傳資料';
    }
  }

  String get description {
    switch (this) {
      case RewardType.watchAd:
        return '觀看一則廣告，獲得額外球數';
      case RewardType.inviteFriend:
        return '好友使用你的邀請碼註冊，雙方各得獎勵';
      case RewardType.submitFeedback:
        return '回報問題或建議，幫助改善 App';
      case RewardType.uploadData:
        return '上傳本地分析資料至伺服器，協助 AI 訓練';
    }
  }

  /// 每次動作獲得的球數
  int get ballsPerAction {
    switch (this) {
      case RewardType.watchAd:        return 1;
      case RewardType.inviteFriend:   return 5;
      case RewardType.submitFeedback: return 2;
      case RewardType.uploadData:     return 3;
    }
  }

  /// 每日上限；-1 = 無限制
  int get dailyCap {
    switch (this) {
      case RewardType.watchAd:        return 5;
      case RewardType.inviteFriend:   return -1;
      case RewardType.submitFeedback: return 1;
      case RewardType.uploadData:     return -1;
    }
  }
}

// ════════════════════════════════════════════════════════════════
// 獎勵狀態
// ════════════════════════════════════════════════════════════════

class RewardStatus {
  /// 累積獎勵球數（後端儲存）
  final int bonusBalls;

  /// 今日已看廣告次數
  final int adClaimedToday;

  /// 今日是否已提交回饋
  final bool feedbackClaimedToday;

  /// 使用者邀請碼
  final String? inviteCode;

  /// 已成功邀請的好友數
  final int inviteCount;

  /// 是否已使用過別人的邀請碼（每帳號限一次）
  final bool hasAppliedInviteCode;

  /// true = 後端不可用，資料來自本地快取
  final bool fromCache;

  const RewardStatus({
    this.bonusBalls = 0,
    this.adClaimedToday = 0,
    this.feedbackClaimedToday = false,
    this.inviteCode,
    this.inviteCount = 0,
    this.hasAppliedInviteCode = false,
    this.fromCache = false,
  });

  bool get canWatchAd => adClaimedToday < RewardType.watchAd.dailyCap;
  bool get canSubmitFeedback => !feedbackClaimedToday;
  bool get canApplyInviteCode => !hasAppliedInviteCode;

  RewardStatus copyWith({
    int? bonusBalls,
    int? adClaimedToday,
    bool? feedbackClaimedToday,
    String? inviteCode,
    int? inviteCount,
    bool? hasAppliedInviteCode,
    bool? fromCache,
  }) {
    return RewardStatus(
      bonusBalls:           bonusBalls           ?? this.bonusBalls,
      adClaimedToday:       adClaimedToday       ?? this.adClaimedToday,
      feedbackClaimedToday: feedbackClaimedToday ?? this.feedbackClaimedToday,
      inviteCode:           inviteCode           ?? this.inviteCode,
      inviteCount:          inviteCount          ?? this.inviteCount,
      hasAppliedInviteCode: hasAppliedInviteCode ?? this.hasAppliedInviteCode,
      fromCache:            fromCache            ?? this.fromCache,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// RewardService
// ════════════════════════════════════════════════════════════════

class RewardService {
  RewardService._();

  static const _tag = '[RewardService]';
  static const _keyBonusBalls    = 'reward_bonus_balls';
  static const _keyAdCount       = 'reward_ad_count';
  static const _keyAdDate        = 'reward_ad_date';
  static const _keyFeedbackDate  = 'reward_feedback_date';
  static const _keyInviteCode    = 'reward_invite_code';
  static const _keyInviteCount   = 'reward_invite_count';

  // ── 取得獎勵狀態 ─────────────────────────────────────────────

  static Future<RewardStatus> getStatus() async {
    try {
      final data = await VideoServerClient.instance.getRewardStatus();
      if (data != null) {
        final status = RewardStatus(
          bonusBalls:           (data['bonusBalls']           as int?)  ?? 0,
          adClaimedToday:       (data['adClaimedToday']       as int?)  ?? 0,
          feedbackClaimedToday: (data['feedbackClaimedToday'] as bool?) ?? false,
          inviteCode:            data['inviteCode']            as String?,
          inviteCount:          (data['inviteCount']           as int?)  ?? 0,
          hasAppliedInviteCode: (data['hasAppliedInviteCode'] as bool?) ?? false,
        );
        await _cacheStatus(status);
        debugPrint('$_tag ✅ 後端: bonus=${status.bonusBalls} ad=${status.adClaimedToday}');
        return status;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ⚠️ 後端不可用，使用快取: $e');
    }
    return _readCachedStatus();
  }

  // ── 看廣告獎勵 ───────────────────────────────────────────────

  /// 廣告看完後呼叫，回傳實際獎勵球數（0 = 失敗 / 已達上限）
  static Future<int> claimAdReward() async {
    try {
      final result = await VideoServerClient.instance.claimAdReward();
      if (result != null) {
        final balls = (result['balls'] as int?) ?? 0;
        debugPrint('$_tag ✅ 廣告獎勵: +$balls 球');
        return balls;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 廣告獎勵失敗: $e');
    }
    return 0;
  }

  // ── 邀請碼 ───────────────────────────────────────────────────

  static Future<String?> getInviteCode() async {
    try {
      final code = await VideoServerClient.instance.getInviteCode();
      if (code != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyInviteCode, code);
        return code;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 邀請碼失敗: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyInviteCode);
  }

  // ── 套用邀請碼 ───────────────────────────────────────────────

  /// 套用好友邀請碼，回傳 `(success, message, ballsEarned)`
  static Future<({bool success, String message, int balls})> applyInviteCode(
      String code) async {
    try {
      final result = await VideoServerClient.instance.applyInviteCode(code);
      if (result == null) return (success: false, message: '伺服器無回應', balls: 0);
      final success = result['success'] as bool? ?? false;
      final msg     = result['message'] as String? ?? '';
      final balls   = (result['ballsEarned'] as num?)?.toInt() ?? 0;
      return (success: success, message: msg, balls: balls);
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 套用邀請碼失敗: $e');
      return (success: false, message: '網路錯誤：$e', balls: 0);
    }
  }

  // ── 問題回饋 ─────────────────────────────────────────────────

  /// [type] = 'bug' | 'feature' | 'other'
  /// 回傳實際獎勵球數
  static Future<int> submitFeedback({
    required String type,
    required String text,
    String? videoId,
    String? imageB2Key,
  }) async {
    try {
      final result = await VideoServerClient.instance.submitFeedback(
        type: type,
        text: text,
        videoId: videoId,
        imageB2Key: imageB2Key,
      );
      if (result != null) {
        final balls = (result['balls'] as int?) ?? 0;
        debugPrint('$_tag ✅ 回饋獎勵: +$balls 球');
        return balls;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 回饋提交失敗: $e');
    }
    return 0;
  }

  // ── 上傳資料獎勵 ─────────────────────────────────────────────

  /// 真實上傳該筆錄影的影片 + 骨架 CSV 到伺服器（presigned PUT）。
  ///
  /// - entry 已上傳過或做過 AI 分析（檔案已在伺服器）→ 回 null，不重傳。
  /// - 否則：prepare 取得 uploadId 與 PUT URL → 上傳影片（entry.filePath）
  ///   與 CSV（同目錄 pose_landmarks.csv，找不到就略過）→ 回 uploadId。
  /// - 任一步失敗（含 prepare / 影片 PUT）丟例外。
  static Future<String?> uploadSessionFiles(RecordingHistoryEntry entry) async {
    if (entry.isEffectivelyUploaded) return null;

    final videoFile = File(entry.filePath);
    if (!videoFile.existsSync()) {
      throw Exception('找不到影片檔案：${entry.filePath}');
    }

    final prep = await VideoServerClient.instance.prepareDatasetUpload();
    if (prep == null) {
      throw Exception('無法取得上傳授權，請稍後再試');
    }
    final uploadId = prep['uploadId'] as String?;
    final videoUrl = prep['videoUploadUrl'] as String?;
    final csvUrl   = prep['csvUploadUrl'] as String?;
    if (uploadId == null || videoUrl == null) {
      throw Exception('上傳授權回應格式錯誤');
    }

    // 影片直傳（presigned PUT）
    await _putFile(videoUrl, videoFile, 'video/mp4');
    debugPrint('$_tag ✅ 資料集影片上傳完成 ($uploadId)');

    // CSV 直傳（可能不存在，略過）
    final csvPath = resolveSkeletonCsv(p.dirname(entry.filePath));
    if (csvPath != null && csvUrl != null) {
      try {
        await _putFile(csvUrl, File(csvPath), 'text/csv');
        debugPrint('$_tag ✅ 資料集 CSV 上傳完成 ($uploadId)');
      } catch (e) {
        debugPrint('$_tag ⚠️ 資料集 CSV 上傳失敗（略過）: $e');
      }
    }

    return uploadId;
  }

  static Future<void> _putFile(
      String url, File file, String contentType) async {
    final bytes = await file.readAsBytes();
    final resp = await http
        .put(
          Uri.parse(url),
          headers: {'Content-Type': contentType},
          body: bytes,
        )
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('檔案上傳失敗 (HTTP ${resp.statusCode})');
    }
  }

  /// [sessions] = 精簡的錄影記錄清單（不含影片二進位）
  ///
  /// 審核制：送出後建立待審核紀錄，審核通過後才發球。
  /// 回傳本次新建立的待審核筆數（重複提交 = 0）。
  static Future<int> claimUploadReward({
    required List<Map<String, dynamic>> sessions,
  }) async {
    try {
      final result = await VideoServerClient.instance.claimUploadReward(
        sessions: sessions,
      );
      if (result != null) {
        final pending = (result['pending'] as int?) ?? 0;
        debugPrint('$_tag ✅ 上傳送審: $pending 筆待審核');
        return pending;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 上傳送審失敗: $e');
    }
    return 0;
  }

  /// 查詢自己的資料上傳審核狀態（審核中 / 已通過筆數摘要）
  static Future<Map<String, dynamic>?> getUploadReviewStatus({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      return await VideoServerClient.instance
          .getMyDatasetUploads(page: page, pageSize: pageSize);
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 審核狀態查詢失敗: $e');
      return null;
    }
  }

  // ── 本地快取 ─────────────────────────────────────────────────

  static Future<void> _cacheStatus(RewardStatus s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _today();
      await prefs.setInt(_keyBonusBalls,  s.bonusBalls);
      await prefs.setInt(_keyAdCount,     s.adClaimedToday);
      await prefs.setString(_keyAdDate,   today);
      await prefs.setInt(_keyInviteCount, s.inviteCount);
      if (s.feedbackClaimedToday) await prefs.setString(_keyFeedbackDate, today);
      if (s.inviteCode != null)   await prefs.setString(_keyInviteCode, s.inviteCode!);
    } catch (_) {}
  }

  static Future<RewardStatus> _readCachedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _today();
      final adDate      = prefs.getString(_keyAdDate)      ?? '';
      final feedDate    = prefs.getString(_keyFeedbackDate) ?? '';
      return RewardStatus(
        bonusBalls:           prefs.getInt(_keyBonusBalls)   ?? 0,
        adClaimedToday:       adDate == today ? (prefs.getInt(_keyAdCount) ?? 0) : 0,
        feedbackClaimedToday: feedDate == today,
        inviteCode:           prefs.getString(_keyInviteCode),
        inviteCount:          prefs.getInt(_keyInviteCount) ?? 0,
        fromCache:            true,
      );
    } catch (_) {
      return const RewardStatus(fromCache: true);
    }
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);
}
