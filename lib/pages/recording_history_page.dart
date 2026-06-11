import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_quality.dart';
import '../models/recording_history_entry.dart';
import '../models/hits_summary.dart';
import '../models/swing_hit.dart';
import '../models/swing_posture.dart';
import '../services/recording_history_storage.dart';
import '../services/skeleton_csv_locator.dart';
import '../services/hits_summary_storage.dart';
import '../services/statistics_service.dart';
import '../services/swing_auto_clip_service.dart';
import '../services/swing_impact_detector.dart';
import '../services/clip_pipeline_service.dart';
import '../services/golf_analysis_service.dart';
import '../services/analysis_progress_service.dart';
import '../services/video_analysis_pipeline_service.dart';
import '../services/audio_export_service.dart';
import '../services/audio_export_models.dart';
import '../services/audio_extraction_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/ad_service.dart';
import '../services/analysis_service.dart';
import '../services/plan_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../widgets/hits_summary_widget.dart';
import '../widgets/green_page_header.dart';
import 'ai_coach_page.dart';
import 'video_comparison_page.dart';
import 'video_player_page.dart';
import 'recording_detail_page.dart';
import '../widgets/share_upload_dialog.dart';
import '../services/video_export_service.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, detectHits, analyze, compare, share, download, delete }

enum _ClipMenuAction { rename, share, download, delete }

/// 排序選項
enum _SortBy {
  /// 按時間排序（最新優先）
  date,
  /// 按最佳速度（峰值）排序（最高優先）
  peakValue,
  /// 按片段時間排序（切片在原始影片中的開始秒數，由小到大）
  clipTime;

  /// 中文標籤
  String get label {
    switch (this) {
      case _SortBy.date:
        return '時間';
      case _SortBy.peakValue:
        return '最佳速度';
      case _SortBy.clipTime:
        return '片段時間';
    }
  }
}

/// 從 RecordingHistoryEntry 已有的音訊分析欄位，組裝成後端所需的 audioAnalysisJson。
/// 若無音訊資料，回傳 null（後端將標記 available=false）。
String? _buildAudioAnalysisJson(RecordingHistoryEntry entry) {
  final passCount = entry.audioPassCount;
  if (passCount == null) return null;

  final passes    = entry.audioPasses ?? {};
  final features  = entry.audioFeatureValues ?? {};
  final sweetSpot = passCount >= AudioAnalysisService.goodBadThreshold;

  return jsonEncode({
    'available':      true,
    'pass_count':     passCount,
    'total_features': 5,
    'sweet_spot':     sweetSpot,
    'passes':         passes,
    'features':       features,
  });
}

