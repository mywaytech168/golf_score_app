# 🎓 Audio Analysis - 單一影片處理使用指南

## 快速概覽

audio_analysis.py 現已轉換為 **單一影片處理模式**，而不是批處理模式。

- **輸入：** 1 個視頻檔案
- **輸出：** 1 個 CSV 摘要 + 音訊段
- **時間：** ~10-30 秒/影片

---

## 🚀 基本使用

### 最簡單的方式

```python
from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis

config = AudioAnalysisConfig(
    video_path="golf_video.mp4",
    output_dir="output"
)

result = run_audio_analysis(config)
print(result)
```

### 完整示例

```python
from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis
import json

# 配置
config = AudioAnalysisConfig(
    video_path="data/swing_001.mp4",
    output_dir="output/swing_001",
    loudness_mode="dbfs",
    peak_rel_strength=0.8,
    target_hit_sec=3.0,
    target_tol_sec=0.5,
    save_segment_audio=True
)

# 執行
result = run_audio_analysis(config)

# 檢查結果
if result['status'] == 'success':
    print(f"✅ 成功分析：{result['video']}")
    print(f"   檢測到 {result['hits_detected']} 個擊球")
    print(f"   耗時 {result['elapsed_time']:.1f} 秒")
    print(f"   CSV：{result['denoised_summary_path']}")
else:
    print(f"❌ 失敗：{result['status']}")
```

---

## 📋 返回值說明

```python
{
    'status': 'success',              # 'success' | 'no_peaks' | 'peak_out_of_range'
    'video': 'swing_001',             # 視頻名稱（無副檔名）
    'hits_detected': 2,               # 檢測到的擊球數
    'denoised_summary_path': '...',   # 去噪特徵 CSV 路徑
    'raw_summary_path': '...',        # 原始特徵 CSV 路徑（可選）
    'segments_dir': '...',            # 音訊段目錄
    'elapsed_time': 25.3              # 執行時間（秒）
}
```

---

## ⚙️ 配置參數

### 必需參數

| 參數 | 說明 | 範例 |
|------|------|------|
| `video_path` | 單一影片路徑 | `"videos/swing.mp4"` |
| `output_dir` | 輸出目錄 | `"output"` |

### 常用參數

| 參數 | 默認 | 說明 | 範圍 |
|------|------|------|------|
| `loudness_mode` | "dbfs" | 音量模式 | "dbfs" 或 "raw" |
| `peak_rel_strength` | 0.8 | 峰值相對強度 | 0.0 - 1.0 |
| `mad_k` | 4.0 | RMS MAD 係數 | 1.0 - 10.0 |
| `target_hit_sec` | 3.0 | 目標擊球時間（秒） | 0.0 - video_length |
| `target_tol_sec` | 0.5 | 允許誤差（秒） | 0.0 - 5.0 |

### 時間參數

| 參數 | 默認 | 說明 |
|------|------|------|
| `pre_time_sec` | 0.10 | 擊球前取樣 |
| `post_time_sec` | 0.10 | 擊球後取樣 |
| `rms_frame_sec` | 0.02 | RMS 幀長 |
| `rms_hop_sec` | 0.01 | RMS hop |
| `min_dist_sec` | 0.35 | 最小擊球間距 |

### 輸出參數

| 參數 | 默認 | 說明 |
|------|------|------|
| `save_segment_audio` | True | 保存擊球段音訊 |
| `output_raw_csv` | True | 輸出原始特徵 CSV |

---

## 🎛️ 調優場景

### 場景 1：高敏感檢測（容易誤檢）
```python
config = AudioAnalysisConfig(
    video_path="video.mp4",
    output_dir="output",
    peak_rel_strength=0.6,  # 降低
    mad_k=3.0,              # 降低
)
```

### 場景 2：保守檢測（容易漏檢）
```python
config = AudioAnalysisConfig(
    video_path="video.mp4",
    output_dir="output",
    peak_rel_strength=0.95, # 提高
    mad_k=5.0,              # 提高
)
```

### 場景 3：不同目標時間
```python
config = AudioAnalysisConfig(
    video_path="video.mp4",
    output_dir="output",
    target_hit_sec=2.5,     # 改為 2.5 秒
    target_tol_sec=0.3,     # ±0.3 秒容差
)
```

### 場景 4：不保存音訊段（加速）
```python
config = AudioAnalysisConfig(
    video_path="video.mp4",
    output_dir="output",
    save_segment_audio=False,  # 跳過保存
)
```

---

## 📊 輸出文件結構

```
output_dir/
├── swing_raw_summary.csv              # 原始特徵
├── swing_denoised_summary.csv         # 去噪特徵（主要使用）
├── swing_audio.wav                    # 提取的音訊
└── segments_swing/
    ├── hit_001.wav                    # 擊球 1 原始音訊
    ├── hit_001_den.wav                # 擊球 1 去噪音訊
    ├── hit_001_bg.wav                 # 擊球 1 背景參考
    ├── hit_002.wav
    ├── hit_002_den.wav
    ├── hit_002_bg.wav
    └── ...
```

---

## 📈 CSV 欄位說明

