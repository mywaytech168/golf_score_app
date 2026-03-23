# ⚠️ 重要: 你下載的是錯誤的檔案類型!

## 問題

你下載的檔案是:
```
client_secret_446697241300-dt24k77jh2cva8qi1pbhsqd3s3a26842.apps.googleusercontent.com.json
```

這是 **Web/Desktop 類型** 的 OAuth，**不是 Android** 的!

---

## ✅ 你需要的檔案

你需要的是:
```
google-services.json
```

這是 **Android 特定** 的設定檔。

---

## 🔧 正確的步驟

### 步驟 1: 確保你建立了 Android OAuth

1. 打開: https://console.cloud.google.com/apis/credentials
2. 在 **OAuth 2.0 Client IDs** 區域
3. 應該看到一個標記為 **"Android"** 的項目

---

### 步驟 2: 下載正確的檔案

**方法 A: 直接下載 (推薦)**

1. 找到 **Android Client ID** (應該看起來像這樣):
   ```
   446697241300-???????.apps.googleusercontent.com
   Package name: com.example.golf_score_app
   SHA-1: 15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
   ```

2. 右下角應該有 **"Download JSON"** 按鈕
3. 點擊下載
4. 檔案名稱應該是 **google-services.json**

**方法 B: 透過 Firebase Console**

1. 打開: https://console.firebase.google.com/
2. 選你的專案: **golf-score-app-485702**
3. 左側 → Project settings (⚙️)
4. 往下看 **"Your apps"** 區域
5. 找 **Android** 應用
6. 點 **"google-services.json"** 下載

---

### 步驟 3: 驗證檔案內容

下載後，用文字編輯器開啟檔案，應該看起來像:

```json
{
  "project_info": {
    "project_number": "446697241300",
    "project_id": "golf-score-app-485702"
  },
  "client": [
    {
      "client_info": {
        "package_name": "com.example.golf_score_app"
      },
      "oauth_client": [
        {
          "client_id": "446697241300-???????.apps.googleusercontent.com",
          "client_type": 1,
          "android_info": {
            "package_name": "com.example.golf_score_app",
            "certificate_hash": [
              "15e70309806c5a21fab afa403a221f365aaacb0"
            ]
          }
        }
      ]
    }
  ]
}
```

**檢查點:**
- ✓ `"client_type": 1` (代表 Android)
- ✓ `"package_name": "com.example.golf_score_app"`
- ✓ `"certificate_hash"` 包含你的 SHA-1

---

### 步驟 4: 複製到正確位置

```cmd
copy "你的下載路徑\google-services.json" "d:\project\golf\golf-score_app_1\android\app\google-services.json"
```

例如:
```cmd
copy "%USERPROFILE%\Downloads\google-services.json" "d:\project\golf\golf-score_app_1\android\app\google-services.json"
```

---

### 步驟 5: 編譯執行

```cmd
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run
```

---

## 🆘 如果找不到 "Download JSON" 按鈕

可能是你沒有建立 Android OAuth。試試:

1. 確保你已經 **刪除舊的** OAuth
2. 重新建立新的:
   - 點 **+ CREATE CREDENTIALS**
   - 選 **OAuth client ID**
   - 應用程式類型: **Android**
   - Package name: `com.example.golf_score_app`
   - SHA-1: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`
   - 點 **CREATE**

3. 建立後應該會看到下載選項

---

## 📝 摘要

| 檔案 | 用途 | 你下載的 |
|------|------|--------|
| `google-services.json` | Android 設定 | ✅ 需要這個 |
| `client_secret_xxxx.json` | Web/Desktop OAuth | ❌ 不需要 |

---

需要幫忙嗎? 告訴我你卡在哪一步!
