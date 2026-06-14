import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/recording_history_entry.dart';
import '../models/statistics_response.dart';
import '../providers/user_provider.dart';
import '../providers/plan_provider.dart';
import '../services/plan_service.dart';
import '../theme/app_theme.dart';
import '../services/recording_history_storage.dart';
import '../services/video_server_client.dart';
import '../services/statistics_service.dart';
import '../services/purchase_service.dart';
import '../services/announcement_service.dart';
import '../services/reward_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/p_system_trend_service.dart';
import '../widgets/audio_feature_pass_row.dart';
import '../widgets/green_page_header.dart';
import '../widgets/posture_breakdown_card.dart';
import '../widgets/p_system_trend_card.dart';
import 'announcement_page.dart';
import 'reward_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  /// 點問候語「準備開始」時跳轉到錄製分頁（由 main_shell 切到 index 2）。
  final VoidCallback? onStartRecording;
  const HomePage({super.key, this.onStartRecording});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<RecordingHistoryEntry> _recordingHistory = [];
  late final StatisticsService _statisticsService = StatisticsService();
  late final PurchaseService _purchaseService = PurchaseService();

  int _unreadAnnouncements = 0;
  Map<String, double>? _featurePassRates;
  RewardStatus? _rewardStatus;

  @override
  void initState() {
    super.initState();
    _loadInitialHistory();
    _initializeStatistics();
    _initializePurchaseService();
    _loadUnreadCount();
    _loadRewardStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlanProvider>().refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
  }

  Future<void> _loadRewardStatus() async {
    try {
      final status = await RewardService.getStatus();
      if (mounted) setState(() => _rewardStatus = status);
    } catch (e) {
      debugPrint('⚠️ [HomePage] 載入獎勵狀態失敗: $e');
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await AnnouncementService.instance.getUnreadCount();
      if (mounted) setState(() => _unreadAnnouncements = count);
    } catch (e) {
      debugPrint('⚠️ [HomePage] 載入公告未讀數失敗: $e');
    }
  }

  Future<void> _openAnnouncements() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnnouncementPage()),
    );
    _loadUnreadCount(); // 返回後刷新未讀數
  }

  @override
  void dispose() {
    _statisticsService.dispose();
    super.dispose();
  }

  Future<void> _initializePurchaseService() async {
    try {
      await _purchaseService.initialize();
    } catch (e) {
      debugPrint('❌ [購買服務] 初始化失敗: $e');
    }
  }

  Future<void> _initializeStatistics() async {
    try {
      await _statisticsService.loadAllStatistics();
      if (mounted) context.read<PlanProvider>().refresh(); // 統計刷新後同步用量
      final rates = await _computeFeaturePassRates();
      if (mounted) setState(() => _featurePassRates = rates);
    } on UnauthorizedException {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('⚠️ 初始化統計服務失敗: $e');
    }
  }

  Future<Map<String, double>?> _computeFeaturePassRates() async {
    try {
      final all = await RecordingHistoryStorage.instance.loadHistory();
      final now = DateTime.now();
      final filtered = all.where((e) {
        if (e.audioPasses == null) return false;
        final t = e.recordedAt;
        return t.year == now.year && t.month == now.month && t.day == now.day;
      }).toList();
      if (filtered.isEmpty) return null;
      final totals = <String, int>{};
      final passes = <String, int>{};
      for (final entry in filtered) {
        final ap = entry.audioPasses!;
        for (final key in AudioAnalysisService.featureLabels.keys) {
          totals[key] = (totals[key] ?? 0) + 1;
          if (ap[key] == true) passes[key] = (passes[key] ?? 0) + 1;
        }
      }
      if (totals.isEmpty) return null;
      return {
        for (final key in AudioAnalysisService.featureLabels.keys)
          if (totals.containsKey(key))
            key: (passes[key] ?? 0) / totals[key]!,
      };
    } catch (e) {
      debugPrint('⚠️ [HomePage] feature pass rates 失敗: $e');
      return null;
    }
  }

  /// 取得「目前建議」：歷史中最近一筆且含訓練建議的紀錄
  RecordingHistoryEntry? get _currentSuggestionEntry {
    RecordingHistoryEntry? best;
    for (final e in _recordingHistory) {
      final s = e.practiceSuggestions;
      if (s == null || s.isEmpty) continue;
      if (best == null || e.sortTime.isAfter(best.sortTime)) best = e;
    }
    return best;
  }

  /// 勾選 / 取消勾選某則訓練建議，並寫回資料庫
  Future<void> _toggleSuggestion(
      RecordingHistoryEntry entry, int index, bool done) async {
    final list = List<PracticeSuggestionItem>.from(entry.practiceSuggestions!);
    if (index < 0 || index >= list.length) return;
    list[index] = list[index].copyWith(done: done);
    final updated = entry.copyWith(practiceSuggestions: list);
    setState(() {
      final i =
          _recordingHistory.indexWhere((e) => e.filePath == entry.filePath);
      if (i >= 0) _recordingHistory[i] = updated;
    });
    await RecordingHistoryStorage.instance.upsertEntry(updated);
  }

  Future<void> _loadInitialHistory() async {
    final entries = await RecordingHistoryStorage.instance.loadHistory();
    final regenerated = await _cleanInvalidThumbnails(entries);
    final finalEntries = regenerated ?? entries;
    if (!mounted) return;
    setState(() {
      _recordingHistory
        ..clear()
        ..addAll(finalEntries);
    });
    if (regenerated != null) {
      unawaited(RecordingHistoryStorage.instance.saveHistory(finalEntries));
    }
  }

  Future<List<RecordingHistoryEntry>?> _cleanInvalidThumbnails(
    List<RecordingHistoryEntry> entries,
  ) async {
    if (entries.isEmpty) return null;
    final updated = <RecordingHistoryEntry>[];
    var hasChanges = false;
    for (final entry in entries) {
      // 跳過 pre-warm session（pw_ 前綴），這些資料夾是相機預熱用，不應出現在歷史
      final folderName = p.basename(p.dirname(entry.filePath));
      if (folderName.startsWith('pw_')) {
        // 將這筆標記為無縮圖（不產生）
        if (entry.thumbnailPath != null) {
          updated.add(entry.copyWith(thumbnailPath: null));
          hasChanges = true;
        } else {
          updated.add(entry);
        }
        continue;
      }

      var thumbnailPath = entry.thumbnailPath;
      final missing = thumbnailPath == null ||
          thumbnailPath.isEmpty ||
          !(await File(thumbnailPath).exists());
      if (missing) {
        // 縮圖遺失時嘗試從影片重新生成（處理舊有 HEVC/MOV 影片）
        final regen = await _tryRegenThumbnail(entry.filePath);
        thumbnailPath = regen;
      }
      if (thumbnailPath != entry.thumbnailPath) hasChanges = true;
      updated.add(entry.copyWith(thumbnailPath: thumbnailPath));
    }
    return hasChanges ? updated : null;
  }

  /// 嘗試重新生成縮圖，支援 HEVC/MOV fallback。失敗回傳 null。
  static Future<String?> _tryRegenThumbnail(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;
    // 過小的檔案（< 100KB）通常是空白或損壞的影片，直接跳過
    if (await file.length() < 100 * 1024) return null;
    final outPath = p.join(file.parent.path, 'thumbnail.jpg');
    for (final timeMs in [0, 1000, 3000]) {
      try {
        final path = await vt.VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: outPath,
          imageFormat: vt.ImageFormat.JPEG,
          maxHeight: 256,
          timeMs: timeMs,
          quality: 75,
        );
        if (path != null && path.isNotEmpty) return path;
      } catch (_) {}
    }
    try {
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: vt.ImageFormat.JPEG,
        maxHeight: 256,
        timeMs: 0,
        quality: 75,
      );
      if (bytes != null && bytes.isNotEmpty) {
        await File(outPath).writeAsBytes(bytes);
        return outPath;
      }
    } catch (_) {}
    return null;
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: Column(
        children: [
          // ── 綠色頂部面板 ─────────────────────────────────────
          _buildGreenHeader(context),

          // ── 可捲動主體 ───────────────────────────────────────
          Expanded(
            child: StreamBuilder<LoadingState>(
              stream: _statisticsService.watchLoadingState(),
              initialData: _statisticsService.loadingState,
              builder: (context, loadingSnap) {
                return StreamBuilder<StatisticsResponse?>(
                  stream: _statisticsService.watchStatistics(),
                  initialData: _statisticsService.statistics,
                  builder: (context, statsSnap) {
                    final today = _statisticsService.todayStatistics;
                    final isLoading = loadingSnap.data?.isLoading ?? false;

                    final l = AppLocalizations.of(context);
                    return RefreshIndicator(
                      onRefresh: () async {
                        await _initializeStatistics();
                        await _loadRewardStatus();
                      },
                      color: kBrandPrimary,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            kSpaceMD, kSpaceMD, kSpaceMD, kSpaceXL),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildGreeting(context),
                            const SizedBox(height: kSpaceLG),
                            _buildQuotaRows(context),
                            const SizedBox(height: kSpaceLG),
                            _buildStatsRow(context, today, isLoading),
                            const SizedBox(height: kSpaceLG),
                            _HitAnalysisCard(
                              today: today,
                              overall: statsSnap.data,
                              loading: isLoading,
                              onTap: () => _showAnalysisDetailSheet(
                                  context, today, isLoading),
                            ),
                            const SizedBox(height: kSpaceMD),
                            if (_currentSuggestionEntry == null &&
                                !isLoading &&
                                ((today?.goodShot ?? 0) +
                                        (today?.badShot ?? 0)) ==
                                    0)
                              Padding(
                                padding: const EdgeInsets.only(top: kSpaceSM),
                                child: Column(
                                  children: [
                                    Text(
                                      l.homeEmptyHint,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: context.textHint),
                                    ),
                                    const SizedBox(height: kSpaceMD),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: widget.onStartRecording,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: kBrandPrimary,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14)),
                                        ),
                                        icon: const Icon(
                                            Icons.videocam_rounded, size: 20),
                                        label: Text(
                                          l.homeStartRecording,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ── 訓練重點 banner（固定在底部導覽列上方）──────────────
          if (_currentSuggestionEntry != null)
            _FocusBanner(
              entry: _currentSuggestionEntry!,
              onTap: () => _showSuggestionsSheet(context),
            ),
        ],
      ),
    );
  }

  // ── 問候語區塊 ───────────────────────────────────────────────

  Widget _buildGreeting(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Consumer<UserProvider>(
      builder: (context, user, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.homeHi(user.displayName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: context.textPrimary,
            ),
          ),
          // 「準備開始」流光漸層 + 點擊跳轉錄製
          _StartShimmerGreeting(
            text: l.homeGreetingQuestion,
            onTap: widget.onStartRecording,
          ),
        ],
      ),
    );
  }

  // ── 今日用量 / 獎勵球數 兩列 ─────────────────────────────────

  Widget _buildQuotaRows(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Consumer<PlanProvider>(
      builder: (context, planProvider, _) {
        final s = planProvider.status;
        final quotaValue = s.plan.isUnlimited
            ? l.homeTodayUnlimited
            : l.homeQuotaBalls(s.todayUsed, s.dailyLimit);
        final adCap = RewardType.watchAd.dailyCap;
        final rewardValue =
            l.homeQuotaBalls(_rewardStatus?.adClaimedToday ?? 0, adCap);
        void openRewards() {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RewardPage()))
              .then((_) {
            planProvider.refresh();
            _loadRewardStatus();
          });
        }

        return Material(
          color: context.bgCard, // 白背景（淺色主題）
          borderRadius: BorderRadius.circular(kRadiusMD),
          child: InkWell(
            onTap: openRewards,
            borderRadius: BorderRadius.circular(kRadiusMD),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadiusMD),
                border: Border.all(color: context.borderColor),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: kSpaceMD, vertical: 14),
              child: Row(
                children: [
                  _QuotaHalf(
                    icon: Icons.adjust_rounded,
                    label: l.homeTodayQuota,
                    value: quotaValue,
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: context.borderColor,
                    margin: const EdgeInsets.symmetric(horizontal: kSpaceSM),
                  ),
                  _QuotaHalf(
                    icon: Icons.smart_display_rounded,
                    label: l.homeRewardBalls,
                    value: rewardValue,
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: context.borderColor,
                    margin: const EdgeInsets.symmetric(horizontal: kSpaceSM),
                  ),
                  _QuotaHalf(
                    icon: Icons.savings_rounded,
                    label: l.rewardStatBonusBalls,
                    value: l.homeBallsUnit(_rewardStatus?.bonusBalls ?? 0),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 四格統計（無卡片、貼底色）────────────────────────────────

  Widget _buildStatsRow(
      BuildContext context, StatisticsResponse? today, bool loading) {
    final l = AppLocalizations.of(context);
    String v(int? n) => loading ? '–' : (n ?? 0).toString();
    return Row(
      children: [
        _PlainStat(label: l.homeRounds, value: v(today?.roundCount)),
        _PlainStat(label: l.homePractices, value: v(today?.practiceCount)),
        _PlainStat(label: l.homeGoodShot, value: v(today?.goodShot)),
        _PlainStat(label: l.homeBadShot, value: v(today?.badShot)),
      ],
    );
  }

  // ── 擊球分析細節 sheet（速度/甜蜜點、音訊特徵、姿勢分解）──────

  void _showAnalysisDetailSheet(
      BuildContext context, StatisticsResponse? today, bool loading) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgPage,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLG)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kSpaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _KeyMetricsRow(stats: today, loading: loading),
              const SizedBox(height: kSpaceSM),
              AudioFeaturePassRow(passRates: _featurePassRates),
              const SizedBox(height: kSpaceMD),
              PostureBreakdownCard(
                breakdown: today?.postureBreakdown ?? {},
                title: AppLocalizations.of(context).homeTodayPosture,
              ),
              const SizedBox(height: kSpaceMD),
              // 修正追蹤：跨 clip 讀 angles.json 算 P-System 趨勢（無資料→不顯示）
              FutureBuilder<List<DefectTrend>>(
                future: PSystemTrendService.loadRecent(),
                builder: (ctx, snap) {
                  final trends = snap.data;
                  if (trends == null || trends.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return PSystemTrendCard(trends: trends);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 訓練建議 sheet ───────────────────────────────────────────

  void _showSuggestionsSheet(BuildContext context) {
    final entry = _currentSuggestionEntry;
    if (entry == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgPage,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLG)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // 取最新版 entry（勾選後 _recordingHistory 內容已更新）
          final cur = _recordingHistory.firstWhere(
            (e) => e.filePath == entry.filePath,
            orElse: () => entry,
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(kSpaceMD),
              child: _PracticeSuggestionsCard(
                entry: cur,
                onToggle: (e, i, done) async {
                  await _toggleSuggestion(e, i, done);
                  setSheetState(() {});
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGreenHeader(BuildContext context) {
    return Consumer2<UserProvider, PlanProvider>(
      builder: (context, user, planProvider, _) {
        final plan = planProvider.status.plan;
        return _buildGreenHeaderContent(
          context: context,
          user: user,
          plan: plan,
        );
      },
    );
  }

  Widget _buildGreenHeaderContent({
    required BuildContext context,
    required UserProvider user,
    required UserPlan plan,
  }) {
    final l = AppLocalizations.of(context);

    // 頭像
    final avatar = SizedBox(
      width: 40,
      height: 40,
      child: user.avatarPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(user.avatarPath!), fit: BoxFit.cover),
            )
          : Image.asset('assets/branding/logo_icon.png', fit: BoxFit.contain),
    );

    // 方案 badge：實心白底 + 品牌深字（高對比，不再融進漸層）
    final planBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 層級色點（金/藍/灰等）+ 深字，白底高對比
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: Color(plan.colorValue), shape: BoxShape.circle),
          ),
          Text(
            plan.label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );

    return GreenPageHeader(
      leading: Padding(
        padding: const EdgeInsets.only(left: kSpaceMD, right: kSpaceSM),
        child: avatar,
      ),
      title: '',
      actions: [
        planBadge,
        // 公告鈴鐺
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: l.annBoardTitle,
              icon: const Icon(Icons.notifications_rounded,
                  color: Colors.white, shadows: _kHeaderIconShadow),
              onPressed: _openAnnouncements,
            ),
            if (_unreadAnnouncements > 0)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE05252),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _unreadAnnouncements > 99
                          ? '99+'
                          : '$_unreadAnnouncements',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: l.homeRewardBalls,
          icon: const Icon(Icons.card_giftcard_rounded,
              color: Colors.white, shadows: _kHeaderIconShadow),
          onPressed: () {
            final plan = context.read<PlanProvider>();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RewardPage()),
            ).then((_) => plan.refresh());
          },
        ),
        IconButton(
          tooltip: l.settingsTitle,
          icon: const Icon(Icons.settings_rounded,
              color: Colors.white, shadows: _kHeaderIconShadow),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
        ),
      ],
    );
  }
}

// ── 問候語「準備開始」流光漸層（點擊跳轉錄製）─────────────────────

/// 頂部白色 icon 在亮漸層上的細陰影，提升對比。
const _kHeaderIconShadow = <Shadow>[
  Shadow(color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1)),
];

