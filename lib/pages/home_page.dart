import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/recording_history_entry.dart';
import '../models/statistics_response.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../services/recording_history_storage.dart';
import '../services/video_server_client.dart';
import '../services/statistics_service.dart';
import '../services/purchase_service.dart';
import '../services/plan_service.dart';
import '../services/announcement_service.dart';
import '../widgets/green_page_header.dart';
import '../widgets/posture_breakdown_card.dart';
import 'announcement_page.dart';
import 'reward_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<RecordingHistoryEntry> _recordingHistory = [];
  late final StatisticsService _statisticsService = StatisticsService();
  late final PurchaseService _purchaseService = PurchaseService();

  PlanStatus _planStatus = const PlanStatus(
    plan: UserPlan.free,
    todayUsed: 0,
    dailyLimit: 10,
  );

  int _unreadAnnouncements = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialHistory();
    _initializeStatistics();
    _initializePurchaseService();
    _loadPlanStatus();
    _loadUnreadCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
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

  Future<void> _loadPlanStatus() async {
    try {
      final status = await PlanService.getPlanStatus();
      if (mounted) setState(() => _planStatus = status);
    } catch (e) {
      debugPrint('⚠️ [HomePage] 載入方案狀態失敗: $e');
    }
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
      await _loadPlanStatus(); // 統計刷新後同步用量
    } on UnauthorizedException {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('⚠️ 初始化統計服務失敗: $e');
    }
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
    if (!await File(videoPath).exists()) return null;
    final outPath = p.join(File(videoPath).parent.path, 'thumbnail.jpg');
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
      backgroundColor: kBgPage,
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

                    return RefreshIndicator(
                      onRefresh: _initializeStatistics,
                      color: kPrimaryGreen,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            kSpaceMD, kSpaceSM, kSpaceMD, kSpaceXL),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TodayOverviewCard(
                              rounds: today?.roundCount ?? 0,
                              practices: today?.practiceCount ?? 0,
                              good: today?.goodShot ?? 0,
                              bad: today?.badShot ?? 0,
                              loading: isLoading,
                            ),
                            const SizedBox(height: kSpaceMD),
                            _KeyMetricsRow(stats: today, loading: isLoading),
                            if (!isLoading && (today?.postureBreakdown.values.any((v) => v > 0) ?? false)) ...[
                              const SizedBox(height: kSpaceMD),
                              PostureBreakdownCard(
                                breakdown: today!.postureBreakdown,
                                title: AppLocalizations.of(context).homeTodayPosture,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreenHeader(BuildContext context) {
    final l         = AppLocalizations.of(context);
    final plan      = _planStatus.plan;
    final used      = _planStatus.todayUsed;
    final baseLimit = _planStatus.dailyLimit;   // 方案原始上限（不含獎勵）
    final total     = _planStatus.totalLimit;   // dailyLimit + bonusBalls（實際可用）
    final planColor = Color(plan.colorValue);

    final overLimit = !plan.isUnlimited && used >= total;
    String quotaText;
    if (plan.isUnlimited) {
      quotaText = l.homeTodayUnlimited;
    } else if (overLimit) {
      quotaText = '${l.homeTodayUsage(used, baseLimit)}  ${l.homeTodayLimit}';
    } else {
      quotaText = l.homeTodayUsage(used, baseLimit);
    }

    return Consumer<UserProvider>(
      builder: (context, user, _) {
        // 頭像
        final avatar = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white38, width: 1.5),
          ),
          child: user.avatarPath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.file(File(user.avatarPath!), fit: BoxFit.cover),
                )
              : const Icon(Icons.golf_course_rounded, color: Colors.white, size: 22),
        );

        // 方案 badge
        final planBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white38),
          ),
          child: Text(
            plan.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: planColor == const Color(0xFF1E8E5A)
                  ? Colors.white
                  : Color(plan.colorValue),
            ),
          ),
        );

        return GreenPageHeader(
          leading: Padding(
            padding: const EdgeInsets.only(left: kSpaceMD, right: kSpaceSM),
            child: avatar,
          ),
          title: l.homeHi(user.displayName),
          subtitle: quotaText,
          actions: [
            planBadge,
            // 公告鈴鐺
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: l.annBoardTitle,
                  icon: const Icon(Icons.notifications_rounded, color: Colors.white),
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
              icon: const Icon(Icons.card_giftcard_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RewardPage()),
              ).then((_) => _loadPlanStatus()),
            ),
            IconButton(
              tooltip: l.settingsTitle,
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── 今日快覽卡片 ──────────────────────────────────────────────────

class _TodayOverviewCard extends StatelessWidget {
  final int rounds;
  final int practices;
  final int good;
  final int bad;
  final bool loading;
  const _TodayOverviewCard({
    required this.rounds,
    required this.practices,
    required this.good,
    required this.bad,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final l   = AppLocalizations.of(context);
    final now = DateTime.now();
    final weekdays = [l.weekdayMon, l.weekdayTue, l.weekdayWed, l.weekdayThu, l.weekdayFri, l.weekdaySat, l.weekdaySun];
    final label =
        '${weekdays[now.weekday - 1]}  ${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return Container(
      decoration: const BoxDecoration(
        gradient: kPrimaryGradient,
        borderRadius: BorderRadius.all(Radius.circular(kRadiusLG)),
      ),
      padding: const EdgeInsets.all(kSpaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.homeTodayOverview,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: kSpaceLG),
          loading
              ? _buildSkeleton()
              : Row(
                  children: [
                    _OverviewStat(
                        label: l.homeRounds,
                        value: rounds.toString(),
                        icon: Icons.videocam_rounded),
                    const _WhiteDivider(),
                    _OverviewStat(
                        label: l.homePractices,
                        value: practices.toString(),
                        icon: Icons.sports_golf_rounded),
                    const _WhiteDivider(),
                    _OverviewStat(
                        label: l.homeGoodShot,
                        value: good.toString(),
                        icon: Icons.thumb_up_rounded),
                    const _WhiteDivider(),
                    _OverviewStat(
                        label: l.homeBadShot,
                        value: bad.toString(),
                        icon: Icons.thumb_down_rounded),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        4,
        (_) => Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: kSpaceSM),
            Container(
              width: 28,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _OverviewStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: kSpaceXS),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _WhiteDivider extends StatelessWidget {
  const _WhiteDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 52, color: Colors.white24);
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
    final crisp = (stats?.audioCrispness.average ?? 0) > 0
        ? stats!.audioCrispness.average
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
        const SizedBox(width: kSpaceSM),
        Expanded(
          child: _MetricMini(
            label: l.homeCrispness,
            value: crisp != null
                ? crisp.toStringAsFixed(0)
                : '--',
            icon: Icons.graphic_eq_rounded,
            color: kCrispColor,
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
      decoration: kCardDecoration(radius: kRadiusMD),
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
                    color: kTextHint.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: kSpaceSM),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: value == '--' ? kTextHint : color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: kTextSecondary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: kSpaceXS),
        Text(label,
            style: const TextStyle(fontSize: 12, color: kTextSecondary)),
      ],
    );
  }
}
