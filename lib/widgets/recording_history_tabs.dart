import 'dart:io';
import 'package:flutter/material.dart';
import '../models/recording_history_entry.dart';

/// 本地與雲端錄影歷史的分頁顯示組件
/// 
/// 使用 TabBar 來分別展示：
/// 1. 本地錄影 (UploadStatus.local/failed)
/// 2. 雲端錄影 (UploadStatus.uploaded)
/// 
/// 支援自訂列表項目構建器，由上層決定單項列表如何顯示與互動
class RecordingHistoryTabs extends StatefulWidget {
  /// 完整的錄影歷史清單
  final List<RecordingHistoryEntry> entries;

  /// 用於構建單項列表項目的回呼函數
  /// 
  /// 參數：
  /// - context: 當前組件上下文
  /// - entry: 單項錄影紀錄
  /// - index: 在該分類清單中的索引（0 開始）
  final Widget Function(BuildContext context, RecordingHistoryEntry entry,
      int index) itemBuilder;

  /// 當使用者點擊某項時的回呼（可選）
  final Function(RecordingHistoryEntry)? onEntryTapped;

  /// 是否顯示上傳進度和錯誤狀態
  final bool showUploadStatus;

  const RecordingHistoryTabs({
    Key? key,
    required this.entries,
    required this.itemBuilder,
    this.onEntryTapped,
    this.showUploadStatus = true,
  }) : super(key: key);

  @override
  State<RecordingHistoryTabs> createState() => _RecordingHistoryTabsState();
}

class _RecordingHistoryTabsState extends State<RecordingHistoryTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 取得本地錄影清單（未上傳或上傳失敗）
  List<RecordingHistoryEntry> get localEntries => widget.entries
      .where((e) =>
          e.uploadStatus == UploadStatus.local ||
          e.uploadStatus == UploadStatus.failed)
      .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  /// 取得雲端錄影清單（已上傳）
  List<RecordingHistoryEntry> get cloudEntries => widget.entries
      .where((e) => e.uploadStatus == UploadStatus.uploaded)
      .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  @override
  Widget build(BuildContext context) {
    final localCount = localEntries.length;
    final cloudCount = cloudEntries.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('錄影歷史'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📱 本地'),
                  Text(
                    '($localCount)',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Tab(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('☁️ 雲端'),
                  Text(
                    '($cloudCount)',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 本地錄影頁籤
          _buildLocalTab(context),
          // 雲端錄影頁籤
          _buildCloudTab(context),
        ],
      ),
    );
  }

  /// 構建本地錄影頁籤
  Widget _buildLocalTab(BuildContext context) {
    if (localEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '沒有本地錄影',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '完成新的錄影後，將在此顯示',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: localEntries.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final entry = localEntries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _buildEntryCard(context, entry, index),
        );
      },
    );
  }

  /// 構建雲端錄影頁籤
  Widget _buildCloudTab(BuildContext context) {
    if (cloudEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '還沒有上傳錄影',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '從本地頁籤上傳您的錄影',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: cloudEntries.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final entry = cloudEntries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _buildEntryCard(context, entry, index),
        );
      },
    );
  }

  /// 構建單項錄影卡片，包含狀態與操作按鈕
  Widget _buildEntryCard(
      BuildContext context, RecordingHistoryEntry entry, int index) {
    return GestureDetector(
      onTap: () => widget.onEntryTapped?.call(entry),
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            // 標題與狀態列
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 縮圖或佔位符
                  if (entry.thumbnailPath != null &&
                      entry.thumbnailPath!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(entry.thumbnailPath!),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildThumbnailPlaceholder(),
                      ),
                    )
                  else
                    _buildThumbnailPlaceholder(),
                  const SizedBox(width: 12),
                  // 標題、時間、狀態
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayTitle,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDateTime(entry.recordedAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                        const SizedBox(height: 4),
                        if (widget.showUploadStatus)
                          _buildStatusBadge(entry),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 分隔線
            const Divider(height: 1, indent: 12, endIndent: 12),
            // 詳細資訊與操作
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '模式：${entry.modeLabel}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      Text(
                        '時長：${entry.durationSeconds}秒',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 自訂項目構建器
                  widget.itemBuilder(context, entry, index),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 構建縮圖佔位符
  Widget _buildThumbnailPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.videocam,
        color: Colors.grey[600],
        size: 30,
      ),
    );
  }

  /// 構建上傳狀態徽章
  Widget _buildStatusBadge(RecordingHistoryEntry entry) {
    final statusColor = _getStatusColor(entry.uploadStatus);
    final statusLabel = entry.uploadStatus.badge;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(30),
        border: Border.all(color: statusColor, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (entry.uploadStatus == UploadStatus.uploading) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(statusColor),
              ),
            ),
          ],
          if (entry.uploadStatus == UploadStatus.failed &&
              entry.uploadError != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: entry.uploadError!,
              child: Icon(
                Icons.info_outline,
                size: 12,
                color: statusColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 根據上傳狀態取得顏色
  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.local:
        return Colors.blue;
      case UploadStatus.uploading:
        return Colors.orange;
      case UploadStatus.uploaded:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
    }
  }

  /// 格式化日期時間顯示
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

    String dayPart;
    if (targetDay == today) {
      dayPart = '今天';
    } else if (targetDay == today.subtract(const Duration(days: 1))) {
      dayPart = '昨天';
    } else {
      dayPart = '${dateTime.month}月${dateTime.day}日';
    }

    return '$dayPart ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
