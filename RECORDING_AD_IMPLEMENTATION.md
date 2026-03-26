# 錄影廣告實現文檔

## 功能概述

當用戶按下錄影按鈕時，系統會先顯示廣告檢查對話框。根據用戶的購買狀態，提供兩種選項：

1. **高級用戶**（已購買無廣告版本）：直接進入錄影
2. **普通用戶**：
   - 選項 A：觀看獎勵廣告後進入錄影
   - 選項 B：購買無廣告版本，永久無廣告

## 實現方式

### 修改位置

`lib/recorder_page.dart` - `_openRecordingSession()` 方法

### 主要改動

1. **添加導入**：
   ```dart
   import 'services/purchase_service.dart';
   import 'widgets/ad_check_dialog.dart';
   ```

2. **修改 `_openRecordingSession()` 方法**：
   - 現在先顯示廣告檢查對話框（`showAdCheckDialog`）
   - 用戶確認後才進行實際錄影

3. **新增 `_proceedWithRecordingSession()` 方法**：
   - 包含原來的錄影邏輯
   - 在廣告檢查後執行

### 工作流程

```
用戶點擊「開始錄影」按鈕
        ↓
觸發 _openRecordingSession()
        ↓
初始化 PurchaseService
        ↓
顯示 AdCheckDialog
        ↓
  ├─ 如果是高級用戶 → 直接調用 onContinue()
  ├─ 如果選擇看廣告 → 播放獎勵廣告 → 調用 onContinue()
  └─ 如果選擇購買 → 購買流程 → 調用 onContinue()
        ↓
調用 _proceedWithRecordingSession()（實際錄影邏輯）
        ↓
導航到 RecordingSessionPage
```

## 廣告系統架構

### 相關文件

- `lib/services/ad_service.dart` - 廣告加載和顯示
- `lib/services/purchase_service.dart` - 購買狀態管理
- `lib/widgets/ad_check_dialog.dart` - 廣告檢查對話框 UI

### 廣告類型

- **獎勵廣告** (Rewarded Ads)：用戶看完廣告後獲得獎勵（進入錄影）
- **插頁廣告** (Interstitial Ads)：全屏廣告（可選）
- **橫幅廣告** (Banner Ads)：頁面底部橫幅（可選）

### 生產環境配置

當準備發佈應用時，需要在 `ad_service.dart` 中替換測試 Ad Unit IDs 為生產 IDs：

```dart
// 測試 IDs（當前使用）
static const String rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

// 生產 IDs（需要從 AdMob 申請）
static const String rewardedAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyyyyyy';
```

## 測試

### 本地測試

1. 編譯並運行應用
2. 點擊「開始錄影」按鈕
3. 應該看到廣告檢查對話框，包含兩個選項
4. 選擇「看廣告再玩」會顯示測試獎勵廣告
5. 廣告看完後，應該進入錄影頁面

### 購買狀態測試

- 在 `purchase_service.dart` 中手動調用 `setPremiumUser(true)` 測試高級用戶流程
- 或通過 SharedPreferences 設置 `user_premium_purchase = true`

## 注意事項

1. **廣告顯示延遲**：第一次顯示廣告可能需要 1-2 秒加載
2. **測試設備**：使用 AdMob 測試 IDs 時廣告可能不總是顯示
3. **購買集成**：目前 `purchasePremium()` 需要集成真實支付系統（Google Play Billing 或 App Store）
4. **用戶體驗**：廣告對話框是模態對話框，用戶必須做出選擇才能繼續

## 未來改進

1. 集成真實支付系統（Google Play Billing、App Store In-App Purchase）
2. 添加廣告展示頻率控制（例如，每次錄影都展示 vs 定時展示）
3. 添加廣告跳過選項（如果需要）
4. 集成 Firebase Analytics 追蹤廣告轉化率

