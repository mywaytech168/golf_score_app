import 'package:flutter/material.dart';

import '../models/recording_history_entry.dart';

/// 自訂底部彈窗，統一顯示錄影歷史列表與播放行為
Future<void> showRecordingHistorySheet({
  required BuildContext context,
  required List<RecordingHistoryEntry> entries,
  required ValueChanged<RecordingHistoryEntry> onPlayEntry,
  VoidCallback? onPickExternal,
  String title = '曾經錄影紀錄',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final displayEntries = List<RecordingHistoryEntry>.from(entries);

      return FractionallySizedBox(
        heightFactor: 0.7,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF123B70),
                  ),
                ),
                const SizedBox(height: 16),
                if (displayEntries.isEmpty)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.video_collection_outlined, size: 56, color: Color(0xFF9AA6B2)),
                        SizedBox(height: 12),
                        Text(
                          '目前沒有錄影紀錄，完成錄影後會自動顯示在此處。',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6F7B86)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: displayEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = displayEntries[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            onPlayEntry(entry);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F7FB),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF123B70),
                                  child: Text(
                                    entry.roundIndex.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.displayTitle,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF123B70),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _buildSubtitle(entry),
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.play_arrow_rounded, color: Color(0xFF1E8E5A), size: 28),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (onPickExternal != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onPickExternal();
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: const Color(0xFF123B70),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('從檔案資料夾選取影片'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 將錄影紀錄的時間與模式組合成描述文字
String _buildSubtitle(RecordingHistoryEntry entry) {
  final buffer = StringBuffer()
    ..write(_formatTimestamp(entry.recordedAt))
    ..write(' · ')
    ..write('${entry.durationSeconds}\u0020秒')
    ..write(' · ')
    ..write(entry.modeLabel)
    ..write('\n')
    ..write(entry.fileName);
  if (entry.hasImuCsv) {
    buffer
      ..write('\n')
      ..write('IMU CSV：')
      ..write(entry.csvFileNames.join(', '));
  }
  return buffer.toString();
}

/// 以簡潔格式顯示日期時間，避免依賴額外套件
String _formatTimestamp(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.year}/$month/$day $hour:$minute';
}
