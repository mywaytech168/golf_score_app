# 🔊 改用 WAV 格式代替 PCM 的完整分析

## 📊 影响范围分析

### 🎯 需要改动的 6 个核心位置

```
1. audio_extraction_service.dart
   └─ 生成 audio.wav (不是 audio.pcm)
   
2. video_analysis_service.dart  
   └─ 生成 audio.wav (不是 audio.pcm)
   
3. recording_history_page.dart (完整分析)
   ├─ 读取 audio.wav
   ├─ 解析 WAV 得到 PCM 样本
   └─ 调用 analyzeFromPcm
   
4. recording_history_page.dart (偵測擊球)
   ├─ 读取 audio.wav
   ├─ 解析 WAV 得到 PCM 样本
   └─ 调用 SwingImpactDetector
   
5. clip_pipeline_service.dart
   ├─ 读取 audio.wav (音频切片源)
   └─ 生成 audio.wav (切片后)
   
6. audio_export_service.dart
   └─ 可能需要调整 API（接收 WAV 路径而不是 PCM 样本）
```

---

## 🔄 改动详细分析

### 改动 1: audio_extraction_service.dart

**当前**:
```dart
static Future<int> extractAudioFromVideo({
  required String videoPath,
  required String outputPcmPath,    // ← audio.pcm
  ...
}) async {
  final samplesExtracted = await _convertWavToPcm(
    wavPath: wavPath,
    outputPcmPath: outputPcmPath,   // ← 保存为 PCM
    ...
  );
  return samplesExtracted;
}

static Future<int> _convertWavToPcm({
  required String wavPath,
  required String outputPcmPath,    // ← audio.pcm
  ...
}) async {
  // 转换 WAV → PCM Float32
  await File(outputPcmPath).writeAsBytes(...);  // ← 保存为 PCM
}
```

**改为**:
```dart
static Future<int> extractAudioFromVideo({
  required String videoPath,
  required String outputWavPath,    // ← 改为 audio.wav
  ...
}) async {
  // 直接保存 WAV，不转换
  final samplesCount = await _copyWavFile(
    wavPath: wavPath,
    outputWavPath: outputWavPath,   // ← 保存为 WAV
    ...
  );
  return samplesCount;
}

static Future<int> _copyWavFile({
  required String wavPath,
  required String outputWavPath,    // ← audio.wav
  ...
}) async {
  // 只复制 WAV 文件（无转换）
  await File(wavPath).copy(outputWavPath);
  
  // 计算样本数
  final wavBytes = await File(outputWavPath).readAsBytes();
  final sampleCount = (wavBytes.length - 44) ~/ 2;
  
  return sampleCount;
}
```

**变化**:
- ✅ 不再转换 WAV → PCM
- ✅ 直接保存 WAV 文件（保留原始音频和元数据）
- ✅ 文件名: `audio.wav`
- ✅ 简化代码逻辑
- ❌ 文件大小增加 (WAV 头 44 字节)

---

### 改动 2: video_analysis_service.dart

**当前**:
```dart
Future<bool> _extractAudio({
  required String videoPath,
  required String audioPath,         // ← audio.pcm
}) async {
  final wavBytes = await wavFile.readAsBytes();
  
  // 转换 int16 → float32
  final pcmData = wavBytes.sublist(44);
  ...
  await File(audioPath).writeAsBytes(dst.buffer.asUint8List());
}
```

**改为**:
```dart
Future<bool> _extractAudio({
  required String videoPath,
  required String audioPath,         // ← audio.wav
}) async {
  final result = await _audioChannel.invokeMethod<Map>('extractAudio', {...});
  final wavPath = result['path'] as String?;
  
  // 直接复制 WAV 文件（不转换）
  final wavFile = File(wavPath);
  await wavFile.copy(audioPath);      // ← 直接复制，保存为 audio.wav
  try { await wavFile.delete(); } catch (_) {}
  
  return true;
}
```

**变化**:
- ✅ 移除 PCM 转换逻辑
- ✅ 直接复制 WAV 文件
- ✅ 代码更简洁
- ❌ 文件大小更大

---

### 改动 3: recording_history_page.dart (完整分析)

