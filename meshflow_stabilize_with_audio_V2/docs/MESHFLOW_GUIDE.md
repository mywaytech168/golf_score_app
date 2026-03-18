# MeshFlow Video Stabilization - 完整 API 文檔

## 概述

MeshFlow 視頻穩定化是一個生產級函數庫，用於檢測和移除視頻中的相機晃動。

**核心特性：**
- 🎯 自動晃動段檢測（堅牢統計算法）
- 🔧 完全可配置的 20+ 參數
- 🎨 優雅降級（tqdm 可選）
- 📊 詳細的結果報告
- 🔊 保留原始音訊
- 💾 支持大視頻處理

---

## 快速開始

### 最簡單的方式

```python
from functions.meshflow_stabilization import MeshFlowConfig, run_meshflow_stabilization

# 基本配置
config = MeshFlowConfig(
    input_path="input_video.mp4",
    output_path="output_stabilized.mp4"
)

# 執行穩定化
result = run_meshflow_stabilization(config)

# 結果
print(result)
# {'mode': 'segment_meshflow', 
#  'segment': (100, 500),      # 晃動段
#  'crop_boundaries': (x, y, w, h),  # 裁剪邊界
#  'output': '/path/to/output.mp4'}
```

### 進階配置

```python
from functions.meshflow_stabilization import MeshFlowConfig, run_meshflow_stabilization

config = MeshFlowConfig(
    # ========== 輸入輸出 ==========
    input_path="input.mp4",
    output_path="output.mp4",
    
    # ========== 晃動檢測參數 ==========
    auto_shake_segment=True,         # 自動檢測晃動段
    shake_smooth_win=7,              # 平滑窗口大小
    shake_thresh_k=3.0,              # 堅牢閾值係數（越高越嚴格）
    shake_pad_frames=10,             # 晃動段前後擴展
    shake_min_seg_len=12,            # 最小晃動段長度
    
    # ========== 網格參數 ==========
    mesh_row_count=16,               # 網格行數
    mesh_col_count=16,               # 網格列數
    mesh_outlier_subframe_row_count=4,
    mesh_outlier_subframe_col_count=4,
    
    # ========== 時間平滑 ==========
    temporal_smoothing_radius=10,    # 時間平滑範圍
    optimization_num_iterations=80,  # 優化迭代次數
    
    # ========== 特徵偵測 ==========
    homography_min_number_corresponding_features=4,
    feature_ellipse_row_count=10,
    feature_ellipse_col_count=10,
)

result = run_meshflow_stabilization(config)
```

---

## 配置參數詳解

### MeshFlowConfig 類

#### 輸入輸出

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `input_path` | str | "" | 輸入視頻文件路徑（必需） |
| `output_path` | str | "" | 輸出 MP4 文件路徑（必需） |

#### 晃動檢測參數

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `auto_shake_segment` | bool | True | 自動檢測晃動段（True）或手動指定（False） |
| `shake_smooth_win` | int | 7 | 晃動評分平滑窗口大小（必須是奇數） |
| `shake_thresh_k` | float | 3.0 | 堅牢閾值係數：threshold = median + k*MAD |
| `shake_pad_frames` | int | 10 | 晃動段前後擴展的幀數 |
| `shake_min_seg_len` | int | 12 | 最小晃動段長度（少於此長度的段被忽略） |
| `manual_start` | int | None | 手動指定晃動段起始幀（auto_shake_segment=False） |
| `manual_end` | int | None | 手動指定晃動段末尾幀（auto_shake_segment=False） |

**晃動檢測策略：**
- 原始信號：將每對相鄰幀的單應矩陣轉換為「運動量」
- 高通濾波：計算 raw - median_filter(raw)，提取高頻晃動能量
- 堅牢檢測：使用 MAD（中位數絕對差）計算自適應閾值
- 連續性：合併鄰近的高分幀，選擇最長的連續區段

#### 網格參數（MeshFlow 算法）

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `mesh_row_count` | int | 16 | 變形網格行數 |
| `mesh_col_count` | int | 16 | 變形網格列數 |
| `mesh_outlier_subframe_row_count` | int | 4 | 異常檢測子幀行數 |
| `mesh_outlier_subframe_col_count` | int | 4 | 異常檢測子幀列數 |

**建議：**
- 低分辨率（< 720p）：8x8 或 12x12
- 高分辨率（>= 720p）：16x16 或 20x20
- 快速處理：12x12 左右
- 高精度：20x20 或更高

#### 時間平滑參數

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `temporal_smoothing_radius` | int | 10 | 時間平滑影響範圍（幀數） |
| `optimization_num_iterations` | int | 80 | Jacobi 迭代優化次數 |
| `adaptive_weights_definition` | int | 0 | 自適應權重定義（0-3） |

**自適應權重選項：**
- 0 = ORIGINAL（默認，根據單應特徵值自適應）
- 1 = FLIPPED（相反的自適應權重）
- 2 = CONSTANT_HIGH（常數高權重，激進平滑）
- 3 = CONSTANT_LOW（常數低權重，保留細節）

