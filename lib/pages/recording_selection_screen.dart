import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import '../recording/record_screen.dart';
import 'external_video_importer_local.dart';
import '../models/recording_history_entry.dart';
import '../services/recording_history_storage.dart';
import 'share_import_page.dart';

/// 通知類型枚舉
enum NotificationType {
  selected,   // ✅ 已選擇
  importing,  // ⏳ 導入中
  success,    // ✅ 成功
  failed,     // ❌ 失敗
  cancelled,  // ⊘ 已取消
}

/// 錄製選擇屏幕：讓使用者選擇「開始錄製」或「選擇本地影片」
class RecordingSelectionScreen extends StatefulWidget {
  final RecordCompleteCallback? onComplete;
  final VoidCallback? onVideoImported;

  const RecordingSelectionScreen({
    this.onComplete,
    this.onVideoImported,
    super.key,
  });

  @override
  State<RecordingSelectionScreen> createState() =>
      _RecordingSelectionScreenState();
}

class _RecordingSelectionScreenState extends State<RecordingSelectionScreen> {
  final ExternalVideoImporter _videoImporter = const ExternalVideoImporter();
  bool _isImporting = false; // 控制導入過程中的 UI 狀態

  /// 選項 1: 開始錄製
  void _startRecording() {
    debugPrint('[RecordingSelection] 使用者選擇開始錄製');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordScreen(
          onComplete: ({
            required videoPath,
            required csvPath,
            required audioPath,
            required durationSeconds,
            required thumbnailPath,
            required audioLabel,
            List<String>? audioTags,
          }) {
            debugPrint('[RecordingSelection] 錄製完成，調用回調');
            // 調用父頁面的回調
            widget.onComplete?.call(
              videoPath: videoPath,
              csvPath: csvPath,
              audioPath: audioPath,
              durationSeconds: durationSeconds,
              thumbnailPath: thumbnailPath,
              audioLabel: audioLabel,
              audioTags: audioTags,
            );
            // 返回到選擇屏幕
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  /// 選項 3: 從分享連結取得
  void _importFromShare() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareImportPage(
          onImported: () {
            widget.onVideoImported?.call();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  /// 選項 2: 選擇本地影片
  void _selectLocalVideo() async {
    debugPrint('[RecordingSelection] 使用者選擇本地影片');

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty || result.files.single.path == null) {
      debugPrint('[RecordingSelection] 使用者取消選擇');
      _showNotification(
        message: '❌ 未選擇任何檔案',
        type: NotificationType.cancelled,
      );
      return;
    }

    // 選完立即鎖定畫面，防止使用者繼續操作
    if (!mounted) return;
    setState(() => _isImporting = true);

    final path = result.files.single.path!;
    final fileName = result.files.single.name;
    final fileSize = result.files.single.size;

    // 先檢查影片長度，超過 2 分鐘拒絕
    final durationSec = await _getVideoDurationSeconds(path);
    if (durationSec > 120) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      _showNotification(
        message: '❌ 影片超過 2 分鐘限制（$durationSec 秒）\n請選擇 120 秒以內的影片',
        type: NotificationType.failed,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    // 通過時長限制，通知使用者
    if (!mounted) return;
    _showNotification(
      message: '✅ 影片時長 $durationSec 秒，符合 2 分鐘限制',
      type: NotificationType.selected,
    );

    await _importExternalVideo(
      path: path,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  /// 取得影片秒數（失敗時回傳 0）
  Future<int> _getVideoDurationSeconds(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return controller.value.duration.inSeconds;
    } catch (_) {
      return 0;
    } finally {
      await controller.dispose();
    }
  }

  /// 實際執行影片匯入（含骨架分析與音訊提取）
  Future<void> _importExternalVideo({
    required String path,
    String? fileName,
    required int fileSize,
  }) async {
    if (!mounted) return;

    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備中...'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('影片分析中', style: TextStyle(color: Colors.white)),
          content: ValueListenableBuilder<(double, String)>(
            valueListenable: progressNotifier,
            builder: (_, val, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: val.$1,
                  backgroundColor: Colors.grey[700],
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                Text(
                  val.$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final existing = await RecordingHistoryStorage.instance.loadHistory();
      final nextRoundIndex = ExternalVideoImporter.calculateNextRoundIndex(existing);

      final entry = await _videoImporter.importVideo(
        sourcePath: path,
        originalName: fileName,
        nextRoundIndex: nextRoundIndex,
        onProgress: (prog, label) => progressNotifier.value = (prog, label),
      );

      if (!mounted) return;
      Navigator.pop(context); // 關閉進度 Dialog

      if (entry == null) {
        _showNotification(
          message: '❌ 導入失敗\n檔案可能不存在或格式不支援',
          type: NotificationType.failed,
          duration: const Duration(seconds: 3),
        );
        return;
      }

      final updated = <RecordingHistoryEntry>[entry, ...existing];
      await RecordingHistoryStorage.instance.saveHistory(updated);

      if (!mounted) return;

      final durationStr = _formatDuration(entry.durationSeconds);
      _showNotification(
        message: '✅ 導入成功！\n${entry.customName ?? fileName}\n時長: $durationStr',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );

      widget.onVideoImported?.call();
      debugPrint('[RecordingSelection] 本地影片導入完成: ${entry.filePath}');
    } catch (e) {
      debugPrint('[RecordingSelection] 本地影片導入失敗: $e');
      if (mounted) {
        Navigator.pop(context); // 關閉進度 Dialog
        _showNotification(
          message: '❌ 導入出錯\n$e',
          type: NotificationType.failed,
          duration: const Duration(seconds: 3),
        );
      }
    } finally {
      progressNotifier.dispose();
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// 顯示通知消息
  void _showNotification({
    required String message,
    required NotificationType type,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        duration: duration,
        backgroundColor: _getNotificationColor(type),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// 根據通知類型返回顏色
  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.selected:
        return const Color(0xFF2196F3); // 藍色 - 已選擇
      case NotificationType.importing:
        return const Color(0xFFFFA500); // 橙色 - 導入中
      case NotificationType.success:
        return const Color(0xFF4CAF50); // 綠色 - 成功
      case NotificationType.failed:
        return const Color(0xFFE53935); // 紅色 - 失敗
      case NotificationType.cancelled:
        return const Color(0xFF757575); // 灰色 - 已取消
    }
  }

  /// 格式化視頻時長
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: const SizedBox.shrink(),
        centerTitle: true,
        title: const Text(
          '選擇錄製方式',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: _isImporting 
        ? _buildLoadingOverlay()
        : _buildSelectionUI(),
    );
  }

  /// 加載中的覆蓋層
  Widget _buildLoadingOverlay() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7C3AED)),
            strokeWidth: 3,
          ),
          const SizedBox(height: 24),
          Text(
            '正在導入影片...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請勿關閉應用',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 選擇 UI
  Widget _buildSelectionUI() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 選項 1: 開始錄製
              _buildSelectionCard(
                emoji: '🎥',
                title: '開始錄製',
                subtitle: '即時拍攝並分析',
                description: 'Start Live Recording',
                onTap: _startRecording,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(height: 32),
              
              // 選項 2: 選擇本地影片
              _buildSelectionCard(
                emoji: '📂',
                title: '選擇本地影片',
                subtitle: '從設備選擇已有影片',
                description: 'Select Local Video',
                onTap: _selectLocalVideo,
                color: const Color(0xFF7C3AED),
              ),
              const SizedBox(height: 32),

              // 選項 3: 從分享連結取得
              _buildSelectionCard(
                emoji: '🔗',
                title: '從分享連結取得',
                subtitle: '輸入 16 碼分享碼下載影片',
                description: 'Import from Share Code',
                onTap: _importFromShare,
                color: const Color(0xFF1565C0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCard({
    required String emoji,
    required String title,
    required String subtitle,
    required String description,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  // 表情符號
                  Text(
                    emoji,
                    style: const TextStyle(fontSize: 56),
                  ),
                  const SizedBox(height: 16),
                  
                  // 標題
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // 副標題
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 英文說明
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