**当前**:
```dart
final pcmFile = File(p.join(sessionDir, 'audio.pcm'));
debugPrint('[完整分析] PCM 檔案路徑: ${pcmFile.path}');

AudioAnalysisResult? audioResult;
var pcmExists = await pcmFile.exists();

if (!pcmExists) {
  // 提取音频
  final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
    videoPath: clipPath,
    outputPcmPath: pcmFile.path,  // ← audio.pcm
    ...
  );
}

if (pcmExists) {
  final bytes = await pcmFile.readAsBytes();
  final byteData = bytes.buffer.asByteData();
  final pcmSamples = List<double>.generate(
    bytes.length ~/ 4,
    (i) => byteData.getFloat32(i * 4, Endian.little),
  );
  
  // 使用 PCM 样本
  audioResult = await AudioExportService.analyzeFromPcm(
    pcmSamples: pcmSamples,
    ...
  );
}
```

**改为**:
```dart
final wavFile = File(p.join(sessionDir, 'audio.wav'));
debugPrint('[完整分析] WAV 文件路径: ${wavFile.path}');

AudioAnalysisResult? audioResult;
var wavExists = await wavFile.exists();

if (!wavExists) {
  // 提取音频
  final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
    videoPath: clipPath,
    outputWavPath: wavFile.path,  // ← audio.wav
    ...
  );
}

if (wavExists) {
  // 🔧 读取 WAV 并解析为 PCM 样本
  final bytes = await wavFile.readAsBytes();
  
  // 解析 WAV 头
  final audioFormat = bytes[8] | (bytes[9] << 8);
  final sampleRate = bytes[24] | (bytes[25] << 8) | 
                     (bytes[26] << 16) | (bytes[27] << 24);
  
  // 查找 data chunk
  int dataStart = 44;
  for (int i = 36; i < bytes.length - 8; i++) {
    if (bytes[i] == 100 && bytes[i + 1] == 97 &&
        bytes[i + 2] == 116 && bytes[i + 3] == 97) {
      dataStart = i + 8;
      break;
    }
  }
  
  // 转换 int16 → float32
  final audioDataBytes = bytes.sublist(dataStart);
  final pcmSamples = <double>[];
  
  for (int i = 0; i < audioDataBytes.length - 1; i += 2) {
    final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);
    final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
    pcmSamples.add(signedInt16 / 32768.0);
  }
  
  // 调用分析（传递 PCM 样本）
  audioResult = await AudioExportService.analyzeFromPcm(
    pcmSamples: pcmSamples,
    ...
  );
}
```

**变化**:
- ❌ 增加了读取和解析 WAV 的代码
- ✅ WAV 保存了完整的音频元数据
- ✅ 支持多种 WAV 格式（位深、采样率等）
- ⚠️ 性能: 每次读取都要解析 WAV 头

---

### 改动 4: recording_history_page.dart (偵測擊球)

**当前**:
```dart
final audioPath = p.join(sessionDir, 'audio.pcm');
List<double> audioPcm = [];

if (await pcmFile.exists()) {
  final bytes = await pcmFile.readAsBytes();
  final byteData = bytes.buffer.asByteData();
  audioPcm = List<double>.generate(
    bytes.length ~/ 4,
    (i) => byteData.getFloat32(i * 4, Endian.little),
  );
}

final hits = await SwingImpactDetector.detect(
  csvPath: csvPath,
  audioPcm: audioPcm,  // ← 传递 PCM 样本
  audioSampleRate: sampleRate,
);
```

**改为**:
```dart
final audioPath = p.join(sessionDir, 'audio.wav');
List<double> audioPcm = [];

if (await File(audioPath).exists()) {
  // 🔧 读取 WAV 并解析为 PCM 样本
  final bytes = await File(audioPath).readAsBytes();
  
  // 解析 WAV 头获得采样率
  final sampleRate = bytes[24] | (bytes[25] << 8) | 
                     (bytes[26] << 16) | (bytes[27] << 24);
  
  // 查找 data chunk
  int dataStart = 44;
  for (int i = 36; i < bytes.length - 8; i++) {
    if (bytes[i] == 100 && bytes[i + 1] == 97 &&
        bytes[i + 2] == 116 && bytes[i + 3] == 97) {
      dataStart = i + 8;
      break;
    }
  }
  
  // 转换 int16 → float32
  final audioDataBytes = bytes.sublist(dataStart);
  for (int i = 0; i < audioDataBytes.length - 1; i += 2) {
    final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);
    final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
    audioPcm.add(signedInt16 / 32768.0);
  }
}

final hits = await SwingImpactDetector.detect(
  csvPath: csvPath,
  audioPcm: audioPcm,  // ← 传递 PCM 样本
  audioSampleRate: sampleRate,
);
```

