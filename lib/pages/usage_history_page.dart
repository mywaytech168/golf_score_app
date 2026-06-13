import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';
import '../widgets/green_page_header.dart';

// ════════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════════

class _AnalysisRecord {
  final String id;
  final String source; // 'daily_quota' | 'bonus_ball'
  final int ballsSpent;
  final DateTime usedAt;

  const _AnalysisRecord({
    required this.id,
    required this.source,
    required this.ballsSpent,
    required this.usedAt,
  });

  factory _AnalysisRecord.fromJson(Map<String, dynamic> m) => _AnalysisRecord(
        id:         m['id'] as String? ?? '',
        source:     m['source'] as String? ?? '',
        ballsSpent: (m['ballsSpent'] as num?)?.toInt() ?? 0,
        usedAt:     DateTime.tryParse(m['usedAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class _BallRecord {
  final String id;
  final String reason; // 'ad'|'feedback'|'invite'|'upload'|'analysis'|'manual'
  final int delta;
  final int balanceAfter;
  final DateTime createdAt;

  const _BallRecord({
    required this.id,
    required this.reason,
    required this.delta,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory _BallRecord.fromJson(Map<String, dynamic> m) => _BallRecord(
        id:           m['id'] as String? ?? '',
        reason:       m['reason'] as String? ?? '',
        delta:        (m['delta'] as num?)?.toInt() ?? 0,
        balanceAfter: (m['balanceAfter'] as num?)?.toInt() ?? 0,
        createdAt:    DateTime.tryParse(m['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

// ════════════════════════════════════════════════════════════════
// 頁面
// ════════════════════════════════════════════════════════════════

class UsageHistoryPage extends StatefulWidget {
  const UsageHistoryPage({super.key});

  @override
  State<UsageHistoryPage> createState() => _UsageHistoryPageState();
}

class _UsageHistoryPageState extends State<UsageHistoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(top: false, child: Column(
        children: [
          GreenPageHeader(
            title: AppLocalizations.of(context).usageTitle,
            subtitle: AppLocalizations.of(context).usageSubtitle,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: kOnGradient, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: const [],
          ),

          // Tab Bar
          Builder(builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Container(
              color: kBrandPrimaryDark,
              child: TabBar(
                controller: _tab,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(icon: const Icon(Icons.sports_golf_rounded, size: 18),
                      text: l10n.usageTabAnalysis),
                  Tab(icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      text: l10n.usageTabBalls),
                ],
              ),
            );
          }),

          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _AnalysisTab(),
                _BallsTab(),
              ],
            ),
          ),
        ],
      )),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Tab 1 — AI 分析紀錄
// ════════════════════════════════════════════════════════════════

class _AnalysisTab extends StatefulWidget {
  const _AnalysisTab();

  @override
  State<_AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<_AnalysisTab>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 20;

  final _items     = <_AnalysisRecord>[];
  int  _total      = 0;
  int  _todayUsed  = 0;
  int  _page       = 1;
  bool _loading    = false;
  bool _hasMore    = true;
  String? _error;

  final _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

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
      final data = await VideoServerClient.instance.getAnalysisHistory(
        page: _page, pageSize: _pageSize);
      if (!mounted) return;

      if (data == null) {
        setState(() { _error = AppLocalizations.of(context).usageLoadFailed; _loading = false; });
        return;
      }

      final rawItems = (data['items'] as List<dynamic>?) ?? [];
      final newItems = rawItems
          .map((e) => _AnalysisRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        if (reset) _items.clear();
        _items.addAll(newItems);
        _total     = (data['total']     as num?)?.toInt() ?? 0;
        _todayUsed = (data['todayUsed'] as num?)?.toInt() ?? 0;
        _hasMore   = _items.length < _total;
        _page++;
        _loading   = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = AppLocalizations.of(context).usageLoadError(e.toString()); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _loadMore(reset: true),
      color: kBrandPrimary,
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // 統計卡
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _AnalysisSummaryCard(
                  total: _total, todayUsed: _todayUsed),
            ),
          ),

          if (_error != null && _items.isEmpty)
            SliverFillRemaining(
              child: _ErrorState(message: _error!, onRetry: () => _loadMore(reset: true)),
            )
          else if (_items.isEmpty && !_loading)
            SliverFillRemaining(child: _EmptyState(text: AppLocalizations.of(context).usageEmptyAnalysis))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final l10n = AppLocalizations.of(ctx);
                    if (i == _items.length) {
                      return _hasMore
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(l10n.usageAllLoaded,
                                    style: TextStyle(
                                        fontSize: 12, color: context.textHint)),
                              ),
                            );
                    }
                    final item = _items[i];
                    final isFirst = i == 0 ||
                        !_isSameDay(_items[i - 1].usedAt, item.usedAt);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isFirst) _DateHeader(date: item.usedAt),
                        _AnalysisTile(
                            record: item, index: _total - i),
                      ],
                    );
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
    );
  }
}

