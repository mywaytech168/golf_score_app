import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
// restored original local VideoPlayerPage usage
import '../models/recording_history_entry.dart';
import 'external_video_importer_local.dart';
import '../services/recording_history_storage.dart';
import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import '../services/swing_split_service.dart';
import 'recording_session_page.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, editDuration, delete, split, upload, unbindCloud }

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

    _entries.removeAt(index); // 先調整資料來源
    if (mounted) {
      debugPrint('[歷史頁] 刪除後立即刷新列表，剩餘 ${_entries.length} 筆');
      setState(() {}); // 通知畫面重新渲染
    }

    await _removeEntryFiles(entry);
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

    // 更新條目：清除雲端相關資訊，重置為未同步狀態
    _entries[index] = _entries[index].copyWith(
      syncStatus: SyncStatus.notSynced,
      cloudVideoId: null,
    );

    await RecordingHistoryStorage.instance.saveHistory(_entries);
    
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移除 ${entry.displayTitle} 的雲端綁定')),
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
      final results = await SwingSplitService.split(
        videoPath: entry.filePath,
        imuCsvPath: csvPath,
        outDirName: p.basename(outDir),
      );
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
    await _playVideoByPath(entry.filePath, missingFileName: entry.fileName);
  }

  /// 上傳未同步的錄影
  Future<void> _uploadEntry(RecordingHistoryEntry entry) async {
    // 只有已同步或正在同步中的才禁止上傳，失败也允许重新上传
    if (entry.syncStatus == SyncStatus.synced || entry.syncStatus == SyncStatus.syncing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此影片已同步或正在同步中')),
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
      final createResponse = await serverClient.createVideo(
        name: entry.displayTitle,
        type: 'original',
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

      // 2. 上傳視頻文件
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

      // 2.5 上傳 CSV 文件（IMU 數據）
      debugPrint('[歷史頁] 步驟 2.5：上傳 CSV 文件');
      if (entry.imuCsvPaths.isNotEmpty) {
        for (final csvEntry in entry.imuCsvPaths.entries) {
          final csvLabel = csvEntry.key; // e.g., "RIGHT_WRIST", "CHEST"
          final csvPath = csvEntry.value;
          
          if (await File(csvPath).exists()) {
            debugPrint('📊 上傳 $csvLabel CSV: $csvPath');
            final csvResponse = await serverClient.uploadVideoFile(
              videoId: videoId,
              videoFilePath: csvPath,
              fileType: csvLabel.toLowerCase(), // 使用 "right_wrist" 或 "chest" 作為檔案類型
              sourceLocalFilePath: csvPath,
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

      // 2.6 上傳縮略圖（如果存在）
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

      // 4. 更新同步狀態
      debugPrint('[歷史頁] 步驟 4：保存同步狀態');
      _entries[entryIndex] = _entries[entryIndex].copyWith(
        syncStatus: SyncStatus.synced,
        cloudVideoId: videoId.toString(),
      );
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

  /// 透過檔案挑選器匯入外部影片，並加入現有練習歷史清單
  Future<void> _importExternalVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) {
      return; // 使用者取消或選取失敗
    }

    final csvResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: '選擇對應的 IMU CSV（可略過）',
    );
    final String? imuCsvPath = csvResult?.files.single.path;

    final entry = await _videoImporter.importVideo(
      sourcePath: result.files.single.path!,
      originalName: result.files.single.name,
      nextRoundIndex: ExternalVideoImporter.calculateNextRoundIndex(_entries),
      imuCsvPath: imuCsvPath,
    );

    if (entry == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('匯入影片失敗，請確認檔案是否可讀取。')),
      );
      return;
    }

    _entries.insert(0, entry); // 新增練習置於最前方，方便立即查看
    if (mounted) {
      _scheduleRebuild();
    }

    await RecordingHistoryStorage.instance.saveHistory(_entries);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已匯入 ${entry.displayTitle}，同步加入練習紀錄。')),
    );
  }

  /// 自外部檔案夾挑選影片後播放，支援檢視非當前清單中的檔案
  Future<void> _pickExternalVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) {
      return;
    }
    await _playVideoByPath(result.files.single.path!);
  }

  /// 實際進行影片播放與檔案檢查的共用方法
  Future<void> _playVideoByPath(String path, {String? missingFileName}) async {
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

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
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
              onPressed: _importExternalVideo,
              tooltip: '匯入外部影片',
              icon: const Icon(Icons.file_upload_rounded),
            ),
            IconButton(
              onPressed: _pickExternalVideo,
              tooltip: '開啟其他影片',
              icon: const Icon(Icons.folder_open_rounded),
            ),
          ],
        ),
        body: _entries.isEmpty
            ? const _EmptyHistoryView()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
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
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: _entries.length,
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
class _HistoryTile extends StatelessWidget {
  final RecordingHistoryEntry entry; // 對應的錄影資料
  final String formattedTime; // 已轉換好的顯示時間
  final VoidCallback onTap; // 點擊後的播放行為
  final VoidCallback onRename; // 重新命名影片
  final VoidCallback onEditDuration; // 調整影片時長
  final VoidCallback onSplit; // 自動分片
  final VoidCallback onDelete; // 刪除影片紀錄
  final VoidCallback? onUpload; // 上傳影片（未同步時可用）
  final VoidCallback? onUnbindCloud; // 移除雲端綁定（已同步時可用）

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
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
                  thumbnailPath: entry.thumbnailPath,
                  roundIndex: entry.roundIndex,
                ),
                const SizedBox(width: 12),
                // 標題和同步狀態
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.displayTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF123B70),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 狀態徽章區
                      Row(
                        children: [
                          // 同步狀態徽章
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: entry.syncStatus.badgeColor.withAlpha(30),
                              border: Border.all(
                                color: entry.syncStatus.badgeColor,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              entry.syncStatus.label,
                              style: TextStyle(
                                fontSize: 10,
                                color: entry.syncStatus.badgeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 已切片標記（只對原始影片顯示）
                          if (entry.videoType == VideoType.original &&
                              entry.isClipped)
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
                          onRename();
                          break;
                        case _HistoryMenuAction.editDuration:
                          onEditDuration();
                          break;
                        case _HistoryMenuAction.split:
                          onSplit();
                          break;
                        case _HistoryMenuAction.upload:
                          onUpload?.call();
                          break;
                        case _HistoryMenuAction.delete:
                          onDelete();
                          break;
                        case _HistoryMenuAction.unbindCloud:
                          onUnbindCloud?.call();
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
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.split,
                      child: Text('自動分片'),
                    ),
                    if (onUpload != null)
                      const PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.upload,
                        child: Text('上傳到雲端'),
                      ),
                    if (entry.syncStatus == SyncStatus.synced)
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
                    '$formattedTime · ${entry.durationSeconds} 秒 · ${entry.modeLabel}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onTap,
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
            // 第三行：影片類型和檔名
            Text(
              '${entry.videoType.icon} ${entry.videoType.label}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9AA6B2)),
            ),
            const SizedBox(height: 2),
            Text(
              entry.fileName,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9AA6B2)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (entry.hasImuCsv) ...[
              const SizedBox(height: 6),
              Text(
                'IMU CSV：${entry.csvFileNames.join(', ')}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4F5D75)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