/// 讀取 sessionDir/audio.wav（不存在則從 clipPath 萃取），解析 PCM 並回傳音訊分析結果。
/// [targetHitTime] 為擊球時刻相對 clip 起點的秒數，傳入可提升分析精度。
/// 失敗或無音訊時回傳 null，內部捕捉例外不向外拋。
Future<AudioAnalysisResult?> _analyzeWavFile({
  required String sessionDir,
  required String clipPath,
  required void Function(double progress, String message) onProgress,
  double? targetHitTime,
}) async {
  final wavFile = File(p.join(sessionDir, 'audio.wav'));
  var wavExists = await wavFile.exists();

  if (!wavExists) {
    onProgress(0.72, '提取音頻中...');
    final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
      videoPath: clipPath,
      outputWavPath: wavFile.path,
      onProgress: (progress, message) {
        onProgress(0.72 + progress * 0.08, message);
      },
    );
    if (samplesExtracted > 0) wavExists = await wavFile.exists();
  }

  if (!wavExists) return null;

  try {
    final bytes = await wavFile.readAsBytes();
    if (bytes.length < 44) return null;

    final wavHd        = bytes.buffer.asByteData();
    final wavChannels  = wavHd.getUint16(22, Endian.little);
    final wavSampleRate = wavHd.getUint32(24, Endian.little);
    final wavBlockAlign = wavHd.getUint16(32, Endian.little);

    // 掃描 'data' chunk，跳過可能的中繼 chunks
    int dataStart = 44;
    for (int i = 36; i < bytes.length - 8; i++) {
      if (bytes[i] == 100 && bytes[i+1] == 97 && bytes[i+2] == 116 && bytes[i+3] == 97) {
        dataStart = i + 8;
        break;
      }
    }

    final stride = wavBlockAlign > 0 ? wavBlockAlign : 2;
    final audioDataLen = bytes.length - dataStart;
    final pcmSamples = <double>[];
    for (int i = 0; i + stride <= audioDataLen; i += stride) {
      double frameVal = 0.0;
      for (int ch = 0; ch < wavChannels; ch++) {
        final offset = dataStart + i + ch * 2;
        if (offset + 1 >= bytes.length) break;
        final raw    = bytes[offset] | (bytes[offset + 1] << 8);
        final signed = (raw > 32767) ? raw - 65536 : raw;
        frameVal += signed / 32768.0;
      }
      pcmSamples.add(frameVal / wavChannels);
    }

    if (pcmSamples.isEmpty) return null;

    return await AudioExportService.analyzeFromPcm(
      pcmSamples: pcmSamples,
      sessionDir: sessionDir,
      sampleRate: wavSampleRate,
      targetHitTime: targetHitTime?.clamp(0.0, 300.0) ?? 3.0,
      onProgress: (progress) {
        onProgress(0.8 + progress.progress * 0.2, progress.message);
      },
    );
  } catch (e) {
    debugPrint('[音頻分析] 異常：$e');
    return null;
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
  // ── 篩選 & 排序狀態（從 SharedPreferences 持久化，跨重啟保留）──
  bool? _selectedGoodShot; // 好球/壞球篩選 - null: 全部, true: 好球, false: 壞球
  bool? _videoTypeIsLong;  // 影片長度篩選 - null: 全部, true: 長影片, false: 短影片
  bool? _aiAnalyzedFilter; // 分析狀態篩選 - null: 全部, true: 已分析, false: 未分析
  bool? _aiCoachFilter;    // AI教練篩選   - null: 全部, true: 已AI分析, false: 未AI分析
  bool? _clippedFilter;    // 切片狀態篩選 - null: 全部, true: 已切片, false: 未切片
  /// 姿勢篩選：null=全部，''=完美，其餘=對應 SwingPosture error label
  String? _postureFilter;
  String? _datePreset;         // 日期篩選 - null: 全部, 'today', 'week', 'month', 'custom'
  DateTime? _customDateFrom;   // 自訂日期起始（_datePreset == 'custom' 時使用）
  DateTime? _customDateTo;     // 自訂日期結束（_datePreset == 'custom' 時使用）
  _SortBy _sortBy = _SortBy.date; // 排序選項，預設按時間排序
  bool _filtersExpanded = false;  // 篩選面板折疊狀態（預設收起）

  // ── 文字搜尋 ──────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
    _loadFilters();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery) setState(() => _searchQuery = q);
    });
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
    _searchController.dispose();
    super.dispose();
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

    // 精確刪除單筆（原子操作，不影響其他記錄）
    await RecordingHistoryStorage.instance.deleteEntry(entry.filePath);

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

    await RecordingHistoryStorage.instance.upsertEntry(_entries[index]);

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
      RecordingHistoryStorage.instance.upsertEntry(_entries[idx]);
    }
    _entries.addAll(clips);
    setState(() {});
    for (final clip in clips) {
      RecordingHistoryStorage.instance.upsertEntry(clip);
    }
  }

  /// 影片分析完成後，以新版 entry 取代舊版
  void _onEntryUpdated(RecordingHistoryEntry oldEntry, RecordingHistoryEntry newEntry) {
    final idx = _entries.indexWhere((e) => e.filePath == oldEntry.filePath);
    if (idx != -1) {
      _entries[idx] = newEntry;
      setState(() {});
      // filePath 若改變（clip.mp4 → final.mp4），必須先刪除舊 PRIMARY KEY，
      // 否則 DB 會同時保留兩筆記錄，重啟後出現多一個切片。
      if (oldEntry.filePath != newEntry.filePath) {
        RecordingHistoryStorage.instance.deleteEntry(oldEntry.filePath);
      }
      RecordingHistoryStorage.instance.upsertEntry(newEntry);
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

  // ---------- 篩選持久化 ----------

  static const _kGoodShot   = 'hf_good_shot';
  static const _kVideoType  = 'hf_video_type';
  static const _kAnalyzed   = 'hf_analyzed';
  static const _kAiCoach    = 'hf_ai_coach';
  static const _kClipped    = 'hf_clipped';
  static const _kPosture    = 'hf_posture';
  static const _kSortBy     = 'hf_sort_by';
  static const _kDatePreset = 'hf_date_preset';
  static const _kDateFrom   = 'hf_date_from';
  static const _kDateTo     = 'hf_date_to';

  /// 從 SharedPreferences 還原篩選狀態（initState 呼叫）
  Future<void> _loadFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedGoodShot = _prefBool(prefs, _kGoodShot);
      _videoTypeIsLong  = _prefBool(prefs, _kVideoType);
      _aiAnalyzedFilter = _prefBool(prefs, _kAnalyzed);
      _aiCoachFilter    = _prefBool(prefs, _kAiCoach);
      _clippedFilter    = _prefBool(prefs, _kClipped);
      // 姿勢篩選：'__none__' 代表未設定（避免與合法的 '' 混淆）
      final rawPosture = prefs.getString(_kPosture);
      _postureFilter = rawPosture == '__none__' ? null : rawPosture;
      _datePreset = prefs.getString(_kDatePreset);
      final fromMs = prefs.getInt(_kDateFrom);
      final toMs   = prefs.getInt(_kDateTo);
      _customDateFrom = fromMs != null ? DateTime.fromMillisecondsSinceEpoch(fromMs) : null;
      _customDateTo   = toMs   != null ? DateTime.fromMillisecondsSinceEpoch(toMs)   : null;
      final name = prefs.getString(_kSortBy);
      if (name != null) {
        _sortBy = _SortBy.values.firstWhere(
          (e) => e.name == name, orElse: () => _SortBy.date);
      }
    });
  }

  /// 將篩選狀態寫入 SharedPreferences（每次改值後呼叫）
  void _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    _setPrefBool(prefs, _kGoodShot,  _selectedGoodShot);
    _setPrefBool(prefs, _kVideoType, _videoTypeIsLong);
    _setPrefBool(prefs, _kAnalyzed,  _aiAnalyzedFilter);
    _setPrefBool(prefs, _kAiCoach,   _aiCoachFilter);
    _setPrefBool(prefs, _kClipped,   _clippedFilter);
    prefs.setString(_kPosture, _postureFilter ?? '__none__');
    await prefs.setString(_kSortBy, _sortBy.name);
    if (_datePreset == null) {
      prefs.remove(_kDatePreset);
      prefs.remove(_kDateFrom);
      prefs.remove(_kDateTo);
    } else {
      prefs.setString(_kDatePreset, _datePreset!);
      if (_customDateFrom != null) prefs.setInt(_kDateFrom, _customDateFrom!.millisecondsSinceEpoch);
      if (_customDateTo   != null) prefs.setInt(_kDateTo,   _customDateTo!.millisecondsSinceEpoch);
    }
  }

  static bool? _prefBool(SharedPreferences p, String key) {
    final v = p.getString(key);
    if (v == 'true')  return true;
    if (v == 'false') return false;
    return null;
  }

  static void _setPrefBool(SharedPreferences p, String key, bool? value) {
    if (value == null) {
      p.remove(key);
    } else {
      p.setString(key, value.toString());
    }
  }

  // ---------- 篩選面板 Helper ----------

  /// 單列篩選行：左側固定寬度標籤 + 右側橫向捲動 chips
  Widget _filterRow(String label, List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6F7B86),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  chips[i],
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// 快速建立 _HistoryFilterChip
  Widget _chip(String label, bool selected, Color color, VoidCallback onTap) =>
      _HistoryFilterChip(label: label, selected: selected, selectedColor: color, onTap: onTap);

  /// 計算日期篩選的有效起迄範圍
  (DateTime? from, DateTime? to) get _effectiveDateRange {
    final now = DateTime.now();
    switch (_datePreset) {
      case 'today':
        return (DateTime(now.year, now.month, now.day),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(weekStart.year, weekStart.month, weekStart.day),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'month':
        return (DateTime(now.year, now.month, 1),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'custom':
        return (_customDateFrom, _customDateTo);
      default:
        return (null, null);
    }
  }

  /// 目前非預設值的篩選條件數量
  int get _activeFilterCount {
    int n = 0;
    if (_selectedGoodShot != null) n++;
    if (_videoTypeIsLong  != null) n++;
    if (_aiAnalyzedFilter != null) n++;
    if (_aiCoachFilter    != null) n++;
    if (_clippedFilter    != null) n++;
    if (_postureFilter    != null) n++;
    if (_datePreset       != null) n++;
    if (_sortBy != _SortBy.date)   n++;
    return n;
  }

  /// 折疊時顯示目前啟用的篩選摘要小 chip
  Widget _activeFilterSummary() {
    final items = <(String, Color)>[];
    if (_selectedGoodShot == true)  items.add(('好球',   const Color(0xFF4CAF50)));
    if (_selectedGoodShot == false) items.add(('壞球',   const Color(0xFFF44336)));
    if (_videoTypeIsLong  == true)  items.add(('長影片', const Color(0xFF1565C0)));
    if (_videoTypeIsLong  == false) items.add(('短影片', const Color(0xFF757575)));
    if (_aiAnalyzedFilter == true)  items.add(('已分析', const Color(0xFF1E8E5A)));
    if (_aiAnalyzedFilter == false) items.add(('未分析', const Color(0xFF9AA6B2)));
    if (_aiCoachFilter    == true)  items.add(('AI已分析', const Color(0xFF7C3AED)));
    if (_aiCoachFilter    == false) items.add(('AI未分析', const Color(0xFF9AA6B2)));
    if (_clippedFilter    == true)  items.add(('已切片', const Color(0xFFFF9800)));
    if (_clippedFilter    == false) items.add(('未切片', const Color(0xFF9AA6B2)));
    if (_postureFilter != null) {
      final color = SwingPosture.isPerfect(_postureFilter)
          ? const Color(0xFF4CAF50)
          : const Color(0xFFE57373);
      items.add((SwingPosture.zhName(_postureFilter!), color));
    }
    if (_datePreset == 'today')  items.add(('今天',     const Color(0xFF2196F3)));
    if (_datePreset == 'week')   items.add(('本週',     const Color(0xFF2196F3)));
    if (_datePreset == 'month')  items.add(('本月',     const Color(0xFF2196F3)));
    if (_datePreset == 'custom' && _customDateFrom != null) {
      final df = _customDateFrom!;
      final dt = _customDateTo ?? _customDateFrom!;
      final fmt = (DateTime d) => '${d.month}/${d.day}';
      items.add(('${fmt(df)}–${fmt(dt)}', const Color(0xFF2196F3)));
    }
    if (_sortBy != _SortBy.date)    items.add((_sortBy.label, const Color(0xFF1565C0)));

    if (items.isEmpty) {
      return const Text('全部',
          style: TextStyle(fontSize: 11, color: Color(0xFF9AA6B2)));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((t) => Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: t.$2.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.$2.withValues(alpha: 0.4)),
          ),
          child: Text(t.$1,
              style: TextStyle(
                  fontSize: 10, color: t.$2, fontWeight: FontWeight.w600)),
        )).toList(),
      ),
    );
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
      
      case _SortBy.clipTime:
        // 按片段內播放位置排序（startSecond 小的前者先）
        sorted.sort((a, b) {
          final isClipA = a.videoType == VideoType.localClip;
          final isClipB = b.videoType == VideoType.localClip;
          // 切片排前，不是切片的按日期排序
          if (isClipA != isClipB) return isClipA ? -1 : 1;
          if (isClipA && isClipB) {
            final ta = a.startSecond ?? a.hitSecond ?? 0.0;
            final tb = b.startSecond ?? b.hitSecond ?? 0.0;
            return ta.compareTo(tb);
          }
          return b.sortTime.compareTo(a.sortTime);
        });
        break;
    }
    
    return sorted;
  }

  /// 取得最高速度峰值（bestSpeedValue 欄位），用於「最佳速度」排序
  double? _getMaxPeakValue(RecordingHistoryEntry entry) {
    return entry.bestSpeedValue;
  }

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
    // 好球/壞球
    var filteredEntries = _selectedGoodShot == null
        ? _entries
        : _entries.where((entry) => entry.goodShot == _selectedGoodShot).toList();

    // 影片類型（長/短）
    if (_videoTypeIsLong != null) {
      filteredEntries = filteredEntries.where((e) {
        final isLong = e.durationSeconds > 5 && e.durationSeconds <= 600;
        return _videoTypeIsLong! ? isLong : !isLong;
      }).toList();
    }

    // 分析狀態（已分析/未分析）
    if (_aiAnalyzedFilter != null) {
      filteredEntries = filteredEntries
          .where((e) => e.isAnalyzed == _aiAnalyzedFilter)
          .toList();
    }

    // AI教練分析（已AI分析/未AI分析）
    if (_aiCoachFilter != null) {
      filteredEntries = filteredEntries
          .where((e) => e.hasAiCoachAnalysis == _aiCoachFilter)
          .toList();
    }

    // 切片狀態（已切片/未切片）
    if (_clippedFilter != null) {
      filteredEntries = filteredEntries
          .where((e) => e.isClipped == _clippedFilter)
          .toList();
    }

    // 姿勢篩選（只顯示 swingPostureLabel != null 的條目）
    if (_postureFilter != null) {
      filteredEntries = filteredEntries
          .where((e) => e.swingPostureLabel == _postureFilter)
          .toList();
    }

    // 日期篩選
    if (_datePreset != null) {
      final (from, to) = _effectiveDateRange;
      if (from != null) {
        filteredEntries = filteredEntries
            .where((e) => !e.recordedAt.isBefore(from))
            .toList();
      }
      if (to != null) {
        filteredEntries = filteredEntries
            .where((e) => !e.recordedAt.isAfter(to))
            .toList();
      }
    }

    // 應用排序
    filteredEntries = _sortEntries(filteredEntries);

    // 排除已有父影片的切片（改為巢狀顯示於父卡片下）
    final parentPaths = _entries.map((e) => e.filePath).toSet();
    filteredEntries = filteredEntries.where((e) =>
        !(e.videoType == VideoType.localClip &&
          e.sourceVideoPath != null &&
          parentPaths.contains(e.sourceVideoPath))).toList();

    // 文字搜尋
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredEntries = filteredEntries.where((e) {
        if (e.displayTitle.toLowerCase().contains(q)) return true;
        if ((e.customName ?? '').toLowerCase().contains(q)) return true;
        if (_formatTimestamp(e.recordedAt).contains(q)) return true;
        return false;
      }).toList();
    }

    // 統計文字
    final goodCount = _entries.where((e) => e.goodShot == true).length;
    final badCount  = _entries.where((e) => e.goodShot == false).length;
    final totalShown = filteredEntries.length;
    final subtitle  = _isLoading
        ? '載入中…'
        : _searchQuery.isNotEmpty
            ? '搜尋結果 $totalShown / ${_entries.length} 筆'
            : '共 ${_entries.length} 筆 · 好球 $goodCount · 壞球 $badCount';

    return Scaffold(
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
                  ),
              ],
            ),
            // ── 文字搜尋欄（常駐）────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
                  decoration: InputDecoration(
                    hintText: '搜尋影片名稱、日期…',
                    hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFFB0B8C1)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF9AA6B2)),
                    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                            child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF9AA6B2)),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    filled: true,
                    fillColor: const Color(0xFFF4F6F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1E8E5A), width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
            // ── 篩選 & 排序面板（可折疊）────────────────────────
            Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 折疊標頭列（常駐）
                  InkWell(
                    onTap: () => setState(
                        () => _filtersExpanded = !_filtersExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded,
                              size: 15, color: Color(0xFF1E8E5A)),
                          const SizedBox(width: 6),
                          const Text('篩選與排序',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF123B70))),
                          if (_activeFilterCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E8E5A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('$_activeFilterCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                          const SizedBox(width: 8),
                          // 折疊時顯示啟用篩選摘要
                          if (!_filtersExpanded)
                            Expanded(child: _activeFilterSummary())
                          else
                            const Spacer(),
                          AnimatedRotation(
                            turns: _filtersExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: Color(0xFF9AA6B2)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 展開的篩選列（AnimatedSize 平滑動畫）
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _filtersExpanded
                        ? Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _filterRow('好/壞', [
                                  _chip('全部',   _selectedGoodShot == null,  const Color(0xFF1E8E5A), () { setState(() => _selectedGoodShot = null);  _saveFilters(); }),
                                  _chip('好球',   _selectedGoodShot == true,  const Color(0xFF4CAF50), () { setState(() => _selectedGoodShot = true);  _saveFilters(); }),
                                  _chip('壞球',   _selectedGoodShot == false, const Color(0xFFF44336), () { setState(() => _selectedGoodShot = false); _saveFilters(); }),
                                ]),
                                _filterRow('影片', [
                                  _chip('全部',   _videoTypeIsLong == null,  const Color(0xFF1E8E5A), () { setState(() => _videoTypeIsLong = null);  _saveFilters(); }),
                                  _chip('長影片', _videoTypeIsLong == true,  const Color(0xFF1565C0), () { setState(() => _videoTypeIsLong = true);  _saveFilters(); }),
                                  _chip('短影片', _videoTypeIsLong == false, const Color(0xFF757575), () { setState(() => _videoTypeIsLong = false); _saveFilters(); }),
                                ]),
                                _filterRow('分析', [
                                  _chip('全部',   _aiAnalyzedFilter == null,  const Color(0xFF1E8E5A), () { setState(() => _aiAnalyzedFilter = null);  _saveFilters(); }),
                                  _chip('已分析', _aiAnalyzedFilter == true,  const Color(0xFF4CAF50), () { setState(() => _aiAnalyzedFilter = true);  _saveFilters(); }),
                                  _chip('未分析', _aiAnalyzedFilter == false, const Color(0xFF9AA6B2), () { setState(() => _aiAnalyzedFilter = false); _saveFilters(); }),
                                ]),
                                _filterRow('AI', [
                                  _chip('全部',   _aiCoachFilter == null,  const Color(0xFF1E8E5A), () { setState(() => _aiCoachFilter = null);  _saveFilters(); }),
                                  _chip('已分析', _aiCoachFilter == true,  const Color(0xFF7C3AED), () { setState(() => _aiCoachFilter = true);  _saveFilters(); }),
                                  _chip('未分析', _aiCoachFilter == false, const Color(0xFF9AA6B2), () { setState(() => _aiCoachFilter = false); _saveFilters(); }),
                                ]),
                                _filterRow('切片', [
                                  _chip('全部',   _clippedFilter == null,  const Color(0xFF1E8E5A), () { setState(() => _clippedFilter = null);  _saveFilters(); }),
                                  _chip('已切片', _clippedFilter == true,  const Color(0xFFFF9800), () { setState(() => _clippedFilter = true);  _saveFilters(); }),
                                  _chip('未切片', _clippedFilter == false, const Color(0xFF9AA6B2), () { setState(() => _clippedFilter = false); _saveFilters(); }),
                                ]),
                                _filterRow('姿勢', [
                                  _chip('全部', _postureFilter == null, const Color(0xFF1E8E5A), () { setState(() => _postureFilter = null); _saveFilters(); }),
                                  _chip(
                                    SwingPosture.zhName(SwingPosture.good),
                                    _postureFilter == SwingPosture.good,
                                    const Color(0xFF4CAF50),
                                    () { setState(() => _postureFilter = SwingPosture.good); _saveFilters(); },
                                  ),
                                  for (final label in SwingPosture.errorLabels)
                                    _chip(
                                      SwingPosture.zhName(label),
                                      _postureFilter == label,
                                      const Color(0xFFE57373),
                                      () { setState(() => _postureFilter = label); _saveFilters(); },
                                    ),
                                ]),
                                _filterRow('日期', [
                                  _chip('全部', _datePreset == null,    const Color(0xFF1E8E5A), () { setState(() { _datePreset = null; _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _chip('今天', _datePreset == 'today', const Color(0xFF2196F3), () { setState(() { _datePreset = 'today'; _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _chip('本週', _datePreset == 'week',  const Color(0xFF2196F3), () { setState(() { _datePreset = 'week';  _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _chip('本月', _datePreset == 'month', const Color(0xFF2196F3), () { setState(() { _datePreset = 'month'; _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _DateRangeChip(
                                    selected: _datePreset == 'custom',
                                    dateFrom: _customDateFrom,
                                    dateTo: _customDateTo,
                                    onPicked: (from, to) {
                                      setState(() { _datePreset = 'custom'; _customDateFrom = from; _customDateTo = to; });
                                      _saveFilters();
                                    },
                                  ),
                                ]),
                                _filterRow('排序', [
                                  _chip('時間',     _sortBy == _SortBy.date,      const Color(0xFF1E8E5A), () { setState(() => _sortBy = _SortBy.date);      _saveFilters(); }),
                                  _chip('最佳速度', _sortBy == _SortBy.peakValue, const Color(0xFF1565C0), () { setState(() => _sortBy = _SortBy.peakValue); _saveFilters(); }),
                                  _chip('片段時間', _sortBy == _SortBy.clipTime,  const Color(0xFFFF9800), () { setState(() => _sortBy = _SortBy.clipTime);  _saveFilters(); }),
                                ]),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                ],
              ),
            ),
            // 影片列表
            Expanded(
              child: filteredEntries.isEmpty
                  ? (_searchQuery.isNotEmpty
                      ? _SearchEmptyView(query: _searchQuery,
                          onClear: () { _searchController.clear(); FocusScope.of(context).unfocus(); })
                      : const _EmptyHistoryView())
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
                          onDeleteClip: _deleteEntry,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: filteredEntries.length,
                    ),
            ),
          ],
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

/// 搜尋無結果空狀態
class _SearchEmptyView extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _SearchEmptyView({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 64, color: Color(0xFF9AA6B2)),
          const SizedBox(height: 16),
          const Text(
            '找不到符合的影片',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF123B70)),
          ),
          const SizedBox(height: 6),
          Text(
            '沒有包含「$query」的紀錄',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6F7B86)),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('清除搜尋'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF1E8E5A)),
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
  /// 刪除子切片的回呼（由 _ClipSubCard 觸發）
  final void Function(RecordingHistoryEntry clip)? onDeleteClip;

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
    this.onDeleteClip,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late Future<List<HitsSummary>> _hitsSummaryFuture;
  bool _isDetecting = false;
  bool _isAnalyzing = false;
  bool _isSubmittingAi = false;
  bool _isExpanded = false;
  bool get _isLongVideo => widget.entry.durationSeconds > 5 && widget.entry.durationSeconds <= 600;
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

    // ── 偵測模式選擇對話框（含 V1/V2 切換）────────────────────────────
    SkeletonAnalysisMode detectionMode = SkeletonAnalysisMode.v1;
    if (mounted) {
      final result = await showDialog<_DetectionModeResult>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _DetectionModeDialog(),
      );
      if (result == null) return; // 使用者取消
      detectionMode = result.mode;
      if (result.skipToday) await _SkipHelper.markSkipToday('detection');
    }

    setState(() => _isDetecting = true);

    if (!mounted) return;

    // 在第一個 await 之前捕捉 navigator/messenger，確保 Dialog 一定能關閉
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備骨架分析...'));
    final cancelToken = _CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: '擊球偵測中',
        progressNotifier: progressNotifier,
        progressColor: Colors.blue,
        onCancel: () {
          cancelToken.cancel();
          unawaited(_cancelNativeAnalysis());   // 通知 Kotlin 停止分析迴圈
          navigator.pop();
          if (mounted) setState(() => _isDetecting = false);
          messenger.showSnackBar(const SnackBar(content: Text('已取消擊球偵測')));
        },
      ),
    );

    try {
      final sessionDir = p.dirname(widget.entry.filePath);
      final csvPath = p.join(sessionDir, 'pose_landmarks.csv');

      // ── V2：音訊峰值直接偵測，完全跳過全幀骨架分析 ──────────────────
      if (detectionMode == SkeletonAnalysisMode.v2) {
        // 監聽 native EventChannel 進度，即時更新對話框進度條
        final progressSvc = AnalysisProgressService.instance;
        progressSvc.reset('V2 音訊掃描中...');
        void _listenV2() {
          final (pct, label) = progressSvc.progress.value;
          // V2 audio peaks 佔整體進度的 0~0.6，裁切佔 0.6~1.0
          progressNotifier.value = (pct * 0.6, label);
        }
        progressSvc.progress.addListener(_listenV2);

        final peakMs = await GolfAnalysisService.findAudioPeaks(
          videoPath: widget.entry.filePath,
          searchStartMs: 500,
          minGapMs: 2000,
        );
        progressSvc.progress.removeListener(_listenV2);
        if (cancelToken.isCancelled) return;
        debugPrint('[偵測擊球 V2] 音訊峰值: $peakMs');

        // 聯集錄影時 LiveSwingDetector 記錄的擊球時刻（若有），補音訊漏掉的桿
        final liveImpacts =
            await SwingAutoClipService.loadLiveImpacts(sessionDir);
        final candidates = SwingAutoClipService.mergeCandidates(
          audioPeaks: peakMs.map((ms) => ms / 1000.0).toList(),
          liveImpacts: liveImpacts,
        );

        if (candidates.isEmpty) {
          navigator.pop();
          setState(() => _isDetecting = false);
          messenger.showSnackBar(const SnackBar(
            content: Text('V2：影片無音訊或未偵測到擊球聲'),
            backgroundColor: Colors.orange,
          ));
          return;
        }

        progressNotifier.value = (0.4, '裁切片段中...');
        // 把候選轉為 SwingHit（±2.5 秒精確窗口）
        // 每個候選各自對應一個 clip；若兩候選相距 < 5 秒，clip 可重疊，這是預期行為。
        // trimWithSurface() 保證每個 clip 精確 5 秒，以候選為中心。
        final totalDur = widget.entry.durationSeconds.toDouble();
        final v2Hits = <SwingHit>[];
        for (int i = 0; i < candidates.length; i++) {
          final c = candidates[i];
          final (s2, e2) = SwingImpactDetector.calculateClipBoundaries(
            hitSec: c.sec, totalDurationSec: totalDur);
          v2Hits.add(SwingHit(
            hitIndex:   i + 1,
            hitFrame:   (c.sec * 30).round(),
            hitSec:     c.sec,
            startSec:   s2,
            endSec:     e2,
            speedValue: 0.0,
            audioValue: c.fromAudio ? 1.0 : 0.0,
          ));
        }

        // 直接裁切，不跑骨架分析（進度從 0.6 起算）
        await _clipAndSaveHits(
          hits: v2Hits,
          navigator: navigator,
          messenger: messenger,
          progressNotifier: progressNotifier,
          baseProgress: 0.6,
          cancelToken: cancelToken,
        );
        return;
      }

      // ── V3：音訊找候選時間點 → 局部骨架精確定位 → 切片 ──────────────
      if (detectionMode == SkeletonAnalysisMode.v3) {
        // Step 1：音訊掃描（監聽 native 進度，0.0~0.15）
        final progressSvc = AnalysisProgressService.instance;
        progressSvc.reset('V3 音訊掃描中...');
        void listenAudio() {
          if (progressSvc.currentOp == 'findAudioPeaks') {
            final (pct, label) = progressSvc.progress.value;
            progressNotifier.value = (pct * 0.15, label);
          }
        }
        progressSvc.progress.addListener(listenAudio);

        final peakMs = await GolfAnalysisService.findAudioPeaks(
          videoPath: widget.entry.filePath,
          searchStartMs: 500,
          minGapMs: 2000,
        );
        progressSvc.progress.removeListener(listenAudio);
        if (cancelToken.isCancelled) return;
        debugPrint('[偵測擊球 V3] 音訊峰值: $peakMs');

        if (peakMs.isEmpty) {
          navigator.pop();
          setState(() => _isDetecting = false);
          messenger.showSnackBar(const SnackBar(
            content: Text('V3：影片無音訊或未偵測到擊球聲'),
            backgroundColor: Colors.orange,
          ));
          return;
        }

        // Step 2：對每個音訊峰值做局部骨架分析（±3 秒窗口 → 精確 impactMs）
        final totalDur = widget.entry.durationSeconds.toDouble();
        final v3Hits   = <SwingHit>[];

        for (int i = 0; i < peakMs.length; i++) {
          if (cancelToken.isCancelled) return;

          final peak     = peakMs[i];
          final baseFrom = 0.15 + (i / peakMs.length) * 0.55;   // 0.15 ~ 0.70
          final baseTo   = 0.15 + ((i + 1) / peakMs.length) * 0.55;
          final label    = 'V3 骨架分析 ${i+1}/${peakMs.length}';
          progressNotifier.value = (baseFrom, label);

          // 監聽 Kotlin 進度，顯示「第幾個影片 / 總數：Kotlin 幀狀態」
          final peakLabel = '第${i+1}/${peakMs.length}個';
          progressSvc.reset('V3 骨架分析 $peakLabel...');
          void listenSkel() {
            final (pct, frameLbl) = progressSvc.progress.value;
            final mapped  = baseFrom + pct * (baseTo - baseFrom);
            // 合併：「第N/M個：Kotlin幀進度」
            final display = '$peakLabel：$frameLbl';
            progressNotifier.value = (mapped.clamp(0.0, 1.0), display);
          }
          progressSvc.progress.addListener(listenSkel);

          // 直接用音訊峰值做骨架分析（跳過重複音訊偵測）
          // 骨架窗口：peak ± 3 秒（6 秒），從中找右腕 Y 最低點 = 精確 impact
          final result = await GolfAnalysisService.analyzeVideoAtCandidate(
            videoPath:   widget.entry.filePath,
            candidateMs: peak,
            windowMs:    3000,
          );
          progressSvc.progress.removeListener(listenSkel);
          if (cancelToken.isCancelled) return;

          // result == null：骨架驗證未通過（非擊球動作），跳過此峰值
          if (result == null) {
            debugPrint('[偵測擊球 V3] hit ${i+1}: peak=${peak}ms → 骨架驗證失敗，已排除');
            continue;
          }

          final hitMs  = result.impactTimeMs;
          final hitSec = hitMs / 1000.0;

          debugPrint('[偵測擊球 V3] hit ${i+1}: audioPeak=${peak}ms → impact=${hitMs}ms '
              '(精修 ${hitMs - peak}ms)');

          final (s3, e3) = SwingImpactDetector.calculateClipBoundaries(
            hitSec: hitSec, totalDurationSec: totalDur);
          v3Hits.add(SwingHit(
            hitIndex:     i + 1,
            hitFrame:     (hitSec * 30).round(),
            hitSec:       hitSec,
            startSec:     s3,
            endSec:       e3,
            speedValue:   0.0,
            audioValue:   1.0,
            skeletonJson: result.skeletonJson, // V3 局部骨架，直接寫入 clip CSV
          ));
        }

        if (v3Hits.isEmpty) {
          navigator.pop();
          setState(() => _isDetecting = false);
          messenger.showSnackBar(const SnackBar(
            content: Text('V3：無法找到有效擊球時間點'),
            backgroundColor: Colors.orange,
          ));
          return;
        }

        // Step 3：裁切（進度從 0.7 起算）
        await _clipAndSaveHits(
          hits: v3Hits,
          navigator: navigator,
          messenger: messenger,
          progressNotifier: progressNotifier,
          baseProgress: 0.7,
          cancelToken: cancelToken,
        );
        return;
      }

      // ── V1：骨架 CSV 來源（live 優先，零等待）─────────────────────────
      // 有現成骨架（逐幀版或錄影即時 live 版）就直接用，不重新分析；
      // 兩者都沒有時才執行逐幀基礎分析。live 版取樣較疏（~15fps），
      // 擊球幀可能落在兩幀之間 — 使用者已知並接受此 trade-off。
      var detectCsvPath = resolveSkeletonCsv(sessionDir);
      if (detectCsvPath == null) {
        final basicAnalysis = await VideoAnalysisPipelineService.analyzeBasic(
          videoPath: widget.entry.filePath,
          sessionDir: sessionDir,
          durationSeconds: widget.entry.durationSeconds,
          onProgress: (label) {
            progressNotifier.value = (0.3, label);
          },
        );
        if (cancelToken.isCancelled) return;
        if (basicAnalysis == null || !await File(csvPath).exists()) {
          throw '基礎分析失敗：無法生成骨架';
        }
        detectCsvPath = csvPath;
      } else {
        debugPrint('[偵測擊球] ✅ 使用現成骨架: ${p.basename(detectCsvPath)}');
      }

      if (cancelToken.isCancelled) return;

      // 2. 讀取 CSV 檢查骨架數據
      debugPrint('[偵測擊球] 📋 讀取 CSV 文件...');
      List<String> csvLines = [];
      try {
        csvLines = await File(detectCsvPath).readAsLines();
        debugPrint('[偵測擊球] 📋 CSV 行數: ${csvLines.length}');
        int validFrames = 0; double maxConfidence = 0.0;
        for (int i = 1; i < csvLines.length; i++) {
          final parts = csvLines[i].split(',');
          if (parts.length >= 3) {
            final conf = double.tryParse(parts[2]) ?? 0.0;
            if (conf > 0) validFrames++;
            if (conf > maxConfidence) maxConfidence = conf;
          }
        }
        debugPrint('[偵測擊球] 📊 骨架有效幀: $validFrames, 最高信心度: ${maxConfidence.toStringAsFixed(3)}');
      } catch (e) {
        debugPrint('[偵測擊球] ❌ CSV 讀取失敗: $e');
      }

      // 3. 骨架速度偵測擊球
      debugPrint('[偵測擊球] 🔍 開始峰值檢測...');
      progressNotifier.value = (0.5, '偵測擊球中...');
      final hits = await SwingImpactDetector.detect(csvPath: detectCsvPath);
      if (cancelToken.isCancelled) return;
      debugPrint('[偵測擊球] 📊 峰值檢測結果: ${hits.length} 個擊球');

      if (!mounted) return;

      // 📊 統計擊球峰值
      if (hits.isNotEmpty) {
        final avgSpeed = hits.fold<double>(0, (s, h) => s + h.speedValue) / hits.length;
        final hitFrames = hits.map((h) => h.hitFrame).toList();

        debugPrint(
          '[HitDetection] 📊 統計:\n'
          '  偵測擊球數: ${hits.length}\n'
          '  平均速度值: ${avgSpeed.toStringAsFixed(3)}\n'
          '  擊球幀位置: $hitFrames'
        );

        // 計算最高速度峰值並儲存到 entry（供「最佳速度」排序使用）
        final maxSpeed = hits.fold<double>(0.0, (m, h) => h.speedValue > m ? h.speedValue : m);
        final entryWithSpeed = widget.entry.copyWith(bestSpeedValue: maxSpeed);
        unawaited(RecordingHistoryStorage.instance.upsertEntry(entryWithSpeed));
        debugPrint('[HitDetection] 💾 bestSpeedValue=$maxSpeed 已儲存');
      }

      if (hits.isEmpty) {
        debugPrint('[偵測擊球] ⚠️ 未檢測到任何擊球');
        
        // 額外診斷
        debugPrint('[偵測擊球] 🔧 診斷信息:');
        debugPrint('  - CSV 有效: ${csvLines.isNotEmpty}');
        
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

      if (cancelToken.isCancelled) return;
      navigator.pop(); // 無論 mounted 與否，一定關閉 Dialog
      if (mounted) setState(() => _isDetecting = false);

      if (results.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('偵測成功，但片段裁切失敗，請重試')),
        );
        return;
      }



      widget.onClipsGenerated?.call(
        widget.entry,
        results.map((r) => r.entry).toList(),
      );
      await AdService.showBallDetectionInterstitial();
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

  /// 共用裁切 + 儲存邏輯（V1 後半 / V2 均呼叫）
  ///
  /// [baseProgress]：裁切開始時的進度基底（V1=0.5，V2=0.6）
  Future<void> _clipAndSaveHits({
    required List<SwingHit> hits,
    required NavigatorState navigator,
    required ScaffoldMessengerState messenger,
    required ValueNotifier<(double, String)> progressNotifier,
    double baseProgress = 0.5,
    _CancelToken? cancelToken,
  }) async {
    final remaining = 1.0 - baseProgress;
    final results = await ClipPipelineService.run(
      hits: hits,
      srcVideoPath: widget.entry.filePath,
      sourceEntry: widget.entry,
      onProgress: (prog) {
        final pct = prog.total > 0 ? prog.current / prog.total : 0.0;
        progressNotifier.value = (
          baseProgress + pct * remaining,
          '裁切片段中... ${(pct * 100).round()}% (${prog.current}/${prog.total})',
        );
      },
    );

    if (cancelToken?.isCancelled == true) return;

    navigator.pop();
    if (mounted) setState(() => _isDetecting = false);

    if (results.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('偵測成功，但片段裁切失敗，請重試')),
      );
      return;
    }

    widget.onClipsGenerated?.call(
      widget.entry,
      results.map((r) => r.entry).toList(),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text('已生成 ${results.length} 個擊球片段 ✅\n骨架與 8 階段正在背景分析中'),
        duration: const Duration(seconds: 4),
      ),
    );

    // 背景逐 clip 局部分析（~150 幀/clip）：補逐幀骨架 + 精確 hitSecond + 8 階段。
    // 已分析過的 clip（如 V3 帶 skeletonJson）analyzeBasic 會直接跳過。
    unawaited(() async {
      for (final r in results) {
        if (r.entry.isAnalyzed) continue;
        try {
          final analyzed = await SwingAutoClipService.analyzeClipEntry(r.entry);
          await RecordingHistoryStorage.instance.upsertEntry(analyzed);
        } catch (e) {
          debugPrint('[偵測擊球] clip 背景分析失敗: $e');
        }
      }
      debugPrint('[偵測擊球] ✅ 全部 clip 背景分析完成');
    }());
  }

  /// 執行完整分析（視頻 + 音頻），合併結果
  Future<void> _runCombinedAnalysis() async {
    if (_isAnalyzing) return;

    // ── iOS 長影片記憶體警告（> 60 秒）──────────────────────────────
    if ((Platform.isIOS || Platform.isAndroid) && widget.entry.durationSeconds > 60 && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('影片較長'),
          content: Text(
            '此影片長度為 ${widget.entry.durationSeconds} 秒。\n\n'
            '建議先裁切至 30 秒內再匯入分析，\n'
            '以避免記憶體不足導致 App 閃退。\n\n'
            '確定繼續分析整支影片？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('繼續分析'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    // ── 品質選擇對話框（僅短影片需要編碼，長影片直接跳過）────────────
    // 完整分析固定使用 V1 骨架分析（V1/V2 切換是給「擊球偵測」用的）
    ExportQuality selectedQuality = ExportQuality.standard;
    if (!_isLongVideo && mounted) {
      final skipToday = await _SkipHelper.shouldSkip('combined_analysis');
      if (skipToday) {
        selectedQuality = await _SkipHelper.savedQuality();
      } else {
        final lastQ = await _SkipHelper.savedQuality();
        if (!mounted) return;
        final result = await showDialog<_QualityDialogResult>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => _ExportQualityDialog(initialQuality: lastQ),
        );
        if (result == null) return;
        selectedQuality = result.quality;
        if (result.skipToday) {
          await _SkipHelper.markSkipToday('combined_analysis');
          await _SkipHelper.saveQuality(selectedQuality);
        }
      }
    }

    setState(() => _isAnalyzing = true);

    if (!mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備中...'));
    final cancelToken = _CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: '🎬 完整分析中',
        progressNotifier: progressNotifier,
        progressColor: Colors.cyan,
        onCancel: () {
          cancelToken.cancel();
          unawaited(_cancelNativeAnalysis());
          navigator.pop();
          if (mounted) setState(() => _isAnalyzing = false);
          messenger.showSnackBar(const SnackBar(content: Text('已取消完整分析')));
        },
      ),
    );

    try {
      final clipPath     = widget.entry.filePath;
      final sessionDir   = p.dirname(clipPath);
      final csvPath      = p.join(sessionDir, 'pose_landmarks.csv');
      final durationSeconds = widget.entry.durationSeconds;

      // 檢查時長有效性
      if (durationSeconds < 1 || durationSeconds > 600) {
        throw '影片時長 ($durationSeconds 秒) 不符合要求 (1-600 秒)';
      }

      // Stage 1: 視頻分析（0-70%）
      debugPrint('[完整分析] 開始視頻分析...');
      progressNotifier.value = (0.0, '視頻分析中...');

      late RecordingHistoryEntry updatedEntry;

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

        if (cancelToken.isCancelled) return;
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
          quality: selectedQuality,
          mode: SkeletonAnalysisMode.v1,   // 完整分析固定使用 V1
          onProgress: (label) {
            progressNotifier.value = (0.35, label);
          },
        );

        if (cancelToken.isCancelled) return;
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

      if (cancelToken.isCancelled) return;

      // 在 analyze() 之後重新確認 CSV 是否存在（首次分析時由 analyze() 產生）
      final hasCsv = File(csvPath).existsSync();

      // 完整分析後（原始影片 or V2 localClip），重新偵測揮桿 8 階段並寫入 phases.json。
      // 原本限制 _isOriginalVideo，但 V2 切片執行完整分析後 CSV 已重算，
      // 必須重新偵測才能產出正確的 8 階段資料。
      // 長影片（isLongVideo）的切片由「偵測擊球」時的 _trimHit 負責寫入。
      if (!_isLongVideo && hasCsv) {
        try {
          progressNotifier.value = (0.68, '偵測揮桿階段...');
          final phaseHits = await SwingImpactDetector.detect(csvPath: csvPath);
          if (phaseHits.isNotEmpty) {
            await ClipPipelineService.savePhasesJson(
              sessionDir: sessionDir,
              hit: phaseHits.first,
              clipActualStartSec: 0.0,  // CSV 已是 clip 相對時間
            );
            // 同步更新 hitSecond，供播放器 impact 鑽石顯示
            updatedEntry = updatedEntry.copyWith(
              hitSecond: phaseHits.first.hitSec,
            );
            debugPrint('[完整分析] ✅ phases.json 寫出完成 (hit=${phaseHits.first.hitSec.toStringAsFixed(2)}s)');
          } else {
            debugPrint('[完整分析] ⚠️ SwingImpactDetector 未偵測到擊球，略過 phases.json');
          }
        } catch (e) {
          debugPrint('[完整分析] ⚠️ phases 偵測失敗 (略過): $e');
        }
      }

      if (cancelToken.isCancelled) return;

      // Stage 2: 音頻分析（70-100%）
      progressNotifier.value = (0.7, '音頻分析中...');
      final audioResult = await _analyzeWavFile(
        sessionDir:    sessionDir,
        clipPath:      clipPath,
        targetHitTime: widget.entry.hitSecond,
        onProgress:    (progress, message) => progressNotifier.value = (progress, message),
      );

      if (cancelToken.isCancelled) return;
      navigator.pop(); // 無論 mounted 與否，一定關閉 Dialog
      if (mounted) setState(() => _isAnalyzing = false);

      // Stage 3: 合併結果並更新條目
      if (audioResult != null) {
        updatedEntry = updatedEntry.copyWith(
          audioCrispness: audioResult.features.isNotEmpty
              ? audioResult.features.first.sharpnessHfxLoud
              : null,
          goodShot: audioResult.predictedClass == 'good',
          audioLabel: audioResult.feedbackLabel,
          audioPassCount: audioResult.passCount,
          audioPasses: audioResult.passes.isNotEmpty ? audioResult.passes : null,
          audioFeatureValues: audioResult.featureValues.isNotEmpty ? audioResult.featureValues : null,
        );
      }

      widget.onEntryUpdated?.call(widget.entry, updatedEntry);

      // 保底：確保 filePath 改變時舊條目一定從 DB 刪除，防止 callback 找不到條目
      // 而留下雙筆（clip.mp4 + final.mp4）的 bug
      if (widget.entry.filePath != updatedEntry.filePath) {
        unawaited(RecordingHistoryStorage.instance.deleteEntry(widget.entry.filePath));
      }
      unawaited(RecordingHistoryStorage.instance.upsertEntry(updatedEntry));

      final videoId       = p.basename(sessionDir);
      final entrySnapshot = updatedEntry;

      // 背景更新 ONNX 姿勢資料（posture_only，不消耗 AI 配額）
      if (hasCsv) {
        _triggerPostureAnalysisInBackground(
          videoId:  videoId,
          clipPath: entrySnapshot.filePath,
          csvPath:  csvPath,
          onPostureResult: (postureLabel, analysisId) {
            final withPosture = entrySnapshot.copyWith(
              swingPostureLabel: postureLabel,
              postureAnalysisId: analysisId,
            );
            RecordingHistoryStorage.instance.upsertEntry(withPosture);
            if (!mounted) return;
            widget.onEntryUpdated?.call(entrySnapshot, withPosture);
          },
        );
      }
      final audioMsg = audioResult != null
          ? '\n🎵 音頻：${audioResult.feedbackLabel}'
          : '';
      await AdService.showFullAnalysisInterstitial();
      messenger.showSnackBar(SnackBar(
        content: Text('完整分析完成 ✅$audioMsg'),
        duration: const Duration(seconds: 4),
      ));
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

  /// 背景錯誤姿勢分析：提交 posture_only 分析，輪詢直到 idle，回傳最佳錯誤類型。
  /// 不阻塞 UI，失敗時靜默忽略。
  void _triggerPostureAnalysisInBackground({
    required String videoId,
    required String clipPath,
    required String csvPath,
    required void Function(String? postureLabel, String analysisId) onPostureResult,
  }) {
    unawaited(() async {
      try {
        final svc = AnalysisService.instance;
        final analysisId = await svc.submitForAnalysis(
          videoId:  videoId,
          clipPath: clipPath,
          csvPath:  csvPath,
          mode:     'posture_only',
        );
        debugPrint('[PostureAnalysis] 已提交: $analysisId');

        // 輪詢，最多 90 秒（每 6 秒一次）
        for (int i = 0; i < 15; i++) {
          await Future<void>.delayed(const Duration(seconds: 6));
          final status = await svc.getStatus(analysisId);
          debugPrint('[PostureAnalysis] 狀態: ${status.status}');

          if (status.isIdle) {
            final topError = status.onnxResult?.officialErrors.firstOrNull
                          ?? status.onnxResult?.suspectErrors.firstOrNull;
            debugPrint('[PostureAnalysis] 完成，topError=$topError');
            onPostureResult(topError ?? '', analysisId);
            return;
          }
          if (status.isFailed) {
            debugPrint('[PostureAnalysis] 失敗，略過');
            return;
          }
        }
        debugPrint('[PostureAnalysis] 逾時，略過');
      } catch (e) {
        debugPrint('[PostureAnalysis] 例外: $e');
      }
    }());
  }

  /// 提交影片到 AI 教練後端，並跳轉至結果頁面
  Future<void> _runAiAnalysis() async {
    if (_isSubmittingAi) return;

    // ── 球數配額檢查（已分析過不消耗球數，跳過）─────────────────────
    if (!widget.entry.hasAiCoachAnalysis) {
      if (!mounted) return;
      final planStatus = await PlanService.getPlanStatus();
      if (!mounted) return;
      if (!planStatus.plan.isUnlimited && planStatus.remaining <= 0) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.sports_golf_rounded,
                color: Color(0xFF7C3AED), size: 32),
            title: const Text('今日球數已用完'),
            content: Text(
              '今日已使用 ${planStatus.todayUsed} 次，已達上限 ${planStatus.totalLimit} 次。\n\n'
              '明天可繼續使用，或升級方案取得更多次數。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    }

    // ── 確認對話框（已分析過 / 今日不再提醒 → 跳過）─────────────────
    if (mounted && !widget.entry.hasAiCoachAnalysis) {
      final skipToday = await _SkipHelper.shouldSkip('ai_analysis');
      if (!skipToday) {
        if (!mounted) return;
        final result = await showDialog<_ConfirmResult>(
          context: context,
          barrierDismissible: true,
          builder: (_) => const _ConfirmActionDialog(
            icon: Icons.psychology_rounded,
            iconColor: Color(0xFF7C3AED),
            title: '確定送出 AI 分析？',
            description: '影片將上傳至 AI 教練系統進行分析，請確認網路連線正常。',
            confirmLabel: '送出分析',
          ),
        );
        if (result == null) return; // 使用者取消
        if (result.skipToday) {
          await _SkipHelper.markSkipToday('ai_analysis');
        }
      }
    }

    // ── AI 分析模式選擇 ───────────────────────────────────────────────────
    if (!mounted) return;
    final sessionDirForMode = p.dirname(widget.entry.filePath);
    final aiMode = await _showAiModeDialog(context, sessionDirForMode);
    if (aiMode == null) return;

    setState(() => _isSubmittingAi = true);
    if (!mounted) { setState(() => _isSubmittingAi = false); return; }
    try {
      final sessionDir = p.dirname(widget.entry.filePath);
      final csvPath    = p.join(sessionDir, 'pose_landmarks.csv');
      final hasCsv     = File(csvPath).existsSync();
      final audioPath  = p.join(sessionDir, 'audio.wav');
      // videoId 使用 session 目錄名稱（如 "1779413178538_hit_1"），
      // 符合後端 video_id varchar(255) 長度限制，避免送完整路徑超長
      final videoId    = p.basename(sessionDir);

      // ignore: use_build_context_synchronously
      await AdService.showAiCoachInterstitial();
      var aiCallbackFired = false;
      await AiCoachPage.submitAndPush(
        context:          context,
        videoId:          videoId,
        clipPath:         widget.entry.filePath,
        csvPath:          hasCsv ? csvPath : null,
        audioPath:        audioPath,
        promptVersion:    aiMode.promptVersion,
        phaseTimestamps:  aiMode.phaseTimestamps,
        audioAnalysisJson: _buildAudioAnalysisJson(widget.entry),
        onAnalysisComplete: (geminiErrorType, onnxErrorType, analysisId, result) {
          aiCallbackFired = true;
          final updated = widget.entry.copyWith(
            hasAiCoachAnalysis: true,
            geminiPostureLabel: geminiErrorType,
            // posture_only 已設定的 swingPostureLabel 優先保留，僅在 null 時才從 full 回填
            swingPostureLabel:  widget.entry.swingPostureLabel ?? onnxErrorType,
            postureAnalysisId:  analysisId,
            aiPromptVersion:    aiMode.promptVersion,
            practiceSuggestions: result?.practiceSuggestions
                .map((s) => PracticeSuggestionItem(
                      drill:       s.drill,
                      instruction: s.instruction,
                      reps:        s.reps,
                    ))
                .toList(),
            nextTrainingGoal:   result?.nextTrainingGoal,
          );
          // DB 存檔不需要 mounted，確保離開頁面後資料仍能寫入
          RecordingHistoryStorage.instance.upsertEntry(updated);
          StatisticsService().loadAllStatistics();
          unawaited(PlanService.getPlanStatus());
          if (!mounted) return;
          widget.onEntryUpdated?.call(widget.entry, updated);
        },
      );

      // 若 callback 尚未觸發（後端仍在處理），至少先標記已送出
      if (!aiCallbackFired) {
        final updated = widget.entry.copyWith(hasAiCoachAnalysis: true);
        RecordingHistoryStorage.instance.upsertEntry(updated);
        if (mounted) widget.onEntryUpdated?.call(widget.entry, updated);
      }
    } catch (e) {
      debugPrint('[AI分析] 提交失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 分析提交失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingAi = false);
    }
  }

  bool _isDownloading = false;

  /// 下載影片到裝置（顯示版本選單 + 儲存位置選擇）
  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    final sessionDir = p.dirname(widget.entry.filePath);

    final chosen = await _showDownloadPicker(context, sessionDir);
    if (chosen == null || !mounted) return;

    // 選擇儲存位置：下載資料夾 or 自選資料夾
    final toFolder = await _showSaveLocationPicker(context);
    if (toFolder == null || !mounted) return;

    setState(() => _isDownloading = true);
    try {
      final videoPath = p.join(sessionDir, chosen.file);
      final baseName  = (widget.entry.customName?.isNotEmpty == true)
          ? '${widget.entry.customName!}_${chosen.label}'
          : '${p.basenameWithoutExtension(widget.entry.filePath)}_${chosen.label}';
      final result = toFolder
          ? await VideoExportService.downloadToFolder(videoPath, displayName: baseName)
          : await VideoExportService.download(videoPath, displayName: baseName);
      if (!mounted) return;
      _showDownloadResultSnackBar(result, chosen.label);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showDownloadResultSnackBar(ExportResult result, String label) {
    switch (result.status) {
      case ExportStatus.savedToDownloads:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「$label」已儲存 ✅'),
          backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
        ));
      case ExportStatus.savedToPhotos:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「$label」已儲存到相機膠卷 ✅'),
          backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
        ));
      case ExportStatus.sharedViaSheet:
        break;
      case ExportStatus.failed:
        if (result.detail != 'cancelled') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('下載失敗：${result.detail}'),
            backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
          ));
        }
    }
  }

  /// 分享 session
  void _shareSession() {
    ShareUploadDialog.show(
      context,
      entry: widget.entry,
      onShareSaved: (updated) => widget.onEntryUpdated?.call(widget.entry, updated),
    );
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

  // ── Badge 輔助 ────────────────────────────────────────────────

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _badgeWithIcon(String label, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool loading = false,
  }) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: color))
                    : Icon(icon, size: 18, color: color),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 計算屬於此影片的切片（按擊球時間排序）
    final clips = widget.allEntries
        .where((e) =>
            e.videoType == VideoType.localClip &&
            e.sourceVideoPath == widget.entry.filePath)
        .toList()
      ..sort((a, b) => (a.startSecond ?? a.hitSecond ?? 0)
          .compareTo(b.startSecond ?? b.hitSecond ?? 0));
    final hasClips = clips.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 主卡片 ──────────────────────────────────────────────
        Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.08),
      elevation: 2,
      child: Stack(
        children: [
        InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 主體區域 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 40, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 縮圖
                  _HistoryPreview(
                    thumbnailPath: widget.entry.thumbnailPath,
                    roundIndex: widget.entry.roundIndex,
                    durationSeconds: widget.entry.durationSeconds,
                  ),
                  const SizedBox(width: 12),
                  // 標題 + 時間 + 標籤
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 標題
                        Text(
                          widget.entry.displayTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF123B70),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        // 時間資訊
                        Row(children: [
                          const Icon(Icons.access_time_rounded,
                              size: 12, color: Color(0xFF9AA6B2)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${widget.formattedTime} · ${widget.entry.durationSeconds}秒',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF9AA6B2)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        if (widget.formattedImportTime != null) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.download_rounded,
                                size: 12, color: Color(0xFF9AA6B2)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${widget.formattedImportTime!}${widget.entry.sharerName != null ? '  · 來自 ${widget.entry.sharerName}' : ''}',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF9AA6B2)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 7),
                        // 標籤列（基本 badges）
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _badge(
                              _isLongVideo ? '長影片' : '短影片',
                              _isLongVideo
                                  ? const Color(0xFF1565C0)
                                  : const Color(0xFF757575),
                            ),
                            if (widget.entry.videoType == VideoType.original &&
                                widget.entry.isClipped)
                              _badge('已切片', const Color(0xFFFF9800)),
                            if (widget.entry.audioTags
                                    ?.contains('no_audio') ==
                                true)
                              _badge('無聲音', const Color(0xFF9E9E9E)),
                            if (widget.entry.isAnalyzed)
                              _badge('已分析', const Color(0xFF1E8E5A)),
                            if (widget.entry.hasAiCoachAnalysis)
                              _badgeWithIcon('AI', const Color(0xFF7C3AED),
                                  Icons.psychology_rounded),
                            if (widget.entry.swingPostureLabel != null)
                              _badgeWithIcon(
                                SwingPosture.zhName(widget.entry.swingPostureLabel!),
                                const Color(0xFF1565C0),
                                Icons.memory_rounded,
                              ),
                            if (widget.entry.geminiPostureLabel != null)
                              _badgeWithIcon(
                                SwingPosture.zhName(widget.entry.geminiPostureLabel!),
                                const Color(0xFF7C3AED),
                                Icons.auto_awesome_rounded,
                              ),
                          ],
                        ),
                        // ── 速度 + 甜蜜點 數據行（未分析時反灰）────────
                        if (!_isLongVideo) ...[
                          const SizedBox(height: 6),
                          Builder(builder: (context) {
                            final hasSpeed = widget.entry.bestSpeedValue != null &&
                                widget.entry.bestSpeedValue! > 0;
                            final goodShot = widget.entry.goodShot;
                            final dimColor = const Color(0xFFCBD0D8);
                            final speedColor = hasSpeed
                                ? const Color(0xFF1565C0)
                                : dimColor;
                            final sweetColor = goodShot == true
                                ? const Color(0xFF4CAF50)
                                : goodShot == false
                                    ? const Color(0xFFF44336)
                                    : dimColor;
                            return Row(
                              children: [
                                Icon(Icons.speed_rounded,
                                    size: 13, color: speedColor),
                                const SizedBox(width: 3),
                                Text(
                                  hasSpeed
                                      ? widget.entry.bestSpeedValue!
                                          .toStringAsFixed(1)
                                      : '—',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: speedColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 1,
                                  height: 13,
                                  color: const Color(0xFFE0E4EA),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '甜蜜點',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF9AA6B2)),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: sweetColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color:
                                            sweetColor.withValues(alpha: 0.45)),
                                  ),
                                  child: Text(
                                    goodShot == true
                                        ? '命中'
                                        : goodShot == false
                                            ? '未命中'
                                            : '—',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: sweetColor,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                        // ── 5大音頻特徵 數據條行（未分析時反灰）────────
                        if (!_isLongVideo) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              for (final feat
                                  in AudioAnalysisService.featureLabels
                                      .entries) ...[
                                if (feat.key !=
                                    AudioAnalysisService.featureLabels.keys
                                        .first)
                                  const SizedBox(width: 4),
                                Expanded(
                                  child: _AudioFeatureMiniBar(
                                    label: feat.value,
                                    featureKey: feat.key,
                                    value: widget.entry.audioPasses == null
                                        ? null
                                        : (widget.entry.audioFeatureValues ?? const <String, double>{})[feat.key],
                                    passed: widget.entry.audioPasses == null
                                        ? false
                                        : widget.entry.audioPasses![feat.key] ?? false,
                                    enabled: widget.entry.audioPasses != null,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── 擊球摘要 ──────────────────────────────────────────
            FutureBuilder<List<HitsSummary>>(
              future: _hitsSummaryFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: HitsSummaryExpansionTile(
                    hitsSummary: snapshot.data!,
                    title: '擊球摘要',
                    initiallyExpanded: false,
                  ),
                );
              },
            ),
            // ── 底部操作列 ────────────────────────────────────────
            const Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F5)),
            IntrinsicHeight(
              child: Row(
                children: [
                  _actionBtn(
                    icon: Icons.bar_chart_rounded,
                    label: '圖表',
                    color: const Color(0xFF1565C0),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            RecordingDetailPage(entry: widget.entry))),
                  ),
                  const VerticalDivider(
                      width: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                  _actionBtn(
                    icon: Icons.play_arrow_rounded,
                    label: '播放',
                    color: const Color(0xFF1E8E5A),
                    onTap: widget.onTap,
                  ),
                  const VerticalDivider(
                      width: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                  if (_isLongVideo && _isOriginalVideo && widget.entry.isClipped && hasClips)
                    _actionBtn(
                      icon: _isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      label: _isExpanded ? '折疊擊球' : '展開擊球',
                      color: const Color(0xFFE65100),
                      onTap: () => setState(() => _isExpanded = !_isExpanded),
                    )
                  else if (_isLongVideo && _isOriginalVideo && !widget.entry.isClipped)
                    _actionBtn(
                      icon: Icons.sports_golf_rounded,
                      label: '偵測擊球',
                      color: const Color(0xFFE65100),
                      loading: _isDetecting,
                      onTap: _runDetection,
                    )
                  else if (!_isAnalyzed)
                    _actionBtn(
                      icon: Icons.analytics_rounded,
                      label: '完整分析',
                      color: const Color(0xFF00838F),
                      loading: _isAnalyzing,
                      onTap: _runCombinedAnalysis,
                    )
                  else
                    _actionBtn(
                      icon: Icons.psychology_rounded,
                      label: 'AI 分析',
                      color: const Color(0xFF7C3AED),
                      loading: _isSubmittingAi,
                      onTap: _runAiAnalysis,
                    ),
                ],
              ),
            ),
          ],
        ),
        ),
        // ── 右上角更多選單按鈕 ──────────────────────────────────
        Positioned(
          top: 4,
          right: 4,
          child: PopupMenuButton<_HistoryMenuAction>(
            tooltip: '更多操作',
            icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF9AA6B2),
                size: 20),
            padding: EdgeInsets.zero,
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
                  case _HistoryMenuAction.download:
                    _downloadVideo();
                    break;
                  case _HistoryMenuAction.delete:
                    widget.onDelete();
                    break;
                }
              });
            },
            itemBuilder: (context) {
              final canAnalyze = (_isClip || (!_isLongVideo && _isOriginalVideo)) && !_isAnalyzed;
              final canCompare = !_isLongVideo && widget.allEntries
                  .where((e) =>
                      e.filePath != widget.entry.filePath &&
                      e.durationSeconds <= 5 &&
                      File(e.filePath).existsSync())
                  .isNotEmpty;
              final canShare = !_isLongVideo && _isAnalyzed;
              return [
                const PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.rename,
                  child: Text('重新命名'),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.analyze,
                  enabled: canAnalyze && !_isAnalyzing,
                  child: Row(children: [
                    Text(
                        _isAnalyzing ? '分析中...' : '完整分析',
                        style: TextStyle(
                            color: (!canAnalyze || _isAnalyzing)
                                ? Colors.grey
                                : null)),
                    if (_isAnalyzing) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)),
                    ],
                  ]),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.compare,
                  enabled: canCompare,
                  child: Text('與另一部影片比較',
                      style: TextStyle(
                          color: canCompare ? null : Colors.grey)),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.share,
                  enabled: canShare,
                  child: Row(children: [
                    Icon(Icons.share_outlined,
                        size: 16,
                        color: canShare
                            ? const Color(0xFF1E8E5A)
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text('分享連結',
                        style: TextStyle(
                            color: canShare ? null : Colors.grey)),
                  ]),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.download,
                  enabled: !_isDownloading,
                  child: Row(children: [
                    Icon(Icons.download_rounded,
                        size: 16,
                        color: _isDownloading
                            ? Colors.grey
                            : const Color(0xFF1E8E5A)),
                    const SizedBox(width: 8),
                    Text(_isDownloading ? '下載中...' : '下載影片'),
                  ]),
                ),
                const PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.delete,
                  child: Text('刪除影片'),
                ),
              ];
            },
          ),
        ),
        ],
      ),
    ),
    // ── 展開的切片卡片（AnimatedSize 平滑動畫）────────────────
    AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _isExpanded && hasClips
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: clips.asMap().entries.map((e) => Padding(
                  padding: EdgeInsets.only(
                      bottom: e.key < clips.length - 1 ? 8 : 0),
                  child: _ClipSubCard(
                    key: ValueKey(clips[e.key].filePath),
                    clip: e.value,
                    clipIndex: e.key + 1,
                    onEntryUpdated: widget.onEntryUpdated,
                    onDelete: () => widget.onDeleteClip?.call(clips[e.key]),
                  ),
                )).toList(),
              ),
            )
          : const SizedBox.shrink(),
    ),
  ],
  );
  }
}


