# ✅ 最終檢查清單 - Google Sign-In 設定

## 🔧 已完成的步驟

- ✅ 取得你的調試 SHA-1: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`
- ✅ 更新了 `google-services.json`，移除舊的生產 SHA-1
- ✅ 執行 `flutter clean`
- ✅ 執行 `flutter pub get`

---

## 📋 最後的檢查項

在執行 `flutter run` 之前，確認:

### 1. Google Cloud 設定
- [ ] 你已經在 Google Cloud 建立了 **Android** 類型的 OAuth
- [ ] OAuth 的 Package name 是: `com.example.golf_score_app`
- [ ] OAuth 的 SHA-1 是: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`
- [ ] 新 OAuth 已建立至少 **5-10 分鐘**（讓 Google 伺服器同步）

### 2. 本地檔案
- [ ] `android/app/google-services.json` 已更新
- [ ] `android/app/build.gradle.kts` 中有:
  ```
  namespace = "com.example.golf_score_app"
  ```
- [ ] `pubspec.yaml` 中有 `google_sign_in` 套件

### 3. 代碼檢查
檢查 `lib/pages/login_page.dart` 中的 serverClientId 是否正確:
```dart
if (Platform.isAndroid) {
  googleSignIn = GoogleSignIn(
    serverClientId: '你的 Android Client ID',
    ...
  );
}
```

**注意**: serverClientId 應該是你在 Google Cloud 建立的那個 OAuth 的 Client ID

---

## 🚀 執行測試

執行這個命令:
```cmd
cd d:\project\golf\golf-score_app_1
flutter run
```

---

## ✅ 預期結果

### 成功的跡象 ✅
1. 應用啟動無錯誤
2. 看到應用的登入頁面
3. 點擊 **"Use Google Sign-In"** 按鈕
4. **看到 Google 帳號選擇對話框**
5. 可以選擇帳號並登入

### 失敗的跡象 ❌
1. 看到 **Error 10** - SHA-1 不符
2. 看到 **Error 12500** - 應用簽名問題
3. 其他錯誤 - 可能是其他配置問題

---

## 🆘 如果還是不行

### 檢查 1: 驗證 google-services.json
```cmd
type "d:\project\golf\golf-score_app_1\android\app\google-services.json"
```

應該看到:
```json
"certificate_hash": [
  "15e70309806c5a21fab afa403a221f365aaacb0"
]
```

### 檢查 2: 驗證套件名稱
```cmd
grep -n "namespace" "d:\project\golf\golf-score_app_1\android\app\build.gradle.kts"
```

應該看到:
```
namespace = "com.example.golf_score_app"
```

### 檢查 3: 等待更久
有時 Google 需要 15-30 分鐘才能完全同步。
試試等 15 分鐘後再測試。

### 檢查 4: 卸載舊應用
1. 從裝置卸載應用
2. `flutter clean`
3. 重新執行 `flutter run`

---

## 📞 準備好時

當你執行 `flutter run` 時，告訴我:
1. ✅ 有沒有看到 Google 登入對話框
2. ✅ 有沒有看到錯誤訊息
3. ✅ 日誌中最後幾行是什麼

這樣我可以幫你快速診斷!

---

## 💡 提示

如果經過所有檢查還是失敗，可能是:
1. **SHA-1 還沒有在 Google 伺服器同步** - 等待更久
2. **建立的不是 Android OAuth** - 確認是 "Android" 類型
3. **套件名稱拼寫錯誤** - 確保完全相同
4. **使用了錯誤的 Client ID** - 使用新建立的 OAuth 的 Client ID

---

祝你好運! 🚀
