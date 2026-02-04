# Audio Analysis - 單一影片處理重構報告

## 📋 改動摘要

成功將 `audio_analysis.py` 從**批處理模式**轉換為**單一影片處理模式**。

---

## 🔄 核心改動

### 1. 配置類變更（AudioAnalysisConfig）

**刪除：**
- `batch_dir: str` - 批處理目錄

**新增：**
- `video_path: str` - 單一影片路徑（必需）

**驗證邏輯：**
```python
def __post_init__(self):
    if not self.video_path:
        raise ValueError("video_path 不能為空")
    if not Path(self.video_path).exists():
        raise FileNotFoundError(f"影片不存在：{self.video_path}")
```

---

### 2. process_audio_analysis() 重構

**前：批處理循環**
```python
mp4_list = sorted(glob.glob(os.path.join(config.batch_dir, "*.mp4")))
if not mp4_list:
    raise FileNotFoundError(...)
for video_path in _get_tqdm_wrapper(mp4_list, "處理視頻", len(mp4_list)):
    # 處理每個視頻
```

**後：單一影片處理**
```python
video_path = config.video_path
video_name = Path(video_path).stem
# 直接處理單一影片
```

**改動詳情：**
- ❌ 移除 `glob.glob()` 調用
- ❌ 移除外層 `for` 循環
- ✅ 直接使用 `config.video_path`
- ✅ 保留所有內部逻辑（峰值檢測、特徵提取、去噪）

---

### 3. 輸出結構簡化

**前：**
```
output_dir/
├── raw_summary.csv              # 多個視頻的合併摘要
├── denoised_summary.csv
├── video_1_audio.wav
├── segments_video_1/
├── video_2_audio.wav
├── segments_video_2/
└── ...
```

**後：**
```
output_dir/
├── {video_name}_raw_summary.csv              # 單一視頻摘要
├── {video_name}_denoised_summary.csv
├── {video_name}_audio.wav
└── segments_{video_name}/
    ├── hit_001.wav
    ├── hit_001_den.wav
    ├── hit_001_bg.wav
    └── ...
```

---

### 4. 返回值結構

**前：**
```python
{
    'status': 'success',
    'videos_processed': 5,        # 批次統計
    'hits_detected': 8,
    'raw_summary_path': '...',
    'denoised_summary_path': '...',
    'elapsed_time': 120.45
}
```

**後：**
```python
{
    'status': 'success',
    'video': 'golf_swing',         # 單一視頻名稱
    'hits_detected': 2,            # 該視頻的擊球數
    'raw_summary_path': '...',
    'denoised_summary_path': '...',
    'segments_dir': '...',
    'elapsed_time': 25.30
}
```

**狀態代碼：**
- `'success'` - 成功檢測到擊球
- `'no_peaks'` - 未檢測到任何峰值
- `'peak_out_of_range'` - 最近峰值超出允許誤差範圍

---

## 📝 函數簽名變更

### process_audio_analysis()
```python
# 簽名保持不變 - 仍接受 AudioAnalysisConfig
def process_audio_analysis(config: AudioAnalysisConfig) -> Dict[str, Any]:
    """完整的音頻分析工作流（單一影片）"""
```

### run_audio_analysis()
```python
# 簽名保持不變 - 仍是公開入口
def run_audio_analysis(config: Optional[AudioAnalysisConfig] = None) -> Dict[str, Any]:
    """Audio Analysis 的命令行和程序入口（單一影片處理）"""
```

---

## 🔧 內部函數 - 無變更

以下函數保持原樣，無需修改：

- `extract_audio_from_video()` - 音訊提取
- `compute_frame_rms()` - RMS 計算
- `pick_background_mask()` - 背景檢測
- `estimate_noise_spectrum()` - 噪聲估計
- `spectral_subtraction()` - 頻譜減法
- `dynamic_peak_detection()` - 峰值檢測
- `filter_top_peaks_by_strength()` - 峰值篩選
- `compute_audio_features()` - 特徵提取
- `normalize_for_saving()` - 音訊歸一化