**变化**:
- ✅ 从 WAV 头直接获得采样率（无需假设）
- ❌ 增加了解析 WAV 的代码
- ✅ 更加鲁棒

---

### 改动 5: clip_pipeline_service.dart

**当前**:
```dart
// 音频切片
final dstAudioPath = p.join(sessionDir, 'audio.pcm');
await _sliceAudio(
  srcAudioPath: srcAudioPath,        // ← audio.pcm
  dstAudioPath: dstAudioPath,        // ← audio.pcm
  startSec: hit.startSec,
  endSec: hit.endSec,
);

static Future<void> _sliceAudio({
  required String srcAudioPath,      // ← audio.pcm
  required String dstAudioPath,      // ← audio.pcm
  required double startSec,
  required double endSec,
}) async {
  // 从 PCM 文件切出指定时间段
  final srcFile = File(srcAudioPath);
  final bytes = await srcFile.readAsBytes();
  
  const sampleRate = 44100;
  final startSample = (startSec * sampleRate * 4).toInt();
  final endSample = (endSec * sampleRate * 4).toInt();
  
  final sliced = bytes.sublist(
    startSample.clamp(0, bytes.length),
    endSample.clamp(0, bytes.length),
  );
  
  await File(dstAudioPath).writeAsBytes(sliced);
}
```

**改为**:
```dart
// 音频切片
final dstAudioPath = p.join(sessionDir, 'audio.wav');
await _sliceAudio(
  srcAudioPath: srcAudioPath,        // ← audio.wav
  dstAudioPath: dstAudioPath,        // ← audio.wav
  startSec: hit.startSec,
  endSec: hit.endSec,
);

static Future<void> _sliceAudio({
  required String srcAudioPath,      // ← audio.wav
  required String dstAudioPath,      // ← audio.wav
  required double startSec,
  required double endSec,
}) async {
  final srcFile = File(srcAudioPath);
  final bytes = await srcFile.readAsBytes();
  
  if (bytes.length <= 44) return;  // WAV 头至少 44 字节
  
  // 🔧 解析 WAV 头获得采样率
  final sampleRate = bytes[24] | (bytes[25] << 8) | 
                     (bytes[26] << 16) | (bytes[27] << 24);
  
  // 查找 data chunk
  int dataStart = 44;
  for (int i = 36; i < bytes.length - 8; i++) {
    if (bytes[i] == 100 && bytes[i + 1] == 97 &&
        bytes[i + 2] == 116 && bytes[i + 3] == 97) {
      dataStart = i + 8;
      break;
    }
  }
  
  // 计算切片位置（相对于 data chunk）
  final startSample = (startSec * sampleRate * 4).toInt();
  final endSample = (endSec * sampleRate * 4).toInt();
  
  final slicedData = bytes.sublist(
    (dataStart + startSample).clamp(dataStart, bytes.length),
    (dataStart + endSample).clamp(dataStart, bytes.length),
  );
  
  // 🔧 生成新的 WAV 文件（保留头信息）
  final newWavBytes = ByteData((slicedData.length + 44).toInt());
  
  // 复制 WAV 头
  for (int i = 0; i < 44; i++) {
    newWavBytes.setUint8(i, bytes[i]);
  }
  
  // 更新文件大小字段
  final fileSize = slicedData.length + 36;
  newWavBytes.setUint32(4, fileSize, Endian.little);    // file size
  newWavBytes.setUint32(40, slicedData.length, Endian.little);  // data size
  
  // 复制音频数据
  for (int i = 0; i < slicedData.length; i++) {
    newWavBytes.setUint8(44 + i, slicedData[i]);
  }
  
  await File(dstAudioPath).writeAsBytes(newWavBytes.buffer.asUint8List());
}
```

**变化**:
- ✅ 从 WAV 直接获得采样率
- ❌ 切片后需要重新生成 WAV 头
- ❌ 代码更复杂
- ✅ WAV 格式规范

---

### 改动 6: 可选 - 为 AudioExportService 增加 WAV 读取 API

**当前**:
```dart
static Future<AudioAnalysisResult?> analyzeFromPcm({
  required List<double> pcmSamples,  // ← 需要预先读取 PCM 样本
  ...
})
```

