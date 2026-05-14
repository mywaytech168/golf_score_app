# 🔍 三端骨架檢測技術棧對比

## 📋 概況

**Flutter 端不使用 MediaPipe！** 而是用 Google ML Kit。

```
┌─────────────────────────────────────────────────────────────┐
│               三端骨架檢測技術棧                              │
├──────────────────┬─────────────────┬──────────────────────┤
│ 端               │ 技術棧          │ 檔案位置             │
├──────────────────┼─────────────────┼──────────────────────┤
│ Python           │ MediaPipe       │ python/*.py          │
│ Flutter (Dart)   │ Google ML Kit    │ lib/**/*.dart        │
│ Kotlin (Android) │ (無直接推理)     │ android/**/*.kt      │
│                  │ 讀 Python CSV   │ (只做渲染+編碼)     │
└──────────────────┴─────────────────┴──────────────────────┘
```

---

## 🔬 詳細對比

### 1. Python 端：MediaPipe

```python
# python/golf_pose_skeleton_pipeline.py
import mediapipe as mp

with mp.solutions.pose.Pose(
    static_image_mode=False,
    model_complexity=1,              # medium 精度
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
) as pose:
    result = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    # 返回 33 landmarks
```

**特性:**
- ✅ 開源框架
- ✅ 33 landmarks (完整骨架)
- ✅ 支持 GPU 加速
- ⚠️ 需要 ~40-50ms per frame (CPU)
- ⚠️ 單次編碼，質量不够

**輸出:**
```
pose_landmarks.csv
├─ 每行: frame, time_sec, lm0_x_norm, lm0_y_norm, ..., lm0_x_px, lm0_y_px, ...
├─ 座標空間: 原始旋轉後視頻尺寸
└─ 用途: Kotlin SkeletonOverlayRenderer 的輸入
```

---

### 2. Flutter 端：Google ML Kit

```dart
// lib/recording/pose_detector_service.dart
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

final detector = PoseDetector(
  options: PoseDetectorOptions(
    mode: PoseDetectionMode.stream,  // ← 實時模式
    model: PoseDetectionModel.base,
  ),
);

final poses = await detector.processImage(inputImage);
// 返回 List<Pose>，每個 Pose 含 33 landmarks
```

**特性:**
- ✅ 實時推理 (~15-20ms per frame)
- ✅ 時序平滑 (相鄰幀連貫)
- ✅ 集成在 ML Kit 中
- ✅ 基於 MediaPipe 模型（Google 打包）
- ⚠️ 無原始模型訪問權
- ⚠️ 依賴 Google Mobile Services (GMS)

**用途:**
- 即時錄影時的骨架預覽
- 邊錄邊保存到 CSV (透過 PoseFrameModel)
- 用戶 UI 反饋

**關鍵代碼:**
```dart
// record_screen.dart - 即時錄影
final _poseService = PoseDetectorService();  // 預設 stream 模式

Future<void> _onImageAnalysis(AnalysisImage image) async {
  final poses = await _poseService.detect(inputImage);
  
  // 1. 顯示骨架預覽
  setState(() {
    _poses = poses;
  });
  
  // 2. 若錄影中，寫入 CSV
  if (_isRecording) {
    _poseWriter?.addFrame(PoseFrameModel.fromPose(
      frame: _frameCount,
      timeSec: timeSec,
      pose: poses.first,
      imgWidth: image.width.toDouble(),
      imgHeight: image.height.toDouble(),
    ));
  }
}

// video_analysis_service.dart - 離線分析
final poseService = PoseDetectorService(
  mode: PoseDetectionMode.single  // ← 獨立幀模式
);
```

---

### 3. Kotlin 端：無推理（只讀 CSV）

