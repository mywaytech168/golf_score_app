import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'providers/statistics_provider.dart';
import 'providers/app_state_provider.dart';

/// 首頁 Widget
/// 
/// 顯示今日揮桿統計、快速操作和推薦功能
class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const HomePage({
    super.key,
    required this.cameras,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // 初始化時載入數據
    Future.microtask(() {
      if (mounted) {
        context.read<StatisticsProvider>().loadTodayStatistics();
        context.read<UserProvider>().loadProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('高爾夫揮桿分析'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<StatisticsProvider>().refreshAll();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // 導航到設置頁面
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<StatisticsProvider>().refreshAll(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ============ 歡迎區域 ============
              _buildWelcomeSection(),
              const SizedBox(height: 24),

              // ============ 今日統計卡片 ============
              _buildTodayStatsCard(),
              const SizedBox(height: 20),

              // ============ 快速操作區域 ============
              _buildQuickActionsSection(),
              const SizedBox(height: 20),

              // ============ 進度指標 ============
              _buildProgressSection(),
              const SizedBox(height: 20),

              // ============ 推薦操作 ============
              _buildRecommendationsSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// 歡迎區域
  Widget _buildWelcomeSection() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        return Card(
          elevation: 2,
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: userProvider.avatarPath != null
                          ? NetworkImage(userProvider.avatarPath!)
                          : null,
                      child: userProvider.avatarPath == null
                          ? const Icon(Icons.person, size: 30)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '歡迎回來，${userProvider.displayName}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${DateTime.now().month}月${DateTime.now().day}日',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 今日統計卡片
  Widget _buildTodayStatsCard() {
    return Consumer<StatisticsProvider>(
      builder: (context, statsProvider, _) {
        if (statsProvider.isLoading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (statsProvider.errorMessage != null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    statsProvider.errorMessage!,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final metrics = statsProvider.getTodayMetrics();

        return Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日統計',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile('總揮桿數', '${metrics['totalSwings']}'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatTile('好球', '${metrics['goodShots']}'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile('準確率', '${metrics['accuracy']}'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatTile('平均速度', '${metrics['averagePeak']}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 統計機項
  Widget _buildStatTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// 快速操作區域
  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '快速操作',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              icon: Icons.videocam,
              label: '開始錄制',
              onPressed: () {
                // 導航到錄制頁面
              },
            ),
            _buildActionButton(
              icon: Icons.auto_awesome,
              label: '教學',
              onPressed: () {
                // 導航到教學頁面
              },
            ),
            _buildActionButton(
              icon: Icons.trending_up,
              label: '分析',
              onPressed: () {
                // 導航到分析頁面
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 快速操作按鈕
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
            backgroundColor: Colors.blue.shade400,
          ),
          child: Icon(icon, size: 28, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 進度區域
  Widget _buildProgressSection() {
    return Consumer<StatisticsProvider>(
      builder: (context, statsProvider, _) {
        final progress = statsProvider.getProgressPercentage();
        final percentage = (progress * 100).toStringAsFixed(1);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日進度',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      progress > 1.0 ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '目標達成度: $percentage%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 推薦區域
  Widget _buildRecommendationsSection() {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        if (!appState.showTips) {
          return const SizedBox.shrink();
        }

        return Card(
          elevation: 2,
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      '今日提示',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '提高記錄一致性：確保每次錄制時相機角度相同，以便更好地追蹤進度。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      appState.toggleShowTips(false);
                    },
                    child: const Text('不再顯示'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}