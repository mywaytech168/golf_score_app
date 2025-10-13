import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/recording_history_entry.dart';
import '../recorder_page.dart';
import '../services/recording_history_storage.dart';
import 'recording_history_page.dart';
import 'recording_session_page.dart';

/// 首頁提供完整儀表板，呈現揮桿統計、影片庫與分析摘要
class HomePage extends StatefulWidget {
  final String userEmail; // 使用者登入後的電子郵件
  final List<CameraDescription> cameras; // 傳入鏡頭資訊供後續錄影使用

  const HomePage({super.key, required this.userEmail, required this.cameras});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------- 狀態管理區 ----------
  int _currentIndex = 2; // 底部導覽預設聚焦在 Quick Start
  final List<RecordingHistoryEntry> _recordingHistory = []; // 首頁內部維護的錄影紀錄
  bool _isHistoryLoading = true; // 控制歷史載入狀態，避免 UI 閃爍
  int _practiceCount = 0; // 累積練習次數
  double? _averageSpeedMph; // 估算出的平均揮桿速度（MPH）
  double? _bestSpeedMph; // 歷史紀錄中的最佳揮桿速度
  double? _consistencyScore; // 揮桿穩定度（0-1）
  double? _impactClarity; // 擊球清脆度（0-1）
  double? _sweetSpotPercentage; // 甜蜜點命中率百分比
  bool _isMetricCalculating = false; // 是否正在重新計算儀表板數值

  @override
  void initState() {
    super.initState();
    _loadInitialHistory();
  }

