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

/// 首頁提供完整儀表板，呈現揮桿統計、影片庫與分析摘要
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<RecordingHistoryEntry> _recordingHistory = [];
  late final StatisticsService _statisticsService = StatisticsService();
  late final PurchaseService _purchaseService = PurchaseService();

  @override
  void initState() {
    super.initState();
    _loadInitialHistory();
    _initializeStatistics();
    _initializePurchaseService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
  }

  /// 初始化購買服務
  Future<void> _initializePurchaseService() async {
    try {
      await _purchaseService.initialize();
      debugPrint('✅ [購買服務] 已初始化');
    } catch (e) {
      debugPrint('❌ [購買服務] 初始化失敗: $e');
    }
  }

  @override
  void dispose() {
    // 清理統計服務
    _statisticsService.dispose();
    super.dispose();
  }

  /// 初始化統計服務，同時加載後端 API 和本地計算的指標
  /// 如果返回 401，跳轉到登入頁面
  Future<void> _initializeStatistics() async {
    try {
      await _statisticsService.loadAllStatistics();
    } on UnauthorizedException {
      // Token 無效或過期，跳回登入頁
      if (mounted) {
        debugPrint('🔐 統計數據未授權，跳轉到登入頁');
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('⚠️ 初始化統計服務失敗: $e');
    }
    // 本地指標會在 _refreshDashboardMetrics 中計算並更新
  }

  Widget _buildTodayInfoCard() {
    // 使用今天的後端數據
    final todayStats = _statisticsService.todayStatistics;
    final practice = todayStats?.totalCount ?? 0;
    final goodHits = todayStats?.goodShot ?? 0;
    final badHits = todayStats?.badShot ?? 0;
    final sweetPct = todayStats?.sweetSpotPercentage ?? 0;
    final sweetText = sweetPct > 0 ? '${sweetPct.toStringAsFixed(0)}%' : '--';
    final crispnessText = todayStats != null && todayStats.audioCrispness.average > 0
        ? todayStats.audioCrispness.average.toStringAsFixed(0)
        : '--';
    final bestSpeedDisplay = todayStats != null && todayStats.peakValue.maximum > 0
        ? '${todayStats.peakValue.maximum.toStringAsFixed(1)} MPH'
        : '--';

    return Container(
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
          _SectionHeader(title: 'Today Info', actions: const []),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _miniStat(title: '好球', value: goodHits.toString())),
              Expanded(child: _miniStat(title: '壞球', value: badHits.toString())),
              Expanded(child: _miniStat(title: '練習次數', value: practice.toString())),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _miniStat(title: '最佳速度', value: bestSpeedDisplay)),
              Expanded(child: _miniStat(title: '甜蜜點命中', value: sweetText)),
              Expanded(child: _miniStat(title: '聲音清脆度', value: crispnessText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({required String title, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryGreen),
        ),
      ],
    );
  }

  // ---------- 方法區 ----------
  /// 建立統計資訊卡片，方便重複使用與維持一致風格
  /// 構建指標卡片網格
  Widget _buildMetricsGrid(bool isLoadingStats, StatisticsResponse? backendStats) {
    // 使用今天的後端統計數據
    final todayStats = _statisticsService.todayStatistics;
    final goodShotCount = todayStats?.goodShot ?? 0;
    final badShotCount = todayStats?.badShot ?? 0;
    
    // 準備所有指標數據
    final metricsCards = <Map<String, dynamic>>[
      {
        'title': '最佳速度',
        'value': isLoadingStats
            ? '載入中...'
            : todayStats != null && todayStats.peakValue.maximum > 0
                ? '${todayStats.peakValue.maximum.toStringAsFixed(1)} MPH'
                : '尚無資料',
        'color': kSpeedColor,
        'highlight': true,
      },
      {
        'title': '甜蜜點命中',
        'value': isLoadingStats
            ? '載入中...'
            : todayStats != null
                ? '${todayStats.sweetSpotPercentage.toStringAsFixed(0)} %'
                : '尚無資料',
        'color': kSweetColor,
        'highlight': false,
      },
      {
        'title': '好球',
        'value': '$goodShotCount 次',
        'color': kGoodColor,
        'highlight': false,
      },
      {
        'title': '壞球',
        'value': '$badShotCount 次',
        'color': kBadColor,
        'highlight': false,
      },
      {
        'title': '聲音清脆度',
        'value': isLoadingStats
            ? '載入中...'
            : todayStats != null && todayStats.audioCrispness.average > 0
                ? todayStats.audioCrispness.average.toStringAsFixed(0)
                : '尚無資料',
        'color': kBadColor,
        'highlight': false,
      },
      {
        'title': '練習次數',
        'value': '${todayStats?.totalCount ?? 0} 次',
        'color': kGoodColor,
        'highlight': false,
      },
    ];

    // 2×3 Grid 佈局
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        metricsCards.length,
        (index) {
          final card = metricsCards[index];
          return _buildMetricCard(card);
        },
      ),
    );
  }

  /// 構建單個指標卡片 widget
  Widget _buildMetricCard(Map<String, dynamic> card) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
        border: card['highlight'] as bool
            ? Border(
                top: BorderSide(
                  color: card['color'] as Color,
                  width: 3,
                ),
              )
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card['title'] as String,
            style: const TextStyle(
              fontSize: 13,
              color: kTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            card['value'] as String,
            style: TextStyle(
              fontSize: (card['highlight'] as bool) ? 24 : 22,
              fontWeight: FontWeight.bold,
              color: card['color'] as Color,
            ),
          ),
        ],
      ),
    );
  }

  /// 登出用戶
  Future<void> _logout() async {
    // 顯示確認對話框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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
        );
      },
    );

    if (confirmed != true) return;

    // 清除令牌
    await AuthTokenStorage.instance.clearTokens();

    // 清除本地存儲的用戶信息
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');

    if (!mounted) return;

    // 返回登錄頁面
    Navigator.of(context).pushReplacementNamed('/login');
  }

  /// 載入既有錄影歷史，確保重新開啟 App 仍可看到舊資料
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

    unawaited(_refreshDashboardMetrics());
  }

  /// 檢查縮圖檔案是否存在，若遺失則將欄位清空避免顯示破圖
  Future<List<RecordingHistoryEntry>?> _cleanInvalidThumbnails(
    List<RecordingHistoryEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return null; // 無資料時直接返回
    }

    final updated = <RecordingHistoryEntry>[];
    var hasChanges = false;

    for (final entry in entries) {
      var thumbnailPath = entry.thumbnailPath;
      final needsGenerate = thumbnailPath == null ||
          thumbnailPath.isEmpty ||
          !(await File(thumbnailPath).exists());

      if (needsGenerate) {
        // ---------- 縮圖清理說明 ----------
        // 舊版紀錄可能沒有縮圖檔案，或檔案被手動刪除。此時直接清空欄位
        // 讓 UI 顯示預設樣式，避免再度啟動會造成緩衝區警告的擷取流程。
        thumbnailPath = null;
      }

      if (thumbnailPath != entry.thumbnailPath) {
        hasChanges = true;
      }

      updated.add(entry.copyWith(thumbnailPath: thumbnailPath));
    }

    return hasChanges ? updated : null;
  }


  Future<void> _refreshDashboardMetrics() async {
    final snapshot = List<RecordingHistoryEntry>.from(_recordingHistory);
    if (snapshot.isEmpty) {
      _statisticsService.setLocalMetrics(
        consistencyScore: null,
        bestSpeedMph: null,
        sweetSpotPercentage: null,
        audioCrispness: null,
        comparisonBefore: null,
        comparisonAfter: null,
      );
      return;
    }

    try {
      final metrics = await _MetricsCalculator.compute(snapshot);
      if (!mounted) return;

      double? latestAudioCrispness;
      for (final entry in snapshot.reversed) {
        if (entry.audioCrispness != null) {
          latestAudioCrispness = (entry.audioCrispness as num).toDouble();
          break;
        }
      }

      _statisticsService.setLocalMetrics(
        consistencyScore: null,
        bestSpeedMph: metrics.bestSpeedMph,
        sweetSpotPercentage: metrics.sweetSpotPercentage,
        audioCrispness: latestAudioCrispness,
        comparisonBefore: null,
        comparisonAfter: null,
      );
    } catch (_) {
      _statisticsService.setLocalMetrics(
        consistencyScore: null,
        bestSpeedMph: null,
        sweetSpotPercentage: null,
        audioCrispness: null,
        comparisonBefore: null,
        comparisonAfter: null,
      );
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBgPage,
        toolbarHeight: 72,
        automaticallyImplyLeading: false,
        title: Consumer<UserProvider>(
          builder: (context, user, _) => Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kPrimaryGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: user.avatarPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(File(user.avatarPath!), fit: BoxFit.cover),
                      )
                    : const Icon(Icons.golf_course_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('嗨，${user.displayName} 👋',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary)),
                  Text('今天也來練習吧！',
                      style: TextStyle(
                          fontSize: 12, color: kTextSecondary)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: kTextPrimary),
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
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
      ),
      body: StreamBuilder<StatisticsResponse?>(
        stream: _statisticsService.watchStatistics(),
        initialData: _statisticsService.statistics,
        builder: (context, statsSnapshot) {
          return StreamBuilder<LoadingState>(
            stream: _statisticsService.watchLoadingState(),
            initialData: _statisticsService.loadingState,
            builder: (context, loadingSnapshot) {
              final backendStats = statsSnapshot.data;
              final loadingState = loadingSnapshot.data ?? LoadingState(isLoadingStatistics: false, isLoadingLocalMetrics: false);
              final isLoadingStats = loadingState.isLoading;

              return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Data Metrics',
              actions: const [],
            ),
            const SizedBox(height: 16),
            // 統計好球、壞球數量
            _buildMetricsGrid(isLoadingStats, backendStats),
            const SizedBox(height: 24),
            _buildTodayInfoCard(),
            const SizedBox(height: 32),
          ],
        ),
      );
            },
          );
        },
      ),
    );
  }
}

/// 儀表板指標計算工具（簡化版，IMU 數據已移除）
class _MetricsCalculator {
  /// 不再計算任何指標，返回默認結果
  static Future<_MetricsResult> compute(List<RecordingHistoryEntry> entries) async {
    return const _MetricsResult(
      averageSpeedMph: null,
      bestSpeedMph: null,
      consistencyScore: null,
      averageImpactClarity: null,
      sweetSpotPercentage: null,
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

/// 區塊標題元件，集中管理標題與右側操作按鈕
class _SectionHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  const _SectionHeader({
    required this.title,
    this.actions = const [],
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
            color: kTextPrimary,
          ),
        ),
        const Spacer(),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          actions[i],
        ],
      ],
    );
  }
}
