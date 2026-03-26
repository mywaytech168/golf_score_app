import 'dart:async';
import 'dart:convert'; // 匯入文字編碼與換行工具，解析 CSV 時需要用到
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// restored original local VideoPlayerPage usage
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recording_history_entry.dart';
import '../models/statistics_response.dart';
import '../recorder_page.dart';
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
import 'today_info_page.dart';
import 'upgrade_page.dart';

/// 錄影卡片支援的操作種類
enum _HistoryAction { rename, editDuration, delete }

/// 首頁提供完整儀表板，呈現揮桿統計、影片庫與分析摘要
class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras; // 傳入鏡頭資訊供後續錄影使用

  const HomePage({super.key, required this.cameras});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------- 狀態管理區 ----------
  int _currentIndex = 2; // 底部導覽預設聚焦在 Quick Start
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
    final thumbnailPath = entry.thumbnailPath;
    final hasThumbnail = thumbnailPath != null && thumbnailPath.isNotEmpty;

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
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black.withOpacity(0.65), Colors.transparent],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.center,
                          child: Icon(Icons.play_circle_fill, size: 46, color: Colors.white24),
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
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: entry.goodShot == null
                              ? Colors.grey.withOpacity(0.7)
                              : entry.goodShot == true
                                  ? Colors.green.withOpacity(0.8)
                                  : Colors.red.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          entry.goodShot == null
                              ? '未分類'
                              : entry.goodShot == true
                                  ? '好球'
                                  : '壞球',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: PopupMenuButton<_HistoryAction>(
                        tooltip: '更多操作',
                        icon: const Icon(Icons.more_vert, color: Colors.white70),
                        color: Colors.white,
                        onSelected: (action) {
                          // 使用 addPostFrameCallback 讓操作在下一幀進行，確保 PopupMenu 已完整關閉
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            switch (action) {
                              case _HistoryAction.rename:
                                _renameHistoryEntry(entry);
                                break;
                              case _HistoryAction.editDuration:
                                _editHistoryDuration(entry);
                                break;
                              case _HistoryAction.delete:
                                _deleteHistoryEntry(entry);
                                break;
                            }
                          });
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem<_HistoryAction>(
                            value: _HistoryAction.rename,
                            child: Text('重新命名'),
                          ),
                          const PopupMenuItem<_HistoryAction>(
                            value: _HistoryAction.editDuration,
                            child: Text('調整時長'),
                          ),
                          const PopupMenuItem<_HistoryAction>(
                            value: _HistoryAction.delete,
                            child: Text('刪除影片'),
                          ),
                        ],
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
    final bestSpeedScore = _bestSpeedMph != null
        ? (_bestSpeedMph! / 130).clamp(0.0, 1.0)
        : 0.0;
    final clarityScore = (_sweetSpotPercentage != null ? _sweetSpotPercentage! / 100.0 : 0.0)
        .clamp(0.0, 1.0);
    // 安全地處理 _audioCrispness 可能是 int 或 double 的情況
    final crispValue = _audioCrispness != null ? (_audioCrispness is int ? (_audioCrispness as int).toDouble() : _audioCrispness as double) : 0.0;
    final crispnessScore = (crispValue / 100).clamp(0.0, 1.0);
    final volumeScore = (_practiceCount / 12.0).clamp(0.0, 1.0);

    return [bestSpeedScore, clarityScore, crispnessScore, volumeScore];
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

  /// 顯示秒數輸入框，更新影片時長資訊
  Future<void> _editHistoryDuration(RecordingHistoryEntry entry) async {
    debugPrint('[首頁歷史] 準備調整影片時長：${entry.fileName} 當前秒數=${entry.durationSeconds}');
    String tempValue = entry.durationSeconds.toString(); // 以字串暫存輸入內容
    final formKey = GlobalKey<FormState>();
    final newDuration = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('調整影片時長'),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: TextFormField(
              initialValue: tempValue,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '秒數',
                helperText: '輸入影片實際秒數（正整數）',
              ),
              onChanged: (value) => tempValue = value,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                final parsed = int.tryParse(trimmed);
                if (parsed == null || parsed <= 0) {
                  return '請輸入大於 0 的秒數';
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
                final parsed = int.parse(tempValue.trim());
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );

    if (!mounted || newDuration == null) {
      debugPrint('[首頁歷史] 調整時長流程取消或頁面已卸載');
      return; // 使用者取消或未輸入
    }

    if (newDuration == entry.durationSeconds) {
      debugPrint('[首頁歷史] 秒數未變更（$newDuration 秒），略過更新');
      return; // 秒數未變更時不進行後續處理
    }

    final updatedEntries = List<RecordingHistoryEntry>.from(_recordingHistory);
    final targetIndex = updatedEntries.indexWhere((item) =>
        item.filePath == entry.filePath && item.recordedAt == entry.recordedAt);
    if (targetIndex == -1) {
      debugPrint('[首頁歷史] 找不到對應紀錄，無法更新時長');
      return; // 未找到對應項目
    }

    updatedEntries[targetIndex] =
        updatedEntries[targetIndex].copyWith(durationSeconds: newDuration);
    debugPrint('[首頁歷史] 更新索引 $targetIndex 的時長為 $newDuration 秒，準備立即寫回狀態');
    await _applyHistoryState(updatedEntries);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已更新 ${entry.displayTitle} 的時長為 $newDuration 秒')),
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

    for (final path in entry.imuCsvPaths.values) {
      if (path.isEmpty) continue;
      try {
        final csvFile = File(path);
        if (await csvFile.exists()) {
          await csvFile.delete();
        }
      } catch (_) {
        // 單筆刪除失敗可忽略
      }
    }
  }

  /// 處理底部導覽點擊，依據不同索引執行對應導覽
  void _onBottomNavTap(int index) {
    if (index == 1) {
      final practice = _practiceCount;
      final sweetPct = (_sweetSpotPercentage ?? 0).clamp(0, 100);
      final goodHits = practice > 0 ? (practice * sweetPct / 100).round() : 0;
      final badHits = math.max(practice - goodHits, 0);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TodayInfoPage(
            practiceCount: practice,
            bestSpeedMph: _bestSpeedMph,
            sweetSpotPercentage: sweetPct.toDouble(),
            audioCrispness: _audioCrispness,
            goodHits: goodHits,
            badHits: badHits,
            goodVideoPath: null,
            badVideoPath: null,
          ),
        ),
      );
      setState(() => _currentIndex = index);
      return;
    }
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecorderPage(
            cameras: widget.cameras,
            initialHistory: _recordingHistory,
            onHistoryChanged: _handleHistoryUpdated,
            userAvatarPath: _avatarPath,
          ),
        ),
      );
      return;
    }
    if (index == 3) {
      // 點選 Data Metrics 時直接導向錄影歷史頁，方便快速檢視過往紀錄
      unawaited(_openRecordingHistoryPage());
      setState(() => _currentIndex = index);
      return;
    }
    if (index == 4) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UpgradePage()),
      );
      setState(() => _currentIndex = index);
      return;
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
    // Optional: pick matching CSV
    final csvResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: '選擇對應的 IMU CSV（可略過）',
    );
    final String? imuCsvPath = csvResult?.files.single.path;

    final nextRoundIndex =
        ExternalVideoImporter.calculateNextRoundIndex(_recordingHistory);
    final entry = await _videoImporter.importVideo(
      sourcePath: path,
      originalName: fileName,
      nextRoundIndex: nextRoundIndex,
      imuCsvPath: imuCsvPath,
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

  /// 重新計算首頁儀表板指標，將 IMU CSV 中的線性加速度與旋轉資訊轉為練習洞察
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
          cloudVideoId: entry.cloudVideoId,
        ),
      ),
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
          const SizedBox(height: 16),
          _buildRecentPreviewList(),
        ],
      ),
    );
  }

  Widget _buildRecentPreviewList() {
    if (_isHistoryLoading) return const SizedBox.shrink();
    final recent = _recordingHistory.take(4).toList();
    if (recent.isEmpty) {
      return const Text('尚無影片可預覽，錄影或匯入後會出現在此處。', style: TextStyle(fontSize: 13, color: Color(0xFF6F7B86)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('最近影片預覽', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF123B70))),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = recent[index];
              final thumbPath = entry.thumbnailPath;
              final hasThumb = thumbPath != null && thumbPath.isNotEmpty && File(thumbPath).existsSync();
              return InkWell(
                onTap: () => _playHistoryEntry(entry),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 180,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE3E8EE)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: hasThumb
                            ? Image.file(
                                File(thumbPath!),
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 72,
                                height: 72,
                                color: const Color(0xFFDCE3EC),
                                child: const Icon(Icons.movie, color: Color(0xFF123B70)),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(entry.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              '${_formatDurationShort(entry.durationSeconds)} ・ ${entry.modeLabel}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
              final analyticsStatusLabel = isLoadingStats ? '載入中...' : '尚無資料';
              
              // 使用後端統計數據的最佳速度（來自 peakValue.maximum）
              final analyticsBestSpeedText = isLoadingStats
                  ? '載入中...'
                  : backendStats != null && backendStats.peakValue.maximum > 0
                      ? '${backendStats.peakValue.maximum.toStringAsFixed(1)} MPH'
                      : analyticsStatusLabel;
              
              // Sweet Spot 使用後端統計數據
              final analyticsSweetText = isLoadingStats
                  ? '載入中...'
                  : backendStats != null
                      ? '${backendStats.sweetSpotPercentage.toStringAsFixed(0)} %'
                      : analyticsStatusLabel;
              
              // Audio Crispness 使用後端統計數據
              final analyticsCrispnessText = isLoadingStats
                  ? '載入中...'
                  : backendStats != null && backendStats.audioCrispness.average > 0
                      ? '${backendStats.audioCrispness.average.toStringAsFixed(0)}'
                      : analyticsStatusLabel;

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

              return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Data Metrics',
              actions: const [],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                // 始終維持同列呈現，窄螢幕改用橫向滑動避免卡片被擠壓
                final practiceSubtitle = _practiceCount > 0
                    ? '累積完成 $_practiceCount 次錄影'
                    : '完成錄影後即可累積練習次數';
                
                // 使用後端統計數據的最佳速度
                final speedValue = isLoadingStats
                    ? '載入中...'
                    : backendStats != null && backendStats.peakValue.maximum > 0
                        ? '${backendStats.peakValue.maximum.toStringAsFixed(1)} MPH'
                        : '尚無資料';
                final speedSubtitle = isLoadingStats
                    ? '正在載入全部統計數據'
                    : backendStats != null && backendStats.peakValue.maximum > 0
                        ? '全部時間的峰值速度'
                        : '連線 IMU 錄影後即可取得數據';
                
                // 使用後端統計數據的甜蜜點命中
                final sweetValue = isLoadingStats
                    ? '載入中...'
                    : backendStats != null
                        ? '${backendStats.sweetSpotPercentage.toStringAsFixed(0)} %'
                        : '尚無資料';
                final sweetSubtitle = isLoadingStats
                    ? '正在載入全部統計數據'
                    : backendStats != null
                        ? '全部時間的甜蜜點命中率'
                        : '有 IMU 與麥克風資料後顯示';

                final cards = <Widget>[
                  _buildStatCard(
                    title: '練習次數',
                    value: '$_practiceCount 次',
                    subTitle: practiceSubtitle,
                    highlightColor: const Color(0xFF1E8E5A),
                  ),
                  _buildStatCard(
                    title: '最佳速度',
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
              actions: [
                GestureDetector(
                  onTap: () => _onBottomNavTap(3),
                  child: const Text(
                    'See all',
                    style: TextStyle(
                      color: Color(0xFF1E8E5A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
                  _SectionHeader(
                    title: 'Analytics',
                    actions: [
                      GestureDetector(
                        onTap: () {},
                        child: const Text(
                          '詳情報告',
                          style: TextStyle(
                            color: Color(0xFF1E8E5A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Best Speed', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsBestSpeedText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E8E5A),
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
                            const Text('Audio Crispness', style: TextStyle(color: Color(0xFF7D8B9A))),
                            const SizedBox(height: 6),
                            Text(
                              analyticsCrispnessText,
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
            _buildTodayInfoCard(),
            const SizedBox(height: 24),
            _buildComparisonCard(),
            const SizedBox(height: 32),
            _buildHistoryShortcutCard(),
            const SizedBox(height: 32),
          ],
        ),
      );
            },
          );
        },
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 自訂底部導覽列，模擬設計稿中的項目並保留 Quick Start 強調樣式
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
    final entrySnapshots = <_EntrySnapshot>[]; // 紀錄每筆歷史對應的分析結果

    for (final entry in entries) {
      final csvPath = _selectCsvPath(entry);
      if (csvPath == null) {
        entrySnapshots.add(_EntrySnapshot(entry: entry, snapshot: null));
        continue; // 沒有 IMU 檔案無法推算速度
      }

      final snapshot = await _analyzeCsv(csvPath);
      entrySnapshots.add(_EntrySnapshot(entry: entry, snapshot: snapshot));
      if (snapshot == null) {
        continue;
      }

      analyzedSwings++;
      if (snapshot.estimatedSpeedMph != null) {
        aggregatedSpeed += snapshot.estimatedSpeedMph!;
        speedSamples++;
        bestSpeedMph = bestSpeedMph == null
            ? snapshot.estimatedSpeedMph
      : math.max(bestSpeedMph, snapshot.estimatedSpeedMph!);
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

    // ---------- 轉換為比較所需資料：取最新與上一筆成功解析的紀錄 ----------
    final comparable = entrySnapshots
        .where((item) => item.snapshot != null)
        .toList()
      ..sort((a, b) => b.entry.recordedAt.compareTo(a.entry.recordedAt));

    _ComparisonSnapshot? comparisonAfter;
    _ComparisonSnapshot? comparisonBefore;
    if (comparable.isNotEmpty) {
      final latest = comparable.first;
      final latestCrispValue = latest.entry.audioCrispness;
      final latestCrispDouble = (latestCrispValue is int) ? (latestCrispValue as int).toDouble() : latestCrispValue as double?;
      comparisonAfter = _ComparisonSnapshot(
        entry: latest.entry,
        speedMph: latest.snapshot!.estimatedSpeedMph,
        impactClarity: latest.snapshot!.impactClarity,
        audioCrispness: latestCrispDouble,
      );
      if (comparable.length > 1) {
        final previous = comparable[1];
        final prevCrispValue = previous.entry.audioCrispness;
        final prevCrispDouble = (prevCrispValue is int) ? (prevCrispValue as int).toDouble() : prevCrispValue as double?;
        comparisonBefore = _ComparisonSnapshot(
          entry: previous.entry,
          speedMph: previous.snapshot!.estimatedSpeedMph,
          impactClarity: previous.snapshot!.impactClarity,
          audioCrispness: prevCrispDouble,
        );
      }
    }

    return _MetricsResult(
      averageSpeedMph: averageSpeed,
      bestSpeedMph: bestSpeedMph,
      consistencyScore: consistencyScore,
      averageImpactClarity: averageImpact,
      sweetSpotPercentage: sweetSpotPercentage,
      comparisonBefore: comparisonBefore,
      comparisonAfter: comparisonAfter,
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

    var lineCounter = 0; // 記錄讀取行數，定期讓出主執行緒避免阻塞
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

      // 每處理一定筆數後暫停一個事件循環，避免大量 CSV 造成 UI 卡住。
      lineCounter++;
      if (lineCounter % 400 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
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
