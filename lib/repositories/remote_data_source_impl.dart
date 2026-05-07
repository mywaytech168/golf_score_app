import 'package:http/http.dart' as http;
import 'dart:convert';
import 'data_sources.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// 远程数据源实现
/// 使用 HTTP REST API 进行网络通信
class RemoteDataSourceImpl implements RemoteDataSource {
  final http.Client _httpClient;
  final String _baseUrl;

  RemoteDataSourceImpl({
    required http.Client httpClient,
    required String baseUrl,
  })  : _httpClient = httpClient,
        _baseUrl = baseUrl;

  // ===== Auth Operations =====

  @override
  Future<Map<String, dynamic>> signInWithGoogle(String idToken) async {
    try {
      Logger.debug('Signing in with Google', tag: 'RemoteDataSource');
      logHttpRequest('POST', '$_baseUrl/auth/google-signin', {'idToken': idToken});

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/google-signin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw NetworkException('Sign in request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        Logger.info('Google sign in successful', tag: 'RemoteDataSource');
        return result;
      } else if (response.statusCode == 401) {
        throw InvalidTokenException('Invalid Google ID token');
      } else if (response.statusCode == 500) {
        throw ServerException('Server error during sign in');
      } else {
        throw NetworkException(
          'Sign in failed: ${response.statusCode}',
        );
      }
    } on InvalidTokenException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      Logger.error('Google sign in error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to sign in with Google: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      Logger.debug('Refreshing token', tag: 'RemoteDataSource');
      logHttpRequest('POST', '$_baseUrl/auth/refresh-token', {'refreshToken': refreshToken});

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw NetworkException('Token refresh request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        Logger.info('Token refreshed successfully', tag: 'RemoteDataSource');
        return result;
      } else if (response.statusCode == 401) {
        throw InvalidTokenException('Refresh token expired');
      } else if (response.statusCode == 500) {
        throw ServerException('Server error during token refresh');
      } else {
        throw NetworkException('Token refresh failed: ${response.statusCode}');
      }
    } on InvalidTokenException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      Logger.error('Token refresh error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to refresh token: $e');
    }
  }

  @override
  Future<void> signOut(String accessToken) async {
    try {
      Logger.debug('Signing out', tag: 'RemoteDataSource');
      logHttpRequest('POST', '$_baseUrl/auth/signout', {});

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/signout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw NetworkException('Sign out request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        Logger.info('Sign out successful', tag: 'RemoteDataSource');
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized sign out');
      } else {
        Logger.warning('Sign out returned: ${response.statusCode}',
            tag: 'RemoteDataSource');
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      Logger.error('Sign out error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to sign out: $e');
    }
  }

  // ===== User Operations =====

  @override
  Future<Map<String, dynamic>> fetchUserProfile(
    String accessToken,
    String userId,
  ) async {
    try {
      Logger.debug('Fetching user profile for: $userId', tag: 'RemoteDataSource');
      logHttpRequest('GET', '$_baseUrl/users/$userId', {});

      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw NetworkException('Fetch profile request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body) as Map<String, dynamic>;
        Logger.info('User profile fetched', tag: 'RemoteDataSource');
        return profile;
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized profile fetch');
      } else if (response.statusCode == 404) {
        throw DataNotFoundException('User profile not found');
      } else {
        throw NetworkException(
          'Failed to fetch profile: ${response.statusCode}',
        );
      }
    } on UnauthorizedException {
      rethrow;
    } on DataNotFoundException {
      rethrow;
    } catch (e) {
      Logger.error('Fetch profile error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to fetch user profile: $e');
    }
  }

  @override
  Future<void> updateUserProfile(
    String accessToken,
    String userId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      Logger.debug('Updating user profile for: $userId', tag: 'RemoteDataSource');
      logHttpRequest('PUT', '$_baseUrl/users/$userId', profileData);

      final response = await _httpClient.put(
        Uri.parse('$_baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(profileData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw NetworkException('Update profile request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        Logger.info('User profile updated', tag: 'RemoteDataSource');
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized profile update');
      } else if (response.statusCode == 400) {
        throw ValidationException('Invalid profile data');
      } else {
        throw NetworkException('Failed to update profile: ${response.statusCode}');
      }
    } on UnauthorizedException {
      rethrow;
    } on ValidationException {
      rethrow;
    } catch (e) {
      Logger.error('Update profile error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to update user profile: $e');
    }
  }

  // ===== Statistics Operations =====

  @override
  Future<Map<String, dynamic>> fetchTodayStatistics(
    String accessToken,
    String userId,
  ) async {
    try {
      Logger.debug('Fetching today statistics for: $userId',
          tag: 'RemoteDataSource');
      logHttpRequest('GET', '$_baseUrl/users/$userId/statistics/today', {});

      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/users/$userId/statistics/today'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw NetworkException('Fetch today stats request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final stats = jsonDecode(response.body) as Map<String, dynamic>;
        Logger.info('Today statistics fetched', tag: 'RemoteDataSource');
        return stats;
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized stats fetch');
      } else {
        throw NetworkException('Failed to fetch today stats: ${response.statusCode}');
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      Logger.error('Fetch today stats error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to fetch today statistics: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> fetchAllTimeStatistics(
    String accessToken,
    String userId,
  ) async {
    try {
      Logger.debug('Fetching all-time statistics for: $userId',
          tag: 'RemoteDataSource');
      logHttpRequest('GET', '$_baseUrl/users/$userId/statistics/all-time', {});

      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/users/$userId/statistics/all-time'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw NetworkException('Fetch all-time stats request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final stats = jsonDecode(response.body) as Map<String, dynamic>;
        Logger.info('All-time statistics fetched', tag: 'RemoteDataSource');
        return stats;
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized stats fetch');
      } else {
        throw NetworkException(
          'Failed to fetch all-time stats: ${response.statusCode}',
        );
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      Logger.error('Fetch all-time stats error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to fetch all-time statistics: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStatisticsHistory(
    String accessToken,
    String userId, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      Logger.debug('Fetching statistics history for: $userId',
          tag: 'RemoteDataSource');
      final uri = Uri.parse(
        '$_baseUrl/users/$userId/statistics/history?limit=$limit&offset=$offset',
      );
      logHttpRequest('GET', uri.toString(), {});

      final response = await _httpClient.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw NetworkException('Fetch stats history request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final history = List<Map<String, dynamic>>.from(
          jsonDecode(response.body) as List,
        );
        Logger.info('Statistics history fetched (${history.length} items)',
            tag: 'RemoteDataSource');
        return history;
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized history fetch');
      } else {
        throw NetworkException('Failed to fetch stats history: ${response.statusCode}');
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      Logger.error('Fetch stats history error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to fetch statistics history: $e');
    }
  }

  // ===== Recording Operations =====

  @override
  Future<List<Map<String, dynamic>>> fetchRecordingHistory(
    String accessToken,
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      Logger.debug('Fetching recording history for: $userId',
          tag: 'RemoteDataSource');
      final uri = Uri.parse(
        '$_baseUrl/users/$userId/recordings?limit=$limit&offset=$offset',
      );
      logHttpRequest('GET', uri.toString(), {});

      final response = await _httpClient.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw NetworkException('Fetch recording history request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        final history = List<Map<String, dynamic>>.from(
          jsonDecode(response.body) as List,
        );
        Logger.info(
          'Recording history fetched (${history.length} items)',
          tag: 'RemoteDataSource',
        );
        return history;
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized history fetch');
      } else {
        throw NetworkException('Failed to fetch recording history: ${response.statusCode}');
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      Logger.error('Fetch recording history error: $e',
          tag: 'RemoteDataSource');
      throw NetworkException('Failed to fetch recording history: $e');
    }
  }

  @override
  Future<String> uploadRecording(
    String accessToken,
    String userId,
    String filePath,
    Map<String, dynamic> metadata, {
    void Function(int, int)? onProgress,
  }) async {
    try {
      Logger.debug('Uploading recording: $filePath', tag: 'RemoteDataSource');

      final file = await _getFile(filePath);
      final fileBytes = await file.readAsBytes();
      final fileName = file.path.split('/').last;

      // For now, simple implementation
      // In production, use MultipartRequest with proper streaming
      Logger.warning(
        'Recording upload not fully implemented in RemoteDataSourceImpl',
        tag: 'RemoteDataSource',
      );
      throw NotImplementedException('Recording upload requires MultipartRequest');
    } catch (e) {
      Logger.error('Upload recording error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to upload recording: $e');
    }
  }

  @override
  Future<void> deleteRemoteRecording(
    String accessToken,
    String userId,
    String recordingId,
  ) async {
    try {
      Logger.debug('Deleting remote recording: $recordingId',
          tag: 'RemoteDataSource');
      logHttpRequest('DELETE', '$_baseUrl/users/$userId/recordings/$recordingId', {});

      final response = await _httpClient.delete(
        Uri.parse('$_baseUrl/users/$userId/recordings/$recordingId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw NetworkException('Delete recording request timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      if (response.statusCode == 200) {
        Logger.info('Remote recording deleted', tag: 'RemoteDataSource');
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized delete');
      } else if (response.statusCode == 404) {
        throw DataNotFoundException('Recording not found');
      } else {
        throw NetworkException('Failed to delete recording: ${response.statusCode}');
      }
    } on UnauthorizedException {
      rethrow;
    } on DataNotFoundException {
      rethrow;
    } catch (e) {
      Logger.error('Delete recording error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to delete recording: $e');
    }
  }

  // ===== Video Operations =====

  @override
  Future<String> uploadVideo(
    String accessToken,
    String userId,
    String filePath,
    Map<String, dynamic> metadata, {
    void Function(int, int)? onProgress,
  }) async {
    try {
      Logger.debug('Uploading video: $filePath', tag: 'RemoteDataSource');
      Logger.warning(
        'Video upload not fully implemented in RemoteDataSourceImpl',
        tag: 'RemoteDataSource',
      );
      throw NotImplementedException('Video upload requires file streaming');
    } catch (e) {
      Logger.error('Upload video error: $e', tag: 'RemoteDataSource');
      throw NetworkException('Failed to upload video: $e');
    }
  }

  // ===== Health Check =====

  @override
  Future<bool> healthCheck() async {
    try {
      Logger.debug('Performing health check', tag: 'RemoteDataSource');
      logHttpRequest('GET', '$_baseUrl/health', {});

      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw NetworkException('Health check timed out'),
      );

      logHttpResponse(response.statusCode, response.body);

      final isHealthy = response.statusCode == 200;
      Logger.info(
        'Health check: ${isHealthy ? 'OK' : 'FAILED'}',
        tag: 'RemoteDataSource',
      );
      return isHealthy;
    } catch (e) {
      Logger.warning('Health check failed: $e', tag: 'RemoteDataSource');
      return false;
    }
  }

  // ===== Helper Methods =====

  void logHttpRequest(String method, String url, Map<String, dynamic> body) {
    Logger.debug(
      '$method $url',
      tag: 'RemoteDataSource.HTTP',
    );
    if (body.isNotEmpty) {
      Logger.debug(
        'Request body: ${jsonEncode(body)}',
        tag: 'RemoteDataSource.HTTP',
      );
    }
  }

  void logHttpResponse(int statusCode, String body) {
    Logger.debug(
      'Response status: $statusCode',
      tag: 'RemoteDataSource.HTTP',
    );
    if (body.isNotEmpty && body.length < 500) {
      Logger.debug(
        'Response body: $body',
        tag: 'RemoteDataSource.HTTP',
      );
    }
  }

  Future<dynamic> _getFile(String path) async {
    // This is a simplified placeholder
    // In production, use dart.io.File or similar
    throw UnimplementedError('File access not implemented');
  }
}