/// 縮圖元件：顯示影片預覽或替代圖示，並標示錄影輪次與時長
class _HistoryPreview extends StatelessWidget {
  final String? thumbnailPath;
  final int roundIndex;
  final int durationSeconds;

  const _HistoryPreview({
    required this.thumbnailPath,
    required this.roundIndex,
    required this.durationSeconds,
  });

  String _fmtDur(int s) {
    if (s >= 60) {
      final m = s ~/ 60;
      final sec = s % 60;
      return '${m}m${sec}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final filePath = thumbnailPath?.trim() ?? '';
    final hasThumbnail = filePath.isNotEmpty && File(filePath).existsSync();

    final Widget content = hasThumbnail
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(filePath),
              width: 130,
              height: 82,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: 130,
            height: 82,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EBF5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.videocam_outlined,
                color: Color(0xFF123B70), size: 32),
          );

    final overlayDeco = BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(6),
    );
    const overlayStyle = TextStyle(
        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600);

    return Stack(
      children: [
        content,
        // 第N輪 — 左上角
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: overlayDeco,
            child: Text('第$roundIndex輪', style: overlayStyle),
          ),
        ),
        // 時長 — 右下角
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: overlayDeco,
            child: Text(_fmtDur(durationSeconds), style: overlayStyle),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 切片子卡片：巢狀顯示在長影片卡片下方
