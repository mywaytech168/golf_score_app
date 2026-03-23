# ✅ 重新驗證所有設定

## 你的套件名稱

### Android
- **正確的套件名稱**: `com.example.golf_score_app`
- **調試 SHA-1**: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`

### iOS
- **套件名稱**: `atk.golfscoreapp`
- *(這是在 Xcode 中設定的，不會影響 Android)*

---

## 🔐 Google Cloud 檢查清單

### 最重要的問題: 

**你的 Google Cloud OAuth 是為哪個套件名稱建立的?**

1. 打開: https://console.cloud.google.com/apis/credentials
2. 找到 **Android Client ID**
3. 看它的設定:

```
Package name: ???
SHA-1: ???
```

### 應該是:
```
Package name: com.example.golf_score_app
SHA-1: 15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

---

## 如果不對，要怎麼辦?

### 情況 1: 套件名稱是 `atk.golfscoreapp`

❌ 不對！這是錯的。

**解決方案:**
1. 刪除舊的 OAuth (右邊三點選單)
2. 重新建立新的 OAuth:
   - Package name: `com.example.golf_score_app` ← 重要!
   - SHA-1: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`
3. 下載新的 google-services.json
4. 替換你的檔案
5. 執行 flutter clean && flutter run

### 情況 2: 套件名稱是 `com.example.golf_score_app`，SHA-1 正確

✅ 完美! 應該可以了。

**下一步:**
1. 等 5-10 分鐘 (Google 伺服器同步)
2. `flutter clean`
3. `flutter run`
4. 在手機上測試 Google Sign-In

### 情況 3: 一切都正確，但還是 Error 10

❓ 可能是:
- Google 還在同步 (再等 5-10 分鐘)
- 手機上有舊的應用快取
- 需要重新卸載應用

**試試:**
```cmd
flutter clean
rm -r build/
flutter run --release
```

---

## 📋 驗證步驟

### 步驟 1: 確認 Android 套件名稱

```cmd
grep "namespace\|applicationId" "d:\project\golf\golf-score_app_1\android\app\build.gradle.kts"
```

應該看到:
```
namespace = "com.example.golf_score_app"
applicationId = "com.example.golf_score_app"
```

### 步驟 2: 確認 google-services.json

```cmd
grep "package_name" "d:\project\golf\golf-score_app_1\android\app\google-services.json"
```

應該看到:
```
"package_name": "com.example.golf_score_app"
```

### 步驟 3: 確認 Google Cloud

打開: https://console.cloud.google.com/apis/credentials

看 Android Client ID 的:
- Package name: `com.example.golf_score_app` ✓
- SHA-1: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0` ✓

---

## 🚀 現在執行

```cmd
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run
```

然後在手機上點擊 Google Sign-In 按鈕。

---

## 📞 告訴我

1. Google Cloud 的 Android OAuth 套件名稱是什麼?
2. Google Cloud 的 Android OAuth SHA-1 是什麼?
3. 測試結果如何? (成功/Error 10/其他錯誤)

這樣我可以幫你快速診斷!