  // ---------- 方法區 ----------
  /// 建立統計資訊卡片，方便重複使用與維持一致風格
  Widget _buildStatCard({
    required String title,
    required String value,
    required String subTitle,
    required Color highlightColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFF7D8B9A))),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: highlightColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(subTitle, style: const TextStyle(fontSize: 13, color: Color(0xFF1E1E1E))),
        ],
      ),
    );
  }

  /// 建立影片縮圖方塊，將最新錄影資訊轉換為設計稿風格
  Widget _buildVideoTile({
    required RecordingHistoryEntry entry,
    required Color baseColor,
  }) {
    // ---------- 字串組裝區 ----------
    final recordedAt = entry.recordedAt;
    final dateLabel = '${recordedAt.month.toString().padLeft(2, '0')}/${recordedAt.day.toString().padLeft(2, '0')}';
    final durationLabel = '時長 ${entry.durationSeconds} 秒';
    final modeLabel = entry.modeLabel;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SizedBox(
        width: 140,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _playHistoryEntry(entry),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [baseColor, baseColor.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [baseColor.withOpacity(0.95), baseColor.withOpacity(0.55)],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.center,
                          child: Icon(Icons.play_circle_fill, size: 46, color: Colors.white24),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dateLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            entry.displayTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$modeLabel｜$durationLabel',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFF1E8E5A)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 將儀表板數值轉換為雷達圖比例，便於統一控制上限
  List<double> _buildRadarValues() {
    final averageSpeedScore = _averageSpeedMph != null
        ? (_averageSpeedMph! / 120).clamp(0.0, 1.0)
        : 0.0;
    final bestSpeedScore = _bestSpeedMph != null
        ? (_bestSpeedMph! / 130).clamp(0.0, 1.0)
        : averageSpeedScore;
    final stabilityScore = (_consistencyScore ?? 0).clamp(0.0, 1.0);
    final clarityScore = (_impactClarity ??
            (_sweetSpotPercentage != null ? _sweetSpotPercentage! / 100 : 0))
        .clamp(0.0, 1.0);
    final volumeScore = (_practiceCount / 12).clamp(0.0, 1.0);

    return [averageSpeedScore, stabilityScore, clarityScore, bestSpeedScore, volumeScore];
  }

  /// 載入既有錄影歷史，確保重新開啟 App 仍可看到舊資料
  Future<void> _loadInitialHistory() async {
    final entries = await RecordingHistoryStorage.instance.loadHistory();
    if (!mounted) return;
    setState(() {
      _recordingHistory
        ..clear()
        ..addAll(entries);
      _isHistoryLoading = false;
      _practiceCount = entries.length;
    });
    unawaited(_refreshDashboardMetrics());
  }

  /// 處理底部導覽點擊，依據不同索引執行對應導覽
  void _onBottomNavTap(int index) {
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecorderPage(
            cameras: widget.cameras,
            initialHistory: _recordingHistory,
            onHistoryChanged: _handleHistoryUpdated,
          ),
        ),
      );
      return;
    }
    if (index == 3) {
      // 點選 Data Metrics 時直接導向錄影歷史頁，方便快速檢視過往紀錄
      _openRecordingHistoryPage();
      setState(() => _currentIndex = index);
      return;
    }
    setState(() => _currentIndex = index);
  }

  /// 接收錄影頁回傳的歷史紀錄，統一更新首頁資料來源
  void _handleHistoryUpdated(List<RecordingHistoryEntry> entries) {
    setState(() {
      _recordingHistory
        ..clear()
        ..addAll(entries);
      _isHistoryLoading = false;
      _practiceCount = entries.length;
      _isMetricCalculating = true;
    });
    // 將最新清單寫入本機，避免下次開啟 App 時資料遺失
    unawaited(RecordingHistoryStorage.instance.saveHistory(_recordingHistory));
    unawaited(_refreshDashboardMetrics());
  }

  /// 重新計算首頁儀表板指標，將 IMU CSV 中的線性加速度與旋轉資訊轉為練習洞察
  Future<void> _refreshDashboardMetrics() async {
    final snapshot = List<RecordingHistoryEntry>.from(_recordingHistory);
    if (snapshot.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isMetricCalculating = false;
        _averageSpeedMph = null;
        _bestSpeedMph = null;
        _consistencyScore = null;
        _impactClarity = null;
        _sweetSpotPercentage = null;
      });
      return;
    }

    setState(() {
      _isMetricCalculating = true;
    });

    try {
      final metrics = await _MetricsCalculator.compute(snapshot);
      if (!mounted) return;
      setState(() {
        _isMetricCalculating = false;
        _averageSpeedMph = metrics.averageSpeedMph;
        _bestSpeedMph = metrics.bestSpeedMph;
        _consistencyScore = metrics.consistencyScore;
        _impactClarity = metrics.averageImpactClarity;
        _sweetSpotPercentage = metrics.sweetSpotPercentage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isMetricCalculating = false;
        _averageSpeedMph = null;
        _bestSpeedMph = null;
        _consistencyScore = null;
        _impactClarity = null;
        _sweetSpotPercentage = null;
      });
    }
  }

  /// 開啟獨立的錄影歷史頁面，讓使用者專注瀏覽過往影片
  void _openRecordingHistoryPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordingHistoryPage(entries: _recordingHistory),
      ),
    );
  }

  /// 直接播放單筆歷史影片，並在檔案遺失時給予即時提示
  Future<void> _playHistoryEntry(RecordingHistoryEntry entry) async {
    final file = File(entry.filePath); // 建立檔案物件以檢查實際存在狀態
    if (!await file.exists()) {
      if (!mounted) return; // 若畫面已卸載則不再顯示訊息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('找不到影片檔案 ${entry.fileName}，請確認檔案是否仍保留於裝置中。')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoPlayerPage(videoPath: entry.filePath)),
    );
  }

  /// 建立首頁的錄影歷史快捷卡片，提供統計資訊與導覽按鈕
  Widget _buildHistoryShortcutCard() {
    if (_isHistoryLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
          ],
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在載入錄影歷史...', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );
    }

    final historyCount = _recordingHistory.length;
    final latestEntry = historyCount > 0 ? _recordingHistory.first : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF123B70),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.video_library_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '錄影歷史',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF123B70),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      historyCount > 0
                          ? '已累積 $historyCount 筆紀錄，最新一筆是第 ${latestEntry!.roundIndex} 輪。'
                          : '尚未有錄影紀錄，完成錄影後可於此快速檢視。',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6F7B86), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _openRecordingHistoryPage,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E5A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text(
              '檢視完整錄影列表',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ---------- 假資料區（調整為歷史資料產生卡片） ----------
    // 先以時間由新到舊排序，確保影片庫最左側即為最新成果
    final sortedHistory = List<RecordingHistoryEntry>.from(_recordingHistory)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    // 影片庫僅展示前六筆，避免水平列表超出視覺焦點
    final displayedHistory = sortedHistory.take(6).toList(growable: false);
    // 依序套用固定配色，讓卡片易於辨識錄影批次
    const palette = <Color>[
      Color(0xFF123B70),
      Color(0xFF0A5E5A),
      Color(0xFF4C2A9A),
      Color(0xFF1E8E5A),
      Color(0xFF2E8EFF),
      Color(0xFF8E4AF4),
    ];
    // ---------- Analytics 動態字串區 ----------
    final analyticsStatusLabel = _isMetricCalculating ? '分析中...' : '尚無資料';
    final analyticsAvgSpeedText = _averageSpeedMph != null
        ? '${_averageSpeedMph!.toStringAsFixed(1)} MPH'
        : analyticsStatusLabel;
    final analyticsBestSpeedText = _bestSpeedMph != null
        ? '${_bestSpeedMph!.toStringAsFixed(1)} MPH'
        : analyticsStatusLabel;
    final analyticsStabilityText = _consistencyScore != null
        ? '${(_consistencyScore!.clamp(0, 1) * 100).toStringAsFixed(0)} %'
        : analyticsStatusLabel;
    final analyticsSweetText = _sweetSpotPercentage != null
        ? '${_sweetSpotPercentage!.clamp(0, 100).toStringAsFixed(0)} %'
        : analyticsStatusLabel;
    final analyticsClarityText = _impactClarity != null
        ? '${(_impactClarity!.clamp(0, 1) * 100).toStringAsFixed(0)} %'
        : analyticsStatusLabel;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF5F7FB),
        toolbarHeight: 88,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF1E8E5A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.golf_course_rounded, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TekSwing',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0B2A2E),
                  ),
                ),
                Text(
                  widget.userEmail,
                  style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF6E7B87)),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF0B2A2E)),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // 始終維持同列呈現，窄螢幕改用橫向滑動避免卡片被擠壓
                final practiceSubtitle = _practiceCount > 0
                    ? '累積完成 $_practiceCount 次錄影'
                    : '完成錄影後即可累積練習次數';
                final speedValue = _isMetricCalculating
                    ? '分析中...'
                    : _averageSpeedMph != null
                        ? '${_averageSpeedMph!.toStringAsFixed(1)} MPH'
                        : '尚無資料';
                final speedSubtitle = _isMetricCalculating
                    ? '正在解析 IMU 感測紀錄'
                    : _averageSpeedMph != null
                        ? '依據含 IMU 的錄影推算揮桿速度'
                        : '連線 IMU 錄影後即可取得數據';
                final sweetValue = _isMetricCalculating
                    ? '分析中...'
                    : _sweetSpotPercentage != null
                        ? '${_sweetSpotPercentage!.clamp(0, 100).toStringAsFixed(0)} %'
                        : '尚無資料';
                final sweetSubtitle = _isMetricCalculating
                    ? '比對音訊與震動判斷清脆度'
                    : _sweetSpotPercentage != null
                        ? '最近錄影的擊球甜蜜點命中率'
                        : '有 IMU 與麥克風資料後顯示';

                final cards = <Widget>[
                  _buildStatCard(
                    title: '練習次數',
                    value: '$_practiceCount 次',
                    subTitle: practiceSubtitle,
                    highlightColor: const Color(0xFF1E8E5A),
                  ),
                  _buildStatCard(
                    title: '平均速度',
                    value: speedValue,
                    subTitle: speedSubtitle,
                    highlightColor: const Color(0xFF2E8EFF),
                  ),
                  _buildStatCard(
                    title: '甜蜜點命中',
                    value: sweetValue,
                    subTitle: sweetSubtitle,
                    highlightColor: const Color(0xFF8E4AF4),
                  ),
                ];

                if (constraints.maxWidth > 650) {
                  return Row(
                    children: [
                      for (var i = 0; i < cards.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i == cards.length - 1 ? 0 : 16),
                            child: cards[i],
                          ),
                        ),
                    ],
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < cards.length; i++)
                        Padding(
                          padding: EdgeInsets.only(right: i == cards.length - 1 ? 0 : 12),
                          child: SizedBox(
                            width: math.min(240, constraints.maxWidth - 40),
                            child: cards[i],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Video Library',
              actionLabel: 'See all',
              onTap: () => _onBottomNavTap(3),
            ),
            const SizedBox(height: 12),
            if (_isHistoryLoading)
              SizedBox(
                height: 190,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在整理影片庫...', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              )
            else if (displayedHistory.isEmpty)
              Container(
                height: 190,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                  ],
                ),
                child: const Text('尚未有錄影影片，完成錄影後會自動收錄最新紀錄。'),
              )
            else
              SizedBox(
                height: 190,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: displayedHistory.length,
                  itemBuilder: (context, index) {
                    final entry = displayedHistory[index];
                    final color = palette[index % palette.length];
                    return _buildVideoTile(entry: entry, baseColor: color);
                  },
                ),
              ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'Analytics', actionLabel: '詳情報告', onTap: () {}),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Avg Speed', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsAvgSpeedText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E8E5A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Best Speed', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsBestSpeedText,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E8E5A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Stability', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsStabilityText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E8EFF),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Sweet Spot', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsSweetText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8E4AF4),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Impact Clarity', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsClarityText,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDA4E5D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 140,
                        width: 140,
                        child: CustomPaint(
                          painter: _RadarChartPainter(values: _buildRadarValues()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'Comparison', actionLabel: '查看歷史', onTap: () {}),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Before', style: TextStyle(color: Color(0xFF7D8B9A))),
                            SizedBox(height: 6),
                            Text(
                              '86.3 MPH',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDA4E5D),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Feb 14  •  60%', style: TextStyle(color: Color(0xFF7D8B9A))),
                          ],
                        ),
                      ),
                      Container(
                        height: 80,
                        width: 1,
                        color: const Color(0xFFE4E8F0),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('After', style: TextStyle(color: Color(0xFF7D8B9A))),
                            SizedBox(height: 6),
                            Text(
                              '90.1 MPH',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E8E5A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Apr 8  •  82%', style: TextStyle(color: Color(0xFF7D8B9A))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _onBottomNavTap(2),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E5A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('立即開始錄影'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildHistoryShortcutCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 自訂底部導覽列，模擬設計稿中的五個項目並保留 Quick Start 強調樣式
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BottomNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: _currentIndex == 0,
            onTap: () => _onBottomNavTap(0),
          ),
          _BottomNavItem(
            icon: Icons.calendar_today_rounded,
            label: 'Today Info',
            isActive: _currentIndex == 1,
            onTap: () => _onBottomNavTap(1),
          ),
          _QuickStartNavItem(
            onTap: () => _onBottomNavTap(2),
          ),
          _BottomNavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Data Metrics',
            isActive: _currentIndex == 3,
            onTap: () => _onBottomNavTap(3),
          ),
          _BottomNavItem(
            icon: Icons.workspace_premium_rounded,
            label: 'Upgrade',
            isActive: _currentIndex == 4,
            onTap: () => _onBottomNavTap(4),
          ),
        ],
      ),
    );
  }
}