// ────────────────────────────────────────────────────────────────────────────

class _ClipSubCard extends StatefulWidget {
  final RecordingHistoryEntry clip;
  final int clipIndex;
  final void Function(RecordingHistoryEntry old, RecordingHistoryEntry updated)? onEntryUpdated;
  final VoidCallback? onDelete;

  const _ClipSubCard({
    super.key,
    required this.clip,
    required this.clipIndex,
    this.onEntryUpdated,
    this.onDelete,
  });

  @override
  State<_ClipSubCard> createState() => _ClipSubCardState();
}

class _ClipSubCardState extends State<_ClipSubCard> {
  bool _isSubmittingAi = false;
  bool _isAnalyzing = false;

  /// 重新命名切片
  Future<void> _rename() async {
    final clip = widget.clip;
    final initial = clip.customName?.trim().isNotEmpty == true
        ? clip.customName!.trim()
        : '第 ${widget.clipIndex} 球';
    String tempName = initial;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新命名切片'),
        content: TextField(
          controller: TextEditingController(text: initial),
          maxLength: 40,
          decoration: const InputDecoration(labelText: '名稱', helperText: '可留空以恢復預設'),
          onChanged: (v) => tempName = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(tempName),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    final trimmed = newName.trim();
    widget.onEntryUpdated?.call(
      clip,
      clip.copyWith(customName: trimmed.isEmpty ? null : trimmed),
    );
  }

  /// 分享切片
  void _share() {
    ShareUploadDialog.show(
      context,
      entry: widget.clip,
      onShareSaved: (updated) => widget.onEntryUpdated?.call(widget.clip, updated),
    );
  }

  bool _isDownloading = false;

  /// 下載切片影片到裝置（顯示版本選單）
  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    final sessionDir = p.dirname(widget.clip.filePath);

    final chosen = await _showDownloadPicker(context, sessionDir);
    if (chosen == null || !mounted) return;

    final toFolder = await _showSaveLocationPicker(context);
    if (toFolder == null || !mounted) return;

    setState(() => _isDownloading = true);
    try {
      final videoPath = p.join(sessionDir, chosen.file);
      final baseName  = (widget.clip.customName?.isNotEmpty == true)
          ? '${widget.clip.customName!}_${chosen.label}'
          : '${p.basenameWithoutExtension(widget.clip.filePath)}_${chosen.label}';
      final result = toFolder
          ? await VideoExportService.downloadToFolder(videoPath, displayName: baseName)
          : await VideoExportService.download(videoPath, displayName: baseName);
      if (!mounted) return;
      _showClipDownloadResultSnackBar(result, chosen.label);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showClipDownloadResultSnackBar(ExportResult result, String label) {
    switch (result.status) {
      case ExportStatus.savedToDownloads:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「$label」已儲存 ✅'),
          backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
        ));
      case ExportStatus.savedToPhotos:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「$label」已儲存到相機膠卷 ✅'),
          backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
        ));
      case ExportStatus.sharedViaSheet:
        break;
      case ExportStatus.failed:
        if (result.detail != 'cancelled') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('下載失敗：${result.detail}'),
            backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
          ));
        }
    }
  }

  /// 完整分析（短影片）
  Future<void> _runCombinedAnalysis() async {
    if (_isAnalyzing) return;

    // 完整分析固定使用 V1 骨架分析
    ExportQuality selectedQuality = ExportQuality.standard;
    if (mounted) {
      final skipToday = await _SkipHelper.shouldSkip('combined_analysis');
      if (skipToday) {
        selectedQuality = await _SkipHelper.savedQuality();
      } else {
        final lastQ = await _SkipHelper.savedQuality();
        if (!mounted) return;
        final result = await showDialog<_QualityDialogResult>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => _ExportQualityDialog(initialQuality: lastQ),
        );
        if (result == null) return;
        selectedQuality = result.quality;
        if (result.skipToday) {
          await _SkipHelper.markSkipToday('combined_analysis');
          await _SkipHelper.saveQuality(selectedQuality);
        }
      }
    }

    setState(() => _isAnalyzing = true);
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備中...'));
    final cancelToken = _CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: '🎬 完整分析中',
        progressNotifier: progressNotifier,
        progressColor: Colors.cyan,
        onCancel: () {
          cancelToken.cancel();
          unawaited(_cancelNativeAnalysis());   // 通知 Kotlin 停止分析迴圈
          navigator.pop();
          if (mounted) setState(() => _isAnalyzing = false);
          messenger.showSnackBar(const SnackBar(content: Text('已取消完整分析')));
        },
      ),
    );

    try {
      final clip = widget.clip;
      final clipPath = clip.filePath;
      final sessionDir = p.dirname(clipPath);
      final durationSeconds = clip.durationSeconds;

      if (durationSeconds < 1 || durationSeconds > 600) {
        throw '影片時長 ($durationSeconds 秒) 不符合要求 (1-600 秒)';
      }

      progressNotifier.value = (0.0, '視頻分析中...');
      final result = await ClipPipelineService.analyze(
        clipPath: clipPath,
        sessionDir: sessionDir,
        durationSeconds: durationSeconds,
        hitSec: clip.hitSecond,
        quality: selectedQuality,
        mode: SkeletonAnalysisMode.v1,   // 完整分析固定使用 V1
        onProgress: (label) => progressNotifier.value = (0.35, label),
      );
      if (cancelToken.isCancelled) return;
      if (result == null) throw '視頻分析失敗';

      final silenceTags = result.hasSilence ? ['no_audio'] : null;
      var updatedEntry = clip.copyWith(
        filePath: result.finalPath,
        isAnalyzed: true,
        audioTags: silenceTags,
      );

      if (cancelToken.isCancelled) return;

      progressNotifier.value = (0.7, '音頻分析中...');
      final audioResult = await _analyzeWavFile(
        sessionDir:    sessionDir,
        clipPath:      clipPath,
        targetHitTime: clip.hitSecond,
        onProgress:    (progress, message) => progressNotifier.value = (progress, message),
      );

      if (cancelToken.isCancelled) return;

      final csvPathLocal = p.join(sessionDir, 'pose_landmarks.csv');
      final hasCsvLocal  = File(csvPathLocal).existsSync();

      // 完整分析後重新偵測揮桿 8 階段（含 V2 切片完整分析後的情況）
      if (hasCsvLocal) {
        try {
          progressNotifier.value = (0.68, '偵測揮桿階段...');
          final phaseHits = await SwingImpactDetector.detect(csvPath: csvPathLocal);
          if (phaseHits.isNotEmpty) {
            await ClipPipelineService.savePhasesJson(
              sessionDir: sessionDir,
              hit: phaseHits.first,
              clipActualStartSec: 0.0,  // CSV 已是 clip 相對時間
            );
            updatedEntry = updatedEntry.copyWith(
              hitSecond: phaseHits.first.hitSec,
            );
            debugPrint('[切片完整分析] ✅ phases.json 寫出 (hit=${phaseHits.first.hitSec.toStringAsFixed(2)}s)');
          }
        } catch (e) {
          debugPrint('[切片完整分析] ⚠️ phases 偵測失敗 (略過): $e');
        }
      }

      if (cancelToken.isCancelled) return;

      navigator.pop();
      if (mounted) setState(() => _isAnalyzing = false);

      if (audioResult != null) {
        updatedEntry = updatedEntry.copyWith(
          audioCrispness: audioResult.features.isNotEmpty
              ? audioResult.features.first.sharpnessHfxLoud
              : null,
          goodShot: audioResult.predictedClass == 'good',
          audioLabel: audioResult.feedbackLabel,
          audioPassCount: audioResult.passCount,
          audioPasses: audioResult.passes.isNotEmpty ? audioResult.passes : null,
          audioFeatureValues: audioResult.featureValues.isNotEmpty ? audioResult.featureValues : null,
        );
      }
      widget.onEntryUpdated?.call(clip, updatedEntry);

      // 保底：確保 filePath 改變時舊條目一定從 DB 刪除，防止雙筆 bug
      if (clip.filePath != updatedEntry.filePath) {
        unawaited(RecordingHistoryStorage.instance.deleteEntry(clip.filePath));
      }
      unawaited(RecordingHistoryStorage.instance.upsertEntry(updatedEntry));

      final videoId       = p.basename(sessionDir);
      final entrySnapshot = updatedEntry;

      // 背景更新 ONNX 姿勢資料（posture_only，不消耗 AI 配額）
      if (hasCsvLocal) {
        _triggerPostureAnalysisInBackground(
          videoId:  videoId,
          clipPath: entrySnapshot.filePath,
          csvPath:  csvPathLocal,
          onPostureResult: (postureLabel, analysisId) {
            final withPosture = entrySnapshot.copyWith(
              swingPostureLabel: postureLabel,
              postureAnalysisId: analysisId,
            );
            RecordingHistoryStorage.instance.upsertEntry(withPosture);
            if (!mounted) return;
            widget.onEntryUpdated?.call(entrySnapshot, withPosture);
          },
        );
      }
      final audioMsg = audioResult != null ? '\n🎵 音頻：${audioResult.feedbackLabel}' : '';
      await AdService.showFullAnalysisInterstitial();
      messenger.showSnackBar(SnackBar(
        content: Text('完整分析完成 ✅$audioMsg'),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      debugPrint('[切片完整分析] 錯誤: $e');
      navigator.pop();
      if (mounted) setState(() => _isAnalyzing = false);
      messenger.showSnackBar(SnackBar(
        content: Text('完整分析失敗: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      progressNotifier.dispose();
    }
  }

  Future<void> _play() async {
    final file = File(widget.clip.filePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('影片檔案不存在，可能已被刪除')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoPath: widget.clip.filePath,
          entry: widget.clip, // 傳入 entry 以顯示圖表與 AI 分析面板
        ),
      ),
    );
  }

  /// 背景錯誤姿勢分析：提交 posture_only 分析，輪詢直到 idle，回傳最佳錯誤類型。
  /// 不阻塞 UI，失敗時靜默忽略。
  void _triggerPostureAnalysisInBackground({
    required String videoId,
    required String clipPath,
    required String csvPath,
    required void Function(String? postureLabel, String analysisId) onPostureResult,
  }) {
    unawaited(() async {
      try {
        final svc = AnalysisService.instance;
        final analysisId = await svc.submitForAnalysis(
          videoId:  videoId,
          clipPath: clipPath,
          csvPath:  csvPath,
          mode:     'posture_only',
        );
        debugPrint('[PostureAnalysis] 已提交: $analysisId');

        // 輪詢，最多 90 秒（每 6 秒一次）
        for (int i = 0; i < 15; i++) {
          await Future<void>.delayed(const Duration(seconds: 6));
          final status = await svc.getStatus(analysisId);
          debugPrint('[PostureAnalysis] 狀態: ${status.status}');

          if (status.isIdle) {
            final topError = status.onnxResult?.officialErrors.firstOrNull
                          ?? status.onnxResult?.suspectErrors.firstOrNull;
            debugPrint('[PostureAnalysis] 完成，topError=$topError');
            onPostureResult(topError ?? '', analysisId);
            return;
          }
          if (status.isFailed) {
            debugPrint('[PostureAnalysis] 失敗，略過');
            return;
          }
        }
        debugPrint('[PostureAnalysis] 逾時，略過');
      } catch (e) {
        debugPrint('[PostureAnalysis] 例外: $e');
      }
    }());
  }

  Future<void> _runAiAnalysis() async {
    if (_isSubmittingAi) return;

    // ── 球數配額檢查（已分析過不消耗球數，跳過）─────────────────────
    if (!widget.clip.hasAiCoachAnalysis) {
      if (!mounted) return;
      final planStatus = await PlanService.getPlanStatus();
      if (!mounted) return;
      if (!planStatus.plan.isUnlimited && planStatus.remaining <= 0) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.sports_golf_rounded,
                color: Color(0xFF7C3AED), size: 32),
            title: const Text('今日球數已用完'),
            content: Text(
              '今日已使用 ${planStatus.todayUsed} 次，已達上限 ${planStatus.totalLimit} 次。\n\n'
              '明天可繼續使用，或升級方案取得更多次數。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    }

    // ── 確認對話框（已分析過 / 今日不再提醒 → 跳過）─────────────────
    if (mounted && !widget.clip.hasAiCoachAnalysis) {
      final skipToday = await _SkipHelper.shouldSkip('ai_analysis');
      if (!skipToday) {
        if (!mounted) return;
        final result = await showDialog<_ConfirmResult>(
          context: context,
          barrierDismissible: true,
          builder: (_) => const _ConfirmActionDialog(
            icon: Icons.psychology_rounded,
            iconColor: Color(0xFF7C3AED),
            title: '確定送出 AI 分析？',
            description: '影片將上傳至 AI 教練系統進行分析，請確認網路連線正常。',
            confirmLabel: '送出分析',
          ),
        );
        if (result == null) return; // 使用者取消
        if (result.skipToday) {
          await _SkipHelper.markSkipToday('ai_analysis');
        }
      }
    }

    // ── AI 分析模式選擇 ───────────────────────────────────────────────────
    if (!mounted) return;
    final sessionDirForMode = p.dirname(widget.clip.filePath);
    final aiMode = await _showAiModeDialog(context, sessionDirForMode);
    if (aiMode == null) return;

    setState(() => _isSubmittingAi = true);
    if (!mounted) { setState(() => _isSubmittingAi = false); return; }
    try {
      final sessionDir = p.dirname(widget.clip.filePath);
      final csvPath    = p.join(sessionDir, 'pose_landmarks.csv');
      final hasCsv     = File(csvPath).existsSync();
      final audioPath  = p.join(sessionDir, 'audio.wav');
      final videoId    = p.basename(sessionDir);

      // ignore: use_build_context_synchronously
      await AdService.showAiCoachInterstitial();
      var aiCallbackFired = false;
      await AiCoachPage.submitAndPush(
        context:          context,
        videoId:          videoId,
        clipPath:         widget.clip.filePath,
        csvPath:          hasCsv ? csvPath : null,
        audioPath:        audioPath,
        promptVersion:    aiMode.promptVersion,
        phaseTimestamps:  aiMode.phaseTimestamps,
        audioAnalysisJson: _buildAudioAnalysisJson(widget.clip),
        onAnalysisComplete: (geminiErrorType, onnxErrorType, analysisId, result) {
          aiCallbackFired = true;
          final updated = widget.clip.copyWith(
            hasAiCoachAnalysis: true,
            geminiPostureLabel: geminiErrorType,
            swingPostureLabel:  widget.clip.swingPostureLabel ?? onnxErrorType,
            postureAnalysisId:  analysisId,
            aiPromptVersion:    aiMode.promptVersion,
            practiceSuggestions: result?.practiceSuggestions
                .map((s) => PracticeSuggestionItem(
                      drill:       s.drill,
                      instruction: s.instruction,
                      reps:        s.reps,
                    ))
                .toList(),
            nextTrainingGoal:   result?.nextTrainingGoal,
          );
          // DB 存檔不需要 mounted，確保離開頁面後資料仍能寫入
          RecordingHistoryStorage.instance.upsertEntry(updated);
          StatisticsService().loadAllStatistics();
          unawaited(PlanService.getPlanStatus());
          if (!mounted) return;
          widget.onEntryUpdated?.call(widget.clip, updated);
        },
      );

      // 若 callback 尚未觸發（後端仍在處理），至少先標記已送出
      if (!aiCallbackFired) {
        final updated = widget.clip.copyWith(hasAiCoachAnalysis: true);
        RecordingHistoryStorage.instance.upsertEntry(updated);
        if (mounted) widget.onEntryUpdated?.call(widget.clip, updated);
      }
    } catch (e) {
      debugPrint('[切片AI分析] 提交失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 分析提交失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 左側連結線 + 序號徽章 ─────────────────────────────
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 2,
                height: 16,
                color: const Color(0xFFE65100).withValues(alpha: 0.35),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFFE65100),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${widget.clipIndex}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // ── 切片卡片本體 ─────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            child: InkWell(
              onTap: _play,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 卡片主體 ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 36, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 縮圖（小尺寸）
                        _ClipThumbnail(
                          thumbnailPath: clip.thumbnailPath,
                          durationSeconds: clip.durationSeconds,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clip.customName?.trim().isNotEmpty == true
                                    ? clip.customName!.trim()
                                    : '第 ${widget.clipIndex} 球',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF123B70)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (clip.hitSecond != null) ...[
                                const SizedBox(height: 3),
                                Row(children: [
                                  const Icon(Icons.sports_golf_rounded,
                                      size: 11, color: Color(0xFFE65100)),
                                  const SizedBox(width: 3),
                                  Text(
                                    '擊球 @ ${clip.hitSecond!.toStringAsFixed(1)}s',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9AA6B2)),
                                  ),
                                ]),
                              ],
                              if (clip.startSecond != null &&
                                  clip.endSecond != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '片段 ${clip.startSecond!.toStringAsFixed(1)}s ~ ${clip.endSecond!.toStringAsFixed(1)}s',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9AA6B2)),
                                ),
                              ],
                              const SizedBox(height: 5),
                              // 標籤（基本 badges）
                              Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                children: [
                                  if (clip.isAnalyzed)
                                    _smallBadge('已分析', const Color(0xFF1E8E5A)),
                                  if (clip.hasAiCoachAnalysis)
                                    _smallBadge('AI', const Color(0xFF7C3AED)),
                                  if (clip.swingPostureLabel != null)
                                    _smallBadgeWithIcon(
                                      SwingPosture.zhName(clip.swingPostureLabel!),
                                      const Color(0xFF1565C0),
                                      Icons.memory_rounded,
                                    ),
                                  if (clip.geminiPostureLabel != null)
                                    _smallBadgeWithIcon(
                                      SwingPosture.zhName(clip.geminiPostureLabel!),
                                      const Color(0xFF7C3AED),
                                      Icons.auto_awesome_rounded,
                                    ),
                                  if (clip.audioTags?.contains('no_audio') == true)
                                    _smallBadge('無聲音', const Color(0xFF9E9E9E)),
                                ],
                              ),
                              // ── 速度 + 甜蜜點 數據行（未分析時反灰）──
                              const SizedBox(height: 5),
                              Builder(builder: (context) {
                                final hasSpeed = clip.bestSpeedValue != null &&
                                    clip.bestSpeedValue! > 0;
                                final goodShot = clip.goodShot;
                                const dimColor = Color(0xFFCBD0D8);
                                final speedColor =
                                    hasSpeed ? const Color(0xFF1565C0) : dimColor;
                                final sweetColor = goodShot == true
                                    ? const Color(0xFF4CAF50)
                                    : goodShot == false
                                        ? const Color(0xFFF44336)
                                        : dimColor;
                                return Row(
                                  children: [
                                    Icon(Icons.speed_rounded,
                                        size: 12, color: speedColor),
                                    const SizedBox(width: 3),
                                    Text(
                                      hasSpeed
                                          ? clip.bestSpeedValue!.toStringAsFixed(1)
                                          : '—',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: speedColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                        width: 1,
                                        height: 11,
                                        color: const Color(0xFFE0E4EA)),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '甜蜜點',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF9AA6B2)),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: sweetColor.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: sweetColor.withValues(alpha: 0.45)),
                                      ),
                                      child: Text(
                                        goodShot == true
                                            ? '命中'
                                            : goodShot == false
                                                ? '未命中'
                                                : '—',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: sweetColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                              // ── 5大音頻特徵 數據條行（未分析時反灰）──
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  for (final feat in AudioAnalysisService
                                      .featureLabels.entries) ...[
                                    if (feat.key !=
                                        AudioAnalysisService.featureLabels.keys
                                            .first)
                                      const SizedBox(width: 3),
                                    Expanded(
                                      child: _AudioFeatureMiniBar(
                                        label: feat.value,
                                        featureKey: feat.key,
                                        value: clip.audioPasses == null
                                            ? null
                                            : (clip.audioFeatureValues ?? const <String, double>{})[feat.key],
                                        passed: clip.audioPasses == null
                                            ? false
                                            : clip.audioPasses![feat.key] ?? false,
                                        enabled: clip.audioPasses != null,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── 操作列 ──────────────────────────────────
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        _clipBtn(
                          icon: Icons.bar_chart_rounded,
                          label: '圖表',
                          color: const Color(0xFF1565C0),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    RecordingDetailPage(entry: clip)),
                          ),
                        ),
                        const VerticalDivider(
                            width: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                        _clipBtn(
                          icon: Icons.play_arrow_rounded,
                          label: '播放',
                          color: const Color(0xFF1E8E5A),
                          onTap: _play,
                        ),
                        const VerticalDivider(
                            width: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                        if (!clip.isAnalyzed)
                          _clipBtn(
                            icon: Icons.analytics_rounded,
                            label: '完整分析',
                            color: const Color(0xFF00838F),
                            loading: _isAnalyzing,
                            onTap: _runCombinedAnalysis,
                          )
                        else
                          _clipBtn(
                            icon: Icons.psychology_rounded,
                            label: 'AI 分析',
                            color: const Color(0xFF7C3AED),
                            loading: _isSubmittingAi,
                            onTap: _runAiAnalysis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── 右上角選單按鈕 ───────────────────────────────────
          Positioned(
            top: 2,
            right: 2,
            child: PopupMenuButton<_ClipMenuAction>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert_rounded,
                  size: 18, color: Color(0xFF9AA6B2)),
              padding: EdgeInsets.zero,
              onSelected: (action) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  switch (action) {
                    case _ClipMenuAction.rename:
                      _rename();
                      break;
                    case _ClipMenuAction.share:
                      _share();
                      break;
                    case _ClipMenuAction.download:
                      _downloadVideo();
                      break;
                    case _ClipMenuAction.delete:
                      widget.onDelete?.call();
                      break;
                  }
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.rename,
                  child: Text('重新命名'),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.share,
                  enabled: clip.isAnalyzed,
                  child: Row(children: [
                    Icon(Icons.share_outlined,
                        size: 16,
                        color: clip.isAnalyzed
                            ? const Color(0xFF1E8E5A)
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text('分享連結',
                        style: TextStyle(
                            color:
                                clip.isAnalyzed ? null : Colors.grey)),
                  ]),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.download,
                  enabled: !_isDownloading,
                  child: Row(children: [
                    Icon(Icons.download_rounded,
                        size: 16,
                        color: _isDownloading
                            ? Colors.grey
                            : const Color(0xFF1E8E5A)),
                    const SizedBox(width: 8),
                    Text(_isDownloading ? '下載中...' : '下載影片'),
                  ]),
                ),
                const PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.delete,
                  child: Text('刪除影片',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
      ],
    );
  }

  Widget _smallBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _smallBadgeWithIcon(String label, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: color, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _clipBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool loading = false,
  }) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: color))
                    : Icon(icon, size: 16, color: color),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}

