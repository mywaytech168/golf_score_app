# 📊 即時錄影 vs 擊球偵測：骨架處理對比

## 🎯 概述

Flutter 應用中的骨架處理分為兩個完全不同的場景，採用不同的 ML Kit 模式和實現策略。

```
┌─────────────────────────────────────────────────────────────────┐
│                    即時錄影                                      │
├─────────────────────────────────────────────────────────────────┤
│ 模式: PoseDetectionMode.stream                                   │
│ 場景: 用戶錄製時實時顯示骨架，同時保存幀數據                      │
│ 目標: 實時預覽 + 背景保存                                         │
│ 保存: 邊錄邊寫 CSV (同時進行)                                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    擊球偵測                                      │
├─────────────────────────────────────────────────────────────────┤
│ 模式: PoseDetectionMode.single                                   │
│ 場景: 分析已保存的裁切視頻，生成 CSV 用於後續處理                │
│ 目標: 精確分析 + 高質量輸出                                       │
│ 保存: 一次性抽幀→推理→寫 CSV                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 詳細對比

### 1️⃣ ML Kit 模式差異

#### 即時錄影: Stream 模式

```dart
// lib/recording/record_screen.dart
final _poseService = PoseDetectorService();  // 預設 PoseDetectionMode.stream

// PoseDetectorService.dart
PoseDetectorService({this.mode = PoseDetectionMode.stream});

PoseDetector? _detector;
_detector ??= PoseDetector(
  options: PoseDetectorOptions(
    mode: PoseDetectionMode.stream,  // ← 時序模式
    model: PoseDetectionModel.base,
  ),
);
```

**特性:**
- ✅ **時序追蹤**: 利用相鄰幀做連續追蹤
- ✅ **平滑性好**: 相鄰幀結果自動平滑（Kalman-like）
- ⚠️ **對幀間隔敏感**: 假設幀間隔固定 (~30-60ms)
- ⏱️ **低延遲**: 推理時間 ~15-25ms

**適用場景:**
- 實時預覽（幀間隔穩定）
- 相機輸入（CameraX 幀率穩定）
- 需要流暢骨架的場景

---

#### 擊球偵測: Single 模式

```dart
// lib/services/video_analysis_service.dart
final poseService = PoseDetectorService(
  mode: PoseDetectionMode.single  // ← 獨立幀模式
);

// 在 _analyzePose 中使用
final poses = await poseService.detect(
  InputImage.fromFilePath(thumbPath)
);
```

**特性:**
- ✅ **獨立推理**: 每幀完全獨立，無時序依賴
- ✅ **高精度**: 不受幀間隔不規律影響
- ⚠️ **無平滑**: 相鄰幀可能不連貫
- ⏱️ **延遲無關**: 每幀都是完整推理 ~25-35ms

**適用場景:**
- 批量處理（video_analysis）
- 幀時間不穩定（從 thumbnail 提取）
- 需要每幀精確標註

---

### 2️⃣ 數據流和時序

#### 即時錄影流程

```
CameraX 原始幀 (YUV)
  ↓ 30fps, 每幀 ~33ms
  ├─ 顯示預覽 (Canvas + SkeletonPainter)
  ├─ _onImageAnalysis() 回調
  │   ├─ poseService.detect(inputImage)  ← stream 模式
  │   │   └─ 返回: List<Pose>            ← 時序平滑
  │   ├─ PoseFrameModel.fromPose()
  │   └─ _poseWriter?.addFrame()
  │       └─ pose_landmarks.csv (邊寫邊新增)
  └─ 同時進行，無阻塞
```

**時間關係:**
```
錄影 UI 線程:
  ├─ t=0ms:   _onImageAnalysis() 開始
  ├─ t=20ms:  poseService.detect() 返回
  ├─ t=21ms:  CSV 寫入
  └─ t=33ms:  下一幀到達 ← 無卡頓

