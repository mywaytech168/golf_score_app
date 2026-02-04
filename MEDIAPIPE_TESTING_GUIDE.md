# MediaPipe 遷移 - 測試和驗證指南

## 快速檢查清單

### 代碼完整性檢查 ✅
- [x] 所有 OpenPose 導入已移除
- [x] MediaPipe 導入已添加
- [x] 配置類已更新（OpenPoseConfig → MediaPoseConfig）
- [x] 姿勢關鍵點定義已更新
- [x] extract_pose_keypoints() 函數已重寫
- [x] analyze_swing_phases() 配置類型已更新
- [x] initialize_pose_detector() 函數已添加
- [x] run_openpose_analysis() 已更新
- [x] 無編譯錯誤

### 文件位置
```
d:\Projects\golf_score_app\meshflow_stabilize_with_audio_V2\functions\openpose_analysis.py
```

---

## 分階段測試方案

### 第1階段：環境和導入測試

#### 1.1 驗證 MediaPipe 安裝
```bash
pip install mediapipe opencv-python numpy pandas
```

驗證：
```python
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
print("✓ MediaPipe 安裝成功")
```

#### 1.2 驗證模塊導入
```python
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    extract_pose_keypoints,
    initialize_pose_detector,
    run_openpose_analysis,
)
print("✓ 模塊導入成功")
```

### 第2階段：單元函數測試

#### 2.1 測試 initialize_pose_detector()
```python
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    initialize_pose_detector
)

config = MediaPoseConfig(video_path="test_video.mp4")
detector = initialize_pose_detector(config)

assert detector is not None
assert hasattr(detector, 'detect')
print("✓ initialize_pose_detector() 測試通過")
```

#### 2.2 測試 extract_pose_keypoints()
```python
import cv2
import numpy as np
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    extract_pose_keypoints,
    initialize_pose_detector
)

# 準備測試幀
cap = cv2.VideoCapture("test_video.mp4")
ret, frame = cap.read()
cap.release()

# 初始化檢測器
config = MediaPoseConfig(video_path="test_video.mp4")
detector = initialize_pose_detector(config)

# 提取姿勢
result = extract_pose_keypoints(frame, detector, config)

# 驗證結果結構
assert "mean_conf" in result
assert "shoulder_angle" in result
assert "hip_angle" in result
assert "x_factor" in result
assert "nose_x" in result
assert "nose_y" in result
assert "r_wrist_x" in result
assert "r_wrist_y" in result

print("✓ extract_pose_keypoints() 測試通過")
print(f"  平均置信度：{result['mean_conf']}")
print(f"  肩膀角度：{result['shoulder_angle']}°")
print(f"  髖部角度：{result['hip_angle']}°")
```

#### 2.3 測試 analyze_swing_phases()
```python
import pandas as pd
import numpy as np
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    analyze_swing_phases
)

# 創建模擬數據
data = {
    "r_wrist_x": np.random.rand(100) * 640,
    "r_wrist_y": np.random.rand(100) * 480,
    "shoulder_angle": np.linspace(20, 80, 100),
    "hip_angle": np.linspace(10, 40, 100),
}
df = pd.DataFrame(data)

config = MediaPoseConfig(video_path="test.mp4")
fps = 30

result = analyze_swing_phases(df, config, fps)

assert "success" in result
assert "df" in result
assert result["df"] is not None

print("✓ analyze_swing_phases() 測試通過")
```

### 第3階段：集成測試

#### 3.1 完整視頻分析測試
```python
from pathlib import Path
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    run_openpose_analysis
)

# 準備配置
video_path = "path/to/your/test_video.mp4"
output_dir = "path/to/output"

config = MediaPoseConfig(
    video_path=video_path,
    output_dir=output_dir,
    rotation_90_clockwise=0,
    show_rule_label=False,
    save_pose_csv=True,
    save_pose_phase_csv=True,
)

# 運行分析
results_df = run_openpose_analysis(config)

# 驗證結果
assert results_df is not None
assert len(results_df) > 0
assert "frame" in results_df.columns
assert "time_sec" in results_df.columns
assert "mean_conf" in results_df.columns
assert "shoulder_angle" in results_df.columns
assert "hip_angle" in results_df.columns
assert "x_factor" in results_df.columns
assert "nose_x" in results_df.columns
assert "r_wrist_x" in results_df.columns

print(f"✓ 完整視頻分析測試通過")
print(f"  處理幀數：{len(results_df)}")
print(f"  平均置信度：{results_df['mean_conf'].mean():.3f}")
print(f"  有效置信度的幀：{results_df['mean_conf'].notna().sum()}")

# 驗證輸出文件
csv_path = Path(output_dir) / f"{Path(video_path).stem}_pose.csv"
assert csv_path.exists()
print(f"✓ CSV 文件已生成：{csv_path}")

video_path_phase = Path(output_dir) / f"{Path(video_path).stem}_pose_phase.mp4"
assert video_path_phase.exists()
print(f"✓ Phase 視頻已生成：{video_path_phase}")
```