/// 切片縮圖：較小尺寸，無輪次標籤
class _ClipThumbnail extends StatelessWidget {
  final String? thumbnailPath;
  final int durationSeconds;

  const _ClipThumbnail({
    required this.thumbnailPath,
    required this.durationSeconds,
  });

  String _fmtDur(int s) {
    if (s >= 60) {
      return '${s ~/ 60}m${s % 60}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final filePath = thumbnailPath?.trim() ?? '';
    final hasThumbnail = filePath.isNotEmpty && File(filePath).existsSync();

    final Widget content = hasThumbnail
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(filePath),
              width: 90,
              height: 60,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: 90,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EBF5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.content_cut_rounded,
                color: Color(0xFFE65100), size: 24),
          );

    return Stack(
      children: [
        content,
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _fmtDur(durationSeconds),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
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

// ────────────────────────────────────────────────────────────────────────────
// 篩選／排序用的 Chip（明確指定顏色，避免 M3 seed 色推導導致文字不可見）
// ────────────────────────────────────────────────────────────────────────────

/// 自訂日期區間 Chip：點擊後開啟 DateRangePicker，選好後回調
class _DateRangeChip extends StatelessWidget {
  final bool selected;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final void Function(DateTime from, DateTime to) onPicked;

  const _DateRangeChip({
    required this.selected,
    required this.dateFrom,
    required this.dateTo,
    required this.onPicked,
  });

  String get _label {
    if (!selected || dateFrom == null) return '自訂日期';
    final from = dateFrom!;
    final to   = dateTo ?? from;
    final fmt  = (DateTime d) => '${d.month}/${d.day}';
    return '${fmt(from)} – ${fmt(to)}';
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF2196F3);
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now,
          initialDateRange: selected && dateFrom != null
              ? DateTimeRange(start: dateFrom!, end: dateTo ?? dateFrom!)
              : DateTimeRange(
                  start: now.subtract(const Duration(days: 6)),
                  end: now,
                ),
          locale: const Locale('zh', 'TW'),
          helpText: '選擇日期範圍',
          cancelText: '取消',
          confirmText: '確定',
          saveText: '確定',
        );
        if (picked != null) {
          onPicked(picked.start, DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFFBBC4CE),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 13,
              color: selected ? Colors.white : const Color(0xFF4A5568),
            ),
            const SizedBox(width: 4),
            Text(
              _label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF4A5568),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _HistoryFilterChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? selectedColor : const Color(0xFFBBC4CE),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF4A5568),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// AI 分析模式選擇
// ────────────────────────────────────────────────────────────────────────────

/// AI 分析模式選擇結果
class _AiModeResult {
  final String promptVersion;
  final Map<String, double>? phaseTimestamps;

  const _AiModeResult({
    required this.promptVersion,
    this.phaseTimestamps,
  });
}

/// 顯示 AI 分析模式選擇對話框，若 v3 選中但 phases.json 不存在則提示並返回 null。
Future<_AiModeResult?> _showAiModeDialog(
    BuildContext context, String sessionDir) async {
  final chosen = await showDialog<String>(
    context: context,
    builder: (_) => const _SelectAiModeDialog(),
  );
  if (chosen == null) return null;

  // V2：繼續彈出 FPS + Resolution 選擇
  if (chosen == 'v2') {
    return const _AiModeResult(promptVersion: 'v2');
  }

  // V3：讀取 phases.json
  Map<String, double>? phaseTimestamps;
  if (chosen == 'v3') {
    final phasesFile = File(p.join(sessionDir, 'phases.json'));
    if (!await phasesFile.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('找不到 phases.json，請先執行完整分析再選擇此模式'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }
    try {
      final raw = json.decode(await phasesFile.readAsString()) as Map<String, dynamic>;
      phaseTimestamps = raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('phases.json 格式錯誤'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  return _AiModeResult(promptVersion: chosen, phaseTimestamps: phaseTimestamps);
}

class _SelectAiModeDialog extends StatelessWidget {
  const _SelectAiModeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('選擇 AI 分析模式'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeTile(context, 'v1', Icons.flash_on_rounded,
              '原版提示詞（快速）', '標準提示，速度最快'),
          const SizedBox(height: 8),
          _modeTile(context, 'v2', Icons.videocam_rounded,
              '完整讀取影片版本（精確）', '讓 AI 完整閱讀影片後分析'),
          const SizedBox(height: 8),
          _modeTile(context, 'v3', Icons.photo_library_rounded,
              '讀取關鍵禎版本（8 大姿勢圖）', '從 phases.json 提取關鍵幀時間點'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _modeTile(BuildContext ctx, String version, IconData icon,
      String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF7C3AED)),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: () => Navigator.pop(ctx, version),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }
}


// 「今日不再提醒」SharedPreferences 輔助
// ────────────────────────────────────────────────────────────────────────────

/// 管理各操作「今日不再提醒」與最後選擇品質的持久化。
class _SkipHelper {
  _SkipHelper._();

  static String _dateKey(String action) {
    final d = DateTime.now();
    // e.g. skip_confirm_ai_analysis_2026_5_25
    return 'skip_confirm_${action}_${d.year}_${d.month}_${d.day}';
  }

  /// 今天是否已勾選「不再提醒」。
  static Future<bool> shouldSkip(String action) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dateKey(action)) ?? false;
  }

  /// 儲存「今日不再提醒」。
  static Future<void> markSkipToday(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dateKey(action), true);
  }

  // ── 完整分析品質持久化 ──────────────────────────────────────
  static const _kLastQuality = 'last_export_quality';

  static Future<ExportQuality> savedQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_kLastQuality);
    return ExportQuality.values.firstWhere(
      (q) => q.channelKey == val,
      orElse: () => ExportQuality.standard,
    );
  }

  static Future<void> saveQuality(ExportQuality q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastQuality, q.channelKey);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 結果資料類別
// ────────────────────────────────────────────────────────────────────────────

/// 確認對話框回傳：使用者已確認，並標記是否今日不再提醒。
class _ConfirmResult {
  final bool skipToday;
  const _ConfirmResult({required this.skipToday});
}

/// 品質選擇對話框回傳：選取的品質 + 是否今日不再提醒。
/// 完整分析永遠使用 V1 骨架分析（V1/V2 切換僅供「擊球偵測」使用）。
class _QualityDialogResult {
  final ExportQuality quality;
  final bool skipToday;
  const _QualityDialogResult({
    required this.quality,
    required this.skipToday,
  });
}

// ────────────────────────────────────────────────────────────────────────────
// 通用確認對話框（AI分析 / 偵測擊球）
// ────────────────────────────────────────────────────────────────────────────

/// 帶有「今日不再提醒」核取方塊的確認對話框。
/// 使用者確認 → 回傳 [_ConfirmResult]；取消 → pop(null)。
class _ConfirmActionDialog extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String confirmLabel;

  const _ConfirmActionDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.confirmLabel = '確定',
  });

  @override
  State<_ConfirmActionDialog> createState() => _ConfirmActionDialogState();
}

