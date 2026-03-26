import 'package:flutter/material.dart';
import '../services/ad_service.dart';
import '../services/purchase_service.dart';
import '../services/auth_token_storage.dart';
import '../services/daily_ad_manager.dart';

/// 廣告檢查對話框 - 在用戶點擊「玩」時顯示
class AdCheckDialog extends StatefulWidget {
  final VoidCallback onContinue;
  final PurchaseService purchaseService;
  final String? userId;
  
  const AdCheckDialog({
    Key? key,
    required this.onContinue,
    required this.purchaseService,
    this.userId,
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
    debugPrint('🎬 [廣告] 開始顯示獎勵廣告...');
    
    try {
      final rewarded = await AdService.showRewardedAd();
      debugPrint('🎬 [廣告] 廣告顯示完畢，rewarded=$rewarded');
      
      if (rewarded) {
        debugPrint('✅ [廣告] 用戶看完廣告，標記已使用並關閉對話框');
        
        // 標記用戶已使用今天的廣告機會
        final adManager = DailyAdManager();
        await adManager.initialize();
        await adManager.markAdAsUsed();
        debugPrint('✅ [廣告] 已記錄用戶看過廣告');
        
        if (mounted) {
          debugPrint('✅ [廣告] widget 已加載，準備關閉對話框');
          Navigator.pop(context);
          debugPrint('✅ [廣告] 對話框已關閉，調用 onContinue 回調');
          widget.onContinue();
          debugPrint('✅ [廣告] onContinue 回調已觸發');
        } else {
          debugPrint('❌ [廣告] widget 已卸載');
        }
      } else {
        debugPrint('⚠️ [廣告] 用戶未看完廣告');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('請看完廣告才能繼續')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [廣告] 顯示廣告出錯: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _purchasePremium() async {
    setState(() => _isLoading = true);
    
    try {
      String userId = widget.userId ?? '';
      if (userId.isEmpty) {
        final userEmail = await AuthTokenStorage.instance.getUserEmail();
        userId = userEmail ?? 'unknown';
      }
      
      debugPrint('� [廣告] 開始應用商店購買流程，用戶: $userId');
      final success = await widget.purchaseService.purchasePremium(userId: userId);
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 感謝您的購買！現在可以無廣告使用了')),
        );
        
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
            '� 選項 1: 購買無廣告版本',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '綠界支付 - 信用卡、ATM、超商付款\n一次性購買，永久無廣告',
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
        if (_isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
        if (!_isLoading)
          ElevatedButton.icon(
            onPressed: _purchasePremium,
            icon: const Icon(Icons.payment),
            label: const Text('購買無廣告版本'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        if (!_isLoading)
          ElevatedButton.icon(
            onPressed: _showRewardedAd,
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
  bool forceShowAd = false, // 強制顯示廣告（用於測試）
}) async {
  debugPrint('📺 [廣告] showAdCheckDialog 被觸發');
  
  // 初始化每日廣告管理
  final adManager = DailyAdManager();
  await adManager.initialize();
  
  // 檢查用戶是否是高級用戶
  final isPremium = await purchaseService.isPremiumUser();
  debugPrint('👤 [廣告] 用戶是否為高級用戶: $isPremium (forceShowAd: $forceShowAd)');
  
  if (isPremium && !forceShowAd) {
    // 高級用戶直接繼續
    debugPrint('✅ [廣告] 高級用戶，直接繼續');
    onContinue();
    return;
  }
  
  // 檢查用戶今天是否已使用過廣告機會
  final adUsedToday = await adManager.hasUsedAdToday();
  debugPrint('📺 [廣告] 今天是否已使用過廣告機會: $adUsedToday');
  
  if (adUsedToday && !forceShowAd) {
    // 已使用過一次廣告，直接進入錄影，不彈窗
    debugPrint('✅ [廣告] 用戶今天已使用過一次廣告，直接進入錄影（無彈窗）');
    onContinue();
    return;
  }
  
  // 非高級用戶且未使用過廣告 → 顯示選擇對話框
  debugPrint('🎯 [廣告] 顯示廣告選擇對話框');
  if (context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdCheckDialog(
        onContinue: onContinue,
        purchaseService: purchaseService,
      ),
    );
  } else {
    debugPrint('❌ [廣告] 無法顯示對話框 - context 已卸載');
  }
}
