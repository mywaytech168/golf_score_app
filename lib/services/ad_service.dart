import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'auth_token_storage.dart';

/// 廣告服務 - 管理所有廣告操作
class AdService {
  /// 是否顯示廣告。僅 Free 方案為 true；Pro / Elite 免廣告。
  /// 由 [PlanProvider.refresh] 依當前方案更新。
  static bool adsEnabled = true;

  // ── 橫幅廣告 ──────────────────────────────────────────────────
  static String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-6355169055224194/YOUR_ANDROID_BANNER_ID'
        : 'ca-app-pub-6355169055224194/4074869153';
  }

  // ── 插頁廣告單元 IDs ──────────────────────────────────────────
  static String get _interstitialAiCoachId => Platform.isAndroid
      ? 'ca-app-pub-6355169055224194/3885339495'
      : 'ca-app-pub-6355169055224194/2105353968';

  static String get _interstitialBallDetectionId => Platform.isAndroid
      ? 'ca-app-pub-6355169055224194/7194029113'
      : 'ca-app-pub-6355169055224194/8479190620';

  static String get _interstitialFullAnalysisId => Platform.isAndroid
      ? 'ca-app-pub-6355169055224194/3254784102'
      : 'ca-app-pub-6355169055224194/5853027286';

  // ── 獎勵廣告單元 IDs ──────────────────────────────────────────
  static String get _rewardedAiCoachId => Platform.isAndroid
      ? 'ca-app-pub-6355169055224194/5486351308'
      : 'ca-app-pub-6355169055224194/9600700602';

  static String _resolveInterstitialId(String productionId) {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return productionId;
  }

  static String _resolveRewardedId(String productionId) {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return productionId;
  }

  // ── 廣告實例 ──────────────────────────────────────────────────
  static InterstitialAd? _aiCoachAd;
  static InterstitialAd? _ballDetectionAd;
  static InterstitialAd? _fullAnalysisAd;
  static RewardedAd?     _rewardedAiCoachAd;

  /// 初始化 Google Mobile Ads
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    await Future.wait([
      loadAiCoachInterstitial(),
      loadBallDetectionInterstitial(),
      loadFullAnalysisInterstitial(),
      loadRewardedAiCoach(),
    ]);
  }

  // ── 載入方法 ──────────────────────────────────────────────────

  static Future<void> loadAiCoachInterstitial() async {
    await InterstitialAd.load(
      adUnitId: _resolveInterstitialId(_interstitialAiCoachId),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _aiCoachAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) { ad.dispose(); _aiCoachAd = null; loadAiCoachInterstitial(); },
            onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _aiCoachAd = null; loadAiCoachInterstitial(); },
          );
        },
        onAdFailedToLoad: (e) {
          debugPrint('[AdService] AI Coach 插頁廣告載入失敗: $e');
          Future.delayed(const Duration(seconds: 30), loadAiCoachInterstitial);
        },
      ),
    );
  }

  static Future<void> loadBallDetectionInterstitial() async {
    await InterstitialAd.load(
      adUnitId: _resolveInterstitialId(_interstitialBallDetectionId),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ballDetectionAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) { ad.dispose(); _ballDetectionAd = null; loadBallDetectionInterstitial(); },
            onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _ballDetectionAd = null; loadBallDetectionInterstitial(); },
          );
        },
        onAdFailedToLoad: (e) {
          debugPrint('[AdService] 偵測擊球插頁廣告載入失敗: $e');
          Future.delayed(const Duration(seconds: 30), loadBallDetectionInterstitial);
        },
      ),
    );
  }

  static Future<void> loadFullAnalysisInterstitial() async {
    await InterstitialAd.load(
      adUnitId: _resolveInterstitialId(_interstitialFullAnalysisId),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _fullAnalysisAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) { ad.dispose(); _fullAnalysisAd = null; loadFullAnalysisInterstitial(); },
            onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _fullAnalysisAd = null; loadFullAnalysisInterstitial(); },
          );
        },
        onAdFailedToLoad: (e) {
          debugPrint('[AdService] 完整分析插頁廣告載入失敗: $e');
          Future.delayed(const Duration(seconds: 30), loadFullAnalysisInterstitial);
        },
      ),
    );
  }

  static Future<void> loadRewardedAiCoach() async {
    await RewardedAd.load(
      adUnitId: _resolveRewardedId(_rewardedAiCoachId),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) async {
          // SSV：把 userId 綁進 Google 回呼，server 驗簽後依此記錄觀看事件
          try {
            final userId = await AuthTokenStorage.instance.getUserId();
            if (userId != null && userId.isNotEmpty) {
              await ad.setServerSideOptions(
                  ServerSideVerificationOptions(userId: userId));
            }
          } catch (e) {
            debugPrint('[AdService] 設定 SSV userId 失敗: $e');
          }
          _rewardedAiCoachAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) { ad.dispose(); _rewardedAiCoachAd = null; loadRewardedAiCoach(); },
            onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _rewardedAiCoachAd = null; loadRewardedAiCoach(); },
          );
        },
        onAdFailedToLoad: (e) {
          debugPrint('[AdService] AI Coach 獎勵廣告載入失敗: $e');
          Future.delayed(const Duration(seconds: 30), loadRewardedAiCoach);
        },
      ),
    );
  }

  // ── 顯示方法 ──────────────────────────────────────────────────

  /// 顯示 AI Coach 插頁廣告（分析完成後呼叫）
  static Future<void> showAiCoachInterstitial() async {
    if (!adsEnabled) return; // Pro / Elite 免廣告
    if (_aiCoachAd != null) {
      await _aiCoachAd!.show();
    } else {
      debugPrint('[AdService] AI Coach 插頁廣告尚未就緒');
      loadAiCoachInterstitial();
    }
  }

  /// 顯示偵測擊球插頁廣告
  static Future<void> showBallDetectionInterstitial() async {
    if (!adsEnabled) return; // Pro / Elite 免廣告
    if (_ballDetectionAd != null) {
      await _ballDetectionAd!.show();
    } else {
      debugPrint('[AdService] 偵測擊球插頁廣告尚未就緒');
      loadBallDetectionInterstitial();
    }
  }

  /// 顯示完整分析插頁廣告
  static Future<void> showFullAnalysisInterstitial() async {
    if (!adsEnabled) return; // Pro / Elite 免廣告
    if (_fullAnalysisAd != null) {
      await _fullAnalysisAd!.show();
    } else {
      debugPrint('[AdService] 完整分析插頁廣告尚未就緒');
      loadFullAnalysisInterstitial();
    }
  }

  /// 顯示獎勵廣告，返回是否看完
  static Future<bool> showRewardedAiCoach() async {
    if (_rewardedAiCoachAd != null) {
      bool rewarded = false;
      try {
        await _rewardedAiCoachAd!.show(
          onUserEarnedReward: (_, reward) {
            rewarded = true;
            debugPrint('[AdService] 用戶獲得獎勵: ${reward.amount} ${reward.type}');
          },
        );
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[AdService] 顯示獎勵廣告出錯: $e');
        return false;
      }
      return rewarded;
    } else {
      debugPrint('[AdService] AI Coach 獎勵廣告尚未就緒');
      loadRewardedAiCoach();
      return kDebugMode;
    }
  }

  /// 清理資源
  static Future<void> dispose() async {
    await _aiCoachAd?.dispose();
    await _ballDetectionAd?.dispose();
    await _fullAnalysisAd?.dispose();
    await _rewardedAiCoachAd?.dispose();
  }
}