class _ConfirmActionDialogState extends State<_ConfirmActionDialog> {
  bool _skipToday = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Row(
        children: [
          Icon(widget.icon, color: widget.iconColor, size: 22),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF4B5563), height: 1.5),
          ),
          const SizedBox(height: 14),
          // ── 今日不再提醒 ──
          GestureDetector(
            onTap: () => setState(() => _skipToday = !_skipToday),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _skipToday,
                    onChanged: (v) => setState(() => _skipToday = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    activeColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFB0B8C1)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '今日不再提醒',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.iconColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(_ConfirmResult(skipToday: _skipToday)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 輸出品質選擇對話框（含「今日不再提醒」）
// ────────────────────────────────────────────────────────────────────────────

// ────────────────────────────────────────────────────────────────────────────
// 偵測擊球模式選擇對話框（V1 骨架 / V2 音訊）
// ────────────────────────────────────────────────────────────────────────────

class _DetectionModeResult {
  final SkeletonAnalysisMode mode;
  final bool skipToday;
  const _DetectionModeResult({required this.mode, this.skipToday = false});
}

class _DetectionModeDialog extends StatefulWidget {
  const _DetectionModeDialog();
  @override
  State<_DetectionModeDialog> createState() => _DetectionModeDialogState();
}

class _DetectionModeDialogState extends State<_DetectionModeDialog> {
  SkeletonAnalysisMode _mode = SkeletonAnalysisMode.v1;
  bool _skipToday = false;

  static const _kGreen  = Color(0xFF1E8E5A);
  static const _kOrange = Color(0xFFE65100);
  static const _kBlue   = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: const Row(children: [
        Icon(Icons.sports_golf_rounded, color: Color(0xFFE65100), size: 22),
        SizedBox(width: 8),
        Text('選擇偵測模式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 模式卡片 ──
          _modeCard(
            mode: SkeletonAnalysisMode.v1,
            icon: Icons.accessibility_new_rounded,
            color: _kGreen,
            title: 'V1 骨架分析',
            subtitle: '全幀 ML Kit → 依手腕速度偵測',
            badge: '精準',
            badgeColor: _kGreen,
            timeHint: '需 1–3 分鐘',
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          _modeCard(
            mode: SkeletonAnalysisMode.v2,
            icon: Icons.graphic_eq_rounded,
            color: _kOrange,
            title: 'V2 音訊快速偵測',
            subtitle: '掃描擊球聲波峰值，無需骨架',
            badge: '快速',
            badgeColor: _kOrange,
            timeHint: '數秒內完成',
          ),
          const SizedBox(height: 8),
          _modeCard(
            mode: SkeletonAnalysisMode.v3,
            icon: Icons.track_changes_rounded,
            color: _kBlue,
            title: 'V3 音訊 + 局部骨架',
            subtitle: '音訊找候選(±3s)→骨架精確定位→切片(±2.5s)',
            badge: '均衡',
            badgeColor: _kBlue,
            timeHint: '每球約 5–15 秒',
          ),
          // ── 今日不再提醒 ──
          const Divider(height: 16, thickness: 0.8, color: Color(0xFFF0F2F5)),
          GestureDetector(
            onTap: () => setState(() => _skipToday = !_skipToday),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                SizedBox(
                  width: 20, height: 20,
                  child: Checkbox(
                    value: _skipToday,
                    onChanged: (v) => setState(() => _skipToday = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    activeColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFB0B8C1)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('今日不再提醒', style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
              ]),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _mode == SkeletonAnalysisMode.v2 ? _kOrange
                           : _mode == SkeletonAnalysisMode.v3 ? _kBlue
                           : _kGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(
            _DetectionModeResult(mode: _mode, skipToday: _skipToday),
          ),
          child: const Text('開始偵測'),
        ),
      ],
    );
  }

  Widget _modeCard({
    required SkeletonAnalysisMode mode,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required String timeHint,
  }) {
    final isOn = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isOn ? color.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isOn ? color : const Color(0xFFDDE1E7),
            width: isOn ? 1.5 : 1.0,
          ),
        ),
        child: Row(children: [
          Icon(icon, color: isOn ? color : const Color(0xFFB0B8C1), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: TextStyle(
                  fontSize: 13.5, fontWeight: isOn ? FontWeight.w700 : FontWeight.w500,
                  color: isOn ? color : const Color(0xFF1A1A2E),
                )),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge, style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
            ]),
          ),
          Text(timeHint, style: TextStyle(
            fontSize: 10.5, color: isOn ? color : const Color(0xFFB0B8C1), fontWeight: FontWeight.w500,
          )),
        ]),
      ),
    );
  }
}

