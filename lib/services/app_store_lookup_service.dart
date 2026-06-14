import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// App Store 上某 App 的版本資訊（由 iTunes lookup API 取得）。
class AppStoreVersionInfo {
  /// App Store 上目前上架的版本號（e.g. "1.0.0"）
  final String version;

  /// App Store 該 App 頁面網址（用於開啟更新）
  final String trackViewUrl;

  /// 該版本的更新說明（依換行拆成多行）
  final List<String> releaseNotes;

  const AppStoreVersionInfo({
    required this.version,
    required this.trackViewUrl,
    required this.releaseNotes,
  });
}

/// 透過 Apple 公開的 iTunes lookup API 查詢 App Store 上的實際版本。
///
/// 用途：iOS 的更新檢查直接對齊「App Store 上已過審上架的版本」，
/// 避免後端版本號與商店實際版本不同步造成的誤判
/// （後端說有新版但 App Store 還在審核 → 使用者點更新卻看到同一版）。
class AppStoreLookupService {
  AppStoreLookupService._();

  /// 查詢指定 [bundleId] 在 App Store 的版本資訊。
  ///
  /// [country] 為兩碼國別（e.g. "tw"、"us"）；省略則由 Apple 預設（US）。
  /// 版本號全球一致，通常無需指定。
  ///
  /// 查無結果（App 尚未上架 / TestFlight only）或網路失敗 → 回傳 null，
  /// 呼叫端應退回後端檢查，不阻擋使用者。
  static Future<AppStoreVersionInfo?> lookup(
    String bundleId, {
    String? country,
  }) async {
    try {
      final query = <String, String>{'bundleId': bundleId};
      if (country != null && country.isNotEmpty) query['country'] = country;
      final uri = Uri.https('itunes.apple.com', '/lookup', query);

      final resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('[AppStoreLookup] HTTP ${resp.statusCode}');
        return null;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        debugPrint('[AppStoreLookup] 查無 bundleId=$bundleId（可能尚未上架）');
        return null;
      }

      final first = results.first as Map<String, dynamic>;
      final version = (first['version'] as String?)?.trim();
      if (version == null || version.isEmpty) return null;

      final trackViewUrl = (first['trackViewUrl'] as String?) ?? '';
      final rawNotes = (first['releaseNotes'] as String?) ?? '';
      final notes = rawNotes
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      debugPrint('[AppStoreLookup] storeVersion=$version');
      return AppStoreVersionInfo(
        version: version,
        trackViewUrl: trackViewUrl,
        releaseNotes: notes,
      );
    } catch (e) {
      debugPrint('[AppStoreLookup] 查詢失敗（退回後端檢查）: $e');
      return null;
    }
  }
}
