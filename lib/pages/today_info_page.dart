import 'package:flutter/material.dart';
import '../models/statistics_response.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';

class TodayInfoPage extends StatefulWidget {
  final int practiceCount;
  final double? bestSpeedMph;
  final double? sweetSpotPercentage;
  final double? audioCrispness;
  final int goodHits;
  final int badHits;

  const TodayInfoPage({
    super.key,
    required this.practiceCount,
    this.bestSpeedMph,
    this.sweetSpotPercentage,
    this.audioCrispness,
    required this.goodHits,
    required this.badHits,
  });

  @override
  State<TodayInfoPage> createState() => _TodayInfoPageState();
}

class _TodayInfoPageState extends State<TodayInfoPage> {
  bool _loading = true;
  StatisticsResponse? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await VideoServerClient.instance.getStatistics(period: 'today');
      if (mounted) setState(() { _stats = stats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 資料取值（API 優先，否則 fallback widget props）
  int get _practice => _stats?.totalCount ?? widget.practiceCount;
  int get _good => _stats?.goodShot ?? widget.goodHits;
  int get _bad => _stats?.badShot ?? widget.badHits;
  double? get _speed => _stats?.peakValue.maximum != null && _stats!.peakValue.maximum > 0
      ? _stats!.peakValue.maximum
      : widget.bestSpeedMph;
  double? get _sweet => _stats?.sweetSpotPercentage != null && _stats!.sweetSpotPercentage > 0
      ? _stats!.sweetSpotPercentage
      : widget.sweetSpotPercentage;
  double? get _crisp => _stats?.audioCrispness.average != null && _stats!.audioCrispness.average > 0
      ? _stats!.audioCrispness.average
      : widget.audioCrispness;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final weekdays = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
    final weekday = weekdays[now.weekday - 1];

    return Scaffold(
      backgroundColor: kBgPage,
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: kPrimaryGreen,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── AppBar ───────────────────────────────────────
            SliverAppBar(
              expandedHeight: 130,
              pinned: true,
              stretch: true,
              backgroundColor: kPrimaryGreen,
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground],
                background: Container(
                  decoration: const BoxDecoration(gradient: kPrimaryGradient),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(kSpaceLG, 0, kSpaceLG, kSpaceMD),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('今日概況',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  )),
                          const SizedBox(height: kSpaceXS),
                          Text('$weekday  $dateStr',
                              style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                title: const Text('今日概況',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                titlePadding: const EdgeInsets.only(left: kSpaceLG, bottom: kSpaceMD),
              ),
              actions: [
                IconButton(
                  onPressed: _loading ? null : _loadStats,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh_rounded, color: Colors.white),
                  tooltip: '重新整理',
                ),
                const SizedBox(width: kSpaceSM),
              ],
            ),

            // ── 主要內容 ─────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(kSpaceMD),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 練習摘要橫幅
                  _SummaryBanner(
                    practice: _practice,
                    good: _good,
                    bad: _bad,
                    loading: _loading,
                  ),
                  const SizedBox(height: kSpaceMD),

                  // 指標卡片網格
                  _MetricGrid(
                    speed: _speed,
                    sweet: _sweet,
                    crisp: _crisp,
                    loading: _loading,
                  ),
                  const SizedBox(height: kSpaceMD),

                  // 好球率卡片
                  if (!_loading && _practice > 0)
                    _GoodShotRateCard(good: _good, bad: _bad),

                  const SizedBox(height: kSpaceXL),
                ]),
              ),
            ),
          ],
        ),
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
                Expanded(child: _BannerStat(label: '練習次數', value: '$practice', icon: Icons.sports_golf_rounded, color: kPrimaryGreen)),
                _Divider(),
                Expanded(child: _BannerStat(label: '好球', value: '$good', icon: Icons.thumb_up_rounded, color: kGoodColor)),
                _Divider(),
                Expanded(child: _BannerStat(label: '壞球', value: '$bad', icon: Icons.thumb_down_rounded, color: kBadColor)),
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
  const _BannerStat({required this.label, required this.value, required this.icon, required this.color});

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
        Text(value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            )),
        const SizedBox(height: kSpaceXS),
        Text(label,
            style: const TextStyle(fontSize: 12, color: kTextSecondary)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 60, color: kTextHint.withValues(alpha: 0.5));
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
        progress: speed != null ? (speed! / 120).clamp(0, 1) : null,
      ),
      _MetricItem(
        label: '甜蜜點命中',
        value: sweet != null ? sweet!.clamp(0, 100).toStringAsFixed(0) : '--',
        unit: sweet != null ? '%' : '',
        icon: Icons.adjust_rounded,
        color: kSweetColor,
        progress: sweet != null ? (sweet! / 100).clamp(0, 1) : null,
      ),
      _MetricItem(
        label: '聲音清脆度',
        value: crisp != null ? crisp!.clamp(0, 100).toStringAsFixed(0) : '--',
        unit: crisp != null ? '/100' : '',
        icon: Icons.graphic_eq_rounded,
        color: kCrispColor,
        progress: crisp != null ? (crisp! / 100).clamp(0, 1) : null,
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
      itemBuilder: (_, i) => loading ? const _SkeletonCard() : _MetricCardWidget(item: items[i]),
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
                  Text(item.value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: item.value == '--' ? kTextHint : item.color,
                      )),
                  if (item.unit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 2),
                      child: Text(item.unit,
                          style: const TextStyle(fontSize: 11, color: kTextSecondary)),
                    ),
                ],
              ),
              const SizedBox(height: kSpaceXS),
              Text(item.label,
                  style: const TextStyle(fontSize: 11, color: kTextSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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
              const Text('好球率',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: kTextPrimary,
                  )),
              const Spacer(),
              Text('$pct%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: kPrimaryGreen,
                  )),
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
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: kSpaceXS),
        Text(label, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
      ],
    );
  }
}

// ── 骨架載入元件 ─────────────────────────────────────────────────

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
      children: List.generate(3, (_) => Column(
        children: [
          const _SkeletonBox(width: 40, height: 40, radius: 20),
          const SizedBox(height: kSpaceSM),
          const _SkeletonBox(width: 30, height: 22),
          const SizedBox(height: kSpaceXS),
          const _SkeletonBox(width: 50, height: 12),
        ],
      )),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _SkeletonBox(width: 36, height: 36, radius: kSpaceSM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
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
