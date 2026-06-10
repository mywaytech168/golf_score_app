# Google Play 應用內購買設置指南

## 📋 整體流程

```
1. 在 Google Play Console 建立應用
2. 設置應用簽名
3. 上傳應用 APK
4. 建立應用內產品（In-App Products）
5. 在代碼中集成 in_app_purchase 套件
6. 測試購買流程
7. 發布應用到 Google Play Store
```

---

## 🔧 步驟 1: 在 Google Play Console 中建立應用

### 1.1 訪問 Google Play Console
- 打開 https://play.google.com/console
- 用 Google 帳號登入

### 1.2 建立新應用
1. 點擊「建立應用」
2. 填入應用名稱：`Golf Score App` 或 `ORVIA`
3. 選擇預設語言：`繁體中文` 或 `英文`
4. 選擇應用類型：`應用`
5. 點擊「建立」

### 1.3 填寫基本資訊
- 應用名稱：`Golf Score App`
- 簡短描述：`高爾夫揮桿分析應用`
- 完整描述：詳細說明應用功能
- 分類：`運動`
- 內容等級：根據內容填寫

---

## 🔑 步驟 2: 設置應用簽名

### 2.1 生成簽名密鑰

在 Flutter 項目根目錄運行：

```bash
# Windows/Mac/Linux 通用方法
keytool -genkey -v -keystore ~/golf_key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias golf_key

# 或使用 Flutter 工具
flutter pub run keytool
```

**當提示時填寫以下信息：**
```
Keystore password: [輸入密碼，例如: 12345678]
Key password: [輸入密碼，同上]
First and Last Name: [您的名字]
Organizational Unit: [部門，例如: Development]
Organization Name: [公司名，例如: ORVIA]
City or Locality: [城市]
State or Province Name: [州/省]
Country Code: [國家代碼，例如: TW 表示台灣]
```

**重要信息保存：**
```
密鑰存儲路徑: ~/golf_key.jks
別名 (Alias): golf_key
密碼: [您設定的密碼]
有效期: 10000 天
```

### 2.2 查看簽名信息

獲取 SHA-1 指紋（Google Play 需要）：

```bash
keytool -list -v -keystore ~/golf_key.jks -alias golf_key
```

輸出示例：
```
SHA1: AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12
```

**複製 SHA1 指紋留著備用**

### 2.3 配置 Flutter 簽名

編輯 `android/key.properties` 文件（如果不存在則創建）：

```properties
storePassword=12345678
keyPassword=12345678
keyAlias=golf_key
storeFile=/path/to/golf_key.jks
```

編輯 `android/app/build.gradle`，在 `android` 區塊中添加：

```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile file(keystoreProperties['storeFile'])
        storePassword keystoreProperties['storePassword']
    }
}

buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

---

## 📦 步驟 3: 上傳應用 APK

### 3.1 生成簽名 APK

```bash
flutter build apk --release
```

APK 位置：`build/app/outputs/flutter-apk/app-release.apk`

### 3.2 在 Google Play Console 中上傳

1. 進入應用 → 「測試版本」
2. 選擇「內部測試」
3. 點擊「建立版本」
4. 上傳 APK 文件
5. 填寫版本資訊（版本號、更新說明等）
6. 點擊「儲存」

---

## 💰 步驟 4: 建立應用內產品

### 4.1 在 Google Play Console 中建立產品

1. 進入應用 → 「獲利」→ 「應用內產品」
2. 點擊「建立應用內產品」

### 4.2 建立「無廣告版本」產品

**產品詳情：**

| 字段 | 值 |
|------|-----|
| 產品 ID | `golf_no_ads_premium` |
| 產品名稱 | `無廣告版本` |
| 產品描述 | `購買後可無廣告使用應用` |
| 價格 | 選擇幣種和金額（建議：NT$99 或 NT$9.99） |

**狀態：** 
- 點擊「啟用」
- 點擊「儲存」

### 4.3 建立測試帳號

1. 進入「設置」→ 「開發者帳號」
2. 找到「授權的測試帳號」
3. 添加 Gmail 帳號作為測試帳號
4. 該帳號可以進行免費的測試購買

---

## 💻 步驟 5: 代碼集成（已完成）

### 5.1 查看已實現的配置

我們的應用已經集成了 `in_app_purchase` 套件：

**pubspec.yaml:**
```yaml
dependencies:
  in_app_purchase: ^3.2.3
