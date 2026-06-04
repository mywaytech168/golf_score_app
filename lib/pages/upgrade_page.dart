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

  String get price {
    switch (this) {
      case _Plan.free:  return 'NT\$0';
      case _Plan.pro:   return 'NT\$299';
      case _Plan.elite: return 'NT\$599';
    }
  }

  String get period {
    switch (this) {
      case _Plan.free:  return '永久免費';
      case _Plan.pro:   return '/月';
      case _Plan.elite: return '/月';
    }
  }

  Color get primaryColor {
    switch (this) {
      case _Plan.free:  return const Color(0xFF78909C);
      case _Plan.pro:   return kPrimaryGreen;
      case _Plan.elite: return const Color(0xFFB8860B);
    }
  }

  Color get bgColor {
    switch (this) {
      case _Plan.free:  return const Color(0xFFF4F6F9);
      case _Plan.pro:   return const Color(0xFFE8F5EE);
      case _Plan.elite: return const Color(0xFFFFF8E1);
    }
  }

  List<String> get highlights {
    switch (this) {
      case _Plan.free:
        return ['基礎錄影分析', '每項功能限10球', '每日統計報告', '廣告支援'];
      case _Plan.pro:
        return ['每項功能擴充至90球', '細項揮桿分數', '錯誤偵測AI模型', '無廣告'];
      case _Plan.elite:
        return ['所有功能無限制', '高畫質錄影', '個人化AI教練推薦', '弱點分析報告', '進階比較功能'];
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

const _features = <_FeatureRow>[
  _FeatureRow('揮桿錄影',         '✓',      '✓',      '高畫質'),
  _FeatureRow('長影片切片分析',    '10球',   '90球',   '無限制'),
  _FeatureRow('即時語音',         '10球',   '90球',   '無限制'),
  _FeatureRow('球軌跡分析',        '10球',   '90球',   '歷史比較'),
  _FeatureRow('疊影分析',          '10球',   '90球',   '無限制'),
  _FeatureRow('桿頭軌跡分析',      '10球',   '90球',   '無限制'),
  _FeatureRow('骨架姿勢分析',      '10球',   '90球',   '無限制'),
  _FeatureRow('節奏 / 速度分析',   '10球',   '90球',   '無限制'),
  _FeatureRow('揮桿分數估估',      '簡單分數', '細項分數', '進步趨勢'),
  _FeatureRow('AI 姿勢建議',      '綜合評分', '錯誤偵測', '評估+建議'),
  _FeatureRow('訓練建議',          '影片連結', '固定模板', '個人化推薦'),
  _FeatureRow('修正追蹤',          '基本文字', '基本文字', 'AI教練核心'),
  _FeatureRow('每日 / 月報告',     '每日',   '無弱點分析', '含弱點分析'),
  _FeatureRow('與他人比較',        '基礎',   '基礎',   '進階'),
  _FeatureRow('廣告',             '有',     null,     null),
];

// ════════════════════════════════════════════════════════════════
// 球數包資料
// ════════════════════════════════════════════════════════════════

class _BallPack {
  final String productId;
  final int balls;
  final String price;      // fallback hardcode price
  final String? badge;

  const _BallPack({
    required this.productId,
    required this.balls,
    required this.price,
    this.badge,
  });
}

const _ballPacks = <_BallPack>[
  _BallPack(productId: 'golf_balls_1',   balls: 1,   price: 'NT\$30'),
  _BallPack(productId: 'golf_balls_5',   balls: 5,   price: 'NT\$120'),
  _BallPack(productId: 'golf_balls_10',  balls: 10,  price: 'NT\$199',  badge: '熱門'),
  _BallPack(productId: 'golf_balls_50',  balls: 50,  price: 'NT\$799',  badge: '划算'),
  _BallPack(productId: 'golf_balls_100', balls: 100, price: 'NT\$1,290', badge: '最優惠'),
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
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(
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
                  _PlanToggle(selected: _selected, onChanged: (p) => setState(() => _selected = p)),
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
      ),
    );
  }

  void _onBuyBalls(BuildContext context, _BallPack pack) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
    _showPaySheet(context);
  }

  void _showPaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
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
                        color: isSelected ? Colors.white : Colors.black54,
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
        color: Colors.white,
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
                  color: plan.bgColor,
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
                  child: const Text('已訂閱', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(plan.price, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: plan.primaryColor)),
                  Text(plan.period, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // 功能亮點
          ...plan.highlights.map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: plan.primaryColor, size: 16),
                const SizedBox(width: 8),
                Text(h, style: const TextStyle(fontSize: 13, color: Colors.black87)),
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
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[800]),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
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
                              ..._features.asMap().entries.map((e) =>
                                _featureNameCell(e.value.name, e.key.isOdd),
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
                            features: _features,
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

  Widget _featureNameCell(String name, bool isOdd) {
    return Container(
      height: _rowH,
      color: isOdd ? const Color(0xFFF9FAFB) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        name,
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF2C3E50)),
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
              color: plan.bgColor,
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
      bg = isOdd ? plan.bgColor.withValues(alpha: 0.6) : plan.bgColor;
    } else {
      bg = isOdd ? const Color(0xFFF9FAFB) : Colors.white;
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
      content = const Text('有', style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)));
    } else {
      // 文字說明
      content = Text(
        value!,
        style: TextStyle(
          fontSize: 10.5,
          color: isHighlighted ? color : const Color(0xFF546E7A),
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
                    ? '目前方案'
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
  // 從 Store 動態取得的商品（含正確貨幣價格）
  ProductDetails? _productDetails;
  bool _queryingProduct = true;

  String get _productId => switch (widget.plan) {
    _Plan.pro   => 'golf_pro_monthly',
    _Plan.elite => 'golf_elite_monthly',
    _Plan.free  => '',
  };

  @override
  void initState() {
    super.initState();
    _queryProduct();
  }

  /// 開啟 sheet 時就先 query，取得含當地貨幣的正確價格
  Future<void> _queryProduct() async {
    setState(() => _queryingProduct = true);
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available || !mounted) {
        setState(() => _queryingProduct = false);
        return;
      }
      final response = await InAppPurchase.instance.queryProductDetails({_productId});
      if (mounted) {
        setState(() {
          _productDetails = response.productDetails.isNotEmpty
              ? response.productDetails.first
              : null;
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
    try {
      final param = PurchaseParam(productDetails: _productDetails!);
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      // 購買結果由 InAppPurchaseService 的 purchaseStream 處理
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('訂閱失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 顯示的價格：優先用 Store 回傳的本地貨幣，fallback 用 hardcode
  String get _displayPrice {
    if (_productDetails != null) return _productDetails!.price;
    return '${widget.plan.price}${widget.plan.period}';
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
                        _displayPrice,
                        style: TextStyle(fontSize: 13, color: widget.plan.primaryColor, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ],
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
                            ? const Text('商品載入失敗，請稍後再試',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
                            : Text(
                                Platform.isIOS ? 'App Store 訂閱' : 'Google Play 訂閱',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '訂閱後可隨時在 ${Platform.isIOS ? "App Store" : "Google Play"} 管理或取消',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
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
                const Icon(Icons.sports_golf_rounded, size: 18, color: kPrimaryGreen),
                const SizedBox(width: 6),
                Text(
                  '單買球數',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[800]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPrimaryGreen.withValues(alpha: 0.4)),
                  ),
                  child: const Text('不限時間使用', style: TextStyle(fontSize: 11, color: kPrimaryGreen, fontWeight: FontWeight.w600)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
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
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.sports_golf_rounded, color: kPrimaryGreen, size: 22),
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
                            '${pack.balls} 球',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A3A2A)),
                          ),
                          if (pack.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(pack.badge!, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '永久有效，隨時使用',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // 價格 + 購買按鈕
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pack.price,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kPrimaryGreen),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: kPrimaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('購買', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
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
    try {
      await InAppPurchaseService.instance.buyBallPack(_productDetails!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('購買失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _displayPrice {
    if (_productDetails != null) return _productDetails!.price;
    return widget.pack.price;
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
                const Icon(Icons.sports_golf_rounded, color: kPrimaryGreen, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('購買 ${widget.pack.balls} 球',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    if (_queryingProduct)
                      const SizedBox(width: 60, height: 14, child: LinearProgressIndicator(minHeight: 2))
                    else
                      Text(_displayPrice,
                          style: const TextStyle(fontSize: 13, color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '球數永久有效，不限時間使用。用完每日配額後自動消耗。',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                  backgroundColor: kPrimaryGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading || _queryingProduct
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : _productDetails == null
                        ? const Text('商品載入失敗，請稍後再試', style: TextStyle(fontSize: 14))
                        : Text(
                            Platform.isIOS ? 'App Store 購買' : 'Google Play 購買',
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
