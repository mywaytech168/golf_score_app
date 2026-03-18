# Split Hits 函数库 - 使用指南

## 📖 概述

`split_hits.py` 是一个完整的高尔夫擊球检测和视频切分函数库，提供灵活的 API 用于：
- 加载和预处理 IMU 数据
- 检测擊球时间点
- 切分视频和 CSV 数据
- 可视化加速度数据

## 🎯 核心组件

### 1. 配置类：`SplitHitsConfig`

用于管理所有配置参数。

#### 基本用法
```python
from functions.split_hits import SplitHitsConfig, run_split_hits

# 使用默认配置
config = SplitHitsConfig()

# 或自定义配置
config = SplitHitsConfig(
    rec_ts="20260102150000",
    base_dir=r"Z:\Data\golf\20260126",
    thresh_acc_g=25.0,  # 提高阈值
    smooth_win_sec=0.1,   # 增加平滑窗口
)

# 执行处理
result = run_split_hits(config)
```

#### 配置参数说明

| 参数 | 默认值 | 说明 |
|------|-------|------|
| `rec_ts` | "20251231100806" | 录制时间戳 |
| `base_dir` | r"Z:\Data\golf\20260126" | 数据基础目录 |
| `out_dir_name` | "cut" | 输出目录名称 |
| `detect_from` | "Codi2" | 检测源（Codi1 或 Codi2） |
| `window_sec_before` | 3.0 | 擊球前窗口（秒） |
| `window_sec_after` | 3.0 | 擊球后窗口（秒） |
| `smooth_win_sec` | 0.05 | 平滑窗口（秒） |
| `thresh_acc_g` | 20.0 | 加速度阈值（g） |
| `min_swing_interval` | 1.0 | 最小擊球间距（秒） |
| `peak_prominence_g` | None | 峰值突出度（可选） |
| `plot_acc_mag` | True | 是否绘制加速度图 |
| `plot_save` | True | 是否保存图形 |
| `plot_show` | False | 是否显示图形 |
| `plot_dpi` | 200 | 图形 DPI |
| `ffmpeg_crf` | "18" | 视频品质（18~23） |
| `ffmpeg_preset` | "veryfast" | ffmpeg preset |
| `force_sar_1` | True | 强制 SAR=1 |

### 2. 核心函数

#### CSV 数据处理

**`load_codi_raw_v1_csv(path: Path) -> pd.DataFrame`**
- 加载 CODI RAW V1 格式的 CSV
- 自动找到正确的标题行
- 返回包含 IMU 数据的 DataFrame

```python
from pathlib import Path
from functions.split_hits import load_codi_raw_v1_csv

csv_file = Path(r"Z:\Data\golf\20260126\REC_20260126100000_RIGHT_WRIST.csv")
df = load_codi_raw_v1_csv(csv_file)
print(df.columns)  # 查看所有列
```

**`normalize_time(df: pd.DataFrame) -> pd.DataFrame`**
- 标准化时间，从 0 开始
- 添加 Time 列（相对时间）
- 返回修改后的 DataFrame

```python
df = normalize_time(df)
print(df["Time"].min(), df["Time"].max())  # 0.0 到总时长
```

#### 加速度处理

**`acc_magnitude(df: pd.DataFrame) -> np.ndarray`**
- 计算加速度幅度：sqrt(Ax² + Ay² + Az²)
- 返回 numpy 数组

```python
acc = acc_magnitude(df)
print(f"最大加速度：{acc.max():.2f} g")
```

#### 擊球检测

**`detect_swings_from_df(df, smooth_win_sec=0.05, thresh_acc_g=20.0, ...) -> Tuple[np.ndarray, np.ndarray]`**
- 检测擊球时间点
- 返回 (hit_times, hit_heights)

```python
from functions.split_hits import detect_swings_from_df

hit_times, hit_heights = detect_swings_from_df(
    df,
    smooth_win_sec=0.05,
    thresh_acc_g=20.0,
    min_swing_interval=1.0,
)

print(f"检测到 {len(hit_times)} 次擊球")
for t, h in zip(hit_times, hit_heights):
    print(f"  时间：{t:.3f}s，强度：{h:.2f}g")
```

#### 数据切分

**`cut_csv_segment(df, start_t, end_t, t_hit) -> pd.DataFrame`**
- 切分 CSV 数据
- 添加相对时间列 Time_rel

```python
segment = cut_csv_segment(df, start_t=2.0, end_t=4.0, t_hit=3.0)
```

**`cut_video_ffmpeg(src, dst, start_t, end_t, ...) -> None`**
- 使用 ffmpeg 切分视频
- 支持自定义编码参数

```python
from pathlib import Path
from functions.split_hits import cut_video_ffmpeg

src = Path(r"Z:\Data\golf\20260126\REC_20260126100000.mp4")
dst = Path(r"Z:\Data\golf\20260126\cut\hit_001.mp4")
cut_video_ffmpeg(src, dst, start_t=10.0, end_t=16.0)
```

#### 可视化

**`plot_acc_mag(df, title, save_path=None, hit_times=None, ...) -> None`**
- 绘制加速度幅度图
- 可显示擊球点标记

```python
from functions.split_hits import plot_acc_mag
from pathlib import Path

plot_acc_mag(
    df,
    title="IMU Acceleration",
    save_path=Path("acceleration.png"),
    hit_times=hit_times,
    plot_show=True,
)
```

### 3. 主处理函数

**`process_split_hits(config: SplitHitsConfig) -> Dict`**
- 执行完整的擊球检测和切分流程
- 自动处理所有步骤
- 返回详细的结果字典

