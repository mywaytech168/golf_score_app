# Google Play 應用內購買實現流程圖

## 🎯 整體架構圖

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter 應用 (Golf Score App)            │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  用戶界面層                                            │   │
│  │  ├─ ad_check_dialog.dart (廣告選擇對話框)            │   │
│  │  ├─ purchase_test_panel.dart (購買測試面板)         │   │
│  │  └─ home_page.dart (首頁)                           │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  業務邏輯層                                            │   │
│  │  ├─ purchase_service.dart (購買業務)                 │   │
│  │  ├─ ad_service.dart (廣告服務)                       │   │
│  │  └─ daily_ad_manager.dart (每日廣告管理)             │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Google Play 集成層                                   │   │
│  │  └─ in_app_purchase_service.dart                    │   │
│  │      ├─ initialize()                                │   │
│  │      ├─ getProductDetails()                         │   │
│  │      ├─ purchasePremium()                           │   │
│  │      ├─ restorePurchases()                          │   │
│  │      └─ verifyAndCompletePurchase()                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  本地存儲層                                            │   │
│  │  └─ SharedPreferences                               │   │
│  │      ├─ user_premium_purchase (購買狀態)            │   │
│  │      ├─ daily_ad_watched_date (廣告日期)            │   │
│  │      └─ daily_ad_used_today (每日廣告使用狀態)      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                Google Play 服務後端                          │
│  ├─ 驗證購買簽名                                            │
│  ├─ 處理退款                                                │
│  ├─ 同步購買狀態                                            │
│  └─ 收益統計                                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 📱 用戶購買流程時序圖

```
用戶                    應用                 Google Play 服務
  │                      │                        │
  ├─ 點擊錄影 ─────────>│                        │
  │                      │ showAdCheckDialog()   │
  │                      │ isPremiumUser()       │
  │                      │ hasUsedAdToday()      │
  │                      ├─ 讀取 SharedPrefs    │
  │<─────────────────────┤                       │
  │  顯示廣告對話框      │                        │
  │                      │                        │
  ├─ 點擊購買 ───────>│ purchasePremium()    │
  │                      │ InAppPurchaseService │
  │                      │ queryProductDetails()│
  │                      ├─────────────────────>│ 查詢產品
  │                      │<─────────────────────┤ 返回產品信息
  │                      ├─ 顯示購買對話框     │
  │<─────────────────────┤                       │
  │ Google Play 購買     │                        │
  │ 對話框彈出           │                        │
  │                      │                        │
  ├─ 確認購買 ────────>│                        │
  │                      │ requestPurchase()    │
  │                      ├─────────────────────>│ 發起購買
  │                      │                      ├─ 驗證帳號
  │                      │                      ├─ 驗證支付方式
  │                      │                      ├─ 處理支付
  │                      │<─────────────────────┤ 購買成功
  │                      │ 購買完成回調         │
  │                      │ purchaseUpdated()    │
  │                      ├─ verifyPurchase()   │
  │                      ├─ setPremiumUser()   │
  │                      ├─ 保存到 SharedPrefs│
  │                      ├─ markAdAsUsed()     │
  │<─────────────────────┤ 進入錄影            │
  │  錄影頁面 ✅         │                        │
```

---

## 🔄 應用啟動時的初始化流程

```
main()
  ↓
1. WidgetsFlutterBinding.ensureInitialized()
  ↓
2. MobileAds.instance.initialize()
   └─ 初始化 Google Mobile Ads
  ↓
3. InAppPurchaseService.initialize()
   ├─ 檢查設備是否支持應用內購買
   ├─ 設置購買監聽器
   └─ 恢復之前的購買
  ↓
4. PurchaseService().initialize()
   └─ 初始化購買業務邏輯層
  ↓
5. DailyAdManager().initialize()
   ├─ 初始化每日廣告管理
   └─ 檢查是否需要重置廣告狀態
  ↓
6. AdService.loadInterstitialAd()
   └─ 預加載插頁廣告
  ↓
7. AdService.loadRewardedAd()
   └─ 預加載獎勵廣告
  ↓
8. runApp(MyApp())
   └─ 應用就緒
```

---

## 💰 購買流程詳細步驟

