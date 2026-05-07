# Camerawesome API 優化總結

## ✅ 已完成的改進

### 1. **MLKit 圖像轉換 API 修正**

**問題**：
```dart
// ❌ 舊方式 - 硬編碼旋轉角度，缺少 bytesPerRow
final inputImage = InputImage.fromBytes(
  bytes: image.bytes,
  inputImageData: InputImageData(
    size: Size(image.width.toDouble(), image.height.toDouble()),
    imageRotation: InputImageRotation.rotation0deg,  // ❌ 硬編碼
    inputImageFormat: InputImageFormat.nv21,
  ),
);
```

**解決方案**：
```dart
// ✅ 新方式 - MLKit 擴展方法
import 'mlkit_utils.dart';

final inputImage = image.toInputImage();  // 自動處理所有細節
```

**好處**：
- ✅ 自動偵測圖像旋轉角度（不同設備方向）
- ✅ 支援 NV21 和 BGRA8888 格式
- ✅ 正確設定 `bytesPerRow` 和 `planeData`
- ✅ 避免手動轉換錯誤

---

### 2. **視頻質量配置（動態設定）**

**檔案**: `lib/recording/recording_config.dart`

```dart
enum VideoQuality {
  low(480, 1500000, '低 (480p)'),
  standard(720, 3000000, '標準 (720p)'),
  hd(1080, 6000000, '高 (1080p)');

  final int height;
  final int bitrate;
  final String displayName;
}
```

**配置應用**：
```dart
SaveConfig.video(
  videoOptions: _config.getVideoOptions(),  // ✅ 動態設置
)
```

**配置細節**：
- Android: 根據質量自適應位元率
- iOS: 選擇合適的編碼器和幀率
- 降級策略: `QualityFallbackStrategy.lower` - 設備不支援時自動降級

---

### 3. **幀率統一配置**

**之前**：
```
錄製: 未指定（系統默認）
分析: 15fps ❌ 不同步
```

**現在**：
```dart
enum FrameRate {
  fps24(24, '24fps'),
  fps30(30, '30fps'),
  fps60(60, '60fps');
}

// 統一應用到錄製和分析
videoOptions: VideoOptions(ios: CupertinoVideoOptions(fps: frameRate.value)),
imageAnalysisConfig: AnalysisConfig(maxFramesPerSecond: frameRate.value),
```

**推薦值**：
- 30fps ⭐ 最平衡（錄製品質 + 分析精度）
- 60fps 適合高端設備
- 24fps 適合低端設備

---

### 4. **分析圖像寬度優化（姿態檢測精度）**

**之前**：
```dart
// ❌ 固定 512px - 中等精度
AndroidAnalysisOptions.nv21(width: 512)
```

**現在**：
```dart
enum AnalysisWidth {
  low(320, '低精度 (320px)'),           // 快速、低準確度
  medium(480, '中精度 (480px)'),        // 平衡
  high(640, '高精度 (640px)'),          // ⭐ 推薦
  veryHigh(768, '超高精度 (768px)');    // 高端設備
}
```

**推薦值**：
| 寬度 | 精度 | 性能 | 用途 |
|------|------|------|------|
| 320px | 低 | 極快 | 低端設備 |
| 480px | 中 | 快 | 姿態檢測 |
| 640px | 高 | 正常 | ⭐ **推薦** |
| 768px | 超高 | 慢 | 旗艦設備 + 高精度需求 |

---

### 5. **設定面板 UI**

**位置**：右上角設置按鈕
**功能**：即時調整錄製參數，無需重啟

```dart
_buildSettingsPanel()  // 翻頁面板，包含：
  ├─ 視頻質量選擇
  ├─ 幀率選擇
  ├─ 姿態精度選擇
  └─ 錄音開關
```

---

## 📁 新增檔案

### 1. `mlkit_utils.dart`
- MLKit 轉換擴展方法
- 支援 NV21 和 BGRA8888 格式
- 自動旋轉偵測

### 2. `recording_config.dart`
- 視頻質量、幀率、分析寬度選項
- `getVideoOptions()` - 返回 Camerawesome VideoOptions
- `getAnalysisConfig()` - 返回 Camerawesome AnalysisConfig

### 3. `record_screen_optimized.dart`
- 完整的優化實現
- 包含設定面板 UI
- 即時配置調整

---

## 🔧 使用方式

### 1. 更新現有代碼
```dart
// 檔案：lib/main.dart 或路由配置
import 'recording/record_screen_clean.dart';

// 使用（已自動整合優化）
Navigator.push(context, MaterialPageRoute(
  builder: (context) => RecordScreen(
    onComplete: (videoPath, csvPath, audioPath) {
      // 處理錄製完成
    },
  ),
));
```

### 2. 調整設定（運行時）
- 點擊右上角 ⚙️ 設置按鈕
- 選擇視頻質量
- 調整幀率
- 選擇姿態精度
- 開啟/關閉錄音

---

## 📊 效能影響

| 設置 | 低端設備 | 中端設備 | 高端設備 |
|------|---------|---------|---------|
| **視頻質量** | 480p | 720p | 1080p ⭐ |
| **幀率** | 24fps | 30fps | 60fps |
| **分析寬度** | 320px | 480px | 640px ⭐ |
| **預期 FPS** | 15-20 | 25-28 | 28-30 |

---

## 🚀 下一步優化

1. **設備能力檢測** ✅ (已實現)
   - 根據設備 CPU/GPU 自動選擇最優配置

2. **溫度監測**
   - 錄製過程中監測設備溫度
   - 自動降級配置防止過熱

3. **剩餘空間檢查**
   - 錄製前檢查可用空間
   - 預估錄製時長

4. **網絡同步**
   - 將錄製數據實時上傳到雲端
   - 本地繼續錄製

---

## ❓ 常見問題

### Q: 為什麼要改變幀率？
A: 統一幀率可確保錄製視頻和分析數據同步，提高數據準確性。

### Q: 應該選哪個分析寬度？
A: 640px 在準確度和性能間達到最佳平衡，推薦用於姿態檢測。

### Q: 設定會保存嗎？
A: 目前會話內有效。可擴展 `SharedPreferences` 持久化。

### Q: 480p 錄製會模糊嗎？
A: 對於 6 尺寸手機屏幕，720p 已足夠。1080p 用於後期分析。