#### 3.2 邊界情況測試
```python
# 測試 1：短視頻（< 5 幀）
config_short = MediaPoseConfig(
    video_path="short_video.mp4"
)
try:
    results = run_openpose_analysis(config_short)
    print("✓ 短視頻測試通過")
except Exception as e:
    print(f"✗ 短視頻測試失敗：{e}")

# 測試 2：無法檢測到人物的視頻
config_empty = MediaPoseConfig(
    video_path="empty_video.mp4"
)
try:
    results = run_openpose_analysis(config_empty)
    if len(results) == 0:
        print("✓ 空視頻測試通過（正確返回空 DataFrame）")
except Exception as e:
    print(f"✓ 空視頻測試通過（適當地拋出異常：{e}）")

# 測試 3：旋轉視頻
config_rotated = MediaPoseConfig(
    video_path="test_video.mp4",
    rotation_90_clockwise=1
)
try:
    results = run_openpose_analysis(config_rotated)
    print("✓ 旋轉視頻測試通過")
except Exception as e:
    print(f"✗ 旋轉視頻測試失敗：{e}")
```

### 第4階段：性能和準確性測試

#### 4.1 幀率測試
```python
import time
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    run_openpose_analysis
)

start_time = time.time()
config = MediaPoseConfig(video_path="test_video.mp4")
results = run_openpose_analysis(config)
end_time = time.time()

total_frames = len(results)
total_time = end_time - start_time
fps_actual = total_frames / total_time if total_time > 0 else 0

print(f"✓ 性能測試結果")
print(f"  總幀數：{total_frames}")
print(f"  總耗時：{total_time:.2f} 秒")
print(f"  處理速度：{fps_actual:.2f} fps")
```

#### 4.2 檢測置信度測試
```python
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    run_openpose_analysis
)

config = MediaPoseConfig(video_path="test_video.mp4")
results = run_openpose_analysis(config)

# 統計置信度
valid_frames = results[results["mean_conf"].notna()]
confidence_stats = {
    "有效幀數": len(valid_frames),
    "平均置信度": valid_frames["mean_conf"].mean(),
    "最小置信度": valid_frames["mean_conf"].min(),
    "最大置信度": valid_frames["mean_conf"].max(),
    "置信度標準差": valid_frames["mean_conf"].std(),
}

print("✓ 置信度統計")
for key, value in confidence_stats.items():
    print(f"  {key}：{value}")
```

---

## 預期結果

### 正常運行應該看到：
```
================================================================================
🧑 MediaPipe 姿勢分析
================================================================================
📽️ 影片：test_video.mp4
📁 輸出：./output
🎬 FPS: 30.0, 解析度: 1920x1080
⛳ 正在進行姿勢估計...
✓ MediaPipe Pose detector 初始化成功
🎯 正在分析揮桿階段...
✅ 揮桿階段：address→25，backswing→45，impact→65，low→85
💾 已保存 pose CSV：./output/test_video_pose.csv
💾 已保存 pose_phase CSV：./output/test_video_pose_phase.csv
🎥 正在產生帶階段標籤的影片...
🎵 正在合併音訊...
✅ 已輸出 phase 影片：./output/test_video_pose_phase.mp4

✅ MediaPipe 分析完成！共 900 幀
```

### 輸出文件：
```
output/
├── test_video_tmp_pose.mp4          （臨時文件，已刪除）
├── test_video_tmp_phase.mp4         （臨時文件，已刪除）
├── test_video_pose.csv              ✅ 姿勢數據
├── test_video_pose_phase.csv        ✅ 帶階段標籤的姿勢數據
└── test_video_pose_phase.mp4        ✅ 最終分析視頻
```

### CSV 列名：
```
frame, time_sec, mean_conf, shoulder_angle, hip_angle, x_factor,
nose_x, nose_y,
l_shoulder_x, l_shoulder_y, r_shoulder_x, r_shoulder_y,
l_hip_x, l_hip_y, r_hip_x, r_hip_y,
l_wrist_x, l_wrist_y, r_wrist_x, r_wrist_y,
phase
```

---

## 故障排除

### 問題 1：ImportError: No module named 'mediapipe'
```bash
# 解決方案
pip install mediapipe --upgrade
```

### 問題 2：RuntimeError: MediaPipe Pose detector 初始化失敗
- 檢查 MediaPipe 版本
- 嘗試卸載重新安裝：`pip uninstall mediapipe && pip install mediapipe`

### 問題 3：無法開啟影片
- 驗證視頻文件路徑
- 確保視頻格式被 OpenCV 支持（MP4, AVI, MOV 等）
- 檢查視頻文件未被損壞

### 問題 4：不檢測人物
- 確保視頻中有完整的人物身體
- 檢查光線條件
- 嘗試降低 `min_total_conf` 或 `keypoint_conf_threshold`

---

## 下一步操作

1. **立即執行**：第 1 階段 - 環境測試
2. **今天執行**：第 2 階段 - 單元函數測試
3. **本週執行**：第 3 階段 - 集成測試
4. **本週執行**：第 4 階段 - 性能測試

---

**狀態**：✅ 代碼遷移完成，等待測試驗證
**最後更新**：2024