/// 儀表板指標計算工具：讀取 IMU CSV 並轉換為速度與甜蜜點統計
class _MetricsCalculator {
  static const double _impactThreshold = 12.0; // 判定擊球瞬間的加速度門檻
  static const double _sweetSpotThreshold = 0.18; // 認定為甜蜜點的命中比例

  /// 從歷史紀錄中解析出平均揮桿速度與甜蜜點命中率
  static Future<_MetricsResult> compute(List<RecordingHistoryEntry> entries) async {
    double aggregatedSpeed = 0; // 累加每次揮桿的預估速度
    double aggregatedConsistency = 0; // 累加穩定度比例
    double aggregatedImpact = 0; // 累加擊球清脆度
    int speedSamples = 0; // 統計擁有速度資訊的樣本數
    int sweetSpotHits = 0; // 紀錄甜蜜點命中的次數
    int analyzedSwings = 0; // 有成功解析的揮桿筆數
    double? bestSpeedMph; // 歷史最佳速度

    for (final entry in entries) {
      final csvPath = _selectCsvPath(entry);
      if (csvPath == null) {
        continue; // 沒有 IMU 檔案無法推算速度
      }

      final snapshot = await _analyzeCsv(csvPath);
      if (snapshot == null) {
        continue;
      }

      analyzedSwings++;
      if (snapshot.estimatedSpeedMph != null) {
        aggregatedSpeed += snapshot.estimatedSpeedMph!;
        speedSamples++;
        bestSpeedMph = bestSpeedMph == null
            ? snapshot.estimatedSpeedMph
            : math.max(bestSpeedMph!, snapshot.estimatedSpeedMph!);
      }
      aggregatedConsistency += snapshot.consistencyScore;
      aggregatedImpact += snapshot.impactClarity;
      if (snapshot.impactClarity >= _sweetSpotThreshold) {
        sweetSpotHits++;
      }
    }

    final averageSpeed = speedSamples > 0 ? aggregatedSpeed / speedSamples : null;
    final sweetSpotPercentage = analyzedSwings > 0 ? sweetSpotHits / analyzedSwings * 100 : null;
    final consistencyScore = analyzedSwings > 0
        ? math.min(math.max(aggregatedConsistency / analyzedSwings, 0.0), 1.0)
        : null;
    final averageImpact = analyzedSwings > 0
        ? math.min(math.max(aggregatedImpact / analyzedSwings, 0.0), 1.0)
        : null;

    return _MetricsResult(
      averageSpeedMph: averageSpeed,
      bestSpeedMph: bestSpeedMph,
      consistencyScore: consistencyScore,
      averageImpactClarity: averageImpact,
      sweetSpotPercentage: sweetSpotPercentage,
    );
  }

