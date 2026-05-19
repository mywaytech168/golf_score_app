import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recording_history_entry.dart';
import '../models/statistics_response.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../services/recording_history_storage.dart';
import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import '../services/statistics_service.dart';
import '../services/purchase_service.dart';
import '../services/plan_service.dart';
import '../widgets/green_page_header.dart';

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

  @override
  void initState() {
    super.initState();
    _loadInitialHistory();
    _initializeStatistics();
    _initializePurchaseService();
    _loadPlanStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
  }

  Future<void> _loadPlanStatus() async {
    try {
      final status = await PlanService.getPlanStatus();
      if (mounted) setState(() => _planStatus = status);
    } catch (_) {}
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認登出'),
        content: const Text('您確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定登出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AuthTokenStorage.instance.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
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
      if (missing) thumbnailPath = null;
      if (thumbnailPath != entry.thumbnailPath) hasChanges = true;
      updated.add(entry.copyWith(thumbnailPath: thumbnailPath));
    }
    return hasChanges ? updated : null;
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
                            _TodayOverviewCard(stats: today, loading: isLoading),
                            const SizedBox(height: kSpaceMD),
                            _KeyMetricsRow(stats: today, loading: isLoading),
                            const SizedBox(height: kSpaceMD),
                            if (!isLoading && (today?.totalCount ?? 0) > 0)
                              _GoodRateCard(
                                good: today?.goodShot ?? 0,
                                bad: today?.badShot ?? 0,
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
        ],
      ),
    );
  }

  Widget _buildGreenHeader(BuildContext context) {
    final plan  = _planStatus.plan;
    final limit = _planStatus.dailyLimit;
    final used  = _planStatus.todayUsed;
    final planColor = Color(plan.colorValue);

    final overLimit = !plan.isUnlimited && used >= limit;
    final quotaText = plan.isUnlimited
        ? '今日無限制 🏆'
        : '今日用量 $used / $limit 球${overLimit ? '  ⚠️ 已達上限' : ''}';

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
          title: '嗨，${user.displayName} 👋',
          subtitle: quotaText,
          actions: [
            planBadge,
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (v) { if (v == 'logout') _logout(); },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('登出', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── 今日快覽卡片 ──────────────────────────────────────────────────

class _TodayOverviewCard extends StatelessWidget {
  final StatisticsResponse? stats;
  final bool loading;
  const _TodayOverviewCard({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final practice = stats?.totalCount ?? 0;
    final good = stats?.goodShot ?? 0;
    final bad = stats?.badShot ?? 0;

    final now = DateTime.now();
    final weekdays = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
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
              const Text(
                '今日概況',
                style: TextStyle(
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
                        label: '練習次數',
                        value: practice.toString(),
                        icon: Icons.sports_golf_rounded),
                    const _WhiteDivider(),
                    _OverviewStat(
                        label: '好球',
                        value: good.toString(),
                        icon: Icons.thumb_up_rounded),
                    const _WhiteDivider(),
                    _OverviewStat(
                        label: '壞球',
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
        3,
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

    return Row(
      children: [
        Expanded(
          child: _MetricMini(
            label: '最佳速度',
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
            label: '甜蜜點',
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
            label: '清脆度',
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

// ── 好球率卡片 ────────────────────────────────────────────────────

class _GoodRateCard extends StatelessWidget {
  final int good;
  final int bad;
  const _GoodRateCard({required this.good, required this.bad});

  @override
  Widget build(BuildContext context) {
    final total = good + bad;
    final rate = total > 0 ? good / total : 0.0;
    final pct = (rate * 100).round();

    return Container(
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: kCardDecoration(radius: kRadiusMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: kPrimaryGreen, size: 18),
              const SizedBox(width: kSpaceSM),
              const Text(
                '今日好球率',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: kTextPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: kPrimaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceMD),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor: kBadColor.withValues(alpha: 0.15),
              color: kGoodColor,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: kSpaceSM),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Dot(color: kGoodColor, label: '好球 $good 次'),
              _Dot(color: kBadColor, label: '壞球 $bad 次'),
            ],
          ),
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