CSV 增長:
  ├─ frame 0, time_sec 0.0
  ├─ frame 1, time_sec 0.033
  ├─ frame 2, time_sec 0.066
  └─ ...
```

**關鍵特性:**
- ✅ **邊錄邊分析**: 不影響錄影幀率
- ✅ **CSV 增量寫入**: 邊錄邊累加
- ⚠️ **偶爾幀丟失**: 若推理超時 (> 33ms)，該幀可能被跳過

---

#### 擊球偵測流程

```
已保存的視頻檔案 (MP4)
  ↓ VideoAnalysisService.analyze()
  ├─ 串列處理 (每隔 67ms 提取一幀)
  │
  ├─ 第 0 幀:
  │   ├─ VideoThumbnail.thumbnailFile(timeMs: 0)
  │   │   └─ 從 MP4 提取 → JPEG thumbnail (720×1280)
  │   ├─ poseService.detect(InputImage.fromFilePath(thumbPath))
  │   │   └─ single 模式, 獨立推理
  │   └─ writer.addFrame(PoseFrameModel(...))
  │
  ├─ 第 1 幀 (67ms):
  │   └─ (同上，但時間為 67ms)
  │
  └─ ... 重複直到視頻結束
  
  最後: writer.flush() → 輸出 CSV
```

**時間關係:**
```
循環 (每次 67-100ms):
  ├─ t=0ms:    VideoThumbnail.thumbnailFile(timeMs: 0)
  ├─ t=50ms:   圖像解碼完成
  ├─ t=50-80ms: poseService.detect() (single 推理)
  ├─ t=80ms:   結果返回
  └─ t=85ms:   CSV 寫入，進行下一幀
     └─ (可能 50-100ms 後才進行)

CSV 結果:
  ├─ frame 0, time_sec 0.0
  ├─ frame 1, time_sec 0.067
  ├─ frame 2, time_sec 0.134
  └─ (更稀疏的取樣，~15fps)
```

**關鍵特性:**
- ✅ **離線處理**: 不影響 UI
- ✅ **進度通知**: onProgress callback
- ⚠️ **緩慢**: 每幀 100-150ms (包括抽幀+推理)
- ⚠️ **取樣率低**: 每隔 67ms 一幀 (~15fps 標準)

---

### 3️⃣ 骨架畫面對比

#### 即時錄影 (SkeletonPainter)

```dart
// lib/recording/skeleton_painter.dart
class SkeletonPainter extends CustomPainter {
  final List<Pose> poses;  // ← 最新的時序平滑結果
  final Size imageSize;
  
  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = const Color(0xFF00FFFF)  // 青色
      ..strokeWidth = 2.5;
    final jointPaint = Paint()
      ..color = const Color(0xFF00FF00)  // 綠色
      ..style = PaintingStyle.fill;
    final wristPaint = Paint()
      ..color = const Color(0xFFFF0000)  // 紅色 (landmark 16)
      ..style = PaintingStyle.fill;

    // 繪製連線 (25 條邊)
    for (final (a, b) in _edges) {
      // 時序平滑的邊線，很少抖動
      canvas.drawLine(...);
    }
    
    // 繪製關鍵點 (33 個)
    for (final entry in pose.landmarks.entries) {
      // 其中 lm16 (右手腕) 標紅
      canvas.drawCircle(...);
    }
  }
}
```

**視覺特性:**
- 🎬 **平滑動作**: 時序追蹤，相鄰幀連貫
- 🟢 **完整骨架**: 實時顯示所有 33 點
- 🔴 **標紅右手腕**: lm16 特別標記（用於球桿/球追蹤參考點）
- ⚡ **低延遲**: 即時響應用戶動作

**用途:**
- 幫助用戶理解錄製是否成功
- 調整姿勢確保完整捕捉
- 反饋機制

---

#### 擊球偵測 (離線 CSV)

```python
# python/golf_pose_skeleton_pipeline.py
# Kotlin SkeletonOverlayRenderer 讀取 CSV，繪製骨架