/// 在執行完整分析前讓使用者選擇輸出品質模式並確認。
/// 回傳 [_QualityDialogResult]，使用者取消回傳 null。
class _ExportQualityDialog extends StatefulWidget {
  final ExportQuality initialQuality;
  const _ExportQualityDialog({required this.initialQuality});

  @override
  State<_ExportQualityDialog> createState() => _ExportQualityDialogState();
}

class _ExportQualityDialogState extends State<_ExportQualityDialog> {
  late ExportQuality _selected;
  bool _skipToday = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialQuality;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: const Row(
        children: [
          Icon(Icons.high_quality_rounded, color: Color(0xFF1E8E5A), size: 22),
          SizedBox(width: 8),
          Text('選擇輸出品質', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 品質選項 ──
          ...ExportQuality.values.map((q) {
            final isSelected = _selected == q;
            return GestureDetector(
              onTap: () => setState(() => _selected = q),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1E8E5A).withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1E8E5A)
                        : const Color(0xFFDDE1E7),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? const Color(0xFF1E8E5A)
                          : const Color(0xFFB0B8C1),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFF1E8E5A)
                                  : const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            q.sizeHint,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      q.bitrateHint,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? const Color(0xFF1E8E5A)
                            : const Color(0xFFB0B8C1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // ── 今日不再提醒 ──
          const Divider(height: 16, thickness: 0.8, color: Color(0xFFF0F2F5)),
          GestureDetector(
            onTap: () => setState(() => _skipToday = !_skipToday),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _skipToday,
                      onChanged: (v) =>
                          setState(() => _skipToday = v ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      activeColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFB0B8C1)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '今日不再提醒',
                    style:
                        TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child:
              const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1E8E5A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(
            _QualityDialogResult(quality: _selected, skipToday: _skipToday),
          ),
          child: const Text('開始分析'),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 取消令牌
// ────────────────────────────────────────────────────────────────────────────

class _CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 通知 Kotlin 端停止正在執行的分析工作（姿勢分析 / 骨架渲染）。
/// 這是 fire-and-forget：不需等待回應，Kotlin 會在下一個幀邊界停止。
Future<void> _cancelNativeAnalysis() async {
  try {
    const _ch = MethodChannel('com.example.golf_score_app/pose_analyzer');
    await _ch.invokeMethod<void>('cancel');
  } catch (e) {
    debugPrint('[Cancel] native cancel failed: $e');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 分析進度彈窗（含橫幅廣告）
// ────────────────────────────────────────────────────────────────────────────

/// 鎖定式進度對話框，底部嵌入橫幅廣告。
/// 廣告在背景非同步載入，載入成功後自動顯示；失敗時不佔位，UI 不受影響。
class _ProgressWithAdDialog extends StatefulWidget {
  final String title;
  final ValueListenable<(double, String)> progressNotifier;
  final Color progressColor;
  final VoidCallback? onCancel;

  const _ProgressWithAdDialog({
    required this.title,
    required this.progressNotifier,
    required this.progressColor,
    this.onCancel,
  });

  @override
  State<_ProgressWithAdDialog> createState() => _ProgressWithAdDialogState();
}

class _ProgressWithAdDialogState extends State<_ProgressWithAdDialog> {
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: AdSize.banner, // 320×50 dp
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[ProgressDialog] 橫幅廣告載入失敗: $error');
          ad.dispose();
        },
      ),
    )..load();
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 橫幅廣告（title 下方，載入後才顯示，不佔位） ────────
            if (_bannerLoaded && _bannerAd != null) ...[
              SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
              const SizedBox(height: 16),
            ],
            // ── 進度區 ─────────────────────────────────────────────
            ValueListenableBuilder<(double, String)>(
              valueListenable: widget.progressNotifier,
              builder: (_, val, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: val.$1,
                    backgroundColor: Colors.grey[700],
                    color: widget.progressColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    val.$2,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        actions: widget.onCancel != null
            ? [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消', style: TextStyle(color: Colors.white54)),
                ),
              ]
            : null,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 下載版本選擇（共用：HistoryTile + ClipSubCard）
// ════════════════════════════════════════════════════════════════════════════

class _DlOption {
  final String file;
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  const _DlOption({
    required this.file, required this.label,
    required this.desc, required this.icon, required this.color,
  });
}

/// 所有可能的下載選項（依優先顯示順序）
const _kDlOptions = [
  _DlOption(
    file: 'final.mp4', label: '完整分析',
    desc: '骨架 + 球軌跡 overlay',
    icon: Icons.sports_golf_rounded, color: Color(0xFF1E8E5A),
  ),
  _DlOption(
    file: 'skeleton.mp4', label: '骨架版',
    desc: '只含骨架 overlay',
    icon: Icons.accessibility_new_rounded, color: Color(0xFF7C3AED),
  ),
  _DlOption(
    file: 'clip.mp4', label: '原始切片',
    desc: '無 overlay 的原始切片',
    icon: Icons.content_cut_rounded, color: Color(0xFF1565C0),
  ),
  _DlOption(
    file: 'swing.mp4', label: '原始影片',
    desc: '無任何 overlay',
    icon: Icons.videocam_rounded, color: Color(0xFF546E7A),
  ),
  _DlOption(
    file: 'swing.mov', label: '原始影片 (MOV)',
    desc: '原始 MOV 檔',
    icon: Icons.videocam_rounded, color: Color(0xFF546E7A),
  ),
];

/// 顯示下載版本選擇底部選單，回傳使用者選擇的選項或 null（取消）
/// 顯示儲存位置選擇：下載資料夾 or 自選資料夾。
/// 回傳 true = 自選資料夾，false = 下載資料夾，null = 取消。
Future<bool?> _showSaveLocationPicker(BuildContext ctx) {
  return showModalBottomSheet<bool>(
    context: ctx,
    backgroundColor: const Color(0xFF1E1E2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('選擇儲存位置', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.white70),
            title: const Text('下載資料夾', style: TextStyle(color: Colors.white)),
            subtitle: const Text('儲存到系統預設下載位置', style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open, color: Colors.white70),
            title: const Text('選擇資料夾', style: TextStyle(color: Colors.white)),
            subtitle: const Text('自訂儲存位置', style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<_DlOption?> _showDownloadPicker(BuildContext ctx, String sessionDir) {
  final available = _kDlOptions.where((o) => File(p.join(sessionDir, o.file)).existsSync()).toList();
  if (available.isEmpty) return Future.value(null);

  // 只有一個選項時直接回傳，不彈選單
  if (available.length == 1) return Future.value(available.first);

  return showModalBottomSheet<_DlOption>(
    context: ctx,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _DownloadVersionPicker(options: available),
  );
}

class _DownloadVersionPicker extends StatelessWidget {
  final List<_DlOption> options;
  const _DownloadVersionPicker({required this.options});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.download_rounded, color: Color(0xFF1E8E5A), size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('選擇下載版本',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...options.map((opt) => _DlOptionTile(
            option: opt, onTap: () => Navigator.pop(context, opt),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DlOptionTile extends StatelessWidget {
  final _DlOption option;
  final VoidCallback onTap;
  const _DlOptionTile({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(option.icon, color: option.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.label,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(option.desc,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────

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

// ────────────────────────────────────────────────────────────────────────────
// 音頻特徵迷你量規（影片卡片用）
// ────────────────────────────────────────────────────────────────────────────

const _kCardFeatureDisplayRanges = <String, List<double>>{
  'rms_dbfs':          [-45.0, -5.0],
  'spectral_centroid': [1500.0, 7000.0],
  'sharpness_hfxloud': [0.0, 6.0],
  'highband_amp':      [0.0, 60.0],
  'peak_dbfs':         [-30.0, 0.0],
};

class _AudioFeatureMiniBar extends StatelessWidget {
  final String label;
  final String featureKey;
  final double? value;
  final bool passed;
  final bool enabled;

  const _AudioFeatureMiniBar({
    required this.label,
    required this.featureKey,
    required this.value,
    required this.passed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const dimColor = Color(0xFFCBD0D8);
    final barColor = !enabled
        ? dimColor
        : passed
            ? const Color(0xFF4CAF50)
            : const Color(0xFFF44336);
    final displayRange = _kCardFeatureDisplayRanges[featureKey] ?? [0.0, 100.0];
    final threshold = AudioAnalysisService.ruleIntervals[featureKey] ?? [0.0, 1.0];

    double norm(double v) =>
        ((v - displayRange[0]) / (displayRange[1] - displayRange[0])).clamp(0.0, 1.0);

    final tLowN  = norm(threshold[0]);
    final tHighN = norm(threshold[1]);
    final valN   = value != null ? norm(value!) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: enabled ? const Color(0xFF6F7B86) : dimColor,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return SizedBox(
            height: 8,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: enabled ? 0.08 : 0.04),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (enabled)
                  Positioned(
                    left: tLowN * width,
                    width: (tHighN - tLowN) * width,
                    top: 1.5,
                    bottom: 1.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                if (valN != null)
                  Positioned(
                    left: (valN * width - 3).clamp(0.0, width - 6),
                    top: 1,
                    bottom: 1,
                    width: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 2),
        Text(
          value != null
              ? AudioAnalysisService.formatFeatureValue(featureKey, value!)
              : '—',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: barColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
