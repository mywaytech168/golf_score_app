# 音频分析调试指南

## 1️⃣ 如何检查音频分析成功

### 成功完成的日志标志

在 Flutter 日志中查看这些关键消息：

```
[AudioEngine] 检测到 N 个峰值              ← 击球峰值检测成功
[AudioEngine] 提取特徵中... N/M            ← 特徵提取进度
[AudioEngine] CSV 已保存: ...              ← CSV 导出成功
[AudioEngine] TXT 已保存: ...              ← TXT 导出成功
[AudioEngine] 分析完成，耗时 XXXms        ← 完成标志
```

### 完整分析流程的日志

```
[完整分析] 開始視頻分析...
[Pipeline.analyze] ✅ 球軌跡疊加成功       ← 视频分析完成
[完整分析] 開始音頻分析...
[AudioEngine] 检测到 X 个峰值
[AudioEngine] CSV 已保存: ...
[AudioEngine] TXT 已保存: ...
完整分析完成 ✅
🎵 音頻：Pro                               ← 分类标签
```

---

## 2️⃣ CSV 和 TXT 文件位置

### 文件保存路径

文件保存在**录制会话目录**中：

```
📁 golf_recordings/
 └── 📁 {timestamp}_{session_id}/
      ├── video.mp4                        ← 原始视频
      ├── audio.pcm                        ← PCM 音频数据
      ├── pose_landmarks.csv               ← 骨架数据
      ├── audio_features.csv               ← ✅ 音频特徵 CSV
      ├── audio_analysis.txt               ← ✅ 音频分析报告 TXT
      ├── 📁 cut/
      │   └── hits_summary.csv
      └── 📁 output_2025_01_15_10_30_45.mp4  ← 最终输出视频
```

### 文件命名

| 文件 | 名称 | 路径 |
|------|------|------|
| **CSV** | `audio_features.csv` | `{sessionDir}/audio_features.csv` |
| **TXT** | `audio_analysis.txt` | `{sessionDir}/audio_analysis.txt` |

---

## 3️⃣ CSV 文件格式

### 表头结构

```csv
frame_index,time_sec,rms_dbfs,peak_dbfs,spectral_centroid,sharpness_hfxloud,highband_amp,band_0k_1k_peak_amp,band_1k_2k_peak_amp,...
0,0.0000,-20.5,-15.3,2500.00,0.2345,0.15,0.05,0.08,...
1,0.0200,-19.8,-14.9,2600.00,0.2456,0.16,0.06,0.09,...
2,0.0400,-21.2,-16.1,2400.00,0.2234,0.14,0.04,0.07,...

平均值,,–20.5,-15.4
```

### CSV 数据列说明

| 列名 | 单位 | 说明 |
|------|------|------|
| `frame_index` | - | 帧序号 |
| `time_sec` | 秒 | 时间戳 |
| `rms_dbfs` | dBFS | RMS 功率（均方根） |
| `peak_dbfs` | dBFS | 峰值功率 |
| `spectral_centroid` | Hz | 频谱中心频率 |
| `sharpness_hfxloud` | - | 声音清脆度 |
| `highband_amp` | - | 高频带幅度 |
| `band_*_peak_amp` | - | 各频段峰值幅度 |

---

## 4️⃣ TXT 文件格式

### 报告结构

```
======================================
  高尔夫击球音频分析报告
======================================

生成时间: 2025-01-15 10:35:42.123456
分析耗时: 342ms

[分类结果]
预测类别: pro
反馈: Pro
pro: 0.0234
good: 0.5678
bad: 0.4088

[特徵摘要]
样本数: 3
平均 RMS: -20.50 dBFS
平均 Peak: -15.40 dBFS
平均 Centroid: 2500 Hz
平均 Sharpness: 0.235

[详细特徵]
帧 0 @ 0.00s:
  RMS=-20.50dBFS, Peak=-15.40dBFS
  Centroid=2500Hz, Sharpness=0.235
  HighbandAmp=0.15
...

======================================
```

---

## 5️⃣ 调试技巧

### ✅ 验证分析成功的方法

**方法 1: 查看日志**
```
在 Android Studio / VS Code 的 Logcat 中搜索：
- 搜索关键字: "AudioEngine"
- 查找: "[AudioEngine] 分析完成"
```

**方法 2: 检查文件是否存在**
```bash
# 使用 adb 查看文件
adb shell ls -la /data/data/com.example.golf_score_app/files/golf_recordings/{date}/{session_id}/

# 查看 CSV 内容
adb shell cat /data/data/com.example.golf_score_app/files/golf_recordings/{date}/{session_id}/audio_features.csv

# 查看 TXT 内容
adb shell cat /data/data/com.example.golf_score_app/files/golf_recordings/{date}/{session_id}/audio_analysis.txt
```

**方法 3: 在 UI 中检查**
- 录制历史页面中条目显示 "🎵 Pro" 或其他标签
- `audioLabel` 字段已更新
- `goodShot` 标记已设置

### ⚠️ 常见问题

**问题: 看不到 CSV/TXT 文件**
- ✅ 检查 `sessionDir` 路径是否正确
- ✅ 检查权限（需要写入权限）
- ✅ 查看日志中是否有"导出失败"错误

**问题: 无法检测到峰值**
- ✅ PCM 文件是否存在且有效
- ✅ 音频是否包含明显的击球声音
- ✅ MAD 阈值是否过高（当前: `median + 4.0 * MAD`）

**问题: 分类结果不准确**
- ✅ 检查 `audio_class_stats.json` 是否加载成功
- ✅ 验证分布模型参数 (mu, sd) 是否正确
- ✅ 查看特徵值是否在预期范围内

---

## 6️⃣ 日志过滤

### 只显示音频分析日志

```
# Android Logcat 过滤器
AudioEngine|完整分析
```

### 收集完整的分析日志

```bash
# 导出所有日志
adb logcat | grep -E "AudioEngine|完整分析" > analysis_log.txt

# 清除旧日志并重新分析
adb logcat -c
# ... 进行分析 ...
adb logcat > fresh_log.txt
```

---

## 7️⃣ 性能指标

### 典型分析性能

| 操作 | 耗时 | 说明 |
|------|------|------|
| PCM 加载 | ~50ms | 44.1kHz, 45秒 |
| 峰值检测 | ~30ms | RMS + MAD 算法 |
| 特徵提取 | ~200ms | FFT 分析（纯 Dart） |
| 分类评分 | ~10ms | 贝叶斯分类 |
| CSV 导出 | ~20ms | 文件写入 |
| TXT 导出 | ~10ms | 文件写入 |
| **总计** | **~320ms** | 整个流程 |

### 优化建议

如果性能不理想：
- 考虑将 FFT 迁移到 C++ 原生代码（Android NDK）
- 使用异步文件 I/O
- 批量处理特徵提取

---

## 8️⃣ 测试用菜单

### 重置分析状态

在录制历史条目的菜单中：
- "🧪 測試: 重置分析狀態"
- 清除: `isAnalyzed`, `audioLabel`, `goodShot`, `audioCrispness`
- 用于快速重新测试分析流程

---

## 参考资源

- [audio_analysis_engine.dart](lib/services/audio_analysis_engine.dart) - 核心引擎
- [audio_export_service.dart](lib/services/audio_export_service.dart) - 公共 API
- [audio_export_models.dart](lib/services/audio_export_models.dart) - 数据模型
- [recording_history_page.dart](lib/pages/recording_history_page.dart) - UI 集成