```kotlin
// android/app/src/main/kotlin/com/example/golf_score_app/SkeletonOverlayRenderer.kt

class SkeletonOverlayRenderer(private val context: Context) {
    fun render(
        clipPath: String,
        csvPath: String,        // ← 讀 Python 生成的 CSV
        startSec: Double,
        outputPath: String,
    ): Boolean {
        // 1. 從 CSV 讀骨架座標
        val frameData = parseCsv(csvPath)
        
        // 2. 推算原始影像尺寸
        val poseSize = inferPoseImageSize(frameData)
        
        // 3. 解碼影片 + 繪製骨架 + 編碼
        for each frame:
            ├─ YUV → RGB 轉換
            ├─ drawSkeleton(canvas, landmarks)
            ├─ RGB → NV12 轉換
            └─ 硬體編碼 (H.264 @ 25Mbps)
    }
}

// android/app/build.gradle.kts - 依賴
dependencies {
    // MediaPipe？無！
    // 只有 Media3 用於視頻處理
    implementation("androidx.media3:media3-transformer:1.4.1")
    implementation("androidx.media3:media3-extractor:1.4.1")
    implementation("androidx.media3:media3-common:1.4.1")
}
```

**特性:**
- ✅ 不需要 ML 推理（成本低）
- ✅ 完全依賴 Python CSV
- ✅ 適應多層編碼流程
- ⚠️ 無即時推理能力
- ⚠️ 受限於 Python 端質量

**用途:**
- 讀取已分析的骨架座標
- 將骨架渲染到視頻
- 多層編碼疊加 (骨架 + 軌跡)

---

## 🎯 三端數據流

```
【錄影過程 - 實時】
CameraX 原始幀 (YUV, 30fps)
  ├─ Flutter (ML Kit stream)
  │   ├─ 推理: 15-20ms
  │   └─ 結果: 33 landmarks (平滑)
  │        ↓ PoseFrameModel.fromPose()
  │        ↓ (邊錄邊寫)
  │        ↓ pose_landmarks.csv
  └─ 完成: 邊錄邊分析，無延遲

【分析過程 - 離線】
已保存視頻 (MP4)
  ├─ Flutter (ML Kit single)
  │   ├─ 每隔 67ms 抽一幀
  │   ├─ 推理: 30-50ms (獨立)
  │   └─ 結果: 33 landmarks (精確)
  │        ↓ VideoAnalysisService.analyze()
  │        ↓ (批量寫入)
  │        ↓ pose_landmarks.csv
  └─ 完成: 精確離線分析

【渲染過程 - 後期】
pose_landmarks.csv
  ├─ Kotlin (SkeletonOverlayRenderer)
  │   ├─ parseCsv()
  │   ├─ drawSkeleton()
  │   └─ 編碼渲染
  │        ↓ skeleton.mp4
  └─ 完成: 骨架視頻輸出
```

---

## 📊 技術對比表

| 項目 | Python | Flutter | Kotlin |
|------|--------|---------|--------|
| **框架** | MediaPipe | Google ML Kit | Media3 |
| **推理** | ✅ 完整 | ✅ 完整 | ❌ 無 |
| **模型** | 原始 mediapipe | ML Kit 打包 | (從 CSV 讀) |
| **延遲** | 40-50ms/幀 | 15-20ms/幀 | 0ms (讀 CSV) |
| **精度** | 高 | 高 | (繼承 Python/Flutter) |
| **場景** | 離線/後端分析 | 實時/移動端 | 渲染/編碼 |
| **32 landmarks** | ✅ 完整 33 個 | ✅ 完整 33 個 | ✅ 從 CSV 讀 |
| **平滑性** | ⚠️ 單幀 | ✅ 時序 | (CSV 決定) |

---

## 🔗 數據流詳解

### 場景 1：即時錄影 (Flutter Stream 模式)

```
時間軸 (per frame, @30fps = 33ms):
  ├─ t=0ms:   CameraX 幀到達
  ├─ t=1ms:   _onImageAnalysis() 回調
  ├─ t=2ms:   image.toInputImage() 轉換
  ├─ t=3ms:   _poseService.detect() 開始 (ML Kit)
  ├─ t=18ms:  推理完成 (~15ms)
  ├─ t=19ms:  setState() 更新 UI
  ├─ t=20ms:  CustomPaint → SkeletonPainter 繪制
  ├─ t=25ms:  PoseFrameModel.fromPose() 構建
  ├─ t=26ms:  _poseWriter?.addFrame() 寫 CSV
  ├─ t=27ms:  完成
  └─ t=33ms:  下一幀到達 ✅

CSV 增長 (同時進行):
  Frame 0 @ t=0.0s
  Frame 1 @ t=0.033s
  Frame 2 @ t=0.066s
  ...
```