```

**主要服務文件：**
- `lib/services/in_app_purchase_service.dart` - 購買邏輯
- `lib/services/purchase_service.dart` - 高級別購買接口
- `lib/main.dart` - 初始化代碼

### 5.2 產品 ID 配置

**Android (android/app/build.gradle)** - 已默認使用：
```dart
static const String productId = 'golf_no_ads_premium';
```

確保產品 ID 與 Google Play Console 中的完全相同。

---

## 🧪 步驟 6: 測試購買流程

### 6.1 內部測試版本

1. 在 Google Play Console 中建立內部測試版本
2. 添加測試帳號到測試者列表
3. 測試者使用該 Gmail 帳號在測試設備上安裝應用

### 6.2 使用測試帳號進行測試購買

**測試購買流程：**

1. 使用測試 Gmail 帳號登入應用
2. 進入錄影頁面
3. 點擊「錄影」按鈕
4. 選擇「購買無廣告版本」
5. 點擊「購買」按鈕
6. Google Play 購買對話框彈出
7. 點擊「購買」
8. 由於是測試帳號，系統會提示「測試購買」而不會實際扣款

### 6.3 驗證購買狀態

購買成功後，檢查：
- ✅ 應用內是否顯示「已購買」狀態
- ✅ SharedPreferences 中 `user_premium_purchase` 是否為 `true`
- ✅ 後續不再顯示廣告對話框

### 6.4 恢復購買

如果測試帳號在其他設備上安裝應用，應該能通過「恢復購買」功能恢復無廣告狀態。

---

## 📱 步驟 7: 發布到 Google Play Store

### 7.1 完成商店信息

在 Google Play Console 中填寫：
- ✅ 應用圖標 (512x512 PNG)
- ✅ 應用截圖 (至少 2 張)
- ✅ 應用預告片 (可選)
- ✅ 應用分類
- ✅ 內容評級

### 7.2 提交審核

1. 進入「準備發布」
2. 檢查所有必填項
3. 點擊「審核」
4. 點擊「確認」提交
5. 等待 Google 審核 (通常 2-4 小時)

### 7.3 應用審核要點

Google 會檢查：
- 應用是否正常運行
- 內容是否符合政策
- 購買流程是否正確
- 隱私政策是否完整

---

## 🐛 常見問題排查

### 問題 1: 「未找到產品」錯誤

**原因：** 產品 ID 與 Google Play Console 中的不一致

**解決：**
1. 檢查 `lib/services/in_app_purchase_service.dart` 中的 `productId`
2. 確保與 Google Play Console 中完全相同
3. 等待 24 小時讓 Google Play 同步

### 問題 2: 「無法連接到 Google Play」錯誤

**原因：** 設備未正確配置或帳號權限問題

**解決：**
1. 確保設備已登入 Google 帳號
2. 確保設備連接到互聯網
3. 清除 Google Play Services 緩存：
   ```bash
   adb shell pm clear com.android.vending
   ```
4. 重啟設備

### 問題 3: 測試購買失敗

**原因：** 測試帳號未正確配置

**解決：**
1. 確認帳號已添加到 Google Play Console 的測試者列表
2. 重新登入設備（使用測試 Gmail 帳號）
3. 等待 15-30 分鐘讓配置生效
4. 清除應用數據後重試

### 問題 4: 購買後仍然顯示廣告

**原因：** SharedPreferences 未正確保存購買狀態

**解決：**
```dart
// 手動測試：在代碼中添加
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('user_premium_purchase', true);

// 或使用調試面板：首頁 AppBar 的 🧪 購買測試按鈕
```

---

## 📊 完整的購買流程圖

```
用戶進入錄影頁面
    ↓
點擊「錄影」按鈕
    ↓
showAdCheckDialog() 檢查用戶狀態
    ├─ 是高級用戶? → 直接進入
    └─ 否 → 顯示廣告選擇對話框
        ↓
    用戶點擊「購買無廣告版本」
        ↓
    purchasePremium() 被觸發
        ↓
    InAppPurchaseService 調用 Google Play API
        ↓
    Google Play 購買對話框彈出
        ↓
    用戶確認購買
        ↓
    購買成功回調
        ↓
    setPremiumUser(true) 保存狀態到 SharedPreferences
        ↓
    進入錄影頁面
        ↓
    後續不再顯示廣告對話框
```

---

## 📚 相關文件位置

| 文件 | 用途 |
|------|------|
| `lib/services/in_app_purchase_service.dart` | Google Play 購買實現 |
| `lib/services/purchase_service.dart` | 購買業務邏輯 |
| `lib/widgets/ad_check_dialog.dart` | 廣告與購買對話框 UI |
| `lib/main.dart` | 應用初始化 |
| `android/app/build.gradle` | Android 簽名配置 |
| `pubspec.yaml` | 依賴配置 |

---

## ✅ 檢查清單

在上線前請確認：

- [ ] 生成了簽名密鑰 (`golf_key.jks`)
- [ ] 配置了 `android/key.properties`
- [ ] 在 Google Play Console 建立了應用
- [ ] 建立了產品 ID：`golf_no_ads_premium`
- [ ] 上傳了內部測試 APK
- [ ] 添加了測試帳號
- [ ] 進行了測試購買並驗證成功
- [ ] 填寫了應用商店資訊
- [ ] 準備了應用圖標和截圖
- [ ] 寫好了隱私政策

---

## 🎯 後續步驟

### 立即可做：
1. 如果尚未生成簽名密鑰，運行上面的 keytool 命令
2. 配置 `android/key.properties` 和 `build.gradle`
3. 在 Google Play Console 建立應用

### 待應用批準後：
1. 監控購買數據
2. 根據用戶反饋優化購買流程
3. 定期檢查 Google Play 的收益報告

---

## 📞 支持資源

- **Google Play Console 幫助**：https://support.google.com/googleplay/android-developer
- **in_app_purchase 文檔**：https://pub.dev/packages/in_app_purchase
- **Flutter 應用簽名指南**：https://flutter.dev/docs/deployment/android#signing-the-app
