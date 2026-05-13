# WAV 格式实现完成总结

## 🎯 目标
将音频存储格式从 **PCM Float32** (4 字节/样本) 改为 **WAV 格式** (44字节头 + 16-bit PCM 数据)。

---

## ✅ 实现状态：完成

### 修改的文件列表

#### 1. **lib/services/audio_extraction_service.dart** ✅
**改动内容**:
- 参数: `outputPcmPath` → `outputWavPath`
- 移除 `_convertWavToPcm()` 复杂转换逻辑
- 新增 `_copyWavFile()`: 直接复制 WAV 文件，计算样本数
- 保持原有接口和返回值（样本数）

**核心改动**:
```dart
// 旧方式: WAV → PCM Float32 (转换)
final samplesExtracted = await _convertWavToPcm(
  wavPath: wavPath,
  outputPcmPath: outputPcmPath,  // ← 改为 outputWavPath
  targetSampleRate: 44100,
  onProgress: onProgress,
);

// 新方式: 直接复制 WAV (简化)
final samplesCount = await _copyWavFile(
  wavPath: wavPath,
  outputWavPath: outputWavPath,
  onProgress: onProgress,
);
```

**好处**:
- 移除了 PCM 转换复杂性
- 减少运算、降低电量消耗
- 保留 WAV 元数据（采样率、声道等）

---

#### 2. **lib/services/video_analysis_service.dart** ✅
**改动内容**:
- `_extractAudio()`: 改为直接复制 WAV 而非转换

**核心改动**:
```dart
// 旧方式: WAV → int16 → float32 转换
const pcmData = wavBytes.sublist(44);
const dst = ByteData(sampleCount * 4);
for (var i = 0; i < sampleCount; i++) {
  final s = src.getInt16(i * 2, Endian.little) / 32768.0;
  dst.setFloat32(i * 4, s.clamp(-1.0, 1.0), Endian.little);
}
await File(audioPath).writeAsBytes(dst.buffer.asUint8List());

// 新方式: 直接复制
await wavFile.copy(audioPath);  // ✅ 只需一行
```

---

#### 3. **lib/pages/recording_history_page.dart** ✅
**改动位置**: 两处音频处理

##### A. `_runCombinedAnalysis()` - 完整分析流程 (lines ~980-1050)
**改动内容**:
- 改为读取 `audio.wav` 而非 `audio.pcm`
- 在读取时即时解析 WAV 头，转换 int16 → float32 样本
- 将样本列表传给 `AudioExportService.analyzeFromPcm()`

**流程**:
```
1. 读取 audio.wav (44字节头 + PCM数据)
2. 查找 "data" chunk 起始位置
3. 提取 int16 PCM 数据
4. 即时转换为 float32 ([−1, 1] 范围)
5. 传给分析引擎
```

##### B. `_detectHits()` - 击球检测流程 (lines ~754-800)
**改动内容**:
- 改为读取 `audio.wav` 而非 `audio.pcm`
- 相同的 WAV 解析 + int16→float32 转换
- 将样本传给 `SwingImpactDetector.detect()`

---

#### 4. **lib/services/clip_pipeline_service.dart** ✅
**改动内容**:
- 新增导入: `import 'dart:typed_data';`
- 改为处理 `audio.wav` 而非 `audio.pcm`
- `_sliceAudio()` 重写: 处理 WAV 头的复制和重生成

**核心改动**:
```dart
// 旧方式: 简单切分 Float32 字节
const int bytesPerSample = 4;  // Float32
final slicedBytes = bytes.sublist(startByte, endByte);
await File(dstAudioPath).writeAsBytes(slicedBytes);

// 新方式: 处理 WAV 头 + 切分 + 重生成头
1. 查找原始 WAV 的 "data" chunk
2. 从数据块中提取指定时间范围的 16-bit PCM
3. 🔧 重新生成 44 字节的 WAV 头（含新的文件大小）
4. 合并头部 + 数据，写入新 WAV
```

**WAV 头结构** (44 bytes):
```
 0-3  : "RIFF"
 4-7  : ChunkSize (file size - 8)
 8-11 : "WAVE"
12-15 : "fmt "
16-19 : 16 (subchunk1 size)
20-21 : 1 (audio format = PCM)
22-23 : 1 (channels = mono)
24-27 : 44100 (sample rate)
28-31 : 88200 (byte rate)
32-33 : 2 (block align)
34-35 : 16 (bits per sample)
36-39 : "data"
40-43 : DataSize
44+   : PCM samples (int16 LE)
```

