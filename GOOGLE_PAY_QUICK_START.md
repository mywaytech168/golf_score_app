# Google Pay 快速設置清單

## 🎯 您需要做的 5 個步驟

### ✅ 步驟 1: 生成簽名密鑰（5 分鐘）

在終端運行：

```bash
keytool -genkey -v -keystore ~/golf_key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias golf_key
```

**記下密碼！** 例如：`12345678`

---

### ✅ 步驟 2: 配置 Android 簽名（3 分鐘）

#### 2.1 創建 `android/key.properties` 文件

內容：
```properties
storePassword=12345678
keyPassword=12345678
keyAlias=golf_key
storeFile=path/to/golf_key.jks
```

#### 2.2 編輯 `android/app/build.gradle`

在 `android {}` 塊中添加：

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
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
}
```

---

### ✅ 步驟 3: 構建簽名 APK（5 分鐘）

```bash
flutter build apk --release
```

輸出位置：`build/app/outputs/flutter-apk/app-release.apk`

---

### ✅ 步驟 4: 在 Google Play Console 中設置（30 分鐘）

#### 4.1 訪問 Google Play Console
- 打開 https://play.google.com/console
- 登入 Google 帳號

#### 4.2 建立新應用
1. 點擊「建立應用」
2. 名稱：`Golf Score App` 或 `TekSwing`
3. 點擊「建立」

#### 4.3 上傳 APK
1. 進入「測試」→ 「內部測試」
2. 點擊「建立版本」
3. 上傳 `app-release.apk`
4. 點擊「儲存」

#### 4.4 建立產品（購買項目）
1. 進入「獲利」→ 「應用內產品」
2. 點擊「建立應用內產品」
3. 填寫：
   - **產品 ID**：`golf_no_ads_premium`
   - **名稱**：`無廣告版本`
   - **說明**：`購買後可無廣告使用應用`
   - **價格**：選擇 NT$99 或您想要的價格
4. 點擊「啟用」→ 「儲存」

#### 4.5 設置測試帳號
1. 進入「設置」→ 「開發者帳號」
2. 找到「授權的測試帳號」
3. 添加您的 Gmail 帳號

---

### ✅ 步驟 5: 測試購買流程（10 分鐘）

#### 5.1 準備測試設備
1. 確保 Android 設備已連接
2. 用測試 Gmail 帳號登入設備
3. 安裝應用：`flutter run --release`

#### 5.2 進行測試購買
1. 打開應用
2. 點擊「錄影」按鈕
3. 選擇「購買無廣告版本」
4. 點擊「購買」
5. Google Play 購買對話框彈出
6. 確認購買 → **該帳號會顯示「測試購買」**

#### 5.3 驗證購買成功
- ✅ 檢查應用是否進入錄影頁面
- ✅ 後續不再顯示廣告對話框
- ✅ 設置中顯示「已購買」狀態

---

## 🎁 我們的代碼已準備好

您無需修改代碼，因為已經集成了：

| 組件 | 文件 | 狀態 |
|------|------|------|
| 購買邏輯 | `lib/services/in_app_purchase_service.dart` | ✅ 完成 |
| 購買業務 | `lib/services/purchase_service.dart` | ✅ 完成 |
| UI 對話框 | `lib/widgets/ad_check_dialog.dart` | ✅ 完成 |
| 應用初始化 | `lib/main.dart` | ✅ 完成 |

---

## 💡 常見問題

### Q: 為什麼要生成簽名密鑰？
A: Google Play Store 要求所有應用必須用密鑰簽名，防止應用被篡改。

### Q: 測試購買會不會扣款？
A: **不會！** 測試帳號進行的購買是虛擬的，Google 會告知這是「測試購買」。

### Q: 產品 ID 一定要是 `golf_no_ads_premium` 嗎？
A: 可以改，但要確保：
1. Google Play Console 中的產品 ID 與代碼中的完全相同
2. 修改代碼中的產品 ID

### Q: 多久才能在 Google Play Store 正式上線？
A: 
- 內部測試：立即可用
- 正式上線：提交後等待 2-4 小時審核
- 發布到所有用戶：審核通過後可立即發布

---

## 📞 需要幫助？

如果卡在某個步驟，告訴我：
- ❌ 在哪一步遇到問題
- ❌ 看到了什麼錯誤信息
- ❌ 您正在使用的系統 (Windows/Mac/Linux)

我會幫您詳細解決！

---

## 🚀 完成後的下一步

1. **監控收益** - 在 Google Play Console 查看購買統計
2. **收集反饋** - 看用戶是否願意購買無廣告版本
3. **優化定價** - 根據轉化率調整價格
4. **添加更多功能** - 無廣告版本可以添加額外功能