class _AnalysisSummaryCard extends StatelessWidget {
  final int total;
  final int todayUsed;
  const _AnalysisSummaryCard({required this.total, required this.todayUsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.cardShadow,
      ),
      child: Builder(builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Row(
          children: [
            _SummaryCell(
                label: l10n.usageSummaryTotalAnalysis,
                value: '$total',
                unit: l10n.usageUnitTimes,
                color: kBrandPrimary),
            Container(
                width: 1, height: 32, color: context.borderColor,
                margin: const EdgeInsets.symmetric(horizontal: 16)),
            _SummaryCell(
                label: l10n.usageSummaryTodayUsed,
                value: '$todayUsed',
                unit: l10n.usageUnitTimes,
                color: const Color(0xFF4285F4)),
          ],
        );
      }),
    );
  }
}

class _AnalysisTile extends StatelessWidget {
  final _AnalysisRecord record;
  final int index;
  const _AnalysisTile({required this.record, required this.index});

  @override
  Widget build(BuildContext context) {
    final l10n     = AppLocalizations.of(context);
    final isQuota  = record.source == 'daily_quota';
    final color    = isQuota ? kBrandPrimary : const Color(0xFFFF6B35);
    final timeStr  = DateFormat('HH:mm').format(record.usedAt);
    final label    = isQuota ? l10n.usageSourceDailyQuota : l10n.usageSourceBonusBall;
    final srcLabel = isQuota ? l10n.usageSourceDailyQuotaDesc : l10n.usageSourceBonusBallDesc;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: context.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // 圖示圓圈
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sports_golf_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),

            // 描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.usageAnalysisItemTitle,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(srcLabel,
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary)),
                ],
              ),
            ),

            // 右側：標籤 + 時間
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
                const SizedBox(height: 4),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 11, color: context.textHint)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Tab 2 — 球數流水帳
// ════════════════════════════════════════════════════════════════

class _BallsTab extends StatefulWidget {
  const _BallsTab();

  @override
  State<_BallsTab> createState() => _BallsTabState();
}

class _BallsTabState extends State<_BallsTab>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 20;

  final _items       = <_BallRecord>[];
  int  _total        = 0;
  int  _currentBalls = 0;
  int  _page         = 1;
  bool _loading      = false;
  bool _hasMore      = true;
  String? _error;

  final _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

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
      setState(() {
        _items.clear(); _page = 1; _hasMore = true; _error = null;
      });
    }
    setState(() => _loading = true);
    try {
      final data = await VideoServerClient.instance.getBallsHistory(
        page: _page, pageSize: _pageSize);
      if (!mounted) return;

      if (data == null) {
        setState(() { _error = AppLocalizations.of(context).usageLoadFailed; _loading = false; });
        return;
      }

      final rawItems = (data['items'] as List<dynamic>?) ?? [];
      final newItems = rawItems
          .map((e) => _BallRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        if (reset) _items.clear();
        _items.addAll(newItems);
        _total        = (data['total']        as num?)?.toInt() ?? 0;
        _currentBalls = (data['currentBalls'] as num?)?.toInt() ?? 0;
        _hasMore      = _items.length < _total;
        _page++;
        _loading      = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = AppLocalizations.of(context).usageLoadError(e.toString()); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _loadMore(reset: true),
      color: kBrandPrimary,
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _BallsSummaryCard(
                  total: _total, currentBalls: _currentBalls),
            ),
          ),

          if (_error != null && _items.isEmpty)
            SliverFillRemaining(
              child: _ErrorState(
                  message: _error!, onRetry: () => _loadMore(reset: true)),
            )
          else if (_items.isEmpty && !_loading)
            SliverFillRemaining(child: _EmptyState(text: AppLocalizations.of(context).usageEmptyBalls))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final l10n = AppLocalizations.of(ctx);
                    if (i == _items.length) {
                      return _hasMore
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                  child: CircularProgressIndicator()),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(l10n.usageAllLoaded,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.textHint)),
                              ),
                            );
                    }
                    final item = _items[i];
                    final isFirst = i == 0 ||
                        !_isSameDay(_items[i - 1].createdAt, item.createdAt);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isFirst) _DateHeader(date: item.createdAt),
                        _BallTile(record: item),
                      ],
                    );
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
    );
  }
}

