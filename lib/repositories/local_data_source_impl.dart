import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'data_sources.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// 本地数据源实现
/// 使用 SharedPreferences 存储数据
class LocalDataSourceImpl implements LocalDataSource {
  final SharedPreferences _prefs;

  // 存储键常量
  static const String _keyAccessToken = 'auth_access_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyTokenExpiry = 'auth_token_expiry';
  static const String _keyUserProfile = 'user_profile';
  static const String _keyTodayStats = 'stats_today';
  static const String _keyAllTimeStats = 'stats_all_time';
  static const String _keyStatsExpiry = 'stats_expiry';
  static const String _keyRecordingHistory = 'recording_history';

  LocalDataSourceImpl({required SharedPreferences prefs}) : _prefs = prefs;

  // ===== Auth Operations =====

  @override
  Future<String?> getAccessToken() async {
    try {
      final token = _prefs.getString(_keyAccessToken);
      Logger.debug('Retrieved access token', tag: 'LocalDataSource');
      return token;
    } catch (e) {
      Logger.error('Failed to get access token: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to retrieve access token');
    }
  }

  @override
  Future<void> saveAccessToken(String token, String refreshToken) async {
    try {
      await Future.wait([
        _prefs.setString(_keyAccessToken, token),
        _prefs.setString(_keyRefreshToken, refreshToken),
        _prefs.setString(
          _keyTokenExpiry,
          DateTime.now().add(Duration(hours: 24)).toIso8601String(),
        ),
      ]);
      Logger.info('Saved access token', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to save access token: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to save access token');
    }
  }

  @override
  Future<String?> getRefreshToken() async {
    try {
      final token = _prefs.getString(_keyRefreshToken);
      Logger.debug('Retrieved refresh token', tag: 'LocalDataSource');
      return token;
    } catch (e) {
      Logger.error('Failed to get refresh token: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to retrieve refresh token');
    }
  }

  @override
  Future<void> clearAuthTokens() async {
    try {
      await Future.wait([
        _prefs.remove(_keyAccessToken),
        _prefs.remove(_keyRefreshToken),
        _prefs.remove(_keyTokenExpiry),
      ]);
      Logger.info('Cleared auth tokens', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to clear auth tokens: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to clear auth tokens');
    }
  }

  // ===== User Operations =====

  @override
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final json = _prefs.getString(_keyUserProfile);
      if (json == null) return null;
      final profile = jsonDecode(json) as Map<String, dynamic>;
      Logger.debug('Retrieved user profile', tag: 'LocalDataSource');
      return profile;
    } catch (e) {
      Logger.error('Failed to get user profile: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to retrieve user profile');
    }
  }