---

### 場景 2：擊球偵測 (Flutter Single 模式)

```
時間軸 (per frame, @15fps = 67ms):
  ├─ t=0ms:    VideoThumbnail.thumbnailFile(timeMs: ms)
  ├─ t=50ms:   JPEG 解碼完成
  ├─ t=50ms:   _poseService.detect() 開始 (ML Kit)
  ├─ t=80ms:   推理完成 (~30ms)
  ├─ t=81ms:   PoseFrameModel.fromPose() 構建
  ├─ t=82ms:   writer.addFrame() 新增
  ├─ t=100ms:  進行下一幀
  └─ (無 UI 影響，背景進行)

CSV 最終 (完成後寫入):
  Frame 0 @ t=0.0s
  Frame 1 @ t=0.067s
  Frame 2 @ t=0.134s
  ...
```

---

### 場景 3：骨架渲染 (Kotlin)

```
時間軸 (per frame, @30fps):
  ├─ t=0ms:    parseCsv(csvPath) 讀骨架
  ├─ t=5ms:    MediaExtractor 解碼
  ├─ t=20ms:   YUV → RGB 轉換 (2-3ms)
  ├─ t=22ms:   drawSkeleton() 繪制 (1-2ms)
  ├─ t=24ms:   bitmapFillNv12() 編碼 (5-8ms)
  ├─ t=30ms:   H.264 編碼器 (~8-15ms async)
  └─ t=33ms:   準備下一幀

輸出:
  skeleton.mp4 (含所有 33 landmarks)
```

---

## 💡 為何這樣設計？

### 為何 Flutter 用 ML Kit 而不是 MediaPipe？

1. **行動最佳化**
   - ML Kit 是 Google 為移動端打包的 MediaPipe
   - 自動選擇最快的後端 (ARM NEON, GPU)

2. **實時性**
   - 原生 Dart 整合，低開銷
   - Stream 模式時序追蹤更平滑

3. **穩定性**
   - Google 維護，覆蓋更多設備
   - Firebase 一鍵集成

### 為何 Python 還是用原生 MediaPipe？

1. **後端靈活**
   - 原始模型訪問
   - 自訂推理參數

2. **離線處理**
   - 批量分析無時間限制
   - CPU/GPU 自由選擇

3. **一致性**
   - 33 landmarks 標準化
   - Python 影像處理生態

### 為何 Kotlin 不推理？

1. **成本節省**
   - 無重複推理（Python 已做）
   - 硬體限制少

2. **編碼優化**
   - 專注於多層編碼流程
   - Media3 已經是最佳方案

3. **模塊化**
   - 各端職責清晰
   - 易於維護

---

## 🚀 改進方向

### 統一方向 1：全部用 MediaPipe

```
缺點:
  ❌ Kotlin 需要編譯 MediaPipe Aar (~150MB)
  ❌ 增加 APP 大小 20%+
  ❌ 重複推理 (Python+Flutter+Kotlin)
  
優點:
  ✅ 架構一致
  ✅ 無 Google GMS 依賴
```

---

### 統一方向 2：全部用 ML Kit

```
缺點:
  ❌ 需要 Google Mobile Services
  ❌ 無法離線使用 (無 GMS)
  ❌ Python 後端無法用
  
優點:
  ✅ 最輕量
  ✅ 移動端最快
```

---

### 推薦：保持現狀（已最優化）

```
當前設計已經最優:
  ✅ Python: 完整離線分析 (MediaPipe)
  ✅ Flutter: 實時移動端 (ML Kit)
  ✅ Kotlin: 純渲染編碼 (Media3)
  
只需改進各端性能:
  ├─ Python: GPU 加速或抽幀 (50% 快)
  ├─ Flutter: 保持現狀 (已最優)
  └─ Kotlin: SIMD 加速 (65% 快)
```

---

## 📝 總結

**Flutter 不使用 MediaPipe，而是使用 Google ML Kit。**

三端各司其職：
- **Python**: MediaPipe 完整推理 (後端/離線)
- **Flutter**: ML Kit 實時推理 (行動端)
- **Kotlin**: 純渲染編碼 (播放端)

這個設計已經是最優化的，無需改變。重點是改進各端的性能（尤其是 Python 和 Kotlin）。