#### 特徵偵測參數

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `homography_min_number_corresponding_features` | int | 4 | 計算單應需要的最小對應特徵點數 |
| `feature_ellipse_row_count` | int | 10 | 特徵橢圓影響範圍行數 |
| `feature_ellipse_col_count` | int | 10 | 特徵橢圓影響範圍列數 |

#### 輸出參數

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `color_outside_image_area_bgr` | tuple | (0,0,255) | 超出圖像邊界的填充顏色（紅色） |
| `visualize` | bool | False | 顯示穩定化過程的可視化 |
| `warp_downscale` | float | 0.5 | 變形下縮放因子（優化性能） |

---

## API 函數參考

### 主函數

#### `run_meshflow_stabilization(config: Optional[MeshFlowConfig] = None) -> Dict`

**用途：** MeshFlow 穩定化的統一入口

**參數：**
- `config`: MeshFlowConfig 配置對象，None 時使用全部默認值

**返回值：**
```python
{
    "mode": "segment_meshflow" 或 "no_shake_detected_copy_only",
    "segment": (start_frame, end_frame) 或 None,
    "crop_boundaries": (left, top, right, bottom),
    "output": "/path/to/output.mp4"
}
```

**異常：**
- `ValueError`: 配置參數無效
- `IOError`: 視頻無法讀取
- `RuntimeError`: ffmpeg 執行失敗

**示例：**
```python
from functions.meshflow_stabilization import MeshFlowConfig, run_meshflow_stabilization

config = MeshFlowConfig(
    input_path="shake_video.mp4",
    output_path="stable_video.mp4",
    shake_thresh_k=3.0
)
result = run_meshflow_stabilization(config)
print(f"穩定段：{result['segment']}")
```

### 工作流函數

#### `process_meshflow_stabilization(config: MeshFlowConfig) -> Dict`

**用途：** 完整的穩定化工作流（底層 API）

**流程：**
1. 讀取視頻全幀
2. 建立 MeshFlow Stabilizer
3. 偵測晃動段（自動或手動）
4. 計算動作估計
5. 穩定化晃動段
6. 組合全片並裁剪
7. 編寫輸出視頻

**參數：**
- `config`: MeshFlowConfig 配置

**返回值：** 同 `run_meshflow_stabilization()`

### 晃動檢測函數

#### `compute_shake_scores(homographies: np.ndarray, frame_width: int, frame_height: int) -> np.ndarray`

**用途：** 計算每幀的晃動評分

**原理：**
- 從單應矩陣提取平移和仿射信息
- 計算高頻能量（raw - median_filter(raw)）

**參數：**
- `homographies`: (num_frames, 3, 3) 單應矩陣
- `frame_width`: 幀寬度
- `frame_height`: 幀高度

**返回值：** (num_frames,) 晃動評分

#### `pick_shake_segment(scores: np.ndarray, pad: int = 10, k: float = 4.0, min_len: int = 12) -> Optional[Tuple]`

**用途：** 從晃動評分中檢測晃動段

**算法：**
- 計算 threshold = median + k * MAD（堅牢統計）
- 找所有高於閾值的連續區段
- 選擇最長的區段並擴展 `pad` 幀

**參數：**
- `scores`: 晃動評分
- `pad`: 段前後擴展幀數
- `k`: 閾值係數（越高越嚴格）
- `min_len`: 最小段長度

**返回值：** (start_frame, end_frame) 或 None

### IO 函數

#### `load_video_frames(video_path: str) -> Tuple[List[np.ndarray], int, float]`

**用途：** 讀取視頻的所有幀

**參數：**
- `video_path`: 視頻文件路徑

**返回值：** (frames, num_frames, fps)
- frames: 幀列表（BGR numpy 數組）
- num_frames: 總幀數
- fps: 幀率

**異常：**
- `IOError`: 無法打開視頻或讀取失敗

#### `write_video_with_audio_copy(input_path: str, output_path: str, fps: float, frames_bgr: List[np.ndarray]) -> bool`

**用途：** 寫出視頻並複製音訊

**流程：**
1. OpenCV 寫臨時 AVI（無音訊，MJPG/XVID）
2. ffmpeg 合成：臨時視頻 + 原音訊 → MP4

**參數：**
- `input_path`: 原視頻路徑（提取音訊）
- `output_path`: 輸出 MP4 路徑
- `fps`: 幀率
- `frames_bgr`: BGR 幀列表

**返回值：** True 成功

**異常：**
- `ValueError`: 輸出路徑不是 .mp4
- `IOError`: 視頻寫入失敗
- `RuntimeError`: ffmpeg 執行失敗

---

## 常見使用場景

### 場景 1：快速穩定化（默認參數）

```python
from functions.meshflow_stabilization import MeshFlowConfig, run_meshflow_stabilization

result = run_meshflow_stabilization(
    MeshFlowConfig(
        input_path="shaky_golf_video.mp4",
        output_path="stable_golf_video.mp4"
    )
)
```

