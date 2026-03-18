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
  final String? goodVideoPath;
  final String? badVideoPath;

  const TodayInfoSnapshot({
    required this.practiceCount,
    required this.goodHits,
    required this.badHits,
    this.bestSpeedMph,
    this.sweetSpotPercentage,
    this.audioCrispness,
    this.goodVideoPath,
    this.badVideoPath,
  });
}

typedef TodayInfoRangeFetcher = Future<TodayInfoSnapshot?> Function(DateTimeRange range);

class TodayInfoPage extends StatefulWidget {
  final int practiceCount;
  final double? bestSpeedMph;
  final double? sweetSpotPercentage;
  final double? audioCrispness;
  final int goodHits;
  final int badHits;
  final String? goodVideoPath;
  final String? badVideoPath;
  final void Function(DateTimeRange range)? onRangeSelected;
  final TodayInfoRangeFetcher? fetchRangeData;

  const TodayInfoPage({
    super.key,
    required this.practiceCount,
    this.bestSpeedMph,
    this.sweetSpotPercentage,
    this.audioCrispness,
    required this.goodHits,
    required this.badHits,
    this.goodVideoPath,
    this.badVideoPath,
    this.onRangeSelected,
    this.fetchRangeData,
  });

  @override
  State<TodayInfoPage> createState() => _TodayInfoPageState();
}

class _TodayInfoPageState extends State<TodayInfoPage> {
  DateTimeRange? _selectedRange;
  bool _loading = false;

  late int _practice;
  double? _bestSpeed;
  double? _sweetPct;
  double? _audioCrispness;
  int _good = 0;
  int _bad = 0;
  String? _goodVideo;
  String? _badVideo;
  
  // 統計API相關
  StatisticsResponse? _statistics;
  String _selectedPeriod = 'today'; // 當前選擇的時間維度

  @override
  void initState() {
    super.initState();
    _practice = widget.practiceCount;
    _bestSpeed = widget.bestSpeedMph;
    _sweetPct = widget.sweetSpotPercentage;
    _audioCrispness = widget.audioCrispness;
    _good = widget.goodHits;
    _bad = widget.badHits;
    _goodVideo = widget.goodVideoPath;
    _badVideo = widget.badVideoPath;
    
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
          _selectedPeriod = period;
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          ),
    );
    if (result != null) {
      setState(() => _selectedRange = result);
      if (widget.fetchRangeData != null) {
        setState(() => _loading = true);
        final snap = await widget.fetchRangeData!(result);
        if (mounted && snap != null) {
          setState(() {
            _practice = snap.practiceCount;
            _good = snap.goodHits;
            _bad = snap.badHits;
            _bestSpeed = snap.bestSpeedMph;
            _sweetPct = snap.sweetSpotPercentage;
            _audioCrispness = snap.audioCrispness;
            _goodVideo = snap.goodVideoPath;
            _badVideo = snap.badVideoPath;
            _loading = false;
          });
        } else if (mounted) {
          setState(() => _loading = false);
        }
      }
      widget.onRangeSelected?.call(result);
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
    final rangeLabel = _selectedRange != null
        ? '${_selectedRange!.start.toString().split(' ').first} - ${_selectedRange!.end.toString().split(' ').first}'
        : '選擇日期範圍';
    return Scaffold(
      appBar: AppBar(title: const Text('Today Info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 時間維度選擇器
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPeriodButton('全部', 'all'),
                _buildPeriodButton('昨天', 'yesterday'),
                _buildPeriodButton('今天', 'today'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(rangeLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          _card(children: [
            _title('好壞影片對照'),
            const SizedBox(height: 8),
            _videoSlot(context, label: '今日最佳', path: _goodVideo, color: Colors.green),
            const SizedBox(height: 12),
            _videoSlot(context, label: '今日待改善', path: _badVideo, color: Colors.red),
          ]),
        ],
      ),
    );
  }

  /// 時間維度按鈕
  Widget _buildPeriodButton(String label, String period) {
    final isSelected = _selectedPeriod == period;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        onSelected: (selected) {
          if (selected) {
            _loadStatistics(period);
          }
        },
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
