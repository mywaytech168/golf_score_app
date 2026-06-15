import 'dart:io';
import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../providers/plan_provider.dart';
import '../services/in_app_purchase_service.dart';
import '../services/plan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/green_page_header.dart';
import '../services/analytics_service.dart';

// ════════════════════════════════════════════════════════════════
// 幣別 / 在地定價（隨多語系切換：繁中 NT$ / 簡中 ¥ / 英文 US$）
// ════════════════════════════════════════════════════════════════

enum _Currency { twd, cny, usd }

_Currency _currencyOf(BuildContext context) {
  final l = Localizations.localeOf(context);
  if (l.languageCode == 'en') return _Currency.usd;
  if (l.languageCode == 'zh' && l.countryCode == 'CN') return _Currency.cny;
  return _Currency.twd; // 繁中及其他預設台幣
}

/// 同一價格在三種幣別下的顯示字串（純展示用 fallback；實際扣款仍由商店回傳）
class _PriceSet {
  final String twd;
  final String cny;
  final String usd;
  const _PriceSet({required this.twd, required this.cny, required this.usd});

  String of(_Currency c) => switch (c) {
        _Currency.twd => twd,
        _Currency.cny => cny,
        _Currency.usd => usd,
      };

  String inContext(BuildContext context) => of(_currencyOf(context));
}

// ════════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════════

enum _Plan { free, pro, elite }

extension _PlanX on _Plan {
  String get label {
    switch (this) {
      case _Plan.free:  return 'Free';
      case _Plan.pro:   return 'Pro';
      case _Plan.elite: return 'Elite';
    }
  }

  _PriceSet get _monthlyPrices {
    switch (this) {
      case _Plan.free:  return const _PriceSet(twd: 'NT\$0',     cny: '¥0',     usd: 'US\$0');
      case _Plan.pro:   return const _PriceSet(twd: 'NT\$600',   cny: '¥138',   usd: 'US\$19');
      case _Plan.elite: return const _PriceSet(twd: 'NT\$1,200', cny: '¥268',   usd: 'US\$38');
    }
  }

  _PriceSet get _yearlyPrices {
    switch (this) {
      case _Plan.free:  return const _PriceSet(twd: 'NT\$0',      cny: '¥0',      usd: 'US\$0');
      case _Plan.pro:   return const _PriceSet(twd: 'NT\$6,000',  cny: '¥1,380',  usd: 'US\$190');
      case _Plan.elite: return const _PriceSet(twd: 'NT\$12,000', cny: '¥2,680',  usd: 'US\$380');
    }
  }

  String price(BuildContext context) => _monthlyPrices.inContext(context);
  String priceYearly(BuildContext context) => _yearlyPrices.inContext(context);

  String period(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (this) {
      case _Plan.free:  return l10n.upgradeFreeForever;
      case _Plan.pro:   return l10n.upgradePerMonth;
      case _Plan.elite: return l10n.upgradePerMonth;
    }
  }

  Color get primaryColor {
    switch (this) {
      case _Plan.free:  return const Color(0xFF78909C);
      case _Plan.pro:   return kBrandPrimary;
      case _Plan.elite: return const Color(0xFFB8860B);
    }
  }

  Color bgColorIn(BuildContext context) {
    if (context.isDarkMode) return primaryColor.withValues(alpha: 0.18);
    switch (this) {
      case _Plan.free:  return const Color(0xFFF4F6F9);
      case _Plan.pro:   return const Color(0xFFE8F5EE);
      case _Plan.elite: return const Color(0xFFFFF8E1);
    }
  }

  List<String> highlights(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (this) {
      case _Plan.free:
        return [l10n.upgradeHighlightFullFeatured, l10n.upgradeHighlightAiDaily10, l10n.upgradeHighlightBuyMore];
      case _Plan.pro:
        return [l10n.upgradeHighlightFullFeatured, l10n.upgradeHighlightAiDaily90, l10n.upgradeNoAds];
      case _Plan.elite:
        return [l10n.upgradeHighlightFullFeatured, l10n.upgradeHighlightAiUnlimited, l10n.upgradeNoAds];
    }
  }

