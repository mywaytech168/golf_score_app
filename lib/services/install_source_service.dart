import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// App 的安裝來源分類。
enum AppDistribution {
  /// Android：由 Google Play 商店安裝 → 自我更新必須走 Play 管道
  playStore,

  /// Android：側載 / APK / 其他商店安裝 → 可走外部下載更新
  sideload,

  /// iOS：App Store / TestFlight（更新一律走 App Store）
  iosStore,

  /// 無法判定（罕見，例如部分 ROM 取不到 installer）
  unknown,
}

/// 判斷 App 安裝來源，並依來源開啟正確的更新管道。
///
/// 關鍵：Google Play 政策禁止「從 Play 安裝的 App」用外部下載 APK 自我更新，
/// 否則會違規下架。因此 Play 安裝 → 導向 Play 商店頁；其餘 → 後端外部連結。
class InstallSourceService {
  InstallSourceService._();

  static const _channel = MethodChannel('com.example.golf_score_app/app_info');
  static const _updateChannel =
      MethodChannel('com.example.golf_score_app/app_update');

  /// Google Play 商店的 installer package name。
  static const _playStorePackage = 'com.android.vending';

  /// Play 更新優先級門檻：>= 此值用 Immediate（全螢幕強制），否則 Flexible。
  /// 優先級於 Play Console 發版時設定（0-5）。
  static const _immediatePriorityThreshold = 4;

  /// 安裝來源整個 session 不會變，偵測一次後快取。
  static AppDistribution? _cached;

  /// Flexible 更新下載完成的回呼（由 UI 層設定以顯示「重啟套用」提示）。
  static VoidCallback? _onFlexibleDownloaded;

  /// 設定 Flexible 更新下載完成回呼。設定時即註冊原生→Dart 的 channel handler。
  /// 傳 null 取消（例如 UI dispose）。
  static set onFlexibleUpdateDownloaded(VoidCallback? callback) {
    _onFlexibleDownloaded = callback;
    _updateChannel.setMethodCallHandler(callback == null ? null : _handleNative);
  }

  static Future<dynamic> _handleNative(MethodCall call) async {
    if (call.method == 'onFlexibleDownloaded') {
      _onFlexibleDownloaded?.call();
    }
    return null;
  }

  /// 套用已下載的 Flexible 更新（觸發安裝並重啟 App）。
  static Future<void> completeFlexibleUpdate() async {
    try {
      await _updateChannel.invokeMethod('complete');
    } catch (e) {
      debugPrint('[InstallSource] completeUpdate 失敗: $e');
    }
  }

  /// 偵測（並快取）App 的安裝來源。
  static Future<AppDistribution> distribution() async {
    return _cached ??= await _detect();
  }

  /// 是否由 Google Play 安裝。
  static Future<bool> get isPlayInstall async =>
      (await distribution()) == AppDistribution.playStore;

  static Future<AppDistribution> _detect() async {
    if (Platform.isIOS) return AppDistribution.iosStore;
    if (!Platform.isAndroid) return AppDistribution.unknown;
    try {
      final installer =
          await _channel.invokeMethod<String>('getInstallerPackageName');
      debugPrint('[InstallSource] installer=$installer');
      return installer == _playStorePackage
          ? AppDistribution.playStore
          : AppDistribution.sideload;
    } catch (e) {
      // 取不到安裝來源 → 視為未知，後續退回外部更新（不阻擋使用者）
      debugPrint('[InstallSource] 偵測失敗（退回外部更新）: $e');
      return AppDistribution.unknown;
    }
  }

  /// Play 安裝專用：透過 Play Core 啟動原生應用內更新流程。
  ///
  /// 由 Play Store 自己判斷「有沒有可裝的更新」（版本真實來源＝Play，
  /// 免疫上架審查不同步）並負責下載安裝，App 不碰 APK、不需任何權限。
  /// 更新模式依 Play Console 設定的 updatePriority 決定：
  /// 高優先級 → Immediate（全螢幕擋住，等同強制更新）；否則 Flexible（背景下載）。
  ///
  /// Play 回報無更新（含審查中）→ 靜默結束。流程失敗 → 退回開 Play 商店頁。
  /// 僅供 Android Play 安裝呼叫；其他來源請用 [launchUpdate]。
  static Future<void> runPlayUpdateFlow() async {
    try {
      final info =
          await _updateChannel.invokeMapMethod<String, dynamic>('check');
      if (info == null || info['available'] != true) {
        debugPrint('[InstallSource] Play 回報無可用更新');
        return;
      }

      final immediateAllowed = info['immediateAllowed'] == true;
      final flexibleAllowed = info['flexibleAllowed'] == true;
      if (!immediateAllowed && !flexibleAllowed) return;

      final priority = (info['priority'] as int?) ?? 0;
      // 高優先級且裝置支援 → Immediate；否則 Flexible。
      // 若僅支援其中一種模式，退回可用者。
      final preferImmediate =
          priority >= _immediatePriorityThreshold && immediateAllowed;
      final useImmediate = preferImmediate || !flexibleAllowed;

      await _updateChannel
          .invokeMethod('start', {'immediate': useImmediate});
    } catch (e) {
      debugPrint('[InstallSource] Play 更新流程失敗（退回商店頁）: $e');
      await _openPlayStorePage();
    }
  }

  /// 依安裝來源開啟正確的更新管道（供自訂更新對話框的「立即更新」呼叫）。
  ///
  /// - Play 安裝 → 開 Play 商店該 App 頁面（防呆：正常情況 Play 走
  ///   [runPlayUpdateFlow] 不會進到自訂對話框，此處僅為避免誤開外部 APK 的保險）。
  /// - 其他（側載 / iOS / 未知）→ 開後端提供的 [externalUrl]
  ///   （側載 = APK 連結；iOS = App Store 連結）。
  ///
  /// 回傳 true 代表成功開啟更新管道。
  static Future<bool> launchUpdate(String externalUrl) async {
    if (await isPlayInstall) {
      return _openPlayStorePage();
    }

    if (externalUrl.isEmpty) return false;
    return launchUrl(
      Uri.parse(externalUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  /// 開啟 Play 商店該 App 頁面（market:// 直接喚起 Play App，失敗退回網頁版）。
  static Future<bool> _openPlayStorePage() async {
    final pkg = (await PackageInfo.fromPlatform()).packageName;
    final market = Uri.parse('market://details?id=$pkg');
    try {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Play App 不存在（極罕見）→ 退回網頁版商店
    }
    final web =
        Uri.parse('https://play.google.com/store/apps/details?id=$pkg');
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }
}
