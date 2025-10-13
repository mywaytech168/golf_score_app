import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recording_history_entry.dart';
import '../services/recording_history_storage.dart';
import 'recording_session_page.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, editDuration, delete }

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

  /// 返回上一頁並帶出更新後的清單
  void _finishWithResult() {
    Navigator.of(context).pop(List<RecordingHistoryEntry>.from(_entries));
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

    setState(() {
      _entries.removeWhere((item) =>
          item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    });

    await _removeEntryFiles(entry);
    await RecordingHistoryStorage.instance.saveHistory(_entries);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已刪除 ${entry.fileName}')),
    );
  }

  /// 顯示輸入框調整秒數並更新記錄
  Future<void> _editEntryDuration(RecordingHistoryEntry entry) async {
    final controller = TextEditingController(text: entry.durationSeconds.toString());
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
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '秒數',
                helperText: '輸入影片實際秒數（正整數）',
              ),
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
                final parsed = int.parse(controller.text.trim());
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || newDuration == null) {
      return;
    }

    final index = _entries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (index == -1) {
      return;
    }

    if (_entries[index].durationSeconds == newDuration) {
      return; // 秒數未變更時略過更新
    }

    setState(() {
      _entries[index] = _entries[index].copyWith(durationSeconds: newDuration);
    });

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
    final controller = TextEditingController(text: initialText);
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
              controller: controller,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: '影片名稱',
                helperText: '可留空以恢復預設名稱',
              ),
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
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || newName == null) {
      return;
    }

    final normalizedName = newName.trim();
    final storedName = normalizedName.isEmpty ? '' : normalizedName;

    final index = _entries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (index == -1) {
      return;
    }

    final originalName = (_entries[index].customName ?? '').trim();
    if (storedName == originalName) {
      return; // 名稱未變更時不更新檔案
    }

    final defaultTitle = entry.copyWith(customName: '').displayTitle;

    setState(() {
      _entries[index] = _entries[index].copyWith(customName: storedName);
    });

    await RecordingHistoryStorage.instance.saveHistory(_entries);

    if (!mounted) return;
    final snackMessage = storedName.isEmpty
        ? '已恢復影片名稱為 $defaultTitle'
        : '已將影片命名為 $storedName';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackMessage)),
    );
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
                    onDelete: () => _deleteEntry(entry),
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
  final VoidCallback onDelete; // 刪除影片紀錄

  const _HistoryTile({
    required this.entry,
    required this.formattedTime,
    required this.onTap,
    required this.onRename,
    required this.onEditDuration,
    required this.onDelete,
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
            const SizedBox(width: 4),
            PopupMenuButton<_HistoryMenuAction>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert, color: Color(0xFF123B70)),
              onSelected: (action) {
                switch (action) {
                  case _HistoryMenuAction.rename:
                    onRename();
                    break;
                  case _HistoryMenuAction.editDuration:
                    onEditDuration();
                    break;
                  case _HistoryMenuAction.delete:
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.rename,
                  child: Text('重新命名'),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.editDuration,
                  child: Text('調整時長'),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.delete,
                  child: Text('刪除影片'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
