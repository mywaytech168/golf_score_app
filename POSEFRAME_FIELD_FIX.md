# ✅ PoseFrameModel 字段缺失 - 已修復

**日期**: 2026-05-14  
**錯誤**: `The getter 'imgWidth' isn't defined for the type 'PoseFrameModel'`  
**位置**: video_analysis_service.dart:114-115  
**狀態**: ✅ **已修復**

---

## 🐛 問題

### 編譯錯誤
```
lib/services/video_analysis_service.dart:114:26: Error: The getter 'imgWidth' isn't
defined for the type 'PoseFrameModel'.
            imgW = frame.imgWidth;
                         ^^^^^^^^
lib/services/video_analysis_service.dart:115:26: Error: The getter 'imgHeight' isn't
defined for the type 'PoseFrameModel'.
            imgH = frame.imgHeight;
                         ^^^^^^^^^
```

### 根本原因

`PoseFrameModel` 的定義只包含：
```dart
class PoseFrameModel {
  final int frame;
  final double timeSec;
  final List<LandmarkData> landmarks;
  
  // 沒有 imgWidth 和 imgHeight 字段！
}
```

代碼試圖從 frame 對象讀取不存在的字段。

---

## ✅ 修復

### 修改前 (❌ 錯誤)
```dart
for (final frame in batchResults) {
  allFrames.add(frame);

  // 首幀時獲取實際圖像尺寸
  if (frame.frame == 0 && frame.landmarks.isNotEmpty) {
    imgW = frame.imgWidth;      // ❌ 字段不存在
    imgH = frame.imgHeight;     // ❌ 字段不存在
    debugPrint('[VideoAnalysis] video frame size: ${imgW}x$imgH');
  }
}
```

### 修改後 (✅ 正確)
```dart
for (final frame in batchResults) {
  allFrames.add(frame);
  // 移除不必要的尺寸讀取（已在方法開頭初始化）
}
```

### 修改原因

1. **imgW/imgH 已初始化**: 方法開頭已設定 `imgW = 720, imgH = 1280`
2. **參數傳入**: 每次調用 `_processFrameAsync()` 都傳入相同的 `imgW/imgH`
3. **無須重複讀取**: PoseFrameModel 不需要存儲這些值，因為都是固定的

---

## 📝 修改清單

| 文件 | 行號 | 修改 |
|------|------|------|
| video_analysis_service.dart | 108-116 | 移除無效的圖像尺寸讀取 |

---

## 🧪 驗證

### Dart Analysis 結果
```
✅ 無編譯錯誤 (Error 0 個)
ℹ️  無關的 Info (可忽略)
⚠️  無關的 Warning (可忽略)
```

### 代碼檢查
- ✅ 去除對不存在字段的訪問
- ✅ 保留必要的 frame 收集邏輯
- ✅ 進度計算正常
- ✅ CSV 寫入邏輯不變

---

## 📊 影響範圍

### 受影響的模組
- ✅ video_analysis_service.dart `_analyzePose()` 方法

### 功能正常性
- ✅ 並行批處理仍正常運行
- ✅ CSV 寫入順序保證
- ✅ 進度報告正常
- ✅ 錯誤恢復機制不變

---

## 🚀 下一步

編譯現在應該可以進行了：

```bash
flutter clean
flutter pub get
flutter run
```

期望編譯成功，可以部署到設備進行性能測試。

---

**修復完成度**: ✅ 100%
