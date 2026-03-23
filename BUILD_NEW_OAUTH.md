# 📱 建立新的 Google OAuth - 完整步驟

## 你的套件信息
- **套件名稱**: `com.example.golf_score_app`
- **平台**: Android

---

## ✅ 快速步驟 (5-10 分鐘)

### 1️⃣ 刪除舊的 OAuth (1 分鐘)

1. 打開: https://console.cloud.google.com/apis/credentials
2. 找到舊的 Android Client ID
3. 點擊右邊的三點選單 (⋮)
4. 選 **Delete**
5. 確認刪除

---

### 2️⃣ 取得你的調試 SHA-1 (2 分鐘)

在 Windows 命令列執行:

```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

會看到類似:
```
SHA1: 15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

**複製這個 SHA-1** (包含冒號)

---

### 3️⃣ 建立新的 Android OAuth (3 分鐘)

#### 步驟 A: 點擊建立
1. Google Cloud Console → Credentials
2. 按 **+ CREATE CREDENTIALS**
3. 選 **OAuth client ID**
4. 應用程式類型: **Android**

#### 步驟 B: 填寫表單
```
┌─────────────────────────────────────────┐
│ Create OAuth 2.0 Client ID              │
├─────────────────────────────────────────┤
│                                         │
│ Application type: [Android]             │
│                                         │
│ Package name:                           │
│ [com.example.golf_score_app]            │
│                                         │
│ SHA-1 certificate fingerprints:         │
│ [15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:0│
│  3:A2:21:F3:65:AA:AC:B0]                │
│                                         │
│             [CANCEL] [CREATE]           │
└─────────────────────────────────────────┘
```

**填入:**
- Package name: `com.example.golf_score_app`
- SHA-1: 貼上你上面複製的 SHA-1

#### 步驟 C: 點擊 CREATE

會看到成功訊息，顯示新的 Client ID。

---

### 4️⃣ 下載 google-services.json (2 分鐘)

#### 方法 A: 直接下載
1. 找到剛建立的 Android Client ID
2. 右上角找 **Download JSON** 按鈕
3. 按下載

#### 方法 B: 透過 Firebase Console
1. 打開: https://console.firebase.google.com/
2. 選你的專案
3. 左側 → Project settings (⚙️)
4. 下方找 "Your apps" 區域
5. 找 Android 應用
6. 點 **Download google-services.json**

---

### 5️⃣ 替換檔案 (1 分鐘)

**檔案位置:**
```
d:\project\golf\golf-score_app_1\android\app\google-services.json
```

**複製步驟:**
1. 找到下載的 google-services.json
2. 複製到上面的位置 (覆蓋舊檔案)

**或用命令列:**
```cmd
# 假設下載在 Downloads
copy "%USERPROFILE%\Downloads\google-services.json" "d:\project\golf\golf-score_app_1\android\app\google-services.json"
```

---

### 6️⃣ 編譯和測試 (3 分鐘)

```cmd
cd d:\project\golf\golf-score_app_1

# 清除快取
flutter clean
rm -r build/

# 取得依賴
flutter pub get

# 編譯執行
flutter run
```

---

### 7️⃣ 測試登入 (1 分鐘)

1. 應用啟動後
2. 按 **"Use Google Sign-In"** 按鈕
3. **預期**: 看到 Google 帳號選擇對話框
4. **選擇帳號** → 登入

---

## ⚠️ 重要提醒

### ✓ 必須相同
- Google Cloud 的 SHA-1 ✓
- 你電腦的 debug.keystore SHA-1 ✓
- 必須完全相同!

### ✓ 套件名稱一致
```
com.example.golf_score_app
```
需要在三個地方相同:
1. Google Cloud Console ✓
2. `android/app/build.gradle.kts` ✓
3. `android/app/google-services.json` ✓

### ✓ 等待時間
- 新 OAuth 可能需要 5-10 分鐘才能生效
- 有時需要 15 分鐘

---

## 📊 驗證清單

建立完後檢查:

- [ ] 舊 OAuth 已刪除
- [ ] 新 OAuth 已建立
- [ ] google-services.json 已下載
- [ ] 檔案已複製到 `android/app/`
- [ ] 執行過 `flutter clean`
- [ ] 執行過 `flutter pub get`
- [ ] 應用重新編譯
- [ ] 測試登入成功

---

## 🆘 常見問題

### Q: 找不到 "Download JSON" 按鈕?
**A**: 可能在不同位置。試試:
1. 點擊 Android Client ID 進入詳細頁面
2. 右上角看有沒有下載圖示
3. 或在 Firebase Console 下載

### Q: SHA-1 格式錯誤?
**A**: 必須是這樣格式 (帶冒號):
```
15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

### Q: 套件名稱錯了怎麼辦?
**A**: 必須是 `com.example.golf_score_app`

檢查:
```cmd
cat "d:\project\golf\golf-score_app_1\android\app\build.gradle.kts" | findstr "namespace"
```

應該看到:
```
namespace = "com.example.golf_score_app"
```

### Q: 還是 Error 10?
**A**: 試試:
1. 等待 15 分鐘 (Google 伺服器同步)
2. 執行 `flutter clean`
3. 重新卸載應用
4. 重新編譯執行

---

## ✅ 成功後

1. ✅ Google Cloud 有新的 Android OAuth
2. ✅ google-services.json 已更新
3. ✅ 應用編譯無誤
4. ✅ Google 登入對話框出現
5. ✅ 可以選擇帳號登入

---

需要幫忙嗎? 告訴我你在哪一步卡住了!