# CSV 格式 (每行一幀)
frame,time_sec,...,lm0_x_norm,lm0_y_norm,...,lm0_x_px,lm0_y_px,...
0,0.0,...,0.5,0.4,...,960,432,...
1,0.067,...,0.501,0.398,...,961,430,...
2,0.134,...,0.502,0.397,...,962,429,...
```

**視覺特性:**
- 📊 **後處理結果**: 與 Python 端一致
- 🟡 **稀疏取樣**: 只有 15fps (~67ms 間隔)
- 🟦 **精確像素座標**: 每個點都有 (x_px, y_px) 標註
- 🎞️ **無即時反饋**: 離線分析完成後才看到

**用途:**
- 精確分析用途（球軌跡追蹤、擊球點偵測）
- 與 Python 後端一致性
- 最終視頻輸出的基準

---

### 4️⃣ 取樣率和精度對比

| 項目 | 即時錄影 | 擊球偵測 |
|------|--------|--------|
| **來源** | CameraX (raw YUV) | VideoThumbnail (JPEG) |
| **取樣率** | 30fps (33ms) | ~15fps (67ms) |
| **模式** | stream (時序) | single (獨立) |
| **推理延遲** | ~20ms | ~30-50ms |
| **平滑性** | 優秀（時序） | 普通（獨立） |
| **精度** | 高（原始幀） | 非常高（精確取樣） |
| **是否適時** | 適時 (UI 反饋) | 離線 (後處理) |
| **幀丟失** | 可能 (推理超時) | 無 (完整處理) |

---

## 🔍 代碼實現詳解

### 1. 即時錄影流程

```dart
// record_screen.dart

class RecordScreenState extends State {
  final _poseService = PoseDetectorService();  // ← stream 模式
  List<Pose> _poses = [];
  
  @override
  void initState() {
    super.initState();
    // 初始化相機分析
    _cameraController.startImageStream(_onImageAnalysis);
  }
  
  Future<void> _onImageAnalysis(AnalysisImage image) async {
    if (_isPoseProcessing) return;
    _isPoseProcessing = true;
    
    try {
      // 1. 實時推理 (stream 模式自動時序平滑)
      final inputImage = image.toInputImage();
      final poses = await _poseService.detect(inputImage);  // ← ~20ms
      
      if (!mounted) return;
      
      // 2. 立即更新 UI
      setState(() {
        _poses = poses;  // → 下一幀 repaint
      });
      
      // 3. 若錄影中，寫入 CSV
      if (_isRecording) {
        final frameModel = poses.isNotEmpty
            ? PoseFrameModel.fromPose(
                frame: _frameCount,
                timeSec: timeSec,
                pose: poses.first,
                imgWidth: image.width.toDouble(),
                imgHeight: image.height.toDouble(),
              )
            : PoseFrameModel.empty(...);
        
        _poseWriter?.addFrame(frameModel);  // ← 邊錄邊寫
        _frameCount++;
      }
    } finally {
      _isPoseProcessing = false;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CameraPreview(_cameraController),
        // 即時骨架疊加
        CustomPaint(
          painter: SkeletonPainter(
            poses: _poses,
            imageSize: Size(w, h),
          ),
        ),
      ],
    );
  }
}
```

**關鍵點:**
1. stream 模式自動時序平滑
2. _onImageAnalysis 邊繪制邊寫 CSV
3. 無論是否錄影，都會實時顯示骨架

---

### 2. 擊球偵測流程

```dart
// video_analysis_service.dart

class VideoAnalysisService {
  static const _frameIntervalMs = 67;  // 15fps
  
  Future<VideoAnalysisResult> analyze({
    required String videoPath,
    required String sessionDir,
    required int durationSeconds,
    void Function(double, String)? onProgress,
  }) async {
    final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
    
    // ← 專門用 single 模式
    final poseService = PoseDetectorService(
      mode: PoseDetectionMode.single
    );
    
    try {
      await _analyzePose(
        videoPath: videoPath,
        csvPath: csvPath,
        durationSeconds: durationSeconds,
        poseService: poseService,
        onProgress: onProgress,
      );
    } finally {
      poseService.dispose();
    }
  }
  
