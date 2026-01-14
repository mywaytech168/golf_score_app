import 'dart:math' as math;
import 'package:flutter/material.dart';

class TodayInfoPage extends StatelessWidget {
  final int practiceCount;
  final double? averageSpeedMph;
  final double? bestSpeedMph;
  final double? impactClarity;
  final double? sweetSpotPercentage;
  final int goodHits;
  final int badHits;
  final String? goodVideoPath;
  final String? badVideoPath;

  const TodayInfoPage({
    super.key,
    required this.practiceCount,
    this.averageSpeedMph,
    this.bestSpeedMph,
    this.impactClarity,
    this.sweetSpotPercentage,
    required this.goodHits,
    required this.badHits,
    this.goodVideoPath,
    this.badVideoPath,
  });

  @override
  Widget build(BuildContext context) {
    final sweetText = sweetSpotPercentage != null
        ? '${sweetSpotPercentage!.clamp(0, 100).toStringAsFixed(0)}%'
        : '--';
    final impactText = impactClarity != null
        ? '${(impactClarity!.clamp(0, 1) * 100).toStringAsFixed(0)}%'
        : '--';
    return Scaffold(
      appBar: AppBar(title: const Text('Today Info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(children: [
            _title('今日概況'),
            const SizedBox(height: 12),
            _miniStat('練習次數', '$practiceCount'),
            _miniStat('好球', '$goodHits'),
            _miniStat('壞球', '$badHits'),
            _miniStat('平均速度', averageSpeedMph != null ? '${averageSpeedMph!.toStringAsFixed(1)} mph' : '--'),
            _miniStat('最佳速度', bestSpeedMph != null ? '${bestSpeedMph!.toStringAsFixed(1)} mph' : '--'),
            _miniStat('甜蜜點命中', sweetText),
            _miniStat('擊球清脆度', impactText),
          ]),
          const SizedBox(height: 16),
          _card(children: [
            _title('好壞影片對照'),
            const SizedBox(height: 8),
            _videoSlot(context, label: '今日最佳', path: goodVideoPath, color: Colors.green),
            const SizedBox(height: 12),
            _videoSlot(context, label: '今日待改善', path: badVideoPath, color: Colors.red),
          ]),
        ],
      ),
    );
  }

  Widget _videoSlot(BuildContext context, {required String label, String? path, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.play_circle_fill, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(path ?? '尚未選擇影片', style: const TextStyle(fontSize: 14))),
          TextButton(
            onPressed: () {
              if (path == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('暫無影片')));
              } else {
                // TODO: 導向播放器或歷史列表
              }
            },
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );

  Widget _miniStat(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF7D8B9A), fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E8E5A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
