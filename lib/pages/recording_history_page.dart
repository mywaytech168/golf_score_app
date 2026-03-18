import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:video_player/video_player.dart';
// restored original local VideoPlayerPage usage
import '../models/recording_history_entry.dart';
import '../models/hits_summary.dart';
import 'external_video_importer_local.dart';
import '../services/recording_history_storage.dart';
import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import '../services/swing_split_service.dart';
import '../services/hits_summary_storage.dart';
import '../widgets/hits_summary_widget.dart';
import 'recording_session_page.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, editDuration, delete, split, upload, unbindCloud, rerunAnalysis }

/// 排序選項
enum _SortBy {
  /// 按時間排序（最新優先）
  date,
  /// 按最佳速度（峰值）排序（最高優先）
  peakValue,
  /// 按聲音清脆度排序（最高優先）
  audioCrispness;

  /// 中文標籤
  String get label {
    switch (this) {
      case _SortBy.date:
        return '時間';
      case _SortBy.peakValue:
        return '最佳速度';
      case _SortBy.audioCrispness:
        return '聲音清脆度';
    }
  }
}

/// 錄影歷史獨立頁面：集中顯示所有曾經錄影的檔案，供使用者重播或挑選外部影片
class RecordingHistoryPage extends StatefulWidget {
  final List<RecordingHistoryEntry> entries; // 外部帶入的歷史資料清單
  final String? userAvatarPath; // 使用者自訂頭像，方便進入播放頁時供分享覆蓋

  const RecordingHistoryPage({
    super.key,
    required this.entries,
    this.userAvatarPath,
  });

  @override
  State<RecordingHistoryPage> createState() => _RecordingHistoryPageState();
}

class _RecordingHistoryPageState extends State<RecordingHistoryPage> {
  late final List<RecordingHistoryEntry> _entries =
      List<RecordingHistoryEntry>.from(widget.entries); // 本地複製一份資料避免直接修改來源
  bool _rebuildScheduled = false; // 避免重複排程 setState 造成框架錯誤
  final ExternalVideoImporter _videoImporter = const ExternalVideoImporter(); // 外部影片匯入工具
  bool _isLoadingCloudList = false; // 標記是否正在載入雲端列表
  Timer? _syncTimer; // 定時器，每 5 秒更新一次列表
  bool? _selectedGoodShot; // 好球/壞球篩選 - null: 全部, true: 好球, false: 壞球
  _SortBy _sortBy = _SortBy.date; // 排序選項，預設按時間排序

