import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_quality.dart';
import '../models/export_spec.dart';
import '../providers/plan_provider.dart';
import '../services/overlay_burn_service.dart';
import '../widgets/custom_export_sheet.dart';
import '../theme/app_theme.dart';
import '../models/recording_history_entry.dart';
import '../models/hits_summary.dart';
import '../models/swing_hit.dart';
import '../models/swing_posture.dart';
import '../services/recording_history_storage.dart';
import '../services/skeleton_csv_locator.dart';
import '../services/hits_summary_storage.dart';
import '../services/statistics_service.dart';
import '../services/swing_auto_clip_service.dart';
import '../services/swing_detect_prefs.dart';
import '../services/swing_impact_detector.dart';
import '../services/clip_pipeline_service.dart';
import '../services/golf_analysis_service.dart';
import '../services/analysis_progress_service.dart';
import '../services/video_analysis_pipeline_service.dart';
import '../services/audio_export_models.dart';
import '../services/clip_audio_score_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/ad_service.dart';
import '../services/reward_service.dart';
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
import '../widgets/clip_candidates_sheet.dart';
import '../services/video_export_service.dart';

/// 列表操作選項
enum _HistoryMenuAction { rename, note, detectHits, addClip, analyze, compare, share, customExport, uploadReward, delete }

enum _ClipMenuAction { rename, note, share, customExport, uploadReward, delete }

/// 排序選項
enum _SortBy {
  /// 按時間排序（最新優先）
  date,
  /// 按最佳速度（峰值）排序（最高優先）
  peakValue,
  /// 按片段時間排序（切片在原始影片中的開始秒數，由小到大）
  clipTime;

