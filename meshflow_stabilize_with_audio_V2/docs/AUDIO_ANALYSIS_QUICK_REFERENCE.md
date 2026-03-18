# Audio Analysis - 快速參考卡（單一影片處理）

## 🚀 快速開始（30 秒）

```python
from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis

config = AudioAnalysisConfig(
    video_path="path/to/video.mp4",
    output_dir="path/to/output"
)
result = run_audio_analysis(config)
```

---

## 📊 配置參數速查表

### 最常用參數

| 參數 | 默認 | 說明 |
|------|------|------|
| `video_path` | "" | 單一影片路徑（必需） |
| `output_dir` | "" | 輸出目錄（必需） |
| `loudness_mode` | "dbfs" | 音量尺度："dbfs" 或 "raw" |
| `peak_rel_strength` | 0.8 | 峰值相對強度閾值 |
| `mad_k` | 4.0 | RMS+MAD 檢測係數 |
| `target_hit_sec` | 3.0 | 目標擊球時間（秒） |
| `target_tol_sec` | 0.5 | 允許誤差（秒） |

### 時間參數

| 參數 | 默認 | 說明 |
|------|------|------|
| `pre_time_sec` | 0.10 | 擊球前取樣（秒） |
| `post_time_sec` | 0.10 | 擊球後取樣（秒） |
| `rms_frame_sec` | 0.02 | RMS 幀長 |
| `rms_hop_sec` | 0.01 | RMS hop |
| `min_dist_sec` | 0.35 | 最小擊球間距 |

---

## 🎯 常見場景速解

### 場景 1：標準分析（推薦）
```python
config = AudioAnalysisConfig(
    video_path="data/golf_swing.mp4",
    output_dir="output"
)
result = run_audio_analysis(config)
```

### 場景 2：高敏感檢測
```python
config = AudioAnalysisConfig(
    video_path="data/golf_swing.mp4",
    output_dir="output",
    peak_rel_strength=0.6,  # 更低
    mad_k=3.0,              # 更低
)
```

### 場景 3：保守檢測
```python
config = AudioAnalysisConfig(
    video_path="data/golf_swing.mp4",
    output_dir="output",
    peak_rel_strength=0.95,  # 更高
    mad_k=5.0,               # 更高
)
```

### 場景 4：不同目標擊球時間
```python
config = AudioAnalysisConfig(
    video_path="data/golf_swing.mp4",
    output_dir="output",
    target_hit_sec=2.5,      # 改為 2.5 秒
    target_tol_sec=0.3,      # ±0.3 秒容差
)
```

---

## 📈 提取的特徵（30+ 個）

**音量特徵：**
- `peak_dbfs`, `rms_dbfs`（若 loudness_mode="dbfs"）
- `max_amp`, `rms`（若 loudness_mode="raw"）

**頻譜特徵：**
- `spectral_centroid` - 頻譜重心
- `sharpness_hfxloud` - 尖銳度
- `zcr` - 過零率

**頻帶特徵（8 個頻帶，0-8kHz）：**
- `band_0k_1k_peak_freq`, `band_0k_1k_peak_amp`
- `band_1k_2k_peak_freq`, `band_1k_2k_peak_amp`
- ... （共 16 個）

**MFCC：**
- `mfcc1` 到 `mfcc13`（13 個梅爾頻率倒譜係數）

---

## 📋 返回值

```python
{
    'status': 'success',
    'video': 'golf_swing',
    'hits_detected': 2,
    'denoised_summary_path': '/path/to/golf_swing_denoised_summary.csv',
    'raw_summary_path': '/path/to/golf_swing_raw_summary.csv',  # 若 output_raw_csv=True
    'segments_dir': '/path/to/segments_golf_swing',
    'elapsed_time': 25.30
}
```

---

## 🔗 核心函數

```python
# 主入口
run_audio_analysis(config) -> Dict

# 工作流
process_audio_analysis(config) -> Dict

# 峰值檢測
dynamic_peak_detection(y, sr, ...) -> Tuple[np.ndarray, Tuple]
filter_top_peaks_by_strength(peaks, y, sr, ...) -> np.ndarray

# 特徵提取
compute_audio_features(y_segment, sr, ...) -> Dict
extract_audio_from_video(video_path, output_path) -> bool

# 去噪
spectral_subtraction(segment, sr, noise_mag, ...) -> np.ndarray
```

---

## ⚡ 性能參考

| 任務 | 時間 | 輸出 |
|------|------|------|
| 單個視頻分析 | ~10-30 秒 | CSV + 音訊段 |

---

## 💾 輸出文件

```
output_dir/
├── {video_name}_raw_summary.csv              # 原始特徵摘要（若啟用）
├── {video_name}_denoised_summary.csv         # 去噪特徵摘要
├── {video_name}_audio.wav                   # 提取的音訊
├── segments_{video_name}/
│   ├── hit_001.wav              # 擊球段音訊
│   ├── hit_001_den.wav          # 去噪後音訊
│   ├── hit_001_bg.wav           # 背景參考
│   └── ...
```

---

## 🛠️ 調試技巧

### 查看完整配置
```python
config = AudioAnalysisConfig(batch_dir="a", output_dir="b")
print(config.__dict__)
```

### 檢查峰值檢測
```python
from functions.audio_analysis import dynamic_peak_detection
peaks, ctx = dynamic_peak_detection(y, sr)
print(f"檢測到 {len(peaks)} 個峰值")
```

### 驗證特徵提取
```python
from functions.audio_analysis import compute_audio_features
features = compute_audio_features(y_seg, sr)
print(list(features.keys()))  # 列出所有特徵
```

---

## ❓ 常見問題

**Q: 如何只保存去噪版本？**
A: 設置 `output_raw_csv=False`（默認）

**Q: 如何調整音訊提取採樣率？**
A: 修改 `extract_audio_from_video()` 的 `sr` 參數

**Q: 如何改變檢測敏感度？**
A: 調整 `peak_rel_strength` 和 `mad_k`

**Q: CSV 包含哪些列？**
A: 元數據 + 30+ 個特徵列

---

## 📖 相關文件

- [AUDIO_ANALYSIS_GUIDE.md](AUDIO_ANALYSIS_GUIDE.md) - 完整 API 文檔
- [AUDIO_ANALYSIS_EXAMPLES.py](AUDIO_ANALYSIS_EXAMPLES.py) - 10 個示例
- [functions/audio_analysis.py](functions/audio_analysis.py) - 源代碼