```
用戶在 ad_check_dialog.dart 中點擊「購買無廣告版本」
  ↓
_purchasePremium() 被觸發
  ↓
┌─────────────────────────────────────────────┐
│ Step 1: 準備用戶信息                          │
├─────────────────────────────────────────────┤
│ - 獲取用戶 Email 或 ID                      │
│ - 用於後端驗證和統計                        │
└─────────────────────────────────────────────┘
  ↓
PurchaseService.purchasePremium(userId: userId)
  ↓
┌─────────────────────────────────────────────┐
│ Step 2: 調用 InAppPurchaseService           │
├─────────────────────────────────────────────┤
│ InAppPurchaseService().purchasePremium()   │
│ 返回: Future<bool>                         │
└─────────────────────────────────────────────┘
  ↓
InAppPurchaseService.purchasePremium()
  ↓
┌─────────────────────────────────────────────┐
│ Step 3: 查詢產品信息                        │
├─────────────────────────────────────────────┤
│ getProductDetails() 查詢 google_play        │
│ 返回:                                       │
│ - productId: "golf_no_ads_premium"         │
│ - price: "NT$99.00"                        │
│ - title: "無廣告版本"                       │
└─────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────┐
│ Step 4: 發起購買                            │
├─────────────────────────────────────────────┤
│ InAppPurchase.instance.buyConsumable()    │
│ (或 buyNonConsumable() 取決於產品類型)     │
│ 返回: Future<void>                         │
└─────────────────────────────────────────────┘
  ↓
[Google Play 購買對話框彈出]
  ↓
用戶確認購買
  ↓
┌─────────────────────────────────────────────┐
│ Step 5: 處理購買完成                        │
├─────────────────────────────────────────────┤
│ purchaseUpdated() 回調被觸發                │
│ - 狀態檢查: PurchaseStatus.purchased        │
└─────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────┐
│ Step 6: 驗證購買簽名                        │
├─────────────────────────────────────────────┤
│ verifyAndCompletePurchase()                │
│ - 驗證 Google 簽名                         │
│ - 確認購買合法性                            │
│ - 檢查是否已消費                            │
└─────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────┐
│ Step 7: 完成消費                            │
├─────────────────────────────────────────────┤
│ consumePurchase() 或 markPurchaseAsComplete
│ 告知 Google Play 購買已完成                 │
└─────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────┐
│ Step 8: 更新本地狀態                        │
├─────────────────────────────────────────────┤
│ setPremiumUser(true, 'google_play')        │
│ - 設置 user_premium_purchase = true        │
│ - 設置 user_payment_method = "google_play" │
│ markAdAsUsed()                             │
│ - 設置 daily_ad_used_today = true          │
└─────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────┐
│ Step 9: 返回成功                            │
├─────────────────────────────────────────────┤
│ 方法返回 true                               │
│ 觸發 onContinue() 回調                      │
└─────────────────────────────────────────────┘
  ↓
[關閉購買對話框]
  ↓
[進入錄影頁面] ✅
```

---

## 🔐 Google Play 安全驗證流程

```
應用發起購買請求
  ↓
[Google Play 服務]
  ├─ 驗證帳號身份
  ├─ 檢查帳號是否在測試清單（測試購買）
  ├─ 驗證支付方式
  ├─ 處理支付交易
  └─ 生成購買令牌和簽名
  ↓
應用接收購買結果
  ├─ purchaseToken (購買令牌)
  ├─ orderId (訂單 ID)
  └─ signature (Google 簽名)
  ↓
應用驗證簽名
  ├─ 使用 Google Play 公鑰
  ├─ 驗證簽名的完整性
  └─ 確認購買數據未被篡改
  ↓
[簽名驗證成功] ✅
  ├─ 授予用戶權限
  ├─ 保存購買狀態
  └─ 向 Google Play 確認已完成
  ↓
[應用更新]
  ├─ 隱藏廣告
  ├─ 解鎖高級功能
  └─ 顯示感謝信息
```

---

## 📊 配置檢查清單

### ✅ Flutter 代碼層面

```
lib/
├─ main.dart
│  └─ ✅ InAppPurchaseService.initialize()
│  └─ ✅ DailyAdManager().initialize()
│
├─ services/
│  ├─ in_app_purchase_service.dart
│  │  ├─ ✅ productId = 'golf_no_ads_premium'
│  │  ├─ ✅ initialize()
│  │  ├─ ✅ getProductDetails()
│  │  ├─ ✅ purchasePremium()
│  │  ├─ ✅ restorePurchases()
│  │  └─ ✅ verifyAndCompletePurchase()
│  │
│  ├─ purchase_service.dart
│  │  ├─ ✅ isPremiumUser()
│  │  ├─ ✅ setPremiumUser()
│  │  └─ ✅ purchasePremium()
│  │
│  ├─ ad_service.dart
│  │  ├─ ✅ loadRewardedAd()
│  │  └─ ✅ showRewardedAd()
│  │
│  └─ daily_ad_manager.dart
│     ├─ ✅ hasUsedAdToday()
│     ├─ ✅ markAdAsUsed()
│     └─ ✅ resetAdUsage()
│
├─ widgets/
│  ├─ ad_check_dialog.dart
│  │  ├─ ✅ 廣告對話框 UI
│  │  ├─ ✅ _showRewardedAd()
│  │  └─ ✅ _purchasePremium()
│  │
│  └─ purchase_test_panel.dart
│     └─ ✅ 購買測試調試面板
│
└─ pages/
   └─ home_page.dart
      └─ ✅ 🔄 重置廣告調試按鈕
```