  /// 優先使用手腕裝置，其次胸前裝置，最後取第一個可用 CSV
  static String? _selectCsvPath(RecordingHistoryEntry entry) {
    if (entry.imuCsvPaths.isEmpty) {
      return null;
    }
    if (entry.imuCsvPaths['RIGHT_WRIST'] != null && entry.imuCsvPaths['RIGHT_WRIST']!.isNotEmpty) {
      return entry.imuCsvPaths['RIGHT_WRIST'];
    }
    if (entry.imuCsvPaths['CHEST'] != null && entry.imuCsvPaths['CHEST']!.isNotEmpty) {
      return entry.imuCsvPaths['CHEST'];
    }
    final fallback = entry.imuCsvPaths.values.firstWhere(
      (path) => path.isNotEmpty,
      orElse: () => '',
    );
    return fallback.isNotEmpty ? fallback : null;
  }

  /// 解析單支 CSV：同時估算平均加速度、峰值與擊球清脆度
  static Future<_SwingSnapshot?> _analyzeCsv(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final stream = file.openRead().transform(utf8.decoder).transform(const LineSplitter());
    double sumMagnitude = 0;
    double maxMagnitude = 0;
    int totalSamples = 0;
    int impactSamples = 0;

    await for (final rawLine in stream) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('CODI_') || line.startsWith('Device:') || line.startsWith('Quat')) {
        continue; // 跳過表頭與段落資訊
      }