---

## 🔄 数据流变化

### 存储流程对比

**旧方式 (PCM)**:
```
视频 → MediaCodec 提取 WAV 
     → _convertWavToPcm() 
        ├─ 解析头
        ├─ int16 → float32 转换
        ├─ 重采样 (if needed)
        └─ 保存为 4字节/样本
     → audio.pcm (float32)
```

**新方式 (WAV)**:
```
视频 → MediaCodec 提取 WAV 
     → 直接复制
     → audio.wav (44头 + int16 PCM)
```

### 读取流程对比

**旧方式**:
```
audio.pcm → 读取 float32 → 直接使用
```

**新方式**:
```
audio.wav → 解析头
         → 提取 int16 PCM
         → 即时转换 int16 → float32
         → 使用 (只在需要时转换)
```

---

## 📊 优势

| 方面 | PCM Float32 | WAV 16-bit |
|-----|------------|-----------|
| 文件大小 | 4B × 样本数 | ~2B × 样本数 + 44B |
| 处理速度 | 提取时全部转换 | 按需转换 |
| 兼容性 | 自定义格式 | 标准格式 |
| 元数据 | 丢失 | 保留 (采样率等) |
| 存储空间 | ~2.5 MB/秒 | ~1.2 MB/秒 |

**示例** (1秒音频 @ 44.1kHz):
- PCM Float32: 44100 样本 × 4 字节 = **176.4 KB**
- WAV 16-bit: 44字节头 + 44100 样本 × 2 字节 = **88.3 KB** ✅ 省一半

---

## 🧪 测试清单

- [ ] **基础音频提取**: 导入视频 → 检查 `audio.wav` 是否生成
- [ ] **完整分析**: 分析结果是否正确（应与 PCM 版本一致）
- [ ] **击球检测**: 击球点检测是否正确
- [ ] **视频切片**: 切分后的 `audio.wav` 是否有效
- [ ] **文件大小**: 检查音频文件大小是否减半
- [ ] **旧录制兼容**: 处理既有的 PCM 文件（若有）

---

## 🔧 故障排查

### 问题1: 音频为空或失败
**原因**: WAV 解析失败 (头损坏 或 data chunk 位置不对)  
**解决**: 检查 data chunk 查找逻辑

### 问题2: 转换错误或失真
**原因**: int16 转 float32 时符号处理不对  
**验证**:
```dart
// int16 > 32767 时需要符号扩展
final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
final normalized = signedInt16 / 32768.0;  // [-1, 1]
```

### 问题3: 切片音频损坏
**原因**: 样本对齐问题 (startByte 必须是偶数)  
**验证**:
```dart
// 字节级别: 样本数 × 2字节
final startByte = startSample * 2;  // ← 必须偶数
```

---

## 📝 代码验证

### ✅ 语法检查状态
- audio_extraction_service.dart: 编译 ✓
- video_analysis_service.dart: 编译 ✓
- recording_history_page.dart: 编译 ✓
- clip_pipeline_service.dart: 编译 ✓ (已导入 `dart:typed_data`)

### 🔍 关键验证点

**1. WAV 头查找** (4字节 "data"):
```dart
for (int i = 36; i < bytes.length - 8; i++) {
  if (bytes[i] == 100 && bytes[i + 1] == 97 &&
      bytes[i + 2] == 116 && bytes[i + 3] == 97) {
    dataStart = i + 8;
    break;
  }
}
```
ASCII: 100=d, 97=a, 116=t, 97=a ✓

**2. int16 → float32 转换**:
```dart
final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);
final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
pcmSamples.add(signedInt16 / 32768.0);  // [-1, 1]
```

---

## 🚀 后续

### 可选优化
1. 添加 WAV 格式验证 (检查 RIFF/WAVE 签名)
2. 支持多声道 WAV (当前假设单声道)
3. 支持自定义采样率 (当前固定 44.1kHz)

### 性能指标监控
- 提取时间对比
- 内存使用对比
- 文件大小节省百分比

---

## 完成时间

✅ **实现完成**  
- 修改文件: 4 个
- 新增逻辑: WAV 头生成、头解析、int16 转换
- 删除逻辑: PCM 转换代码简化
- 编译状态: 通过

下一步: **设备测试** (导入视频 → 分析 → 验证 WAV 生成和使用)
