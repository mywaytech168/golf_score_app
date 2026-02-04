# 🚀 Gyro/IMU Affine 穩定化 - 快速開始指南

## 📍 當前進度

✅ 已有系統：
- IMU 數據記錄（外置 BLE + 手機加速度計）
- CSV 輸出格式
- 視頻錄制與時間戳同步

🔲 需要新增：
- 陀螺儀實時融合 (Gyro Fusion)
- 運動追蹤 (Motion Tracker)
- Affine 補償矩陣計算

---

## 📦 依賴新增

```yaml
# pubspec.yaml
dependencies:
  sensors_plus: ^3.0.0        # 內置加速度計、陀螺儀、磁力計
  matrix4: ^2.3.0             # 矩陣運算
```

---

## 🎯 3 個核心模塊

### 1️⃣ GyroFusion (`gyro_fusion.dart`)
```
作用：實時融合陀螺儀 + 加速度計 → 四元數
    輸入：加速度計 (100Hz) + 陀螺儀 (100Hz)
    輸出：四元數 (q = [i, j, k, w])
    算法：互補濾波 (Complementary Filter)
    
時間：< 5ms 計算延遲
精度：± 1-2° 角誤差
```

### 2️⃣ MotionTracker (`motion_tracker.dart`)
```
作用：為每個視頻幀估計相機運動
    輸入：GyroFusion 的四元數序列
    輸出：逐幀的旋轉四元數 + 歐拉角
    
幀數：30 fps 視頻 = 30 幀/秒
數據點：100 IMU 樣本/幀 = 精確估計
```

### 3️⃣ AffineCompensator (`affine_compensator.dart`)
```
作用：計算幀的補償變換矩陣
    輸入：MotionTracker 的幀運動
    輸出：3x3 Affine 矩陣 per 幀
    
模式：
    - 旋轉補償 (最快)
    - 旋轉 + 縮放補償 (平衡)
    - 完整 Affine (最準確)
```

---

## 🏗️ 集成方式

### 方式 A：後處理（推薦開始）

```dart
// 1. 錄制視頻時
_gyroFusion = GyroFusion();
_gyroFusion.start();

_motionTracker = MotionTracker(gyroFusion: _gyroFusion);
_motionTracker.initialize();

// 2. 每幀更新 (需要從 camera 插件獲取幀時間戳)
_motionTracker.updateFrame(frameId, frameTimeMs);

// 3. 錄制結束後
final motions = _motionTracker.getAllFrameMotions();
final compensator = AffineCompensator(
  motions: motions,
  frameWidth: 720,
  frameHeight: 1280,
  mode: CompensationMode.rotationWithZoom,
);

// 4. 導出參數
final matrices = compensator.exportMatrices();
// → JSON 文件保存
```

### 方式 B：實時應用（進階）

```dart
// GPU 著色器中應用
varying vec2 texCoord;
uniform mat3 affineMatrix;

void main() {
  vec3 transformed = affineMatrix * vec3(texCoord, 1.0);
  gl_FragColor = texture2D(texture, transformed.xy / transformed.z);
}
```

---

## 📊 數據格式

### 輸出 JSON (`{video}_affine.json`)

```json
{
  "metadata": {
    "recordingStartTime": "2026-02-04T10:30:45Z",
    "frameRate": 30,
    "totalFrames": 180,
    "compensationMode": "rotationWithZoom"
  },
  "frames": [
    {
      "frameId": 0,
      "timestampMs": 0,
      "affineMatrix": [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0]
      ],
      "confidence": 0.95
    },
    ...
  ]
}
```

### 應用方式 1：FFmpeg 濾鏡

```bash
# 生成 FFmpeg 濾鏡字符串
ffmpeg -i input.mp4 -vf "..." output_stabilized.mp4
```

### 應用方式 2：OpenCV Python

```python
import cv2, json
with open('video_affine.json') as f:
  data = json.load(f)
  for frame in data['frames']:
    matrix = np.array(frame['affineMatrix'])
    # 應用變換
    warped = cv2.warpAffine(frame_img, matrix[:2], ...)
```

---

## 🔧 測試清單

### 單元測試
- [ ] Quaternion 數學運算
- [ ] Euler 角轉換精度
- [ ] Matrix 矩陣平滑
- [ ] 時間戳同步偏差 < 1ms

### 集成測試
- [ ] 與現有 MeshFlow 結果對比
- [ ] 與 FFmpeg 參數兼容性
- [ ] 視頻質量評估 (SSIM/PSNR)

### 性能測試
- [ ] CPU 使用率 < 10%
- [ ] 內存占用 < 50MB
- [ ] 處理延遲 < 100ms

---

## 📈 預期效果

| 指標 | 改進 |
|------|------|
| 抖動減少 | 60-80% (相對于原始) |
| 邊界損失 | 5-10% (通過縮放補償) |
| 計算時間 | 2-5 秒 (180 幀視頻) |
| 實時預覽 | 支持 (降低質量) |

---

## 🎓 與現有系統對比

| 特性 | Gyro/IMU | FFmpeg | MeshFlow |
|------|----------|--------|----------|
| **速度** | ⚡ 最快 | ⚡⚡ 快 | 🐢 慢 |
| **精度** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **實時性** | ✅ 可實時 | ❌ 無 | ❌ 無 |
| **硬件** | ✅ 內置 | ✅ 軟件 | ✅ 軟件 |
| **融合** | ✅ 可 | ❌ 無 | ❌ 無 |

---

## 🚀 未來擴展

1. **光學流 (Optical Flow)**
   - 檢測特征點移動
   - 改進邊界像素穩定性

2. **機器學習**
   - 自動參數調整
   - 質量預測

3. **多傳感器**
   - 手機 IMU + 外置 BLE IMU 融合
   - GPS 輔助（可選）

4. **實時預覽**
   - 在錄制時顯示穩定化效果
   - GPU 加速著色器

---

## 📞 常見問題

**Q: 是否可以不修改現有系統？**  
A: 可以。後處理方式完全獨立，只需添加新模塊。

**Q: 陀螺儀標定如何進行？**  
A: 自動標定：錄制前 1 秒保持靜止即可。

**Q: 可以與 MeshFlow 同時使用嗎？**  
A: 可以，Gyro 參數先應用，再進入 MeshFlow 管道。

**Q: 視頻播放時可以實時應用嗎？**  
A: 可以，但需要 GPU 著色器支持（Flutter 可通過 OpenGL/Vulkan）。

---

**版本**: 1.0  
**最後更新**: 2026-02-04  