---

## 📊 工作流對比

### 批處理工作流（舊）
```
main.py
  ↓
run_audio_analysis(config)
  ↓
process_audio_analysis(config)
  ↓
for video in glob(batch_dir/*.mp4):
  - 提取音訊
  - 檢測峰值
  - 估計噪聲
  - 提取特徵
  - 生成 CSV (每個視頻一行)
  ↓
合併所有行到 raw_summary.csv + denoised_summary.csv
```

### 單一影片工作流（新）
```
main.py
  ↓
run_audio_analysis(config)
  ↓
process_audio_analysis(config)
  ↓
video_path = config.video_path
  - 提取音訊
  - 檢測峰值
  - 估計噪聲
  - 提取特徵（每個擊球段一行）
  ↓
生成 {video_name}_denoised_summary.csv
```

---

## 💾 配置示例

### 舊（批處理）
```python
config = AudioAnalysisConfig(
    batch_dir="videos/batch_001",
    output_dir="output/analysis_001",
    loudness_mode="dbfs",
    save_segment_audio=True
)
```

### 新（單一影片）
```python
config = AudioAnalysisConfig(
    video_path="videos/golf_swing_001.mp4",
    output_dir="output/swing_001",
    loudness_mode="dbfs",
    save_segment_audio=True
)
```

---

## ✅ 驗證清單

- [x] 配置類已更新（batch_dir → video_path）
- [x] __post_init__ 驗證已更新
- [x] process_audio_analysis() 已重構（移除 glob 循環）
- [x] 返回值結構已簡化
- [x] 輸出文件名已更新
- [x] run_audio_analysis() 文檔已更新
- [x] 主函數 __main__ 已更新
- [x] AUDIO_ANALYSIS_QUICK_REFERENCE.md 已更新
- [x] AUDIO_ANALYSIS_COMPLETION_SUMMARY.md 已更新
- [x] 配置驗證測試通過 ✅

---

## 🚀 測試方法

```python
from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis
import tempfile
import os

# 創建臨時視頻文件進行測試
with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f:
    temp_video = f.name
    f.write(b'dummy video content')

try:
    config = AudioAnalysisConfig(
        video_path=temp_video,
        output_dir='output'
    )
    print("✅ Configuration created successfully")
    print(f"   video_path: {config.video_path}")
    print(f"   output_dir: {config.output_dir}")
finally:
    os.unlink(temp_video)
```

**預期結果：**
```
✅ Configuration created successfully
   video_path: C:\Users\...\tmp123.mp4
   output_dir: output
```

---

## 📚 相關文檔

- [functions/audio_analysis.py](functions/audio_analysis.py) - 實現代碼
- [AUDIO_ANALYSIS_QUICK_REFERENCE.md](AUDIO_ANALYSIS_QUICK_REFERENCE.md) - 快速參考
- [AUDIO_ANALYSIS_COMPLETION_SUMMARY.md](AUDIO_ANALYSIS_COMPLETION_SUMMARY.md) - 完成摘要

---

## 🔗 整合點

### 與 main.py 的集成

```python
# 在 main_scripts/main.py 中調用
from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis

# 步驟 3：Audio Analysis
config = AudioAnalysisConfig(
    video_path=video_path,          # 從上一步獲得
    output_dir=output_dir,          # 輸出目錄
    loudness_mode="dbfs"
)
audio_result = run_audio_analysis(config)

if audio_result['status'] == 'success':
    print(f"✅ 檢測到 {audio_result['hits_detected']} 個擊球")
    csv_path = audio_result['denoised_summary_path']
```

---

## 📈 後續工作

1. **測試** - 使用實際視頻文件進行集成測試
2. **集成** - 更新 main.py 以使用新 API
3. **其他模塊** - 重構 audio_scoring、openpose、ball_tracking

---

**最後更新：** 2024
**狀態：** ✅ 完成
