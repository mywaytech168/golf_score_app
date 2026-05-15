# 🔧 類型轉換錯誤修復

**日期**: 2026-05-14  
**問題**: `java.lang.Integer cannot be cast to java.lang.Long`  
**位置**: MainActivity.kt:300  
**狀態**: ✅ **已修復**

---

## 🐛 問題分析

### 錯誤症狀
```
[VideoAnalysis] frame 53 error: PlatformException(error, 
  java.lang.Integer cannot be cast to java.lang.Long...
[VideoAnalysis] frame 54 error...
```

每幀都發生 (frame 53-74+)，代表這是系統性的類型轉換問題。

### 根本原因

**Dart → Android MethodChannel 類型映射**:
- Dart `int` (32/64 bit) → Android `java.lang.Integer` ❌ (不是 Long!)
- Kotlin 代碼期望 `Long` 但實際收到 `Integer`
- 強轉失敗: `Integer cannot be cast to Long`

---

## 📋 修復內容

### 修改前 (錯誤)
```kotlin
// MainActivity.kt:300
val timeMs = call.argument<Long>("timeMs") ?: 0L  // ❌ 期望 Long，但收到 Integer
```

### 修改後 (正確)
```kotlin
// MainActivity.kt:300
// ⚠️ 修復: Dart int → Android Integer (不是 Long!)
val timeMs = (call.argument<Int>("timeMs") ?: 0).toLong()  // ✅ 先取 Int，再轉 Long
```

### 原理
```
Dart side:           Android side:           Kotlin side:
'timeMs': ms  ──→  java.lang.Integer  ──→  call.argument<Int>() → toLong()
                   (注意：不是 Long!)
```

---

## 🔍 驗證

### 修復範圍
| 參數 | Dart 型別 | Android 映射 | 修復 |
|------|---------|-----------|------|
| `videoPath` | String | String | ✅ 無需修改 |
| `timeMs` | int | Integer | ✅ 已修改 |
| `maxWidth` | int | Integer | ✅ 無需修改 (已是 Int) |

### 代碼驗證
```kotlin
// 正確用法
val timeMs = (call.argument<Int>("timeMs") ?: 0).toLong()  // ✅
val maxWidth = call.argument<Int>("maxWidth") ?: 720       // ✅

// 錯誤用法 (已修復)
// val timeMs = call.argument<Long>("timeMs") ?: 0L  // ❌ 會拋 ClassCastException
```

---

## 📊 預期改進

### 修復前
```
❌ 每幀失敗
[VideoAnalysis] frame 53 error: PlatformException(error, java.lang.Integer cannot be cast to java.lang.Long
[VideoAnalysis] frame 54 error: PlatformException(error, java.lang.Integer cannot be cast to java.lang.Long
...
[VideoAnalysis] frame 74 error...
```

### 修復後
```
✅ 正常運行
[VideoAnalysis] 幀 53: 提取=15ms + 推理=42ms
[VideoAnalysis] 幀 54: 提取=14ms + 推理=41ms
...
[VideoAnalysis] ✅ 並行分析完成: 450 幀
```

---

## 🚀 後續步驟

1. ✅ **代碼修復** (已完成)
2. ⏳ **重新編譯** (flutter clean && flutter pub get && flutter run)
3. ⏳ **實機測試** (驗證幀提取是否正常工作)
4. ⏳ **性能測試** (測量修復後的實際耗時)

---

## 💡 相關知識

### MethodChannel 型別映射表
```
Dart              Java/Android       Kotlin
int      ────→    Integer/Long       Int/Long
double   ────→    Double             Double
bool     ────→    Boolean            Boolean
String   ────→    String             String
List     ────→    ArrayList          List
Map      ────→    HashMap            Map
```

### 注意事項
- **永遠檢查實際接收型別**, 不要假設
- 使用 `call.argument<T>()` 時務必用正確的 generic type
- 當不確定時，考慮用 `call.arguments` 檢查原始值

---

**修復說明**: Android MethodChannel 從 Dart 接收 int 時會轉成 `Integer`，不是 `Long`。因此改用 `call.argument<Int>()` 然後 `.toLong()` 轉換。
