# 🎬 穩定化參數快速參考

## 三級配置對照表

### LIGHT (輕度) - 保留細節

```
┌─────────────────────────────────────────────────┐
│ FFmpeg Configuration                            │
├─────────────────────────────────────────────────┤
│ shakiness       : 4                             │
│ accuracy        : 12                            │
│ stepsize        : 8                             │
│ mincontrast     : 0.30                          │
│ smoothing       : 10                            │
│ zoomspeed       : 0.10                          │
│ interpol        : 1 (bilinear)                  │
│ crf             : 18 (保留品質)                  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ MeshFlow Configuration                          │
├─────────────────────────────────────────────────┤
│ mesh_row_count              : 12                │
│ mesh_col_count              : 12                │
│ feature_ellipse_row_count   : 8                 │
│ temporal_smoothing_radius   : 8                 │
│ optimization_num_iterations : 60                │
│ shake_thresh_k              : 4.5               │
│ shake_smooth_win            : 5                 │
│ shake_pad_frames            : 5                 │
└─────────────────────────────────────────────────┘

用途: 保留自然感，最小干擾，適合高速分析
```

---

### MEDIUM (中等) ⭐ 推薦

```
┌─────────────────────────────────────────────────┐
│ FFmpeg Configuration                            │
├─────────────────────────────────────────────────┤
│ shakiness       : 6                             │
│ accuracy        : 15                            │
│ stepsize        : 6                             │
│ mincontrast     : 0.25                          │
│ smoothing       : 20                            │
│ zoomspeed       : 0.15                          │
│ interpol        : 2 (bicubic)                   │
│ crf             : 16 (高品質)                    │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ MeshFlow Configuration                          │
├─────────────────────────────────────────────────┤
│ mesh_row_count              : 16                │
│ mesh_col_count              : 16                │
│ feature_ellipse_row_count   : 10                │
│ temporal_smoothing_radius   : 10                │
│ optimization_num_iterations : 80                │
│ shake_thresh_k              : 4.0               │
│ shake_smooth_win            : 7                 │
│ shake_pad_frames            : 8                 │
└─────────────────────────────────────────────────┘

用途: 平衡穩定性和自然感，最適合高爾夫分析
時間: FFmpeg ~10s，MeshFlow ~30s
```

---

### STRONG (強) - 優先穩定

```
┌─────────────────────────────────────────────────┐
│ FFmpeg Configuration                            │
├─────────────────────────────────────────────────┤
│ shakiness       : 8                             │
│ accuracy        : 15                            │
│ stepsize        : 4                             │
│ mincontrast     : 0.20                          │
│ smoothing       : 40                            │
│ zoomspeed       : 0.30                          │
│ interpol        : 2 (bicubic)                   │
│ crf             : 14 (最高品質)                  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ MeshFlow Configuration                          │
├─────────────────────────────────────────────────┤
│ mesh_row_count              : 20                │
│ mesh_col_count              : 20                │
│ feature_ellipse_row_count   : 12                │
│ temporal_smoothing_radius   : 15                │
│ optimization_num_iterations : 120               │
│ shake_thresh_k              : 3.5               │
│ shake_smooth_win            : 9                 │
│ shake_pad_frames            : 10                │
└─────────────────────────────────────────────────┘

用途: 強烈穩定化，電影般效果，可能過度平滑
時間: FFmpeg ~12s，MeshFlow ~45s
```

---

## 🎯 快速選擇指南

```
你的需求是什麼？

1️⃣ 快速分析，需要速度優先
   └─ 使用 FFmpeg + MEDIUM
   └─ 時間: ~10秒

2️⃣ 精細分析，運動複雜
   └─ 使用 MeshFlow + MEDIUM
   └─ 時間: ~30秒

3️⃣ 不確定，試試兩個
   └─ FFmpeg 先快速預覽
   └─ 然後用 MeshFlow 精化

4️⃣ 性能要求高
   └─ FFmpeg + LIGHT
   └─ 時間: ~8秒

5️⃣ 品質要求極高
   └─ MeshFlow + STRONG
   └─ 時間: ~45秒
```

---

## 💻 代碼使用示例

### 方式 1：使用預設（推薦）

```python
from stabilization_preset import get_preset
from ffmpeg_stabilization import FFmpegStabilizeConfig, run_ffmpeg_stabilization

# 獲取預設
preset = get_preset('golf_medium')

# 創建配置
config = FFmpegStabilizeConfig(
    input_path="input.mp4",
    output_path="output.mp4"
)

# 應用預設
preset.apply_to_ffmpeg_config(config)

# 運行穩定化
result = run_ffmpeg_stabilization(config)
```

### 方式 2：手動配置

```python
from ffmpeg_stabilization import FFmpegStabilizeConfig, run_ffmpeg_stabilization

config = FFmpegStabilizeConfig(
    input_path="input.mp4",
    output_path="output.mp4",
    # MEDIUM 配置
    shakiness=6,
    accuracy=15,
    stepsize=6,
    mincontrast=0.25,
    smoothing=20,
    zoomspeed=0.15,
    interpol=2,
    crf=16
)

result = run_ffmpeg_stabilization(config)
```

### 方式 3：列出所有預設

```python
from stabilization_preset import get_all_presets

presets = get_all_presets()
for name, preset in presets.items():
    print(f"{name}: {preset.description}")
    print(f"  FFmpeg: {preset.get_ffmpeg_config()}")
    print(f"  MeshFlow: {preset.get_meshflow_config()}")
```

---

## 📊 性能參考

```
視頻: 720×1280, 30fps, 6秒 = 180幀

FFmpeg (MEDIUM)
├─ 檢測: 0.5秒 (vidstabdetect)
├─ 應用: 2秒 (vidstabtransform)
├─ 編碼: 8秒 (libx264)
└─ 總計: 10.5秒 ⚡

MeshFlow (MEDIUM)
├─ 檢測: 5秒 (16×16網格追蹤)
├─ 平滑: 3秒 (temporal濾波)
├─ 編碼: 15秒 (FFmpeg)
├─ 邊界處理: 5秒
└─ 總計: 28秒
```

---

## 🔗 文件引用

- **詳細分析**: [STABILIZATION_EFFECT_CONSISTENCY.md](./STABILIZATION_EFFECT_CONSISTENCY.md)
- **實現方案**: [STABILIZATION_SYNC_IMPLEMENTATION.md](./STABILIZATION_SYNC_IMPLEMENTATION.md)
- **預設管理**: [stabilization_preset.py](./meshflow_stabilize_with_audio_V2/functions/stabilization_preset.py)
- **FFmpeg實現**: [ffmpeg_stabilization.py](./meshflow_stabilize_with_audio_V2/functions/ffmpeg_stabilization.py)
- **MeshFlow實現**: [meshflow_stabilization.py](./meshflow_stabilize_with_audio_V2/functions/meshflow_stabilization.py)

