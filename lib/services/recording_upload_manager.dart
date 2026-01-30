import 'package:flutter/foundation.dart';
import '../models/recording_history_entry.dart';
import 'recording_history_storage.dart';
import 'video_server_client.dart';

/// 管理錄影上傳的狀態與同步邏輯
/// 
/// 職責：
/// 1. 跟蹤本地錄影的上傳進度
/// 2. 自動重試失敗的上傳
/// 3. 更新本地 JSON 中的上傳狀態
/// 4. 通知上層 UI 狀態變化
class RecordingUploadManager extends ChangeNotifier {
  final RecordingHistoryStorage _storage;
  final VideoServerClient _serverClient;

  /// 當前各錄影的上傳狀態（filePath -> UploadStatus）
  final Map<String, UploadStatus> _uploadStates = {};

  /// 上傳進度（filePath -> 進度 0.0-1.0）
  final Map<String, double> _uploadProgress = {};

  /// 是否正在執行批量同步
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// 最後同步的時間
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  RecordingUploadManager({
    required RecordingHistoryStorage storage,
    required VideoServerClient serverClient,
  })  : _storage = storage,
        _serverClient = serverClient;

  /// 初始化上傳狀態（從儲存區讀取）
  Future<void> initialize() async {
    final entries = await _storage.loadHistory();
    for (final entry in entries) {
      _uploadStates[entry.filePath] = entry.uploadStatus;
    }
    notifyListeners();
  }

  /// 開始上傳單個錄影
  /// 
  /// 參數：
  /// - entry: 要上傳的錄影紀錄
  /// - onProgress: 上傳進度回呼（0.0-1.0）
  /// 
  /// 返回：成功則返回 serverId，失敗則返回 null
  Future<int?> uploadRecording(
    RecordingHistoryEntry entry, {
    ValueChanged<double>? onProgress,
  }) async {
    final filePath = entry.filePath;

    try {
      // 更新狀態為上傳中
      _updateUploadState(filePath, UploadStatus.uploading);

      debugPrint('⬆️ 開始上傳錄影: $filePath');

      // TODO: 實現實際上傳邏輯
      // 1. 讀取檔案
      // 2. 建立多部分表單請求
      // 3. 監聽上傳進度
      // 4. 發送到後端 API
      // 5. 接收 serverId

      // 模擬延遲
      await Future.delayed(const Duration(seconds: 2));

      // 模擬成功
      const serverId = 12345;

      // 更新本地紀錄
      final updatedEntry = entry.copyWith(
        uploadStatus: UploadStatus.uploaded,
        cloudVideoId: serverId,
        lastUploadAttempt: DateTime.now(),
      );

      await _storage.saveEntry(updatedEntry);
      _updateUploadState(filePath, UploadStatus.uploaded);

      debugPrint('✅ 上傳成功: $filePath -> serverId=$serverId');
      return serverId;
    } catch (e) {
      final errorMsg = e.toString();
      debugPrint('❌ 上傳失敗: $filePath - $errorMsg');

      // 更新本地紀錄
      final updatedEntry = entry.copyWith(
        uploadStatus: UploadStatus.failed,
        uploadError: errorMsg,
        lastUploadAttempt: DateTime.now(),
      );

      await _storage.saveEntry(updatedEntry);
      _updateUploadState(filePath, UploadStatus.failed);

      return null;
    }
  }

  /// 批量上傳所有本地錄影
  /// 
  /// 返回：成功上傳的錄影數量
  Future<int> syncAllLocal() async {
    if (_isSyncing) {
      debugPrint('⚠️ 同步已在進行中，跳過重複請求');
      return 0;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final entries = await _storage.loadHistory();
      final localEntries = entries
          .where((e) =>
              e.uploadStatus == UploadStatus.local ||
              e.uploadStatus == UploadStatus.failed)
          .toList();

      if (localEntries.isEmpty) {
        debugPrint('ℹ️ 沒有待上傳的錄影');
        return 0;
      }

      debugPrint('🔄 開始同步 ${localEntries.length} 個錄影...');

      int successCount = 0;
      for (final entry in localEntries) {
        final result = await uploadRecording(entry);
        if (result != null) {
          successCount++;
        }
      }

      _lastSyncTime = DateTime.now();
      debugPrint('✅ 同步完成，成功上傳 $successCount 個錄影');

      return successCount;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 重試失敗的上傳
  Future<int> retryFailedUploads() async {
    final entries = await _storage.loadHistory();
    final failedEntries =
        entries.where((e) => e.uploadStatus == UploadStatus.failed).toList();

    if (failedEntries.isEmpty) {
      return 0;
    }

    debugPrint('🔄 重試 ${failedEntries.length} 個失敗的上傳...');

    int successCount = 0;
    for (final entry in failedEntries) {
      final result = await uploadRecording(entry);
      if (result != null) {
        successCount++;
      }
    }

    return successCount;
  }

  /// 刪除本地錄影
  Future<void> deleteRecording(RecordingHistoryEntry entry) async {
    await _storage.removeEntry(entry.filePath);
    _uploadStates.remove(entry.filePath);
    notifyListeners();
    debugPrint('🗑️ 已刪除錄影: ${entry.filePath}');
  }

  /// 刪除已上傳的錄影（本地副本）
  Future<void> deleteCloudRecording(RecordingHistoryEntry entry) async {
    // TODO: 調用後端 API 刪除雲端副本
    await _storage.removeEntry(entry.filePath);
    _uploadStates.remove(entry.filePath);
    notifyListeners();
    debugPrint('☁️ 已刪除雲端錄影: ${entry.filePath}');
  }

  /// 取得單個錄影的上傳進度
  double getUploadProgress(String filePath) =>
      _uploadProgress[filePath] ?? 0.0;

  /// 取得單個錄影的上傳狀態
  UploadStatus? getUploadStatus(String filePath) =>
      _uploadStates[filePath];

  /// 更新上傳狀態
  void _updateUploadState(String filePath, UploadStatus status) {
    _uploadStates[filePath] = status;
    notifyListeners();
  }

  /// 更新上傳進度
  void _updateUploadProgress(String filePath, double progress) {
    _uploadProgress[filePath] = progress.clamp(0.0, 1.0);
    notifyListeners();
  }
}
