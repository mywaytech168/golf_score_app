# 一次性廣告機制說明文檔

## 功能設計

實現了"一次性廣告"機制，允許用戶每天看一次廣告即可直接進入錄影，無需再次彈窗。

## 工作流程

### 1. 首次進入錄影頁面（今天還沒看過廣告）
- 用戶按下「錄影」或「IMU 按鈕」
- `showAdCheckDialog()` 檢查：
  - 是否是高級用戶 → 直接進入
  - 是否今天已使用過廣告 → 直接進入
  - 都沒有 → 彈出廣告選擇對話框
- 用戶選擇「看廣告玩」
- 看完廣告後：
  - 調用 `DailyAdManager.markAdAsUsed()` 標記已使用
  - 對話框關閉
  - `onContinue()` 回調觸發
  - 進入錄影畫面

### 2. 再次按錄影按鈕（今天已看過廣告）
- 用戶按下「錄影」或「IMU 按鈕」
- `showAdCheckDialog()` 檢查：
  - 已使用過廣告 → **直接進入，無彈窗**
- 直接進入錄影畫面

### 3. 中途離開（回到首頁或其他頁面）
- 廣告使用狀態保存在 SharedPreferences
- 即使用戶回到首頁，使用狀態仍然保留
- 再次進入時，仍然不會彈窗

### 4. 隔天重置
- `DailyAdManager._checkAndResetDaily()` 自動檢查日期
- 如果是新的一天，重置廣告使用狀態
- 用戶又可以看一次廣告

## 關鍵代碼位置

### DailyAdManager (`lib/services/daily_ad_manager.dart`)
```dart
// 檢查用戶今天是否已使用過廣告
Future<bool> hasUsedAdToday() async

// 標記用戶已使用廣告（看完後調用）
Future<void> markAdAsUsed() async

// 重置廣告使用狀態（測試用）
Future<void> resetAdUsage() async
```

### ad_check_dialog.dart 修改
```dart
// 在 _showRewardedAd() 中，看完廣告後調用
final adManager = DailyAdManager();
await adManager.initialize();
await adManager.markAdAsUsed();
```

### showAdCheckDialog() 函數修改
```dart
// 檢查今天是否已使用過廣告機會
final adUsedToday = await adManager.hasUsedAdToday();
if (adUsedToday && !forceShowAd) {
  // 直接進入，無彈窗
  onContinue();
  return;
}
```

## 測試方法

### 方式1：使用測試按鈕
1. 在調試模式下運行應用
2. 首頁 AppBar 右上方有 2 個調試按鈕：
   - 🧪 購買測試：測試購買功能
   - 🔄 重置廣告：重置廣告使用狀態
3. 點擊「🔄 重置廣告」按鈕
4. 彈出 SnackBar 提示「✅ 廣告使用狀態已重置」

### 方式2：手動測試流程
1. 第一次按錄影 → 看完廣告 → 進入錄影畫面 ✅
2. 回到首頁，再按錄影 → **不彈窗，直接進入錄影** ✅
3. 點擊「🔄 重置廣告」按鈕
4. 再按錄影 → 重新彈出廣告對話框 ✅

### 方式3：卸載應用或清除數據後重新啟動
- 廣告狀態會重置
- 再按錄影時會彈出廣告對話框

## LocalStorage 字段

廣告狀態保存在 SharedPreferences 中：
- `daily_ad_watched_date`：最後一次看廣告的日期 (YYYY-MM-DD 格式)
- `daily_ad_used_today`：是否在今天已使用過廣告機會 (boolean)

## 日期判斷

使用 `DateTime.now().toString().split(' ')[0]` 獲取日期字符串 (YYYY-MM-DD 格式)，
每次調用 `hasUsedAdToday()` 或相關方法時自動檢查是否進入新的一天。

## 調試日誌

當用戶進行廣告相關操作時，控制台會打印以下日誌：
```
🗓️ [廣告] 新的一天，已重置廣告使用狀態
✅ [廣告] 已標記用戶使用了今天的廣告機會
📺 [廣告] 今天是否已使用過廣告機會: true
✅ [廣告] 用戶今天已使用過一次廣告，直接進入錄影（無彈窗）
🔄 [廣告] 已重置廣告使用狀態（測試用）
```

## 文件修改列表

1. **新增**: `lib/services/daily_ad_manager.dart` - 每日廣告管理服務
2. **修改**: `lib/widgets/ad_check_dialog.dart`
   - 添加 DailyAdManager import
   - 在 `_showRewardedAd()` 中調用 `markAdAsUsed()`
   - 在 `showAdCheckDialog()` 中添加廣告使用狀態檢查
3. **修改**: `lib/main.dart`
   - 添加 DailyAdManager import
   - 在 main() 中初始化 DailyAdManager
4. **修改**: `lib/pages/home_page.dart`
   - 添加 DailyAdManager import
   - 在 AppBar 中添加「🔄 重置廣告」調試按鈕
   - 添加重置廣告的點擊處理邏輯

## 注意事項

- ✅ 廣告使用狀態是全局的，不分錄影、IMU 按鈕等操作
- ✅ 一旦看完廣告，該天內所有進入錄影的操作都不會彈窗
- ✅ 隔天時自動重置，無需手動處理
- ✅ 高級用戶購買後不受廣告機制影響，始終直接進入
- ✅ 可通過 `forceShowAd=true` 參數強制顯示廣告（測試用）