/// 流光品牌色碼（深青 → Blue → Purple），循環發亮。對稱排列確保旋轉無縫。
/// 不用亮 cyan #00E5CC——它在淺色底上對比太低（看起來糊/淡），改用較深的青。
const _shimmerColors = <Color>[
  Color(0xFF008C99), // 深青（淺底可讀）
  kOrviaBlue,        // #4A7FFF
  kOrviaViolet,      // Purple #6B4FD8
  kOrviaBlue,
  Color(0xFF008C99),
];
const _shimmerStops = <double>[0.0, 0.25, 0.5, 0.75, 1.0];

class _StartShimmerGreeting extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  const _StartShimmerGreeting({required this.text, this.onTap});

  @override
  State<_StartShimmerGreeting> createState() => _StartShimmerGreetingState();
}

class _StartShimmerGreetingState extends State<_StartShimmerGreeting>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.25,
      color: Colors.white, // ShaderMask 需不透明底色
    );
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 旋轉漸層 → 色帶流動發亮（0~2π 無縫循環）
              Flexible(
                child: _GradientFlowText(
                    text: widget.text, style: textStyle, t: _ctrl.value),
              ),
              // 可點擊提示箭頭：實心品牌色（不用漸層，避免亮端在淺底上看不見）
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 3),
                child: Icon(Icons.play_circle_fill_rounded,
                    size: 24, color: kBrandPrimary),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 以旋轉漸層填色的文字，[t] 0→1 驅動色帶流動（無縫循環）。