  /// 標籤（僅供 dead-code 保留；UI 使用 historySortDate/PeakSpeed/ClipTime）
  String get label {
    switch (this) {
      case _SortBy.date:
        return 'date';
      case _SortBy.peakValue:
        return 'peakValue';
      case _SortBy.clipTime:
        return 'clipTime';
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
/// 已抽出為 ClipAudioScoreService 共用（SHOT 模式 / 自動切片同套邏輯），此處保留轉呼叫。
Future<AudioAnalysisResult?> _analyzeWavFile({
  required String sessionDir,
  required String clipPath,
  required void Function(double progress, String message) onProgress,
  double? targetHitTime,
}) =>
    ClipAudioScoreService.analyzeWav(
      sessionDir: sessionDir,
      clipPath: clipPath,
      targetHitTime: targetHitTime,
      onProgress: onProgress,
    );

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

  /// 此原始影片底下的切片（切片存在獨立的 {session}_hit_n/ 兄弟目錄，
  /// 不在原始 session 目錄內，刪除時必須逐筆處理）
  List<RecordingHistoryEntry> _childClipsOf(RecordingHistoryEntry entry) =>
      _entries.where((e) =>
          e.videoType == VideoType.localClip &&
          e.sourceVideoPath == entry.filePath).toList();

  /// 移除指定紀錄並同步刪除實體檔案。
  /// - 原始影片：連同所有切片（檔案 + DB 記錄）一併移除
  /// - 切片：只刪該切片；若是最後一個切片，解除來源影片的 isClipped，
  ///   讓使用者可以重新偵測擊球
  Future<void> _deleteEntry(RecordingHistoryEntry entry) async {
    final isClip = entry.videoType == VideoType.localClip;
    final childClips = isClip ? const <RecordingHistoryEntry>[] : _childClipsOf(entry);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).historyDeleteTitle),
          content: Text(
        isClip
            ? AppLocalizations.of(context).historyDeleteClipConfirm(entry.displayTitle)
            : childClips.isEmpty
                ? AppLocalizations.of(context).historyDeleteVideoConfirm(entry.displayTitle)
                : AppLocalizations.of(context).historyDeleteVideoWithClipsConfirm(entry.displayTitle, childClips.length),
      ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.of(context).commonDelete),
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

    // 原始影片：先清掉所有子切片（檔案 + DB），再刪自己
    for (final clip in childClips) {
      await _removeEntryFiles(clip);
      await RecordingHistoryStorage.instance.deleteEntry(clip.filePath);
    }
    if (childClips.isNotEmpty) {
      final clipPaths = childClips.map((c) => c.filePath).toSet();
      _entries.removeWhere((e) => clipPaths.contains(e.filePath));
    }

    // 移除檔案
    await _removeEntryFiles(entry);

    _entries.removeWhere((item) => item.filePath == entry.filePath);

    // 切片刪光時解除來源影片的「已切片」標記，允許重新偵測
    if (isClip && entry.sourceVideoPath != null) {
      final srcIdx =
          _entries.indexWhere((e) => e.filePath == entry.sourceVideoPath);
      final siblingsLeft = _entries.any((e) =>
          e.videoType == VideoType.localClip &&
          e.sourceVideoPath == entry.sourceVideoPath);
      if (srcIdx != -1 && !siblingsLeft && _entries[srcIdx].isClipped) {
        _entries[srcIdx] = _entries[srcIdx].copyWith(isClipped: false);
        await RecordingHistoryStorage.instance.upsertEntry(_entries[srcIdx]);
      }
    }

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
      SnackBar(content: Text(
        childClips.isEmpty
            ? AppLocalizations.of(context).historyDeletedSnack(entry.fileName)
            : AppLocalizations.of(context).historyDeletedWithClipsSnack(entry.fileName, childClips.length),
      )),
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
          title: Text(AppLocalizations.of(context).historyRenameTitle),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: TextFormField(
              initialValue: initialText,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).historyRenameLabel,
                helperText: AppLocalizations.of(context).historyRenameHelper,
              ),
              onChanged: (value) => tempName = value,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.length > 40) {
                  return AppLocalizations.of(context).historyRenameValidation;
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final isValid = formKey.currentState?.validate() ?? false;
                if (!isValid) {
                  return;
                }
                Navigator.of(dialogContext).pop(tempName.trim());
              },
              child: Text(AppLocalizations.of(context).commonSave),
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
        ? AppLocalizations.of(context).historyRenameResetSnack(defaultTitle)
        : AppLocalizations.of(context).historyRenamedSnack(storedName);
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

  /// 重置所有篩選與排序回預設值
  void _resetFilters() {
    setState(() {
      _selectedGoodShot = null;
      _videoTypeIsLong  = null;
      _aiAnalyzedFilter = null;
      _aiCoachFilter    = null;
      _clippedFilter    = null;
      _postureFilter    = null;
      _datePreset       = null;
      _customDateFrom   = null;
      _customDateTo     = null;
      _sortBy           = _SortBy.date;
    });
    _saveFilters();
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
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
    final l10n = AppLocalizations.of(context);
    final items = <(String, Color)>[];
    if (_selectedGoodShot == true)  items.add((l10n.historyFilterGood,         const Color(0xFF4CAF50)));
    if (_selectedGoodShot == false) items.add((l10n.historyFilterBad,          const Color(0xFFF44336)));
    if (_videoTypeIsLong  == true)  items.add((l10n.historyFilterLongVideo,    const Color(0xFF1565C0)));
    if (_videoTypeIsLong  == false) items.add((l10n.historyFilterShortVideo,   const Color(0xFF757575)));
    if (_aiAnalyzedFilter == true)  items.add((l10n.historyFilterAnalyzed,     kGoodColor));
    if (_aiAnalyzedFilter == false) items.add((l10n.historyFilterNotAnalyzed,  const Color(0xFF9AA6B2)));
    if (_aiCoachFilter    == true)  items.add((l10n.historyFilterAiAnalyzed,   const Color(0xFF7C3AED)));
    if (_aiCoachFilter    == false) items.add((l10n.historyFilterAiNotAnalyzed,const Color(0xFF9AA6B2)));
    if (_clippedFilter    == true)  items.add((l10n.historyFilterClipped,      const Color(0xFFFF9800)));
    if (_clippedFilter    == false) items.add((l10n.historyFilterNotClipped,   const Color(0xFF9AA6B2)));
    if (_postureFilter != null) {
      final color = SwingPosture.isPerfect(_postureFilter)
          ? const Color(0xFF4CAF50)
          : const Color(0xFFE57373);
      items.add((SwingPosture.zhName(_postureFilter!), color));
    }
    if (_datePreset == 'today')  items.add((l10n.historyFilterToday, const Color(0xFF2196F3)));
    if (_datePreset == 'week')   items.add((l10n.historyFilterWeek,  const Color(0xFF2196F3)));
    if (_datePreset == 'month')  items.add((l10n.historyFilterMonth, const Color(0xFF2196F3)));
    if (_datePreset == 'custom' && _customDateFrom != null) {
      final df = _customDateFrom!;
      final dt = _customDateTo ?? _customDateFrom!;
      String fmt(DateTime d) => '${d.month}/${d.day}';
      items.add(('${fmt(df)}–${fmt(dt)}', const Color(0xFF2196F3)));
    }
    if (_sortBy != _SortBy.date) {
      final sortLabel = _sortBy == _SortBy.peakValue
          ? l10n.historySortPeakSpeed
          : l10n.historySortClipTime;
      items.add((sortLabel, const Color(0xFF1565C0)));
    }

    if (items.isEmpty) {
      return Text(l10n.historyFilterAll,
          style: TextStyle(fontSize: 11, color: context.textHint));
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
        SnackBar(content: Text(AppLocalizations.of(context).historyFileNotFound(entry.fileName))),
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
          onEntryUpdated: _onEntryUpdated,
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
        if ((e.note ?? '').toLowerCase().contains(q)) return true;
        if (_formatTimestamp(e.recordedAt).contains(q)) return true;
        return false;
      }).toList();
    }

    // 統計文字
    final goodCount = _entries.where((e) => e.goodShot == true).length;
    final badCount  = _entries.where((e) => e.goodShot == false).length;
    final totalShown = filteredEntries.length;
    final l10n = AppLocalizations.of(context);
    final subtitle  = _isLoading
        ? l10n.commonLoading
        : _searchQuery.isNotEmpty
            ? l10n.historySearchResult(totalShown, _entries.length)
            : l10n.historySubtitle(_entries.length, goodCount, badCount);

    return Scaffold(
        backgroundColor: context.bgPage,
        body: Column(
          children: [
            // ── 綠色頂部面板 ─────────────────────────────────────
            GreenPageHeader(
              title: l10n.historyTitle,
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
              color: context.bgCard,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 14, color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: l10n.historySearchHint,
                    hintMaxLines: 1,
                    hintStyle: TextStyle(fontSize: 13.5, color: context.textHint),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textHint),
                    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                            child: Icon(Icons.close_rounded, size: 16, color: context.textHint),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    filled: true,
                    fillColor: context.bgInset,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBrandPrimary, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
            // ── 篩選 & 排序面板（可折疊）────────────────────────
            Container(
              color: context.bgCard,
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
                              size: 15, color: kBrandPrimary),
                          const SizedBox(width: 6),
                          Text(l10n.historyFilterSort,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.textPrimary)),
                          if (_activeFilterCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: kBrandPrimary,
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
                            child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: context.textHint),
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
                                _filterRow(l10n.historyFilterLabelGoodBad, [
                                  _chip(l10n.historyFilterAll,   _selectedGoodShot == null,  kBrandPrimary, () { setState(() => _selectedGoodShot = null);  _saveFilters(); }),
                                  _chip(l10n.historyFilterGood,  _selectedGoodShot == true,  const Color(0xFF4CAF50), () { setState(() => _selectedGoodShot = true);  _saveFilters(); }),
                                  _chip(l10n.historyFilterBad,   _selectedGoodShot == false, const Color(0xFFF44336), () { setState(() => _selectedGoodShot = false); _saveFilters(); }),
                                ]),
                                _filterRow(l10n.historyFilterLabelVideo, [
                                  _chip(l10n.historyFilterAll,        _videoTypeIsLong == null,  kBrandPrimary, () { setState(() => _videoTypeIsLong = null);  _saveFilters(); }),
                                  _chip(l10n.historyFilterLongVideo,  _videoTypeIsLong == true,  const Color(0xFF1565C0), () { setState(() => _videoTypeIsLong = true);  _saveFilters(); }),
                                  _chip(l10n.historyFilterShortVideo, _videoTypeIsLong == false, const Color(0xFF757575), () { setState(() => _videoTypeIsLong = false); _saveFilters(); }),
                                ]),
                                _filterRow(l10n.historyFilterLabelAnalysis, [
                                  _chip(l10n.historyFilterAll,          _aiAnalyzedFilter == null,  kBrandPrimary, () { setState(() => _aiAnalyzedFilter = null);  _saveFilters(); }),
                                  _chip(l10n.historyFilterAnalyzed,     _aiAnalyzedFilter == true,  const Color(0xFF4CAF50), () { setState(() => _aiAnalyzedFilter = true);  _saveFilters(); }),
                                  _chip(l10n.historyFilterNotAnalyzed,  _aiAnalyzedFilter == false, const Color(0xFF9AA6B2), () { setState(() => _aiAnalyzedFilter = false); _saveFilters(); }),
                                ]),
                                _filterRow(l10n.historyFilterLabelAI, [
                                  _chip(l10n.historyFilterAll,             _aiCoachFilter == null,  kBrandPrimary, () { setState(() => _aiCoachFilter = null);  _saveFilters(); }),
                                  _chip(l10n.historyFilterAiAnalyzed,      _aiCoachFilter == true,  const Color(0xFF7C3AED), () { setState(() => _aiCoachFilter = true);  _saveFilters(); }),
                                  _chip(l10n.historyFilterAiNotAnalyzed,   _aiCoachFilter == false, const Color(0xFF9AA6B2), () { setState(() => _aiCoachFilter = false); _saveFilters(); }),
                                ]),
                                _filterRow(l10n.historyFilterLabelClip, [
                                  _chip(l10n.historyFilterAll,        _clippedFilter == null,  kBrandPrimary, () { setState(() => _clippedFilter = null);  _saveFilters(); }),
                                  _chip(l10n.historyFilterClipped,    _clippedFilter == true,  const Color(0xFFFF9800), () { setState(() => _clippedFilter = true);  _saveFilters(); }),
                                  _chip(l10n.historyFilterNotClipped, _clippedFilter == false, const Color(0xFF9AA6B2), () { setState(() => _clippedFilter = false); _saveFilters(); }),
                                ]),
                                _filterRow(l10n.historyFilterLabelPosture, [
                                  _chip(l10n.historyFilterAll, _postureFilter == null, kBrandPrimary, () { setState(() => _postureFilter = null); _saveFilters(); }),
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
                                _filterRow(l10n.historyFilterLabelDate, [
                                  _chip(l10n.historyFilterAll,   _datePreset == null,    kBrandPrimary, () { setState(() { _datePreset = null; _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _chip(l10n.historyFilterToday, _datePreset == 'today', const Color(0xFF2196F3), () { setState(() { _datePreset = 'today'; _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _chip(l10n.historyFilterWeek,  _datePreset == 'week',  const Color(0xFF2196F3), () { setState(() { _datePreset = 'week';  _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
                                  _chip(l10n.historyFilterMonth, _datePreset == 'month', const Color(0xFF2196F3), () { setState(() { _datePreset = 'month'; _customDateFrom = null; _customDateTo = null; }); _saveFilters(); }),
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
                                _filterRow(l10n.historyFilterLabelSort, [
                                  _chip(l10n.historySortDate,      _sortBy == _SortBy.date,      kBrandPrimary, () { setState(() => _sortBy = _SortBy.date);      _saveFilters(); }),
                                  _chip(l10n.historySortPeakSpeed, _sortBy == _SortBy.peakValue, const Color(0xFF1565C0), () { setState(() => _sortBy = _SortBy.peakValue); _saveFilters(); }),
                                  _chip(l10n.historySortClipTime,  _sortBy == _SortBy.clipTime,  const Color(0xFFFF9800), () { setState(() => _sortBy = _SortBy.clipTime);  _saveFilters(); }),
                                ]),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _activeFilterCount > 0 ? _resetFilters : null,
                                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                                    label: Text(AppLocalizations.of(context).historyFilterReset,
                                        style: const TextStyle(fontSize: 13)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: kBrandPrimary,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Divider(height: 1, thickness: 1, color: context.borderColor),
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
        children: [
          Icon(Icons.video_collection_outlined, size: 72, color: context.textHint),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).historyEmptyTitle,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).historyEmptySubtitle,
            style: TextStyle(fontSize: 13, color: context.textSecondary),
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
          Icon(Icons.search_off_rounded, size: 64, color: context.textHint),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).historySearchNoResult,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).historySearchNoResultHint(query),
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text(AppLocalizations.of(context).historySearchClear),
            style: TextButton.styleFrom(foregroundColor: kBrandPrimary),
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

  /// 既有切片中最大的 hit 序號（解析 `_hit_N` 目錄名），供「加入切片」接續編號。
  int _maxExistingHitIndex() {
    final re = RegExp(r'_hit_(\d+)');
    var maxN = 0;
    for (final e in widget.allEntries) {
      if (e.sourceVideoPath != widget.entry.filePath) continue;
      final m = re.firstMatch(e.filePath);
      final n = m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
      if (n > maxN) maxN = n;
    }
    return maxN;
  }

  /// 加入切片（已切片長片用）：只開手動自由切片，框選一段 → 裁成新切片**附加**，
  /// 不重跑偵測、不動既有切片。新切片序號接在既有最大值之後。
  Future<void> _addManualClip() async {
    if (_isDetecting) return;
    final l10n = AppLocalizations.of(context);

    // 既有切片的擊球時刻（原片座標 = clip 起點 + clip 內 hitSecond），當灰色參考標記
    final existingMarks = <double>[
      for (final e in widget.allEntries)
        if (e.sourceVideoPath == widget.entry.filePath)
          (e.startSecond ?? 0) + (e.hitSecond ?? 0),
    ];

    final selection = await showClipCandidatesSheet(
      context,
      videoPath: widget.entry.filePath,
      durationSeconds: widget.entry.durationSeconds.toDouble(),
      candidates: const [], // 純手動：無自動候選
      existingClipMarks: existingMarks,
    );
    if (selection == null || selection.manualRanges.isEmpty || !mounted) return;

    setState(() => _isDetecting = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier =
        ValueNotifier<(double, String)>((0.0, l10n.historyProgressDetectingHit));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: l10n.historyMenuAddClip,
        progressNotifier: progressNotifier,
        progressColor: const Color(0xFFE65100),
        onCancel: () {
          navigator.pop();
          if (mounted) setState(() => _isDetecting = false);
        },
      ),
    );

    // 接續既有 hit 序號，避免覆蓋現有切片目錄
    var idx = _maxExistingHitIndex() + 1;
    final ranges = selection.manualRanges;
    final hits = <SwingHit>[];
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      final mid = (r.startSec + r.endSec) / 2;
      // 進度 0~0.4：逐段在框選區間內跑骨架找弧底（精修擊球點，失敗退回中點）
      progressNotifier.value =
          (i / (ranges.length + 1) * 0.4, l10n.historyProgressDetectingHit);
      var hitSec = mid;
      try {
        final win = (((r.endSec - r.startSec) / 2) * 1000).round().clamp(500, 3000);
        final res = await GolfAnalysisService.analyzeVideoAtCandidate(
          videoPath:   widget.entry.filePath,
          candidateMs: (mid * 1000).round(),
          windowMs:    win,
        );
        if (res != null) {
          hitSec = (res.impactTimeMs / 1000.0).clamp(r.startSec, r.endSec);
        }
      } catch (_) {
        // 骨架分析失敗 → 沿用中點
      }
      hits.add(SwingHit(
        hitIndex:   idx++,
        hitFrame:   (hitSec * 30).round(),
        hitSec:     hitSec,
        startSec:   r.startSec,
        endSec:     r.endSec,
        speedValue: 0.0,
        audioValue: 0.0,
      ));
    }

    // 進切片階段前先切換 label，避免裁切太快沒回報而停在「偵測擊球」
    progressNotifier.value = (0.4, l10n.historyProgressClippingPct(0, 0, hits.length));

    await _clipAndSaveHits(
      hits: hits,
      navigator: navigator,
      messenger: messenger,
      progressNotifier: progressNotifier,
      baseProgress: 0.4,
    );
  }

  /// 執行擊球偵測 → 裁切片段（顯示進度對話框）
  /// 前置條件：必須先進行骨架分析與音訊提取
  Future<void> _runDetection() async {
    // 檢查是否已經切片過
    if (widget.entry.isClipped) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).historyAlreadyClipped),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isDetecting) return;

    // ── 偵測模式選擇對話框（含 V1/V2 切換）────────────────────────────
    SkeletonAnalysisMode detectionMode = SkeletonAnalysisMode.v1;
    bool bothHands = await SwingDetectPrefs.getBothHands();
    // 此影片錄製時是否帶錨點 → 決定是否顯示離線 V4
    final sessionAnchor =
        await SwingAutoClipService.loadAnchor(p.dirname(widget.entry.filePath));
    if (mounted) {
      final result = await showDialog<_DetectionModeResult>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _DetectionModeDialog(
          initialBothHands: bothHands,
          hasAnchor: sessionAnchor != null,
        ),
      );
      if (result == null) return; // 使用者取消
      detectionMode = result.mode;
      bothHands = result.bothHands;
      await SwingDetectPrefs.setBothHands(bothHands); // 記住選擇，下次預設
      if (result.skipToday) await _SkipHelper.markSkipToday('detection');
    }

    setState(() => _isDetecting = true);

    if (!mounted) return;

    // 在第一個 await 之前捕捉 navigator/messenger，確保 Dialog 一定能關閉
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, l10n.historyProgressPreparingSkeleton));
    final cancelToken = _CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: AppLocalizations.of(context).historyDetectingShots,
        progressNotifier: progressNotifier,
        progressColor: Colors.blue,
        onCancel: () {
          cancelToken.cancel();
          unawaited(_cancelNativeAnalysis());   // 通知 Kotlin 停止分析迴圈
          navigator.pop();
          if (mounted) setState(() => _isDetecting = false);
          messenger.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).historyCancelledDetection)));
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
        progressSvc.reset(l10n.historyProgressV2AudioScan);
        void listenV2() {
          final (pct, label) = progressSvc.progress.value;
          // V2 audio peaks 佔整體進度的 0~0.6，裁切佔 0.6~1.0
          progressNotifier.value = (pct * 0.6, label);
        }
        progressSvc.progress.addListener(listenV2);

        // 優先讀錄影結束時預計算的快取（audio_peaks.json），免重掃音軌
        final peakMs = await SwingAutoClipService.getOrComputeAudioPeaks(
          videoPath: widget.entry.filePath,
          searchStartMs: 500,
          minGapMs: 2000,
        );
        progressSvc.progress.removeListener(listenV2);
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
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.historyV2NoAudio),
            backgroundColor: Colors.orange,
          ));
          return;
        }

        // ── 切片前確認：逐段預覽、勾選保留、自由切片 ────────────────
        final totalDur = widget.entry.durationSeconds.toDouble();
        progressNotifier.value = (0.4, l10n.historyProgressWaitingConfirm);
        if (!mounted) return;
        final selection = await showClipCandidatesSheet(
          context,
          videoPath: widget.entry.filePath,
          durationSeconds: totalDur,
          candidates: candidates,
        );
        if (selection == null || selection.isEmpty) {
          navigator.pop();
          if (mounted) setState(() => _isDetecting = false);
          return;
        }

        progressNotifier.value = (0.4, l10n.historyProgressClipping);
        // 把保留的候選轉為 SwingHit（±2.5 秒精確窗口）
        // 每個候選各自對應一個 clip；若兩候選相距 < 5 秒，clip 可重疊，這是預期行為。
        // trimWithSurface() 保證每個 clip 精確 5 秒，以候選為中心。
        // 自由切片區段則直接以使用者選的起迄裁切。
        final v2Hits = _hitsFromSelection(selection, totalDur);

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
        progressSvc.reset(l10n.historyProgressV3AudioScan);
        void listenAudio() {
          if (progressSvc.currentOp == 'findAudioPeaks') {
            final (pct, label) = progressSvc.progress.value;
            progressNotifier.value = (pct * 0.15, label);
          }
        }
        progressSvc.progress.addListener(listenAudio);

        // 優先讀錄影結束時預計算的快取（audio_peaks.json），免重掃音軌
        final rawPeakMs = await SwingAutoClipService.getOrComputeAudioPeaks(
          videoPath: widget.entry.filePath,
          searchStartMs: 500,
          minGapMs: 2000,
        );
        progressSvc.progress.removeListener(listenAudio);
        if (cancelToken.isCancelled) return;
        debugPrint('[偵測擊球 V3] 音訊峰值: $rawPeakMs');

        // 骨架偵測為主：live impacts 判定桿數、音訊峰值僅精修時間；
        // 無 live 資料（匯入影片）時退回音訊峰值
        final v3LiveImpacts =
            await SwingAutoClipService.loadLiveImpacts(sessionDir);
        final v3Candidates = SwingAutoClipService.mergeCandidates(
          audioPeaks: rawPeakMs.map((ms) => ms / 1000.0).toList(),
          liveImpacts: v3LiveImpacts,
        );

        if (v3Candidates.isEmpty) {
          navigator.pop();
          setState(() => _isDetecting = false);
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.historyV3NoShot),
            backgroundColor: Colors.orange,
          ));
          return;
        }

        // ── 切片前確認：逐段預覽、勾選保留、自由切片 ────────────────
        // 在骨架精修前先讓使用者篩掉誤判峰值，省下被剔除候選的分析時間。
        final totalDur = widget.entry.durationSeconds.toDouble();
        progressNotifier.value = (0.15, l10n.historyProgressWaitingConfirm);
        if (!mounted) return;
        final selection = await showClipCandidatesSheet(
          context,
          videoPath: widget.entry.filePath,
          durationSeconds: totalDur,
          candidates: v3Candidates,
        );
        if (selection == null || selection.isEmpty) {
          navigator.pop();
          if (mounted) setState(() => _isDetecting = false);
          return;
        }
        final peakMs =
            selection.candidates.map((c) => (c.sec * 1000).round()).toList();

        // Step 2：對每個音訊峰值做局部骨架分析（±3 秒窗口 → 精確 impactMs）
        final v3Hits   = <SwingHit>[];

        for (int i = 0; i < peakMs.length; i++) {
          if (cancelToken.isCancelled) return;

          final peak     = peakMs[i];
          final baseFrom = 0.15 + (i / peakMs.length) * 0.55;   // 0.15 ~ 0.70
          final baseTo   = 0.15 + ((i + 1) / peakMs.length) * 0.55;
          final label    = l10n.historyProgressV3SkeletonAnalysis(i+1, peakMs.length);
          progressNotifier.value = (baseFrom, label);

          // 監聽 Kotlin 進度，顯示「第幾個影片 / 總數：Kotlin 幀狀態」
          final peakLabel = l10n.historyProgressV3SkeletonItem(i+1, peakMs.length);
          progressSvc.reset(l10n.historyProgressV3SkeletonAnalysis(i+1, peakMs.length));
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

          // 擊球時間取捨：音訊候選 → 保留音訊峰值（=真實觸球，骨架只做驗證）；
          //              live 候選（無音訊時間）→ 用骨架 Y-LOW。
          final cand   = selection.candidates[i];
          final hitSec = cand.fromAudio
              ? cand.sec                       // 音訊峰值 = 桿頭觸球瞬間
              : result.impactTimeMs / 1000.0;  // live 候選 → 骨架弧底

          debugPrint('[偵測擊球 V3] hit ${i+1}: '
              '${cand.fromAudio ? "音訊峰值 ${peak}ms(保留)" : "live→骨架 ${result.impactTimeMs}ms"} '
              '→ hitSec=${hitSec.toStringAsFixed(3)}s');

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

        // 自由切片區段：不經骨架精修，直接以使用者選的起迄裁切
        // （hitIndex 接在既有最大值之後 — 精修失敗的峰值會留下編號空洞）
        var nextIndex = v3Hits.isEmpty
            ? 1
            : v3Hits.map((h) => h.hitIndex).reduce(math.max) + 1;
        for (final r in selection.manualRanges) {
          final mid = (r.startSec + r.endSec) / 2;
          v3Hits.add(SwingHit(
            hitIndex:   nextIndex++,
            hitFrame:   (mid * 30).round(),
            hitSec:     mid,
            startSec:   r.startSec,
            endSec:     r.endSec,
            speedValue: 0.0,
            audioValue: 0.0,
          ));
        }

        if (v3Hits.isEmpty) {
          navigator.pop();
          setState(() => _isDetecting = false);
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.historyV3NoValidHit),
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
      progressNotifier.value = (0.5, l10n.historyProgressDetectingHit);
      final hits = await SwingImpactDetector.detect(
          csvPath: detectCsvPath, bothHands: bothHands,
          anchorX: detectionMode == SkeletonAnalysisMode.v4 ? sessionAnchor?.$1 : null,
          anchorY: detectionMode == SkeletonAnalysisMode.v4 ? sessionAnchor?.$2 : null);
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
          SnackBar(
            content: Text(
              l10n.historyNoShotDetected,
              style: const TextStyle(height: 1.5),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      // ── 切片前確認：逐段預覽、勾選保留、自由切片（與 V2/V3 一致）────
      final totalDur = widget.entry.durationSeconds.toDouble();
      progressNotifier.value = (0.5, l10n.historyProgressWaitingConfirm);
      if (!mounted) return;
      final selection = await showClipCandidatesSheet(
        context,
        videoPath: widget.entry.filePath,
        durationSeconds: totalDur,
        candidates: [for (final h in hits) (sec: h.hitSec, fromAudio: false)],
      );
      if (selection == null || selection.isEmpty) {
        navigator.pop();
        if (mounted) setState(() => _isDetecting = false);
        return;
      }

      // 以 hitSec 對回原 hit，保留偵測出的速度/階段/幀資訊
      final keptSecs = selection.candidates.map((c) => c.sec).toSet();
      final selectedHits = [
        for (final h in hits)
          if (keptSecs.contains(h.hitSec)) h,
      ];
      // 自由切片區段：直接以使用者選的起迄裁切（無骨架資訊）
      var nextIndex = selectedHits.isEmpty
          ? 1
          : selectedHits.map((h) => h.hitIndex).reduce(math.max) + 1;
      for (final r in selection.manualRanges) {
        final mid = (r.startSec + r.endSec) / 2;
        selectedHits.add(SwingHit(
          hitIndex:   nextIndex++,
          hitFrame:   (mid * 30).round(),
          hitSec:     mid,
          startSec:   r.startSec,
          endSec:     r.endSec,
          speedValue: 0.0,
          audioValue: 0.0,
        ));
      }

      // 4. 依序裁切
      final results = await ClipPipelineService.run(
        hits: selectedHits,
        srcVideoPath: widget.entry.filePath,
        sourceEntry: widget.entry,
        onProgress: (prog) {
          final percentage = prog.total > 0
            ? (prog.current / prog.total) * 100
            : 0;
          progressNotifier.value = (
            0.5 + (percentage / 100) * 0.5,
            l10n.historyProgressClippingPct(percentage.round(), prog.current, prog.total),
          );
        },
      );

      if (cancelToken.isCancelled) return;
      navigator.pop(); // 無論 mounted 與否，一定關閉 Dialog
      if (mounted) setState(() => _isDetecting = false);

      if (results.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.historyClipFailed)),
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
          content: Text(l10n.historyClipsGenerated(results.length)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[偵測擊球] 錯誤: $e');
      navigator.pop();
      if (mounted) setState(() => _isDetecting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.historyDetectFailed(e.toString())),
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
  /// 確認 sheet 的選擇結果 → SwingHit 列表。
  /// 自動候選用 ±2.5 秒標準窗口；自由切片區段直接用使用者選的起迄。
  List<SwingHit> _hitsFromSelection(ClipSelection selection, double totalDur) {
    final hits = <SwingHit>[];
    var idx = 1;
    for (final c in selection.candidates) {
      final (s, e) = SwingImpactDetector.calculateClipBoundaries(
        hitSec: c.sec, totalDurationSec: totalDur);
      hits.add(SwingHit(
        hitIndex:   idx++,
        hitFrame:   (c.sec * 30).round(),
        hitSec:     c.sec,
        startSec:   s,
        endSec:     e,
        speedValue: 0.0,
        audioValue: c.fromAudio ? 1.0 : 0.0,
      ));
    }
    for (final r in selection.manualRanges) {
      final mid = (r.startSec + r.endSec) / 2;
      hits.add(SwingHit(
        hitIndex:   idx++,
        hitFrame:   (mid * 30).round(),
        hitSec:     mid,
        startSec:   r.startSec,
        endSec:     r.endSec,
        speedValue: 0.0,
        audioValue: 0.0,
      ));
    }
    return hits;
  }

  Future<void> _clipAndSaveHits({
    required List<SwingHit> hits,
    required NavigatorState navigator,
    required ScaffoldMessengerState messenger,
    required ValueNotifier<(double, String)> progressNotifier,
    double baseProgress = 0.5,
    _CancelToken? cancelToken,
  }) async {
    final l10n = AppLocalizations.of(context);
    final remaining = 1.0 - baseProgress;
    final results = await ClipPipelineService.run(
      hits: hits,
      srcVideoPath: widget.entry.filePath,
      sourceEntry: widget.entry,
      onProgress: (prog) {
        final pct = prog.total > 0 ? prog.current / prog.total : 0.0;
        progressNotifier.value = (
          baseProgress + pct * remaining,
          l10n.historyProgressClippingPct((pct * 100).round(), prog.current, prog.total),
        );
      },
    );

    if (cancelToken?.isCancelled == true) return;

    navigator.pop();
    if (mounted) setState(() => _isDetecting = false);

    if (results.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.historyClipFailed)),
      );
      return;
    }

    widget.onClipsGenerated?.call(
      widget.entry,
      results.map((r) => r.entry).toList(),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.historyClipsGeneratedBg(results.length)),
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
          title: Text(AppLocalizations.of(context).historyLongVideoTitle),
          content: Text(
            AppLocalizations.of(context).historyLongVideoContent(widget.entry.durationSeconds),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(context).historyContinueAnalysis),
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
    final l10n = AppLocalizations.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, l10n.historyProgressPreparing));
    final cancelToken = _CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: l10n.historyFullAnalysisTitle,
        progressNotifier: progressNotifier,
        progressColor: Colors.cyan,
        onCancel: () {
          cancelToken.cancel();
          unawaited(_cancelNativeAnalysis());
          navigator.pop();
          if (mounted) setState(() => _isAnalyzing = false);
          messenger.showSnackBar(SnackBar(content: Text(l10n.historyCancelledAnalysis)));
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
        throw l10n.historyInvalidDuration(durationSeconds);
      }

      // Stage 1: 視頻分析（0-70%）
      debugPrint('[完整分析] 開始視頻分析...');
      progressNotifier.value = (0.0, l10n.historyProgressVideoAnalysis);

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
          progressNotifier.value = (0.68, l10n.historyProgressDetectingPhase);
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
      progressNotifier.value = (0.7, l10n.historyProgressAudioAnalysis);
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
        content: Text(l10n.historyAnalysisComplete(audioMsg)),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      debugPrint('[完整分析] 錯誤: $e');
      navigator.pop();
      if (mounted) setState(() => _isAnalyzing = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.historyAnalysisFailed(e.toString())),
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
            title: Text(AppLocalizations.of(context).historyQuotaExhaustedTitle),
            content: Text(
              AppLocalizations.of(context).historyQuotaExhaustedContent(planStatus.todayUsed, planStatus.totalLimit),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context).historyGotIt),
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
          builder: (_) => _ConfirmActionDialog(
            icon: Icons.psychology_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: AppLocalizations.of(context).historyAiAnalysisConfirmTitle,
            description: AppLocalizations.of(context).historyAiAnalysisConfirmDesc,
            confirmLabel: AppLocalizations.of(context).historyAiAnalysisConfirmBtn,
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
      if (!mounted) return;
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
            content: Text(AppLocalizations.of(context).historyAiSubmitFailed(AnalysisService.friendlyError(e))),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingAi = false);
    }
  }

  bool _isDownloading = false;

  /// 匯出（勾選疊加元素 + 浮水印分級 → 合成下載）
  Future<void> _customExport() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      await _runCustomExportFlow(context, widget.entry);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// 上傳分析資料領獎勵
  Future<void> _claimUploadReward() async {
    final updated = await _runUploadRewardFlow(context, widget.entry);
    if (updated != null && mounted) {
      widget.onEntryUpdated?.call(widget.entry, updated);
    }
  }

  /// 編輯影片備註
  Future<void> _editNote() async {
    final newNote = await _showNoteDialog(context, widget.entry.note);
    if (newNote == null || !mounted) return;
    if (newNote == (widget.entry.note ?? '')) return;
    widget.onEntryUpdated?.call(
      widget.entry,
      widget.entry.copyWith(note: newNote),
    );
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
        SnackBar(content: Text(AppLocalizations.of(context).historyNoOtherVideoToCompare)),
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
    final l10n = AppLocalizations.of(context);
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
      color: context.bgCard,
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
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        // 時間資訊
                        Row(children: [
                          Icon(Icons.access_time_rounded,
                              size: 12, color: context.textHint),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context).historyDurationLine(widget.formattedTime, widget.entry.durationSeconds),
                              style: TextStyle(
                                  fontSize: 11, color: context.textHint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        if (widget.formattedImportTime != null) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(Icons.download_rounded,
                                size: 12, color: context.textHint),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${widget.formattedImportTime!}${widget.entry.sharerName != null ? '  · ${AppLocalizations.of(context).historyImportedFrom(widget.entry.sharerName!)}' : ''}',
                                style: TextStyle(
                                    fontSize: 11, color: context.textHint),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                        ],
                        if (widget.entry.note?.trim().isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          _NoteLine(note: widget.entry.note!.trim()),
                        ],
                        const SizedBox(height: 7),
                        // 標籤列（基本 badges）
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _badge(
                              _isLongVideo ? l10n.historyFilterLongVideo : l10n.historyFilterShortVideo,
                              _isLongVideo
                                  ? const Color(0xFF1565C0)
                                  : const Color(0xFF757575),
                            ),
                            if (widget.entry.videoType == VideoType.original &&
                                widget.entry.isClipped)
                              _badge(l10n.historyFilterClipped, const Color(0xFFFF9800)),
                            if (widget.entry.audioTags
                                    ?.contains('no_audio') ==
                                true)
                              _badge(l10n.historyBadgeNoAudio, const Color(0xFF9E9E9E)),
                            if (widget.entry.isAnalyzed)
                              _badge(l10n.historyFilterAnalyzed, kGoodColor),
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
                            // 用 Wrap：窄卡放不下時甜蜜點群組換到次行，避免右側溢出
                            return Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                Row(mainAxisSize: MainAxisSize.min, children: [
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
                                ]),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(
                                    l10n.historySweetSpot,
                                    style: TextStyle(
                                        fontSize: 11, color: context.textHint),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: sweetColor.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: sweetColor.withValues(
                                              alpha: 0.45)),
                                    ),
                                    child: Text(
                                      goodShot == true
                                          ? l10n.historySweetSpotHit
                                          : goodShot == false
                                              ? l10n.historySweetSpotMiss
                                              : '—',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: sweetColor,
                                      ),
                                    ),
                                  ),
                                ]),
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
                    title: l10n.historyHitSummary,
                    initiallyExpanded: false,
                  ),
                );
              },
            ),
            // ── 底部操作列 ────────────────────────────────────────
            Divider(height: 1, thickness: 1, color: context.borderColor),
            IntrinsicHeight(
              child: Row(
                children: [
                  _actionBtn(
                    icon: Icons.bar_chart_rounded,
                    label: l10n.historyActionChart,
                    color: const Color(0xFF1565C0),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            RecordingDetailPage(entry: widget.entry))),
                  ),
                  VerticalDivider(
                      width: 1, thickness: 1, color: context.borderColor),
                  _actionBtn(
                    icon: Icons.play_arrow_rounded,
                    label: l10n.historyActionPlay,
                    color: kBrandPrimary,
                    onTap: widget.onTap,
                  ),
                  VerticalDivider(
                      width: 1, thickness: 1, color: context.borderColor),
                  if (_isLongVideo && _isOriginalVideo && widget.entry.isClipped && hasClips)
                    _actionBtn(
                      icon: _isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      label: _isExpanded ? l10n.historyActionCollapse : l10n.historyActionExpand,
                      color: const Color(0xFFE65100),
                      onTap: () => setState(() => _isExpanded = !_isExpanded),
                    )
                  else if (_isLongVideo && _isOriginalVideo && !widget.entry.isClipped)
                    _actionBtn(
                      icon: Icons.sports_golf_rounded,
                      label: l10n.historyActionDetect,
                      color: const Color(0xFFE65100),
                      loading: _isDetecting,
                      onTap: _runDetection,
                    )
                  else if (!_isAnalyzed)
                    _actionBtn(
                      icon: Icons.analytics_rounded,
                      label: l10n.historyActionFullAnalysis,
                      color: const Color(0xFF00838F),
                      loading: _isAnalyzing,
                      onTap: _runCombinedAnalysis,
                    )
                  else
                    _actionBtn(
                      icon: Icons.psychology_rounded,
                      label: l10n.historyActionAiAnalysis,
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
            tooltip: l10n.historyMoreActions,
            icon: Icon(
                Icons.more_vert_rounded,
                color: context.textHint,
                size: 20),
            padding: EdgeInsets.zero,
            onSelected: (action) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                switch (action) {
                  case _HistoryMenuAction.rename:
                    widget.onRename();
                    break;
                  case _HistoryMenuAction.note:
                    _editNote();
                    break;
                  case _HistoryMenuAction.detectHits:
                    _runDetection();
                    break;
                  case _HistoryMenuAction.addClip:
                    _addManualClip();
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
                  case _HistoryMenuAction.customExport:
                    _customExport();
                    break;
                  case _HistoryMenuAction.uploadReward:
                    _claimUploadReward();
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
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.rename,
                  child: Text(l10n.historyMenuRename),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.note,
                  child: Text(
                      (widget.entry.note?.trim().isNotEmpty ?? false)
                          ? l10n.historyMenuEditNote
                          : l10n.historyMenuAddNote),
                ),
                // 長片切片入口：未切片→整支偵測；已切片→只補加一段（不重切）
                if (_isLongVideo && _isOriginalVideo && !widget.entry.isClipped)
                  PopupMenuItem<_HistoryMenuAction>(
                    value: _HistoryMenuAction.detectHits,
                    enabled: !_isDetecting,
                    child: Row(children: [
                      Icon(Icons.sports_golf_rounded,
                          size: 16,
                          color: _isDetecting ? Colors.grey : const Color(0xFFE65100)),
                      const SizedBox(width: 8),
                      Text(l10n.historyActionDetect),
                    ]),
                  ),
                if (_isLongVideo && _isOriginalVideo && widget.entry.isClipped)
                  PopupMenuItem<_HistoryMenuAction>(
                    value: _HistoryMenuAction.addClip,
                    enabled: !_isDetecting,
                    child: Row(children: [
                      Icon(Icons.add_box_outlined,
                          size: 16,
                          color: _isDetecting ? Colors.grey : const Color(0xFFE65100)),
                      const SizedBox(width: 8),
                      Text(l10n.historyMenuAddClip),
                    ]),
                  ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.analyze,
                  enabled: canAnalyze && !_isAnalyzing,
                  child: Row(children: [
                    Text(
                        _isAnalyzing ? l10n.historyMenuAnalyzing : l10n.historyActionFullAnalysis,
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
                  child: Text(l10n.historyMenuCompare,
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
                            ? kBrandPrimary
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.historyMenuShare,
                        style: TextStyle(
                            color: canShare ? null : Colors.grey)),
                  ]),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.customExport,
                  enabled: !_isDownloading,
                  child: Row(children: [
                    Icon(_isDownloading ? Icons.hourglass_top_rounded : Icons.download_rounded,
                        size: 16,
                        color: _isDownloading ? Colors.grey : kBrandPrimary),
                    const SizedBox(width: 8),
                    Text(_isDownloading ? l10n.historyMenuDownloading : l10n.exportCustomTitle),
                  ]),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.uploadReward,
                  enabled: widget.entry.isAnalyzed &&
                      !widget.entry.isEffectivelyUploaded,
                  child: Row(children: [
                    Icon(Icons.cloud_upload_rounded,
                        size: 16,
                        color: (widget.entry.isAnalyzed &&
                                !widget.entry.isEffectivelyUploaded)
                            ? const Color(0xFF00897B)
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      widget.entry.isEffectivelyUploaded
                          ? l10n.historyMenuUploaded
                          : l10n.historyMenuUploadReward(RewardType.uploadData.ballsPerAction),
                      style: TextStyle(
                          color: (widget.entry.isAnalyzed &&
                                  !widget.entry.isEffectivelyUploaded)
                              ? null
                              : Colors.grey),
                    ),
                  ]),
                ),
                PopupMenuItem<_HistoryMenuAction>(
                  value: _HistoryMenuAction.delete,
                  child: Text(l10n.historyMenuDeleteVideo),
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
              width: 90,
              height: 160,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: 90,
            height: 160,
            decoration: BoxDecoration(
              color: context.bgInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.videocam_outlined,
                color: context.textSecondary, size: 32),
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
            child: Text(AppLocalizations.of(context).historyRoundLabel(roundIndex), style: overlayStyle),
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
    final l10n = AppLocalizations.of(context);
    final initial = clip.customName?.trim().isNotEmpty == true
        ? clip.customName!.trim()
        : l10n.historyClipDefaultName(widget.clipIndex);
    String tempName = initial;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.historyRenameClipTitle),
        content: TextField(
          controller: TextEditingController(text: initial),
          maxLength: 40,
          decoration: InputDecoration(labelText: l10n.historyRenameLabel, helperText: l10n.historyRenameHelper),
          onChanged: (v) => tempName = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(tempName),
            child: Text(l10n.commonOk),
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

  /// 上傳分析資料領獎勵
  Future<void> _claimUploadReward() async {
    final updated = await _runUploadRewardFlow(context, widget.clip);
    if (updated != null && mounted) {
      widget.onEntryUpdated?.call(widget.clip, updated);
    }
  }

  /// 編輯切片備註
  Future<void> _editNote() async {
    final clip = widget.clip;
    final newNote = await _showNoteDialog(context, clip.note);
    if (newNote == null || !mounted) return;
    if (newNote == (clip.note ?? '')) return;
    widget.onEntryUpdated?.call(clip, clip.copyWith(note: newNote));
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

  /// 匯出切片（勾選疊加元素 + 浮水印分級 → 合成下載）
  Future<void> _customExport() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      await _runCustomExportFlow(context, widget.clip);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
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
    final l10n = AppLocalizations.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0.0, l10n.historyProgressPreparing));
    final cancelToken = _CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressWithAdDialog(
        title: l10n.historyFullAnalysisTitle,
        progressNotifier: progressNotifier,
        progressColor: Colors.cyan,
        onCancel: () {
          cancelToken.cancel();
          unawaited(_cancelNativeAnalysis());   // 通知 Kotlin 停止分析迴圈
          navigator.pop();
          if (mounted) setState(() => _isAnalyzing = false);
          messenger.showSnackBar(SnackBar(content: Text(l10n.historyCancelledAnalysis)));
        },
      ),
    );

    try {
      final clip = widget.clip;
      final clipPath = clip.filePath;
      final sessionDir = p.dirname(clipPath);
      final durationSeconds = clip.durationSeconds;

      if (durationSeconds < 1 || durationSeconds > 600) {
        throw l10n.historyInvalidDuration(durationSeconds);
      }

      progressNotifier.value = (0.0, l10n.historyProgressPreparing);
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

      progressNotifier.value = (0.7, l10n.historyProgressAudioAnalysis);
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
          progressNotifier.value = (0.68, l10n.historyProgressDetectingPhase);
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
        content: Text(l10n.historyAnalysisComplete(audioMsg)),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      debugPrint('[切片完整分析] 錯誤: $e');
      navigator.pop();
      if (mounted) setState(() => _isAnalyzing = false);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.historyAnalysisFailed(e.toString())),
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
          SnackBar(content: Text(AppLocalizations.of(context).historyClipFileNotExist)),
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
          onEntryUpdated: widget.onEntryUpdated,
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
            title: Text(AppLocalizations.of(context).historyQuotaExhaustedTitle),
            content: Text(
              AppLocalizations.of(context).historyQuotaExhaustedContent(planStatus.todayUsed, planStatus.totalLimit),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context).historyGotIt),
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
          builder: (_) => _ConfirmActionDialog(
            icon: Icons.psychology_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: AppLocalizations.of(context).historyAiAnalysisConfirmTitle,
            description: AppLocalizations.of(context).historyAiAnalysisConfirmDesc,
            confirmLabel: AppLocalizations.of(context).historyAiAnalysisConfirmBtn,
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
      if (!mounted) return;
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
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).historyAiSubmitFailed(AnalysisService.friendlyError(e))),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            color: context.bgCard,
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
                                    : l10n.historyClipDefaultName(widget.clipIndex),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: context.textPrimary),
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
                                    l10n.historyClipHitAt(clip.hitSecond!.toStringAsFixed(1)),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: context.textHint),
                                  ),
                                ]),
                              ],
                              if (clip.startSecond != null &&
                                  clip.endSecond != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  l10n.historyClipRange(clip.startSecond!.toStringAsFixed(1), clip.endSecond!.toStringAsFixed(1)),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: context.textHint),
                                ),
                              ],
                              if (clip.note?.trim().isNotEmpty ?? false) ...[
                                const SizedBox(height: 2),
                                _NoteLine(note: clip.note!.trim()),
                              ],
                              const SizedBox(height: 5),
                              // 標籤（基本 badges）
                              Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                children: [
                                  if (clip.isAnalyzed)
                                    _smallBadge(l10n.historyFilterAnalyzed, kGoodColor),
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
                                    _smallBadge(l10n.historyBadgeNoAudio, const Color(0xFF9E9E9E)),
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
                                // Wrap：窄卡放不下時甜蜜點群組換行，避免右側溢出
                                return Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.speed_rounded,
                                          size: 12, color: speedColor),
                                      const SizedBox(width: 3),
                                      Text(
                                        hasSpeed
                                            ? clip.bestSpeedValue!
                                                .toStringAsFixed(1)
                                            : '—',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: speedColor,
                                        ),
                                      ),
                                    ]),
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text(
                                        l10n.historySweetSpot,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: context.textHint),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color:
                                              sweetColor.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                              color: sweetColor.withValues(
                                                  alpha: 0.45)),
                                        ),
                                        child: Text(
                                          goodShot == true
                                              ? l10n.historySweetSpotHit
                                              : goodShot == false
                                                  ? l10n.historySweetSpotMiss
                                                  : '—',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: sweetColor,
                                          ),
                                        ),
                                      ),
                                    ]),
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
                  Divider(height: 1, thickness: 1, color: context.borderColor),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        _clipBtn(
                          icon: Icons.bar_chart_rounded,
                          label: l10n.historyActionChart,
                          color: const Color(0xFF1565C0),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    RecordingDetailPage(entry: clip)),
                          ),
                        ),
                        VerticalDivider(
                            width: 1, thickness: 1, color: context.borderColor),
                        _clipBtn(
                          icon: Icons.play_arrow_rounded,
                          label: l10n.historyActionPlay,
                          color: kBrandPrimary,
                          onTap: _play,
                        ),
                        VerticalDivider(
                            width: 1, thickness: 1, color: context.borderColor),
                        if (!clip.isAnalyzed)
                          _clipBtn(
                            icon: Icons.analytics_rounded,
                            label: l10n.historyActionFullAnalysis,
                            color: const Color(0xFF00838F),
                            loading: _isAnalyzing,
                            onTap: _runCombinedAnalysis,
                          )
                        else
                          _clipBtn(
                            icon: Icons.psychology_rounded,
                            label: l10n.historyActionAiAnalysis,
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
              tooltip: l10n.historyMoreActions,
              icon: Icon(Icons.more_vert_rounded,
                  size: 18, color: context.textHint),
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
                    case _ClipMenuAction.customExport:
                      _customExport();
                      break;
                    case _ClipMenuAction.note:
                      _editNote();
                      break;
                    case _ClipMenuAction.uploadReward:
                      _claimUploadReward();
                      break;
                    case _ClipMenuAction.delete:
                      widget.onDelete?.call();
                      break;
                  }
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.rename,
                  child: Text(l10n.historyMenuRename),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.note,
                  child: Text(
                      (clip.note?.trim().isNotEmpty ?? false)
                          ? l10n.historyMenuEditNote
                          : l10n.historyMenuAddNote),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.share,
                  enabled: clip.isAnalyzed,
                  child: Row(children: [
                    Icon(Icons.share_outlined,
                        size: 16,
                        color: clip.isAnalyzed
                            ? kBrandPrimary
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.historyMenuShare,
                        style: TextStyle(
                            color:
                                clip.isAnalyzed ? null : Colors.grey)),
                  ]),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.customExport,
                  enabled: !_isDownloading,
                  child: Row(children: [
                    Icon(_isDownloading ? Icons.hourglass_top_rounded : Icons.download_rounded,
                        size: 16,
                        color: _isDownloading ? Colors.grey : kBrandPrimary),
                    const SizedBox(width: 8),
                    Text(_isDownloading ? l10n.historyMenuDownloading : l10n.exportCustomTitle),
                  ]),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.uploadReward,
                  enabled: clip.isAnalyzed && !clip.isEffectivelyUploaded,
                  child: Row(children: [
                    Icon(Icons.cloud_upload_rounded,
                        size: 16,
                        color: (clip.isAnalyzed && !clip.isEffectivelyUploaded)
                            ? const Color(0xFF00897B)
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      clip.isEffectivelyUploaded
                          ? l10n.historyMenuUploaded
                          : l10n.historyMenuUploadReward(RewardType.uploadData.ballsPerAction),
                      style: TextStyle(
                          color: (clip.isAnalyzed &&
                                  !clip.isEffectivelyUploaded)
                              ? null
                              : Colors.grey),
                    ),
                  ]),
                ),
                PopupMenuItem<_ClipMenuAction>(
                  value: _ClipMenuAction.delete,
                  child: Text(l10n.historyMenuDeleteVideo,
                      style: const TextStyle(color: Colors.red)),
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
              color: context.bgInset,
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
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    Text(
                      AppLocalizations.of(context).historyCompareTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context).historyCompareSubtitle(currentEntry.displayTitle),
                      style: TextStyle(fontSize: 12, color: context.textSecondary),
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

  String _label(BuildContext context) {
    if (!selected || dateFrom == null) return AppLocalizations.of(context).historyFilterCustomDate;
    final from = dateFrom!;
    final to   = dateTo ?? from;
    String fmt(DateTime d) => '${d.month}/${d.day}';
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
          helpText: AppLocalizations.of(context).historyDateRangeHelp,
          cancelText: AppLocalizations.of(context).commonCancel,
          confirmText: AppLocalizations.of(context).commonOk,
          saveText: AppLocalizations.of(context).commonOk,
        );
        if (picked != null) {
          onPicked(picked.start, DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : context.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : context.borderColor,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 13,
              color: selected ? Colors.white : context.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              _label(context),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : context.textSecondary,
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
          color: selected ? selectedColor : context.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? selectedColor : context.borderColor,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.textSecondary,
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
          SnackBar(
            content: Text(AppLocalizations.of(context).historyPhasesJsonMissing),
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
          SnackBar(
            content: Text(AppLocalizations.of(context).historyPhasesJsonInvalid),
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
      title: Text(AppLocalizations.of(context).historySelectAiModeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeTile(context, 'v1', Icons.flash_on_rounded,
              AppLocalizations.of(context).historyAiModeV1Title,
              AppLocalizations.of(context).historyAiModeV1Desc),
          const SizedBox(height: 8),
          _modeTile(context, 'v2', Icons.videocam_rounded,
              AppLocalizations.of(context).historyAiModeV2Title,
              AppLocalizations.of(context).historyAiModeV2Desc),
          const SizedBox(height: 8),
          _modeTile(context, 'v3', Icons.photo_library_rounded,
              AppLocalizations.of(context).historyAiModeV3Title,
              AppLocalizations.of(context).historyAiModeV3Desc),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).commonCancel),
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
        side: BorderSide(color: ctx.borderColor),
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
  final String? confirmLabel;

  const _ConfirmActionDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.confirmLabel,
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
            style: TextStyle(fontSize: 13.5, color: context.textSecondary, height: 1.5),
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
                    side: BorderSide(color: context.textHint),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).historySkipToday,
                  style: TextStyle(fontSize: 12.5, color: context.textSecondary),
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
          child: Text(AppLocalizations.of(context).commonCancel, style: TextStyle(color: context.textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.iconColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(_ConfirmResult(skipToday: _skipToday)),
          child: Text(widget.confirmLabel ?? AppLocalizations.of(context).commonOk),
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
  final bool bothHands;
  const _DetectionModeResult({
    required this.mode,
    this.skipToday = false,
    this.bothHands = false,
  });
}

class _DetectionModeDialog extends StatefulWidget {
  final bool initialBothHands;
  final bool hasAnchor; // 此影片錄製時帶錨點 → 顯示離線 V4
  const _DetectionModeDialog({this.initialBothHands = false, this.hasAnchor = false});
  @override
  State<_DetectionModeDialog> createState() => _DetectionModeDialogState();
}

class _DetectionModeDialogState extends State<_DetectionModeDialog> {
  SkeletonAnalysisMode _mode = SkeletonAnalysisMode.v1;
  bool _skipToday = false;
  late bool _bothHands = widget.initialBothHands;

  static const _kGreen  = kBrandPrimary;
  static const _kOrange = Color(0xFFE65100);
  static const _kBlue   = Color(0xFF1565C0);
  static const _kViolet = Color(0xFF6B4FD8);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Row(children: [
        const Icon(Icons.sports_golf_rounded, color: Color(0xFFE65100), size: 22),
        const SizedBox(width: 8),
        Text(AppLocalizations.of(context).historySelectDetectModeTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 模式卡片 ──
          _modeCard(
            mode: SkeletonAnalysisMode.v1,
            icon: Icons.accessibility_new_rounded,
            color: _kGreen,
            title: AppLocalizations.of(context).historyDetectV1Title,
            subtitle: AppLocalizations.of(context).historyDetectV1Desc,
            badge: AppLocalizations.of(context).historyDetectBadgePrecise,
            badgeColor: _kGreen,
            timeHint: AppLocalizations.of(context).historyDetectV1Time,
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          _modeCard(
            mode: SkeletonAnalysisMode.v2,
            icon: Icons.graphic_eq_rounded,
            color: _kOrange,
            title: AppLocalizations.of(context).historyDetectV2Title,
            subtitle: AppLocalizations.of(context).historyDetectV2Desc,
            badge: AppLocalizations.of(context).historyDetectBadgeFast,
            badgeColor: _kOrange,
            timeHint: AppLocalizations.of(context).historyDetectV2Time,
          ),
          const SizedBox(height: 8),
          _modeCard(
            mode: SkeletonAnalysisMode.v3,
            icon: Icons.track_changes_rounded,
            color: _kBlue,
            title: AppLocalizations.of(context).historyDetectV3Title,
            subtitle: AppLocalizations.of(context).historyDetectV3Desc,
            badge: AppLocalizations.of(context).historyDetectBadgeBalanced,
            badgeColor: _kBlue,
            timeHint: AppLocalizations.of(context).historyDetectV3Time,
          ),
          // V4 錨點：僅在此影片錄製時帶錨點才顯示
          if (widget.hasAnchor) ...[
            const SizedBox(height: 8),
            _modeCard(
              mode: SkeletonAnalysisMode.v4,
              icon: Icons.center_focus_strong_rounded,
              color: _kViolet,
              title: AppLocalizations.of(context).historyDetectV4Title,
              subtitle: AppLocalizations.of(context).historyDetectV4Desc,
              badge: AppLocalizations.of(context).historyDetectBadgeAnchor,
              badgeColor: _kViolet,
              timeHint: AppLocalizations.of(context).historyDetectV1Time,
            ),
          ],
          // ── 雙手判斷 ──
          Divider(height: 16, thickness: 0.8, color: context.borderColor),
          GestureDetector(
            onTap: () => setState(() => _bothHands = !_bothHands),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                Icon(Icons.back_hand_outlined, size: 18, color: context.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).swingBothHands,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(AppLocalizations.of(context).swingBothHandsDesc,
                          style: TextStyle(fontSize: 11, color: context.textSecondary)),
                    ],
                  ),
                ),
                Switch(
                  value: _bothHands,
                  onChanged: (v) => setState(() => _bothHands = v),
                  activeThumbColor: kBrandPrimary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ]),
            ),
          ),
          // ── 今日不再提醒 ──
          Divider(height: 8, thickness: 0.8, color: context.borderColor),
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
                    side: BorderSide(color: context.textHint),
                  ),
                ),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context).historySkipToday, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(AppLocalizations.of(context).commonCancel, style: TextStyle(color: context.textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _mode == SkeletonAnalysisMode.v2 ? _kOrange
                           : _mode == SkeletonAnalysisMode.v3 ? _kBlue
                           : _mode == SkeletonAnalysisMode.v4 ? _kViolet
                           : _kGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(
            _DetectionModeResult(
                mode: _mode, skipToday: _skipToday, bothHands: _bothHands),
          ),
          child: Text(AppLocalizations.of(context).historyStartDetect),
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
            color: isOn ? color : context.borderColor,
            width: isOn ? 1.5 : 1.0,
          ),
        ),
        child: Row(children: [
          Icon(icon, color: isOn ? color : context.textHint, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: TextStyle(
                  fontSize: 13.5, fontWeight: isOn ? FontWeight.w700 : FontWeight.w500,
                  color: isOn ? color : context.textPrimary,
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
              Text(subtitle, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
            ]),
          ),
          Text(timeHint, style: TextStyle(
            fontSize: 10.5, color: isOn ? color : context.textHint, fontWeight: FontWeight.w500,
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
      title: Row(
        children: [
          const Icon(Icons.high_quality_rounded, color: kBrandPrimary, size: 22),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context).historySelectQualityTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                      ? kBrandPrimary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? kBrandPrimary
                        : context.borderColor,
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
                          ? kBrandPrimary
                          : context.textHint,
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
                                  ? kBrandPrimary
                                  : context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            q.sizeHint,
                            style: TextStyle(
                                fontSize: 12, color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      q.bitrateHint,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? kBrandPrimary
                            : context.textHint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // ── 今日不再提醒 ──
          Divider(height: 16, thickness: 0.8, color: context.borderColor),
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
                      side: BorderSide(color: context.textHint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context).historySkipToday,
                    style:
                        TextStyle(fontSize: 12.5, color: context.textSecondary),
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
              Text(AppLocalizations.of(context).commonCancel, style: TextStyle(color: context.textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kBrandPrimary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(
            _QualityDialogResult(quality: _selected, skipToday: _skipToday),
          ),
          child: Text(AppLocalizations.of(context).historyStartAnalysis),
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
    const ch = MethodChannel('com.example.golf_score_app/pose_analyzer');
    await ch.invokeMethod<void>('cancel');
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
    if (!AdService.adsEnabled) return; // Pro / Elite 免廣告
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
                  child: Text(AppLocalizations.of(context).commonCancel, style: const TextStyle(color: Colors.white54)),
                ),
              ]
            : null,
      ),
    );
  }
}

/// 共用上傳獎勵流程（原始影片與切片皆走此路）：
/// 確認 → 上傳分析資料領獎勵 → 標記 isUploaded。
/// 回傳更新後的 entry（取消或失敗回傳 null）。
///
/// 條件：entry 需已分析；AI 分析過的影片（影片+CSV 已在伺服器）
/// 視為已上傳（isEffectivelyUploaded），不可重複領取。
Future<RecordingHistoryEntry?> _runUploadRewardFlow(
    BuildContext context, RecordingHistoryEntry entry) async {
  final balls = RewardType.uploadData.ballsPerAction;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(context).historyUploadRewardTitle),
      content: Text(
        AppLocalizations.of(context).historyUploadRewardContent(entry.displayTitle, balls),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(AppLocalizations.of(context).historyUploadSubmit),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;

  // 真實上傳影片 + CSV（可能 5-50MB，顯示進度提示）
  String? uploadId;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(AppLocalizations.of(context).historyUploadingProgress)),
        ]),
      ),
    ),
  );
  try {
    uploadId = await RewardService.uploadSessionFiles(entry);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).historyUploadFailed(e.toString())),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return null;
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();

  try {
    final pending = await RewardService.claimUploadReward(sessions: [
      {
        'filePath':        entry.filePath,
        'recordedAt':      entry.recordedAt.toIso8601String(),
        'durationSeconds': entry.durationSeconds,
        'goodShot':        entry.goodShot,
        'audioCrispness':  entry.audioCrispness,
        'audioLabel':      entry.audioLabel,
        'videoType':       entry.videoType.name,
        'uploadId':        uploadId,
      },
    ]);
    // pending=0 = 送審未建立（網路失敗或同檔已提交過，含被拒絕者——
    // 審核制不允許重送），不標記 isUploaded，讓使用者可在排除問題後重試。
    if (pending == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).historyUploadSubmitFailed),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return null;
    }
    // isUploaded 標記：防止重複提交（被拒絕者依政策不開放重送）。
    final updated = entry.copyWith(isUploaded: true);
    await RecordingHistoryStorage.instance.upsertEntry(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).historyUploadReviewPending(balls)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return updated;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).historyUploadFailed(e.toString())),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return null;
  }
}

