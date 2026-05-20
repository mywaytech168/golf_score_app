import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pay/pay.dart';

import '../services/plan_service.dart';
import '../theme/app_theme.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 24),
                _PlanToggle(selected: _selected, onChanged: (p) => setState(() => _selected = p)),
                const SizedBox(height: 20),
                _SelectedPlanCard(plan: _selected),
                const SizedBox(height: 28),
                _FeatureTable(highlighted: _selected),
                const SizedBox(height: 28),
                _CtaButton(plan: _selected, onTap: () => _onUpgrade(context)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: kPrimaryGreen,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kPrimaryGreen, Color(0xFF0A5C3A)],
            ),
          ),
          // 不用 SafeArea，讓 SliverAppBar 自己處理 status bar
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 72, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 28),
                    SizedBox(width: 10),
                    Text(
                      '升級您的方案',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '解鎖更多揮桿分析功能，精進您的球技',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 18),
            SizedBox(width: 6),
            Text('升級方案', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
      ),
    );
  }

  void _onUpgrade(BuildContext context) {
    if (_selected == _Plan.free) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('您目前使用的已是免費方案')),
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
  const _SelectedPlanCard({required this.plan});

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
                  child: const Text('推薦', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
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

  static const _rowH = 40.0;
  static const _colW  = 88.0;
  static const _plans = [_Plan.free, _Plan.pro, _Plan.elite];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 左欄寬度隨螢幕縮放，小螢幕最小 90dp，大螢幕最大 130dp
          final leftW = (constraints.maxWidth * 0.34).clamp(90.0, 130.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: Text(
                  '完整功能比較',
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
                        // 固定功能名稱欄（響應式寬度）
                        SizedBox(
                          width: leftW,
                          child: Column(
                            children: [
                              _headerCell('功能', null),
                              ..._features.asMap().entries.map((e) =>
                                _featureNameCell(e.value.name, e.key.isOdd),
                              ),
                            ],
                          ),
                        ),
                        // 三個方案欄（可橫向捲動）
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _plans.map((plan) {
                                final isHighlighted = plan == highlighted;
                                return _PlanColumn(
                                  plan: plan,
                                  isHighlighted: isHighlighted,
                                  features: _features,
                                  rowH: _rowH,
                                  colW: _colW,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
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
  final VoidCallback onTap;

  const _CtaButton({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFree = plan == _Plan.free;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: isFree ? Colors.grey[400] : plan.primaryColor,
            foregroundColor: Colors.white,
            elevation: isFree ? 0 : 4,
            shadowColor: plan.primaryColor.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isFree ? Icons.check_circle_outline : Icons.workspace_premium_rounded, size: 20),
              const SizedBox(width: 8),
              Text(
                isFree ? '目前方案' : '升級 ${plan.label} 方案',
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
  PaymentConfiguration? _googlePayConfig;
  bool _configError = false;

  @override
  void initState() {
    super.initState();
    PaymentConfiguration.fromAsset('assets/pay/google_pay_config.json').then((cfg) {
      if (mounted) setState(() => _googlePayConfig = cfg);
    }).catchError((_) {
      if (mounted) setState(() => _configError = true);
    });
  }

  String get _priceAmount {
    switch (widget.plan) {
      case _Plan.pro:   return '299.00';
      case _Plan.elite: return '599.00';
      default:          return '0.00';
    }
  }

  List<PaymentItem> get _paymentItems => [
    PaymentItem(
      label: 'TekSwing ${widget.plan.label} 方案',
      amount: _priceAmount,
      status: PaymentItemStatus.final_price,
    ),
  ];

  Future<void> _onGooglePayResult(Map<String, dynamic> result) async {
    debugPrint('[GooglePay] result: $result');
    if (!mounted) return;
    Navigator.of(context).pop();

    // 從 Google Pay 結果中取出 token（TEST 環境為 JSON 字串）
    final tokenData = result['paymentMethodData']?['tokenizationData'];
    final token = tokenData?['token'] as String? ?? jsonEncode(result);
    await _purchaseWithToken('google_pay', token);
  }

  void _onGooglePayError(Object? error) {
    debugPrint('[GooglePay] error: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Google Pay 發生錯誤：$error')),
    );
  }

  /// 送後端驗證並升級（真實付款路徑）
  Future<void> _purchaseWithToken(String store, String token) async {
    final userPlan = switch (widget.plan) {
      _Plan.free  => UserPlan.free,
      _Plan.pro   => UserPlan.pro,
      _Plan.elite => UserPlan.elite,
    };
    final ok = await PlanService.purchasePlan(userPlan, store: store, purchaseToken: token);
    if (!mounted) return;
    if (ok) {
      _showSuccess(store == 'google_pay' ? 'Google Pay' : store);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('付款驗證失敗，請稍後重試')),
      );
    }
  }

  /// Mock 付款路徑（僅 UI 展示用，不呼叫後端）
  Future<void> _activatePlan(String method) async {
    final userPlan = switch (widget.plan) {
      _Plan.free  => UserPlan.free,
      _Plan.pro   => UserPlan.pro,
      _Plan.elite => UserPlan.elite,
    };
    await PlanService.setPlan(userPlan);
    if (mounted) _showSuccess(method);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標頭
            Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: widget.plan.primaryColor, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('升級 ${widget.plan.label} 方案',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('${widget.plan.price}${widget.plan.period}',
                        style: TextStyle(fontSize: 13, color: widget.plan.primaryColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('選擇付款方式', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),

            // ── Google Pay ──────────────────────────────────────
            if (_googlePayConfig != null)
              _GooglePayRow(
                config: _googlePayConfig!,
                paymentItems: _paymentItems,
                onPaymentResult: _onGooglePayResult,
                onError: _onGooglePayError,
              )
            else if (_configError)
              _payOptionMock(context, Icons.phone_android_rounded, 'Google Pay', const Color(0xFF4285F4))
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              ),

            // ── 其他付款方式（Mock）──────────────────────────────
            _payOptionMock(context, Icons.apple_rounded,       'Apple Pay', Colors.black87),
            _payOptionMock(context, Icons.credit_card_rounded, '信用卡',    const Color(0xFF7B1FA2)),
            _payOptionMock(context, Icons.chat_rounded,        'LINE Pay',  const Color(0xFF00B900)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _payOptionMock(BuildContext context, IconData icon, String label, Color color) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black38),
      onTap: () async {
        Navigator.of(context).pop();
        await _activatePlan(label);
      },
    );
  }

  void _showSuccess(String method) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.check_circle_rounded, color: widget.plan.primaryColor),
          const SizedBox(width: 8),
          const Text('升級成功'),
        ]),
        content: Text('已透過 $method 升級為 ${widget.plan.label} 方案。\n感謝您的支持！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('確定', style: TextStyle(color: widget.plan.primaryColor)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Google Pay 按鈕列
// ════════════════════════════════════════════════════════════════

class _GooglePayRow extends StatelessWidget {
  final PaymentConfiguration config;
  final List<PaymentItem> paymentItems;
  final void Function(Map<String, dynamic>) onPaymentResult;
  final void Function(Object?) onError;

  const _GooglePayRow({
    required this.config,
    required this.paymentItems,
    required this.onPaymentResult,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 左側圖示（仿 _payOptionMock 風格）
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.phone_android_rounded, color: Color(0xFF4285F4), size: 22),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('Google Pay', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
          ),
          // 官方 Google Pay 按鈕
          SizedBox(
            height: 44,
            child: GooglePayButton(
              paymentConfiguration: config,
              paymentItems: paymentItems,
              type: GooglePayButtonType.pay,
              theme: GooglePayButtonTheme.dark,
              cornerRadius: 10,
              onPaymentResult: onPaymentResult,
              onError: onError,
              loadingIndicator: const SizedBox(
                width: 80, height: 44,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