      final parts = line.split(',');
      if (parts.length < 7) {
        continue; // 欄位不足時不納入計算
      }

      final ax = double.tryParse(parts[4]) ?? 0;
      final ay = double.tryParse(parts[5]) ?? 0;
      final az = double.tryParse(parts[6]) ?? 0;
      final magnitude = math.sqrt(ax * ax + ay * ay + az * az);
      if (!magnitude.isFinite) {
        continue;
      }

      sumMagnitude += magnitude;
      if (magnitude > maxMagnitude) {
        maxMagnitude = magnitude;
      }
      if (magnitude >= _impactThreshold) {
        impactSamples++;
      }
      totalSamples++;
    }

    if (totalSamples == 0) {
      return null;
    }

    final avgMagnitude = sumMagnitude / totalSamples;
    // 透過經驗係數估算揮桿速度：峰值代表爆發力、平均值代表穩定性
    final estimatedSpeedMps = (avgMagnitude * 0.45) + (maxMagnitude * 0.25);
    final estimatedSpeedMph = estimatedSpeedMps * 2.23694;
    final impactClarity = impactSamples / totalSamples;
    final consistency = maxMagnitude > 0 ? (avgMagnitude / maxMagnitude).clamp(0.0, 1.0) : 0.0;

    return _SwingSnapshot(
      estimatedSpeedMph: estimatedSpeedMph.isFinite ? estimatedSpeedMph : null,
      impactClarity: impactClarity.clamp(0.0, 1.0),
      consistencyScore: consistency,
    );
  }
}

