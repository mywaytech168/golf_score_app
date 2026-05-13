import 'package:flutter/material.dart';
import '../services/video_server_client.dart';
import '../models/statistics_response.dart';

class TodayInfoSnapshot {
  final int practiceCount;
  final int goodHits;
  final int badHits;
  final double? bestSpeedMph;
  final double? sweetSpotPercentage;
  final double? audioCrispness;

  const TodayInfoSnapshot({
    required this.practiceCount,
    required this.goodHits,
    required this.badHits,
    this.bestSpeedMph,
    this.sweetSpotPercentage,
    this.audioCrispness,
  });
}

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
  bool _loading = false;

  late int _practice;
  double? _bestSpeed;
  double? _sweetPct;
  double? _audioCrispness;
  int _good = 0;
  int _bad = 0;
  
  // 統計API相關
  StatisticsResponse? _statistics;

  @override
  void initState() {
    super.initState();
    _practice = widget.practiceCount;
    _bestSpeed = widget.bestSpeedMph;
    _sweetPct = widget.sweetSpotPercentage;
    _audioCrispness = widget.audioCrispness;
    _good = widget.goodHits;
    _bad = widget.badHits;
    
    // 初始化時載入今天的統計數據
    _loadStatistics('today');
  }
  
  /// 載入統計數據
  Future<void> _loadStatistics(String period, {String? date}) async {
    setState(() => _loading = true);
    
    try {
      final stats = await VideoServerClient.instance.getStatistics(
        period: period,
        date: date,
      );
      
      if (mounted && stats != null) {
        setState(() {
          _statistics = stats;
          // 從API數據更新本地變量
          _practice = stats.totalCount;
          _good = stats.goodShot;
          _bad = stats.badShot;
          _sweetPct = stats.sweetSpotPercentage;
          _bestSpeed = stats.peakValue.average > 0 ? stats.peakValue.average : null;
          _audioCrispness = stats.audioCrispness.average > 0 ? stats.audioCrispness.average : null;
        });
      }
    } catch (e) {
      debugPrint('❌ 載入統計數據失敗: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final sweetText = _sweetPct != null
        ? '${_sweetPct!.clamp(0, 100).toStringAsFixed(0)}%'
        : '--';
    final crispnessText = _audioCrispness != null
        ? '${_audioCrispness!.clamp(0, 100).toStringAsFixed(0)}'
        : '--';
    return Scaffold(
      appBar: AppBar(title: const Text('Today Info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(children: [
            _title('統計概況'),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            _miniStat('練習次數', '$_practice'),
            _miniStat('好球', '$_good'),
            _miniStat('壞球', '$_bad'),
            _miniStat('最佳速度', _bestSpeed != null ? '${_bestSpeed!.toStringAsFixed(1)} mph' : '--'),
            _miniStat('甜蜜點命中', sweetText),
            _miniStat('聲音清脆度', crispnessText),
          ]),
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
