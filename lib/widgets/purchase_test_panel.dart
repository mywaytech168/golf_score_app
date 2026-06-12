import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import '../services/purchase_service.dart';
import '../theme/app_theme.dart';

/// 測試購買面板 - 只在調試模式下顯示
class PurchaseTestPanel extends StatefulWidget {
  final PurchaseService purchaseService;

  const PurchaseTestPanel({
    super.key,
    required this.purchaseService,
  });

  @override
  State<PurchaseTestPanel> createState() => _PurchaseTestPanelState();
}

class _PurchaseTestPanelState extends State<PurchaseTestPanel> {
  bool _isPremium = false;
  String? _paymentMethod;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final isPremium = await widget.purchaseService.isPremiumUser();
    final paymentMethod = await widget.purchaseService.getPaymentMethod();

    if (mounted) {
      setState(() {
        _isPremium = isPremium;
        _paymentMethod = paymentMethod;
      });
    }
  }

  Future<void> _simulatePurchaseSuccess() async {
    setState(() => _isLoading = true);

    try {
      // 模擬購買成功
      await widget.purchaseService.setPremiumUser(
        true,
        paymentMethod: 'test_app_store',
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.purchaseTestSimulateSuccessMsg),
            backgroundColor: Colors.green,
          ),
        );
        _refreshStatus();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.purchaseTestErrorMsg(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearPurchase() async {
    setState(() => _isLoading = true);

    try {
      // 清除購買紀錄
      await widget.purchaseService.debugClearPremiumStatus();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.purchaseTestClearSuccessMsg),
            backgroundColor: Colors.blue,
          ),
        );
        _refreshStatus();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.purchaseTestErrorMsg(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.amber.withValues(alpha: 0.10)
            : Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題
          Row(
            children: [
              Icon(Icons.bug_report, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Text(
                l10n.purchaseTestPanelTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.isDarkMode
                      ? Colors.amber.shade300
                      : Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 狀態顯示
          Container(
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(l10n.purchaseTestPremiumStatusLabel),
                    if (_isPremium)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.purchaseTestStatusPurchased,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.purchaseTestStatusNotPurchased,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.purchaseTestPaymentMethod(_paymentMethod ?? l10n.purchaseTestPaymentMethodNone),
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 按鈕組
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _simulatePurchaseSuccess,
                  icon: const Icon(Icons.check_circle),
                  label: Text(l10n.purchaseTestSimulateBtn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _clearPurchase,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.purchaseTestClearBtn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          // 刷新按鈕
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _refreshStatus,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.purchaseTestRefreshBtn),
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

/// 顯示購買測試面板的對話框
Future<void> showPurchaseTestPanel(
  BuildContext context, {
  required PurchaseService purchaseService,
}) async {
  final l10n = AppLocalizations.of(context);
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.purchaseTestDialogTitle),
      content: SizedBox(
        width: 300,
        child: PurchaseTestPanel(purchaseService: purchaseService),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}