  Future<void> _analyzePose({
    required String videoPath,
    required String csvPath,
    required int durationSeconds,
    required PoseDetectorService poseService,
    void Function(double)? onProgress,
  }) async {
    final writer = PoseCsvWriter(csvPath);
    final tmpDir = (await getTemporaryDirectory()).path;
    final totalMs = durationSeconds * 1000;
    final totalSteps = (totalMs / _frameIntervalMs).ceil();
    
    var frameIndex = 0;
    
    // 按 67ms 間隔逐幀處理
    for (var ms = 0; ms < totalMs; ms += _frameIntervalMs) {
      String? thumbPath;
      try {
        // 1. 從視頻提取 thumbnail (JPEG)
        thumbPath = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: tmpDir,
          imageFormat: ImageFormat.JPEG,
          timeMs: ms,
          quality: 85,
          maxWidth: 720,  // 對齊 Python FAST_POSE_LONG_SIDE=720
        );
        
        if (thumbPath != null && await File(thumbPath).exists()) {
          // 2. 推理 (single 模式, 獨立幀)
          final poses = await poseService.detect(
            InputImage.fromFilePath(thumbPath)
          );  // ← ~30-50ms
          
          // 3. 寫入 CSV
          if (poses.isNotEmpty) {
            writer.addFrame(PoseFrameModel.fromPose(
              frame: frameIndex,
              timeSec: ms / 1000.0,
              pose: poses.first,
              imgWidth: 720,
              imgHeight: 1280,
            ));
          } else {
            writer.addFrame(PoseFrameModel.empty(
              frame: frameIndex,
              timeSec: ms / 1000.0,
            ));
          }
        }
      } finally {
        // 清理臨時 JPEG
        if (thumbPath != null) {
          try { await File(thumbPath).delete(); } catch (_) {}
        }
      }
      
      frameIndex++;
      // 進度回調
      onProgress?.call(frameIndex / totalSteps);
    }
    