class _BallsSummaryCard extends StatelessWidget {
  final int total;
  final int currentBalls;
  const _BallsSummaryCard(
      {required this.total, required this.currentBalls});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.cardShadow,
      ),
      child: Builder(builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Row(
          children: [
            _SummaryCell(
                label: l10n.usageSummaryTotalRecords,
                value: '$total',
                unit: l10n.usageUnitRecords,
                color: kBrandPrimary),
            Container(
                width: 1,
                height: 32,
                color: context.borderColor,
                margin: const EdgeInsets.symmetric(horizontal: 16)),
            _SummaryCell(
                label: l10n.usageSummaryCurrentBalls,
                value: '$currentBalls',
                unit: l10n.usageUnitBalls,
                color: const Color(0xFFFF6B35)),
          ],
        );
      }),
    );
  }
}

class _BallTile extends StatelessWidget {
  final _BallRecord record;
  const _BallTile({required this.record});

  static const _reasonMeta = <String, _ReasonMeta>{
    'ad':       _ReasonMeta('📺', 'ad',       Color(0xFF4285F4)),
    'feedback': _ReasonMeta('💬', 'feedback', Color(0xFF9C27B0)),
    'invite':   _ReasonMeta('👥', 'invite',   Color(0xFFFF6B35)),
    'upload':   _ReasonMeta('☁️', 'upload',   Color(0xFF00897B)),
    'analysis': _ReasonMeta('🏌️', 'analysis', Color(0xFFF44336)),
    'manual':   _ReasonMeta('✏️', 'manual',   Color(0xFF9E9E9E)),
  };

  @override
  Widget build(BuildContext context) {
    final l10n    = AppLocalizations.of(context);
    final meta    = _reasonMeta[record.reason]
        ?? const _ReasonMeta('❓', 'other', Color(0xFF9E9E9E));
    final isEarn  = record.delta > 0;
    final deltaStr = isEarn ? '+${record.delta}' : '${record.delta}';
    final timeStr = DateFormat('HH:mm').format(record.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: context.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Emoji 圓圈
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(meta.emoji,
                    style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),

            // 描述 + 餘額
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.label(l10n),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(AppLocalizations.of(context).usageBallBalance(record.balanceAfter),
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary)),
                ],
              ),
            ),

            // 右側：增減 + 時間
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  deltaStr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isEarn
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
                const SizedBox(height: 2),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 11, color: context.textHint)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonMeta {
  final String emoji;
  final String _labelKey; // internal stable key, not displayed directly
  final Color color;
  const _ReasonMeta(this.emoji, this._labelKey, this.color);

  String label(AppLocalizations l10n) {
    switch (_labelKey) {
      case 'ad':       return l10n.usageReasonAd;
      case 'feedback': return l10n.usageReasonFeedback;
      case 'invite':   return l10n.usageReasonInvite;
      case 'upload':   return l10n.usageReasonUpload;
      case 'analysis': return l10n.usageReasonAnalysis;
      case 'manual':   return l10n.usageReasonManual;
      default:         return l10n.usageReasonOther;
    }
  }
}

// ════════════════════════════════════════════════════════════════
// 共用小元件
// ════════════════════════════════════════════════════════════════

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _SummaryCell(
      {required this.label,
      required this.value,
      required this.unit,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondary)),
            ]),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ],
      ),
    );
  }
}

// 日期標題
class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(date.year, date.month, date.day);

    final l10n = AppLocalizations.of(context);
    String label;
    if (d == today) {
      label = l10n.usageDateToday;
    } else if (d == today.subtract(const Duration(days: 1))) {
      label = l10n.usageDateYesterday;
    } else {
      label = DateFormat('MM/dd  EEEE', 'zh_TW').format(date);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: kBrandPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kBrandPrimary.withValues(alpha: 0.8))),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1)),
      ]),
    );
  }
}

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
            Icon(Icons.receipt_long_rounded,
                size: 56, color: context.textHint),
            const SizedBox(height: 12),
            Text(text,
                style: TextStyle(fontSize: 15, color: context.textHint)),
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
            Icon(Icons.cloud_off_rounded,
                size: 48, color: context.textHint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: context.textSecondary)),
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

// 工具函式
bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
