import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:video_player/video_player.dart';
// restored original local VideoPlayerPage usage
import '../models/recording_history_entry.dart';
import '../models/hits_summary.dart';
import '../models/swing_hit.dart';
import '../services/recording_history_storage.dart';
import '../services/hits_summary_storage.dart';
import '../services/swing_impact_detector.dart';
import '../widgets/hits_summary_widget.dart';
import 'video_player_page.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, detectHits, delete }

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
  List<RecordingHistoryEntry> _entries = [];
  bool _isLoading = true;
  bool _rebuildScheduled = false; // 避免重複排程 setState 造成框架錯誤
  bool? _selectedGoodShot; // 好球/壞球篩選 - null: 全部, true: 好球, false: 壞球
  _SortBy _sortBy = _SortBy.date; // 排序選項，預設按時間排序

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final loaded = await RecordingHistoryStorage.instance.loadHistory();
    if (!mounted) return;
    setState(() {
      _entries = loaded;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    super.dispose();
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

    // 移除本地檔案
    await _removeEntryFiles(entry);

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

  /// 刪除整個 session 目錄（影片、CSV、音訊、hits.json、縮圖等）
  Future<void> _removeEntryFiles(RecordingHistoryEntry entry) async {
    try {
      final sessionDir = Directory(p.dirname(entry.filePath));
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
        return;
      }
    } catch (_) {}

    // fallback：session 目錄刪除失敗時逐一清除已知檔案
    final filesToDelete = [
      entry.filePath,
      if (entry.thumbnailPath != null && entry.thumbnailPath!.isNotEmpty)
        entry.thumbnailPath!,
    ];
    for (final path in filesToDelete) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
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
  Future<void> _playVideoByPath(String path, {String? missingFileName}) async {
    // 检查本地文件
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
    return null;
  }

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('錄影歷史')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
                          key: ValueKey(entry.filePath),
                          entry: entry,
                          formattedTime: _formatTimestamp(entry.recordedAt),
                          onTap: () => _playEntry(entry),
                          onRename: () => _renameEntry(entry),
                          onDelete: () => _deleteEntry(entry),
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
  final VoidCallback onDelete; // 刪除影片紀錄

  const _HistoryTile({
    super.key,
    required this.entry,
    required this.formattedTime,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late Future<List<HitsSummary>> _hitsSummaryFuture;
  late Future<List<SwingHit>> _swingHitsFuture;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _loadHitsSummary();
    _swingHitsFuture = SwingHit.loadFromSession(p.dirname(widget.entry.filePath));
  }

  @override
  void didUpdateWidget(_HistoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.filePath != widget.entry.filePath) {
      _loadHitsSummary();
      _swingHitsFuture = SwingHit.loadFromSession(p.dirname(widget.entry.filePath));
    }
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

  /// 執行擊球偵測：讀取 pose CSV 與可選音頻 PCM，
  /// 呼叫 SwingImpactDetector，將結果存入 hits.json 並刷新面板。
  Future<void> _runDetection() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);

    try {
      final sessionDir = p.dirname(widget.entry.filePath);
      final csvPath = p.join(sessionDir, 'pose_landmarks.csv');

      // 嘗試讀取原始 float32 PCM（若存在）
      List<double> audioPcm = [];
      const int sampleRate = 44100;
      final pcmFile = File(p.join(sessionDir, 'audio.pcm'));
      if (await pcmFile.exists()) {
        final bytes = await pcmFile.readAsBytes();
        final byteData = bytes.buffer.asByteData();
        audioPcm = List<double>.generate(
          bytes.length ~/ 4,
          (i) => byteData.getFloat32(i * 4, Endian.little),
        );
      }

      final hits = await SwingImpactDetector.detect(
        csvPath: csvPath,
        audioPcm: audioPcm,
        audioSampleRate: sampleRate,
      );

      await SwingHit.saveToSession(sessionDir, hits);

      if (!mounted) return;
      setState(() {
        _swingHitsFuture = Future.value(hits);
        _isDetecting = false;
      });

      final msg = hits.isEmpty ? '未偵測到擊球（請確認 pose CSV 資料）' : '偵測到 ${hits.length} 次擊球 ✅';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      debugPrint('[偵測擊球] 錯誤: $e');
      if (!mounted) return;
      setState(() => _isDetecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('偵測失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                        case _HistoryMenuAction.detectHits:
                          _runDetection();
                          break;
                        case _HistoryMenuAction.delete:
                          widget.onDelete();
                          break;
                      }
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.rename,
                      child: Text('重新命名'),
                    ),
                    PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.detectHits,
                      child: Row(
                        children: [
                          Text(
                            _isDetecting ? '偵測中...' : '偵測擊球',
                            style: TextStyle(
                              color: _isDetecting ? Colors.grey : null,
                            ),
                          ),
                          if (_isDetecting) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
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
                    '${widget.formattedTime} · ${widget.entry.durationSeconds} 秒',
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
            // 第三行：聲音清脆度
            if (widget.entry.audioCrispness != null)
              Row(
                children: [
                  const Icon(Icons.music_note, size: 14, color: Color(0xFFFF6F00)),
                  const SizedBox(width: 4),
                  Text(
                    '清脆度: ${widget.entry.audioCrispness!.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFFF6F00), fontWeight: FontWeight.w500),
                  ),
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
            // 擊球偵測列表
            if (_isDetecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '正在偵測擊球...',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
                    ),
                  ],
                ),
              )
            else
              FutureBuilder<List<SwingHit>>(
                future: _swingHitsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _SwingHitsPanel(
                    hits: snapshot.data!,
                    videoPath: widget.entry.filePath,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 擊球偵測列表面板：可收合，每筆顯示時間範圍與跳轉播放按鈕
class _SwingHitsPanel extends StatelessWidget {
  final List<SwingHit> hits;
  final String videoPath;

  const _SwingHitsPanel({required this.hits, required this.videoPath});

  String _fmtSec(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toStringAsFixed(1);
    return m > 0 ? '$m:${s.padLeft(4, '0')}' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Row(
          children: [
            const Icon(Icons.sports_golf, size: 16, color: Color(0xFF1E8E5A)),
            const SizedBox(width: 6),
            Text(
              '偵測到 ${hits.length} 次擊球',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E8E5A),
              ),
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          ...hits.map((hit) => _HitRow(hit: hit, videoPath: videoPath, fmtSec: _fmtSec)),
        ],
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final SwingHit hit;
  final String videoPath;
  final String Function(double) fmtSec;

  const _HitRow({required this.hit, required this.videoPath, required this.fmtSec});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1E8E5A).withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${hit.hitIndex}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E8E5A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${fmtSec(hit.startSec)} – ${fmtSec(hit.endSec)}  ·  撞擊 ${fmtSec(hit.hitSec)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF4F5D75)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline, size: 22, color: Color(0xFF1976D2)),
            tooltip: '從擊球點播放',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoPlayerPage(
                    videoPath: videoPath,
                    startPosition: hit.startDuration,
                  ),
                ),
              );
            },
          ),
        ],
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