class _GradientFlowText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double t;
  const _GradientFlowText(
      {required this.text, required this.style, required this.t});

  Widget _masked() => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: _shimmerColors,
          stops: _shimmerStops,
          transform: GradientRotation(t * 2 * math.pi),
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        // 單行不換行：空間不足時整體等比縮放，避免截字
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      );

  @override
  Widget build(BuildContext context) => _masked(); // 銳利漸層流光，不加模糊
}

// ── 今日用量 / 獎勵球數 半欄（合併雙欄卡用）──────────────────────

class _QuotaHalf extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _QuotaHalf({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.textPrimary),
          const SizedBox(width: kSpaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 四格統計（無卡片）────────────────────────────────────────────

class _PlainStat extends StatelessWidget {
  final String label;
  final String value;
  const _PlainStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: kSpaceXS),
          Text(value,
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ── 擊球分析卡片（甜蜜點圓環）────────────────────────────────────

class _HitAnalysisCard extends StatelessWidget {
  final StatisticsResponse? today;
  final StatisticsResponse? overall;
  final bool loading;
  final VoidCallback onTap;
  const _HitAnalysisCard({
    required this.today,
    required this.overall,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shots = (today?.goodShot ?? 0) + (today?.badShot ?? 0);
    final sweet = today?.sweetSpotPercentage ?? 0.0;
    final avgSweet = overall?.sweetSpotPercentage ?? 0.0;
    final delta = sweet - avgSweet;

    return Material(
      color: context.bgCard,
      borderRadius: BorderRadius.circular(kRadiusLG),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusLG),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(kSpaceLG),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadiusLG),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.homeHitAnalysis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.textHint),
                ],
              ),
              if (!loading && shots > 0 && delta >= 1) ...[
                const SizedBox(height: kSpaceXS),
                Text(
                  l.homeImprovedVsAvg(delta.toStringAsFixed(0)),
                  style: TextStyle(
                      fontSize: 13, color: context.textSecondary),
                ),
              ],
              const SizedBox(height: kSpaceMD),
              SizedBox(
                height: 180,
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: kBrandPrimary))
                    : shots == 0
                        ? Center(
                            child: Text(
                              l.homeNoShotsToday,
                              style: TextStyle(
                                  fontSize: 13, color: context.textHint),
                            ),
                          )
                        : _buildDonut(context, l,
                            today?.goodShot ?? 0, today?.badShot ?? 0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDonut(
      BuildContext context, AppLocalizations l, int good, int bad) {
    final total = good + bad;
    final goodV = good.toDouble();
    final badV = bad.toDouble();
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 56,
            startDegreeOffset: -90,
            sections: [
              PieChartSectionData(
                value: goodV > 0 ? goodV : (badV > 0 ? 0.0001 : 1),
                color: kGoodColor,
                radius: 26,
                showTitle: false,
              ),
              if (badV > 0)
                PieChartSectionData(
                  value: badV,
                  color: kBadColor,
                  radius: 26,
                  showTitle: false,
                ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$total',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: context.textPrimary,
              ),
            ),
            Text(
              l.homeHitRecordsLabel,
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendDot(color: kGoodColor, label: '${l.homeGoodShot} $good'),
              const SizedBox(height: 2),
              _LegendDot(color: kBadColor, label: '${l.homeBadShot} $bad'),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: context.textSecondary)),
      ],
    );
  }
}