  @override
  void initState() {
    super.initState();
    // 初始化時從雲端同步錄影列表
    _syncWithCloudEntries();
    
    // 設置定時器，每 5 秒更新一次列表
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _syncWithCloudEntries();
    });
  }

  @override
  void dispose() {
    // 清理定時器
    _syncTimer?.cancel();
    super.dispose();
  }

  /// 從雲端同步錄影列表，與本地進行去重
  Future<void> _syncWithCloudEntries() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingCloudList = true;
    });
    
    try {
      debugPrint('[歷史頁] 開始從雲端同步錄影列表...');
      
      // 檢查是否已登入
      final isLoggedIn = await AuthTokenStorage.instance.isLoggedIn();
      if (!isLoggedIn) {
        debugPrint('[歷史頁] 未登入，跳過雲端同步');
        setState(() {
          _isLoadingCloudList = false;
        });
        return;
      }
      
      // 從 API 獲取雲端列表
      final serverClient = VideoServerClient();
      final cloudListResponse = await serverClient.getVideos(limit: 100); // 獲取最多 100 個視頻
      
      if (!cloudListResponse['success']) {
        final error = cloudListResponse['error'] ?? '未知錯誤';
        debugPrint('[歷史頁] ⚠️ 獲取雲端列表失敗: $error');
        
        // 如果是 401 未授權，返回登入頁
        if (error.contains('401') || error.contains('未授權')) {
          debugPrint('[歷史頁] 🔐 檢測到 401 未授權，跳轉到登入頁');
          
          if (mounted) {
            await AuthTokenStorage.instance.clearTokens();
            Navigator.of(context).pushReplacementNamed('/login');
          }
          return;
        }
        
        setState(() {
          _isLoadingCloudList = false;
        });
        return;
      }
      
      // 解析雲端視頻列表
      // API 可能返回不同格式：直接數組或分頁對象
      List<dynamic> cloudVideos = [];
      final responseData = cloudListResponse['data'];
      
      if (responseData is List) {
        cloudVideos = responseData;
      } else if (responseData is Map) {
        // 嘗試從常見的分頁字段提取數據
        if (responseData['videos'] != null && responseData['videos'] is List) {
          cloudVideos = responseData['videos'];
        } else if (responseData['items'] != null && responseData['items'] is List) {
          cloudVideos = responseData['items'];
        } else if (responseData['data'] != null && responseData['data'] is List) {
          cloudVideos = responseData['data'];
        } else {
          debugPrint('[歷史頁] ⚠️ 無法從雲端數據中提取視頻列表: $responseData');
          cloudVideos = [];
        }
      }
      
      debugPrint('[歷史頁] ✅ 從雲端獲取 ${cloudVideos.length} 個視頻');
      
      // 與本地列表進行比對去重
      _mergeCloudAndLocalEntries(cloudVideos);
      
      if (mounted) {
        setState(() {
          _isLoadingCloudList = false;
        });
      }
      
      debugPrint('[歷史頁] ✅ 雲端同步完成');
    } catch (e) {
      debugPrint('[歷史頁] ❌ 同步失敗: $e');
      if (mounted) {
        setState(() {
          _isLoadingCloudList = false;
        });
      }
    }
  }

  /// 將雲端列表與本地列表進行合併去重
  /// 策略：如果本地有對應的視頻，則更新為雲端綁定狀態，並根據 mainFileType 判斷視頻類型
  Future<void> _mergeCloudAndLocalEntries(List<dynamic> cloudVideos) async {
    debugPrint('[歷史頁] 開始合併雲端和本地列表...');
    
    // 構建雲端視頻的映射（使用視頻 ID 作為鍵 - 仅用於精確匹配）
    final Map<String, dynamic> cloudVideoMap = {};
    final Set<String> cloudVideoIds = {};
    
    for (final video in cloudVideos) {
      final videoId = video['id']?.toString();
      final videoName = video['name']?.toString();
      final mainFileType = video['mainFileType']?.toString() ?? 'original';
      final queueStatus = video['queueStatus'] as Map<String, dynamic>?;
      
      debugPrint('[歷史頁] 雲端視頻: ID=$videoId, Name=$videoName, MainFileType=$mainFileType');
      if (queueStatus != null) {
        final status = queueStatus['latestStatus']?.toString() ?? 'notStarted';
        debugPrint('[歷史頁]   - 處理狀態: $status');
      }
      
      // 僅使用 ID 作為鍵，不添加名稱鍵（禁用名稱匹配）
      if (videoId != null) {
        cloudVideoMap[videoId] = video;
        cloudVideoIds.add(videoId);
      }
    }
    
    debugPrint('[歷史頁] 雲端視頻映射: ${cloudVideoMap.keys.toList()}');
    
    // 遍歷本地列表，使用 cloudVideoId 精確匹配雲端視頻
    int matchedCount = 0;
    final Set<String> matchedCloudIds = {};
    
    for (int i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final localFileName = entry.displayTitle;
      
      // 使用 cloudVideoId 精確匹配雲端視頻 - 不進行名稱模糊匹配
      if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
        if (cloudVideoMap.containsKey(entry.cloudVideoId)) {
          final cloudVideo = cloudVideoMap[entry.cloudVideoId] as Map<String, dynamic>;
          
          debugPrint('[歷史頁] ✓ 本地視頻 \"$localFileName\" 已有雲端綁定: ${entry.cloudVideoId}');
          matchedCloudIds.add(entry.cloudVideoId!);
          
          // 提取處理隊列狀態
          ProcessingStatus newProcessingStatus = entry.processingStatus;
          final queueStatus = cloudVideo['queueStatus'] as Map<String, dynamic>?;
          if (queueStatus != null) {
            final latestStatus = queueStatus['status']?.toString() ?? 'notStarted';
            newProcessingStatus = ProcessingStatus.fromString(latestStatus);
            debugPrint('[歷史頁]   - 更新處理狀態: $latestStatus');
          }
          
          // 已綁定的本地影片保持原有的 videoType，不要根據後端的 mainFileType 改變
          // 只更新 syncStatus 和 processingStatus，保證數據一致性
          if (entry.syncStatus != SyncStatus.synced || entry.processingStatus != newProcessingStatus) {
            _entries[i] = _entries[i].copyWith(
              syncStatus: SyncStatus.synced,
              processingStatus: newProcessingStatus,
            );
          }
          
          if (cloudVideo['goodShot'] != null) {
            _entries[i] = _entries[i].copyWith(
              goodShot: cloudVideo['goodShot']
            );
          }
          
          matchedCount++;
        } else {
          debugPrint('[歷史頁] ✗ 本地視頻 \"$localFileName\" 的雲端綁定 ID 不存在: ${entry.cloudVideoId}');
        }
      }
    }
    
    // 添加沒有本地匹配的雲端視頻到列表
    int unmatchedCount = 0;
    for (final videoId in cloudVideoIds) {
      if (!matchedCloudIds.contains(videoId)) {
        final cloudVideo = cloudVideoMap[videoId] as Map<String, dynamic>;
        final videoName = cloudVideo['name']?.toString() ?? 'Unknown';
        final mainFileType = cloudVideo['mainFileType']?.toString() ?? 'original';
        final queueStatus = cloudVideo['queueStatus'] as Map<String, dynamic>?;
        
        debugPrint('[歷史頁] 添加未匹配的雲端視頻: ID=$videoId, Name=$videoName');
        
        // 根據 mainFileType 判定 videoType
        VideoType videoType = VideoType.cloudOriginal;
        if (mainFileType == 'clip') {
          videoType = VideoType.cloudClip;
        }
        
        // 提取處理狀態
        ProcessingStatus processingStatus = ProcessingStatus.notStarted;
        if (queueStatus != null) {
          final status = queueStatus['status']?.toString() ?? 'notStarted';
          processingStatus = ProcessingStatus.fromString(status);
        }
        
        // 提取音頻分析數據
        double? audioCrispness;
        bool? goodShot;
        if (cloudVideo['audioCrispness'] != null) {
          audioCrispness = (cloudVideo['audioCrispness'] as num?)?.toDouble();
        }
        if (cloudVideo['goodShot'] != null) {
          goodShot = cloudVideo['goodShot'] as bool?;
        }
        
        // 創建新的條目
        final newEntry = RecordingHistoryEntry(
          filePath: '', // 雲端視頻沒有本地路徑
          roundIndex: 0,
          recordedAt: DateTime.now(),
          durationSeconds: 0,
          imuConnected: false,
          customName: videoName,
          imuCsvPaths: {},
          thumbnailPath: null,
          uploadStatus: UploadStatus.uploaded,
          cloudVideoId: videoId,
          uploadError: null,
          lastUploadAttempt: null,
          videoType: videoType,
          syncStatus: SyncStatus.synced,
          processingStatus: processingStatus,
          processingSuccess: null,
          mainFileType: mainFileType,
          isClipped: videoType == VideoType.cloudClip,
          peakValues: {},
          audioCrispness: audioCrispness,
          goodShot: goodShot,
        );
        
        _entries.add(newEntry);
        unmatchedCount++;
      }
    }
    
    debugPrint('[歷史頁] 合併完成: 共匹配 $matchedCount 個雲端視頻，添加 $unmatchedCount 個未匹配的雲端視頻');
    
    // 保存更新後的本地列表
    await RecordingHistoryStorage.instance.saveHistory(_entries);
  }

  /// 返回上一頁並帶出更新後的清單
  void _finishWithResult() {
    Navigator.of(context).pop(List<RecordingHistoryEntry>.from(_entries));
  }

  /// 根據視頻檔案路徑獲取對應的縮略圖路徑
  /// 例如：/path/REC_20260129100658.mp4 -> /path/REC_20260129100658.jpg
  String _getThumbnailPath(String videoFilePath) {
    final withoutExtension = videoFilePath.replaceFirst(RegExp(r'\.[^.]*$'), '');
    return '$withoutExtension.jpg';
  }

  /// 獲取視頻的時長（秒數）
  Future<int> _getVideoDuration(String videoPath) async {
    try {
      debugPrint('[歷史頁] 正在獲取視頻時長: $videoPath');
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration.inSeconds;
      await controller.dispose();
      debugPrint('[歷史頁] ✅ 視頻時長: $duration 秒');
      return duration;
    } catch (e) {
      debugPrint('[歷史頁] ⚠️ 獲取視頻時長失敗: $e，使用預設值 0');
      return 0;
    }
  }

  /// 計算 CSV 中各軌跡的峰值（加速度幅度最大值）
  /// 返回 Map<String, double>，鍵為軌跡標籤（如 'chest', 'right_wrist'），值為該軌跡的峰值
  Future<Map<String, double>> _calculatePeakValues(Map<String, String> imuCsvPaths) async {
    final peakValues = <String, double>{};
    
    for (final entry in imuCsvPaths.entries) {
      final label = entry.key; // 'chest' 或 'right_wrist'
      final csvPath = entry.value;
      
      try {
        final file = File(csvPath);
        if (!await file.exists()) {
          debugPrint('[歷史頁] ⚠️ CSV 檔案不存在: $csvPath');
          continue;
        }

        debugPrint('[歷史頁] 正在分析 $label 軌跡: $csvPath');
        
        // 讀取 CSV 檔案
        final lines = await file.readAsLines();
        
        // 尋找表頭行（包含 ElapsedSec, AccelX, AccelY, AccelZ）
        int headerIdx = -1;
        List<String> headers = [];
        for (int i = 0; i < lines.length && i < 100; i++) {
          final line = lines[i].trim();
          if (line.contains('ElapsedSec') && line.contains('AccelX') && 
              line.contains('AccelY') && line.contains('AccelZ')) {
            headerIdx = i;
            headers = line.split(',');
            break;
          }
        }

        if (headerIdx == -1) {
          debugPrint('[歷史頁] ⚠️ 無法找到 CSV 表頭，跳過 $label');
          continue;
        }

        final idxAx = headers.indexOf('AccelX');
        final idxAy = headers.indexOf('AccelY');
        final idxAz = headers.indexOf('AccelZ');

        if (idxAx < 0 || idxAy < 0 || idxAz < 0) {
          debugPrint('[歷史頁] ⚠️ 無法找到加速度欄位，跳過 $label');
          continue;
        }

        // 計算加速度幅度的最大值
        double maxAcceleration = 0;
        for (int i = headerIdx + 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || line.startsWith('Device:') || line.startsWith('Quat')) {
            continue;
          }

          final parts = line.split(',');
          final maxIdx = math.max(idxAx, math.max(idxAy, idxAz));
          if (parts.length <= maxIdx) {
            continue;
          }

          final ax = double.tryParse(parts[idxAx]) ?? 0;
          final ay = double.tryParse(parts[idxAy]) ?? 0;
          final az = double.tryParse(parts[idxAz]) ?? 0;
          
          // 計算加速度幅度: sqrt(Ax^2 + Ay^2 + Az^2)
          final magnitude = math.sqrt(ax * ax + ay * ay + az * az);
          
          if (magnitude > maxAcceleration) {
            maxAcceleration = magnitude;
          }
        }

        peakValues[label] = maxAcceleration;
        debugPrint('[歷史頁] 📊 $label 峰值: ${maxAcceleration.toStringAsFixed(2)} G');
      } catch (e) {
        debugPrint('[歷史頁] ❌ 計算 $label 峰值失敗: $e');
      }
    }

    return peakValues;
  }

  /// 為指定的視頻生成縮略圖
  /// 使用 VideoThumbnail 套件從視頻的第一幀提取縮略圖
  Future<String?> _generateThumbnailForVideo(String videoPath) async {
    try {
      debugPrint('[歷史頁] 正在為 $videoPath 生成縮略圖...');
      final targetPath = _getThumbnailPath(videoPath);
      
      // 使用 video_thumbnail 套件生成縮略圖
      // 如果套件可用，會生成 JPEG 縮略圖；否則返回 null
      final thumb = await vt.VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: vt.ImageFormat.JPEG,
        timeMs: 0, // 從第 0 毫秒處提取
        quality: 75,
        thumbnailPath: targetPath,
      );
      
      if (thumb != null && thumb.isNotEmpty) {
        debugPrint('[歷史頁] ✅ 縮略圖成功生成: $targetPath');
        return targetPath;
      } else {
        debugPrint('[歷史頁] ⚠️ 縮略圖生成失敗: $videoPath');
        return null;
      }
    } catch (e) {
      debugPrint('[歷史頁] ❌ 生成縮略圖時發生錯誤: $e');
      return null;
    }
  }

  /// 移除指定紀錄並同步刪除實體檔案
  Future<void> _deleteEntry(RecordingHistoryEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('刪除影片'),
          content: Text('確定要刪除「${entry.displayTitle}」嗎？影片與 CSV 將會一併移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('刪除'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final index = _entries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (index == -1) {
      return; // 找不到對應項目時直接結束
    }

    // 根據視頻類型決定是否調用 API 標記為 delete
    bool shouldDeleteDirectly = true; // 是否應該直接刪除

    if (entry.videoType == VideoType.cloudClip) {
      // 雲端切片：直接標記為 delete
      debugPrint('[歷史頁] 雲端切片刪除，將標記雲端狀態為 delete');
      shouldDeleteDirectly = false;
      
      if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
        try {
          final client = VideoServerClient();
          await client.markVideoAsDeleted(entry.cloudVideoId!);
          debugPrint('[歷史頁] ✓ 已標記雲端視頻為 delete: ${entry.cloudVideoId}');
        } catch (e) {
          debugPrint('[歷史頁] ⚠️ 標記雲端視頻失敗: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('標記雲端視頻失敗: $e')),
            );
          }
          return;
        }
      }
    } else if (entry.videoType == VideoType.localClip) {
      // 本地切片
      if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
        // 有雲端綁定：標記為 delete
        debugPrint('[歷史頁] 本地切片有雲端綁定，將標記雲端狀態為 delete');
        shouldDeleteDirectly = false;
        
        try {
          final client = VideoServerClient();
          await client.markVideoAsDeleted(entry.cloudVideoId!);
          debugPrint('[歷史頁] ✓ 已標記雲端視頻為 delete: ${entry.cloudVideoId}');
        } catch (e) {
          debugPrint('[歷史頁] ⚠️ 標記雲端視頻失敗: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('標記雲端視頻失敗: $e')),
            );
          }
          return;
        }
      } else {
        // 無雲端綁定：直接刪除
        debugPrint('[歷史頁] 本地切片無雲端綁定，直接刪除');
        shouldDeleteDirectly = true;
      }
    }

    // 移除本地檔案
    if (shouldDeleteDirectly) {
      await _removeEntryFiles(entry);
    }

    _entries.removeAt(index); // 先調整資料來源
    if (mounted) {
      debugPrint('[歷史頁] 刪除後立即刷新列表，剩餘 ${_entries.length} 筆');
      setState(() {}); // 通知畫面重新渲染
    }

    await RecordingHistoryStorage.instance.saveHistory(_entries);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已刪除 ${entry.fileName}')),
    );
  }


  /// 移除影片與雲端的綁定，將狀態重置為未同步
  Future<void> _unbindCloudVideo(RecordingHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認移除雲端綁定'),
        content: const Text('這將解除影片與雲端的連接，但不會刪除雲端檔案。解除後可以重新上傳為新的影片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移除綁定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final index = _entries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (index == -1) return;

    // 如果有 cloudVideoId，先呼叫後端 API 解除綁定
    if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
      try {
        final client = VideoServerClient();
        final success = await client.unbindVideo(entry.cloudVideoId!);
        
        // 如果失敗，仍然允許解除本地綁定（影片可能已在雲端刪除）
        if (!success) {
          debugPrint('[歷史頁] ⚠️ 雲端解除綁定失敗，但繼續本地解除綁定');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('雲端解除綁定失敗，但本地綁定已移除')),
            );
          }
        } else {
          debugPrint('[歷史頁] ✓ 雲端解除綁定成功');
        }
      } catch (e) {
        debugPrint('[歷史頁] ⚠️ 解除雲端綁定出錯: $e');
        // 出錯時也繼續本地解除（影片可能已刪除或無權限）
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('雲端已無法存取，本地綁定已移除')),
          );
        }
      }
    }

    // 更新條目：清除雲端相關資訊，重置為未同步狀態
    _entries[index] = _entries[index].copyWith(
      syncStatus: SyncStatus.notSynced,
      clearCloudVideoId: true,
    );

    await RecordingHistoryStorage.instance.saveHistory(_entries);
    
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移除 ${entry.displayTitle} 的雲端綁定')),
      );
    }
  }

  /// 重新分析影片 (Re-run Analysis)
  /// 呼叫後端 API 重新排隊分析該影片
  Future<void> _rerunAnalysisEntry(RecordingHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新分析影片'),
        content: Text('確定要重新分析「${entry.displayTitle}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('重新分析'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;

    // 顯示載入中的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在重新分析 ${entry.displayTitle}...')),
    );

    try {
      // 檢查影片是否已上傳到雲端
      if (entry.cloudVideoId == null || entry.cloudVideoId!.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('影片尚未上傳到雲端，請先上傳')),
        );
        return;
      }

      // 呼叫後端 API 重新分析
      final serverClient = VideoServerClient();
      final response = await serverClient.rerunAnalysis(entry.cloudVideoId!);

      if (!mounted) return;

      if (response['success'] ?? false) {
        debugPrint('[歷史頁] ✅ 重新分析已排隊');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已重新分析 ${entry.displayTitle}，請稍後查看結果')),
        );
      } else {
        final error = response['error'] ?? '未知錯誤';
        debugPrint('[歷史頁] ❌ 重新分析失敗：$error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新分析失敗：$error')),
        );
      }
    } catch (e) {
      debugPrint('[歷史頁] ❌ 重新分析異常：$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新分析失敗：$e')),
      );
    }
  }

  Future<void> _splitEntry(RecordingHistoryEntry entry) async {
    final String? csvPath = entry.imuCsvPaths.isNotEmpty
        ? entry.imuCsvPaths.values.first
        : null;
    if (csvPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到 IMU CSV，無法分片')));
      return;
    }
    final String outDir = p.join(p.dirname(entry.filePath), 'cut_${entry.roundIndex}');
    // 顯示簡易等待動畫，避免使用者誤以為卡住
    void hideLoading() {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('自動分片進行中，請稍候...'),
          ],
        ),
      ),
    );
    try {
      // 使用 split 獲取分割結果
      final results = await SwingSplitService.split(
        videoPath: entry.filePath,
        imuCsvPath: csvPath,
        outDirName: p.basename(outDir),
      );
      
      // 構建 hits_summary.csv 路徑（與 split 中 _writeSummary 的路徑保持一致）
      final hitsSummaryPath = results.isNotEmpty
          ? p.join(p.dirname(results.first.videoPath), 'hits_summary.csv')
          : p.join(outDir, 'hits_summary.csv');
      
      hideLoading();
      if (results.isNotEmpty) {
        final int baseIndex = _entries.isEmpty
            ? 1
            : (_entries.map((e) => e.roundIndex).reduce(math.max) + 1);
        final List<RecordingHistoryEntry> newEntries = [];
        for (int i = 0; i < results.length; i++) {
          final r = results[i];
          final duration = (r.endSecond - r.startSecond).round().clamp(0, 24 * 60 * 60);
          
          // 為切片生成縮圖
          final clipThumbnailPath = _getThumbnailPath(r.videoPath);
          
          // 計算切片的峰值
          final clipPeakValues = await _calculatePeakValues({'right_wrist': r.csvPath});
          
          newEntries.add(
            RecordingHistoryEntry(
              filePath: r.videoPath,
              roundIndex: baseIndex + i,
              recordedAt: DateTime.now(),
              durationSeconds: duration,
              imuConnected: true,
              customName: '${entry.displayTitle}_${r.tag}',
              imuCsvPaths: {'right_wrist': r.csvPath},
              thumbnailPath: clipThumbnailPath,
              cloudVideoId: null,
              isClipped: true,
              videoType: VideoType.localClip,
              peakValues: clipPeakValues.isNotEmpty ? clipPeakValues : null,
            ),
          );
        }
        _entries.insertAll(0, newEntries);
        await RecordingHistoryStorage.instance.saveHistory(_entries);
        if (mounted) {
          setState(() {});
        }
        
        // 為每個切片生成縮略圖
        debugPrint('[歷史頁] 開始為 ${newEntries.length} 個切片生成縮略圖');
        for (int i = 0; i < newEntries.length; i++) {
          final clipEntry = newEntries[i];
          debugPrint('[歷史頁] 正在為第 $i 個切片生成縮略圖: ${clipEntry.filePath}');
          
          // 實際生成縮略圖文件
          final generatedThumbnailPath = await _generateThumbnailForVideo(clipEntry.filePath);
          
          if (generatedThumbnailPath != null && generatedThumbnailPath.isNotEmpty) {
            // 更新本地記錄中的縮略圖路徑
            _entries[i] = _entries[i].copyWith(thumbnailPath: generatedThumbnailPath);
            debugPrint('[歷史頁] ✅ 第 $i 個切片的縮略圖已生成: $generatedThumbnailPath');
          } else {
            debugPrint('[歷史頁] ⚠️ 第 $i 個切片的縮略圖生成失敗');
          }
        }
        await RecordingHistoryStorage.instance.saveHistory(_entries);
        
        // 自動上傳每個切片
        debugPrint('[歷史頁] 開始自動上傳 ${newEntries.length} 個切片');
        for (final clipEntry in newEntries) {
          debugPrint('[歷史頁] 正在上傳切片: ${clipEntry.customName}');
          await _uploadEntry(clipEntry);
        }
        
        // 上傳 hits_summary 到原始視頻
        debugPrint('[歷史頁] 準備上傳摆球摘要到原始視頻');
        if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
          debugPrint('[歷史頁] 原始視頻 ID: ${entry.cloudVideoId}');
          try {
            final uploadResult = await VideoServerClient().uploadHitsSummary(
              videoId: entry.cloudVideoId!,
              hitsSummaryCsvPath: hitsSummaryPath,
            );
            
            if (uploadResult['success'] == true) {
              debugPrint('[歷史頁] ✅ 摆球摘要上傳成功到原始視頻');
            } else {
              debugPrint('[歷史頁] ⚠️ 摆球摘要上傳失敗: ${uploadResult['error']}');
            }
          } catch (e) {
            debugPrint('[歷史頁] ⚠️ 摆球摘要上傳異常: $e');
          }
        } else {
          debugPrint('[歷史頁] ℹ️ 原始視頻尚未上傳到雲端，摆球摘要將在視頻同步後再上傳');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分片完成：${results.length} 段')));
    } catch (e) {
      hideLoading();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分片失敗：$e')));
    }
  }

  /// 顯示輸入框調整秒數並更新記錄
  Future<void> _editEntryDuration(RecordingHistoryEntry entry) async {
    debugPrint('[歷史頁] 準備調整影片時長：${entry.fileName} 當前秒數=${entry.durationSeconds}');
    String tempValue = entry.durationSeconds.toString(); // 暫存輸入內容，避免控制器重複使用
    final formKey = GlobalKey<FormState>();
    final newDuration = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('調整影片時長'),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: TextFormField(
              initialValue: tempValue,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '秒數',
                helperText: '輸入影片實際秒數（正整數）',
              ),
              onChanged: (value) => tempValue = value,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                final parsed = int.tryParse(trimmed);
                if (parsed == null || parsed <= 0) {
                  return '請輸入大於 0 的秒數';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final isValid = formKey.currentState?.validate() ?? false;
                if (!isValid) {
                  return;
                }
                final parsed = int.parse(tempValue.trim());
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );

    if (!mounted || newDuration == null) {
      debugPrint('[歷史頁] 調整時長流程取消或頁面已卸載');
      return;
    }

    final index = _entries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (index == -1) {
      debugPrint('[歷史頁] 找不到對應紀錄，無法更新時長');
      return;
    }

    if (_entries[index].durationSeconds == newDuration) {
      debugPrint('[歷史頁] 秒數未變更（$newDuration 秒），略過更新');
      return; // 秒數未變更時略過更新
    }

    _entries[index] = _entries[index].copyWith(durationSeconds: newDuration);
    debugPrint('[歷史頁] 更新索引 $index 的時長為 $newDuration 秒，準備儲存');
    if (mounted) {
      debugPrint('[歷史頁] 調整秒數後重繪列表');
      _scheduleRebuild(); // 透過佇列化的排程避免與對話框動畫衝突
    }

    await RecordingHistoryStorage.instance.saveHistory(_entries);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已更新 ${entry.displayTitle} 為 $newDuration 秒')),
    );
  }

  /// 提供重新命名功能，讓使用者快速辨識影片
  Future<void> _renameEntry(RecordingHistoryEntry entry) async {
    final initialText = entry.customName != null && entry.customName!.trim().isNotEmpty
        ? entry.customName!.trim()
        : entry.displayTitle;
    debugPrint('[歷史頁] 準備重新命名影片：${entry.fileName} 初始名稱=$initialText');
    String tempName = initialText; // 暫存輸入內容，避免控制器釋放後仍被引用
    final formKey = GlobalKey<FormState>();
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重新命名影片'),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: TextFormField(
              initialValue: initialText,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: '影片名稱',
                helperText: '可留空以恢復預設名稱',
              ),
              onChanged: (value) => tempName = value,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.length > 40) {
                  return '名稱需在 40 字以內';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final isValid = formKey.currentState?.validate() ?? false;
                if (!isValid) {
                  return;
                }
                Navigator.of(dialogContext).pop(tempName.trim());
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );

    if (!mounted || newName == null) {
      debugPrint('[歷史頁] 重新命名流程取消或頁面已卸載');
      return;
    }

    final normalizedName = newName.trim();
    final storedName = normalizedName.isEmpty ? '' : normalizedName;
    debugPrint('[歷史頁] 重新命名輸入：stored="$storedName"');

    final index = _entries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (index == -1) {
      debugPrint('[歷史頁] 找不到對應紀錄，無法重新命名');
      return;
    }

    final originalName = (_entries[index].customName ?? '').trim();
    if (storedName == originalName) {
      debugPrint('[歷史頁] 名稱未變更，略過更新');
      return; // 名稱未變更時不更新檔案
    }

    final defaultTitle = entry.copyWith(customName: '').displayTitle;

    // 如果有雲端綁定，先更新雲端名稱
    if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
      try {
        final client = VideoServerClient();
        final displayName = storedName.isEmpty ? defaultTitle : storedName;
        final success = await client.updateVideoName(entry.cloudVideoId!, displayName);
        
        if (success) {
          debugPrint('[歷史頁] ✓ 已更新雲端影片名稱: $displayName');
        } else {
          debugPrint('[歷史頁] ⚠️ 更新雲端名稱失敗，但繼續更新本地');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('本地已更新，但雲端名稱更新失敗')),
            );
          }
        }
      } catch (e) {
        debugPrint('[歷史頁] ⚠️ 更新雲端名稱異常: $e，但繼續更新本地');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('本地已更新，但雲端同步失敗: $e')),
          );
        }
      }
    }

    _entries[index] = _entries[index].copyWith(customName: storedName);
    debugPrint('[歷史頁] 更新索引 $index 的名稱為 "$storedName"，準備儲存');
    if (mounted) {
      debugPrint('[歷史頁] 重新命名後刷新列表');
      _scheduleRebuild(); // 延後到安全時機再更新畫面
    }

    await RecordingHistoryStorage.instance.saveHistory(_entries);

    if (!mounted) return;
    final snackMessage = storedName.isEmpty
        ? '已恢復影片名稱為 $defaultTitle'
        : '已將影片命名為 $storedName';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackMessage)),
    );
  }

  /// 封裝安全的重繪流程，避免在對話框或排程回呼中直接呼叫 setState
  void _scheduleRebuild() {
    if (!mounted) {
      return; // 若頁面已卸載則不做任何事
    }

    if (_rebuildScheduled) {
      debugPrint('[歷史頁] 已有重繪排程，略過此次請求');
      return;
    }

    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) {
        debugPrint('[歷史頁] 排程執行時頁面已卸載，取消重繪');
        return;
      }

      debugPrint('[歷史頁] 執行排程重繪');
      setState(() {});
    });
  }

  /// 刪除影片檔與對應 CSV
  Future<void> _removeEntryFiles(RecordingHistoryEntry entry) async {
    try {
      final videoFile = File(entry.filePath);
      if (await videoFile.exists()) {
        await videoFile.delete();
      }
    } catch (_) {
      // 失敗時忽略，避免打斷流程
    }

    final thumbnailPath = entry.thumbnailPath;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      try {
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      } catch (_) {
        // 縮圖刪除失敗無須打斷主流程
      }
    }

    for (final path in entry.imuCsvPaths.values) {
      if (path.isEmpty) continue;
      try {
        final csvFile = File(path);
        if (await csvFile.exists()) {
          await csvFile.delete();
        }
      } catch (_) {
        // 單筆刪除失敗不影響整體
      }
    }
  }

  // ---------- 方法區 ----------
  /// 將時間轉換為易讀字串，方便列表展示
  String _formatTimestamp(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.year}/$month/$day $hour:$minute';
  }

  /// 嘗試播放指定的錄影紀錄，並在檔案遺失時提示使用者
  Future<void> _playEntry(RecordingHistoryEntry entry) async {
    await _playVideoByPath(entry.filePath, missingFileName: entry.fileName, cloudVideoId: entry.cloudVideoId);
  }

  Future<void> _showRecordingTypeDialog(RecordingHistoryEntry entry) async {
    if (!mounted) return;
    
    bool isClipped = false; // 用戶選擇的錄影類型
    bool uploadVideo = true; // 是否上傳影片
    bool uploadTrajectory = true; // 是否上傳軌跡
    bool directUpload = false; // 是否直接上傳（立即上傳）
    
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('上傳設定'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('影片名稱: ${entry.displayTitle}'),
                    const SizedBox(height: 16),
                    
                    // 錄影類型選擇
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '錄影類型',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ListTile(
                                    title: const Text('完整錄影'),
                                    leading: Radio<bool>(
                                      value: false,
                                      groupValue: isClipped,
                                      onChanged: (value) {
                                        setState(() {
                                          isClipped = value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListTile(
                                    title: const Text('已切割切片'),
                                    leading: Radio<bool>(
                                      value: true,
                                      groupValue: isClipped,
                                      onChanged: (value) {
                                        setState(() {
                                          isClipped = value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // 上傳內容選擇
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '上傳內容',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              title: const Text('上傳影片'),
                              value: uploadVideo,
                              onChanged: (value) {
                                setState(() {
                                  uploadVideo = value ?? true;
                                });
                              },
                            ),
                            CheckboxListTile(
                              title: const Text('上傳軌跡'),
                              value: uploadTrajectory,
                              onChanged: (value) {
                                setState(() {
                                  uploadTrajectory = value ?? true;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // 上傳方式選擇
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '上傳方式',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ListTile(
                                    title: const Text('稍後上傳'),
                                    leading: Radio<bool>(
                                      value: false,
                                      groupValue: directUpload,
                                      onChanged: (value) {
                                        setState(() {
                                          directUpload = value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListTile(
                                    title: const Text('直接上傳'),
                                    leading: Radio<bool>(
                                      value: true,
                                      groupValue: directUpload,
                                      onChanged: (value) {
                                        setState(() {
                                          directUpload = value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    // 根據選擇進行上傳
                    String uploadType = 'none';
                    if (uploadVideo && uploadTrajectory) {
                      uploadType = 'full';
                    } else if (uploadVideo) {
                      uploadType = 'video';
                    } else if (uploadTrajectory) {
                      uploadType = 'trajectory';
                    }
                    
                    if (uploadType != 'none') {
                      _uploadEntry(entry, uploadType: uploadType, isClipped: isClipped, directUpload: directUpload);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('請至少選擇上傳影片或軌跡')),
                      );
                    }
                  },
                  child: const Text('確認上傳'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 影片記錄建檔對話框 - 用於單條記錄
  Future<void> _showRecordingArchiveDialogForEntry(RecordingHistoryEntry entry) async {
    await _showRecordingArchiveDialogImpl(entry: entry);
  }

  /// 影片記錄建檔對話框 - 右上角按鈕，用於建立新記錄
  Future<void> _showRecordingArchiveDialog() async {
    await _showRecordingArchiveDialogImpl(forNewEntry: true);
  }

  /// 影片記錄建檔對話框 - 統一實現
  Future<void> _showRecordingArchiveDialogImpl({RecordingHistoryEntry? entry, bool forNewEntry = false}) async {
    if (!mounted) return;
    
    bool isClipped = false;
    String selectedVideoPath = '';
    String selectedChestCsvPath = '';
    String selectedRightWristCsvPath = '';
    
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.video_library_outlined, color: Color(0xFF123B70)),
                  SizedBox(width: 8),
                  Text('建立新記錄'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 影片類型選擇
                    const Text(
                      '📹 影片類型',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF123B70),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    isClipped = false;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: !isClipped ? const Color(0xFFE5EBF5) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: !isClipped ? const Color(0xFF123B70) : Colors.grey[300]!,
                                      width: !isClipped ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.videocam_outlined,
                                        color: !isClipped ? const Color(0xFF123B70) : Colors.grey,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '完整錄影',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: !isClipped ? const Color(0xFF123B70) : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    isClipped = true;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isClipped ? const Color(0xFFE5EBF5) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isClipped ? const Color(0xFF123B70) : Colors.grey[300]!,
                                      width: isClipped ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.cut,
                                        color: isClipped ? const Color(0xFF123B70) : Colors.grey,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '已切割片段',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isClipped ? const Color(0xFF123B70) : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // 上傳內容選擇
                    const Text(
                      '📁 選擇檔案',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF123B70),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 影片檔案區域
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FA),
                                border: Border.all(color: const Color(0xFFDCE3E8)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.movie_outlined, size: 16, color: Color(0xFF6F7B86)),
                                      SizedBox(width: 6),
                                      Text(
                                        '影片 *必填',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF123B70),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (selectedVideoPath.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF1E8E5A), width: 1.5),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle, size: 16, color: Color(0xFF1E8E5A)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              p.basename(selectedVideoPath),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                selectedVideoPath = '';
                                              });
                                            },
                                            child: const Icon(Icons.close, size: 16, color: Color(0xFF6F7B86)),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.folder_open_outlined),
                                      label: const Text('選擇影片'),
                                      onPressed: () async {
                                        final result = await FilePicker.platform.pickFiles(
                                          type: FileType.video,
                                        );
                                        if (result != null && result.files.isNotEmpty) {
                                          setState(() {
                                            selectedVideoPath = result.files.first.path ?? '';
                                          });
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 10),
                            
                            // CHEST 軌跡區域
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FA),
                                border: Border.all(color: const Color(0xFFDCE3E8)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.motion_photos_on_outlined, size: 16, color: Color(0xFF6F7B86)),
                                      SizedBox(width: 6),
                                      Text(
                                        'CHEST 軌跡',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF123B70),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (selectedChestCsvPath.isEmpty)
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.folder_open_outlined),
                                      label: const Text('選擇 CSV'),
                                      onPressed: () async {
                                        final result = await FilePicker.platform.pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: ['csv'],
                                        );
                                        if (result != null && result.files.isNotEmpty) {
                                          setState(() {
                                            selectedChestCsvPath = result.files.first.path ?? '';
                                          });
                                        }
                                      },
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF1E8E5A), width: 1.5),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle, size: 16, color: Color(0xFF1E8E5A)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              p.basename(selectedChestCsvPath),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                selectedChestCsvPath = '';
                                              });
                                            },
                                            child: const Icon(Icons.close, size: 16, color: Color(0xFF6F7B86)),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 10),
                            
                            // RIGHT WRIST 軌跡區域
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FA),
                                border: Border.all(color: const Color(0xFFDCE3E8)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.motion_photos_on_outlined, size: 16, color: Color(0xFF6F7B86)),
                                      SizedBox(width: 6),
                                      Text(
                                        'RIGHT WRIST 軌跡',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF123B70),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (selectedRightWristCsvPath.isEmpty)
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.folder_open_outlined),
                                      label: const Text('選擇 CSV'),
                                      onPressed: () async {
                                        final result = await FilePicker.platform.pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: ['csv'],
                                        );
                                        if (result != null && result.files.isNotEmpty) {
                                          setState(() {
                                            selectedRightWristCsvPath = result.files.first.path ?? '';
                                          });
                                        }
                                      },
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF1E8E5A), width: 1.5),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle, size: 16, color: Color(0xFF1E8E5A)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              p.basename(selectedRightWristCsvPath),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                selectedRightWristCsvPath = '';
                                              });
                                            },
                                            child: const Icon(Icons.close, size: 16, color: Color(0xFF6F7B86)),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _createNewRecordingEntry(
                      isClipped,
                      selectedVideoPath,
                      selectedChestCsvPath,
                      selectedRightWristCsvPath,
                    );
                  },
                  label: const Text('建立記錄'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 建立新的錄影記錄，綁定選定的影片和軌跡
  Future<void> _createNewRecordingEntry(
    bool isClipped,
    String selectedVideoPath,
    String selectedChestCsvPath,
    String selectedRightWristCsvPath,
  ) async {
    debugPrint('[歷史頁] 開始建立新記錄');
    debugPrint('📹 選擇影片: $selectedVideoPath');
    debugPrint('📊 CHEST軌跡: $selectedChestCsvPath');
    debugPrint('📊 RIGHT WRIST軌跡: $selectedRightWristCsvPath');
    
    if (selectedVideoPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請選擇影片')),
      );
      return;
    }

    try {
      final videoFile = File(selectedVideoPath);
      if (!await videoFile.exists()) {
        throw Exception('選擇的影片不存在');
      }

      // 構建 imuCsvPaths（只包含已選擇的軌跡）
      final Map<String, String> imuCsvPaths = {};
      if (selectedChestCsvPath.isNotEmpty) {
        if (!await File(selectedChestCsvPath).exists()) {
          throw Exception('CHEST軌跡檔案不存在');
        }
        imuCsvPaths['chest'] = selectedChestCsvPath;
      }
      if (selectedRightWristCsvPath.isNotEmpty) {
        if (!await File(selectedRightWristCsvPath).exists()) {
          throw Exception('RIGHT WRIST軌跡檔案不存在');
        }
        imuCsvPaths['right_wrist'] = selectedRightWristCsvPath;
      }

      // 生成縮略圖路徑
      final thumbnailPath = _getThumbnailPath(selectedVideoPath);

      // 計算新記錄的 roundIndex
      final int newRoundIndex = _entries.isEmpty
          ? 1
          : (_entries.map((e) => e.roundIndex).reduce(math.max) + 1);

      // 自動獲取視頻時長
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在分析影片...')),
      );
      final durationSeconds = await _getVideoDuration(selectedVideoPath);

      // 自動生成縮略圖
      debugPrint('[歷史頁] 開始生成縮略圖: $selectedVideoPath');
      final generatedThumbnailPath = await _generateThumbnailForVideo(selectedVideoPath);
      final finalThumbnailPath = generatedThumbnailPath ?? thumbnailPath;

      // 計算各軌跡的峰值
      debugPrint('[歷史頁] 開始計算峰值...');
      final peakValues = await _calculatePeakValues(imuCsvPaths);
      debugPrint('[歷史頁] ✅ 峰值計算完成: $peakValues');

      // 建立新的 RecordingHistoryEntry
      final newEntry = RecordingHistoryEntry(
        filePath: selectedVideoPath,
        roundIndex: newRoundIndex,
        recordedAt: DateTime.now(),
        durationSeconds: durationSeconds,
        imuConnected: imuCsvPaths.isNotEmpty,
        customName: '',
        imuCsvPaths: imuCsvPaths,
        thumbnailPath: finalThumbnailPath,
        cloudVideoId: null,
        isClipped: isClipped,
        videoType: VideoType.localClip,
        peakValues: peakValues.isNotEmpty ? peakValues : null,
      );

      // 新記錄添加到列表前端
      _entries.insert(0, newEntry);
      await RecordingHistoryStorage.instance.saveHistory(_entries);

      if (!mounted) return;
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 新記錄已建立：${p.basename(selectedVideoPath)}')),
      );

      debugPrint('[歷史頁] ✅ 新記錄建立成功');
      debugPrint('[歷史頁] 📋 記錄 ID: ${newEntry.roundIndex}');
      debugPrint('[歷史頁] 🎬 影片: ${newEntry.filePath}');
      debugPrint('[歷史頁] 📊 軌跡: ${imuCsvPaths.keys.join(", ")}');
    } catch (e) {
      debugPrint('[歷史頁] ❌ 建立記錄失敗: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('建立記錄失敗：$e')),
      );
    }
  }

  /// 上傳未同步的錄影
  Future<void> _uploadEntry(RecordingHistoryEntry entry, {
    String? uploadType, // 'video', 'trajectory', 'full', or null for default
    bool? isClipped,
    bool? directUpload,
  }) async {
    // 只有已同步或正在同步中的才禁止上傳，失败也允许重新上传
    if (entry.syncStatus == SyncStatus.synced || entry.syncStatus == SyncStatus.syncing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此影片已同步或正在同步中')),
      );
      return;
    }

    // 如果沒有指定上傳類型，使用預設值（上傳影片和軌跡）
    uploadType ??= 'full';
    
    // 如果選擇稍後上傳，只保存狀態不立即上傳
    if (directUpload == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.displayTitle} 已保存上傳設定，稍後可再次點擊上傳按鈕進行上傳')),
      );
      return;
    }

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[歷史頁] 開始上傳流程');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('📹 影片名稱: ${entry.displayTitle}');
    debugPrint('📂 檔案名稱: ${entry.fileName}');
    debugPrint('📍 檔案路徑: ${entry.filePath}');
    debugPrint('⏰ 錄製時間: ${entry.recordedAt}');
    debugPrint('📊 同步狀態: ${entry.syncStatus}');
    debugPrint('🎬 上傳類型: $uploadType');
    debugPrint('📋 是否為切割: ${isClipped ?? false}');
    debugPrint('⚡ 直接上傳: ${directUpload ?? true}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('開始上傳 ${entry.displayTitle}...')),
    );

    // 更新同步狀態為 syncing
    final int entryIndex = _entries.indexWhere((e) =>
        e.filePath == entry.filePath && e.recordedAt == entry.recordedAt);
    if (entryIndex == -1) return;

    _entries[entryIndex] = entry.copyWith(syncStatus: SyncStatus.syncing);
    if (mounted) {
      setState(() {});
    }

    try {
      // 檢查用戶是否已登入
      debugPrint('[歷史頁] 檢查登入狀態...');
      final isLoggedIn = await AuthTokenStorage.instance.isLoggedIn();
      final userId = await AuthTokenStorage.instance.getUserId();
      debugPrint('✅ 登入狀態: $isLoggedIn');
      debugPrint('👤 用戶 ID: $userId');
      
      if (!isLoggedIn) {
        // 導航到登入頁面
        if (!mounted) return;
        
        _entries[entryIndex] = entry.copyWith(syncStatus: SyncStatus.notSynced);
        if (mounted) {
          setState(() {});
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請登入後重試上傳')),
        );
        
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // 檢查文件是否存在
      debugPrint('[歷史頁] 檢查本地檔案...');
      final file = File(entry.filePath);
      final exists = await file.exists();
      debugPrint('📂 檔案存在: $exists');
      
      if (!exists) {
        throw Exception('視頻文件不存在：${entry.filePath}');
      }

      final fileSize = await file.length();
      debugPrint('💾 檔案大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      final serverClient = VideoServerClient();

      // 1. 在服務器上建立視頻紀錄
      debugPrint('[歷史頁] 步驟 1：建立服務器視頻紀錄');
      
      // 從 peakValues 中提取主要的峰值（優先使用 right_wrist，其次 chest，最後任意一個）
      double? mainPeakValue;
      if (entry.peakValues != null && entry.peakValues!.isNotEmpty) {
        if (entry.peakValues!.containsKey('right_wrist')) {
          mainPeakValue = entry.peakValues!['right_wrist'];
        } else if (entry.peakValues!.containsKey('chest')) {
          mainPeakValue = entry.peakValues!['chest'];
        } else {
          mainPeakValue = entry.peakValues!.values.first;
        }
        debugPrint('📊 提取主要峰值: $mainPeakValue');
      }
      
      final createResponse = await serverClient.createVideo(
        name: entry.displayTitle,
        type: 'original',
        hitSecond: entry.hitSecond,
        startSecond: entry.startSecond,
        endSecond: entry.endSecond,
        peakValue: mainPeakValue,
        rawPeakValues: entry.peakValues,
      );

      if (!createResponse['success']) {
        final error = createResponse['error'] ?? '未知錯誤';
        
        // 如果是 401 未授權，返回登入頁
        if (error.contains('401') || error.contains('未授權') || error.contains('無效的用戶身份')) {
          if (!mounted) return;
          
          _entries[entryIndex] = entry.copyWith(syncStatus: SyncStatus.notSynced);
          if (mounted) {
            setState(() {});
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登入已過期，請重新登入')),
          );
          
          await AuthTokenStorage.instance.clearTokens();
          Navigator.of(context).pushReplacementNamed('/login');
          return;
        }
        
        throw Exception('建立視頻失敗：$error');
      }

      // 從響應中提取視頻 ID
      // VideoServerClient 返回結構: { success: true, data: {...parsed json...} }
      // 而伺服器 API 的 JSON 返回結構: { success: true, video: { id: "...", ... } }
      var videoId;
      
      final data = createResponse['data'];
      if (data is Map) {
        // 直接取 data['video']['id'] 或 data['id']
        if (data['video'] != null) {
          videoId = data['video']['id'];
        } else {
          videoId = data['id'];
        }
      }
      
      if (videoId == null || videoId.toString().isEmpty) {
        debugPrint('[歷史頁] DEBUG 回應: $createResponse');
        throw Exception('無法從服務器回應取得視頻 ID');
      }

      debugPrint('[歷史頁] ✅ 視頻紀錄建立成功，ID: $videoId');

      // 立即將 videoId 綁定到本地記錄（用於追踪和恢復）
      _entries[entryIndex] = _entries[entryIndex].copyWith(
        cloudVideoId: videoId,
      );
      await RecordingHistoryStorage.instance.saveHistory(_entries);
      debugPrint('[歷史頁] 已將視頻 ID 綁定到本地記錄：cloudVideoId=$videoId');

      // 2. 上傳視頻文件（除非只上傳軌跡）
      if (uploadType != 'trajectory') {
        debugPrint('[歷史頁] 步驟 2：上傳視頻文件');
        debugPrint('📤 正在上傳檔案到伺服器...');
        debugPrint('🔗 API 端點: /api/videos/$videoId/files');
        final videoFileType = entry.isClipped ? 'clip' : 'original';
        final uploadResponse = await serverClient.uploadVideoFile(
          videoId: videoId,
          videoFilePath: entry.filePath,
          fileType: videoFileType,
          sourceLocalFilePath: entry.filePath,
        );

        debugPrint('📥 上傳回應: ${uploadResponse['success']}');
        
        if (!uploadResponse['success']) {
          final error = uploadResponse['error'] ?? '未知錯誤';
          debugPrint('❌ 上傳錯誤: $error');
          
          // 如果是 401 未授權，返回登入頁
          if (error.contains('401') || error.contains('未授權')) {
            if (!mounted) return;
            
            _entries[entryIndex] = entry.copyWith(syncStatus: SyncStatus.notSynced);
            if (mounted) {
              setState(() {});
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('登入已過期，請重新登入')),
            );
            
            await AuthTokenStorage.instance.clearTokens();
            Navigator.of(context).pushReplacementNamed('/login');
            return;
          }
          
          throw Exception('上傳文件失敗：$error');
        }

        debugPrint('[歷史頁] ✅ 視頻文件上傳成功');
      }

      // 2.5 上傳 CSV 文件（IMU 數據）（除非只上傳影片）
      if (uploadType != 'video') {
        debugPrint('[歷史頁] 步驟 2.5：上傳 CSV 文件');
        if (entry.imuCsvPaths.isNotEmpty) {
          for (final csvEntry in entry.imuCsvPaths.entries) {
            final csvLabel = csvEntry.key; // e.g., "RIGHT_WRIST", "CHEST"
            final csvPath = csvEntry.value;
            final peakValue = entry.peakValues?[csvLabel]; // 取得該軌跡的峰值
            
            if (await File(csvPath).exists()) {
              debugPrint('📊 上傳 $csvLabel CSV: $csvPath');
              if (peakValue != null) {
                debugPrint('📈 峰值: $peakValue');
              }
              
              final csvResponse = await serverClient.uploadVideoFile(
                videoId: videoId,
                videoFilePath: csvPath,
                fileType: csvLabel.toLowerCase(), // 使用 "right_wrist" 或 "chest" 作為檔案類型
                sourceLocalFilePath: csvPath,
                peakValue: peakValue,
              );

              if (csvResponse['success']) {
                debugPrint('[歷史頁] ✅ $csvLabel CSV 上傳成功');
              } else {
                debugPrint('[歷史頁] ⚠️ $csvLabel CSV 上傳失敗，但繼續進行');
              }
            } else {
              debugPrint('📊 未找到 $csvLabel CSV: $csvPath，跳過上傳');
            }
          }
        } else {
          debugPrint('📊 未找到任何 CSV 文件，跳過上傳');
        }
      }

      // 2.6 上傳縮略圖（如果存在且不只上傳軌跡）
      if (uploadType != 'trajectory') {
        debugPrint('[歷史頁] 步驟 2.6：上傳縮略圖');
        // 優先使用本地記錄的 thumbnailPath，如果沒有則試圖生成
        final storedThumbnailPath = entry.thumbnailPath?.trim() ?? '';
        final generatedThumbnailPath = _getThumbnailPath(entry.filePath);
        
        String? finalThumbnailPath;
        if (storedThumbnailPath.isNotEmpty && await File(storedThumbnailPath).exists()) {
          finalThumbnailPath = storedThumbnailPath;
          debugPrint('📸 使用已記錄的縮略圖: $storedThumbnailPath');
        } else if (await File(generatedThumbnailPath).exists()) {
          finalThumbnailPath = generatedThumbnailPath;
          debugPrint('📸 使用生成的縮略圖路徑: $generatedThumbnailPath');
        }
        
        if (finalThumbnailPath != null && finalThumbnailPath.isNotEmpty) {
          debugPrint('📸 發現縮略圖: $finalThumbnailPath');
          final thumbnailResponse = await serverClient.uploadVideoFile(
            videoId: videoId,
            videoFilePath: finalThumbnailPath,
            fileType: 'thumbnail',
            sourceLocalFilePath: finalThumbnailPath,
          );

          if (thumbnailResponse['success']) {
            debugPrint('[歷史頁] ✅ 縮略圖上傳成功');
          } else {
            debugPrint('[歷史頁] ⚠️ 縮略圖上傳失敗，但繼續進行');
          }
        } else {
          debugPrint('📸 未找到縮略圖，跳過上傳');
        }
      }

      // 3. 標記影片上傳完成
      debugPrint('[歷史頁] 步驟 3：標記上傳完成');
      final completeResponse = await serverClient.markVideoUploadComplete(
        videoId: videoId,
      );

      if (!completeResponse['success']) {
        final error = completeResponse['error'] ?? '未知錯誤';
        debugPrint('❌ 標記完成失敗: $error');
        
        if (error.contains('401') || error.contains('未授權')) {
          if (!mounted) return;
          
          _entries[entryIndex] = entry.copyWith(syncStatus: SyncStatus.notSynced);
          if (mounted) {
            setState(() {});
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登入已過期，請重新登入')),
          );
          
          await AuthTokenStorage.instance.clearTokens();
          Navigator.of(context).pushReplacementNamed('/login');
          return;
        }
        
        throw Exception('標記上傳完成失敗：$error');
      }

      debugPrint('[歷史頁] ✅ 影片上傳完成標記成功');

      // 4. 從雲端重新獲取最新的視頻元數據和處理狀態
      debugPrint('[歷史頁] 步驟 4：從雲端重新獲取視頻元數據和處理狀態...');
      try {
        final serverClient = VideoServerClient();
        final videoDetailResponse = await serverClient.getVideoDetail(videoId);
        
        if (videoDetailResponse['success']) {
          final videoDetail = videoDetailResponse['data'] as Map<String, dynamic>;
          final queueStatus = videoDetail['queueStatus'] as Map<String, dynamic>?;
          
          // 更新 processingStatus
          ProcessingStatus updatedProcessingStatus = ProcessingStatus.notStarted;
          if (queueStatus != null) {
            final latestStatus = queueStatus['status']?.toString() ?? 'notStarted';
            updatedProcessingStatus = ProcessingStatus.fromString(latestStatus);
            debugPrint('📊 從雲端獲取最新處理狀態: $latestStatus');
          }
          
          // 提取音頻分析數據
          double? audioCrispness;
          bool? goodShot;
          if (videoDetail['audioCrispness'] != null) {
            audioCrispness = (videoDetail['audioCrispness'] as num?)?.toDouble();
          }
          if (videoDetail['goodShot'] != null) {
            goodShot = videoDetail['goodShot'] as bool?;
          }
          
          // 保存最新的元數據
          _entries[entryIndex] = _entries[entryIndex].copyWith(
            syncStatus: SyncStatus.synced,
            cloudVideoId: videoId.toString(),
            processingStatus: updatedProcessingStatus,
            audioCrispness: audioCrispness,
            goodShot: goodShot,
          );
        } else {
          // 如果無法獲取，仍然保存同步狀態但保留原有的 processingStatus
          _entries[entryIndex] = _entries[entryIndex].copyWith(
            syncStatus: SyncStatus.synced,
            cloudVideoId: videoId.toString(),
          );
          debugPrint('⚠️ 無法從雲端獲取最新元數據，但上傳已成功');
        }
      } catch (e) {
        debugPrint('⚠️ 獲取雲端元數據失敗: $e，但上傳已成功');
        // 即使失敗也繼續，至少保存同步狀態
        _entries[entryIndex] = _entries[entryIndex].copyWith(
          syncStatus: SyncStatus.synced,
          cloudVideoId: videoId.toString(),
        );
      }
      
      await RecordingHistoryStorage.instance.saveHistory(_entries);
      
      if (!mounted) return;
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.displayTitle} 上傳成功')),
      );

      debugPrint('[歷史頁] ✅ 上傳流程完成');
      debugPrint('═══════════════════════════════════════════════════════════');
    } catch (e) {
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('[歷史頁] ❌ 上傳失敗: $e');
      debugPrint('📋 堆棧追蹤:');
      debugPrint(e.toString());
      debugPrint('═══════════════════════════════════════════════════════════');
      
      _entries[entryIndex] = _entries[entryIndex].copyWith(
        syncStatus: SyncStatus.failed,
        uploadError: e.toString(),
      );
      if (mounted) {
        setState(() {});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上傳失敗：$e')),
      );
    }
  }

  /// 自外部檔案夾挑選影片後播放，支援檢視非當前清單中的檔案
  Future<void> _pickExternalVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) {
      return;
    }
    await _playVideoByPath(result.files.single.path!);
  }

  /// 顯示本地影片紀錄的 JSON debug 資訊
  Future<void> _showDebugJsonInfo() async {
    if (!mounted) return;
    
    try {
      // 將所有本地紀錄轉換為格式化的 JSON（帶換行和縮進）
      final jsonList = _entries.map((entry) => entry.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
      
      if (!mounted) return;
      
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('本地影片紀錄 (JSON Debug)'),
          content: SingleChildScrollView(
            child: SelectableText(
              jsonString,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'Courier',
                color: Color(0xFF123B70),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('關閉'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法顯示 JSON：$e')),
      );
    }
  }

  /// 實際進行影片播放與檔案檢查的共用方法
  Future<void> _playVideoByPath(String path, {String? missingFileName, String? cloudVideoId}) async {
    // 如果有云端视频 ID，直接使用云端版本，不检查本地文件
    if (cloudVideoId != null && cloudVideoId.isNotEmpty) {
      debugPrint('[歷史頁] 優先使用雲端視頻：$cloudVideoId');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            videoPath: path,
            avatarPath: widget.userAvatarPath,
            cloudVideoId: cloudVideoId,
          ),
        ),
      );
      return;
    }

    // 没有云端版本，检查本地文件
    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      final fallbackName = missingFileName ?? path.split(RegExp(r'[\\/]')).last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('找不到影片檔案 $fallbackName，請確認檔案是否仍存在於裝置內。')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoPath: path,
          avatarPath: widget.userAvatarPath,
        ),
      ),
    );
  }

  /// 根據排序選項對條目進行排序
  List<RecordingHistoryEntry> _sortEntries(List<RecordingHistoryEntry> entries) {
    final sorted = List<RecordingHistoryEntry>.from(entries);
    
    switch (_sortBy) {
      case _SortBy.date:
        // 按時間排序（最新優先）
        sorted.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
        break;
      
      case _SortBy.peakValue:
        // 按最佳速度排序（最高優先）
        sorted.sort((a, b) {
          // 取得每個條目的最高峰值
          final maxPeakA = _getMaxPeakValue(a);
          final maxPeakB = _getMaxPeakValue(b);
          
          // 如果都沒有數據，則按時間排序
          if (maxPeakA == null && maxPeakB == null) {
            return b.recordedAt.compareTo(a.recordedAt);
          }
          
          // 如果只有一個有數據，有數據的排前面
          if (maxPeakA == null) return 1;
          if (maxPeakB == null) return -1;
          
          // 都有數據的話，較高的排前面
          return maxPeakB.compareTo(maxPeakA);
        });
        break;
      
      case _SortBy.audioCrispness:
        // 按聲音清脆度排序（最高優先）
        sorted.sort((a, b) {
          final crispnessA = a.audioCrispness ?? -1;
          final crispnessB = b.audioCrispness ?? -1;
          
          // 如果都沒有數據，則按時間排序
          if (crispnessA == -1 && crispnessB == -1) {
            return b.recordedAt.compareTo(a.recordedAt);
          }
          
          // 較高的排前面
          return crispnessB.compareTo(crispnessA);
        });
        break;
    }
    
    return sorted;
  }

  /// 從 peakValues Map 中獲取最高峰值
  double? _getMaxPeakValue(RecordingHistoryEntry entry) {
    if (entry.peakValues == null || entry.peakValues!.isEmpty) {
      return null;
    }
    return entry.peakValues!.values.reduce((a, b) => a > b ? a : b);
  }

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
    // 根据选中的过滤条件过滤条目
    var filteredEntries = _selectedGoodShot == null
        ? _entries
        : _entries.where((entry) => entry.goodShot == _selectedGoodShot).toList();
    
    // 應用排序
    filteredEntries = _sortEntries(filteredEntries);

    return WillPopScope(
      onWillPop: () async {
        _finishWithResult();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('錄影歷史'),
          leading: IconButton(
            onPressed: _finishWithResult,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              onPressed: _showRecordingArchiveDialog,
              tooltip: '建立新記錄',
              icon: const Icon(Icons.add_rounded),
            ),
            IconButton(
              onPressed: _pickExternalVideo,
              tooltip: '開啟其他影片',
              icon: const Icon(Icons.folder_open_rounded),
            ),
            IconButton(
              onPressed: _showDebugJsonInfo,
              tooltip: 'Debug: 本地紀錄 JSON',
              icon: const Icon(Icons.bug_report_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            // 好球/壞球 TAB 選擇器
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    FilterChip(
                      selected: _selectedGoodShot == null,
                      label: const Text('全部'),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedGoodShot = null);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _selectedGoodShot == true,
                      label: const Text('好球 ✓'),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedGoodShot = true);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _selectedGoodShot == false,
                      label: const Text('壞球 ✗'),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedGoodShot = false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            // 排序選擇器
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      '排序: ',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _sortBy == _SortBy.date,
                      label: const Text('時間'),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _sortBy = _SortBy.date);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _sortBy == _SortBy.peakValue,
                      label: const Text('最佳速度 🎯'),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _sortBy = _SortBy.peakValue);
                        }
                      },
                    ),
                    const SizedBox(width: 8)
                  ],
                ),
              ),
            ),
            // 影片列表
            Expanded(
              child: filteredEntries.isEmpty
                  ? const _EmptyHistoryView()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        return _HistoryTile(
                          entry: entry,
                          formattedTime: _formatTimestamp(entry.recordedAt),
                          onTap: () => _playEntry(entry),
                          onRename: () => _renameEntry(entry),
                          onEditDuration: () => _editEntryDuration(entry),
                          onSplit: () => _splitEntry(entry),
                          onDelete: () => _deleteEntry(entry),
                          onUpload: entry.syncStatus == SyncStatus.notSynced || entry.syncStatus == SyncStatus.failed
                              ? () => _uploadEntry(entry)
                              : null,
                          onUnbindCloud: entry.syncStatus == SyncStatus.synced
                              ? () => _unbindCloudVideo(entry)
                              : null,
                          onRerunAnalysis: entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty
                              ? () => _rerunAnalysisEntry(entry)
                              : null,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: filteredEntries.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空狀態元件：提醒使用者目前沒有歷史資料
class _EmptyHistoryView extends StatelessWidget {
  const _EmptyHistoryView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.video_collection_outlined, size: 72, color: Color(0xFF9AA6B2)),
          SizedBox(height: 16),
          Text(
            '目前沒有錄影紀錄',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF123B70)),
          ),
          SizedBox(height: 8),
          Text(
            '完成一次錄影後即可在此查看歷史影片。',
            style: TextStyle(fontSize: 13, color: Color(0xFF6F7B86)),
          ),
        ],
      ),
    );
  }
}