### ✅ 配置文件層面

```
pubspec.yaml
├─ ✅ in_app_purchase: ^3.2.3
├─ ✅ google_mobile_ads: ^4.0.0
├─ ✅ shared_preferences: ^2.3.2
└─ ✅ 其他依賴

android/app/build.gradle
├─ ✅ minSdkVersion 21+ (支持應用內購買)
└─ ✅ 簽名配置

android/key.properties
└─ ⏳ 待建立 (您需要創建)
```

### ✅ Google Play Console 層面

```
Google Play Console 中的應用
├─ ⏳ 應用基本信息
│  ├─ 應用名稱
│  ├─ 應用圖標
│  └─ 應用分類
│
├─ ⏳ 上傳 APK
│  └─ 內部測試版本
│
├─ ⏳ 應用內產品
│  └─ Product ID: golf_no_ads_premium
│     ├─ 名稱: 無廣告版本
│     ├─ 描述: 購買後可無廣告使用應用
│     └─ 價格: NT$99 (或其他)
│
└─ ⏳ 測試帳號
   └─ 添加 Gmail 帳號作為測試者
```

---

## 🎁 產品類型說明

```
消耗性產品 (Consumable)
  ├─ 例如: 金幣、道具
  ├─ 特性: 可多次購買
  ├─ 必須消費 (consume) 後才能再購買
  └─ 我們的應用: ❌ 不使用

非消耗性產品 (Non-Consumable)
  ├─ 例如: 無廣告版本、VIP 會員
  ├─ 特性: 購買一次永久擁有
  ├─ 無需消費，永久存在
  └─ 我們的應用: ✅ 使用此類型

訂閱產品 (Subscription)
  ├─ 例如: 月度 VIP、年度會員
  ├─ 特性: 自動續費
  ├─ 可設置試用期
  └─ 我們的應用: ❌ 暫不使用
```

---

## 📈 收益追蹤

```
用戶購買後 → Google Play 收取費用 (30% 服務費)
              │
              ├─ Google Play 抽成: 30%
              └─ 開發者收益: 70%
              
例如: 用戶花費 NT$99
      ├─ Google Play: NT$29.7
      └─ 您的收入: NT$69.3

收益查看位置:
Google Play Console → 財務 → 收益報表
```

---

## 🚀 上線前的最後檢查

```
┌─────────────────────────────────────────────┐
│ 功能測試                                      │
├─────────────────────────────────────────────┤
│ ✅ 查詢產品信息成功                         │
│ ✅ 購買流程能正常啟動                       │
│ ✅ Google Play 購買對話框正常彈出          │
│ ✅ 購買完成後應用能正常進入                 │
│ ✅ 購買狀態正確保存到 SharedPreferences    │
│ ✅ 下次進入應用無廣告對話框                 │
│ ✅ 購買測試面板功能正常                     │
│ ✅ 重置廣告按鈕功能正常                     │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 應用商店信息                                  │
├─────────────────────────────────────────────┤
│ ✅ 應用名稱完整                             │
│ ✅ 應用描述清晰                             │
│ ✅ 應用截圖至少 2 張                       │
│ ✅ 應用圖標 512x512 PNG                    │
│ ✅ 隱私政策已提供                           │
│ ✅ 內容分級已完成                           │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 安全和合規                                    │
├─────────────────────────────────────────────┤
│ ✅ APK 已簽名                               │
│ ✅ 簽名密鑰已妥善保管                       │
│ ✅ 產品 ID 正確配置                         │
│ ✅ Google Play 政策已閱讀                  │
│ ✅ 應用內購買描述清晰                       │
│ ✅ 退款政策已說明                           │
└─────────────────────────────────────────────┘
```

---

## 📞 遇到問題？

### 「找不到產品」錯誤
```
原因: 產品 ID 不匹配
解決:
1. 檢查 Google Play Console 中的產品 ID
2. 確保代碼中的 productId 完全相同
3. 等待 24 小時讓 Google Play 同步
```

### 「無法連接到 Google Play」
```
原因: 網絡或帳號問題
解決:
1. 確保設備連接網絡
2. 使用測試 Gmail 帳號登入設備
3. 檢查帳號是否被添加到測試者列表
```

### 「購買後仍顯示廣告」
```
原因: 購買狀態未正確保存
解決:
1. 檢查 SharedPreferences 是否保存
2. 使用購買測試面板手動設置
3. 清除應用數據後重試
```

---

## ✨ 恭喜！

當您完成上述所有步驟後，您的應用將：

✅ 支持 Google Play 購買
✅ 提供無廣告版本
✅ 可在 Google Play Store 上架
✅ 開始產生收益
✅ 通過官方應用商店向全球用戶發布

**準備好了嗎？讓我們開始吧！** 🚀
