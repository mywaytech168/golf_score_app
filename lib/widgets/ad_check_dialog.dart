import 'package:flutter/material.dart';
import '../services/ad_service.dart';
import '../services/purchase_service.dart';

/// 廣告檢查對話框 - 在用戶點擊「玩」時顯示
class AdCheckDialog extends StatefulWidget {
  final VoidCallback onContinue;
  final PurchaseService purchaseService;
  
  const AdCheckDialog({
    Key? key,
    required this.onContinue,
    required this.purchaseService,
  }) : super(key: key);

  @override
  State<AdCheckDialog> createState() => _AdCheckDialogState();
}

class _AdCheckDialogState extends State<AdCheckDialog> {
  bool _isLoading = false;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await widget.purchaseService.isPremiumUser();
    setState(() {
      _isPremium = isPremium;
    });
  }

  Future<void> _showRewardedAd() async {
    setState(() => _isLoading = true);
    
    try {
      // 顯示獎勵廣告
      final rewarded = await AdService.showRewardedAd();
      
      if (rewarded) {
        // 廣告看完，關閉對話框並繼續
        if (mounted) {
          Navigator.pop(context);
          widget.onContinue();
        }
      } else {
        // 用戶跳過廣告
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('請看完廣告才能繼續')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _purchasePremium() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await widget.purchaseService.purchasePremium();
      
      if (success && mounted) {
        setState(() => _isPremium = true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('感謝您的購買！現在可以無廣告玩遊戲了')),
        );
        
        // 自動繼續
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pop(context);
            widget.onContinue();
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPremium) {
      // 高級用戶，直接继续
      Future.microtask(() {
        Navigator.pop(context);
        widget.onContinue();
      });
      return const SizedBox.shrink();
    }

    return AlertDialog(
      title: const Text('觀看廣告即可繼續'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '選擇以下選項之一：',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '💰 選項 1: 購買無廣告版本',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '一次性購買，永久無廣告',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '📺 選項 2: 看廣告再玩',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '看完廣告就能玩，每次都需要',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _purchasePremium,
          icon: const Icon(Icons.shopping_cart),
          label: const Text('購買無廣告版本'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _showRewardedAd,
          icon: const Icon(Icons.videocam),
          label: const Text('看廣告玩'),
        ),
      ],
    );
  }
}

/// 顯示廣告檢查對話框的幫助函數
Future<void> showAdCheckDialog(
  BuildContext context, {
  required VoidCallback onContinue,
  required PurchaseService purchaseService,
}) async {
  // 檢查用戶是否是高級用戶
  final isPremium = await purchaseService.isPremiumUser();
  
  if (isPremium) {
    // 高級用戶直接繼續
    onContinue();
    return;
  }
  
  // 非高級用戶顯示選擇對話框
  if (context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdCheckDialog(
        onContinue: onContinue,
        purchaseService: purchaseService,
      ),
    );
  }
}
