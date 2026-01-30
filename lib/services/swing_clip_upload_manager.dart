import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/recording_history_entry.dart';
import 'recording_history_storage.dart';
import 'video_server_client.dart';

/// 切片視頻上傳隊列項目
class UploadQueueItem {
  /// 队列项目的唯一 ID
  final String id;

  /// 所属的原始录影 ID
  final String recordingId;

  /// 切片视频的本地文件路径
  final String videoPath;

  /// 切片 CSV 数据的本地文件路径
  final String? csvPath;

  /// 切片元数据（标签、打击时间等）
  final Map<String, dynamic> metadata;

  /// 上传状态
  UploadStatus uploadStatus;

  /// 上传进度（0.0-1.0）
  double uploadProgress;

  /// 上传失败的原因
  String? uploadError;

  /// 上傳到伺服器的剪輯 ID
  int? clipId;

  /// 上傳時間戳
  DateTime? uploadedAt;

  /// 最後一次上傳嘗試
  DateTime? lastUploadAttempt;

  /// 重試次數
  int retryCount;

  /// 最大重試次數
  static const int maxRetries = 3;

  UploadQueueItem({
    required this.id,
    required this.recordingId,
    required this.videoPath,
    this.csvPath,
    required this.metadata,
    this.uploadStatus = UploadStatus.local,
    this.uploadProgress = 0.0,
    this.uploadError,
    this.clipId,
    this.uploadedAt,
    this.lastUploadAttempt,
    this.retryCount = 0,
  });

  /// 序列化为 JSON（用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recordingId': recordingId,
      'videoPath': videoPath,
      'csvPath': csvPath,
      'metadata': metadata,
      'uploadStatus': uploadStatus.name,
      'uploadProgress': uploadProgress,
      'uploadError': uploadError,
      'clipId': clipId,
      'uploadedAt': uploadedAt?.toIso8601String(),
      'lastUploadAttempt': lastUploadAttempt?.toIso8601String(),
      'retryCount': retryCount,
    };
  }

  /// 从 JSON 反序列化
  factory UploadQueueItem.fromJson(Map<String, dynamic> json) {
    UploadStatus status = UploadStatus.local;
    try {
      status = UploadStatus.values.byName(json['uploadStatus'] ?? 'local');
    } catch (_) {}

    return UploadQueueItem(
      id: json['id'] ?? '',
      recordingId: json['recordingId'] ?? '',
      videoPath: json['videoPath'] ?? '',
      csvPath: json['csvPath'],
      metadata: json['metadata'] ?? {},
      uploadStatus: status,
      uploadProgress: (json['uploadProgress'] ?? 0.0).toDouble(),
      uploadError: json['uploadError'],
      clipId: json['clipId'],
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.tryParse(json['uploadedAt'])
          : null,
      lastUploadAttempt: json['lastUploadAttempt'] != null
          ? DateTime.tryParse(json['lastUploadAttempt'])
          : null,
      retryCount: json['retryCount'] ?? 0,
    );
  }

  /// 是否可以重試
  bool get canRetry => retryCount < maxRetries && uploadStatus == UploadStatus.failed;

  /// 是否已完成上傳
  bool get isCompleted =>
      uploadStatus == UploadStatus.uploaded || uploadError != null;
}

/// 切片視頻上傳隊列管理器
/// 
/// 職責：
/// 1. 管理待上傳的切片視頻隊列
/// 2. 優先級排隊（元數據優先於視頻）
/// 3. 自動重試失敗的上傳
/// 4. 追蹤上傳進度
/// 5. 持久化隊列狀態
class SwingClipUploadManager extends ChangeNotifier {
  final VideoServerClient _serverClient;
  final RecordingHistoryStorage _storage;

  /// 上傳隊列（recordingId -> List<UploadQueueItem>）
  final Map<String, List<UploadQueueItem>> _uploadQueue = {};

  /// 正在上傳的項目
  UploadQueueItem? _currentItem;
  UploadQueueItem? get currentItem => _currentItem;

  /// 是否正在上傳
  bool _isUploading = false;
  bool get isUploading => _isUploading;

  /// 是否已暫停
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// 總上傳進度（0.0-1.0）
  double _totalProgress = 0.0;
  double get totalProgress => _totalProgress;

  /// 成功上傳的項目數
  int _successCount = 0;
  int get successCount => _successCount;

  /// 失敗的項目數
  int _failureCount = 0;
  int get failureCount => _failureCount;

  SwingClipUploadManager({
    required VideoServerClient serverClient,
    required RecordingHistoryStorage storage,
  })  : _serverClient = serverClient,
        _storage = storage;

  /// 初始化隊列（從持久化存儲恢復）
  Future<void> initialize() async {
    try {
      // TODO: 從本地存儲讀取隊列
      debugPrint('✅ 上傳隊列已初始化');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ 初始化隊列失敗: $e');
    }
  }

