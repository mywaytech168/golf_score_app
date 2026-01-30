import 'package:flutter/foundation.dart';
import 'swing_split_service.dart';
import 'swing_clip_upload_manager.dart';

/// 自動切分與上傳的整合服務
/// 
/// 職責：
/// 1. 執行視頻自動切分
/// 2. 將每個切片自動添加到上傳隊列
/// 3. 啟動上傳流程
/// 4. 提供統一的進度回調
class AutoSplitAndUploadService {
  final SwingClipUploadManager _uploadManager;

  /// 切分進度回調 (0.0-1.0)
  final ValueChanged<double>? onSplitProgress;

  /// 上傳進度回調 (0.0-1.0)
  final ValueChanged<double>? onUploadProgress;

  /// 狀態變化回調
  final ValueChanged<String>? onStatusChanged;

  /// 錯誤回調
  final ValueChanged<String>? onError;

  AutoSplitAndUploadService({
    required SwingClipUploadManager uploadManager,
    this.onSplitProgress,
    this.onUploadProgress,
    this.onStatusChanged,
    this.onError,
  }) : _uploadManager = uploadManager;

  /// 執行自動切分與上傳流程
  /// 
  /// 參數：
  /// - videoPath: 原始視頻路徑
  /// - imuCsvPath: IMU 數據 CSV 路徑
  /// - recordingId: 錄影 ID（用於關聯）
  /// - windowBeforeSec: 切分前的時間窗口（秒）
  /// - windowAfterSec: 切分後的時間窗口（秒）
  /// - threshG: 加速度閾值（G）
  /// 
  /// 返回：成功上傳的切片數量
  Future<int> executeAutoSplitAndUpload({
    required String videoPath,
    required String imuCsvPath,
    required String recordingId,
    double windowBeforeSec = 3.0,
    double windowAfterSec = 1.0,
    double threshG = 20.0,
    bool autoStartUpload = true,
  }) async {
    try {
      _updateStatus('開始自動切分...');

      // 步驟1：執行視頻自動切分
      debugPrint('🎬 開始切分視頻');
      final results = await SwingSplitService.split(
        videoPath: videoPath,
        imuCsvPath: imuCsvPath,
        windowBeforeSec: windowBeforeSec,
        windowAfterSec: windowAfterSec,
        threshG: threshG,
      );

      debugPrint('✅ 切分完成，找到 ${results.length} 個擊棒');
      _updateProgress(onSplitProgress, 1.0);

      if (results.isEmpty) {
        _updateStatus('未檢測到擊棒');
        return 0;
      }

      // 步驟2：將每個切片添加到上傳隊列
      _updateStatus('準備上傳隊列...');
      await _addClipsToQueue(recordingId, results);

      _updateStatus('隊列已準備，共 ${results.length} 個切片');

      // 步驟3：自動啟動上傳（可選）
      if (autoStartUpload) {
        _updateStatus('開始自動上傳...');
        await _uploadManager.startProcessing();
        _updateStatus('上傳中...');
      }

      return results.length;
    } catch (e) {
      final errorMsg = '自動切分上傳失敗: $e';
      debugPrint('❌ $errorMsg');
      _updateError(errorMsg);
      rethrow;
    }
  }

  /// 將切分結果添加到上傳隊列
  Future<void> _addClipsToQueue(
    String recordingId,
    List<SwingClipResult> results,
  ) async {
    final clips = <Map<String, dynamic>>[];

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final tag = result.tag.isNotEmpty
          ? result.tag
          : 'swing_${i + 1}';

      clips.add({
        'videoPath': result.videoPath,
        'csvPath': result.csvPath,
        'metadata': {
          'tag': tag,
          'hitSecond': result.hitSecond,
          'startSecond': result.startSecond,
          'endSecond': result.endSecond,
          'peakValue': result.peakValue,
          'goodShot': result.goodShot,
          'badShot': result.badShot,
          'maxAcceleration': result.maxAcceleration,
          'avgAcceleration': result.avgAcceleration,
        },
      });

      debugPrint(
        '📝 隊列項 ${i + 1}/${results.length}: '
        '${result.tag} @ ${result.hitSecond.toStringAsFixed(2)}s '
        '(${result.goodShot ? "✓" : result.badShot ? "✗" : "⚠"})',
      );
    }

    _uploadManager.addClipsToQueue(
      recordingId: recordingId,
      clips: clips,
    );

    debugPrint('✅ 所有 ${clips.length} 個切片已添加到隊列');
  }

  /// 取得上傳管理器統計信息
  Map<String, dynamic> getUploadStatistics() {
    return _uploadManager.getStatistics();
  }

  /// 暫停上傳
  void pauseUpload() {
    _uploadManager.pauseProcessing();
    _updateStatus('上傳已暫停');
  }

  /// 繼續上傳
  Future<void> resumeUpload() async {
    await _uploadManager.resumeProcessing();
    _updateStatus('上傳已繼續');
  }

  /// 取消所有
  void cancelAll() {
    _uploadManager.cancelAll();
    _updateStatus('已取消所有上傳');
  }

  /// 私有方法：更新狀態
  void _updateStatus(String status) {
    debugPrint('📢 狀態: $status');
    onStatusChanged?.call(status);
  }

  /// 私有方法：更新進度
  void _updateProgress(ValueChanged<double>? callback, double progress) {
    callback?.call(progress.clamp(0.0, 1.0));
  }

  /// 私有方法：報告錯誤
  void _updateError(String error) {
    debugPrint('❌ 錯誤: $error');
    onError?.call(error);
  }
}
