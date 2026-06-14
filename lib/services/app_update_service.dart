import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_store_lookup_service.dart';
import 'video_server_client.dart';

// ─────────────────────────────────────────────────────────────────
// 資料模型
// ─────────────────────────────────────────────────────────────────

enum UpdateStatus {
  /// 已是最新版，不需要更新
  none,

  /// 有新版可用，使用者可選擇跳過
  optional,

  /// 版本過舊，必須更新才能繼續使用
  forced,
}

class AppUpdateResult {
  final UpdateStatus status;
  final String currentVersion;
  final String latestVersion;
  final String updateUrl;
  final List<String> releaseNotes;
  final String releaseDate;

  const AppUpdateResult({
    required this.status,
    required this.currentVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.releaseNotes,
    required this.releaseDate,
  });

  bool get needsUpdate => status != UpdateStatus.none;
  bool get isForced => status == UpdateStatus.forced;
}

// ─────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────

class AppUpdateService {
  AppUpdateService._();

  static const _snoozeKey = 'update_snoozed_version';

  /// 取得使用者選擇「不再提醒」的版本號，若無則回傳 null。
  static Future<String?> snoozedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_snoozeKey);
  }

  /// 儲存使用者選擇「不再提醒」的版本，下次遇到相同版本不再彈出對話框。
  static Future<void> snoozeVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snoozeKey, version);
  }

  /// 查詢最新版本，回傳更新結果。
  ///
  /// 檢查來源依平台對齊實際發佈通路：
  /// - iOS → App Store（iTunes lookup）為「有沒有新版」的真實來源，
  ///   強制政策仍由後端決定；查不到時退回後端檢查。
  /// - Android → 後端 orvia.api（側載 APK 通路由後端掌控版本號）。
  ///
  /// 若網路不可用或異常，回傳 [UpdateStatus.none]，不阻擋使用者。
  static Future<AppUpdateResult> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.0.0"

      if (Platform.isIOS) {
        return await _checkIos(currentVersion, info.packageName);
      }
      return await _checkBackend(currentVersion, 'android');
    } catch (e) {
      debugPrint('[AppUpdate] 版本檢查失敗（略過）: $e');
      return _noUpdate('');
    }
  }

  /// iOS：以 App Store 上架版本為準判斷是否有新版。
  static Future<AppUpdateResult> _checkIos(
      String currentVersion, String bundleId) async {
    final store = await AppStoreLookupService.lookup(bundleId);

    // App Store 查不到（未上架 / TestFlight / 網路失敗）→ 退回後端檢查
    if (store == null) {
      return _checkBackend(currentVersion, 'ios');
    }

    final isNewer = _isOlderThan(currentVersion, store.version);
    if (!isNewer) return _noUpdate(currentVersion);

    // 強制更新政策仍由後端決定（minRequiredVersion / forceUpdate），
    // 後端不可用時退回「非強制」，不阻擋使用者。
    bool forced = false;
    try {
      final data = await VideoServerClient.instance
          .checkVersion(platform: 'ios', version: currentVersion);
      if (data != null) {
        final minRequired = (data['minRequiredVersion'] as String?) ?? '0.0.0';
        final forceUpdate = (data['forceUpdate'] as bool?) ?? false;
        forced = forceUpdate || _isOlderThan(currentVersion, minRequired);
      }
    } catch (_) {
      // 後端不可用 → 非強制
    }

    debugPrint('[AppUpdate][iOS] current=$currentVersion '
        'store=${store.version} forced=$forced');

    return AppUpdateResult(
      status: forced ? UpdateStatus.forced : UpdateStatus.optional,
      currentVersion: currentVersion,
      latestVersion: store.version,
      updateUrl: store.trackViewUrl,
      releaseNotes: store.releaseNotes,
      releaseDate: '',
    );
  }

  /// 後端 orvia.api 版本檢查（Android 主用；iOS 在 App Store 查不到時退回）。
  static Future<AppUpdateResult> _checkBackend(
      String currentVersion, String platform) async {
    final data = await VideoServerClient.instance.checkVersion(
      platform: platform,
      version: currentVersion,
    );

    if (data == null) {
      return _noUpdate(currentVersion);
    }

    final latestVersion = (data['latestVersion'] as String?) ?? currentVersion;
    final minRequired  = (data['minRequiredVersion'] as String?) ?? '0.0.0';
    final forceUpdate  = (data['forceUpdate'] as bool?) ?? false;
    final updateUrl    = (data['updateUrl'] as String?) ?? '';
    final releaseDate  = (data['releaseDate'] as String?) ?? '';
    final rawNotes     = data['releaseNotes'];
    final releaseNotes = rawNotes is List
        ? rawNotes.whereType<String>().toList()
        : <String>[];

    // 判斷是否需要更新
    final isNewer = _isOlderThan(currentVersion, latestVersion);
    if (!isNewer) return _noUpdate(currentVersion);

    // 強制 or 選用：優先看後端 forceUpdate 旗標，
    // 若後端未設定則用 minRequired 自動計算
    final isForcedByVersion = _isOlderThan(currentVersion, minRequired);
    final status = (forceUpdate || isForcedByVersion)
        ? UpdateStatus.forced
        : UpdateStatus.optional;

    debugPrint('[AppUpdate] current=$currentVersion latest=$latestVersion '
        'min=$minRequired status=$status');

    return AppUpdateResult(
      status: status,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      updateUrl: updateUrl,
      releaseNotes: releaseNotes,
      releaseDate: releaseDate,
    );
  }

  // ── 工具方法 ──────────────────────────────────────────────────

  static AppUpdateResult _noUpdate(String current) => AppUpdateResult(
        status: UpdateStatus.none,
        currentVersion: current,
        latestVersion: current,
        updateUrl: '',
        releaseNotes: [],
        releaseDate: '',
      );

  /// 回傳 true 代表 [current] 版本 < [target] 版本（語意版本比較）
  static bool _isOlderThan(String current, String target) {
    try {
      final c = _parse(current);
      final t = _parse(target);
      for (int i = 0; i < 3; i++) {
        if (c[i] < t[i]) return true;
        if (c[i] > t[i]) return false;
      }
      return false; // equal
    } catch (_) {
      return false;
    }
  }

  /// 解析 "1.2.3" 或 "1.2.3+4" → [1, 2, 3]
  static List<int> _parse(String v) {
    final base = v.split('+').first;
    final parts = base.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (parts.length < 3) { parts.add(0); }
    return parts;
  }
}
