import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import '../services/ad_service.dart';
import '../services/recording_history_storage.dart';
import '../services/reward_service.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';
import '../widgets/green_page_header.dart';
import 'usage_history_page.dart';

// ════════════════════════════════════════════════════════════════
// RewardPage
// ════════════════════════════════════════════════════════════════

class RewardPage extends StatefulWidget {
  const RewardPage({super.key});

  @override
  State<RewardPage> createState() => _RewardPageState();
}

class _RewardPageState extends State<RewardPage> {
  RewardStatus _status = const RewardStatus();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await RewardService.getStatus();
      if (mounted) setState(() { _status = s; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showEarned(int balls, String source) {
    if (balls <= 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Text('🎯 ', style: TextStyle(fontSize: 18)),
          Text('透過「$source」獲得 +$balls 額外球數！'),
        ]),
        backgroundColor: kPrimaryGreen,
        duration: const Duration(seconds: 3),
      ),
    );
    _load(); // 重整狀態
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: Column(
        children: [
          GreenPageHeader(
            title: '獎勵球數',
            subtitle: _loading
                ? '載入中...'
                : '累積獎勵：${_status.bonusBalls} 球',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                tooltip: '使用紀錄',
                icon: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 22),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const UsageHistoryPage()),
                ),
              ),
            ],
          ),

          // ── 球數統計卡 ─────────────────────────────────────────
          if (!_loading) _BonusSummaryBar(status: _status),

          // ── 獎勵卡列表 ─────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: kPrimaryGreen,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _WatchAdCard(
                    status: _status,
                    onEarned: (b) => _showEarned(b, '看廣告'),
                    onError: _showError,
                  ),
                  const SizedBox(height: 12),
                  _InviteCard(
                    status: _status,
                    onError: _showError,
                    onRefresh: _load,
                  ),
                  const SizedBox(height: 12),

                  // 輸入邀請碼（未套用過才顯示）
                  if (!_status.hasAppliedInviteCode) ...[
                    _EnterInviteCodeCard(
                      onEarned: (b) => _showEarned(b, '輸入邀請碼'),
                      onError: _showError,
                      onApplied: _load,
                    ),
                    const SizedBox(height: 12),
                  ],

                  _FeedbackCard(
                    status: _status,
                    onEarned: (b) => _showEarned(b, '問題回饋'),
                    onError: _showError,
                  ),
                  const SizedBox(height: 12),
                  _UploadCard(
                    status: _status,
                    onEarned: (b) => _showEarned(b, '上傳資料'),
                    onError: _showError,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 頂部統計列
// ════════════════════════════════════════════════════════════════

class _BonusSummaryBar extends StatelessWidget {
  final RewardStatus status;
  const _BonusSummaryBar({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        children: [
          _StatCell(label: '累積獎勵', value: '${status.bonusBalls}', unit: '球', color: kPrimaryGreen),
          _divider(context),
          _StatCell(label: '今日廣告', value: '${status.adClaimedToday}', unit: '/ 5 次', color: const Color(0xFF4285F4)),
          _divider(context),
          _StatCell(label: '邀請好友', value: '${status.inviteCount}', unit: '位', color: const Color(0xFFFF6B35)),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(height: 36, width: 1, color: context.borderColor, margin: const EdgeInsets.symmetric(horizontal: 12));
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _StatCell({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            text: TextSpan(children: [
              TextSpan(text: value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: context.textSecondary)),
            ]),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: context.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 基礎獎勵卡框架
// ════════════════════════════════════════════════════════════════

class _RewardCard extends StatelessWidget {
  final Color iconBg;
  final IconData icon;
  final String title;
  final String description;
  final int balls;
  final int? dailyCap;
  final int? usedToday;
  final bool claimed;
  final Widget? bottomWidget;
  final String? buttonLabel;
  final bool buttonBusy;
  final VoidCallback? onTap;

  const _RewardCard({
    required this.iconBg,
    required this.icon,
    required this.title,
    required this.description,
    required this.balls,
    this.dailyCap,
    this.usedToday,
    this.claimed = false,
    this.bottomWidget,
    this.buttonLabel,
    this.buttonBusy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAction = buttonLabel != null;
    final isAvailable = !claimed && onTap != null;

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 圖示
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                // 標題 + 描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 球數徽章
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: iconBg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: iconBg.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '+$balls 球',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: iconBg),
                  ),
                ),
              ],
            ),

            // 每日進度條（僅廣告有 cap）
            if (dailyCap != null && dailyCap! > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (usedToday ?? 0) / dailyCap!,
                      backgroundColor: context.bgInset,
                      color: iconBg,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${usedToday ?? 0} / $dailyCap 次', style: TextStyle(fontSize: 11, color: context.textSecondary)),
                ],
              ),
            ],

            // 子 widget（邀請碼、回饋表單…）
            if (bottomWidget != null) ...[
              const SizedBox(height: 12),
              bottomWidget!,
            ],

            // 按鈕
            if (hasAction) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (isAvailable && !buttonBusy) ? onTap : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAvailable ? iconBg : Colors.grey[300],
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    disabledBackgroundColor: Colors.grey[200],
                    disabledForegroundColor: Colors.grey[400],
                  ),
                  child: buttonBusy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (claimed)
                              const Icon(Icons.check_circle_rounded, size: 16)
                            else
                              Icon(icon, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                claimed ? '今日已完成' : (buttonLabel ?? ''),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 1. 看廣告
// ════════════════════════════════════════════════════════════════

class _WatchAdCard extends StatefulWidget {
  final RewardStatus status;
  final void Function(int balls) onEarned;
  final void Function(String) onError;

  const _WatchAdCard({required this.status, required this.onEarned, required this.onError});

  @override
  State<_WatchAdCard> createState() => _WatchAdCardState();
}

class _WatchAdCardState extends State<_WatchAdCard> {
  bool _busy = false;

  Future<void> _onTap() async {
    setState(() => _busy = true);
    try {
      final rewarded = await AdService.showRewardedAiCoach();
      if (!rewarded) {
        widget.onError('廣告未播放完成或暫時無法載入，請稍後再試');
        return;
      }
      final balls = await RewardService.claimAdReward();
      widget.onEarned(balls);
    } catch (e) {
      widget.onError('廣告獎勵失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    return _RewardCard(
      iconBg: const Color(0xFF4285F4),
      icon: Icons.play_circle_filled_rounded,
      title: '看廣告',
      description: RewardType.watchAd.description,
      balls: RewardType.watchAd.ballsPerAction,
      dailyCap: RewardType.watchAd.dailyCap,
      usedToday: s.adClaimedToday,
      claimed: !s.canWatchAd,
      buttonLabel: '觀看廣告 +${RewardType.watchAd.ballsPerAction} 球',
      buttonBusy: _busy,
      onTap: _onTap,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 2. 邀請好友
// ════════════════════════════════════════════════════════════════

class _InviteCard extends StatefulWidget {
  final RewardStatus status;
  final void Function(String) onError;
  final VoidCallback onRefresh;

  const _InviteCard({required this.status, required this.onError, required this.onRefresh});

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  String? _code;
  bool _loadingCode = false;

  // 已邀請好友列表
  bool _friendsExpanded = false;
  bool _loadingFriends  = false;
  List<_InvitedFriend> _friends = [];
  bool _friendsLoaded   = false;

  @override
  void initState() {
    super.initState();
    _code = widget.status.inviteCode;
    if (_code == null) _fetchCode();
  }

  Future<void> _fetchCode() async {
    setState(() => _loadingCode = true);
    try {
      final code = await RewardService.getInviteCode();
      if (mounted) setState(() { _code = code; _loadingCode = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCode = false);
    }
  }

  Future<void> _toggleFriends() async {
    if (_friendsExpanded) {
      setState(() => _friendsExpanded = false);
      return;
    }
    setState(() { _friendsExpanded = true; });
    if (_friendsLoaded) return; // 已載入過，直接展開
    setState(() => _loadingFriends = true);
    try {
      final data = await VideoServerClient.instance.getInvitedFriends();
      if (!mounted) return;
      final rawList = (data?['friends'] as List<dynamic>?) ?? [];
      _friends = rawList.map((e) {
        final m = e as Map<String, dynamic>;
        return _InvitedFriend(
          displayName: m['displayName'] as String? ?? '好友',
          avatarUrl:   m['avatarUrl']   as String?,
          joinedAt:    DateTime.tryParse(m['joinedAt'] as String? ?? '') ?? DateTime.now(),
          ballsEarned: (m['ballsEarned'] as num?)?.toInt() ?? 0,
        );
      }).toList();
      setState(() { _loadingFriends = false; _friendsLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  void _copyCode() {
    if (_code == null) return;
    Clipboard.setData(ClipboardData(text: _code!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邀請碼已複製'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    return _RewardCard(
      iconBg: const Color(0xFFFF6B35),
      icon: Icons.group_add_rounded,
      title: '邀請好友',
      description: '好友使用邀請碼註冊後，你獲得 +${RewardType.inviteFriend.ballsPerAction} 球，好友也獲得 +${RewardType.inviteFriend.ballsPerAction} 球',
      balls: RewardType.inviteFriend.ballsPerAction,
      bottomWidget: _loadingCode
          ? const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ))
          : _code == null
              ? TextButton.icon(
                  onPressed: _fetchCode,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('取得邀請碼'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 邀請碼顯示 ────────────────────────────────
                    Text('你的邀請碼', style: TextStyle(fontSize: 11, color: context.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.isDarkMode
                  ? const Color(0xFFFF6B35).withValues(alpha: 0.16)
                  : const Color(0xFFFFF3EE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _code!,
                              style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold,
                                letterSpacing: 4, color: Color(0xFFE55A1C),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _copyCode,
                            child: const Icon(Icons.copy_rounded, color: Color(0xFFFF6B35), size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── 已邀請好友列表折疊列 ─────────────────────
                    InkWell(
                      onTap: _toggleFriends,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFFFF6B35)),
                            const SizedBox(width: 6),
                            Text(
                              '已邀請好友',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFE55A1C)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${s.inviteCount} 位',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE55A1C)),
                              ),
                            ),
                            const Spacer(),
                            AnimatedRotation(
                              turns: _friendsExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFFFF6B35)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── 展開的好友列表 ───────────────────────────
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: _friendsExpanded
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _loadingFriends
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B35))),
                                      ),
                                    )
                                  : _friends.isEmpty
                                      ? _EmptyFriendsList()
                                      : _FriendsList(friends: _friends),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
    );
  }
}

// ── 資料模型 ─────────────────────────────────────────────────────

class _InvitedFriend {
  final String displayName;
  final String? avatarUrl;
  final DateTime joinedAt;
  final int ballsEarned;
  const _InvitedFriend({
    required this.displayName,
    this.avatarUrl,
    required this.joinedAt,
    required this.ballsEarned,
  });
}

// ── 空狀態 ───────────────────────────────────────────────────────

class _EmptyFriendsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.person_search_rounded, size: 36, color: context.textHint),
          const SizedBox(height: 8),
          Text('尚無邀請紀錄', style: TextStyle(fontSize: 13, color: context.textHint)),
          const SizedBox(height: 4),
          Text('分享你的邀請碼，邀請好友一起練習！',
              style: TextStyle(fontSize: 11, color: context.textHint)),
        ],
      ),
    );
  }
}

// ── 好友列表 ─────────────────────────────────────────────────────

class _FriendsList extends StatelessWidget {
  final List<_InvitedFriend> friends;
  const _FriendsList({required this.friends});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: friends.asMap().entries.map((entry) {
        final i = entry.key;
        final f = entry.value;
        return Column(
          children: [
            if (i > 0) Divider(height: 1, color: context.borderColor),
            _FriendTile(friend: f, index: i + 1),
          ],
        );
      }).toList(),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final _InvitedFriend friend;
  final int index;
  const _FriendTile({required this.friend, required this.index});

  @override
  Widget build(BuildContext context) {
    final initials = friend.displayName.isNotEmpty
        ? friend.displayName.characters.first.toUpperCase()
        : '?';
    final dateStr = DateFormat('yyyy/MM/dd').format(friend.joinedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Row(
        children: [
          // 序號 + 大頭貼
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFFFE0D0),
                backgroundImage: friend.avatarUrl != null ? NetworkImage(friend.avatarUrl!) : null,
                child: friend.avatarUrl == null
                    ? Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFE55A1C)))
                    : null,
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B35),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('$index', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // 名稱 + 日期
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.displayName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 11, color: context.textHint),
                    const SizedBox(width: 3),
                    Text(dateStr, style: TextStyle(fontSize: 11, color: context.textSecondary)),
                  ],
                ),
              ],
            ),
          ),

          // 獎勵球數徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? const Color(0xFFFF6B35).withValues(alpha: 0.16)
                  : const Color(0xFFFFF3EE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⛳', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 3),
                Text(
                  '+${friend.ballsEarned}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE55A1C)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 3. 輸入邀請碼（被邀請方）
// ════════════════════════════════════════════════════════════════

class _EnterInviteCodeCard extends StatefulWidget {
  final void Function(int balls) onEarned;
  final void Function(String) onError;
  final VoidCallback onApplied;

  const _EnterInviteCodeCard({
    required this.onEarned,
    required this.onError,
    required this.onApplied,
  });

  @override
  State<_EnterInviteCodeCard> createState() => _EnterInviteCodeCardState();
}

class _EnterInviteCodeCardState extends State<_EnterInviteCodeCard> {
  bool _expanded = false;
  bool _busy     = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) { widget.onError('請輸入邀請碼'); return; }

    setState(() => _busy = true);
    try {
      final r = await RewardService.applyInviteCode(code);
      if (!mounted) return;
      if (r.success) {
        _ctrl.clear();
        setState(() { _expanded = false; });
        widget.onEarned(r.balls);
        widget.onApplied(); // 刷新狀態，卡片消失
      } else {
        widget.onError(r.message.isNotEmpty ? r.message : '邀請碼無效');
      }
    } catch (e) {
      if (mounted) widget.onError('套用失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RewardCard(
      iconBg: const Color(0xFF7B61FF),
      icon: Icons.card_giftcard_rounded,
      title: '輸入邀請碼',
      description: '輸入好友的邀請碼，你獲得 +${RewardType.inviteFriend.ballsPerAction} 球，好友也獲得 +${RewardType.inviteFriend.ballsPerAction} 球',
      balls: RewardType.inviteFriend.ballsPerAction,
      bottomWidget: _expanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 12,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: Color(0xFF5B42D6),
                  ),
                  decoration: InputDecoration(
                    hintText: 'ABCD1234',
                    hintStyle: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 18,
                      letterSpacing: 3,
                    ),
                    filled: true,
                    fillColor: context.isDarkMode
                        ? const Color(0xFFB39DDB).withValues(alpha: 0.14)
                        : const Color(0xFFF3F0FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFB39DDB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF7B61FF), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFD1C4E9)),
                    ),
                    prefixIcon: const Icon(Icons.vpn_key_rounded, color: Color(0xFF7B61FF), size: 20),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => setState(() { _expanded = false; _ctrl.clear(); }),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_rounded, size: 16),
                        label: Text(_busy ? '套用中...' : '套用 +${RewardType.inviteFriend.ballsPerAction} 球'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B61FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      buttonLabel: _expanded ? null : '輸入好友邀請碼',
      onTap: () => setState(() => _expanded = true),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 4. 問題回饋
// ════════════════════════════════════════════════════════════════

class _FeedbackCard extends StatefulWidget {
  final RewardStatus status;
  final void Function(int balls) onEarned;
  final void Function(String) onError;

  const _FeedbackCard({required this.status, required this.onEarned, required this.onError});

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  String _type = 'bug';
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _expanded = false;

  RecordingHistoryEntry? _selectedVideo;
  File? _selectedImageFile;
  Uint8List? _previewImageBytes;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 從歷史錄影選取影片
  Future<void> _pickVideo() async {
    final entries = await RecordingHistoryStorage.instance.loadHistory();
    if (!mounted) return;
    final picked = await showModalBottomSheet<RecordingHistoryEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VideoPickerSheet(entries: entries),
    );
    if (picked != null) {
      setState(() => _selectedVideo = picked);
    }
  }

  /// 從相簿/檔案選取圖片並壓縮
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      final decoded = await Isolate.run(() => _decodeAndCompress(bytes));
      if (mounted) {
        setState(() {
          _selectedImageFile = file;
          _previewImageBytes = decoded;
        });
      }
    } catch (e) {
      debugPrint('[圖片壓縮] 錯誤: $e');
      if (mounted) {
        setState(() {
          _selectedImageFile = file;
          _previewImageBytes = null;
        });
      }
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      widget.onError('請輸入回饋內容');
      return;
    }
    setState(() => _busy = true);
    try {
      // 附加影片 Session ID
      String? videoId;
      if (_selectedVideo != null) {
        videoId = p.basename(p.dirname(_selectedVideo!.filePath));
      }
      // 附加圖片：上傳至 B2，取得 imageId
      String? imageB2Key;
      if (_previewImageBytes != null) {
        final urlData = await VideoServerClient.instance.getFeedbackImageUploadUrl();
        if (urlData != null) {
          final uploadUrl = urlData['uploadUrl'] as String?;
          final imageId   = urlData['imageId'] as String?;
          if (uploadUrl != null && imageId != null) {
            final uploadResp = await http.put(
              Uri.parse(uploadUrl),
              headers: {'Content-Type': 'image/jpeg'},
              body: _previewImageBytes,
            );
            if (uploadResp.statusCode == 200) {
              imageB2Key = imageId;
              debugPrint('[回饋圖片] ✅ 上傳至 B2: $imageId');
            } else {
              debugPrint('[回饋圖片] ❌ B2 上傳失敗: ${uploadResp.statusCode}');
            }
          }
        }
      }

      final balls = await RewardService.submitFeedback(
        type: _type,
        text: text,
        videoId: videoId,
        imageB2Key: imageB2Key,
      );
      _ctrl.clear();
      setState(() {
        _expanded = false;
        _selectedVideo = null;
        _selectedImageFile = null;
        _previewImageBytes = null;
      });
      widget.onEarned(balls);
    } catch (e) {
      widget.onError('提交失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claimed = widget.status.feedbackClaimedToday;
    return _RewardCard(
      iconBg: const Color(0xFF9C27B0),
      icon: Icons.feedback_rounded,
      title: '問題回饋',
      description: RewardType.submitFeedback.description,
      balls: RewardType.submitFeedback.ballsPerAction,
      claimed: claimed,
      bottomWidget: _expanded && !claimed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 12),
                // 類型選擇
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _TypeChip(label: '🐛 問題回報', value: 'bug',     selected: _type, onTap: (v) => setState(() => _type = v)),
                    _TypeChip(label: '💡 功能建議', value: 'feature', selected: _type, onTap: (v) => setState(() => _type = v)),
                    _TypeChip(label: '💬 其他',    value: 'other',   selected: _type, onTap: (v) => setState(() => _type = v)),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrl,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: '請詳細描述你的回饋...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    filled: true,
                    fillColor: context.isDarkMode
                        ? const Color(0xFFCE93D8).withValues(alpha: 0.14)
                        : const Color(0xFFF9F4FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCE93D8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF9C27B0), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE1BEE7)),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    counterStyle: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ),
                const SizedBox(height: 10),
                // ── 附件按鈕列 ─────────────────────────────────
                Row(
                  children: [
                    _attachBtn(
                      icon: Icons.videocam_rounded,
                      label: _selectedVideo == null ? '選擇影片' : '更換影片',
                      onTap: _pickVideo,
                    ),
                    const SizedBox(width: 8),
                    _attachBtn(
                      icon: Icons.image_rounded,
                      label: _selectedImageFile == null ? '上傳圖片' : '更換圖片',
                      onTap: _pickImage,
                    ),
                  ],
                ),
                // ── 已選影片 chip ──────────────────────────────
                if (_selectedVideo != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? const Color(0xFFCE93D8).withValues(alpha: 0.16)
                          : const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCE93D8)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.videocam_rounded,
                            size: 14, color: Color(0xFF9C27B0)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selectedVideo!.displayTitle,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF7B1FA2)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _selectedVideo = null),
                          child: const Icon(Icons.close,
                              size: 14, color: Color(0xFF9C27B0)),
                        ),
                      ],
                    ),
                  ),
                ],
                // ── 已選圖片預覽 ───────────────────────────────
                if (_previewImageBytes != null) ...[
                  const SizedBox(height: 8),
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _previewImageBytes!,
                          height: 110,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedImageFile = null;
                            _previewImageBytes = null;
                          }),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (_selectedImageFile != null) ...[
                  // 圖片壓縮失敗時顯示路徑
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? const Color(0xFFCE93D8).withValues(alpha: 0.16)
                          : const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCE93D8)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.image_rounded,
                            size: 14, color: Color(0xFF9C27B0)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            p.basename(_selectedImageFile!.path),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF7B1FA2)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _selectedImageFile = null;
                            _previewImageBytes = null;
                          }),
                          child: const Icon(Icons.close,
                              size: 14, color: Color(0xFF9C27B0)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _expanded = false),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9C27B0),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('送出回饋 +${RewardType.submitFeedback.ballsPerAction} 球'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      buttonLabel: claimed ? null : (_expanded ? null : '填寫回饋 +${RewardType.submitFeedback.ballsPerAction} 球'),
      buttonBusy: _busy,
      onTap: claimed ? null : () => setState(() => _expanded = true),
    );
  }

  Widget _attachBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF9C27B0),
          side: const BorderSide(color: Color(0xFFCE93D8)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
}

