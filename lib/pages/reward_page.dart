import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/recording_history_entry.dart';
import '../services/ad_service.dart';
import '../services/recording_history_storage.dart';
import '../services/reward_service.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';
import '../widgets/green_page_header.dart';

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
      backgroundColor: const Color(0xFFF4F6F9),
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
            actions: const [],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          _StatCell(label: '累積獎勵', value: '${status.bonusBalls}', unit: '球', color: kPrimaryGreen),
          _divider(),
          _StatCell(label: '今日廣告', value: '${status.adClaimedToday}', unit: '/ 5 次', color: const Color(0xFF4285F4)),
          _divider(),
          _StatCell(label: '邀請好友', value: '${status.inviteCount}', unit: '位', color: const Color(0xFFFF6B35)),
        ],
      ),
    );
  }

  Widget _divider() => Container(height: 36, width: 1, color: Colors.grey[200], margin: const EdgeInsets.symmetric(horizontal: 12));
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
              TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ]),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
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
                      Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
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
                      backgroundColor: Colors.grey[200],
                      color: iconBg,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${usedToday ?? 0} / $dailyCap 次', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                height: 42,
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (claimed)
                              const Icon(Icons.check_circle_rounded, size: 16)
                            else
                              Icon(icon, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              claimed ? '今日已完成' : (buttonLabel ?? ''),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
      final rewarded = await AdService.showRewardedAd();
      if (!rewarded) {
        widget.onError('請看完廣告才能獲得獎勵');
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
                    Text('你的邀請碼', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3EE),
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
          Icon(Icons.person_search_rounded, size: 36, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text('尚無邀請紀錄', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          const SizedBox(height: 4),
          Text('分享你的邀請碼，邀請好友一起練習！',
              style: TextStyle(fontSize: 11, color: Colors.grey[400])),
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
            if (i > 0) Divider(height: 1, color: Colors.grey[100]),
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
                    Icon(Icons.calendar_today_rounded, size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 3),
                    Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
          ),

          // 獎勵球數徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3EE),
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
// 3. 問題回饋
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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      widget.onError('請輸入回饋內容');
      return;
    }
    setState(() => _busy = true);
    try {
      final balls = await RewardService.submitFeedback(type: _type, text: text);
      _ctrl.clear();
      setState(() => _expanded = false);
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
                Row(
                  children: [
                    _TypeChip(label: '🐛 問題回報', value: 'bug',     selected: _type, onTap: (v) => setState(() => _type = v)),
                    const SizedBox(width: 8),
                    _TypeChip(label: '💡 功能建議', value: 'feature', selected: _type, onTap: (v) => setState(() => _type = v)),
                    const SizedBox(width: 8),
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
                    fillColor: const Color(0xFFF9F4FC),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _expanded = false),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 38,
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
          color: isSelected ? const Color(0xFF9C27B0).withValues(alpha: 0.12) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF9C27B0) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? const Color(0xFF9C27B0) : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 4. 上傳資料
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
  bool _busy = false;
  int _sessionCount = 0;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _countSessions();
  }

  Future<void> _countSessions() async {
    try {
      final all = await RecordingHistoryStorage.instance.loadHistory();
      // 只上傳已分析的短片（有實際分析資料的才有價值）
      final uploadable = all.where((e) => e.isAnalyzed).length;
      if (mounted) setState(() { _sessionCount = uploadable; _counted = true; });
    } catch (_) {
      if (mounted) setState(() => _counted = true);
    }
  }

  Future<List<Map<String, dynamic>>> _buildPayload() async {
    final all = await RecordingHistoryStorage.instance.loadHistory();
    return all
        .where((e) => e.isAnalyzed)
        .map((e) => _entryToJson(e))
        .toList();
  }

  Map<String, dynamic> _entryToJson(RecordingHistoryEntry e) => {
    'filePath':        e.filePath,
    'recordedAt':      e.recordedAt.toIso8601String(),
    'durationSeconds': e.durationSeconds,
    'goodShot':        e.goodShot,
    'audioCrispness':  e.audioCrispness,
    'audioLabel':      e.audioLabel,
    'videoType':       e.videoType.name,
  };

  Future<void> _upload() async {
    if (_sessionCount == 0) {
      widget.onError('目前沒有可上傳的分析資料');
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = await _buildPayload();
      final balls = await RewardService.claimUploadReward(sessions: payload);
      widget.onEarned(balls);
    } catch (e) {
      widget.onError('上傳失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RewardCard(
      iconBg: const Color(0xFF00897B),
      icon: Icons.cloud_upload_rounded,
      title: '上傳分析資料',
      description: RewardType.uploadData.description,
      balls: RewardType.uploadData.ballsPerAction,
      bottomWidget: _counted
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.analytics_rounded, color: Color(0xFF00897B), size: 18),
                const SizedBox(width: 8),
                Text(
                  '可上傳 $_sessionCount 筆已分析錄影記錄',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF00695C)),
                ),
              ]),
            )
          : const SizedBox(
              height: 32,
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
      buttonLabel: '上傳資料 +${RewardType.uploadData.ballsPerAction} 球',
      buttonBusy: _busy,
      onTap: _sessionCount > 0 ? _upload : null,
    );
  }
}
