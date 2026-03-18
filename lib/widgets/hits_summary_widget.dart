import 'package:flutter/material.dart';
import '../models/hits_summary.dart';

/// 显示摆球摘要列表的 Widget
/// 提供了卡片视图，展示每个摆球的关键信息
class HitsSummaryWidget extends StatelessWidget {
  /// 摆球摘要列表
  final List<HitsSummary> hitsSummary;

  /// 是否显示详细信息
  final bool showDetails;

  /// 点击摆球时的回调
  final Function(HitsSummary)? onHitTap;

  const HitsSummaryWidget({
    super.key,
    required this.hitsSummary,
    this.showDetails = true,
    this.onHitTap,
  });

  @override
  Widget build(BuildContext context) {
    if (hitsSummary.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            '还没有检测到摆球',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: hitsSummary.length,
      itemBuilder: (context, index) {
        final hit = hitsSummary[index];
        return _HitCard(
          hit: hit,
          index: index + 1,
          showDetails: showDetails,
          onTap: onHitTap,
        );
      },
    );
  }
}

/// 单个摆球的卡片视图
class _HitCard extends StatelessWidget {
  final HitsSummary hit;
  final int index;
  final bool showDetails;
  final Function(HitsSummary)? onTap;

  const _HitCard({
    required this.hit,
    required this.index,
    required this.showDetails,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap != null ? () => onTap!(hit) : null,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行：摆球编号和时间
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '摆球 #$index',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Chip(
                    label: Text(hit.formattedHitTime),
                    backgroundColor: Colors.blue.shade100,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 详细信息行
              if (showDetails) ...[
                Row(
                  children: [
                    Expanded(
                      child: _DetailRow(
                        label: '峰值',
                        value: '${hit.peakSmooth.toStringAsFixed(2)} G',
                        icon: Icons.trending_up,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DetailRow(
                        label: '时长',
                        value: '${hit.duration.toStringAsFixed(2)} s',
                        icon: Icons.timer,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DetailRow(
                        label: '开始',
                        value: _formatTime(hit.startT),
                        icon: Icons.skip_previous,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DetailRow(
                        label: '结束',
                        value: _formatTime(hit.endT),
                        icon: Icons.skip_next,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
                if (hit.detectFrom != null && hit.detectFrom!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '检测源: ${hit.detectFrom}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(double seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${secs.toStringAsFixed(1).padLeft(4, '0')}';
  }
}

/// 详细信息行组件
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.grey.shade600,
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 用于在历史页面中显示摆球摘要的折叠面板
class HitsSummaryExpansionTile extends StatelessWidget {
  /// 摆球摘要列表
  final List<HitsSummary> hitsSummary;

  /// 标题
  final String title;

  /// 点击摆球时的回调
  final Function(HitsSummary)? onHitTap;

  /// 初始展开状态
  final bool initiallyExpanded;

  const HitsSummaryExpansionTile({
    super.key,
    required this.hitsSummary,
    this.title = '摆球摘要',
    this.onHitTap,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      subtitle: Text(
        '共 ${hitsSummary.length} 个摆球',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      initiallyExpanded: initiallyExpanded,
      children: [
        HitsSummaryWidget(
          hitsSummary: hitsSummary,
          showDetails: true,
          onHitTap: onHitTap,
        ),
      ],
    );
  }
}