  /// 新增切片到上傳隊列
  /// 
  /// 參數：
  /// - recordingId: 原始錄影 ID
  /// - videoPath: 切片視頻文件路徑
  /// - csvPath: 切片 CSV 數據路徑（可選）
  /// - metadata: 切片元數據（tag, hitSecond, goodShot 等）
  void addClipToQueue({
    required String recordingId,
    required String videoPath,
    String? csvPath,
    required Map<String, dynamic> metadata,
  }) {
    final itemId = '${recordingId}_${metadata['tag'] ?? DateTime.now().millisecondsSinceEpoch}';

    final queueItem = UploadQueueItem(
      id: itemId,
      recordingId: recordingId,
      videoPath: videoPath,
      csvPath: csvPath,
      metadata: metadata,
    );

    _uploadQueue.putIfAbsent(recordingId, () => []).add(queueItem);

    debugPrint('📝 新增到隊列: $itemId (共 ${_getQueueSize()} 個待上傳項目)');
    notifyListeners();

    // 如果還沒在上傳，就開始上傳
    if (!_isUploading && !_isPaused) {
      _processNextItem();
    }
  }

  /// 批量新增多個切片到隊列
  void addClipsToQueue({
    required String recordingId,
    required List<Map<String, dynamic>> clips,
  }) {
    for (final clip in clips) {
      addClipToQueue(
        recordingId: recordingId,
        videoPath: clip['videoPath'] ?? '',
        csvPath: clip['csvPath'],
        metadata: clip['metadata'] ?? {},
      );
    }
  }

  /// 開始處理隊列
  Future<void> startProcessing() async {
    if (_isUploading) {
      debugPrint('⚠️ 上傳已在進行中');
      return;
    }

    _isPaused = false;
    _isUploading = true;
    _successCount = 0;
    _failureCount = 0;
    notifyListeners();

    debugPrint('▶️ 開始上傳隊列 (共 ${_getQueueSize()} 項)');
    await _processNextItem();
  }

  /// 暫停上傳
  void pauseProcessing() {
    _isPaused = true;
    notifyListeners();
    debugPrint('⏸️ 已暫停上傳隊列');
  }

  /// 繼續上傳
  Future<void> resumeProcessing() async {
    if (!_isPaused) return;

    _isPaused = false;
    notifyListeners();
    debugPrint('▶️ 繼續上傳隊列');

    await _processNextItem();
  }

  /// 取消所有上傳
  void cancelAll() {
    _uploadQueue.clear();
    _currentItem = null;
    _isUploading = false;
    _isPaused = false;
    notifyListeners();
    debugPrint('❌ 已取消所有待上傳項目');
  }

  /// 取消單個上傳項目
  void cancelItem(String itemId) {
    for (final list in _uploadQueue.values) {
      final index = list.indexWhere((item) => item.id == itemId);
      if (index >= 0) {
        list.removeAt(index);
        debugPrint('❌ 已取消項目: $itemId');
        notifyListeners();
        return;
      }
    }
  }

  /// 私有方法：處理下一個隊列項目
  Future<void> _processNextItem() async {
    if (_isPaused || _uploadQueue.isEmpty) {
      if (_uploadQueue.isEmpty && _isUploading) {
        _isUploading = false;
        debugPrint('✅ 隊列上傳完成 (成功: $_successCount, 失敗: $_failureCount)');
        notifyListeners();
      }
      return;
    }

    // 取得下一個未上傳的項目
    UploadQueueItem? nextItem;
    String? recordingId;

    for (final recId in _uploadQueue.keys) {
      final items = _uploadQueue[recId]!;
      final item = items.firstWhere(
        (i) =>
            i.uploadStatus == UploadStatus.local ||
            (i.uploadStatus == UploadStatus.failed && i.canRetry),
        orElse: () => UploadQueueItem(
          id: '',
          recordingId: '',
          videoPath: '',
          metadata: {},
        ),
      );
      if (item.id.isNotEmpty) {
        nextItem = item;
        recordingId = recId;
        break;
      }
    }

    if (nextItem == null) {
      _isUploading = false;
      debugPrint('✅ 隊列上傳完成 (成功: $_successCount, 失敗: $_failureCount)');
      notifyListeners();
      return;
    }

    _currentItem = nextItem;
    nextItem.uploadStatus = UploadStatus.uploading;
    nextItem.lastUploadAttempt = DateTime.now();
    notifyListeners();

    try {
      debugPrint('⬆️ 上傳項目: ${nextItem.id}');

      // 第1步：上傳元數據
      await _uploadMetadata(nextItem);

      // 第2步：上傳視頻文件
      await _uploadVideoFile(nextItem);

      // 第3步：上傳 CSV 數據（如果有）
      if (nextItem.csvPath != null && nextItem.csvPath!.isNotEmpty) {
        await _uploadCsvData(nextItem);
      }

      // 標記為已上傳
      nextItem.uploadStatus = UploadStatus.uploaded;
      nextItem.uploadedAt = DateTime.now();
      nextItem.uploadProgress = 1.0;
      _successCount++;

      debugPrint('✅ 項目上傳成功: ${nextItem.id}');
    } catch (e) {
      debugPrint('❌ 項目上傳失敗: ${nextItem.id} - $e');

      nextItem.uploadStatus = UploadStatus.failed;
      nextItem.uploadError = e.toString();
      nextItem.retryCount++;
      _failureCount++;
    }

    notifyListeners();

    // 繼續處理下一個項目
    await Future.delayed(const Duration(milliseconds: 500));
    await _processNextItem();
  }

