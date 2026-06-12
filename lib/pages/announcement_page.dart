import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/green_page_header.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  List<Announcement> _items   = [];
  Set<String>        _readIds = {};
  bool               _loading = true;
  String?            _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        AnnouncementService.instance.fetchAnnouncements(),
        AnnouncementService.instance.getReadIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _items   = results[0] as List<Announcement>;
        _readIds = results[1] as Set<String>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = AppLocalizations.of(context).annLoadFailed; });
    }
  }

  Future<void> _markAllRead() async {
    await AnnouncementService.instance.markAllAsRead(_items);
    if (!mounted) return;
    setState(() => _readIds = _items.map((a) => a.id).toSet());
  }

  Future<void> _openDetail(Announcement item) async {
    await AnnouncementService.instance.markAsRead(item.id);
    setState(() => _readIds.add(item.id));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _AnnouncementDetailPage(item: item)),
    );
  }

  int get _unreadCount => _items.where((a) => !_readIds.contains(a.id)).length;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bgPage,
      body: Column(
        children: [
          GreenPageHeader(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: kOnGradient, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: l.annBoardTitle,
            subtitle: _unreadCount > 0 ? l.annUnreadCount(_unreadCount) : l.annAllAnnouncements,
            actions: [
              if (_unreadCount > 0)
                TextButton(
                  onPressed: _markAllRead,
                  child: Text(
                    l.annMarkAllRead,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              IconButton(
                tooltip: l.annRefresh,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: _load,
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary))
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? const _EmptyView()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: kBrandPrimary,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: kSpaceMD, vertical: kSpaceSM),
                              itemCount: _items.length,
                              itemBuilder: (ctx, i) => _AnnouncementCard(
                                item:    _items[i],
                                isRead:  _readIds.contains(_items[i].id),
                                onTap:   () => _openDetail(_items[i]),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 公告 Card
// ════════════════════════════════════════════════════════════════

class _AnnouncementCard extends StatelessWidget {
  final Announcement item;
  final bool isRead;
  final VoidCallback onTap;

  const _AnnouncementCard({
    required this.item,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final type  = item.type;
    final color = type.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpaceSM),
      child: Material(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMD),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左側色條
                Container(width: 4, color: color),
                // 內容
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 類型 badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(type.icon, size: 11, color: color),
                                  const SizedBox(width: 3),
                                  Text(
                                    type.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // 未讀紅點
                            if (!isRead)
                              Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE05252),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 4),
                            // 日期
                            Text(
                              _formatDate(context, item.publishedAt),
                              style: TextStyle(
                                  fontSize: 11, color: context.textHint),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.w700,
                            color: isRead
                                ? context.textSecondary
                                : context.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          style: TextStyle(
                              fontSize: 13, color: context.textSecondary, height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_right_rounded,
                      color: context.textHint, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime dt) {
    final l    = AppLocalizations.of(context);
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return l.annMinutesAgo(diff.inMinutes);
      return l.annHoursAgo(diff.inHours);
    }
    if (diff.inDays < 7) return l.annDaysAgo(diff.inDays);
    return '${dt.month}/${dt.day}';
  }
}

// ════════════════════════════════════════════════════════════════
// 公告詳情頁
// ════════════════════════════════════════════════════════════════

class _AnnouncementDetailPage extends StatelessWidget {
  final Announcement item;
  const _AnnouncementDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context);
    final type  = item.type;
    final color = type.color;

    return Scaffold(
      backgroundColor: context.bgPage,
      body: Column(
        children: [
          GreenPageHeader(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: kOnGradient, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: l.annDetailTitle,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(kSpaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 類型 + 日期 列
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(type.icon, size: 14, color: color),
                            const SizedBox(width: 4),
                            Text(type.label,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _fullDate(item.publishedAt),
                        style: TextStyle(
                            fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 標題
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  // 色條分隔
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Container(
                      height: 3,
                      width: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // 圖片
                  if (item.imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(kRadiusMD),
                      child: Image.network(
                        item.imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // 內文
                  Text(
                    item.body,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.textPrimary,
                      height: 1.7,
                    ),
                  ),
                  if (item.expiresAt != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(kRadiusSM),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            l.annExpiresAt(_fullDate(item.expiresAt!)),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: kSpaceXL),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fullDate(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
}

// ════════════════════════════════════════════════════════════════
// 空狀態 / 錯誤狀態
// ════════════════════════════════════════════════════════════════

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, size: 64, color: context.textHint),
          const SizedBox(height: 16),
          Text(l.annEmpty,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.textSecondary)),
          const SizedBox(height: 6),
          Text(l.annEmptySubtitle,
              style: TextStyle(fontSize: 13, color: context.textHint)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 52, color: context.textHint),
          const SizedBox(height: 16),
          Text(message,
              style:
                  TextStyle(fontSize: 14, color: context.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(AppLocalizations.of(context).commonRetry),
            style: ElevatedButton.styleFrom(backgroundColor: kBrandPrimary),
          ),
        ],
      ),
    );
  }
}