### 元數據欄
| 欄位 | 說明 |
|------|------|
| `title` | 視頻名稱 |
| `idx` | 擊球編號 |
| `start_time` | 擊球段開始時間（秒） |
| `end_time` | 擊球段結束時間（秒） |
| `peak_time` | 檢測到的峰值時間（秒） |
| `audio_file` | 擊球段檔案名 |
| `denoised_file` | 去噪檔案名 |
| `bg_file` | 背景參考檔案名 |

### 音量特徵
| 欄位 | 說明 |
|------|------|
| `peak_dbfs` | 峰值分貝 |
| `rms_dbfs` | RMS 分貝 |
| `max_amp` | 最大振幅 |
| `rms` | RMS 值 |

### 頻譜特徵
| 欄位 | 說明 |
|------|------|
| `spectral_centroid` | 頻譜重心（Hz） |
| `sharpness_hfxloud` | 尖銳度 |
| `zcr` | 過零率 |

### 頻帶特徵（8 個 1kHz 寬的頻帶）
| 欄位範例 | 說明 |
|------|------|
| `band_0k_1k_peak_freq` | 0-1kHz 頻帶的峰值頻率 |
| `band_0k_1k_peak_amp` | 0-1kHz 頻帶的峰值幅度 |
| ... | ... |
| `band_7k_8k_peak_freq` | 7-8kHz 頻帶的峰值頻率 |
| `band_7k_8k_peak_amp` | 7-8kHz 頻帶的峰值幅度 |

### MFCC 特徵（13 個）
| 欄位 | 說明 |
|------|------|
| `mfcc1` - `mfcc13` | 梅爾頻率倒譜係數 |

---

## ❌ 常見問題

### Q: 如何處理多個視頻？
A: 逐個調用，每次傳一個 video_path：
```python
video_list = ["video1.mp4", "video2.mp4", "video3.mp4"]
for video_file in video_list:
    config = AudioAnalysisConfig(
        video_path=video_file,
        output_dir=f"output_{video_file.stem}"
    )
    result = run_audio_analysis(config)
```

### Q: 如何改變採樣率？
A: 修改 `extract_audio_from_video()` 呼叫中的 `sr` 參數：
```python
# 在 process_audio_analysis() 中修改
extract_audio_from_video(video_path, audio_path, sr=44100)  # 改為 44.1kHz
```

### Q: 如何跳過去噪？
A: 目前沒有跳過選項，但可以設置 `ss_floor` 為 0 以禁用去噪：
```python
config = AudioAnalysisConfig(
    video_path="video.mp4",
    output_dir="output",
    ss_floor=0.0  # 禁用去噪下限
)
```

### Q: 如何調試為什麼沒有檢測到擊球？
A: 檢查返回狀態碼和調整參數：
```python
result = run_audio_analysis(config)

if result['status'] == 'no_peaks':
    print("未檢測到任何峰值，試試降低 peak_rel_strength")
elif result['status'] == 'peak_out_of_range':
    print("峰值超出允許時間範圍，調整 target_hit_sec 或 target_tol_sec")
```

---

## 🔧 與 main.py 集成

### 在 main_scripts/main.py 中使用

```python
from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis

def main():
    video_file = "golf_video.mp4"
    output_dir = "analysis_output"
    
    # 步驟 3：Audio Analysis
    print("\n[步驟 3] 音頻分析...")
    
    config = AudioAnalysisConfig(
        video_path=video_file,
        output_dir=output_dir,
        loudness_mode="dbfs"
    )
    
    result = run_audio_analysis(config)
    
    if result['status'] == 'success':
        print(f"✅ 檢測到 {result['hits_detected']} 個擊球")
        csv_path = result['denoised_summary_path']
        
        # 傳遞給下一步使用
        next_step(csv_path)
    else:
        print(f"❌ 音頻分析失敗：{result['status']}")
        return False
    
    return True
```

---

## 📚 相關文件

- [functions/audio_analysis.py](functions/audio_analysis.py) - 實現代碼
- [AUDIO_ANALYSIS_QUICK_REFERENCE.md](AUDIO_ANALYSIS_QUICK_REFERENCE.md) - 快速參考
- [AUDIO_ANALYSIS_COMPLETION_SUMMARY.md](AUDIO_ANALYSIS_COMPLETION_SUMMARY.md) - 完成摘要
- [AUDIO_ANALYSIS_SINGLE_VIDEO_REFACTOR.md](AUDIO_ANALYSIS_SINGLE_VIDEO_REFACTOR.md) - 重構詳情
- [AUDIO_ANALYSIS_CHANGES_CHECKLIST.md](AUDIO_ANALYSIS_CHANGES_CHECKLIST.md) - 改動檢查清單

---

## 🆘 技術支持

如有問題：
1. 檢查 [AUDIO_ANALYSIS_CHANGES_CHECKLIST.md](AUDIO_ANALYSIS_CHANGES_CHECKLIST.md) 的驗證清單
2. 查看函數源代碼中的文檔字符串
3. 執行測試代碼確認配置有效

---

**最後更新：** 2024年
**版本：** 1.0 - 單一影片處理模式
**狀態：** ✅ 生產就緒