/// 單筆歷史紀錄的呈現元件，包含標題、時間與檔名資訊
class _HistoryTile extends StatefulWidget {
  final RecordingHistoryEntry entry; // 對應的錄影資料
  final String formattedTime; // 已轉換好的顯示時間
  final VoidCallback onTap; // 點擊後的播放行為
  final VoidCallback onRename; // 重新命名影片
  final VoidCallback onEditDuration; // 調整影片時長
  final VoidCallback onSplit; // 自動分片
  final VoidCallback onDelete; // 刪除影片紀錄
  final VoidCallback? onUpload; // 上傳影片（未同步時可用）
  final VoidCallback? onUnbindCloud; // 移除雲端綁定（已同步時可用）
  final VoidCallback? onRerunAnalysis; // 重新分析影片

  const _HistoryTile({
    required this.entry,
    required this.formattedTime,
    required this.onTap,
    required this.onRename,
    required this.onEditDuration,
    required this.onSplit,
    required this.onDelete,
    this.onUpload,
    this.onUnbindCloud,
    this.onRerunAnalysis,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late Future<List<HitsSummary>> _hitsSummaryFuture;
  late Future<Map<String, dynamic>> _cloudVideoDetailFuture;

  @override
  void initState() {
    super.initState();
    _loadHitsSummary();
    _loadCloudVideoDetail();
  }

  void _loadHitsSummary() {
    // 尝试从cut目录加载hits_summary.csv
    final summaryPath = p.join(
      p.dirname(widget.entry.filePath),
      'cut',
      'hits_summary.csv',
    );
    _hitsSummaryFuture = HitsSummaryStorage.loadHitsSummary(summaryPath);
  }

  /// 如果有云端绑定，从云端获取视频详细信息
  void _loadCloudVideoDetail() {
    if (widget.entry.cloudVideoId != null && widget.entry.cloudVideoId!.isNotEmpty) {
      debugPrint('[歷史磚] 加載雲端視頻詳情: ${widget.entry.cloudVideoId}');
      final serverClient = VideoServerClient();
      _cloudVideoDetailFuture = serverClient.getVideoDetail(widget.entry.cloudVideoId!);
    } else {
      // 如果沒有雲端綁定，返回空的 Future
      _cloudVideoDetailFuture = Future.value({
        'success': false,
        'data': null,
      });
    }
  }

  /// 從 peakValues Map 中獲取最高峰值
  double? _getMaxPeakValue(RecordingHistoryEntry entry) {
    if (entry.peakValues == null || entry.peakValues!.isEmpty) {
      return null;
    }
    return entry.peakValues!.values.reduce((a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：縮圖、標題和操作按鈕
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 縮圖
                _HistoryPreview(
                  thumbnailPath: widget.entry.thumbnailPath,
                  roundIndex: widget.entry.roundIndex,
                ),
                const SizedBox(width: 12),
                // 標題和同步狀態
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 如果是雲端影片，顯示雲端名稱；否則顯示本地名稱
                      if (widget.entry.videoType == VideoType.cloudClip)
                        FutureBuilder<Map<String, dynamic>>(
                          future: _cloudVideoDetailFuture,
                          builder: (context, snapshot) {
                            String displayName = widget.entry.displayTitle;
                            if (snapshot.hasData && (snapshot.data?['success'] ?? false)) {
                              final videoDetail = snapshot.data!['data'] as Map<String, dynamic>?;
                              if (videoDetail != null && videoDetail['name'] != null) {
                                displayName = videoDetail['name'] as String;
                              }
                            }
                            return Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF123B70),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        )
                      else
                        Text(
                          widget.entry.displayTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF123B70),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      // 狀態徽章區 - 使用 Wrap 以支援標籤換行
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // 同步狀態徽章
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: widget.entry.syncStatus.badgeColor.withAlpha(30),
                              border: Border.all(
                                color: widget.entry.syncStatus.badgeColor,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              // 雲端影片且已同步時，顯示「雲端」；否則顯示同步狀態
                              (widget.entry.videoType == VideoType.cloudClip &&
                               widget.entry.syncStatus == SyncStatus.synced)
                                  ? '☁️ 雲端'
                                  : widget.entry.syncStatus.label,
                              style: TextStyle(
                                fontSize: 10,
                                color: widget.entry.syncStatus.badgeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // 處理隊列狀態（已同步時顯示）
                          if (widget.entry.syncStatus == SyncStatus.synced)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: widget.entry.processingStatus.badgeColor.withAlpha(30),
                                border: Border.all(
                                  color: widget.entry.processingStatus.badgeColor,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.entry.processingStatus.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.entry.processingStatus.badgeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          // 已切片標記（只對原始影片顯示）
                          if (widget.entry.videoType == VideoType.original &&
                              widget.entry.isClipped)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800).withAlpha(30),
                                border: Border.all(
                                  color: const Color(0xFFFF9800),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '✂️ 已切片',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFFF9800),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          // 雲端影片高亮 - 有cloudVideoId時顯示
                          if (widget.entry.cloudVideoId != null && widget.entry.cloudVideoId!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3).withAlpha(40),
                                border: Border.all(
                                  color: const Color(0xFF2196F3),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '☁️ 雲端下載',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF2196F3),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          // 好球/壞球指示器
                          if (widget.entry.goodShot != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: widget.entry.goodShot == true
                                    ? const Color(0xFF4CAF50).withAlpha(30)
                                    : const Color(0xFFF44336).withAlpha(30),
                                border: Border.all(
                                  color: widget.entry.goodShot == true
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF44336),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.entry.goodShot == true ? '✓ 好球' : '✗ 壞球',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.entry.goodShot == true
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF44336),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 右側操作按鈕（固定位置）
                PopupMenuButton<_HistoryMenuAction>(
                  tooltip: '更多操作',
                  icon: const Icon(
                    Icons.more_vert,
                    color: Color(0xFF123B70),
                    size: 20,
                  ),
                  onSelected: (action) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      switch (action) {
                        case _HistoryMenuAction.rename:
                          widget.onRename();
                          break;
                        case _HistoryMenuAction.editDuration:
                          widget.onEditDuration();
                          break;
                        case _HistoryMenuAction.split:
                          widget.onSplit();
                          break;
                        case _HistoryMenuAction.upload:
                          widget.onUpload?.call();
                          break;
                        case _HistoryMenuAction.delete:
                          widget.onDelete();
                          break;
                        case _HistoryMenuAction.unbindCloud:
                          widget.onUnbindCloud?.call();
                          break;
                        case _HistoryMenuAction.rerunAnalysis:
                          widget.onRerunAnalysis?.call();
                          break;
                      }
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.rename,
                      child: Text('重新命名'),
                    ),
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.editDuration,
                      child: Text('調整時長'),
                    ),
                    // 只有本地原始影片才能自動分片，切片影片不顯示此選項
                    if (!widget.entry.isClipped)
                      const PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.split,
                        child: Text('自動分片'),
                      ),
                    // 若是雲端切片，不顯示上傳
                    if (widget.onUpload != null && widget.entry.videoType != VideoType.cloudClip)
                      const PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.upload,
                        child: Text('上傳到雲端'),
                      ),
                    // 若是雲端切片，不顯示移除雲端綁定
                    if (widget.entry.syncStatus == SyncStatus.synced && widget.entry.videoType != VideoType.cloudClip)
                      const PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.unbindCloud,
                        child: Text('移除雲端綁定'),
                      ),
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.delete,
                      child: Text('刪除影片'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 第二行：時間、時長、模式（帶播放按鈕）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${widget.formattedTime} · ${widget.entry.durationSeconds} 秒 · ${widget.entry.modeLabel}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: widget.onTap,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFF1E8E5A),
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 第三行：最佳速度和聲音清脆度
            if (widget.entry.peakValues != null && widget.entry.peakValues!.isNotEmpty || widget.entry.audioCrispness != null)
              Row(
                children: [
                  if (widget.entry.peakValues != null && widget.entry.peakValues!.isNotEmpty) ...[
                    const Icon(Icons.trending_up, size: 14, color: Color(0xFF1976D2)),
                    const SizedBox(width: 4),
                    Text(
                      '速度: ${_getMaxPeakValue(widget.entry)?.toStringAsFixed(1) ?? 'N/A'}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF1976D2), fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (widget.entry.audioCrispness != null) ...[
                    const Icon(Icons.music_note, size: 14, color: Color(0xFFFF6F00)),
                    const SizedBox(width: 4),
                    Text(
                      '清脆度: ${widget.entry.audioCrispness!.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFFF6F00), fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 6),
            // 第四行：影片類型和檔名
            Text(
              '${widget.entry.videoType.icon} ${widget.entry.videoType.label}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9AA6B2)),
            ),
            const SizedBox(height: 2),
            Text(
              widget.entry.fileName,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9AA6B2)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.entry.hasImuCsv) ...[
              const SizedBox(height: 6),
              Text(
                'IMU CSV：${widget.entry.csvFileNames.join(', ')}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4F5D75)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // 摆球摘要展开面板
            const SizedBox(height: 12),
            FutureBuilder<List<HitsSummary>>(
              future: _hitsSummaryFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }

                final hitsSummary = snapshot.data!;
                return HitsSummaryExpansionTile(
                  hitsSummary: hitsSummary,
                  title: '摆球摘要',
                  initiallyExpanded: false,
                );
              },
            ),
            // 云端處理隊列狀態顯示
            if (widget.entry.cloudVideoId != null && widget.entry.cloudVideoId!.isNotEmpty) ...[
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _cloudVideoDetailFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  if (!snapshot.hasData || !(snapshot.data?['success'] ?? false)) {
                    return const SizedBox.shrink();
                  }

                  final videoDetail = snapshot.data!['data'] as Map<String, dynamic>?;
                  if (videoDetail == null) {
                    return const SizedBox.shrink();
                  }

                  // 提取隊列狀態信息
                  final queueStatus = videoDetail['queueStatus'] as Map<String, dynamic>?;
                  if (queueStatus == null) {
                    return const SizedBox.shrink();
                  }

                  final total = queueStatus['total'] as int? ?? 0;
                  final pending = queueStatus['pending'] as int? ?? 0;
                  final processing = queueStatus['processing'] as int? ?? 0;
                  final completed = queueStatus['completed'] as int? ?? 0;
                  final failed = queueStatus['failed'] as int? ?? 0;
                  final latestStatus = queueStatus['latestStatus'] as String? ?? 'unknown';

                  // 如果沒有隊列項目則不顯示
                  if (total == 0) {
                    return const SizedBox.shrink();
                  }

                  // 根據狀態顯示不同的標籤
                  Color statusColor;
                  String statusLabel;
                  IconData statusIcon;

                  switch (latestStatus) {
                    case 'completed':
                      statusColor = const Color(0xFF1E8E5A);
                      statusLabel = '已完成';
                      statusIcon = Icons.check_circle;
                      break;
                    case 'processing':
                      statusColor = const Color(0xFFF59E0B);
                      statusLabel = '處理中';
                      statusIcon = Icons.hourglass_bottom;
                      break;
                    case 'queued':
                      statusColor = const Color(0xFF3B82F6);
                      statusLabel = '排隊中';
                      statusIcon = Icons.schedule;
                      break;
                    case 'failed':
                      statusColor = const Color(0xFFEF4444);
                      statusLabel = '已失敗';
                      statusIcon = Icons.error;
                      break;
                    default:
                      statusColor = const Color(0xFF6F7B86);
                      statusLabel = '未知';
                      statusIcon = Icons.info;
                  }

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(statusIcon, color: statusColor, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '雲端處理狀態：$statusLabel',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (completed > 0) ...[
                              Text(
                                '✅ 已完成 $completed',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF1E8E5A)),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (processing > 0) ...[
                              Text(
                                '⏳ 處理中 $processing',
                                style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (pending > 0) ...[
                              Text(
                                '⏳ 排隊 $pending',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (failed > 0) ...[
                              Text(
                                '❌ 失敗 $failed',
                                style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 縮圖元件：顯示影片預覽或替代圖示，並標示錄影輪次
class _HistoryPreview extends StatelessWidget {
  final String? thumbnailPath; // 影片縮圖路徑
  final int roundIndex; // 對應的錄影輪次

  const _HistoryPreview({
    required this.thumbnailPath,
    required this.roundIndex,
  });

  @override
  Widget build(BuildContext context) {
    final filePath = thumbnailPath?.trim() ?? '';
    final hasThumbnail = filePath.isNotEmpty && File(filePath).existsSync();

    // 若有縮圖則顯示圖片，否則提供預設背景與圖示
    final Widget content = hasThumbnail
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(filePath),
              width: 112,
              height: 72,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: 112,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EBF5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.videocam_outlined, color: Color(0xFF123B70), size: 32),
          );

    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        content,
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '第 $roundIndex 輪',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
