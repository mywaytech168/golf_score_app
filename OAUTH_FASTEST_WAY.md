# 🚀 建立新 OAuth - 最快方式

## 你的套件名稱
```
com.example.golf_score_app
```

## 3 個簡單步驟

### ✅ 步驟 1: 取得 SHA-1 (2 分鐘)

在 Windows 命令列執行:
```
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

**複製看到的 SHA-1** (比如: `15:E7:03:09:80:64:C5:A2:...`)

---

### ✅ 步驟 2: Google Cloud 建立新 OAuth (3 分鐘)

1. 進入: https://console.cloud.google.com/apis/credentials
2. **刪除** 舊的 Android Client ID (右邊三點選單)
3. 點 **+ CREATE CREDENTIALS**
4. 選 **OAuth client ID** → **Android**
5. 填入:
   - Package name: `com.example.golf_score_app`
   - SHA-1: 貼上上面複製的 SHA-1
6. 點 **CREATE**
7. 點 **Download JSON** 下載檔案

---

### ✅ 步驟 3: 更新檔案並測試 (3 分鐘)

```cmd
# 複製 google-services.json
copy "%USERPROFILE%\Downloads\google-services.json" "d:\project\golf\golf-score_app_1\android\app\google-services.json"

# 進入專案目錄
cd d:\project\golf\golf-score_app_1

# 清除並重新編譯
flutter clean
flutter pub get
flutter run
```

**結果**: 應該看到 Google 登入對話框 ✅

---

## 完成!

就這樣! 總共 5-10 分鐘。

有問題嗎? 告訴我你在哪一步!
