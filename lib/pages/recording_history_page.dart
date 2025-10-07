import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/recording_history_entry.dart';
import 'recording_session_page.dart';

/// 錄影歷史獨立頁面：集中顯示所有曾經錄影的檔案，供使用者重播或挑選外部影片
class RecordingHistoryPage extends StatefulWidget {
  final List<RecordingHistoryEntry> entries; // 外部帶入的歷史資料清單

  const RecordingHistoryPage({super.key, required this.entries});

  @override
  State<RecordingHistoryPage> createState() => _RecordingHistoryPageState();
}

class _RecordingHistoryPageState extends State<RecordingHistoryPage> {
  late final List<RecordingHistoryEntry> _entries =
      List<RecordingHistoryEntry>.from(widget.entries); // 本地複製一份資料避免直接修改來源

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
      MaterialPageRoute(builder: (_) => VideoPlayerPage(videoPath: path)),
    );
  }

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('錄影歷史'),
        actions: [
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
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _entries.length,
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

  const _HistoryTile({
    required this.entry,
    required this.formattedTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF123B70),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                entry.roundIndex.toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF123B70),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$formattedTime · ${entry.durationSeconds} 秒 · ${entry.modeLabel}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6F7B86)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.fileName,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9AA6B2)),
                  ),
                  if (entry.hasImuCsv) ...[
                    const SizedBox(height: 4),
                    Text(
                      'IMU CSV：${entry.csvFileNames.join(', ')}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF4F5D75)),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.play_arrow_rounded, color: Color(0xFF1E8E5A), size: 32),
          ],
        ),
      ),
    );
  }
}