/// 儀表板計算回傳的彙整結果
class _MetricsResult {
  final double? averageSpeedMph;
  final double? bestSpeedMph;
  final double? consistencyScore;
  final double? averageImpactClarity;
  final double? sweetSpotPercentage;

  const _MetricsResult({
    required this.averageSpeedMph,
    required this.bestSpeedMph,
    required this.consistencyScore,
    required this.averageImpactClarity,
    required this.sweetSpotPercentage,
  });
}

/// 解析單支 CSV 後的即時統計
class _SwingSnapshot {
  final double? estimatedSpeedMph; // 估算出的揮桿速度
  final double impactClarity; // 高加速度樣本占比，代表擊球清脆度
  final double consistencyScore; // 平均與峰值的比例，代表穩定度

  const _SwingSnapshot({
    required this.estimatedSpeedMph,
    required this.impactClarity,
    required this.consistencyScore,
  });
}

/// 雷達圖繪製器，呈現五個指標的相對表現
class _RadarChartPainter extends CustomPainter {
  final List<double> values; // 介於 0 到 1 的比例值

  const _RadarChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.85;
    final paint = Paint()
      ..color = const Color(0xFF2E8EFF).withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFF2E8EFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final angleStep = 2 * math.pi / values.length;
    for (var i = 0; i < values.length; i++) {
      final angle = -math.pi / 2 + angleStep * i;
      final pointRadius = radius * values[i].clamp(0.0, 1.0);
      final offset = Offset(
        center.dx + pointRadius * math.cos(angle),
        center.dy + pointRadius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFE4E8F0)
      ..style = PaintingStyle.stroke;

    // 繪製背景網格，提供視覺上的比例參考
    for (var layer = 1; layer <= 4; layer++) {
      final layerRadius = radius * layer / 4;
      final gridPath = Path();
      for (var i = 0; i < values.length; i++) {
        final angle = -math.pi / 2 + angleStep * i;
        final offset = Offset(
          center.dx + layerRadius * math.cos(angle),
          center.dy + layerRadius * math.sin(angle),
        );
        if (i == 0) {
          gridPath.moveTo(offset.dx, offset.dy);
        } else {
          gridPath.lineTo(offset.dx, offset.dy);
        }
      }
      gridPath.close();
      canvas.drawPath(gridPath, gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) => !listEquals(oldDelegate.values, values);
}

/// 一般底部導覽按鈕元件
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? const Color(0xFF1E8E5A) : const Color(0xFF7D8B9A)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF1E8E5A) : const Color(0xFF7D8B9A),
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 快速開始按鈕獨立元件，採用圓形浮起樣式凸顯互動焦點
class _QuickStartNavItem extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickStartNavItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 70,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF1E8E5A),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.flash_on_rounded, color: Colors.white),
            SizedBox(height: 4),
            Text(
              'Quick\nStart',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

/// 區塊標題元件，集中管理標題與右側操作按鈕
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onTap;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0B2A2E),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          child: Text(
            actionLabel,
            style: const TextStyle(color: Color(0xFF1E8E5A), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