### 場景 2：嚴格的晃動檢測

```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    shake_thresh_k=2.0,         # 更低的閾值（更敏感）
    shake_pad_frames=15,        # 擴展更多幀
    shake_smooth_win=9,         # 更強的平滑
)
result = run_meshflow_stabilization(config)
```

### 場景 3：寬鬆的晃動檢測

```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    shake_thresh_k=5.0,         # 更高的閾值（更保守）
    shake_min_seg_len=20,       # 更長的最小段
)
result = run_meshflow_stabilization(config)
```

### 場景 4：手動指定晃動段

```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    auto_shake_segment=False,
    manual_start=100,            # 從第 100 幀開始
    manual_end=500,              # 到第 500 幀結束
)
result = run_meshflow_stabilization(config)
```

### 場景 5：高精度穩定化

```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    mesh_row_count=20,           # 更高的網格密度
    mesh_col_count=20,
    temporal_smoothing_radius=15,  # 更強的時間平滑
    optimization_num_iterations=150,
)
result = run_meshflow_stabilization(config)
```

### 場景 6：快速處理（低精度）

```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    mesh_row_count=8,            # 更低的網格密度
    mesh_col_count=8,
    temporal_smoothing_radius=5,
    optimization_num_iterations=40,
)
result = run_meshflow_stabilization(config)
```

---

## 故障排查

### 問題 1：未檢測到晃動段

**原因：** 晃動不夠明顯或參數過於嚴格

**解決方案：**
```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    shake_thresh_k=2.0,    # 降低閾值
    shake_min_seg_len=5,   # 降低最小段長度
)
```

### 問題 2：穩定化結果不好

**原因：** 網格太粗、時間平滑不足或算法參數不匹配

**解決方案：**
```python
config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="output.mp4",
    mesh_row_count=20,     # 增加網格密度
    mesh_col_count=20,
    temporal_smoothing_radius=15,  # 增加時間平滑
)
```

### 問題 3：ffmpeg 錯誤

**原因：** ffmpeg 未安裝或視頻格式不支持

**解決方案：**
```bash
# Windows
choco install ffmpeg

# Ubuntu
sudo apt-get install ffmpeg

# macOS
brew install ffmpeg
```

### 問題 4：內存不足

**原因：** 大視頻文件一次加載全幀

**解決方案：** 
- 降低視頻分辨率或幀率
- 分段處理（在代碼中手動切割視頻）
- 使用更高內存的機器

---

## 性能優化建議

| 操作 | 建議 |
|------|------|
| **快速預覽** | mesh=8x8, iter=40, radius=5 |
| **標準處理** | mesh=16x16, iter=80, radius=10（默認） |
| **高精度** | mesh=20x20, iter=150, radius=15 |
| **大視頻** | 分段處理，或使用更低的網格密度 |

---

## 返回值詳解

### 成功案例 1：檢測到晃動並穩定化

```python
{
    "mode": "segment_meshflow",
    "segment": (100, 500),                    # 晃動段起始、結束
    "crop_boundaries": (50, 40, 1230, 710),  # 裁剪邊界
    "output": "/path/to/output.mp4"
}
```

### 成功案例 2：未檢測到晃動，直接複製

```python
{
    "mode": "no_shake_detected_copy_only",
    "segment": None,
    "output": "/path/to/output.mp4"
}
```

---

## 進階用法

### 自定義晃動檢測

```python
from functions.meshflow_stabilization import (
    load_video_frames,
    compute_shake_scores,
    pick_shake_segment,
    MeshFlowConfig
)
import importlib.util
from pathlib import Path

# 讀取視頻
frames, num_frames, fps = load_video_frames("video.mp4")

# 導入 Stabilizer
script_path = Path("original/main_scripts/meshflow_stabilize_with_audio.py")
spec = importlib.util.spec_from_file_location("m", script_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

stabilizer = module.MeshFlowStabilizer()

# 計算晃動評分
h, w = frames[0].shape[:2]
unstab_disp, homographies = stabilizer._get_unstabilized_vertex_displacements_and_homographies(
    num_frames, frames
)
scores = compute_shake_scores(homographies, w, h)

# 自定義檢測邏輯
seg = pick_shake_segment(scores, pad=15, k=2.5, min_len=10)
print(f"晃動段：{seg}")
```

---

## 版本信息

- **版本：** 1.0 (MeshFlow Refactoring)
- **依賴：** numpy, cv2, subprocess, pathlib
- **可選：** tqdm（進度條）
- **Python：** 3.7+

---

## 相關文件

- [MESHFLOW_EXAMPLES.py](MESHFLOW_EXAMPLES.py) - 10 個實用示例
- [MESHFLOW_QUICK_REFERENCE.md](MESHFLOW_QUICK_REFERENCE.md) - 快速參考
- [functions/meshflow_stabilization.py](functions/meshflow_stabilization.py) - 源代碼

