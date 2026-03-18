# Split Hits 函數庫 - 快速參考

## 🚀 最快開始

```python
from functions.split_hits import run_split_hits

# 執行完整流程
result = run_split_hits()
print(f"✅ 檢測到 {result['hit_count']} 次擊球")
```

## 📝 常用代碼片段

### 1. 自定義檢測敏感度
```python
from functions.split_hits import SplitHitsConfig, run_split_hits

config = SplitHitsConfig(
    thresh_acc_g=15.0,      # 降低阈值（更敏感）
    smooth_win_sec=0.03,    # 減少平滑
)
result = run_split_hits(config)
```

### 2. 只進行檢測（無切分）
```python
from functions.split_hits import (
    SplitHitsConfig,
    load_codi_raw_v1_csv,
    normalize_time,
    detect_swings_from_df,
)

config = SplitHitsConfig()
df = normalize_time(load_codi_raw_v1_csv(config.csv_codi2))
hit_times, hit_heights = detect_swings_from_df(df)
```

### 3. 繪製加速度圖
```python
from functions.split_hits import plot_acc_mag
from pathlib import Path

plot_acc_mag(
    df,
    title="Acceleration",
    save_path=Path("output.png"),
    hit_times=hit_times,
)
```

### 4. 手動切分段落
```python
from functions.split_hits import cut_csv_segment

segment = cut_csv_segment(df, start_t=2.0, end_t=4.0, t_hit=3.0)
segment.to_csv("segment.csv")
```

### 5. 批量處理
```python
for ts in ["20260101", "20260102", "20260103"]:
    config = SplitHitsConfig(rec_ts=ts)
    result = run_split_hits(config)
```

## 🎯 配置參數速查表

| 參數 | 默認值 | 用途 |
|------|-------|------|
| `rec_ts` | "20251231100806" | 錄製時間戳 |
| `thresh_acc_g` | 20.0 | 加速度閾值（g） |
| `smooth_win_sec` | 0.05 | 平滑窗口（秒） |
| `min_swing_interval` | 1.0 | 最小擊球間距（秒） |
| `window_sec_before` | 3.0 | 擊球前窗口（秒） |
| `window_sec_after` | 3.0 | 擊球后窗口（秒） |
| `plot_acc_mag` | True | 繪製圖表 |
| `plot_save` | True | 保存圖表 |
| `ffmpeg_crf` | "18" | 視頻品質 |

## 🔧 解決常見問題

### 問題：檢測不到擊球
```python
# 解決：降低閾值
config = SplitHitsConfig(thresh_acc_g=10.0)
```

### 問題：檢測太多誤報
```python
# 解決：提高閾值
config = SplitHitsConfig(thresh_acc_g=30.0)
```

### 問題：缺少依賴
```python
# 自動跳過不可用的功能，仍可進行其他操作
# moviepy 不可用時，跳過視頻時長檢測
# matplotlib 不可用時，跳過圖表生成
```

## 📊 返回值格式

```python
result = run_split_hits(config)

# 返回字典：
{
    'success': True,                        # 是否成功
    'hit_count': 12,                        # 檢測到的擊球數
    'output_dir': '/path/to/output',        # 輸出目錄
    'summary': DataFrame(...)               # 摘要 DataFrame（可選）
}
```

## 🔗 核心函數列表

| 函數 | 功能 |
|------|------|
| `load_codi_raw_v1_csv(path)` | 加載 CSV |
| `normalize_time(df)` | 標準化時間 |
| `acc_magnitude(df)` | 計算加速度幅度 |
| `detect_swings_from_df(df, ...)` | 檢測擊球 |
| `plot_acc_mag(df, ...)` | 繪製圖表 |
| `cut_csv_segment(df, ...)` | 切分 CSV |
| `cut_video_ffmpeg(src, dst, ...)` | 切分視頻 |
| `process_split_hits(config)` | 完整流程 |
| `run_split_hits(config)` | 命令行入口 |

## 📚 完整文檔

| 文檔 | 內容 |
|------|------|
| [SPLIT_HITS_GUIDE.md](SPLIT_HITS_GUIDE.md) | 詳細 API 文檔 |
| [SPLIT_HITS_EXAMPLES.py](SPLIT_HITS_EXAMPLES.py) | 10 個使用示例 |
| [SPLIT_HITS_REFACTORING_REPORT.md](SPLIT_HITS_REFACTORING_REPORT.md) | 完整報告 |

## 💡 提示

- 📝 所有函數都有完整的文檔字符串（docstring）
- 🔍 使用 `help(function_name)` 查看詳細幫助
- ⚙️ 所有參數都可通過 `SplitHitsConfig` 配置
- 🚀 支持在 Python REPL 中交互式使用
- 📊 輸出包含完整的 CSV 和視頻段落

---

**快速幫助**：`python -c "from functions.split_hits import run_split_hits; help(run_split_hits)"`
