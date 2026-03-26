# 廣告未顯示 - 調試指南

## 問題診斷

### 可能的原因

1. **用戶是高級用戶**
   - 如果用戶在 SharedPreferences 中被標記為 `user_premium_purchase = true`
   - 系統會直接進入錄影，不顯示廣告對話框

2. **廣告服務未初始化**
   - `AdService` 在 `main.dart` 中應該被初始化
   - 檢查 logcat 中是否有初始化錯誤

3. **網絡問題**
   - 廣告需要聯網
   - 檢查設備是否連接到互聯網

4. **Context 已卸載**
   - 對話框顯示時 context 已經卸載
   - 應用在後台時切換到前台

## 調試步驟

### 步驟 1：檢查日誌

在 logcat 中查看以下日誌：

```
🎬 [錄影] _openRecordingSession 被觸發
👤 [錄影] 用戶是否為高級用戶: true/false
🎯 [錄影] 顯示廣告檢查對話框...
📺 [廣告] showAdCheckDialog 被觸發
```

### 步驟 2：清除高級用戶狀態（測試）

**方式 A：修改代碼**

在 `lib/recorder_page.dart` 中取消註釋以下行：

```dart
// 在 _openRecordingSession 方法中，大約第 2325 行
// 【開發/測試】如果需要測試廣告，可以清除高級狀態
await purchaseService.debugClearPremiumStatus();  // ← 取消註釋
```

然後重新編譯並運行。

**方式 B：使用 Flutter 命令清除數據**

```bash
# 清除應用數據（會重置所有設置）
adb shell pm clear com.golf_score_app
```

**方式 C：使用 Dart DevTools**

1. 在 Android Studio 中打開 Dart DevTools
2. 找到 SharedPreferences 部分
3. 刪除 `user_premium_purchase` 鍵

### 步驟 3：強制顯示廣告（測試）

在 `lib/recorder_page.dart` 的 `_openRecordingSession` 方法中：

```dart
showAdCheckDialog(
  context,
  onContinue: () async { ... },
  purchaseService: purchaseService,
  forceShowAd: true,  // ← 改成 true 強制顯示廣告
);
```

### 步驟 4：檢查廣告服務

確認 `lib/main.dart` 中廣告服務已正確初始化：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 Google Mobile Ads
  await MobileAds.instance.initialize();  // ← 應該在這裡
  
  // 預加載廣告
  AdService.loadInterstitialAd();
  AdService.loadRewardedAd();  // ← 應該在這裡
  
  // ...
}
```

## 預期行為

### 普通用戶（非高級用戶）

1. 點擊「開始錄影」按鈕
2. ✅ 應該看到「廣告檢查對話框」
3. 顯示兩個選項：
   - 💰 購買無廣告版本
   - 📺 看廣告再玩
4. 選擇任意一個選項後，進入錄影頁面

### 高級用戶（已購買無廣告版本）

1. 點擊「開始錄影」按鈕
2. ✅ **直接進入錄影頁面**，不顯示廣告對話框

## 完整日誌示例

### 正常流程（普通用戶）

```
🎬 [錄影] _openRecordingSession 被觸發
📱 [錄影] 初始化 PurchaseService...
👤 [錄影] 用戶是否為高級用戶: false
🎯 [錄影] 顯示廣告檢查對話框...
📺 [廣告] showAdCheckDialog 被觸發
🎯 [廣告] 顯示廣告選擇對話框
✅ [錄影] 用戶已確認廣告，準備進入錄影...
```

### 高級用戶流程

```
🎬 [錄影] _openRecordingSession 被觸發
📱 [錄影] 初始化 PurchaseService...
👤 [錄影] 用戶是否為高級用戶: true
🎯 [錄影] 顯示廣告檢查對話框...
📺 [廣告] showAdCheckDialog 被觸發
✅ [廣告] 高級用戶，直接繼續
```

## 常見問題

### Q: 我是高級用戶，想看廣告對話框怎麼辦？
A: 在 `_openRecordingSession` 中設置 `forceShowAd: true`

### Q: 廣告一直不顯示
A: 
1. 檢查網絡連接
2. 確認 AdMob 設置正確
3. 在 logcat 中查看是否有廣告加載錯誤

### Q: 看廣告後還是回到登入頁面？
A: 這是之前的 Google Sign-In Token 問題（已在 login_page.dart 中修復）

## 重置為初始狀態

如果想完全重置應用狀態（用於測試）：

```bash
# Android
adb shell pm clear com.golf_score_app

# 然後重新運行應用
flutter run
```

