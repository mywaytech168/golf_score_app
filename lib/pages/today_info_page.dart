import 'package:flutter/material.dart';
import '../models/statistics_response.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';

class TodayInfoPage extends StatefulWidget {
  const TodayInfoPage({super.key});

  @override
  State<TodayInfoPage> createState() => _TodayInfoPageState();
}

class _TodayInfoPageState extends State<TodayInfoPage> {
  bool _loading = true;
  StatisticsResponse? _stats;
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

  String _formatDisplay(DateTime d) {
    final weekdays = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
    final wd = weekdays[d.weekday - 1];
    final ds = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    return '$wd  $ds';
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final isToday = _isToday(_selectedDate);
      final stats = await VideoServerClient.instance.getStatistics(
        period: isToday ? 'today' : 'day',
        date: isToday ? null : _formatApi(_selectedDate),
      );
      if (mounted) setState(() { _stats = stats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _stats = null; _loading = false; });
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
          colorScheme: const ColorScheme.light(
            primary: kPrimaryGreen,
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
  int get _practice => _stats?.totalCount ?? 0;
  int get _good => _stats?.goodShot ?? 0;
  int get _bad => _stats?.badShot ?? 0;
  double? get _speed => (_stats?.peakValue.maximum ?? 0) > 0 ? _stats!.peakValue.maximum : null;
  double? get _sweet => (_stats?.sweetSpotPercentage ?? 0) > 0 ? _stats!.sweetSpotPercentage : null;
  double? get _crisp => (_stats?.audioCrispness.average ?? 0) > 0 ? _stats!.audioCrispness.average : null;

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(_selectedDate);
    final canGoNext = !isToday;

    return Scaffold(
      backgroundColor: kBgPage,
      body: Column(
        children: [
          // ── 靜態 Header ─────────────────────────────────────
          _StaticHeader(
            displayText: _formatDisplay(_selectedDate),
            isToday: isToday,
            loading: _loading,
            onRefresh: _loadStats,
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadStats,
              color: kPrimaryGreen,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(kSpaceMD),
                child: Column(
                  children: [
                    _SummaryBanner(
                      practice: _practice,
                      good: _good,
                      bad: _bad,
                      loading: _loading,
                    ),
                    const SizedBox(height: kSpaceMD),
                    _MetricGrid(
                      speed: _speed,
                      sweet: _sweet,
                      crisp: _crisp,
                      loading: _loading,
                    ),
                    const SizedBox(height: kSpaceMD),
                    if (!_loading && _practice > 0)
                      _GoodShotRateCard(good: _good, bad: _bad),
                    if (!_loading && _practice == 0)
                      _EmptyState(isToday: isToday),
                    const SizedBox(height: kSpaceXL),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 靜態標題列 ────────────────────────────────────────────────────

class _StaticHeader extends StatelessWidget {
  final String displayText;
  final bool isToday;
  final bool loading;
  final VoidCallback onRefresh;

  const _StaticHeader({
    required this.displayText,
    required this.isToday,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kPrimaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceLG, kSpaceMD, kSpaceSM, kSpaceMD),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday ? '今日概況' : '歷史概況',
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
              const Spacer(),
              IconButton(
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: '重新整理',
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
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceXS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            color: kPrimaryGreen,
            iconSize: 28,
            splashRadius: 20,
          ),
          GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceMD, vertical: kSpaceXS),
              decoration: BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.circular(kRadiusSM),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 15, color: kPrimaryGreen),
                  const SizedBox(width: kSpaceXS),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? kPrimaryGreen : kTextHint,
            iconSize: 28,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

// ── 空狀態 ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isToday;
  const _EmptyState({required this.isToday});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpaceXL),
      child: Column(
        children: [
          Icon(
            isToday ? Icons.sports_golf_rounded : Icons.event_busy_rounded,
            size: 56,
            color: kTextHint,
          ),
          const SizedBox(height: kSpaceMD),
          Text(
            isToday ? '今天還沒有練習記錄' : '這天沒有練習記錄',
            style: const TextStyle(fontSize: 15, color: kTextSecondary),
          ),
          if (isToday) ...[
            const SizedBox(height: kSpaceXS),
            const Text(
              '去錄一支揮桿吧！',
              style: TextStyle(fontSize: 13, color: kTextHint),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 練習摘要橫幅 ─────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final int practice;
  final int good;
  final int bad;
  final bool loading;

  const _SummaryBanner({
    required this.practice,
    required this.good,
    required this.bad,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: kCardDecoration(radius: kRadiusLG),
      child: loading
          ? const _SkeletonRow()
          : Row(
              children: [
                Expanded(
                  child: _BannerStat(
                    label: '練習次數',
                    value: practice.toString(),
                    icon: Icons.sports_golf_rounded,
                    color: kPrimaryGreen,
                  ),
                ),
                _VertDivider(),
                Expanded(
                  child: _BannerStat(
                    label: '好球',
                    value: good.toString(),
                    icon: Icons.thumb_up_rounded,
                    color: kGoodColor,
                  ),
                ),
                _VertDivider(),
                Expanded(
                  child: _BannerStat(
                    label: '壞球',
                    value: bad.toString(),
                    icon: Icons.thumb_down_rounded,
                    color: kBadColor,
                  ),
                ),
              ],
            ),
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
        Text(label, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 60, color: kTextHint.withValues(alpha: 0.4));
}

// ── 指標網格 ─────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final double? speed;
  final double? sweet;
  final double? crisp;
  final bool loading;

  const _MetricGrid({
    required this.speed,
    required this.sweet,
    required this.crisp,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricItem(
        label: '最佳速度',
        value: speed != null ? speed!.toStringAsFixed(1) : '--',
        unit: speed != null ? 'MPH' : '',
        icon: Icons.speed_rounded,
        color: kSpeedColor,
        progress: speed != null ? (speed! / 120).clamp(0.0, 1.0) : null,
      ),
      _MetricItem(
        label: '甜蜜點命中',
        value: sweet != null ? sweet!.clamp(0, 100).toStringAsFixed(0) : '--',
        unit: sweet != null ? '%' : '',
        icon: Icons.adjust_rounded,
        color: kSweetColor,
        progress: sweet != null ? (sweet! / 100).clamp(0.0, 1.0) : null,
      ),
      _MetricItem(
        label: '聲音清脆度',
        value: crisp != null ? crisp!.clamp(0, 100).toStringAsFixed(0) : '--',
        unit: crisp != null ? '/100' : '',
        icon: Icons.graphic_eq_rounded,
        color: kCrispColor,
        progress: crisp != null ? (crisp! / 100).clamp(0.0, 1.0) : null,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: kSpaceSM,
        mainAxisSpacing: kSpaceSM,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          loading ? const _SkeletonCard() : _MetricCardWidget(item: items[i]),
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
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: kCardDecoration(radius: kRadiusMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(kSpaceSM),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: item.value == '--' ? kTextHint : item.color,
                    ),
                  ),
                  if (item.unit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 2),
                      child: Text(
                        item.unit,
                        style: const TextStyle(fontSize: 11, color: kTextSecondary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: kSpaceXS),
              Text(
                item.label,
                style: const TextStyle(fontSize: 11, color: kTextSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.progress != null) ...[
                const SizedBox(height: kSpaceSM),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    backgroundColor: item.color.withValues(alpha: 0.12),
                    color: item.color,
                    minHeight: 3,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── 好球率卡片 ───────────────────────────────────────────────────

class _GoodShotRateCard extends StatelessWidget {
  final int good;
  final int bad;
  const _GoodShotRateCard({required this.good, required this.bad});

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
              const Icon(Icons.bar_chart_rounded, color: kPrimaryGreen, size: 18),
              const SizedBox(width: kSpaceSM),
              const Text(
                '好球率',
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
                  fontSize: 18,
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
              _LegendDot(color: kGoodColor, label: '好球 $good 次'),
              _LegendDot(color: kBadColor, label: '壞球 $bad 次'),
            ],
          ),
        ],
      ),
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: kSpaceXS),
        Text(label, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
      ],
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
        color: kTextHint.withValues(alpha: 0.3),
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
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: kCardDecoration(radius: kRadiusMD),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SkeletonBox(width: 36, height: 36, radius: kSpaceSM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBox(width: 40, height: 20),
              SizedBox(height: kSpaceXS),
              _SkeletonBox(width: 60, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}
