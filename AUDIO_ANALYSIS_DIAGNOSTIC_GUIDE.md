# 🔧 音频分析诊断与快速修复方案

## 当前状态

**❌ 问题确认**：
- PCM 文件存在：✅ `/data/data/com.example.golf_score_app/app_flutter/golf_recordings/1778637922771/audio.pcm` (16MB)
- CSV 文件生成：❌ 未发现 `audio_features.csv`
- TXT 文件生成：❌ 未发现 `audio_analysis.txt`

**推断**：音频分析过程未正确完成或生成文件

---

## 🚀 快速诊断步骤

### 1️⃣ 启用详细日志监听

在 Terminal 中运行：

```bash
# 清除旧日志
adb logcat -c

# 监听 AudioEngine 和完整分析的日志
adb logcat | grep -E "\[AudioExport\]|\[AudioEngine\]|\[完整分析\]"
```

### 2️⃣ 在应用中执行分析

1. 打开应用（已启动）
2. 导航到 **录制历史** 页面
3. 点击 **2026-05-13 11:04** 的记录
4. 点击菜单 (⋮) → **"完整分析"**
5. 等待 Progress Bar 完成 (应该看到 "🎵 Pro/Good/Bad" 标签出现)

### 3️⃣ 查看实时日志

监听日志应该显示：

```
I/flutter (PID): [完整分析] 開始音頻分析...
I/flutter (PID): [AudioExport] 🎵 analyzeFromPcm 開始
I/flutter (PID): [AudioExport] PCM 樣本: 705600, 採樣率: 44100, sessionDir: ...
I/flutter (PID): [AudioEngine] 🔍 开始峰值检测...
I/flutter (PID): [AudioEngine] ✅ 峰值检测完成，共 X 个
I/flutter (PID): [AudioEngine] 🎵 开始特徵提取...
I/flutter (PID): [AudioEngine] ✅ 特徵提取完成，共 X 个
I/flutter (PID): [AudioEngine] 🤖 开始分类评分...
I/flutter (PID): [AudioEngine] ✅ 分类完成: pro
I/flutter (PID): [AudioEngine] 📝 开始导出 CSV...
I/flutter (PID): [AudioEngine] ✅ CSV 已保存: ...
I/flutter (PID): [AudioEngine] 📝 开始导出 TXT...
I/flutter (PID): [AudioEngine] ✅ TXT 已保存: ...
I/flutter (PID): [AudioEngine] 分析完成，耗时 XXXms
```

---

## 🐛 可能的问题与解决方案

### ❌ 问题 1: PCM 转换失败

**症状日志**：
```
[完整分析] ❌ PCM 樣本為空
```

**原因**：PCM 字节转换失败

**解决**：
```dart
// RecordingHistoryPage 中的诊断代码
final pcmFile = File(p.join(sessionDir, 'audio.pcm'));
final bytes = await pcmFile.readAsBytes();
print('[诊断] PCM 字节数: ${bytes.length}');
print('[诊断] 字节数 % 4 = ${bytes.length % 4}'); // 应该是 0

// 尝试转换
try {
  final byteData = bytes.buffer.asByteData();
  final samples = List<double>.generate(
    bytes.length ~/ 4,
    (i) => byteData.getFloat32(i * 4, Endian.little),
  );
  print('[诊断] 成功转换，样本数: ${samples.length}');
  print('[诊断] 第一个样本: ${samples.first}');
  print('[诊断] 最后一个样本: ${samples.last}');
} catch (e) {
  print('[诊断] ❌ 转换失败: $e');
}
```

---

### ❌ 问题 2: 分析过程中无峰值检测

**症状日志**：
```
[AudioEngine] 检测到 0 个峰值
[AudioEngine] 未检测到击球
```

**原因**：
- PCM 数据全是 0（无效音频）
- RMS + MAD 阈值过高
- PCM 字节顺序 (Endianness) 错误

**解决**：检查 PCM 数据有效性

```bash
# 导出 PCM 文件并分析
adb shell run-as com.example.golf_score_app cat app_flutter/golf_recordings/1778637922771/audio.pcm | head -c 1024 | hexdump -C | head -20
```

如果全是 `00 00 00 00`，则 PCM 数据无效。

---

### ❌ 问题 3: 文件写入权限问题

**症状日志**：
```
[AudioEngine] CSV 导出失败: Permission denied
[AudioEngine] TXT 导出失败: Permission denied
```

**原因**：sessionDir 无写入权限

**解决**：
```bash
# 检查权限
adb shell run-as com.example.golf_score_app ls -la app_flutter/golf_recordings/1778637922771/
# 应该显示 drwx------ (700) 权限

# 如果不对，手动创建目录
adb shell run-as com.example.golf_score_app mkdir -p app_flutter/golf_recordings/1778637922771/
```

---

### ❌ 问题 4: AudioAnalysisService.scoreSummary 失败

**症状日志**：
```
[AudioEngine] 分类失败，使用默认值
```

**原因**：
- 分布模型加载失败
- 特徵值无效（NaN/Infinity）

**解决**：检查 `assets/audio/audio_class_stats.json`

```bash
# 检查资源是否存在
adb shell run-as com.example.golf_score_app ls -la app_flutter/assets/audio/
```

---

## 📋 完整诊断清单

使用此清单逐项检查：

- [ ] PCM 文件存在且大小 > 1MB
- [ ] PCM 字节数能被 4 整除 (bytes.length % 4 == 0)
- [ ] PCM 转换后样本数 = 字节数 / 4
- [ ] 样本数 > 44100 (至少 1 秒)
- [ ] 样本值范围在 [-1.0, 1.0] 之间
- [ ] 至少检测到 1 个峰值
- [ ] 至少提取到 1 个特徵
- [ ] 分类结果非 null
- [ ] sessionDir 有写入权限
- [ ] 生成的 CSV 和 TXT 文件可读

---

## 🔍 收集完整诊断信息

运行此脚本收集所有诊断数据：

```bash
# 1. 导出所有音频分析相关的日志
adb logcat -d > flutter_logs.txt

# 2. 导出应用文件结构
adb shell run-as com.example.golf_score_app find app_flutter/golf_recordings/1778637922771/ -type f > files_structure.txt

# 3. 检查文件大小和时间戳
adb shell run-as com.example.golf_score_app ls -lh app_flutter/golf_recordings/1778637922771/ > file_details.txt

# 查看结果
type flutter_logs.txt files_structure.txt file_details.txt
```

---

## ⚡ 下一步行动

1. **立即执行**：在应用上点击"完整分析"，同时监听日志
2. **收集日志**：运行诊断脚本收集输出
3. **分析日志**：查看是否有 `[AudioEngine]` 或 `[AudioExport]` 错误消息
4. **报告结果**：共享日志内容，以便进一步诊断

---

## 📞 快速参考

| 命令 | 目的 |
|------|------|
| `adb logcat \| grep -E "\[AudioEngine\]\|\[AudioExport\]"` | 过滤音频分析日志 |
| `adb shell run-as ... ls -la app_flutter/golf_recordings/` | 查看录制目录 |
| `adb shell run-as ... find . -name "audio_*.csv"` | 查找 CSV 文件 |
| `adb shell run-as ... cat app_flutter/golf_recordings/.../audio_analysis.txt` | 查看分析报告 |