  @override
  Future<void> saveUserProfile(Map<String, dynamic> profile) async {
    try {
      await _prefs.setString(_keyUserProfile, jsonEncode(profile));
      Logger.info('Saved user profile', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to save user profile: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to save user profile');
    }
  }

  @override
  Future<void> clearUserProfile() async {
    try {
      await _prefs.remove(_keyUserProfile);
      Logger.info('Cleared user profile', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to clear user profile: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to clear user profile');
    }
  }

  // ===== Statistics Operations =====

  @override
  Future<Map<String, dynamic>?> getTodayStatistics() async {
    try {
      final json = _prefs.getString(_keyTodayStats);
      if (json == null) return null;
      final stats = jsonDecode(json) as Map<String, dynamic>;
      Logger.debug('Retrieved today statistics', tag: 'LocalDataSource');
      return stats;
    } catch (e) {
      Logger.error('Failed to get today stats: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to retrieve today statistics');
    }
  }

  @override
  Future<void> saveTodayStatistics(Map<String, dynamic> statistics) async {
    try {
      await Future.wait([
        _prefs.setString(_keyTodayStats, jsonEncode(statistics)),
        _prefs.setString(_keyStatsExpiry, DateTime.now().toIso8601String()),
      ]);
      Logger.info('Saved today statistics', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to save today stats: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to save today statistics');
    }
  }

  @override
  Future<Map<String, dynamic>?> getAllTimeStatistics() async {
    try {
      final json = _prefs.getString(_keyAllTimeStats);
      if (json == null) return null;
      final stats = jsonDecode(json) as Map<String, dynamic>;
      Logger.debug('Retrieved all-time statistics', tag: 'LocalDataSource');
      return stats;
    } catch (e) {
      Logger.error('Failed to get all-time stats: $e',
          tag: 'LocalDataSource');
      throw StorageException('Failed to retrieve all-time statistics');
    }
  }

  @override
  Future<void> saveAllTimeStatistics(Map<String, dynamic> statistics) async {
    try {
      await _prefs.setString(_keyAllTimeStats, jsonEncode(statistics));
      Logger.info('Saved all-time statistics', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to save all-time stats: $e',
          tag: 'LocalDataSource');
      throw StorageException('Failed to save all-time statistics');
    }
  }

  @override
  Future<String?> getStatsExpiryTime() async {
    try {
      final expiry = _prefs.getString(_keyStatsExpiry);
      return expiry;
    } catch (e) {
      Logger.error('Failed to get stats expiry: $e', tag: 'LocalDataSource');
      return null;
    }
  }

  // ===== Recording Operations =====

  @override
  Future<List<Map<String, dynamic>>?> getRecordingHistory() async {
    try {
      final json = _prefs.getString(_keyRecordingHistory);
      if (json == null) return null;
      final history = List<Map<String, dynamic>>.from(
        jsonDecode(json) as List,
      );
      Logger.debug('Retrieved recording history', tag: 'LocalDataSource');
      return history;
    } catch (e) {
      Logger.error('Failed to get recording history: $e',
          tag: 'LocalDataSource');
      throw StorageException('Failed to retrieve recording history');
    }
  }

  @override
  Future<void> saveLocalRecording(Map<String, dynamic> recording) async {
    try {
      final history = await getRecordingHistory() ?? [];
      history.add(recording);
      await _prefs.setString(_keyRecordingHistory, jsonEncode(history));
      Logger.info('Saved local recording', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to save local recording: $e',
          tag: 'LocalDataSource');
      throw StorageException('Failed to save local recording');
    }
  }

  @override
  Future<void> deleteLocalRecording(String recordingId) async {
    try {
      final history = await getRecordingHistory() ?? [];
      history.removeWhere((r) => r['id'] == recordingId);
      await _prefs.setString(_keyRecordingHistory, jsonEncode(history));
      Logger.info('Deleted local recording: $recordingId',
          tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to delete local recording: $e',
          tag: 'LocalDataSource');
      throw StorageException('Failed to delete local recording');
    }
  }

  // ===== Generic Cache Operations =====

  @override
  Future<dynamic> getCacheValue(String key) async {
    try {
      final value = _prefs.get(key);
      Logger.debug('Retrieved cache value for key: $key', tag: 'LocalDataSource');
      return value;
    } catch (e) {
      Logger.error('Failed to get cache value: $e', tag: 'LocalDataSource');
      return null;
    }
  }

  @override
  Future<void> saveCacheValue(String key, dynamic value) async {
    try {
      if (value is String) {
        await _prefs.setString(key, value);
      } else if (value is int) {
        await _prefs.setInt(key, value);
      } else if (value is double) {
        await _prefs.setDouble(key, value);
      } else if (value is bool) {
        await _prefs.setBool(key, value);
      } else if (value is List<String>) {
        await _prefs.setStringList(key, value);
      } else {
        // For complex objects, convert to JSON
        await _prefs.setString(key, jsonEncode(value));
      }
      Logger.info('Saved cache value for key: $key', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to save cache value: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to save cache value');
    }
  }

  @override
  Future<void> removeCacheValue(String key) async {
    try {
      await _prefs.remove(key);
      Logger.info('Removed cache value for key: $key', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to remove cache value: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to remove cache value');
    }
  }

  @override
  Future<void> clearAllCache() async {
    try {
      await _prefs.clear();
      Logger.info('Cleared all cache', tag: 'LocalDataSource');
    } catch (e) {
      Logger.error('Failed to clear all cache: $e', tag: 'LocalDataSource');
      throw StorageException('Failed to clear all cache');
    }
  }
}