/// 共用備註編輯對話框（原始影片與切片皆走此路）。
/// 回傳 null = 取消；'' = 清除備註；其餘為新備註內容。
Future<String?> _showNoteDialog(BuildContext context, String? initial) {
  String tempNote = initial ?? '';
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(context).historyNoteDialogTitle),
      content: TextField(
        controller: TextEditingController(text: initial ?? ''),
        maxLength: 200,
        maxLines: 4,
        minLines: 2,
        autofocus: true,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).historyNoteHint,
          helperText: AppLocalizations.of(context).historyNoteHelper,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => tempNote = v,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(tempNote.trim()),
          child: Text(AppLocalizations.of(context).commonSave),
        ),
      ],
    ),
  );
}

/// 列表卡片上的備註列（單行省略，原始影片與切片共用）
class _NoteLine extends StatelessWidget {
  final String note;
  const _NoteLine({required this.note});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.sticky_note_2_outlined,
          size: 12, color: kBrandPrimary),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          note,
          style: TextStyle(
            fontSize: 11,
            color: context.textSecondary,
            fontStyle: FontStyle.italic,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

/// 匯出流程（原始影片與切片共用）：勾選疊加元素 → 單 pass 合成 →
/// 選儲存位置 → 匯出。浮水印由方案決定（免費強制）。
Future<void> _runCustomExportFlow(
    BuildContext context, RecordingHistoryEntry entry) async {
  final l10n = AppLocalizations.of(context);
  final sessionDir = p.dirname(entry.filePath);
  if (!OverlayBurnService.canCompose(sessionDir)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.recDetailNoVideoFound),
      backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final hasSkeleton   = resolveSkeletonCsv(sessionDir) != null;
  final hasTrajectory = File(p.join(sessionDir, 'trajectory.json')).existsSync();
  final isFree        = context.read<PlanProvider>().plan == UserPlan.free;

  final spec = await showModalBottomSheet<ExportSpec>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => CustomExportSheet(
      hasSkeleton: hasSkeleton,
      hasTrajectory: hasTrajectory,
      hasImpact: entry.hitSecond != null,
      hasShotQuality: entry.goodShot != null,
      isFree: isFree,
    ),
  );
  if (spec == null || !context.mounted) return;

  final toFolder = await _showSaveLocationPicker(context);
  if (toFolder == null || !context.mounted) return;

  final burned = await OverlayBurnService.composeForExport(
    sessionDir,
    spec,
    impactSec: entry.hitSecond,
    goodShot: entry.goodShot,
    passCount: entry.audioPassCount ?? 0,
  );
  if (burned == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.recDetailBurnFailed),
      backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final baseName = (entry.customName?.isNotEmpty == true)
      ? '${entry.customName!}_${l10n.exportCustomTitle}'
      : '${p.basenameWithoutExtension(entry.filePath)}_${l10n.exportCustomTitle}';
  final result = toFolder
      ? await VideoExportService.downloadToFolder(burned, displayName: baseName)
      : await VideoExportService.download(burned, displayName: baseName);
  if (!context.mounted) return;
  _showExportResultSnackBar(context, result, l10n.exportCustomTitle);
}

