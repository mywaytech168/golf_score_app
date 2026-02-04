# MeshFlow Video Stabilization - 快速參考卡

## 🚀 快速開始（30 秒）

```python
from functions.meshflow_stabilization import MeshFlowConfig, run_meshflow_stabilization

config = MeshFlowConfig(
    input_path="video.mp4",
    output_path="video_stable.mp4"
)
result = run_meshflow_stabilization(config)
```

---

## 📊 配置參數速查表

### 最常用參數

| 參數 | 范圍 | 默認 | 說明 |
|------|------|------|------|
| `shake_thresh_k` | 1.0-10.0 | 3.0 | 晃動檢測敏感度（低=敏感，高=保守） |
| `mesh_row_count` | 4-32 | 16 | 網格密度（高=精度高但慢） |
| `temporal_smoothing_radius` | 1-20 | 10 | 時間平滑強度 |
| `optimization_num_iterations` | 20-200 | 80 | 優化迭代次數 |

### 快速設置表

```python
# 預覽模式（最快）
mesh_row_count=8, temporal_smoothing_radius=5, optimization_num_iterations=40

# 標準模式（平衡）
mesh_row_count=16, temporal_smoothing_radius=10, optimization_num_iterations=80

# 精細模式（最慢但最好）
mesh_row_count=20, temporal_smoothing_radius=15, optimization_num_iterations=150
```

---

## 🎯 常見場景速解

### 場景 1：自動穩定（推薦）
```python
MeshFlowConfig(input_path="a.mp4", output_path="b.mp4")
```

### 場景 2：檢測所有晃動
```python
MeshFlowConfig(
    input_path="a.mp4", output_path="b.mp4",
    shake_thresh_k=2.0,  # 降低
)
```

### 場景 3：只檢測明顯晃動
```python
MeshFlowConfig(
    input_path="a.mp4", output_path="b.mp4",
    shake_thresh_k=5.0,  # 提高
)
```

### 場景 4：手動指定段
```python
MeshFlowConfig(
    input_path="a.mp4", output_path="b.mp4",
    auto_shake_segment=False,
    manual_start=100, manual_end=500
)
```

### 場景 5：最高質量
```python
MeshFlowConfig(
    input_path="a.mp4", output_path="b.mp4",
    mesh_row_count=20, mesh_col_count=20,
    temporal_smoothing_radius=15,
    optimization_num_iterations=150
)
```

### 場景 6：最快速度
```python
MeshFlowConfig(
    input_path="a.mp4", output_path="b.mp4",
    mesh_row_count=8, mesh_col_count=8,
    temporal_smoothing_radius=5,
    optimization_num_iterations=40
)
```

---

## 💡 參數調整建議

### 如果檢測不到晃動
```python
shake_thresh_k=2.0 或更低  # 降低敏感度
shake_min_seg_len=5         # 降低最小段長
```

### 如果穩定效果不好
```python
mesh_row_count=20           # 增加網格密度
temporal_smoothing_radius=15  # 增加平滑
optimization_num_iterations=150
```

### 如果太慢
```python
mesh_row_count=8            # 降低網格密度
temporal_smoothing_radius=5
optimization_num_iterations=40
```

### 如果過度修改（失去動作）
```python
adaptive_weights_definition=3  # CONSTANT_LOW
temporal_smoothing_radius=5    # 降低平滑
```

---

## 📋 返回值

| 字段 | 說明 |
|------|------|
| `mode` | "segment_meshflow" 或 "no_shake_detected_copy_only" |
| `segment` | (start_frame, end_frame) 或 None |
| `crop_boundaries` | (left, top, right, bottom) |
| `output` | 輸出文件路徑 |

---

## 🔗 核心函數

```python
# 完整入口
run_meshflow_stabilization(config: MeshFlowConfig) -> Dict

# 工作流函數
process_meshflow_stabilization(config: MeshFlowConfig) -> Dict

# 晃動檢測
compute_shake_scores(homographies, W, H) -> np.ndarray
pick_shake_segment(scores, pad=10, k=4.0, min_len=12) -> Tuple or None

# IO 函數
load_video_frames(video_path) -> (frames, num_frames, fps)
write_video_with_audio_copy(input, output, fps, frames) -> bool
```

---

## ⚡ 性能參考

| 配置 | 網格 | 迭代 | 時間 | 質量 |
|------|------|------|------|------|
| 快速 | 8x8 | 40 | ⚡⚡⚡ | ⭐⭐ |
| 標準 | 16x16 | 80 | ⚡⚡ | ⭐⭐⭐ |
| 精細 | 20x20 | 150 | ⚡ | ⭐⭐⭐⭐⭐ |

---

## 🛠️ 調試技巧

### 查看完整配置
```python
config = MeshFlowConfig(input_path="a.mp4", output_path="b.mp4")
print(config.__dict__)
```

### 檢查結果模式
```python
result = run_meshflow_stabilization(config)
if result['mode'] == 'no_shake_detected_copy_only':
    print("未檢測到晃動")
else:
    print(f"穩定化段：{result['segment']}")
```

### 驗證 ffmpeg
```bash
ffmpeg -version  # 檢查是否安裝
```

---

## 📚 相關文件

| 文件 | 用途 |
|------|------|
| [MESHFLOW_GUIDE.md](MESHFLOW_GUIDE.md) | 完整 API 文檔 |
| [MESHFLOW_EXAMPLES.py](MESHFLOW_EXAMPLES.py) | 10 個實用示例 |
| [functions/meshflow_stabilization.py](functions/meshflow_stabilization.py) | 源代碼 |

---

## ❓ 常見問題

**Q: 如何加速處理？**
A: 使用快速預設 (8x8 網格，40 迭代)，見場景 6

**Q: 如何提高穩定質量？**
A: 使用精細預設 (20x20 網格，150 迭代)，見場景 5

**Q: 如何只穩定某一段？**
A: 使用手動指定，見場景 4

**Q: 如何保留更多動作？**
A: 降低 `temporal_smoothing_radius` 或使用 `adaptive_weights_definition=3`

**Q: 輸出文件在哪？**
A: 在 `config.output_path` 指定的位置

---

## 💾 保存配置

```python
from dataclasses import asdict
import json

config = MeshFlowConfig(input_path="a.mp4", output_path="b.mp4")

# 保存為 JSON
with open("config.json", "w") as f:
    json.dump(asdict(config), f)

# 從 JSON 加載
with open("config.json") as f:
    data = json.load(f)
    config = MeshFlowConfig(**data)
```

---

## 🎓 推薦的調整順序

1. 先確定合適的檢測參數（`shake_thresh_k`）
2. 再調整網格密度（`mesh_row_count`）
3. 最後微調平滑強度（`temporal_smoothing_radius`）

---

## 📞 支援資訊

- 文檔：見 [MESHFLOW_GUIDE.md](MESHFLOW_GUIDE.md)
- 示例：見 [MESHFLOW_EXAMPLES.py](MESHFLOW_EXAMPLES.py)
- 源碼：見 [functions/meshflow_stabilization.py](functions/meshflow_stabilization.py)

