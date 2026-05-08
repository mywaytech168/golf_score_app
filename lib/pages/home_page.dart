import 'dart:async';
import 'dart:convert'; // 匯入文字編碼與換行工具，解析 CSV 時需要用到
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// restored original local VideoPlayerPage usage
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recording_history_entry.dart';
import '../models/statistics_response.dart';
import 'external_video_importer_local.dart';
import '../services/recording_history_storage.dart';
import '../services/user_profile_storage.dart';
import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import '../services/statistics_service.dart';
import '../services/purchase_service.dart';
import '../services/daily_ad_manager.dart';
import '../widgets/purchase_test_panel.dart';
import 'recording_history_page.dart';
import 'video_player_page.dart' as video_player;
import 'profile_edit_page.dart';

/// 錄影卡片支援的操作種類
enum _HistoryAction { rename, delete }

/// 首頁提供完整儀表板，呈現揮桿統計、影片庫與分析摘要
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------- 狀態管理區 ----------
  final List<RecordingHistoryEntry> _recordingHistory = []; // 首頁內部維護的錄影紀錄
  bool _isHistoryLoading = true; // 控制歷史載入狀態，避免 UI 閃爍
  int _practiceCount = 0; // 累積練習次數
  double? _bestSpeedMph; // 歷史紀錄中的最佳揮桿速度
  double? _sweetSpotPercentage; // 甜蜜點命中率百分比
  double? _audioCrispness; // 聲音清脆度（0-100）
  bool _isMetricCalculating = false; // 是否正在重新計算儀表板數值
  _ComparisonSnapshot? _comparisonBefore; // 比較區塊的上一筆紀錄
  _ComparisonSnapshot? _comparisonAfter; // 比較區塊的最新紀錄
  String _displayName = 'TekSwing'; // 顯示於標題列的暱稱，預設為產品名稱
  String _userEmail = ''; // 使用者電郵，從 SharedPreferences 讀取
  String? _avatarPath; // 使用者頭像路徑，若為空則顯示預設圖示
  final ExternalVideoImporter _videoImporter = const ExternalVideoImporter(); // 匯入外部影片的工具實例
  
  // 統計服務相關
  late final StatisticsService _statisticsService = StatisticsService();
  
  // 購買服務相關
  late final PurchaseService _purchaseService = PurchaseService();
  
  String _formatDurationShort(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _restoreUserProfile();
    _loadInitialHistory();
    // 初始化統計服務並加載後端和本地數據
    _initializeStatistics();
    // 初始化購買服務
    _initializePurchaseService();
    // 首頁不進行云端和本地視頻的匹配，只顯示本地列表
    // 云端同步由 recording_history_page 統一處理
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

  /// 從本地偏好讀取暱稱、電郵與頭像，確保重新進入 App 仍保有個人化設定
  Future<void> _restoreUserProfile() async {
    final profile =
        await UserProfileStorage.instance.loadProfile(defaultDisplayName: _displayName);
    final prefs = await SharedPreferences.getInstance();
    final userEmail = prefs.getString('user_email') ?? '';
    
    if (!mounted) {
      return; // 若頁面已卸載則不需更新狀態
    }

    setState(() {
      _displayName = profile.displayName; // 還原使用者自訂暱稱
      _userEmail = userEmail; // 還原使用者電郵
      _avatarPath = profile.avatarPath; // 還原之前儲存的頭像
    });
  }

  /// 將時間轉換為比較區塊顯示的日期文字（例：05/21）
  String _formatComparisonDate(DateTime dateTime) {
    return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}';
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
        ? '${todayStats.audioCrispness.average.toStringAsFixed(0)}' 
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
              Expanded(child: _miniStat(title: '好球', value: '$goodHits')),
              Expanded(child: _miniStat(title: '壞球', value: '$badHits')),
              Expanded(child: _miniStat(title: '練習次數', value: '$practice')),
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
        Text(title, style: const TextStyle(color: Color(0xFF7D8B9A), fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E8E5A)),
        ),
      ],
    );
  }

  /// 建立比較區塊，呈現昨天與今天的速度對比
  Widget _buildComparisonCard() {
    // 使用後端 API 的昨天和今天數據
    final yesterdayStats = _statisticsService.yesterdayStatistics;
    final todayStats = _statisticsService.todayStatistics;
    
    final yesterdaySpeed = yesterdayStats?.peakValue.maximum;
    final todaySpeed = todayStats?.peakValue.maximum;
    
    String buildSpeedLabel(double? speed) {
      if (speed == null || speed == 0) return '--';
      return '${speed.toStringAsFixed(1)} MPH';
    }

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
          _SectionHeader(
            title: 'Comparison',
            actions: [
              GestureDetector(
                onTap: _openRecordingHistoryPage,
                child: const Text(
                  '查看歷史',
                  style: TextStyle(
                    color: Color(0xFF1E8E5A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('昨天', style: TextStyle(color: Color(0xFF7D8B9A))),
                    const SizedBox(height: 6),
                    Text(
                      buildSpeedLabel(yesterdaySpeed),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDA4E5D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '昨天的最佳速度',
                      style: TextStyle(color: Color(0xFF7D8B9A)),
                    ),
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
                  children: [
                    const Text('今天', style: TextStyle(color: Color(0xFF7D8B9A))),
                    const SizedBox(height: 6),
                    Text(
                      buildSpeedLabel(todaySpeed),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E8E5A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '今天的最佳速度',
                      style: TextStyle(color: Color(0xFF7D8B9A)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 方法區 ----------
  /// 建立統計資訊卡片，方便重複使用與維持一致風格
  /// 構建指標卡片網格
  Widget _buildMetricsGrid(bool isLoadingStats, StatisticsResponse? backendStats) {
    // 統計好球、壞球數量
    final goodShotCount = _recordingHistory.where((e) => e.goodShot == true).length;
    final badShotCount = _recordingHistory.where((e) => e.goodShot == false).length;
    
    // 準備所有指標數據
    final metricsCards = <Map<String, dynamic>>[
      {
        'title': '最佳速度',
        'value': isLoadingStats
            ? '載入中...'
            : backendStats != null && backendStats.peakValue.maximum > 0
                ? '${backendStats.peakValue.maximum.toStringAsFixed(1)} MPH'
                : '尚無資料',
        'color': const Color(0xFF2E8EFF),
        'highlight': true,
      },
      {
        'title': '甜蜜點命中',
        'value': isLoadingStats
            ? '載入中...'
            : backendStats != null
                ? '${backendStats.sweetSpotPercentage.toStringAsFixed(0)} %'
                : '尚無資料',
        'color': const Color(0xFF8E4AF4),
        'highlight': false,
      },
      {
        'title': '好球',
        'value': '$goodShotCount 次',
        'color': const Color(0xFF1E8E5A),
        'highlight': false,
      },
      {
        'title': '壞球',
        'value': '$badShotCount 次',
        'color': const Color(0xFFDA4E5D),
        'highlight': false,
      },
      {
        'title': '聲音清脆度',
        'value': isLoadingStats
            ? '載入中...'
            : backendStats != null && backendStats.audioCrispness.average > 0
                ? '${backendStats.audioCrispness.average.toStringAsFixed(0)}'
                : '尚無資料',
        'color': const Color(0xFFDA4E5D),
        'highlight': false,
      },
      {
        'title': '練習次數',
        'value': '$_practiceCount 次',
        'color': const Color(0xFF1E8E5A),
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
              color: Color(0xFF7D8B9A),
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

  /// 開啟個人資訊編輯頁，並在儲存後更新首頁顯示資訊
  Future<void> _openProfileEditPage() async {
    final result = await Navigator.of(context).push<ProfileEditResult>(
      MaterialPageRoute(
        builder: (_) => ProfileEditPage(
          initialDisplayName: _displayName,
          initialEmail: _userEmail,
          initialAvatarPath: _avatarPath,
        ),
      ),
    );

    if (!mounted || result == null) {
      return; // 使用者取消或頁面已卸載時不處理回傳資料
    }

    final resolvedDisplayName =
        result.displayName.trim(); // 再次保險去除頭尾空白避免儲存異常
    final safeDisplayName =
        resolvedDisplayName.isEmpty ? 'TekSwing' : resolvedDisplayName; // 防禦性處理空字串

    final nextAvatarPath = result.removeAvatar
        ? null
        : result.avatarPath ?? _avatarPath; // 若僅更新暱稱則沿用舊頭像

    setState(() {
      _displayName = safeDisplayName; // 將最新暱稱同步到標題列
      _avatarPath = nextAvatarPath; // 更新頭像狀態（可能為 null 代表清除）
    });

    await UserProfileStorage.instance.saveProfile(
      displayName: safeDisplayName,
      avatarPath: nextAvatarPath,
    );

    // 顯示提示訊息，告知使用者更新已生效
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('個人資訊已更新')),
    );
  }

  /// 為網格顯示構建緊湊型影片卡片
  Widget _buildCompactVideoTile({
    required RecordingHistoryEntry entry,
    required Color baseColor,
  }) {
    final thumbnailPath = entry.thumbnailPath;
    final hasThumbnail = thumbnailPath != null && thumbnailPath.isNotEmpty;
    final dateLabel = '${entry.recordedAt.month.toString().padLeft(2, '0')}/${entry.recordedAt.day.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _playHistoryEntry(entry),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [baseColor, baseColor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // 背景圖像
                Positioned.fill(
                  child: hasThumbnail
                      ? Image.file(
                          File(thumbnailPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [baseColor.withOpacity(0.95), baseColor.withOpacity(0.55)],
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                ),
                              ),
                            );
                          },
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [baseColor.withOpacity(0.95), baseColor.withOpacity(0.55)],
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                            ),
                          ),
                        ),
                ),
                // 播放圖標遮罩
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    child: const Align(
                      alignment: Alignment.center,
                      child: Icon(Icons.play_circle_fill, size: 32, color: Colors.white24),
                    ),
                  ),
                ),
                // 底部信息
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // 圖標標籤
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: entry.goodShot == null
                          ? Colors.grey.withOpacity(0.7)
                          : entry.goodShot == true
                              ? Colors.green.withOpacity(0.8)
                              : Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      entry.goodShot == null
                          ? '未分'
                          : entry.goodShot == true
                              ? '好球'
                              : '壞球',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 將儀表板數值轉換為雷達圖比例，便於統一控制上限
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
      _isHistoryLoading = false;
      _practiceCount = finalEntries.length;
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

  /// 刪除指定的歷史紀錄，並詢問是否同步移除實體檔案
  Future<void> _deleteHistoryEntry(RecordingHistoryEntry entry) async {
    if (_recordingHistory.isEmpty) {
      return; // 無資料時直接略過
    }

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('刪除影片紀錄'),
          content: Text('確定要刪除「${entry.displayTitle}」嗎？\n影片與對應 CSV 會一併從裝置移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('刪除'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) {
      return; // 使用者取消刪除
    }

    final updatedEntries = List<RecordingHistoryEntry>.from(_recordingHistory)
      ..removeWhere((item) =>
          item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (updatedEntries.length == _recordingHistory.length) {
      return; // 未找到對應項目
    }

    await _applyHistoryState(updatedEntries);
    unawaited(_deleteEntryFiles(entry));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已刪除 ${entry.fileName}')), // 告知刪除完成
    );
  }

  /// 顯示輸入框讓使用者重新命名影片
  Future<void> _renameHistoryEntry(RecordingHistoryEntry entry) async {
    final initialText = entry.customName != null && entry.customName!.trim().isNotEmpty
        ? entry.customName!.trim()
        : entry.displayTitle;
    String tempName = initialText; // 暫存輸入內容，避免 TextEditingController 釋放問題
    final formKey = GlobalKey<FormState>();
    debugPrint('[首頁歷史] 準備重新命名影片：${entry.fileName}'); // 紀錄流程起點
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重新命名影片'),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: TextFormField(
              initialValue: initialText,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: '影片名稱',
                helperText: '可留空以恢復預設名稱',
              ),
              onChanged: (value) => tempName = value,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.length > 40) {
                  return '名稱需在 40 字以內';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final isValid = formKey.currentState?.validate() ?? false;
                if (!isValid) {
                  return; // 驗證失敗時不關閉視窗
                }
                Navigator.of(dialogContext).pop(tempName.trim());
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );

    if (!mounted || newName == null) {
      debugPrint('[首頁歷史] 重新命名流程取消或頁面已卸載');
      return;
    }

    final normalizedName = newName.trim();
    final storedName = normalizedName.isEmpty ? '' : normalizedName;
    final originalName = (entry.customName ?? '').trim();
    debugPrint('[首頁歷史] 重新命名輸入：stored="$storedName" original="$originalName"');
    if (storedName == originalName) {
      debugPrint('[首頁歷史] 名稱未變更，終止重新命名流程');
      return; // 未變更名稱時不進行後續流程
    }

    final updatedEntries = List<RecordingHistoryEntry>.from(_recordingHistory);
    final targetIndex = updatedEntries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (targetIndex == -1) {
      debugPrint('[首頁歷史] 找不到對應紀錄，無法重新命名');
      return;
    }

    final defaultTitle = entry.copyWith(customName: '').displayTitle;
    updatedEntries[targetIndex] =
        updatedEntries[targetIndex].copyWith(customName: storedName);
    debugPrint('[首頁歷史] 套用重新命名至索引 $targetIndex，準備立即寫回狀態');
    await _applyHistoryState(updatedEntries);

    if (!mounted) return;
    final snackMessage = storedName.isEmpty
        ? '已恢復影片名稱為 $defaultTitle'
        : '已將影片命名為 $storedName';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackMessage)),
    );
  }

  /// 移除影片與 CSV 實體檔案，避免資料殘留
  Future<void> _deleteEntryFiles(RecordingHistoryEntry entry) async {
    try {
      final videoFile = File(entry.filePath);
      if (await videoFile.exists()) {
        await videoFile.delete();
      }
    } catch (_) {
      // 保持靜默，避免 IO 例外影響主流程
    }

    final thumbnailPath = entry.thumbnailPath;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      try {
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      } catch (_) {
        // 縮圖刪除失敗時同樣忽略
      }
    }
  }


  /// 透過檔案挑選器挑選影片後匯入，提供 Data Metrics 與 Video Library 共同呼叫
  Future<void> _pickExternalVideoForImport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) {
      return; // 使用者取消挑選時直接結束
    }

    await _importExternalVideo(
      path: result.files.single.path!,
      fileName: result.files.single.name,
    );
  }

  /// 實際執行影片匯入：複製檔案、建立歷史紀錄並刷新練習統計
  Future<void> _importExternalVideo({
    required String path,
    String? fileName,
  }) async {
    final nextRoundIndex =
        ExternalVideoImporter.calculateNextRoundIndex(_recordingHistory);
    final entry = await _videoImporter.importVideo(
      sourcePath: path,
      originalName: fileName,
      nextRoundIndex: nextRoundIndex,
    );

    if (entry == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('匯入影片失敗，請確認檔案是否仍存在。')),
      );
      return;
    }

    final updatedEntries = <RecordingHistoryEntry>[entry, ..._recordingHistory];
    await _applyHistoryState(updatedEntries);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已匯入 ${entry.displayTitle}，並同步加入練習統計。')),
    );
  }

  /// 將更新後的錄影紀錄套用到首頁狀態並觸發儲存與統計重算
  Future<void> _applyHistoryState(List<RecordingHistoryEntry> entries) async {
    if (!mounted) {
      debugPrint('[首頁歷史] _applyHistoryState 略過：頁面已卸載');
      return;
    }

    debugPrint('[首頁歷史] _applyHistoryState 套用 ${entries.length} 筆資料');
    setState(() {
      _recordingHistory
        ..clear()
        ..addAll(entries);
      _isHistoryLoading = false;
      _practiceCount = entries.length;
      _isMetricCalculating = true;
    });

    await RecordingHistoryStorage.instance.saveHistory(
      List<RecordingHistoryEntry>.from(_recordingHistory),
    );

    if (!mounted) {
      debugPrint('[首頁歷史] 儲存完成時頁面已卸載，停止後續流程');
      return;
    }

    await _refreshDashboardMetrics();
  }

  /// 接收錄影頁回傳的歷史紀錄，統一整理後套用到首頁狀態
  void _handleHistoryUpdated(List<RecordingHistoryEntry> entries) {
    unawaited(_prepareHistoryUpdate(entries));
  }

  /// 先確保縮圖完整再寫回狀態，避免畫面顯示灰階背景
  Future<void> _prepareHistoryUpdate(List<RecordingHistoryEntry> entries) async {
    final regenerated = await _cleanInvalidThumbnails(entries);
    await _applyHistoryState(regenerated ?? entries);
  }

  /// 重新計算首頁儀表板指標，基於錄製歷史的音頻分析與擊球檢測結果
  /// 並將計算結果存儲到 StatisticsService 中供 Data Metrics 和 Analytics 使用
  Future<void> _refreshDashboardMetrics() async {
    final snapshot = List<RecordingHistoryEntry>.from(_recordingHistory);
    if (snapshot.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isMetricCalculating = false;
      });
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

    setState(() {
      _isMetricCalculating = true;
    });

    try {
      final metrics = await _MetricsCalculator.compute(snapshot);
      if (!mounted) return;
      
      // 從最新的錄影紀錄中取得聲音清脆度
      double? latestAudioCrispness;
      for (final entry in snapshot.reversed) {
        if (entry.audioCrispness != null) {
          final crispValue = entry.audioCrispness;
          latestAudioCrispness = (crispValue is int) ? (crispValue as int).toDouble() : crispValue as double?;
          break;
        }
      }
      
      // 轉換 _ComparisonSnapshot 為 ComparisonSnapshot
      ComparisonSnapshot? before;
      if (metrics.comparisonBefore != null) {
        before = ComparisonSnapshot(
          entryId: metrics.comparisonBefore!.entry.filePath,
          recordedAtLabel: _formatComparisonDate(metrics.comparisonBefore!.entry.recordedAt),
          speedMph: metrics.comparisonBefore!.speedMph,
          impactClarity: metrics.comparisonBefore!.impactClarity,
          audioCrispness: metrics.comparisonBefore!.audioCrispness,
        );
      }
      
      ComparisonSnapshot? after;
      if (metrics.comparisonAfter != null) {
        after = ComparisonSnapshot(
          entryId: metrics.comparisonAfter!.entry.filePath,
          recordedAtLabel: _formatComparisonDate(metrics.comparisonAfter!.entry.recordedAt),
          speedMph: metrics.comparisonAfter!.speedMph,
          impactClarity: metrics.comparisonAfter!.impactClarity,
          audioCrispness: metrics.comparisonAfter!.audioCrispness,
        );
      }
      
      setState(() {
        _isMetricCalculating = false;
        _bestSpeedMph = metrics.bestSpeedMph;
        _sweetSpotPercentage = metrics.sweetSpotPercentage;
        _audioCrispness = latestAudioCrispness;
        _comparisonBefore = metrics.comparisonBefore;
        _comparisonAfter = metrics.comparisonAfter;
      });
      
      // 更新服務中的本地指標，供 Data Metrics 和 Analytics 共享
      _statisticsService.setLocalMetrics(
        consistencyScore: null, // 不再使用 consistency score
        bestSpeedMph: metrics.bestSpeedMph,
        sweetSpotPercentage: metrics.sweetSpotPercentage,
        audioCrispness: latestAudioCrispness,
        comparisonBefore: before,
        comparisonAfter: after,
      );
      
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isMetricCalculating = false;
      });
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

  /// 開啟獨立的錄影歷史頁面，讓使用者專注瀏覽過往影片
  Future<void> _openRecordingHistoryPage() async {
    final result = await Navigator.of(context).push<List<RecordingHistoryEntry>>(
      MaterialPageRoute(
        builder: (_) => RecordingHistoryPage(
          entries: _recordingHistory,
          userAvatarPath: _avatarPath,
        ),
      ),
    );
    // 無論是否有回傳，重新載入儲存的歷史，確保分片/匯入後首頁同步
    if (result != null) {
      _handleHistoryUpdated(result);
    } else {
      await _loadInitialHistory();
    }
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
      MaterialPageRoute(
        builder: (_) => video_player.VideoPlayerPage(
          videoPath: entry.filePath,
          avatarPath: _avatarPath,
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0B2A2E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _userEmail,
                    style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF6E7B87)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {},
              tooltip: '通知中心',
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF0B2A2E)),
            ),
            if (kDebugMode)
              IconButton(
                onPressed: () => showPurchaseTestPanel(
                  context,
                  purchaseService: _purchaseService,
                ),
                tooltip: '🧪 購買測試',
                icon: const Icon(Icons.bug_report, color: Colors.orange),
              ),
            if (kDebugMode)
              IconButton(
                onPressed: () async {
                  final adManager = DailyAdManager();
                  await adManager.initialize();
                  await adManager.resetAdUsage();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ 廣告使用狀態已重置')),
                    );
                  }
                },
                tooltip: '🔄 重置廣告',
                icon: const Icon(Icons.refresh, color: Colors.blue),
              ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: _logout,
              tooltip: '登出',
              icon: const Icon(Icons.logout_rounded, color: Color(0xFF0B2A2E)),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: _openProfileEditPage,
              borderRadius: BorderRadius.circular(36),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4EA),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: const Color(0xFF1E8E5A)),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: Builder(
                  builder: (context) {
                    // 放大頭像容器與邊框，讓個人圖示更醒目，同時維持裁切為正方形避免拉長
                    if (_avatarPath != null) {
                      final avatarFile = File(_avatarPath!);
                      if (avatarFile.existsSync()) {
                        return Image.file(
                          avatarFile,
                          fit: BoxFit.cover,
                        );
                      }
                    }
                    return const Icon(
                      Icons.person_outline,
                      color: Color(0xFF1E8E5A),
                      size: 40,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
            const SizedBox(height: 24),
            _buildComparisonCard(),
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
      comparisonBefore: null,
      comparisonAfter: null,
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
  final _ComparisonSnapshot? comparisonBefore;
  final _ComparisonSnapshot? comparisonAfter;

  const _MetricsResult({
    required this.averageSpeedMph,
    required this.bestSpeedMph,
    required this.consistencyScore,
    required this.averageImpactClarity,
    required this.sweetSpotPercentage,
    required this.comparisonBefore,
    required this.comparisonAfter,
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

/// 將錄影紀錄與分析結果綁定，供比較與彙整使用
class _EntrySnapshot {
  final RecordingHistoryEntry entry; // 原始錄影資訊
  final _SwingSnapshot? snapshot; // 解析後的感測數據

  const _EntrySnapshot({required this.entry, required this.snapshot});
}

/// 比較區塊顯示的資料結構
class _ComparisonSnapshot {
  final RecordingHistoryEntry entry; // 對應的錄影紀錄
  final double? speedMph; // 預估揮桿速度
  final double impactClarity; // 擊球清脆度比例
  final double? audioCrispness; // 聲音清脆度（0-100）

  const _ComparisonSnapshot({
    required this.entry,
    required this.speedMph,
    required this.impactClarity,
    this.audioCrispness,
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
            color: Color(0xFF0B2A2E),
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