void _showExportResultSnackBar(
    BuildContext context, ExportResult result, String label) {
  switch (result.status) {
    case ExportStatus.savedToDownloads:
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).historyExportSaved(label)),
        backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      ));
    case ExportStatus.savedToPhotos:
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).historyExportSavedPhotos(label)),
        backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      ));
    case ExportStatus.sharedViaSheet:
      break;
    case ExportStatus.failed:
      if (result.detail != 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).historyExportFailed(result.detail ?? '')),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
  }
}

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
          Text(AppLocalizations.of(ctx).historySaveLocationTitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.white70),
            title: Text(AppLocalizations.of(ctx).historySaveLocationDownloads, style: const TextStyle(color: Colors.white)),
            subtitle: Text(AppLocalizations.of(ctx).historySaveLocationDownloadsSub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open, color: Colors.white70),
            title: Text(AppLocalizations.of(ctx).historySaveLocationPick, style: const TextStyle(color: Colors.white)),
            subtitle: Text(AppLocalizations.of(ctx).historySaveLocationPickSub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
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
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 縮圖
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildThumb(context),
            ),
            const SizedBox(width: 12),
            // 資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: context.textHint),
                      const SizedBox(width: 3),
                      Text(
                        AppLocalizations.of(context).historyCandidateDuration(entry.durationSeconds),
                        style: TextStyle(fontSize: 11, color: context.textHint),
                      ),
                      if (entry.isAnalyzed) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, size: 12, color: Color(0xFF4CAF50)),
                        const SizedBox(width: 2),
                        Text(
                          AppLocalizations.of(context).historyBadgeAnalyzed,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb(BuildContext context) {
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
      color: context.bgInset,
      child: Icon(Icons.videocam, size: 24, color: context.textHint),
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
            color: enabled ? context.textSecondary : dimColor,
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
