import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_page.dart';
import 'today_info_page.dart';
import 'upgrade_page.dart';
import 'recording_history_page.dart';
import 'recording_selection_screen.dart';
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
  
  final List<RecordingHistoryEntry> _recordingHistory = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final entries = await RecordingHistoryStorage.instance.loadHistory();
    if (!mounted) return;
    setState(() => _recordingHistory
      ..clear()
      ..addAll(entries));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
  Future<void> _handleRecordingComplete(
    String videoPath,
    String csvPath,
    String audioPath, {
    required int durationSeconds,
    required String? thumbnailPath,
    required String? audioLabel,
    List<String>? audioTags,
  }) async {
    try {
      // 更新本地歷史記錄
      final existing = await RecordingHistoryStorage.instance.loadHistory();
      final timestamp = DateTime.now();
      final entry = RecordingHistoryEntry(
        filePath: videoPath,
        roundIndex: existing.length + 1,
        recordedAt: timestamp,
        durationSeconds: durationSeconds,
        thumbnailPath: thumbnailPath,
        audioLabel: audioLabel,
        audioTags: audioTags,
      );
      
      final updated = <RecordingHistoryEntry>[entry, ...existing];
      await RecordingHistoryStorage.instance.saveHistory(updated);
      
      setState(() {
        _recordingHistory.insert(0, entry);
      });
      
      debugPrint('[MainShell] 錄製完成: ${videoPath.split('/').last}, Tags: $audioTags');
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
          const TodayInfoPage(),
          
          // 第 2 頁：錄製選擇屏幕
          RecordingSelectionScreen(
            onComplete: ({
              required videoPath,
              required csvPath,
              required audioPath,
              required durationSeconds,
              required thumbnailPath,
              required audioLabel,
              List<String>? audioTags,
            }) {
              _handleRecordingComplete(
                videoPath,
                csvPath,
                audioPath,
                durationSeconds: durationSeconds,
                thumbnailPath: thumbnailPath,
                audioLabel: audioLabel,
                audioTags: audioTags,
              );
              // 完成後返回 Home
              _pageController.animateToPage(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            onVideoImported: _loadHistory,
          ),
          
          // 第 3 頁：數據指標頁
          RecordingHistoryPage(
            entries: _recordingHistory,
            userAvatarPath: null,
            onDelete: _loadHistory,
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
            label: '首頁',
            isActive: _currentIndex == 0,
            onTap: () => _onBottomNavTap(0),
          ),
          _BottomNavItem(
            icon: Icons.calendar_today_rounded,
            label: '數據',
            isActive: _currentIndex == 1,
            onTap: () => _onBottomNavTap(1),
          ),
          _QuickStartNavItem(
            isActive: _currentIndex == 2,
            onTap: () => _onBottomNavTap(2),
          ),
          _BottomNavItem(
            icon: Icons.bar_chart_rounded,
            label: '歷史',
            isActive: _currentIndex == 3,
            onTap: () => _onBottomNavTap(3),
          ),
          _BottomNavItem(
            icon: Icons.workspace_premium_rounded,
            label: '付費',
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
            color: isActive ? kPrimaryGreen : Colors.grey,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? kPrimaryGreen : Colors.grey,
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
                      colors: [kPrimaryGreen, kPrimaryLight],
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
                  color: (isActive ? kPrimaryGreen : Colors.grey).withValues(alpha: 0.3),
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
              color: isActive ? kPrimaryGreen : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