  bool get isRecommended => this == _Plan.pro;
}

/// 單一功能項目
class _FeatureRow {
  final String name;
  final String? free;   // null = 無此功能，否則顯示文字（'✓' = 僅有打勾）
  final String? pro;
  final String? elite;

  const _FeatureRow(this.name, this.free, this.pro, this.elite);
}

List<_FeatureRow> _buildFeatures(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return [
    _FeatureRow(l10n.upgradeFeatureSwingRecording,    '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeatureAutoClip,           '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeatureVoiceHint,          '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeatureBallTrack,          '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeaturePose,               '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeatureAudioScore,         '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeatureDualVideo,          '✓',                      '✓',                      '✓'),
    _FeatureRow(l10n.upgradeFeatureAiCoachAnalysis,    l10n.upgradeQuotaDaily10, l10n.upgradeQuotaDaily90, l10n.upgradeQuotaUnlimited),
    _FeatureRow(l10n.upgradeNoAds,                     null,                     '✓',                      '✓'),
  ];
}

// ════════════════════════════════════════════════════════════════
// 球數包資料
// ════════════════════════════════════════════════════════════════

enum _BallBadge { popular, value, bestDeal }

extension _BallBadgeX on _BallBadge {
  String label(AppLocalizations l10n) {
    switch (this) {
      case _BallBadge.popular:  return l10n.upgradeBadgePopular;
      case _BallBadge.value:    return l10n.upgradeBadgeValue;
      case _BallBadge.bestDeal: return l10n.upgradeBadgeBestDeal;
    }
  }
}

class _BallPack {
  final String productId;
  final int balls;
  final _PriceSet prices;   // 在地展示價（fallback；實際扣款由商店回傳）
  final _BallBadge? badge;

  const _BallPack({
    required this.productId,
    required this.balls,
    required this.prices,
    this.badge,
  });

  String price(BuildContext context) => prices.inContext(context);
}

const _ballPacks = <_BallPack>[
  _BallPack(productId: 'orvia_golf_balls_1',   balls: 1,   prices: _PriceSet(twd: 'NT\$60',    cny: '¥12',  usd: 'US\$1.99')),
  _BallPack(productId: 'orvia_golf_balls_5',   balls: 5,   prices: _PriceSet(twd: 'NT\$240',   cny: '¥48',  usd: 'US\$7.99')),
  _BallPack(productId: 'orvia_golf_balls_10',  balls: 10,  prices: _PriceSet(twd: 'NT\$400',   cny: '¥88',  usd: 'US\$12.99'), badge: _BallBadge.popular),
  _BallPack(productId: 'orvia_golf_balls_50',  balls: 50,  prices: _PriceSet(twd: 'NT\$1,600', cny: '¥348', usd: 'US\$49.99'), badge: _BallBadge.value),
  _BallPack(productId: 'orvia_golf_balls_100', balls: 100, prices: _PriceSet(twd: 'NT\$2,600', cny: '¥588', usd: 'US\$79.99'), badge: _BallBadge.bestDeal),
];

// ════════════════════════════════════════════════════════════════
// 主頁面
// ════════════════════════════════════════════════════════════════