// ── 訓練重點 banner ──────────────────────────────────────────────

class _FocusBanner extends StatelessWidget {
  final RecordingHistoryEntry entry;
  final VoidCallback onTap;
  const _FocusBanner({required this.entry, required this.onTap});

  String? get _focusText {
    final suggestions = entry.practiceSuggestions ?? const [];
    for (final s in suggestions) {
      if (!s.done && s.drill.trim().isNotEmpty) return s.drill.trim();
    }
    final goal = entry.nextTrainingGoal?.trim();
    if (goal != null && goal.isNotEmpty) return goal;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = _focusText;
    if (text == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(kSpaceMD, 0, kSpaceMD, kSpaceSM),
        child: Material(
          color: context.mintTint,
          borderRadius: BorderRadius.circular(kRadiusMD),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(kRadiusMD),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kSpaceMD, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: kBrandPrimary),
                  const SizedBox(width: kSpaceSM),
                  Expanded(
                    child: Text(
                      '${l.homeTrainingFocus}：$text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    l.homeViewNow,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kBrandPrimary,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: kBrandPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 三項核心指標橫排 ──────────────────────────────────────────────

class _KeyMetricsRow extends StatelessWidget {
  final StatisticsResponse? stats;
  final bool loading;
  const _KeyMetricsRow({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final speed = (stats?.peakValue.maximum ?? 0) > 0
        ? stats!.peakValue.maximum
        : null;
    final sweet = (stats?.sweetSpotPercentage ?? 0) > 0
        ? stats!.sweetSpotPercentage
        : null;

    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _MetricMini(
            label: l.homeTopSpeed,
            value: speed != null
                ? '${speed.toStringAsFixed(1)} MPH'
                : '--',
            icon: Icons.speed_rounded,
            color: kSpeedColor,
            loading: loading,
          ),
        ),
        const SizedBox(width: kSpaceSM),
        Expanded(
          child: _MetricMini(
            label: l.homeSweetSpot,
            value: sweet != null
                ? '${sweet.toStringAsFixed(0)}%'
                : '--',
            icon: Icons.adjust_rounded,
            color: kSweetColor,
            loading: loading,
          ),
        ),
      ],
    );
  }
}

class _MetricMini extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool loading;
  const _MetricMini({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpaceSM, vertical: kSpaceMD),
      decoration: kCardDecoration(
          color: context.bgCard,
          radius: kRadiusMD,
          shadow: context.cardShadow),
      child: loading
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: kSpaceSM),
                Container(
                  width: 40,
                  height: 14,
                  decoration: BoxDecoration(
                    color: context.textHint.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 15),
                ),
                const SizedBox(width: kSpaceSM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: value == '--' ? context.textHint : color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(label,
                          style: TextStyle(
                              fontSize: 10, color: context.textSecondary),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── 目前訓練建議卡片 ──────────────────────────────────────────────

class _PracticeSuggestionsCard extends StatelessWidget {
  final RecordingHistoryEntry entry;
  final Future<void> Function(
      RecordingHistoryEntry entry, int index, bool done) onToggle;

  const _PracticeSuggestionsCard({
    required this.entry,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = entry.practiceSuggestions ?? const [];
    final doneCount = suggestions.where((s) => s.done).length;
    final goal = entry.nextTrainingGoal?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kSpaceLG),
      decoration: kCardDecoration(
          color: context.bgCard,
          radius: kRadiusLG,
          shadow: context.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_golf_rounded,
                  color: kBrandPrimary, size: 20),
              const SizedBox(width: kSpaceSM),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).homeCurrentSuggestions,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Text(
                '$doneCount/${suggestions.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kBrandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceSM),
          ...suggestions.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value;
            return _SuggestionTile(
              suggestion: s,
              onChanged: (v) => onToggle(entry, i, v),
            );
          }),
          if (goal != null && goal.isNotEmpty) ...[
            const SizedBox(height: kSpaceSM),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(kSpaceSM),
              decoration: BoxDecoration(
                color: kBrandPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(kRadiusSM),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_rounded,
                      color: kBrandPrimary, size: 16),
                  const SizedBox(width: kSpaceXS),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).homeNextGoal(goal),
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final PracticeSuggestionItem suggestion;
  final ValueChanged<bool> onChanged;

  const _SuggestionTile({
    required this.suggestion,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final done = suggestion.done;
    final titleStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: done ? context.textHint : context.textPrimary,
      decoration: done ? TextDecoration.lineThrough : null,
    );

    return InkWell(
      onTap: () => onChanged(!done),
      borderRadius: BorderRadius.circular(kRadiusSM),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpaceXS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: done,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: kBrandPrimary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: kSpaceSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(suggestion.drill, style: titleStyle)),
                      if (suggestion.reps.trim().isNotEmpty) ...[
                        const SizedBox(width: kSpaceXS),
                        Text(
                          suggestion.reps,
                          style: const TextStyle(
                              fontSize: 11, color: kBrandPrimary),
                        ),
                      ],
                    ],
                  ),
                  if (suggestion.instruction.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        suggestion.instruction,
                        style: TextStyle(
                          fontSize: 12,
                          color: done ? context.textHint : context.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

