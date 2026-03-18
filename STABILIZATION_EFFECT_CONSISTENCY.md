# 🎬 FFmpeg vs MeshFlow 穩定化效果一致性分析

## 📋 算法基礎差異

### FFmpeg vidstab（兩步法）
1. **vidstabdetect**：檢測相機運動向量
2. **vidstabtransform**：應用變換平滑運動

**特點**：
- ✅ 速度快（C實現）
- ✅ 參數簡潔（只需要幾個核心參數）
- ⚠️ 全局變換（同一個變換作用於所有像素）
- ⚠️ 較難捕捉局部運動

### MeshFlow（網格化局部法）
1. **建立細密網格**：將視頻分成16×16網格
2. **特徵追蹤**：在各網格點追蹤特徵
3. **運動估計**：逐點計算運動向量
4. **時間平滑**：應用時間濾波
5. **網格變形**：非線性變換應用到視頻

**特點**：
- ✅ 局部自適應（每個區域獨立調整）
- ✅ 處理非剛體運動
- ⚠️ 處理速度慢
- ⚠️ 參數複雜（20+個參數）

---

## 🔍 參數對應關係

### 1. 特徵檢測階段

| 功能 | FFmpeg | MeshFlow | 建議同步 |
|------|--------|----------|---------|
| **特徵敏感度** | `mincontrast=0.3` | `feature_ellipse_row_count=10` | 對應中等靈敏度 |
| **檢測密度** | `stepsize=6` | `mesh_row_count=16` | stepsize越小=mesh越密 |
| **精度等級** | `accuracy=15` | `homography_min_number_corresponding_features=4` | 高精度 |

**推薦一致配置**：
```
FFmpeg: mincontrast=0.25, stepsize=6, accuracy=15
MeshFlow: feature_ellipse_row_count=10, mesh_row_count=16, 
          homography_min_number_corresponding_features=4
```

### 2. 運動檢測階段

| 功能 | FFmpeg | MeshFlow | 含義 |
|------|--------|----------|------|
| **靈敏度** | `shakiness=8` | `shake_thresh_k=4.0` | 檢測晃動的敏感度 |
| **檢測窗口** | N/A | `shake_smooth_win=7` | 時間平滑窗口 |
| **檢測填充** | N/A | `shake_pad_frames=8` | 晃動段周邊填充幀數 |

**對應策略**：
- `shakiness` ↔ `shake_thresh_k`
  - 高shakiness (8-10) → 高shake_thresh_k (3.0-3.5)
  - 低shakiness (4-5) → 低shake_thresh_k (4.5-5.0)

### 3. 平滑化階段

| 功能 | FFmpeg | MeshFlow | 含義 |
|------|--------|----------|------|
| **平滑強度** | `smoothing=15` | `temporal_smoothing_radius=10` | 時間軸平滑 |
| **縮放補償** | `optzoom=1, zoomspeed=0.15` | 隱含在網格變形中 | 邊界黑邊補償 |
| **插值質量** | `interpol=2(bicubic)` | 隱含在mesh變形中 | 高質量重採樣 |

**對應策略**：
- `smoothing` ↔ `temporal_smoothing_radius`
  - smoothing=15 → radius=10（保守平滑）
  - smoothing=50 → radius=15（積極平滑）
  - smoothing=100 → radius=20（極度平滑）

### 4. 優化與迭代

| 功能 | FFmpeg | MeshFlow | 含義 |
|------|--------|----------|------|
| **品質優化** | `crf=16` | `optimization_num_iterations=80` | 計算迭代次數 |
| **自適應權重** | N/A | `adaptive_weights_definition=0` | ORIGINAL=最佳平衡 |

---

## 🎯 效果一致性對應表

### 低至中等穩定化（保留自然感）

```python
# FFmpeg 配置
ffmpeg_config = {
    'shakiness': 6,
    'accuracy': 15,
    'stepsize': 6,
    'mincontrast': 0.25,
    'smoothing': 15,      # 輕度平滑
    'optzoom': 1,
    'zoomspeed': 0.15,
    'interpol': 2,
    'crop': 1,
    'crf': 16
}

# 對應 MeshFlow 配置
meshflow_config = {
    'mesh_row_count': 16,
    'mesh_col_count': 16,
    'feature_ellipse_row_count': 10,
    'feature_ellipse_col_count': 10,
    'temporal_smoothing_radius': 10,        # 對應 smoothing=15
    'optimization_num_iterations': 80,
    'shake_thresh_k': 4.0,                  # 對應 shakiness=6
    'shake_smooth_win': 7,
    'shake_pad_frames': 8
}
```

### 中至高等穩定化（平滑明顯）