class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key});

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  _Plan _selected = _Plan.pro;

  @override
  Widget build(BuildContext context) {
    final currentPlan = context.watch<PlanProvider>().plan;
    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(top: false, child: Column(
        children: [
          GreenPageHeader(
            title: AppLocalizations.of(context).upgradePageTitle,
            subtitle: AppLocalizations.of(context).upgradePageSubtitle,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _PlanToggle(selected: _selected, onChanged: (p) {
                    AnalyticsService.instance.logEvent('subscribe_plan_select', {'plan': p.name});
                    setState(() => _selected = p);
                  }),
                  const SizedBox(height: 20),
                  _SelectedPlanCard(plan: _selected, currentPlan: currentPlan),
                  const SizedBox(height: 28),
                  _FeatureTable(highlighted: _selected),
                  const SizedBox(height: 28),
                  _CtaButton(plan: _selected, currentPlan: currentPlan, onTap: () => _onUpgrade(context)),
                  const SizedBox(height: 32),
                  _BallShopSection(onBuy: (pack) => _onBuyBalls(context, pack)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }

  void _onBuyBalls(BuildContext context, _BallPack pack) {
    AnalyticsService.instance.logEvent('ball_pack_select', {'product': pack.productId});
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BallBuySheet(pack: pack),
    );
  }

  void _onUpgrade(BuildContext context) {
    if (_selected == _Plan.free) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).upgradeAlreadyFree)),
      );
      return;
    }
    AnalyticsService.instance.logEvent('subscribe_cta_click', {'plan': _selected.name});
    _showPaySheet(context);
  }

  void _showPaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PaySheet(plan: _selected),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 方案切換列
// ════════════════════════════════════════════════════════════════

class _PlanToggle extends StatelessWidget {
  final _Plan selected;
  final ValueChanged<_Plan> onChanged;