```python
from functions.split_hits import process_split_hits, SplitHitsConfig

config = SplitHitsConfig(
    rec_ts="20260102150000",
    base_dir=r"Z:\Data\golf\20260126",
)

result = process_split_hits(config)

print(result)
# {
#     'success': True,
#     'hit_count': 12,
#     'output_dir': '/path/to/output',
#     'summary': DataFrame(...)
# }
```

### 4. 命令行入口

**`run_split_hits(config: Optional[SplitHitsConfig] = None) -> Dict`**
- 标准的命令行入口函数
- 使用默认或自定义配置

```python
from functions.split_hits import run_split_hits

# 使用默认配置
result = run_split_hits()

# 或提供自定义配置
config = SplitHitsConfig(thresh_acc_g=25.0)
result = run_split_hits(config)
```

## 💡 常见使用场景

### 场景1：使用默认参数
```bash
cd meshflow_stabilize_with_audio_V2
python -c "from functions.split_hits import run_split_hits; run_split_hits()"
```

### 场景2：调整检测敏感度
```python
from functions.split_hits import run_split_hits, SplitHitsConfig

# 更敏感的检测（降低阈值）
config = SplitHitsConfig(
    thresh_acc_g=15.0,           # 降低阈值
    smooth_win_sec=0.03,         # 减少平滑
    min_swing_interval=0.5,      # 减少最小间距
)
result = run_split_hits(config)
```

### 场景3：调整切分窗口
```python
# 更长的前后窗口（更多背景）
config = SplitHitsConfig(
    window_sec_before=5.0,
    window_sec_after=5.0,
)
result = run_split_hits(config)
```

### 场景4：只进行检测，不切分
```python
from functions.split_hits import (
    SplitHitsConfig,
    load_codi_raw_v1_csv,
    normalize_time,
    detect_swings_from_df,
    plot_acc_mag,
)
from pathlib import Path

config = SplitHitsConfig()
csv_path = config.csv_codi2

df = normalize_time(load_codi_raw_v1_csv(csv_path))
hit_times, hit_heights = detect_swings_from_df(df)

print(f"检测到 {len(hit_times)} 次擊球")

# 绘制图形
plot_acc_mag(df, "Acceleration Analysis", hit_times=hit_times, plot_show=True)
```

### 场景5：批量处理多个文件
```python
from functions.split_hits import SplitHitsConfig, run_split_hits

rec_timestamps = [
    "20260101100000",
    "20260102100000",
    "20260103100000",
]

for ts in rec_timestamps:
    config = SplitHitsConfig(rec_ts=ts)
    result = run_split_hits(config)
    print(f"✅ {ts}: 检测到 {result['hit_count']} 次擊球")
```

## 🔧 参数调优指南

### 调整 `thresh_acc_g`
- **问题**：检测不到擊球
  - **解决**：降低 `thresh_acc_g`（例如 15.0）
- **问题**：检测到太多误报
  - **解决**：提高 `thresh_acc_g`（例如 25.0）

### 调整 `smooth_win_sec`
- **问题**：检测波动太大
  - **解决**：增加 `smooth_win_sec`（例如 0.1）
- **问题**：检测太迟钝
  - **解决**：减少 `smooth_win_sec`（例如 0.03）

### 调整 `min_swing_interval`
- **问题**：相邻擊球被当成一个
  - **解决**：减少 `min_swing_interval`（例如 0.5）

## 📊 输出格式

### hits_summary.csv
```
hit,t_hit,start_t,end_t,peak_smooth,detect_from
hit_001,3.123,0.123,6.123,45.23,Codi2
hit_002,8.456,5.456,11.456,42.15,Codi2
...
```

### 输出目录结构
```
cut/
├── hit_001.mp4              # 视频段
├── hit_001_Codi2.csv        # IMU 数据
├── hit_002.mp4
├── hit_002_Codi2.csv
├── ...
├── IMU_Codi2_AccelMag.png   # 加速度图
└── hits_summary.csv         # 摘要
```

## 🐛 故障排查

### 找不到 ffmpeg
```
RuntimeError: 找不到 ffmpeg：请先安装并确认 ffmpeg 在 PATH
```
**解决**：安装 ffmpeg 并确保能在命令行运行 `ffmpeg -version`

### 找不到 CSV 文件
```
FileNotFoundError: 找不到 CSV：...
```
**解决**：检查 `rec_ts` 和 `base_dir` 是否正确

### 检测不到擊球
**解决**：
1. 检查 `thresh_acc_g` 是否太高
2. 检查 CSV 数据是否正确
3. 绘制加速度图查看实际数据

## 📝 高级用法

### 自定义峰值检测
```python
from functions.split_hits import detect_swings_from_df

# 使用峰值突出度参数
hit_times, hit_heights = detect_swings_from_df(
    df,
    thresh_acc_g=20.0,
    peak_prominence_g=5.0,  # 只保留突出度 > 5.0 的峰值
)
```

### 不同的 CSV 源
```python
config = SplitHitsConfig(
    detect_from="Codi1",  # 使用 Codi1 而不是 Codi2
)
```

## ✨ 特点总结

✅ **完全模块化** - 每个函数可独立使用
✅ **灵活配置** - 所有参数可自定义
✅ **详细日志** - 清晰的进度和结果显示
✅ **错误处理** - 完善的异常管理
✅ **无依赖冲突** - 使用标准的 ffmpeg 和 Python 包

## 📚 参考

- [Scipy find_peaks 文档](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.find_peaks.html)
- [FFmpeg 文档](https://ffmpeg.org/ffmpeg.html)
- [Pandas 文档](https://pandas.pydata.org/)
