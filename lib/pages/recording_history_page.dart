import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import '../models/hits_summary.dart';
import '../services/recording_history_storage.dart';
import '../services/hits_summary_storage.dart';
import '../services/swing_impact_detector.dart';
import '../services/clip_pipeline_service.dart';
import '../services/video_analysis_pipeline_service.dart';
import '../services/audio_export_service.dart';
import '../services/audio_export_models.dart';
import '../services/audio_extraction_service.dart';
import '../services/ad_service.dart';
import '../services/plan_service.dart';
import '../widgets/hits_summary_widget.dart';
import '../widgets/green_page_header.dart';
import 'video_comparison_page.dart';
import 'video_player_page.dart';
import 'recording_detail_page.dart';
import '../widgets/share_upload_dialog.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, detectHits, analyze, compare, share, resetAnalysisState, resetClippingState, delete }

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
  final VoidCallback? onDelete; // 影片刪除時的回調，供父頁面即時刷新

  const RecordingHistoryPage({
    super.key,
    required this.entries,
    this.userAvatarPath,
    this.onDelete,
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

  /// 移除指定紀錄並同步刪除實體檔案
  Future<void> _deleteEntry(RecordingHistoryEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('刪除影片'),
          content: Text(
        entry.videoType == VideoType.localClip
            ? '確定要刪除切片「${entry.displayTitle}」嗎？'
            : '確定要刪除「${entry.displayTitle}」嗎？影片、CSV 及所有切片將一併移除。',
      ),
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

    // 移除檔案
    await _removeEntryFiles(entry);

    _entries.removeAt(index);
    if (mounted) {
      debugPrint('[歷史頁] 刪除後立即刷新列表，剩餘 ${_entries.length} 筆');
      setState(() {}); // 通知畫面重新渲染
      
      // 通知父頁面即時更新（不需要等返回）
      widget.onDelete?.call();
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

  /// 擊球偵測完成後，將切片加入歷史清單並標記來源影片為已切片
  void _onClipsGenerated(RecordingHistoryEntry original, List<RecordingHistoryEntry> clips) {
    final idx = _entries.indexWhere((e) => e.filePath == original.filePath);
    if (idx != -1) {
      _entries[idx] = _entries[idx].copyWith(isClipped: true);
    }
    _entries.addAll(clips);
    setState(() {});
    RecordingHistoryStorage.instance.saveHistory(_entries);
  }

  /// 影片分析完成後，以新版 entry 取代舊版
  void _onEntryUpdated(RecordingHistoryEntry oldEntry, RecordingHistoryEntry newEntry) {
    final idx = _entries.indexWhere((e) => e.filePath == oldEntry.filePath);
    if (idx != -1) {
      _entries[idx] = newEntry;
      setState(() {});
      RecordingHistoryStorage.instance.saveHistory(_entries);
    }
  }

  /// 刪除 session 目錄或切片檔案
  Future<void> _removeEntryFiles(RecordingHistoryEntry entry) async {
    if (entry.videoType == VideoType.localClip) {
      // 切片刪除整個 session 目錄（golf_recordings/{session}_hit_n/）
      try {
        final clipSessionDir = Directory(p.dirname(entry.filePath));
        if (await clipSessionDir.exists()) {
          await clipSessionDir.delete(recursive: true);
          return;
        }
      } catch (_) {}
      // fallback：逐一刪除已知檔案
      for (final path in [
        entry.filePath,
        if (entry.thumbnailPath != null && entry.thumbnailPath!.isNotEmpty)
          entry.thumbnailPath!,
      ]) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      return;
    }

    // 原始影片：刪除整個 session 目錄（含 clips 子目錄）
    try {
      final sessionDir = Directory(p.dirname(entry.filePath));
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
        return;
      }
    } catch (_) {}

    // fallback：session 目錄刪除失敗時逐一清除已知檔案
    for (final path in [
      entry.filePath,
      if (entry.thumbnailPath != null && entry.thumbnailPath!.isNotEmpty)
        entry.thumbnailPath!,
    ]) {
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
    final file = File(entry.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('找不到影片檔案 ${entry.fileName}，請確認檔案是否仍存在於裝置內。')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoPath: entry.filePath,
          avatarPath: widget.userAvatarPath,
          entry: entry,
        ),
      ),
    );
  }

  /// 顯示影片紀錄的 JSON debug 資訊
  Future<void> _showDebugJsonInfo() async {
    if (!mounted) return;
    
    try {
      // 將所有紀錄轉換為格式化的 JSON（帶換行和縮進）
      final jsonList = _entries.map((entry) => entry.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
      
      if (!mounted) return;
      
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('影片紀錄 (JSON Debug)'),
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

  /// 根據排序選項對條目進行排序
  List<RecordingHistoryEntry> _sortEntries(List<RecordingHistoryEntry> entries) {
    final sorted = List<RecordingHistoryEntry>.from(entries);
    
    switch (_sortBy) {
      case _SortBy.date:
        // 按時間排序（最新優先）
        sorted.sort((a, b) => b.sortTime.compareTo(a.sortTime));
        break;
      
      case _SortBy.peakValue:
        // 按最佳速度排序（最高優先）
        sorted.sort((a, b) {
          // 取得每個條目的最高峰值
          final maxPeakA = _getMaxPeakValue(a);
          final maxPeakB = _getMaxPeakValue(b);
          
          // 如果都沒有數據，則按時間排序
          if (maxPeakA == null && maxPeakB == null) {
            return b.sortTime.compareTo(a.sortTime);
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
            return b.sortTime.compareTo(a.sortTime);
          }
          
          // 較高的排前面
          return crispnessB.compareTo(crispnessA);
        });
        break;
    }
    
    return sorted;
  }

  /// 使用 audioCrispness 作為音質峰值排序依據
  double? _getMaxPeakValue(RecordingHistoryEntry entry) {
    return entry.audioCrispness;
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

    // 統計文字
    final goodCount = _entries.where((e) => e.goodShot == true).length;
    final badCount  = _entries.where((e) => e.goodShot == false).length;
    final subtitle  = _isLoading
        ? '載入中…'
        : '共 ${_entries.length} 筆 · 好球 $goodCount · 壞球 $badCount';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finishWithResult();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        body: Column(
          children: [
            // ── 綠色頂部面板 ─────────────────────────────────────
            GreenPageHeader(
              title: '歷史錄影',
              subtitle: subtitle,
              actions: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  )
                else
                  IconButton(
                    onPressed: _showDebugJsonInfo,
                    tooltip: 'Debug',
                    icon: const Icon(Icons.bug_report_outlined, color: Colors.white),
                  ),
              ],
            ),
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
                          formattedImportTime: entry.createdAt != null
                              ? _formatTimestamp(entry.createdAt!)
                              : null,
                          onTap: () => _playEntry(entry),
                          onRename: () => _renameEntry(entry),
                          onDelete: () => _deleteEntry(entry),
                          onClipsGenerated: _onClipsGenerated,
                          onEntryUpdated: _onEntryUpdated,
                          allEntries: _entries,
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
  final String formattedTime; // 原始錄製時間（已格式化）
  final String? formattedImportTime; // 匯入本機時間；僅匯入影片有值
  final VoidCallback onTap; // 點擊後的播放行為
  final VoidCallback onRename; // 重新命名影片
  final VoidCallback onDelete; // 刪除影片紀錄
  /// 擊球偵測完成並裁切片段後的回呼，帶入來源影片與新切片清單
  final void Function(RecordingHistoryEntry original, List<RecordingHistoryEntry> clips)? onClipsGenerated;
  /// 影片分析完成後，以新版 entry 取代舊版
  final void Function(RecordingHistoryEntry old, RecordingHistoryEntry updated)? onEntryUpdated;
  /// 用於比較模式的所有其他 entry（過濾後供選擇第二部影片）
  final List<RecordingHistoryEntry> allEntries;

  const _HistoryTile({
    super.key,
    required this.entry,
    required this.formattedTime,
    this.formattedImportTime,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onClipsGenerated,
    this.onEntryUpdated,
    this.allEntries = const [],
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late Future<List<HitsSummary>> _hitsSummaryFuture;
  bool _isDetecting = false;
  bool _isAnalyzing = false;
  bool get _isLongVideo => widget.entry.durationSeconds > 5 && widget.entry.durationSeconds <= 120;
  bool get _isOriginalVideo => widget.entry.videoType == VideoType.original;
  bool get _isClip => widget.entry.videoType == VideoType.localClip;
  bool get _isAnalyzed => widget.entry.isAnalyzed;

  @override
  void initState() {
    super.initState();
    _loadHitsSummary();
  }

  @override
  void didUpdateWidget(_HistoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.filePath != widget.entry.filePath) {
      _loadHitsSummary();
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

  /// 執行擊球偵測 → 裁切片段（顯示進度對話框）
  /// 前置條件：必須先進行骨架分析與音訊提取
  Future<void> _runDetection() async {
    // 檢查是否已經切片過
    if (widget.entry.isClipped) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('此影片已經切片過，無法重複切片'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isDetecting) return;
    setState(() => _isDetecting = true);

    if (!mounted) return;

    // 在第一個 await 之前捕捉 navigator/messenger，確保 Dialog 一定能關閉
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備骨架分析...'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('擊球偵測中', style: TextStyle(color: Colors.white)),
          content: ValueListenableBuilder<(double, String)>(
            valueListenable: progressNotifier,
            builder: (_, val, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: val.$1,
                  backgroundColor: Colors.grey[700],
                  color: Colors.blue,
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

    // Free 方案：在分析期間插播廣告（fire-and-forget，不阻塞進度）
    final detectionPlan = await PlanService.getPlanStatus();
    if (detectionPlan.plan == UserPlan.free) {
      unawaited(AdService.showInterstitialAd());
    }

    try {
      final sessionDir = p.dirname(widget.entry.filePath);
      final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
      final audioPath = p.join(sessionDir, 'audio.wav');

      // 1. 確保骨架與音訊已分析（若無則先進行基礎分析）
      if (!await File(csvPath).exists()) {
        debugPrint('[偵測擊球] CSV 不存在，先執行基礎分析...');
        final durationSeconds = widget.entry.durationSeconds;
        final basicAnalysis = await VideoAnalysisPipelineService.analyzeBasic(
          videoPath: widget.entry.filePath,
          sessionDir: sessionDir,
          durationSeconds: durationSeconds,
          onProgress: (label) {
            progressNotifier.value = (0.3, label);
          },
        );
        if (basicAnalysis == null) {
          throw '基礎分析失敗：無法生成骨架';
        }
      }

      // 2. 讀取 WAV 並轉換為 PCM
      progressNotifier.value = (0.35, '載入音訊中...');
      List<double> audioPcm = [];
      const int sampleRate = 44100;
      final wavFile = File(audioPath);
      bool audioHasSilence = false;
      
      debugPrint('[偵測擊球] 📂 WAV 路徑: $audioPath');
      debugPrint('[偵測擊球] 📂 CSV 路徑: $csvPath');
      debugPrint('[偵測擊球] 📂 CSV 存在: ${await File(csvPath).exists()}');
      debugPrint('[偵測擊球] 📂 WAV 存在: ${await wavFile.exists()}');
      
      if (await wavFile.exists()) {
        final wavBytes = await wavFile.readAsBytes();
        debugPrint('[偵測擊球] 🔊 WAV 大小: ${wavBytes.length} bytes');
        
        if (wavBytes.length >= 44) {
          // 🔧 解析 WAV 头
          int dataStart = 44;
          for (int i = 36; i < wavBytes.length - 8; i++) {
            if (wavBytes[i] == 100 && wavBytes[i + 1] == 97 &&
                wavBytes[i + 2] == 116 && wavBytes[i + 3] == 97) {
              dataStart = i + 8;
              break;
            }
          }
          
          debugPrint('[偵測擊球] 🔧 WAV data 開始位置: $dataStart');
          
          // 🔧 转换 int16 → float32
          final audioDataBytes = wavBytes.sublist(dataStart);
          debugPrint('[偵測擊球] 🔧 PCM 數據大小: ${audioDataBytes.length} bytes');
          
          if (audioDataBytes.isEmpty) {
            debugPrint('[偵測擊球] ⚠️ 【無聲音】WAV data 為空');
            audioHasSilence = true;
          } else {
            double rmsSum = 0.0;
            double peakVal = 0.0;
            
            for (int i = 0; i < audioDataBytes.length - 1; i += 2) {
              final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);
              final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
              final normalized = signedInt16 / 32768.0;
              audioPcm.add(normalized);
              rmsSum += normalized * normalized;
              if (normalized.abs() > peakVal) peakVal = normalized.abs();
            }
            
            debugPrint('[偵測擊球] ✅ PCM 轉換完成: ${audioPcm.length} 樣本');
            
            // 📊 PCM 統計與無聲音檢測
            if (audioPcm.isNotEmpty) {
              final rms = math.sqrt(rmsSum / audioPcm.length);
              final minVal = audioPcm.reduce((a, b) => a < b ? a : b);
              final maxVal = audioPcm.reduce((a, b) => a > b ? a : b);
              debugPrint('[偵測擊球] 📊 PCM 範圍: [$minVal, $maxVal], RMS=${rms.toStringAsFixed(4)}, Peak=${peakVal.toStringAsFixed(4)}');
              
              // 檢測無聲音：RMS < 0.01 且峰值 < 0.05
              if (rms < 0.01 && peakVal < 0.05) {
                debugPrint('[偵測擊球] ⚠️ 【無聲音】RMS=${rms.toStringAsFixed(4)} < 0.01, Peak=${peakVal.toStringAsFixed(4)} < 0.05');
                audioHasSilence = true;
              }
            }
          }
        } else {
          debugPrint('[偵測擊球] ⚠️ 【無聲音】WAV 檔案過小 (${wavBytes.length} < 44 bytes)');
          audioHasSilence = true;
        }
      } else {
        debugPrint('[偵測擊球] ⚠️ 【無聲音】WAV 文件不存在: $audioPath');
        audioHasSilence = true;
      }

      // 3. 讀取 CSV 檢查骨架數據
      debugPrint('[偵測擊球] 📋 讀取 CSV 文件...');
      List<String> csvLines = [];
      try {
        csvLines = await File(csvPath).readAsLines();
        debugPrint('[偵測擊球] 📋 CSV 行數: ${csvLines.length}');
        
        // 統計有效骨架
        int validFrames = 0;
        double maxConfidence = 0.0;
        for (int i = 1; i < csvLines.length; i++) {
          final parts = csvLines[i].split(',');
          if (parts.length >= 3) {
            try {
              final conf = double.tryParse(parts[2]) ?? 0.0;
              if (conf > 0) validFrames++;
              if (conf > maxConfidence) maxConfidence = conf;
            } catch (_) {}
          }
        }
        debugPrint('[偵測擊球] 📊 骨架有效幀: $validFrames, 最高信心度: ${maxConfidence.toStringAsFixed(3)}');
      } catch (e) {
        debugPrint('[偵測擊球] ❌ CSV 讀取失敗: $e');
      }
      
      // 4. 偵測擊球
      debugPrint('[偵測擊球] 🔍 開始峰值檢測...');
      progressNotifier.value = (0.5, '偵測擊球中...');
      final hits = await SwingImpactDetector.detect(
        csvPath: csvPath,
        audioPcm: audioPcm,
        audioSampleRate: sampleRate,
      );
      debugPrint('[偵測擊球] 📊 峰值檢測結果: ${hits.length} 個擊球');

      if (!mounted) return;

      // 📊 統計擊球峰值
      if (hits.isNotEmpty) {
        final avgSpeed = hits.fold<double>(0, (s, h) => s + h.speedValue) / hits.length;
        final avgAudio = hits.fold<double>(0, (s, h) => s + h.audioValue) / hits.length;
        final hitFrames = hits.map((h) => h.hitFrame).toList();
        
        debugPrint(
          '[HitDetection] 📊 統計:\n'
          '  偵測擊球數: ${hits.length}\n'
          '  平均速度值: ${avgSpeed.toStringAsFixed(3)}\n'
          '  平均音訊值: ${avgAudio.toStringAsFixed(3)}\n'
          '  擊球幀位置: $hitFrames'
        );
      }

      if (hits.isEmpty) {
        debugPrint('[偵測擊球] ⚠️ 未檢測到任何擊球');
        
        // 額外診斷
        debugPrint('[偵測擊球] 🔧 診斷信息:');
        debugPrint('  - CSV 有效: ${csvLines.isNotEmpty}');
        debugPrint('  - PCM 樣本數: ${audioPcm.length}');
        debugPrint('  - 期望樣本數 (30秒@44.1kHz): ${30 * 44100}');
        debugPrint('  - 【無聲音】: $audioHasSilence');
        debugPrint('  - 期望樣本數 (30秒@44.1kHz): ${30 * 44100}');
        debugPrint('  - 【無聲音】: $audioHasSilence');
        
        Navigator.pop(context);
        setState(() => _isDetecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '未偵測到擊球\n影片中可能無明顯揮桿動作，或骨架分析未能成功辨識',
              style: TextStyle(height: 1.5),
            ),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // 4. 依序裁切
      final results = await ClipPipelineService.run(
        hits: hits,
        srcVideoPath: widget.entry.filePath,
        sourceEntry: widget.entry,
        onProgress: (prog) {
          final percentage = prog.total > 0 
            ? (prog.current / prog.total) * 100 
            : 0;
          progressNotifier.value = (
            0.5 + (percentage / 100) * 0.5,
            '裁切片段中... ${percentage.round()}% (${prog.current}/${prog.total})'
          );
        },
      );

      navigator.pop(); // 無論 mounted 與否，一定關閉 Dialog
      if (mounted) setState(() => _isDetecting = false);

      if (results.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('偵測成功，但片段裁切失敗，請重試')),
        );
        return;
      }

      // 若偵測到無聲音，同步更新來源 entry 的 audioTags
      if (audioHasSilence) {
        final updatedSource = widget.entry.copyWith(audioTags: ['no_audio']);
        widget.onEntryUpdated?.call(widget.entry, updatedSource);
      }

      widget.onClipsGenerated?.call(
        widget.entry,
        results.map((r) => r.entry).toList(),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('已生成 ${results.length} 個擊球片段 ✅\n可對每個切片執行「影片分析」加入骨架與球軌跡'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[偵測擊球] 錯誤: $e');
      navigator.pop();
      if (mounted) setState(() => _isDetecting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('偵測失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      progressNotifier.dispose();
    }
  }

  /// 執行完整分析（視頻 + 音頻），合併結果
  Future<void> _runCombinedAnalysis() async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);

    if (!mounted) return;

    // 在第一個 await 之前捕捉 navigator/messenger，確保 Dialog 一定能關閉
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備中...'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('🎬 完整分析中', style: TextStyle(color: Colors.white)),
          content: ValueListenableBuilder<(double, String)>(
            valueListenable: progressNotifier,
            builder: (_, val, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: val.$1,
                  backgroundColor: Colors.grey[700],
                  color: Colors.cyan,
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

    // Free 方案：在分析期間插播廣告（fire-and-forget，不阻塞進度）
    final analysisPlan = await PlanService.getPlanStatus();
    if (analysisPlan.plan == UserPlan.free) {
      unawaited(AdService.showInterstitialAd());
    }

    try {
      final clipPath = widget.entry.filePath;
      final sessionDir = p.dirname(clipPath);
      final durationSeconds = widget.entry.durationSeconds;

      // 檢查時長有效性
      if (durationSeconds < 5 || durationSeconds > 120) {
        throw '影片時長 ($durationSeconds 秒) 不符合要求 (5-120 秒)';
      }

      // Stage 1: 視頻分析（0-70%）
      debugPrint('[完整分析] 開始視頻分析...');
      progressNotifier.value = (0.0, '視頻分析中...');

      RecordingHistoryEntry? updatedEntry;

      if (_isLongVideo) {
        // 長影片：先進行基礎分析
        debugPrint('[完整分析] 長影片 ($durationSeconds s)：執行基礎分析');
        
        final basicAnalysis = await VideoAnalysisPipelineService.analyzeBasic(
          videoPath: clipPath,
          sessionDir: sessionDir,
          durationSeconds: durationSeconds,
          onProgress: (label) {
            progressNotifier.value = (0.35, label);
          },
        );

        if (basicAnalysis == null) {
          throw '基礎分析失敗';
        }

        updatedEntry = widget.entry.copyWith(isAnalyzed: true);
      } else {
        // 短影片：進行完整分析
        debugPrint('[完整分析] 短影片 ($durationSeconds s)：執行完整分析');
        
        final result = await ClipPipelineService.analyze(
          clipPath: clipPath,
          sessionDir: sessionDir,
          durationSeconds: durationSeconds,
          hitSec: widget.entry.hitSecond,
          onProgress: (label) {
            progressNotifier.value = (0.35, label);
          },
        );

        if (result == null) {
          throw '視頻分析失敗';
        }

        final silenceTags = result.hasSilence ? ['no_audio'] : null;
        updatedEntry = widget.entry.copyWith(
          filePath: result.finalPath,
          isAnalyzed: true,
          audioTags: silenceTags,
        );
      }

      // Stage 2: 音頻分析（70-100%）
      debugPrint('[完整分析] 開始音頻分析...');
      progressNotifier.value = (0.7, '音頻分析中...');

      const int sampleRate = 44100;
      final wavFile = File(p.join(sessionDir, 'audio.wav'));
      debugPrint('[完整分析] WAV 檔案路徑: ${wavFile.path}');
      
      AudioAnalysisResult? audioResult;
      var wavExists = await wavFile.exists();
      
      // 如果 WAV 不存在，尝试从视频提取
      if (!wavExists) {
        debugPrint('[完整分析] 📥 WAV 不存在，尝试从视频提取...');
        progressNotifier.value = (0.72, '从视频提取音频中...');
        
        // 使用原始视频提取音频（clipPath 是导入的或已分析的视频）
        debugPrint('[完整分析] 提取音频源: $clipPath');
        
        final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
          videoPath: clipPath,
          outputWavPath: wavFile.path,
          onProgress: (progress, message) {
            final adjustedProgress = 0.72 + progress * 0.08;
            progressNotifier.value = (adjustedProgress, message);
          },
        );
        
        if (samplesExtracted > 0) {
          debugPrint('[完整分析] ✅ 音频提取成功: $samplesExtracted 样本');
          wavExists = await wavFile.exists();
        } else {
          debugPrint('[完整分析] ⚠️  音频提取失败或系统无FFmpeg支持');
        }
      }
      
      if (wavExists) {
        debugPrint('[完整分析] ✅ WAV 檔案存在');
        try {
          final bytes = await wavFile.readAsBytes();
          debugPrint('[完整分析] WAV 字節數: ${bytes.length}');
          
          if (bytes.isEmpty || bytes.length < 44) {
            debugPrint('[完整分析] ⚠️  WAV 檔案太小');
          } else {
            // 🔧 解析 WAV 头
            int dataStart = 44;
            for (int i = 36; i < bytes.length - 8; i++) {
              if (bytes[i] == 100 && bytes[i + 1] == 97 &&
                  bytes[i + 2] == 116 && bytes[i + 3] == 97) {
                dataStart = i + 8;
                break;
              }
            }
            
            // 🔧 转换 int16 → float32
            final audioDataBytes = bytes.sublist(dataStart);
            final pcmSamples = <double>[];
            
            for (int i = 0; i < audioDataBytes.length - 1; i += 2) {
              final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);
              final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
              pcmSamples.add(signedInt16 / 32768.0);
            }
            
            debugPrint('[完整分析] PCM 樣本數: ${pcmSamples.length}');

            if (pcmSamples.isNotEmpty) {
              debugPrint('[完整分析] 🎵 開始調用 AudioExportService.analyzeFromPcm...');
              audioResult = await AudioExportService.analyzeFromPcm(
                pcmSamples: pcmSamples,
                sessionDir: sessionDir,
                sampleRate: sampleRate,
                onProgress: (progress) {
                  // 調整音頻進度到 80-100% 範圍
                  final adjustedProgress = 0.8 + progress.progress * 0.2;
                  progressNotifier.value = (adjustedProgress, progress.message);
                },
              );
              debugPrint('[完整分析] 📊 分析返回結果: ${audioResult != null ? "成功" : "null"}');
              if (audioResult != null) {
                debugPrint('[完整分析] ✅ 分類: ${audioResult.predictedClass}, 反饋: ${audioResult.feedbackLabel}');
              }
            } else {
              debugPrint('[完整分析] ⚠️  PCM 樣本為空');
            }
          }
        } catch (e) {
          debugPrint('[完整分析] ❌ 音頻分析異常：$e');
        }
      } else {
        debugPrint('[完整分析] ℹ️  WAV 檔案不存在，无法提取音频（可能是舊錄製或系统无FFmpeg支持）');
      }

      navigator.pop(); // 無論 mounted 與否，一定關閉 Dialog
      if (mounted) setState(() => _isAnalyzing = false);

      // Stage 3: 合併結果並更新條目
      if (audioResult != null) {
        updatedEntry = updatedEntry.copyWith(
          audioCrispness: audioResult.features.isNotEmpty
              ? audioResult.features.first.sharpnessHfxLoud
              : null,
          goodShot: audioResult.predictedClass == 'pro' || audioResult.predictedClass == 'good',
          audioLabel: audioResult.feedbackLabel,
        );
      }

      widget.onEntryUpdated?.call(widget.entry, updatedEntry);

      // 顯示完成訊息
      final audioMsg = audioResult != null
          ? '\n🎵 音頻：${audioResult.feedbackLabel}'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text('完整分析完成 ✅$audioMsg'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[完整分析] 錯誤: $e');
      navigator.pop();
      if (mounted) setState(() => _isAnalyzing = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('完整分析失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      progressNotifier.dispose();
    }
  }

  /// 測試用：重置分析狀態為 false
  void _shareSession() {
    ShareUploadDialog.show(
      context,
      entry: widget.entry,
      onShareSaved: (updated) => widget.onEntryUpdated?.call(widget.entry, updated),
    );
  }

  Future<void> _resetAnalysisState() async {
    final updatedEntry = widget.entry.copyWith(
      isAnalyzed: false,
      audioLabel: null,
      goodShot: null,
      audioCrispness: null,
    );
    
    widget.onEntryUpdated?.call(widget.entry, updatedEntry);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 分析狀態已重置'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 比較模式：先顯示第二部影片選擇器，再跳到比較頁面
  Future<void> _runCompare() async {
    // 候選影片：短影片、不是自己、檔案存在
    final candidates = widget.allEntries.where((e) =>
        e.filePath != widget.entry.filePath &&
        e.durationSeconds <= 5 &&
        File(e.filePath).existsSync()).toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('沒有其他短影片可供比較')),
      );
      return;
    }

    if (!mounted) return;
    final picked = await showModalBottomSheet<RecordingHistoryEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComparePickerSheet(
        candidates: candidates,
        currentEntry: widget.entry,
      ),
    );

    if (picked == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoComparisonPage(
          entryA: widget.entry,
          entryB: picked,
        ),
      ),
    );
  }

  /// 重置切片狀態（測試功能）
  Future<void> _resetClippingState() async {
    final updatedEntry = widget.entry.copyWith(
      isClipped: false,
    );
    
    widget.onEntryUpdated?.call(widget.entry, updatedEntry);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 切片狀態已重置，可重新執行偵測擊球'),
          duration: Duration(seconds: 2),
        ),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      shadowColor: Colors.black12,
      elevation: 4,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          // 長/短影片標記
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _isLongVideo
                                  ? const Color(0xFF1565C0).withAlpha(25)
                                  : const Color(0xFF757575).withAlpha(25),
                              border: Border.all(
                                color: _isLongVideo
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF757575),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isLongVideo ? '🎬 長影片' : '⚡ 短影片',
                              style: TextStyle(
                                fontSize: 10,
                                color: _isLongVideo
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF757575),
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
                          // 音頻分析標籤
                          if (widget.entry.audioLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6F00).withAlpha(25),
                                border: Border.all(
                                  color: const Color(0xFFFF6F00),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '🎵 ${widget.entry.audioLabel}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFFF6F00),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          // 無聲音標籤
                          if (widget.entry.audioTags?.contains('no_audio') == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9E9E9E).withAlpha(40),
                                border: Border.all(
                                  color: const Color(0xFF757575),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '🔇 無聲音',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF757575),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          // 已分析標籤
                          if (widget.entry.isAnalyzed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withAlpha(30),
                                border: Border.all(
                                  color: const Color(0xFF4CAF50),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '✓ 已分析',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF4CAF50),
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
                        case _HistoryMenuAction.analyze:
                          _runCombinedAnalysis();
                          break;
                        case _HistoryMenuAction.compare:
                          _runCompare();
                          break;
                        case _HistoryMenuAction.share:
                          _shareSession();
                          break;
                        case _HistoryMenuAction.resetAnalysisState:
                          _resetAnalysisState();
                          break;
                        case _HistoryMenuAction.resetClippingState:
                          _resetClippingState();
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
                    if (_isLongVideo && _isOriginalVideo && !widget.entry.isClipped)
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
                    if ((_isClip || (!_isLongVideo && _isOriginalVideo)) && !_isAnalyzed)
                      PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.analyze,
                        child: Row(
                          children: [
                            Text(
                              _isAnalyzing ? '分析中...' : '🎬 完整分析',
                              style: TextStyle(
                                color: _isAnalyzing ? Colors.grey : null,
                              ),
                            ),
                            if (_isAnalyzing) ...[
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
                    // 比較模式：限短影片（≤ 30 秒），且列表中還有其他短影片可選
                    if (!_isLongVideo && widget.allEntries.where((e) =>
                        e.filePath != widget.entry.filePath &&
                        e.durationSeconds <= 5 &&
                        File(e.filePath).existsSync()).isNotEmpty)
                      const PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.compare,
                        child: Text('⚖️ 與另一部影片比較'),
                      ),
                    if (!_isLongVideo && _isAnalyzed)
                      const PopupMenuItem<_HistoryMenuAction>(
                        value: _HistoryMenuAction.share,
                        child: Row(
                          children: [
                            Icon(Icons.share_outlined, size: 16, color: Color(0xFF1E8E5A)),
                            SizedBox(width: 8),
                            Text('分享連結'),
                          ],
                        ),
                      ),
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.resetAnalysisState,
                      child: Text('🧪 測試: 重置分析狀態'),
                    ),
                    const PopupMenuItem<_HistoryMenuAction>(
                      value: _HistoryMenuAction.resetClippingState,
                      child: Text('🧪 測試: 重置切片狀態'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🎬 ${widget.formattedTime} · ${widget.entry.durationSeconds} 秒',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.formattedImportTime != null)
                        Text(
                          '📥 ${widget.formattedImportTime}${widget.entry.sharerName != null ? '  來自 ${widget.entry.sharerName}' : ''}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9AA6B2)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecordingDetailPage(entry: widget.entry),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.bar_chart_rounded, color: Color(0xFF1565C0), size: 22),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onTap,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
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
            // 偵測擊球 / 裁切進度（已改為對話框顯示）
            // 影片分析進度（已改為對話框顯示）
          ],
          ),
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
              color: Colors.black.withValues(alpha: 0.6),
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

// ────────────────────────────────────────────────────────────────────────────
// 比較模式：第二部影片選擇器（底部彈出）
// ────────────────────────────────────────────────────────────────────────────

class _ComparePickerSheet extends StatelessWidget {
  final List<RecordingHistoryEntry> candidates;
  final RecordingHistoryEntry currentEntry;

  const _ComparePickerSheet({
    required this.candidates,
    required this.currentEntry,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 把手
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 標題
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚖️ 選擇比較影片',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF123B70),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '將與「${currentEntry.displayTitle}」對軸比較',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              // 列表
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: candidates.length,
                  itemBuilder: (_, i) => _CandidateCard(
                    entry: candidates[i],
                    onTap: () => Navigator.pop(context, candidates[i]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final RecordingHistoryEntry entry;
  final VoidCallback onTap;

  const _CandidateCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 縮圖
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildThumb(),
            ),
            const SizedBox(width: 12),
            // 資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 12, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(
                        '${entry.durationSeconds} 秒',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (entry.isAnalyzed) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, size: 12, color: Color(0xFF4CAF50)),
                        const SizedBox(width: 2),
                        const Text(
                          '已分析',
                          style: TextStyle(fontSize: 11, color: Color(0xFF4CAF50)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb() {
    final thumbPath = entry.thumbnailPath;
    if (thumbPath != null && File(thumbPath).existsSync()) {
      return Image.file(
        File(thumbPath),
        width: 64,
        height: 48,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: 64,
      height: 48,
      color: const Color(0xFFE8EDF2),
      child: const Icon(Icons.videocam, size: 24, color: Colors.grey),
    );
  }
}