/// 背景 isolate：解碼並壓縮圖片至最大 1024px / JPEG Q75
Uint8List _decodeAndCompress(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final resized = decoded.width > 1024
      ? img.copyResize(decoded, width: 1024)
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
}

class _TypeChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  const _TypeChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9C27B0).withValues(alpha: 0.12) : context.bgInset,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF9C27B0) : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? const Color(0xFF9C27B0) : context.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 影片選擇器底部彈出
// ════════════════════════════════════════════════════════════════

class _VideoPickerSheet extends StatelessWidget {
  final List<RecordingHistoryEntry> entries;
  const _VideoPickerSheet({required this.entries});

  @override
  Widget build(BuildContext context) {
    final usable = entries
        .where((e) => e.videoType == VideoType.original)
        .toList()
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖曳把手
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.videocam_rounded,
                    color: Color(0xFF9C27B0), size: 18),
                const SizedBox(width: 8),
                Text('選擇影片',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (usable.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('尚無歷史錄影',
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
            )
          else
            Flexible(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shrinkWrap: true,
                itemCount: usable.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final e = usable[index];
                  final dur = e.durationSeconds;
                  final durStr = dur >= 60
                      ? '${dur ~/ 60}m${dur % 60}s'
                      : '${dur}s';
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(e),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          // 縮圖
                          _MiniThumb(thumbnailPath: e.thumbnailPath),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.displayTitle,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$durStr · ${e.durationSeconds > 5 && e.durationSeconds <= 600 ? '長影片' : '短影片'}',
                                  style: TextStyle(
                                      fontSize: 11, color: context.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: context.textHint, size: 18),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 極小縮圖（影片選擇器用）
class _MiniThumb extends StatelessWidget {
  final String? thumbnailPath;
  const _MiniThumb({this.thumbnailPath});

  @override
  Widget build(BuildContext context) {
    final path = thumbnailPath?.trim() ?? '';
    final has = path.isNotEmpty && File(path).existsSync();
    if (has) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(path),
            width: 52, height: 36, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 52,
      height: 36,
      decoration: BoxDecoration(
        color: context.bgInset,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.videocam_outlined,
          size: 18, color: context.textHint),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 5. 上傳分析資料（手動選擇）
// ════════════════════════════════════════════════════════════════

class _UploadCard extends StatefulWidget {
  final RewardStatus status;
  final void Function(int balls) onEarned;
  final void Function(String) onError;

  const _UploadCard({required this.status, required this.onEarned, required this.onError});

  @override
  State<_UploadCard> createState() => _UploadCardState();
}

class _UploadCardState extends State<_UploadCard> {
  bool _busy         = false;
  bool _loaded       = false;
  List<RecordingHistoryEntry> _uploadable = [];   // 可選取
  int  _alreadyCount = 0;                          // 已上傳數

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final all = await RecordingHistoryStorage.instance.loadHistory();
      final uploadable  = all.where((e) => e.isAnalyzed && !e.isEffectivelyUploaded).toList();
      final alreadyDone = all.where((e) => e.isEffectivelyUploaded).length;
      if (mounted) {
        setState(() {
          _uploadable   = uploadable;
          _alreadyCount = alreadyDone;
          _loaded       = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loaded = true);
      }
    }
  }

  Future<void> _openPicker() async {
    if (_uploadable.isEmpty) {
      widget.onError('目前沒有可上傳的分析資料');
      return;
    }
    if (!mounted) return;

    final selected = await showModalBottomSheet<List<RecordingHistoryEntry>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadPickerSheet(candidates: _uploadable),
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final payload = selected.map(_entryToJson).toList();
      final balls   = await RewardService.claimUploadReward(sessions: payload);

      // 標記為已上傳，精確更新各筆記錄
      for (final e in selected) {
        await RecordingHistoryStorage.instance.upsertEntry(
          e.copyWith(isUploaded: true),
        );
      }

      // 重新計算可上傳數
      await _loadCandidates();

      if (mounted) widget.onEarned(balls);
    } catch (e) {
      if (mounted) widget.onError('上傳失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Map<String, dynamic> _entryToJson(RecordingHistoryEntry e) => {
    'filePath':        e.filePath,
    'recordedAt':      e.recordedAt.toIso8601String(),
    'durationSeconds': e.durationSeconds,
    'goodShot':        e.goodShot,
    'audioCrispness':  e.audioCrispness,
    'audioLabel':      e.audioLabel,
    'videoType':       e.videoType.name,
  };

  @override
  Widget build(BuildContext context) {
    final canUpload = _uploadable.isNotEmpty;

    return _RewardCard(
      iconBg: const Color(0xFF00897B),
      icon: Icons.cloud_upload_rounded,
      title: '上傳分析資料',
      description: RewardType.uploadData.description,
      balls: RewardType.uploadData.ballsPerAction,
      bottomWidget: !_loaded
          ? const SizedBox(
              height: 32,
              child: Center(child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.isDarkMode
                    ? const Color(0xFF00897B).withValues(alpha: 0.18)
                    : const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.analytics_rounded,
                    color: Color(0xFF00897B), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    canUpload
                        ? '可上傳 ${_uploadable.length} 筆，已上傳 $_alreadyCount 筆'
                        : '所有分析資料已上傳（共 $_alreadyCount 筆）',
                    style: TextStyle(
                        fontSize: 12,
                        color: canUpload
                            ? const Color(0xFF00695C)
                            : context.textSecondary),
                  ),
                ),
              ]),
            ),
      buttonLabel: canUpload ? '選擇要上傳的錄影' : null,
      buttonBusy: _busy,
      onTap: canUpload ? _openPicker : null,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 上傳選擇器 Bottom Sheet（多選）
// ════════════════════════════════════════════════════════════════

class _UploadPickerSheet extends StatefulWidget {
  final List<RecordingHistoryEntry> candidates;
  const _UploadPickerSheet({required this.candidates});

  @override
  State<_UploadPickerSheet> createState() => _UploadPickerSheetState();
}

class _UploadPickerSheetState extends State<_UploadPickerSheet> {
  String? _selectedPath;

  void _select(String path) => setState(() => _selectedPath = path);

  void _confirm() {
    final result = widget.candidates
        .where((e) => e.filePath == _selectedPath)
        .toList();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize:     0.40,
      maxChildSize:     0.90,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 把手
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 標題列
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_rounded,
                      color: Color(0xFF00897B), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('選擇要上傳的錄影',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary)),
                        Text('選擇一筆後按「確認上傳」獲得獎勵',
                            style: TextStyle(
                                fontSize: 12, color: context.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // 列表
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                itemCount: widget.candidates.length,
                itemBuilder: (_, i) {
                  final e   = widget.candidates[i];
                  final sel = e.filePath == _selectedPath;
                  return _UploadCandidateTile(
                    entry:    e,
                    selected: sel,
                    onTap:    () => _select(e.filePath),
                  );
                },
              ),
            ),

            // 底部確認列
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Text(
                      _selectedPath == null ? '尚未選擇' : '已選 1 筆',
                      style: TextStyle(
                          fontSize: 13, color: context.textSecondary),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _selectedPath == null ? null : _confirm,
                      icon: const Icon(Icons.upload_rounded, size: 16),
                      label: Text(
                          '確認上傳 +${RewardType.uploadData.ballsPerAction} 球'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 單筆候選卡片 ──────────────────────────────────────────────────

class _UploadCandidateTile extends StatelessWidget {
  final RecordingHistoryEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _UploadCandidateTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF00897B);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.06)
              : context.bgCard,
          border: Border.all(
            color: selected ? color : context.borderColor,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Radio
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: selected ? color : Colors.transparent,
                border: Border.all(
                  color: selected ? color : context.textHint,
                  width: 1.5,
                ),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(Icons.circle, color: Colors.white, size: 10)
                  : null,
            ),
            const SizedBox(width: 10),

            // 縮圖
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: _buildThumb(context),
            ),
            const SizedBox(width: 10),

            // 文字資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayTitle,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.access_time_rounded,
                        size: 11, color: context.textHint),
                    const SizedBox(width: 3),
                    Text('${entry.durationSeconds} 秒',
                        style: TextStyle(
                            fontSize: 11, color: context.textSecondary)),
                    if (entry.isAnalyzed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('已分析',
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF00695C),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (entry.goodShot == true) ...[
                      const SizedBox(width: 6),
                      const Text('⛳', style: TextStyle(fontSize: 11)),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb(BuildContext context) {
    final tp = entry.thumbnailPath;
    if (tp != null && File(tp).existsSync()) {
      return Image.file(File(tp),
          width: 56, height: 42, fit: BoxFit.cover);
    }
    return Container(
      width: 56, height: 42,
      color: context.bgInset,
      child: Icon(Icons.videocam_rounded,
          color: context.textHint, size: 22),
    );
  }
}
