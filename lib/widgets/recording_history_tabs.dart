import 'dart:io';
import 'package:flutter/material.dart';
import '../models/recording_history_entry.dart';

/// 錄影歷史列表顯示組件
///
/// 顯示所有本地錄影（按時間排序），
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

  const RecordingHistoryTabs({
    Key? key,
    required this.entries,
    required this.itemBuilder,
    this.onEntryTapped,
  }) : super(key: key);

  @override
  State<RecordingHistoryTabs> createState() => _RecordingHistoryTabsState();
}

class _RecordingHistoryTabsState extends State<RecordingHistoryTabs> {
  /// 取得所有錄影清單（按時間降序）
  List<RecordingHistoryEntry> get sortedEntries => List<RecordingHistoryEntry>.from(widget.entries)
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  @override
  Widget build(BuildContext context) {
    final entries = sortedEntries;

    return Scaffold(
      appBar: AppBar(
        title: Text('錄影歷史 (${entries.length})'),
        centerTitle: true,
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '沒有錄影紀錄',
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
            )
          : ListView.builder(
              itemCount: entries.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: _buildEntryCard(context, entry, index),
                );
              },
            ),
    );
  }

  /// 構建單項錄影卡片
  Widget _buildEntryCard(
      BuildContext context, RecordingHistoryEntry entry, int index) {
    return GestureDetector(
      onTap: () => widget.onEntryTapped?.call(entry),
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            // 標題與資訊列
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
                  // 標題、時間
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
                          '模式：${entry.videoType.label}',
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
