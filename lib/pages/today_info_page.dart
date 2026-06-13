import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import '../models/statistics_response.dart';
import '../services/audio_analysis_service.dart';
import '../services/local_statistics_calculator.dart';
import '../services/recording_history_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_feature_pass_row.dart';
import '../widgets/posture_breakdown_card.dart';

class TodayInfoPage extends StatefulWidget {
  const TodayInfoPage({super.key});

  @override
  State<TodayInfoPage> createState() => _TodayInfoPageState();
}

class _TodayInfoPageState extends State<TodayInfoPage> {
  bool _loading = true;
  bool _hasError = false;
  StatisticsResponse? _stats;
  /// 各音頻特徵通過率 key→0.0~1.0（null=無資料）
  Map<String, double>? _featurePassRates;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  String _formatApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDisplay(BuildContext context, DateTime d) {
    final l = AppLocalizations.of(context);
    final weekdays = [l.weekdayMon, l.weekdayTue, l.weekdayWed, l.weekdayThu, l.weekdayFri, l.weekdaySat, l.weekdaySun];
    final wd = weekdays[d.weekday - 1];
    final ds = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    return '$wd  $ds';
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final isToday = _isToday(_selectedDate);
      final period = isToday ? 'today' : 'day';
      final dateStr = isToday ? null : _formatApi(_selectedDate);
      final stats = await LocalStatisticsCalculator.compute(
        period: period,
        date: dateStr,
      );
      final featurePassRates = await _computeFeaturePassRates(period, dateStr);
      if (mounted) {
        setState(() {
          _stats = stats;
          _featurePassRates = featurePassRates;
          _loading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('[TodayInfoPage] 載入失敗: $e');
      if (mounted) setState(() { _stats = null; _featurePassRates = null; _loading = false; _hasError = true; });
    }
  }

  Future<Map<String, double>?> _computeFeaturePassRates(String period, String? dateStr) async {
    try {
      final all = await RecordingHistoryStorage.instance.loadHistory();
      final now = DateTime.now();
      final filtered = all.where((e) {
        if (e.audioPasses == null) return false;
        final t = e.recordedAt;
        if (period == 'today') {
          return t.year == now.year && t.month == now.month && t.day == now.day;
        } else if (period == 'day' && dateStr != null) {
          final parts = dateStr.split('-');
          if (parts.length != 3) return false;
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          return y != null && m != null && d != null &&
              t.year == y && t.month == m && t.day == d;
        }
        return true;
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
      debugPrint('[TodayInfoPage] feature pass rates 失敗: $e');
      return null;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: context.isDarkMode
              ? const ColorScheme.dark(
                  primary: kOrviaMint,
                  onPrimary: Color(0xFF00261A),
                )
              : const ColorScheme.light(
                  primary: kBrandPrimary,
                  onPrimary: Colors.white,
                ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _loadStats();
    }
  }

  void _shiftDate(int days) {
    final next = _selectedDate.add(Duration(days: days));
    if (next.isAfter(DateTime.now())) return;
    setState(() => _selectedDate = next);
    _loadStats();
  }

  // ── 資料取值 ──────────────────────────────────────────────────
  int get _rounds    => _stats?.roundCount    ?? 0;
  int get _practices => _stats?.practiceCount ?? 0;
  int get _good      => _stats?.goodShot      ?? 0;
  int get _bad => _stats?.badShot ?? 0;
  double? get _speed => (_stats?.peakValue.maximum ?? 0) > 0 ? _stats!.peakValue.maximum : null;
  double? get _sweet => (_stats?.sweetSpotPercentage ?? 0) > 0 ? _stats!.sweetSpotPercentage : null;

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(_selectedDate);
    final canGoNext = !isToday;

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(top: false, child: Column(
        children: [
          // ── 靜態 Header ─────────────────────────────────────
          _StaticHeader(
            displayText: _formatDisplay(context, _selectedDate),
            isToday: isToday,
          ),

          // ── 日期選擇列 ──────────────────────────────────────
          _DatePickerRow(
            date: _selectedDate,
            canGoNext: canGoNext,
            onPrev: () => _shiftDate(-1),
            onNext: () => _shiftDate(1),
            onPickDate: _pickDate,
          ),

          // ── 可捲動內容 ──────────────────────────────────────
          if (_hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppLocalizations.of(context).todayLoadFailed, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  TextButton(onPressed: _loadStats, child: Text(AppLocalizations.of(context).commonRetry)),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadStats,
              color: kBrandPrimary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(kSpaceMD),
                child: Column(
                  children: [
                    _SummaryBanner(
                      rounds:    _rounds,
                      practices: _practices,
                      good:      _good,
                      bad:       _bad,
                      loading:   _loading,
                    ),
                    const SizedBox(height: kSpaceMD),
                    _MetricGrid(
                      speed: _speed,
                      sweet: _sweet,
                      loading: _loading,
                    ),
                    if (!_loading) ...[
                      const SizedBox(height: kSpaceMD),
                      AudioFeaturePassRow(passRates: _featurePassRates),
                    ],
                    if (!_loading) ...[
                      const SizedBox(height: kSpaceMD),
                      PostureBreakdownCard(
                        breakdown: _stats?.postureBreakdown ?? {},
                        title: isToday
                            ? AppLocalizations.of(context).todayPostureToday
                            : AppLocalizations.of(context).todayPosture,
                      ),
                    ],
                    const SizedBox(height: kSpaceMD),
                  ],
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }
}

// ── 靜態標題列 ────────────────────────────────────────────────────

class _StaticHeader extends StatelessWidget {
  final String displayText;
  final bool isToday;

  const _StaticHeader({
    required this.displayText,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: kPrimaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceLG, kSpaceMD, kSpaceLG, kSpaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isToday
                    ? AppLocalizations.of(context).todayTitleToday
                    : AppLocalizations.of(context).todayTitleHistory,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayText,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 日期選擇列 ─────────────────────────────────────────────────────

class _DatePickerRow extends StatelessWidget {
  final DateTime date;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickDate;

  const _DatePickerRow({
    required this.date,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    return Container(
      color: context.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceXS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            color: kBrandPrimary,
            iconSize: 28,
            splashRadius: 20,
          ),
          GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceMD, vertical: kSpaceXS),
              decoration: BoxDecoration(
                color: context.bgInset,
                borderRadius: BorderRadius.circular(kRadiusSM),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 15, color: kBrandPrimary),
                  const SizedBox(width: kSpaceXS),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? kBrandPrimary : context.textHint,
            iconSize: 28,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

// ── 練習摘要橫幅 ─────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final int rounds;
  final int practices;
  final int good;
  final int bad;
  final bool loading;

  const _SummaryBanner({
    required this.rounds,
    required this.practices,
    required this.good,
    required this.bad,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: kCardDecoration(
          color: context.bgCard,
          radius: kRadiusLG,
          shadow: context.cardShadow),
      child: loading
          ? const _SkeletonRow()
          : Builder(builder: (ctx) {
              final l = AppLocalizations.of(ctx);
              return Row(
                children: [
                  Expanded(
                    child: _BannerStat(
                      label: l.homeRounds,
                      value: rounds.toString(),
                      icon: Icons.videocam_rounded,
                      color: kBrandPrimary,
                    ),
                  ),
                  _VertDivider(),
                  Expanded(
                    child: _BannerStat(
                      label: l.homePractices,
                      value: practices.toString(),
                      icon: Icons.sports_golf_rounded,
                      color: kBrandPrimary,
                    ),
                  ),
                  _VertDivider(),
                  Expanded(
                    child: _BannerStat(
                      label: l.homeGoodShot,
                      value: good.toString(),
                      icon: Icons.thumb_up_rounded,
                      color: kGoodColor,
                    ),
                  ),
                  _VertDivider(),
                  Expanded(
                    child: _BannerStat(
                      label: l.homeBadShot,
                      value: bad.toString(),
                      icon: Icons.thumb_down_rounded,
                      color: kBadColor,
                    ),
                  ),
                ],
              );
            }),
    );
  }
}

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _BannerStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: kSpaceSM),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: kSpaceXS),
        Text(label, style: TextStyle(fontSize: 12, color: context.textSecondary)),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 60, color: context.textHint.withValues(alpha: 0.4));
}

// ── 指標網格 ─────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final double? speed;
  final double? sweet;
  final bool loading;

  const _MetricGrid({
    required this.speed,
    required this.sweet,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = [
      _MetricItem(
        label: l.todayTopSpeed,
        value: speed != null ? speed!.toStringAsFixed(1) : '--',
        unit: speed != null ? 'MPH' : '',
        icon: Icons.speed_rounded,
        color: kSpeedColor,
        progress: speed != null ? (speed! / 120).clamp(0.0, 1.0) : null,
      ),
      _MetricItem(
        label: l.todaySweetSpotHit,
        value: sweet != null ? sweet!.clamp(0, 100).toStringAsFixed(0) : '--',
        unit: sweet != null ? '%' : '',
        icon: Icons.adjust_rounded,
        color: kSweetColor,
        progress: sweet != null ? (sweet! / 100).clamp(0.0, 1.0) : null,
      ),
    ];

    if (loading) {
      return Row(
        children: List.generate(2, (i) => [
          if (i > 0) const SizedBox(width: kSpaceSM),
          const Expanded(child: _SkeletonCard()),
        ]).expand((e) => e).toList(),
      );
    }
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: kSpaceSM),
          Expanded(child: _MetricCardWidget(item: items[i])),
        ],
      ],
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final double? progress;
  const _MetricItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.progress,
  });
}

class _MetricCardWidget extends StatelessWidget {
  final _MetricItem item;
  const _MetricCardWidget({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceMD),
      decoration: kCardDecoration(
          color: context.bgCard,
          radius: kRadiusMD,
          shadow: context.cardShadow),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: item.color, size: 15),
          ),
          const SizedBox(width: kSpaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.value + (item.unit.isNotEmpty ? item.unit : ''),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: item.value == '--' ? context.textHint : item.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.label,
                  style: TextStyle(fontSize: 10, color: context.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 骨架載入 ─────────────────────────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const _SkeletonBox({required this.width, required this.height, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.textHint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        3,
        (_) => const Column(
          children: [
            _SkeletonBox(width: 40, height: 40, radius: 20),
            SizedBox(height: kSpaceSM),
            _SkeletonBox(width: 30, height: 22),
            SizedBox(height: kSpaceXS),
            _SkeletonBox(width: 50, height: 12),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceMD),
      decoration: kCardDecoration(
          color: context.bgCard,
          radius: kRadiusMD,
          shadow: context.cardShadow),
      child: const Row(
        children: [
          _SkeletonBox(width: 28, height: 28, radius: 8),
          SizedBox(width: kSpaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _SkeletonBox(width: 50, height: 14),
                SizedBox(height: kSpaceXS),
                _SkeletonBox(width: 36, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