    await writer.flush();
  }
}
```

**關鍵點:**
1. 每隔 67ms 提取一幀（~15fps 抽樣）
2. 每幀都是 single 模式完整推理
3. 離線進行，不阻塞 UI
4. 最後一次性寫入所有幀

---

## 📊 效能對比

### 即時錄影性能

```
┌──────────────────────────────────────────┐
│ 30fps CameraX 實時錄影                   │
├──────────────────────────────────────────┤
│ 每幀耗時:                                │
│  - CameraX frame 到達: 33ms              │
│  - _onImageAnalysis 回調: <1ms           │
│  - poseService.detect (stream): ~15-20ms │
│  - setState + repaint: ~5-10ms           │
│  - CSV 寫入: ~1-2ms                     │
│  ───────────────────────               │
│  總計: ~25-35ms per frame ✓              │
│                                          │
│ 預期結果:                                │
│  - 幀率穩定: 28-30 fps ✓                │
│  - 骨架流暢: 時序平滑 ✅                │
│  - 無卡頓: 異步處理 ✅                  │
└──────────────────────────────────────────┘
```

### 擊球偵測性能

```
┌──────────────────────────────────────────┐
│ 離線分析 15fps 抽樣                      │
├──────────────────────────────────────────┤
│ 每幀耗時 (单步):                         │
│  - VideoThumbnail.thumbnailFile: ~50ms   │
│  - poseService.detect (single): ~30-50ms │
│  - CSV 寫入: ~1-2ms                     │
│  ───────────────────────               │
│  總計: ~80-100ms per frame               │
│                                          │
│ 對 30 秒視頻:                            │
│  - 抽樣幀數: 30s / 67ms ≈ 448 幀        │
│  - 預期時間: 448 × 90ms ≈ 40 秒        │
│  - (加上 ML Kit 初始化): ~45 秒         │
│                                          │
│ 預期結果:                                │
│  - 準確性: 單幀推理，非常高 ✅          │
│  - 離線: UI 無阻塞 ✅                   │
│  - 完整覆蓋: 無幀丟失 ✅                │
└──────────────────────────────────────────┘
```

---

## 🎯 使用場景總結

### 即時錄影何時使用

1. **用戶正在錄製** → 需要即時骨架預覽
2. **UI 反饋** → 確保用戶正確姿勢
3. **視頻保存同時** → CSV 邊錄邊累加
4. **相機輸入穩定** → 30fps YUV stream

**代碼路徑:**
- `record_screen.dart` 初始化
- `PoseDetectorService(PoseDetectionMode.stream)` 預設
- `_onImageAnalysis()` 回調處理
- `SkeletonPainter` 實時繪制

---

### 擊球偵測何時使用

1. **已保存視頻分析** → 不需要實時預覽
2. **精確離線處理** → 完整幀無丟失
3. **後續處理基準** → 與 Python 端對齐
4. **抽樣代表性** → 67ms 間隔充分

**代碼路徑:**
- `clip_pipeline_service.dart` 觸發
- `VideoAnalysisService.analyze()` 執行
- `PoseDetectorService(PoseDetectionMode.single)` 獨立
- `VideoThumbnail.thumbnailFile()` 抽幀
- CSV 離線寫入

---

## ⚡ 性能優化建議

### 即時錄影優化

1. **降低推理負載**
   ```dart
   // 改用 lightweight 模型 (如可用)
   PoseDetector(options: PoseDetectorOptions(
     model: PoseDetectionModel.lite,  // vs base
   ))
   ```

2. **抽幀減負**
   ```dart
   // 若 CameraX 是 60fps，可以跳幀
   if (frameCount % 2 == 0) {
     poseService.detect(...);  // 只推理 30fps
   }
   ```

3. **異步 CSV 寫入**
   ```dart
   unawaited(_poseWriter?.addFrame(...));  // 不阻塞 UI
   ```

---

### 擊球偵測優化

1. **增加抽樣率** (若需要更多幀)
   ```dart
   for (var ms = 0; ms < totalMs; ms += 33) {  // 改為 33ms (30fps)
     // 更密集的取樣
   }
   ```

2. **平行化處理** (若設備支持)
   ```dart
   // 同時處理多個 thumbnail
   Future.wait([
     analyze(ms: 0),
     analyze(ms: 67),
     analyze(ms: 134),
   ])
   ```

3. **GPU 加速** (若 ML Kit 支持)
   ```dart
   // 配置 GPU 委託 (需要 ML Kit GPU plugin)
   ```

---

## 📋 總結表

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│ 特性             │ 即時錄影            │ 擊球偵測             │
├──────────────────┼─────────────────────┼──────────────────────┤
│ ML 模式          │ stream (時序)       │ single (獨立)        │
│ 數據來源         │ CameraX YUV         │ VideoThumbnail JPEG  │
│ 取樣率           │ 30fps               │ 15fps (~67ms)        │
│ 推理時間/幀      │ 15-20ms             │ 30-50ms              │
│ 平滑性           │ 優秀                │ 普通                 │
│ 精度             │ 高                  │ 非常高               │
│ UI 影響          │ 無 (異步)           │ 無 (離線)            │
│ 幀丟失           │ 可能                │ 無                   │
│ 視頻輸出         │ 骨架預覽            │ 後處理基準           │
│ 代碼位置         │ record_screen.dart  │ video_analysis*.dart │
│ 文件夾           │ pose_landmarks.csv  │ pose_landmarks.csv   │
│ 用途             │ 實時反饋            │ 精確分析             │
└──────────────────┴─────────────────────┴──────────────────────┘
```

---

**核心區別: Stream = 實時预览，Single = 离线精析**