```python
# FFmpeg 配置
ffmpeg_config = {
    'shakiness': 8,
    'accuracy': 15,
    'stepsize': 4,
    'mincontrast': 0.20,
    'smoothing': 50,      # 中等平滑
    'optzoom': 1,
    'zoomspeed': 0.5,
    'interpol': 2,
    'crop': 1,
    'crf': 16
}

# 對應 MeshFlow 配置
meshflow_config = {
    'mesh_row_count': 20,          # 更密集網格
    'mesh_col_count': 20,
    'feature_ellipse_row_count': 12,
    'feature_ellipse_col_count': 12,
    'temporal_smoothing_radius': 15,        # 對應 smoothing=50
    'optimization_num_iterations': 120,
    'shake_thresh_k': 3.5,                  # 對應 shakiness=8
    'shake_smooth_win': 9,
    'shake_pad_frames': 10
}
```

### 極度穩定化（電影般效果）

```python
# FFmpeg 配置
ffmpeg_config = {
    'shakiness': 10,
    'accuracy': 15,
    'stepsize': 4,
    'mincontrast': 0.15,
    'smoothing': 100,     # 極度平滑
    'optzoom': 1,
    'zoomspeed': 1.0,
    'interpol': 2,
    'crop': 1,
    'crf': 14
}

# 對應 MeshFlow 配置
meshflow_config = {
    'mesh_row_count': 24,          # 更密集網格
    'mesh_col_count': 24,
    'feature_ellipse_row_count': 14,
    'feature_ellipse_col_count': 14,
    'temporal_smoothing_radius': 20,        # 對應 smoothing=100
    'optimization_num_iterations': 150,
    'shake_thresh_k': 3.0,                  # 對應 shakiness=10
    'shake_smooth_win': 11,
    'shake_pad_frames': 12
}
```

---

## 🚀 實現效果一致的建議

### 方案 1：統一配置管理類（推薦）

創建 `StabilizationPreset` 類，自動轉換參數：

```python
@dataclass
class StabilizationPreset:
    """統一的穩定化預設"""
    name: str           # 預設名稱
    level: int          # 1=輕, 2=中, 3=強
    
    def get_ffmpeg_config(self):
        """返回 FFmpeg 配置"""
        ...
    
    def get_meshflow_config(self):
        """返回 MeshFlow 配置"""
        ...

# 使用方式
preset = StabilizationPreset('golf_swing', level=2)
ffmpeg_cfg = preset.get_ffmpeg_config()
meshflow_cfg = preset.get_meshflow_config()
```

### 方案 2：質量指標同步

定義統一的輸出質量指標：

```python
class StabilizationQuality:
    METRICS = {
        'smoothness': 0.0-1.0,      # 平滑度
        'naturalness': 0.0-1.0,     # 自然度
        'artifact_level': 0.0-1.0,  # 偽影等級
    }
```

### 方案 3：A/B 對比測試

```python
def compare_stabilization(video_path):
    """並行運行兩種方法並對比效果"""
    # 運行 FFmpeg
    ffmpeg_result = run_ffmpeg_stabilization(ffmpeg_config)
    
    # 運行 MeshFlow
    meshflow_result = run_meshflow_stabilization(meshflow_config)
    
    # 計算相似度指標
    metrics = compute_similarity(ffmpeg_result, meshflow_result)
    return metrics
```

---

## 📊 當前配置對比

### FFmpeg 當前設置
```
shakiness=6, accuracy=15, stepsize=6, mincontrast=0.3
smoothing=15, zoomspeed=0.15, interpol=2, crf=16
```
**效果**：輕度穩定化，保留自然感

### MeshFlow 當前設置
```
mesh=16×16, feature=10×10, temporal_radius=10, iterations=80
shake_thresh_k=4.0, smooth_win=7, pad_frames=8
```
**效果**：中等穩定化，局部自適應

### 一致性評分
- ⚠️ **不完全一致** (70%)
- 原因：
  - FFmpeg smoothing=15 vs MeshFlow radius=10（有差異）
  - MeshFlow 網格更密集，檢測更精細
  - FFmpeg 采用全局變換，MeshFlow 采用局部變換

---

## ✅ 同步建議

### 立即調整

**FFmpeg 配置**：
```python
# 增加平滑度以匹配 MeshFlow
smoothing = 20  # 從 15 → 20
```

**MeshFlow 配置**：
```python
# 減少網格密度以加快速度
mesh_row_count = 12  # 從 16 → 12
mesh_col_count = 12
```

### 中期計劃

1. 實現 `StabilizationPreset` 類進行統一管理
2. 為用戶提供 3 個預設（輕/中/強）
3. 在同一個 API 下支持兩種算法切換

### 長期方案

1. 基於實際視頻創建效果對照庫
2. 用深度學習模型預測最佳參數組合
3. 實時質量評估反饋

---

## 📌 快速參考

```
┌─ 檢測敏感度 ─────────────────────┐
│ FFmpeg shakiness=8                │
│ MeshFlow shake_thresh_k=3.5       │
└───────────────────────────────────┘

┌─ 平滑強度 ──────────────────────┐
│ FFmpeg smoothing=50               │
│ MeshFlow temporal_radius=15       │
└──────────────────────────────────┘

┌─ 檢測精度 ──────────────────────┐
│ FFmpeg stepsize=4, accuracy=15    │
│ MeshFlow feature_row/col=12       │
└──────────────────────────────────┘
```