  const _PlanToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(22),
          boxShadow: context.cardShadow,
        ),
        child: Row(
          children: _Plan.values.map((plan) {
            final isSelected = plan == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(plan),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected ? plan.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      plan.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : context.textSecondary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 選中方案卡片
// ════════════════════════════════════════════════════════════════

class _SelectedPlanCard extends StatelessWidget {
  final _Plan plan;
  final UserPlan currentPlan;
  const _SelectedPlanCard({required this.plan, required this.currentPlan});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      key: ValueKey(plan),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: plan.primaryColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(color: plan.primaryColor.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 方案標頭
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: plan.bgColorIn(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: plan.primaryColor.withValues(alpha: 0.3)),
                ),
                child: Text(plan.label, style: TextStyle(color: plan.primaryColor, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (plan.isRecommended) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(10)),
                  child: Text(AppLocalizations.of(context).upgradeRecommended, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
              if (currentPlan.index == plan.index) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: plan.primaryColor, borderRadius: BorderRadius.circular(10)),
                  child: Text(AppLocalizations.of(context).upgradeSubscribed, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(plan.price(context), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: context.priceColor)),
                  Text(plan.period(context), style: TextStyle(fontSize: 12, color: context.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // 功能亮點
          ...plan.highlights(context).map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: plan.primaryColor, size: 16),
                const SizedBox(width: 8),
                Text(h, style: TextStyle(fontSize: 13, color: context.textPrimary)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 完整功能比較表
// ════════════════════════════════════════════════════════════════

class _FeatureTable extends StatelessWidget {
  final _Plan highlighted;
  const _FeatureTable({required this.highlighted});

  static const _rowH  = 44.0;
  static const _plans = [_Plan.free, _Plan.pro, _Plan.elite];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 左欄寬度：30%，最小 80、最大 110
          final leftW = (constraints.maxWidth * 0.30).clamp(80.0, 110.0);
          // 三個方案欄平分剩餘寬度
          final colW  = (constraints.maxWidth - leftW) / 3;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: Text(
                  AppLocalizations.of(context).upgradeFullComparison,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: context.cardShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 功能名稱欄
                        SizedBox(
                          width: leftW,
                          child: Column(
                            children: [
                              _headerCell(AppLocalizations.of(context).upgradeFeatureColumn, null),
                              ..._buildFeatures(context).asMap().entries.map((e) =>
                                _featureNameCell(context, e.value.name, e.key.isOdd),
                              ),
                            ],
                          ),
                        ),
                        // 三個方案欄（撐滿剩餘寬度，不橫向捲動）
                        ..._plans.map((plan) {
                          final isHighlighted = plan == highlighted;
                          return _PlanColumn(
                            plan: plan,
                            isHighlighted: isHighlighted,
                            features: _buildFeatures(context),
                            rowH: _rowH,
                            colW: colW,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCell(String text, _Plan? plan) {
    return Container(
      height: _rowH,
      color: const Color(0xFF1A3A2A),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _featureNameCell(BuildContext context, String name, bool isOdd) {
    return Container(
      height: _rowH,
      color: isOdd ? context.bgInset : context.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        name,
        style: TextStyle(fontSize: 11.5, color: context.textPrimary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _PlanColumn extends StatelessWidget {
  final _Plan plan;
  final bool isHighlighted;
  final List<_FeatureRow> features;
  final double rowH;
  final double colW;

  const _PlanColumn({
    required this.plan,
    required this.isHighlighted,
    required this.features,
    required this.rowH,
    required this.colW,
  });

  String? _valueFor(_FeatureRow row) {
    switch (plan) {
      case _Plan.free:  return row.free;
      case _Plan.pro:   return row.pro;
      case _Plan.elite: return row.elite;
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlight = isHighlighted;
    final color = plan.primaryColor;

    return Container(
      width: colW,
      decoration: highlight
          ? BoxDecoration(
              color: plan.bgColorIn(context),
              border: Border(
                left:  BorderSide(color: color.withValues(alpha: 0.3)),
                right: BorderSide(color: color.withValues(alpha: 0.3)),
              ),
            )
          : null,
      child: Column(
        children: [
          // 標頭
          Container(
            height: rowH,
            color: highlight ? color : const Color(0xFF1A3A2A),
            alignment: Alignment.center,
            child: Text(
              plan.label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          // 數據列
          ...features.asMap().entries.map((e) {
            final val = _valueFor(e.value);
            final isOdd = e.key.isOdd;
            return _ValueCell(
              value: val,
              plan: plan,
              isHighlighted: highlight,
              isOdd: isOdd,
              rowH: rowH,
            );
          }),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String? value;
  final _Plan plan;
  final bool isHighlighted;
  final bool isOdd;
  final double rowH;

  const _ValueCell({
    required this.value,
    required this.plan,
    required this.isHighlighted,
    required this.isOdd,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context) {
    final color = plan.primaryColor;
    Color? bg;
    if (isHighlighted) {
      bg = isOdd
          ? plan.bgColorIn(context).withValues(alpha: 0.6)
          : plan.bgColorIn(context);
    } else {
      bg = isOdd ? context.bgInset : context.bgCard;
    }

    Widget content;
    if (value == null) {
      // 無此功能 → X
      content = Icon(Icons.close_rounded, color: Colors.red[300], size: 16);
    } else if (value == '✓') {
      // 純勾選
      content = Icon(Icons.check_rounded, color: color, size: 18);
    } else if (value == '有') {
      // 廣告
      content = Text(AppLocalizations.of(context).upgradeFeatureYes,
          style: TextStyle(fontSize: 11, color: context.textSecondary));
    } else {
      // 文字說明
      content = Text(
        value!,
        style: TextStyle(
          fontSize: 10.5,
          color: isHighlighted ? color : context.textSecondary,
          fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Container(
      height: rowH,
      color: bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: content,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// CTA 按鈕
// ════════════════════════════════════════════════════════════════

class _CtaButton extends StatelessWidget {
  final _Plan plan;
  final UserPlan currentPlan;
  final VoidCallback onTap;

  const _CtaButton({required this.plan, required this.currentPlan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFree      = plan == _Plan.free;
    final isSubscribed = currentPlan.index == plan.index && !isFree;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: (isFree || isSubscribed) ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: isSubscribed
                ? Colors.green[700]
                : isFree ? Colors.grey[400] : plan.primaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: isSubscribed ? Colors.green[700] : Colors.grey[400],
            disabledForegroundColor: Colors.white,
            elevation: (isFree || isSubscribed) ? 0 : 4,
            shadowColor: plan.primaryColor.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSubscribed
                    ? Icons.check_circle_rounded
                    : isFree ? Icons.check_circle_outline : Icons.workspace_premium_rounded,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isSubscribed
                    ? AppLocalizations.of(context).upgradeCurrentPlanActive
                    : isFree
                        ? AppLocalizations.of(context).upgradeCurrentPlan
                        : AppLocalizations.of(context).upgradeSubscribePlan(plan.label),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 付款底頁
// ════════════════════════════════════════════════════════════════

class _PaySheet extends StatefulWidget {
  final _Plan plan;
  const _PaySheet({required this.plan});

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  bool _loading = false;
  bool _yearly = false;
  // 從 Store 動態取得的商品（含正確貨幣價格），key = productId
  final Map<String, ProductDetails> _products = {};
  bool _queryingProduct = true;

  String get _monthlyId => switch (widget.plan) {
    _Plan.pro   => 'orvia_golf_pro_monthly',
    _Plan.elite => 'orvia_golf_elite_monthly',
    _Plan.free  => '',
  };

  String get _yearlyId => switch (widget.plan) {
    _Plan.pro   => 'orvia_golf_pro_yearly',
    _Plan.elite => 'orvia_golf_elite_yearly',
    _Plan.free  => '',
  };

  String get _productId => _yearly ? _yearlyId : _monthlyId;

  ProductDetails? get _productDetails => _products[_productId];

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('subscribe_sheet'); // 訂閱付款 sheet
    _queryProduct();
  }

  /// 開啟 sheet 時就先 query 月/年兩個商品，取得含當地貨幣的正確價格
  Future<void> _queryProduct() async {
    setState(() => _queryingProduct = true);
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available || !mounted) {
        setState(() => _queryingProduct = false);
        return;
      }
      final response = await InAppPurchase.instance
          .queryProductDetails({_monthlyId, _yearlyId});
      if (mounted) {
        setState(() {
          for (final p in response.productDetails) {
            _products[p.id] = p;
          }
          _queryingProduct = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _queryingProduct = false);
    }
  }

  Future<void> _subscribe() async {
    if (_loading || _productDetails == null) return;
    setState(() => _loading = true);
    AnalyticsService.instance.logEvent('purchase_click', {
      'type': 'subscription',
      'product': _productDetails!.id,
    });
    try {
      final param = PurchaseParam(productDetails: _productDetails!);
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      // 購買結果由 InAppPurchaseService 的 purchaseStream 處理
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).upgradeSubscribeFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 顯示的價格：優先用語系幣別表（與全 App 一致），實際扣款仍由商店處理
  String _displayPrice(BuildContext context) {
    return _yearly
        ? '${widget.plan.priceYearly(context)}${AppLocalizations.of(context).upgradePerYear}'
        : '${widget.plan.price(context)}${widget.plan.period(context)}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: widget.plan.primaryColor, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).upgradeSubscribePlan(widget.plan.label),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    if (_queryingProduct)
                      const SizedBox(
                        width: 60, height: 14,
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else
                      Text(
                        _displayPrice(context),
                        style: TextStyle(fontSize: 13, color: context.priceColor, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 月繳 / 年繳 切換
            Center(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(AppLocalizations.of(context).upgradeMonthly)),
                  ButtonSegment(value: true, label: Text(AppLocalizations.of(context).upgradeYearly)),
                ],
                selected: {_yearly},
                onSelectionChanged: _loading
                    ? null
                    : (s) {
                        AnalyticsService.instance.logEvent(
                          'subscribe_period_toggle',
                          {'period': s.first ? 'yearly' : 'monthly'},
                        );
                        setState(() => _yearly = s.first);
                      },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor:
                      widget.plan.primaryColor.withValues(alpha: 0.15),
                  selectedForegroundColor: widget.plan.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_loading || _queryingProduct || _productDetails == null) ? null : _subscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.plan.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : _queryingProduct
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : _productDetails == null
                            ? Text(AppLocalizations.of(context).upgradeProductLoadFailed,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
                            : Text(
                                Platform.isIOS ? AppLocalizations.of(context).upgradeAppStoreSubscribe : AppLocalizations.of(context).upgradeGooglePlaySubscribe,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                Platform.isIOS ? AppLocalizations.of(context).upgradeManageSubscriptionIos : AppLocalizations.of(context).upgradeManageSubscriptionAndroid,
                style: TextStyle(fontSize: 11, color: context.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 球數商店區塊
// ════════════════════════════════════════════════════════════════

class _BallShopSection extends StatelessWidget {
  final void Function(_BallPack pack) onBuy;
  const _BallShopSection({required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.sports_golf_rounded, size: 18, color: kBrandPrimary),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).upgradeBuyBalls,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.isDarkMode
                        ? kBrandPrimary.withValues(alpha: 0.18)
                        : const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBrandPrimary.withValues(alpha: 0.4)),
                  ),
                  child: Text(AppLocalizations.of(context).upgradeNoExpiry, style: const TextStyle(fontSize: 11, color: kBrandPrimary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          ...(_ballPacks.map((pack) => _BallPackTile(pack: pack, onTap: () => onBuy(pack)))),
        ],
      ),
    );
  }
}

class _BallPackTile extends StatelessWidget {
  final _BallPack pack;
  final VoidCallback onTap;
  const _BallPackTile({required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 球圖示
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.isDarkMode
                        ? kBrandPrimary.withValues(alpha: 0.18)
                        : const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.sports_golf_rounded, color: kBrandPrimary, size: 22),
                ),
                const SizedBox(width: 14),
                // 球數 + badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).upgradeBallCount(pack.balls),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary),
                          ),
                          if (pack.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(pack.badge!.label(AppLocalizations.of(context)), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).upgradeBallPackValidity,
                        style: TextStyle(fontSize: 11, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
                // 價格 + 購買按鈕
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pack.price(context),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.priceColor),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: kBrandPrimary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(AppLocalizations.of(context).upgradeBuyButton, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 球數購買底頁
// ════════════════════════════════════════════════════════════════

class _BallBuySheet extends StatefulWidget {
  final _BallPack pack;
  const _BallBuySheet({required this.pack});

  @override
  State<_BallBuySheet> createState() => _BallBuySheetState();
}

class _BallBuySheetState extends State<_BallBuySheet> {
  bool _loading = false;
  ProductDetails? _productDetails;
  bool _queryingProduct = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('ball_shop_sheet'); // 球包購買 sheet
    _queryProduct();
  }

  Future<void> _queryProduct() async {
    setState(() => _queryingProduct = true);
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available || !mounted) {
        setState(() => _queryingProduct = false);
        return;
      }
      final response = await InAppPurchase.instance.queryProductDetails({widget.pack.productId});
      if (mounted) {
        setState(() {
          _productDetails = response.productDetails.isNotEmpty ? response.productDetails.first : null;
          _queryingProduct = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _queryingProduct = false);
    }
  }

  Future<void> _buy() async {
    if (_loading || _productDetails == null) return;
    setState(() => _loading = true);
    AnalyticsService.instance.logEvent('purchase_click', {
      'type': 'ball_pack',
      'product': _productDetails!.id,
    });
    try {
      await InAppPurchaseService.instance.buyBallPack(_productDetails!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).upgradePurchaseFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 顯示價格：優先用語系幣別表（與全 App 一致），實際扣款仍由商店處理
  String _displayPrice(BuildContext context) => widget.pack.price(context);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sports_golf_rounded, color: kBrandPrimary, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).upgradeBuyBallCount(widget.pack.balls),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    if (_queryingProduct)
                      const SizedBox(width: 60, height: 14, child: LinearProgressIndicator(minHeight: 2))
                    else
                      Text(_displayPrice(context),
                          style: TextStyle(fontSize: 13, color: context.priceColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).upgradeBallPackDescription,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_loading || _queryingProduct || _productDetails == null) ? null : _buy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading || _queryingProduct
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : _productDetails == null
                        ? Text(AppLocalizations.of(context).upgradeProductLoadFailed, style: const TextStyle(fontSize: 14))
                        : Text(
                            Platform.isIOS ? AppLocalizations.of(context).upgradeAppStorePurchase : AppLocalizations.of(context).upgradeGooglePlayPurchase,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
