import 'package:flutter/material.dart';

import 'home_page.dart';
import 'today_info_page.dart';
import 'upgrade_page.dart';
import 'recording_history_page.dart';
import '../recording/record_screen.dart';
import '../models/recording_history_entry.dart';
import '../services/recording_history_storage.dart';

/// 主應用殼層：統一管理底部導覽列，確保跨頁面持久化
/// 
/// 此 Widget 包含 Scaffold 和 BottomNavigationBar，管理所有主要頁面的切換
/// 無論用戶在哪個頁面，底部導覽列始終可見
class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _currentIndex = 0; // 當前選中的底部導覽項序號
  late PageController _pageController; // 頁面控制器，便於平滑過渡
  
  // 緩存頁面數據
  int _practiceCount = 0;
  double? _bestSpeedMph;
  double? _sweetSpotPercentage;
  double? _audioCrispness;
  int _goodHits = 0;
  int _badHits = 0;
  String? _avatarPath;
  final List<RecordingHistoryEntry> _recordingHistory = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 處理頁面數據更新（來自子頁面）
  void _updatePageData({
    int? practiceCount,
    double? bestSpeedMph,
    double? sweetSpotPercentage,
    double? audioCrispness,
    int? goodHits,
    int? badHits,
    String? avatarPath,
    List<RecordingHistoryEntry>? recordingHistory,
  }) {
    setState(() {
      if (practiceCount != null) _practiceCount = practiceCount;
      if (bestSpeedMph != null) _bestSpeedMph = bestSpeedMph;
      if (sweetSpotPercentage != null) _sweetSpotPercentage = sweetSpotPercentage;
      if (audioCrispness != null) _audioCrispness = audioCrispness;
      if (goodHits != null) _goodHits = goodHits;
      if (badHits != null) _badHits = badHits;
      if (avatarPath != null) _avatarPath = avatarPath;
      if (recordingHistory != null) _recordingHistory.addAll(recordingHistory);
    });
  }

  /// 處理底部導覽點擊，切換頁面
  void _onBottomNavTap(int index) {
    setState(() => _currentIndex = index);
    
    // 對應不同的頁面跳轉
    switch (index) {
      case 0:
        // Home
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        break;
      case 1:
        // Today
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        break;
      case 2:
        // Recording Session (Quick Start)
        _pageController.animateToPage(
          2,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        break;
      case 3:
        // Metrics
        _pageController.animateToPage(
          3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        break;
      case 4:
        // Upgrade
        _pageController.animateToPage(
          4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        break;
    }
  }

  /// 處理錄製完成時的回調
  Future<void> _handleRecordingComplete(String videoPath, String csvPath, String audioPath) async {
    try {
      // 更新本地歷史記錄
      final existing = await RecordingHistoryStorage.instance.loadHistory();
      final timestamp = DateTime.now();
      final entry = RecordingHistoryEntry(
        filePath: videoPath,
        roundIndex: existing.length + 1,
        recordedAt: timestamp,
        durationSeconds: 0, // 會在 record_screen.dart 中計算
        thumbnailPath: null,
        cloudVideoId: null,
      );
      
      final updated = <RecordingHistoryEntry>[entry, ...existing];
      await RecordingHistoryStorage.instance.saveHistory(updated);
      
      setState(() {
        _recordingHistory.insert(0, entry);
      });
      
      debugPrint('[MainShell] 錄製完成: ${videoPath.split('/').last}');
    } catch (e) {
      debugPrint('[MainShell] 處理錄製完成失敗: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        children: [
          // 第 0 頁：首頁
          const HomePage(),
          
          // 第 1 頁：今日信息頁
          TodayInfoPage(
            practiceCount: _practiceCount,
            bestSpeedMph: _bestSpeedMph ?? 0,
            sweetSpotPercentage: _sweetSpotPercentage ?? 0,
            audioCrispness: _audioCrispness ?? 0,
            goodHits: _goodHits,
            badHits: _badHits,
            goodVideoPath: null,
            badVideoPath: null,
          ),
          
          // 第 2 頁：骨架推論錄影頁
          RecordScreen(
            onComplete: ({required videoPath, required csvPath, required audioPath}) {
              _handleRecordingComplete(videoPath, csvPath, audioPath);
            },
          ),
          
          // 第 3 頁：數據指標頁
          RecordingHistoryPage(
            entries: _recordingHistory,
            userAvatarPath: _avatarPath,
          ),
          
          // 第 4 頁：升級頁
          const UpgradePage(),
        ],
        physics: const NeverScrollableScrollPhysics(), // 禁用滑動切換，只允許底部導覽點擊
      ),
      
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 構建自定義底部導覽列
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            label: 'Today',
            isActive: _currentIndex == 1,
            onTap: () => _onBottomNavTap(1),
          ),
          _QuickStartNavItem(
            isActive: _currentIndex == 2,
            onTap: () => _onBottomNavTap(2),
          ),
          _BottomNavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Metrics',
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

/// 底部導覽項 - 常規項目
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
          Icon(
            icon,
            color: isActive ? const Color(0xFF1E8E5A) : Colors.grey,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? const Color(0xFF1E8E5A) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部導覽項 - Quick Start 中央突出項
class _QuickStartNavItem extends StatelessWidget {
  final VoidCallback onTap;
  final bool isActive;

  const _QuickStartNavItem({
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isActive 
                  ? const LinearGradient(
                      colors: [Color(0xFF1E8E5A), Color(0xFF2DB86A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [Colors.grey[400]!, Colors.grey[500]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: [
                BoxShadow(
                  color: (isActive ? const Color(0xFF1E8E5A) : Colors.grey).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.videocam_rounded, 
                color: Colors.white, 
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Record',
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? const Color(0xFF1E8E5A) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