**可选改为**:
```dart
// 保留现有 API
static Future<AudioAnalysisResult?> analyzeFromPcm({
  required List<double> pcmSamples,
  ...
}) => ...

// 新增便捷 API
static Future<AudioAnalysisResult?> analyzeFromWav({
  required String wavPath,           // ← WAV 文件路径
  required String sessionDir,
  required void Function(AudioAnalysisProgress progress)? onProgress,
}) async {
  // 读取 WAV
  final bytes = await File(wavPath).readAsBytes();
  
  // 解析为 PCM 样本
  final pcmSamples = _parseWavToPcm(bytes);
  
  // 调用现有 API
  return await analyzeFromPcm(
    pcmSamples: pcmSamples,
    sessionDir: sessionDir,
    sampleRate: 44100,
    onProgress: onProgress,
  );
}

static List<double> _parseWavToPcm(Uint8List wavBytes) {
  // WAV 解析逻辑
  ...
}
```

**优点**:
- ✅ 提供统一的 WAV 读取接口
- ✅ 减少重复代码
- ✅ 无需修改现有 API

---

## 📊 改动影响总结

| 方面 | 改动前 | 改动后 | 影响 |
|------|--------|--------|------|
| **文件格式** | audio.pcm | audio.wav | ✅ 保留元数据 |
| **文件大小** | 较小 | +44 字节头 | ⚠️ 增加 ~0.0001% |
| **代码复杂度** | 低 | 中等 | ⚠️ WAV 解析逻辑 |
| **性能** | 快 (直接读取) | 中 (需要解析头) | ⚠️ 轻微下降 |
| **鲁棒性** | ❌ 硬编码采样率 | ✅ 从 WAV 头读取 | ✅ 改善 |
| **兼容性** | 无 | 支持多种 WAV 格式 | ✅ 改善 |
| **修改文件数** | - | 5-6 个 | ⚠️ 中等工作量 |

---

## 🔧 改动工作量

### 需要修改的文件

1. **audio_extraction_service.dart** (难度: ⭐ 简单)
   - 移除 PCM 转换逻辑
   - 直接保存 WAV
   - 代码减少

2. **video_analysis_service.dart** (难度: ⭐ 简单)
   - 移除 PCM 转换逻辑
   - 直接复制 WAV
   - 代码减少

3. **recording_history_page.dart** (难度: ⭐⭐ 中等)
   - 添加 WAV 解析逻辑 (完整分析)
   - 添加 WAV 解析逻辑 (偵測擊球)
   - 代码增加

4. **clip_pipeline_service.dart** (难度: ⭐⭐⭐ 较难)
   - 修改切片逻辑
   - 需要生成新的 WAV 头
   - 代码增加

5. **audio_export_service.dart** (难度: ⭐ 简单)
   - 可选：添加便捷 API
   - 或保持现状（让调用方解析）

---

## ✅ 优势

1. **数据完整性**
   - ✅ 保留完整的音频元数据
   - ✅ 支持不同的采样率、位深、声道数

2. **可播放性**
   - ✅ WAV 可以直接用播放器播放（debug 时有用）
   - ❌ PCM 需要特殊工具

3. **鲁棒性**
   - ✅ 自动适应不同格式
   - ✅ 不需要硬编码采样率

4. **兼容性**
   - ✅ WAV 是更通用的格式
   - ✅ 更容易与其他工具集成

---

## ⚠️ 劣势

1. **文件大小**
   - ❌ 增加 44 字节头信息
   - ❌ 影响存储（对项目无关紧要）

2. **代码复杂性**
   - ❌ 增加 WAV 解析逻辑
   - ❌ 每次读取需要解析头

3. **性能**
   - ⚠️ 轻微的性能下降（可忽略）
   - ❌ 多处重复的 WAV 解析代码

4. **维护成本**
   - ⚠️ 需要在多处维护 WAV 解析逻辑

---

## 🎯 建议

### 如果要改用 WAV

**推荐方案**:
1. **立即改动** (1-2 小时)
   - audio_extraction_service.dart: 简化为直接保存 WAV
   - video_analysis_service.dart: 简化为直接复制 WAV

2. **分阶段改动** (2-3 小时)
   - recording_history_page.dart: 添加 WAV 解析
   - clip_pipeline_service.dart: 修改切片逻辑

3. **可选优化** (1 小时)
   - 为 AudioExportService 添加便捷 API
   - 集中 WAV 解析逻辑到一个工具类

**总工作量**: 4-6 小时

### 建议的优先级

1. ✅ **高**: 简化 audio_extraction_service 和 video_analysis_service
2. ✅ **中**: 更新读取逻辑 (recording_history_page)
3. ⚠️ **可选**: 更新切片逻辑 (clip_pipeline_service)
4. ⚠️ **可选**: 添加便捷 API (audio_export_service)

