import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 廣告服務 - 管理所有廣告操作
class AdService {
  static const String testDeviceId = 'YOUR_TEST_DEVICE_ID';
  
  // AdMob App IDs - 使用測試 IDs 進行測試
  // 生產環境請替換為真實 IDs：https://admob.google.com
  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713'; // Google 官方測試 App ID
  static const String iosAppId = 'ca-app-pub-3940256099942544~1458002754'; // Google 官方測試 App ID
  
  // 廣告單元 IDs - 測試用 IDs
  static const String interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712'; // 測試插頁廣告
  static const String rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917'; // 測試獎勵廣告
  static const String bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111'; // 測試橫幅廣告
  
  static late InterstitialAd _interstitialAd;
  static late RewardedAd _rewardedAd;

  static bool _isInterstitialAdReady = false;
  static bool _isRewardedAdReady = false;
  
  /// 初始化 Google Mobile Ads
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }
  
  /// 加載插頁廣告（全屏廣告）
  static Future<void> loadInterstitialAd() async {
    await InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          
          // 設置廣告關閉回調
          _interstitialAd.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              _isInterstitialAdReady = false;
              ad.dispose();
              // 加載下一個廣告
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              _isInterstitialAdReady = false;
              ad.dispose();
              // 加載下一個廣告
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isInterstitialAdReady = false;
          debugPrint('插頁廣告加載失敗: $error');
          // 重試加載
          Future.delayed(const Duration(seconds: 5), () {
            loadInterstitialAd();
          });
        },
      ),
    );
  }
  
  /// 加載獎勵廣告（看完廣告後能玩遊戲）
  static Future<void> loadRewardedAd() async {
    await RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdReady = true;
          
          // 設置廣告關閉回調
          _rewardedAd.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              _isRewardedAdReady = false;
              ad.dispose();
              // 加載下一個廣告
              loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              _isRewardedAdReady = false;
              ad.dispose();
              // 加載下一個廣告
              loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isRewardedAdReady = false;
          debugPrint('獎勵廣告加載失敗: $error');
          // 重試加載
          Future.delayed(const Duration(seconds: 5), () {
            loadRewardedAd();
          });
        },
      ),
    );
  }
  
  /// 顯示插頁廣告
  static Future<void> showInterstitialAd() async {
    if (_isInterstitialAdReady) {
      await _interstitialAd.show();
    } else {
      debugPrint('插頁廣告還未準備好');
      loadInterstitialAd();
    }
  }
  
  /// 顯示獎勵廣告並返回是否看完
  static Future<bool> showRewardedAd() async {
    if (_isRewardedAdReady) {
      bool rewarded = false;
      
      try {
        await _rewardedAd.show(
          onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
            rewarded = true;
            debugPrint('用戶獲得獎勵: ${reward.amount} ${reward.type}');
          },
        );
      } catch (e) {
        debugPrint('顯示廣告時出錯: $e');
        return true; // 如果廣告顯示失敗，允許用戶繼續
      }
      
      // 廣告顯示後，等待一小段時間確保 onUserEarnedReward 被觸發
      await Future.delayed(const Duration(milliseconds: 500));
      
      return rewarded;
    } else {
      debugPrint('⚠️ [AdService] 獎勵廣告尚未就緒');
      loadRewardedAd();
      return kDebugMode; // debug 模式仍允許測試；production 需真正看完廣告
    }
  }
  
  /// 創建橫幅廣告
  static BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('橫幅廣告已加載');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('橫幅廣告加載失敗: $error');
          ad.dispose();
        },
      ),
    )..load();
  }
  
  /// 清理資源
  static Future<void> dispose() async {
    if (_isInterstitialAdReady) {
      await _interstitialAd.dispose();
    }
    if (_isRewardedAdReady) {
      await _rewardedAd.dispose();
    }
  }
}
