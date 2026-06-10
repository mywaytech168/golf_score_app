# 🎯 Google Pay 集成 - 您需要做什麼

## ✅ 我們已經完成的部分

### 代碼層面
- ✅ 集成 `in_app_purchase` 套件 (^3.2.3)
- ✅ 建立 `InAppPurchaseService` 購買服務
- ✅ 建立 `PurchaseService` 業務邏輯層
- ✅ 集成廣告對話框 UI 和購買選項
- ✅ 建立測試調試面板
- ✅ 初始化應用啟動流程
- ✅ 配置產品 ID: `golf_no_ads_premium`
- ✅ 所有代碼已編譯通過，無錯誤

### 完整代碼位置
```
lib/
├─ main.dart (初始化)
├─ services/
│  ├─ in_app_purchase_service.dart ✅
│  ├─ purchase_service.dart ✅
│  ├─ ad_service.dart ✅
│  └─ daily_ad_manager.dart ✅
├─ widgets/
│  ├─ ad_check_dialog.dart ✅
│  └─ purchase_test_panel.dart ✅
└─ pages/
   └─ home_page.dart ✅
```

---

## ⏳ 您需要做的部分

### 第 1 步: 生成簽名密鑰 (5 分鐘)

在終端運行：
```bash
keytool -genkey -v -keystore ~/golf_key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias golf_key
```

**保存這些信息：**
- 密碼: `___________` (您設定的密碼)
- 密鑰文件路徑: `~/golf_key.jks`
- 別名: `golf_key`

---

### 第 2 步: 配置 Android 簽名 (5 分鐘)

#### 2.1 創建 `android/key.properties` 文件

```properties
storePassword=您的密碼
keyPassword=您的密碼
keyAlias=golf_key
storeFile=/Users/您的用戶名/golf_key.jks
```

#### 2.2 編輯 `android/app/build.gradle`

在 `android {}` 之前添加：

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

在 `android {}` 內添加：

```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
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

### 第 3 步: 構建簽名 APK (5 分鐘)

```bash
flutter clean
flutter pub get
flutter build apk --release
```

✅ APK 位置: `build/app/outputs/flutter-apk/app-release.apk`

---

### 第 4 步: 在 Google Play Console 設置 (30 分鐘)

#### 4.1 訪問 Google Play Console
https://play.google.com/console

#### 4.2 建立新應用
1. 點擊「建立應用」
2. 名稱: `Golf Score App` 或 `ORVIA`
3. 點擊「建立」

#### 4.3 上傳 APK
1. 進入「測試」→ 「內部測試」
2. 點擊「建立版本」
3. 上傳 `app-release.apk`
4. 填寫版本號和更新說明
5. 點擊「儲存」

#### 4.4 建立應用內產品
1. 進入「獲利」→ 「應用內產品」
2. 點擊「建立應用內產品」
3. 填寫:
   - 產品 ID: `golf_no_ads_premium`
   - 名稱: `無廣告版本`
   - 描述: `購買後可無廣告使用應用`
   - 價格: 選擇 (建議 NT$99)
4. 點擊「啟用」→ 「儲存」

#### 4.5 添加測試帳號
1. 進入「設置」→ 「開發者帳號」
2. 找「授權的測試帳號」
3. 添加您的 Gmail 帳號

---

### 第 5 步: 測試購買流程 (10 分鐘)

#### 5.1 安裝應用
```bash
flutter run --release
```

#### 5.2 測試購買
1. 用測試 Gmail 帳號登入應用
2. 點擊「錄影」
3. 選擇「購買無廣告版本」
4. 點擊「購買」
5. Google Play 購買對話框彈出
6. 確認購買 → 會顯示「測試購買」(不會扣款)

#### 5.3 驗證成功
- ✅ 應用進入錄影頁面
- ✅ 後續不顯示廣告對話框
- ✅ 購買狀態正確保存

---

## 🎁 我們提供的調試工具

### 1. 購買測試面板
- 位置: 首頁 AppBar → 🧪 購買測試按鈕
- 功能: 模擬購買、清除購買、刷新狀態

### 2. 重置廣告按鈕
- 位置: 首頁 AppBar → 🔄 重置廣告按鈕
- 功能: 快速重置廣告使用狀態

### 3. 詳細日誌
- 所有購買操作都會在控制台打印日誌
- 日誌格式: `🛒 [應用內購買]` 開頭

---

## 📊 文檔導航

| 文檔 | 用途 |
|------|------|
| `GOOGLE_PAY_QUICK_START.md` | 快速開始指南 ⭐ |
| `GOOGLE_PAY_SETUP_GUIDE.md` | 詳細設置步驟 |
| `GOOGLE_PAY_DETAILED_FLOW.md` | 流程圖和架構 |
| `DAILY_AD_MECHANISM.md` | 廣告機制說明 |

---

## ✨ 預期結果

完成上述步驟後，您的應用將：

✅ 可以在 Google Play Store 上架
✅ 支持用戶購買無廣告版本
✅ 購買後正確隱藏廣告
✅ 購買狀態正確保存
✅ 通過每日廣告一次性機制
✅ 可以進行真實購買交易
✅ 開始產生收益

---

## 🆘 常見問題速查表

| 問題 | 解決方案 |
|------|---------|
| 「找不到產品」| 檢查產品 ID 是否與 Google Play Console 一致，等待 24 小時同步 |
| 「無法連接 Google Play」| 檢查網絡連接，確保設備已用測試帳號登入 |
| 購買後仍顯示廣告 | 使用購買測試面板手動設置，或清除應用數據 |
| APK 構建失敗 | 檢查 Android SDK 版本 (minSdk 21+)，確保簽名配置正確 |
| 簽名密鑰丟失 | 無法恢復，需要重新生成並更新 Google Play Console |

---

## 📞 需要幫助？

如果您在以下任何步驟遇到問題：
1. 生成簽名密鑰
2. 配置 Android 簽名
3. 在 Google Play Console 設置
4. 測試購買流程

**請告訴我具體的錯誤信息，我會幫您詳細解決！** 💪

---

## 🚀 下一步

當完成所有測試後：

1. **提交審核** - Google 會在 2-4 小時內審核應用
2. **修復反饋** - 如果有問題，按 Google 要求修復
3. **上線發布** - 審核通過後可立即發布到 Google Play Store
4. **監控收益** - 在 Google Play Console 中查看購買統計

**祝您上線順利！** 🎉
