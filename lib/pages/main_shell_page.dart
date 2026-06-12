import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

import '../theme/app_theme.dart';
import 'home_page.dart';
import 'onboarding_page.dart';
import 'today_info_page.dart';
import 'upgrade_page.dart';
import 'recording_history_page.dart';
import 'video_player_page.dart';
import 'recording_selection_screen.dart';
import '../models/recording_history_entry.dart';
import '../services/recording_history_storage.dart';
import '../services/app_update_service.dart';
import '../services/statistics_service.dart';
import '../widgets/update_dialog.dart';

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
    // 在首幀繪製完成後才做教學引導 / 版本檢查，避免阻塞 UI
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPostFrameChecks());
  }

  /// 首幀後流程：先顯示初次教學引導（若未看過），再做版本檢查
  Future<void> _runPostFrameChecks() async {
    if (!mounted) return;
    await OnboardingPage.maybeShow(context);
    await _checkForUpdate();
  }

  /// 向後端查詢更新，依結果決定顯示強制 / 非強制對話框
  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final result = await AppUpdateService.check();
    if (!mounted || !result.needsUpdate) return;

    // 非強制更新：若使用者已對此版本選擇「不再提醒」則略過
    if (!result.isForced) {
      final snoozed = await AppUpdateService.snoozedVersion();
      if (snoozed == result.latestVersion) return;
    }

    if (!mounted) return;
    await showUpdateDialog(context, result);
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
        // Home — 切回首頁時刷新統計，確保姿勢分析結果即時反映
        StatisticsService().loadAllStatistics();
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
    required String aspectRatioMode,
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
        recordedAspectRatio: aspectRatioMode,
        audioTags: audioTags,
        recordedPlatform:
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      
      await RecordingHistoryStorage.instance.upsertEntry(entry);

      if (mounted) setState(() => _recordingHistory.insert(0, entry));

      debugPrint('[MainShell] 錄製完成: ${videoPath.split('/').last}, Tags: $audioTags');

      // 錄製完成後直接跳到影片播放頁
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerPage(
              videoPath: entry.filePath,
              entry: entry,
            ),
          ),
        );
      }
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
        physics: const NeverScrollableScrollPhysics(),
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
              required aspectRatioMode,
              List<String>? audioTags,
            }) {
              _handleRecordingComplete(
                videoPath,
                csvPath,
                audioPath,
                durationSeconds: durationSeconds,
                thumbnailPath: thumbnailPath,
                audioLabel: audioLabel,
                aspectRatioMode: aspectRatioMode,
                audioTags: audioTags,
              );
              // 導向詳情頁由 _handleRecordingComplete 負責；shell 保持在 index 0
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
        ], // 禁用滑動切換，只允許底部導覽點擊
      ),
      
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.bgCard,
        boxShadow: context.isDarkMode
            ? const []
            : const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BottomNavItem(
            icon: Icons.home_rounded,
            label: l10n.navHome,
            isActive: _currentIndex == 0,
            onTap: () => _onBottomNavTap(0),
          ),
          _BottomNavItem(
            icon: Icons.calendar_today_rounded,
            label: l10n.navData,
            isActive: _currentIndex == 1,
            onTap: () => _onBottomNavTap(1),
          ),
          _QuickStartNavItem(
            label: l10n.navRecord,
            isActive: _currentIndex == 2,
            onTap: () => _onBottomNavTap(2),
          ),
          _BottomNavItem(
            icon: Icons.bar_chart_rounded,
            label: l10n.navHistory,
            isActive: _currentIndex == 3,
            onTap: () => _onBottomNavTap(3),
          ),
          _BottomNavItem(
            icon: Icons.workspace_premium_rounded,
            label: l10n.navPremium,
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
  final String label;

  const _QuickStartNavItem({
    required this.onTap,
    required this.label,
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
