import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../services/video_server_client.dart';
import '../theme/app_theme.dart';
import '../widgets/green_page_header.dart';

// ════════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════════

class _FeedbackItem {
  final String id;
  final String type; // 'bug' | 'feature' | 'other'
  final String text;
  final String? videoId;
  final String? imageUrl;
  final String? adminReply;
  final DateTime? repliedAt;
  final DateTime createdAt;

  const _FeedbackItem({
    required this.id,
    required this.type,
    required this.text,
    this.videoId,
    this.imageUrl,
    this.adminReply,
    this.repliedAt,
    required this.createdAt,
  });

  factory _FeedbackItem.fromJson(Map<String, dynamic> m) => _FeedbackItem(
        id:         m['id'] as String? ?? '',
        type:       m['type'] as String? ?? 'other',
        text:       m['text'] as String? ?? '',
        videoId:    m['videoId'] as String?,
        imageUrl:   m['imageUrl'] as String?,
        adminReply: m['adminReply'] as String?,
        repliedAt:  DateTime.tryParse(m['repliedAt'] as String? ?? '')?.toLocal(),
        createdAt:  DateTime.tryParse(m['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

// ════════════════════════════════════════════════════════════════
// 頁面
// ════════════════════════════════════════════════════════════════

class MyFeedbackPage extends StatefulWidget {
  const MyFeedbackPage({super.key});

  @override
  State<MyFeedbackPage> createState() => _MyFeedbackPageState();
}

class _MyFeedbackPageState extends State<MyFeedbackPage> {
  static const _pageSize = 20;

  final _items   = <_FeedbackItem>[];
  int  _total    = 0;
  int  _page     = 1;
  bool _loading  = false;
  bool _hasMore  = true;
  String? _error;

  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      setState(() { _items.clear(); _page = 1; _hasMore = true; _error = null; });
    }
    setState(() => _loading = true);
    try {
      final data = await VideoServerClient.instance.getMyFeedbacks(
        page: _page, pageSize: _pageSize);
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _error   = AppLocalizations.of(context).myFeedbackLoadFailed;
          _loading = false;
        });
        return;
      }

      final rawItems = (data['items'] as List<dynamic>?) ?? [];
      final newItems = rawItems
          .map((e) => _FeedbackItem.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        if (reset) _items.clear();
        _items.addAll(newItems);
        _total   = (data['total'] as num?)?.toInt() ?? 0;
        _hasMore = _items.length < _total;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(top: false, child: Column(
        children: [
          GreenPageHeader(
            title: l.myFeedbackTitle,
            subtitle: l.myFeedbackSubtitle,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: kOnGradient, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: const [],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadMore(reset: true),
              color: kBrandPrimary,
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  if (_error != null && _items.isEmpty)
                    SliverFillRemaining(
                      child: _ErrorState(
                          message: _error!,
                          onRetry: () => _loadMore(reset: true)),
                    )
                  else if (_items.isEmpty && !_loading)
                    SliverFillRemaining(
                        child: _EmptyState(text: l.myFeedbackEmpty))
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            if (i == _items.length) {
                              return _hasMore
                                  ? const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 24),
                                      child: Center(
                                        child: Text(l.myFeedbackAllLoaded,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: context.textHint)),
                                      ),
                                    );
                            }
                            return _FeedbackTile(item: _items[i]);
                          },
                          childCount: _items.length + 1,
                        ),
                      ),
                    ),
                  ],
                  if (_loading && _items.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 單筆回饋卡片
// ════════════════════════════════════════════════════════════════

class _FeedbackTile extends StatelessWidget {
  final _FeedbackItem item;
  const _FeedbackTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final (typeLabel, typeEmoji, typeColor) = switch (item.type) {
      'bug'     => (l.myFeedbackTypeBug, '🐛', const Color(0xFFF44336)),
      'feature' => (l.myFeedbackTypeFeature, '💡', const Color(0xFFFF9800)),
      _         => (l.myFeedbackTypeOther, '💬', const Color(0xFF9C27B0)),
    };

    final timeStr = DateFormat('yyyy/MM/dd HH:mm').format(item.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 類型 badge + 時間 ───────────────────────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: typeColor.withValues(alpha: 0.3)),
                ),
                child: Text('$typeEmoji $typeLabel',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: typeColor)),
              ),
              if (item.videoId != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.videocam_rounded,
                    size: 14, color: context.textHint),
                const SizedBox(width: 2),
                Text(l.myFeedbackAttachedVideo,
                    style:
                        TextStyle(fontSize: 11, color: context.textHint)),
              ],
              const Spacer(),
              Text(timeStr,
                  style: TextStyle(fontSize: 11, color: context.textHint)),
            ],
          ),
          const SizedBox(height: 10),

          // ── 回饋內容 ───────────────────────────────────────
          Text(item.text,
              style: TextStyle(
                  fontSize: 14, height: 1.4, color: context.textPrimary)),

          // ── 附加圖片 ───────────────────────────────────────
          if (item.imageUrl != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item.imageUrl!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── 管理員回覆 / 等待回覆 ───────────────────────────
          if (item.adminReply != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kBrandPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: kBrandPrimary.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.support_agent_rounded,
                          size: 16, color: kBrandPrimary),
                      const SizedBox(width: 5),
                      Text(l.myFeedbackAdminReply,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: kBrandPrimary)),
                      const Spacer(),
                      if (item.repliedAt != null)
                        Text(
                            DateFormat('yyyy/MM/dd HH:mm')
                                .format(item.repliedAt!),
                            style: TextStyle(
                                fontSize: 10, color: context.textHint)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item.adminReply!,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: context.textPrimary)),
                ],
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.hourglass_empty_rounded,
                    size: 14, color: context.textHint),
                const SizedBox(width: 4),
                Text(l.myFeedbackNoReply,
                    style:
                        TextStyle(fontSize: 12, color: context.textHint)),
              ],
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 空狀態 / 錯誤狀態
// ════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.feedback_outlined, size: 56, color: context.textHint),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(fontSize: 15, color: context.textHint)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: context.textHint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
