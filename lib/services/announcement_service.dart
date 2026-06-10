import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/announcement.dart';
import 'auth_token_storage.dart';

class AnnouncementService {
  static const _baseUrl  = 'https://orvia.api.atk.tw';
  static const _cacheKey = 'announcements_cache';
  static const _readKey  = 'announcements_read_ids';

  AnnouncementService._();
  static final AnnouncementService instance = AnnouncementService._();

  // ── Fetch ────────────────────────────────────────────────────

  /// 從後端取得公告列表。失敗時回傳快取；快取也沒有則回傳空列表。
  Future<List<Announcement>> fetchAnnouncements() async {
    try {
      final token = await AuthTokenStorage.instance.getAccessToken();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/announcements'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (json['data'] as List? ?? json['announcements'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Announcement.fromJson)
            .where((a) => !a.isExpired)
            .toList();
        await _writeCache(list);
        debugPrint('📢 [AnnouncementService] 取得 ${list.length} 則公告');
        return list;
      }
      debugPrint('⚠️ [AnnouncementService] 後端回應 ${response.statusCode}，使用快取');
    } catch (e) {
      debugPrint('⚠️ [AnnouncementService] 請求失敗: $e，使用快取');
    }
    return await _readCache();
  }

  // ── 已讀管理 ─────────────────────────────────────────────────

  Future<Set<String>> getReadIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_readKey) ?? []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> markAsRead(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(_readKey) ?? []).toSet()..add(id);
      await prefs.setStringList(_readKey, ids.toList());
    } catch (e) {
      debugPrint('⚠️ [AnnouncementService] 標記已讀失敗: $e');
    }
  }

  Future<void> markAllAsRead(List<Announcement> announcements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = announcements.map((a) => a.id).toSet();
      await prefs.setStringList(_readKey, ids.toList());
    } catch (e) {
      debugPrint('⚠️ [AnnouncementService] 全部標記已讀失敗: $e');
    }
  }

  /// 計算未讀數量（快取 + 已讀 IDs 交叉比對）
  Future<int> getUnreadCount() async {
    try {
      final list  = await _readCache();
      final read  = await getReadIds();
      return list.where((a) => !read.contains(a.id)).length;
    } catch (_) {
      return 0;
    }
  }

  // ── 本地快取 ─────────────────────────────────────────────────

  Future<void> _writeCache(List<Announcement> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(list.map(_announcementToJson).toList());
      await prefs.setString(_cacheKey, encoded);
    } catch (e) {
      debugPrint('⚠️ [AnnouncementService] 快取寫入失敗: $e');
    }
  }

  Future<List<Announcement>> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_cacheKey);
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(Announcement.fromJson)
          .where((a) => !a.isExpired)
          .toList();
      return list;
    } catch (e) {
      debugPrint('⚠️ [AnnouncementService] 快取讀取失敗: $e');
      return [];
    }
  }

  static Map<String, dynamic> _announcementToJson(Announcement a) => {
    'id':          a.id,
    'title':       a.title,
    'body':        a.body,
    'type':        a.type.name,
    'publishedAt': a.publishedAt.toIso8601String(),
    if (a.expiresAt != null) 'expiresAt': a.expiresAt!.toIso8601String(),
    if (a.imageUrl  != null) 'imageUrl':  a.imageUrl,
  };
}