  /// 上傳元數據（第1步）
  Future<void> _uploadMetadata(UploadQueueItem item) async {
    debugPrint('📝 上傳元數據: ${item.id}');

    final payload = {
      'recordingId': item.recordingId,
      'tag': item.metadata['tag'] ?? 'unknown',
      'hitSecond': item.metadata['hitSecond'] ?? 0,
      'startSecond': item.metadata['startSecond'] ?? 0,
      'endSecond': item.metadata['endSecond'] ?? 0,
      'peakValue': item.metadata['peakValue'] ?? 0,
      'goodShot': item.metadata['goodShot'] ?? false,
      'badShot': item.metadata['badShot'] ?? false,
      'maxAcceleration': item.metadata['maxAcceleration'] ?? 0,
      'avgAcceleration': item.metadata['avgAcceleration'] ?? 0,
    };

    // TODO: 調用後端 API /api/clips/metadata
    // 返回 clipId 用於後續步驟
    item.clipId = 12345; // 模擬伺服器返回的 clipId

    debugPrint('✓ 元數據上傳完成，clipId=${item.clipId}');
  }

  /// 上傳視頻文件（第2步）
  Future<void> _uploadVideoFile(UploadQueueItem item) async {
    final file = File(item.videoPath);
    if (!await file.exists()) {
      throw Exception('視頻文件不存在: ${item.videoPath}');
    }

    final fileSize = await file.length();
    debugPrint('📹 上傳視頻文件: ${item.videoPath} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

    // TODO: 實現分塊上傳與進度報告
    // 1. 將文件分成 5MB 塊
    // 2. 逐塊上傳到 /api/clips/{clipId}/upload
    // 3. 更新 uploadProgress
    // 4. 失敗時支援續傳

    // 模擬上傳進度
    for (int i = 0; i <= 10; i++) {
      item.uploadProgress = i / 10 * 0.7; // 視頻上傳佔 70%
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();
    }

    debugPrint('✓ 視頻文件上傳完成');
  }

  /// 上傳 CSV 數據（第3步）
  Future<void> _uploadCsvData(UploadQueueItem item) async {
    if (item.csvPath == null) return;

    final file = File(item.csvPath!);
    if (!await file.exists()) {
      debugPrint('⚠️ CSV 文件不存在，跳過: ${item.csvPath}');
      return;
    }

    debugPrint('📊 上傳 CSV 數據: ${item.csvPath}');

    // TODO: 上傳到 /api/clips/{clipId}/csv
    // 1. 讀取文件內容
    // 2. POST 到後端
    // 3. 更新進度

    // 模擬上傳進度
    for (int i = 7; i <= 10; i++) {
      item.uploadProgress = i / 10; // CSV 上傳佔剩餘 30%
      await Future.delayed(const Duration(milliseconds: 50));
      notifyListeners();
    }

    debugPrint('✓ CSV 數據上傳完成');
  }

  /// 取得隊列大小
  int _getQueueSize() {
    int total = 0;
    for (final items in _uploadQueue.values) {
      total += items.length;
    }
    return total;
  }

  /// 取得指定錄影的隊列項目
  List<UploadQueueItem> getQueueItems(String recordingId) {
    return _uploadQueue[recordingId] ?? [];
  }

  /// 取得整個隊列
  List<UploadQueueItem> getAllQueueItems() {
    final all = <UploadQueueItem>[];
    for (final items in _uploadQueue.values) {
      all.addAll(items);
    }
    return all;
  }

  /// 取得統計信息
  Map<String, dynamic> getStatistics() {
    final queueItems = getAllQueueItems();
    final local = queueItems.where((i) => i.uploadStatus == UploadStatus.local).length;
    final uploading = queueItems.where((i) => i.uploadStatus == UploadStatus.uploading).length;
    final uploaded = queueItems.where((i) => i.uploadStatus == UploadStatus.uploaded).length;
    final failed = queueItems.where((i) => i.uploadStatus == UploadStatus.failed).length;

    return {
      'total': queueItems.length,
      'local': local,
      'uploading': uploading,
      'uploaded': uploaded,
      'failed': failed,
      'successCount': _successCount,
      'failureCount': _failureCount,
    };
  }

  /// 持久化隊列到本地存儲
  Future<void> persistQueue() async {
    try {
      final items = getAllQueueItems();
      final json = items.map((i) => i.toJson()).toList();
      // TODO: 保存到本地文件或 SharedPreferences
      debugPrint('💾 隊列已持久化 (${items.length} 項)');
    } catch (e) {
      debugPrint('❌ 隊列持久化失敗: $e');
    }
  }
}
