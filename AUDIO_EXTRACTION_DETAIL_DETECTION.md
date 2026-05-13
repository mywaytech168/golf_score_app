# 🔊 偵測擊球中的 PCM 音频提取详细分析

## 📊 完整调用链

```
[偵測擊球] _detectHits()
  ↓
  ├─ 检查 CSV 存在?
  │   ├─ YES → 跳过
  │   └─ NO → 执行基础分析
  │
  └─→ VideoAnalysisPipelineService.analyzeBasic()
      ↓
      └─→ VideoAnalysisService.analyze()
          ↓
          ├─ 75% 进度：_analyzePose()
          │   ├─ 使用 ML Kit 检测关键点
          │   └─ 生成 pose_landmarks.csv
          │
          ├─ 75-100% 进度：_extractAudio()
          │   ├─ 调用 audio_extractor_channel
          │   ├─ 获得 WAV 文件
          │   ├─ WAV → PCM Float32 转换
          │   └─ 保存 audio.pcm
          │
          └─ 返回 VideoAnalysisResult
              ├─ csvPath: pose_landmarks.csv
              └─ audioPath: audio.pcm
      
      ↓
      返回 BasicAnalysisResult
      
  ↓
[偵測擊球] 读取 audio.pcm
  ↓
[偵測擊球] 传递给 SwingImpactDetector.detect()
```

---

## 🔍 关键方法详解

### 1. VideoAnalysisPipelineService.analyzeBasic()

**文件**: `lib/services/video_analysis_pipeline_service.dart:16-55`

```dart
static Future<BasicAnalysisResult?> analyzeBasic({
  required String videoPath,
  required String sessionDir,
  required int durationSeconds,
  void Function(String label)? onProgress,
}) async {
  try {
    final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
    final audioPath = p.join(sessionDir, 'audio.pcm');

    // ✅ 优化：两者都存在则跳过
    if (await File(csvPath).exists() && await File(audioPath).exists()) {
      debugPrint('[VideoAnalysisPipeline] ✅ 骨架与音讯已存在，略过分析');
      onProgress?.call('使用既有分析资料...');
      return BasicAnalysisResult(
        csvPath: csvPath,
        audioPath: audioPath,
        isComplete: true,
      );
    }

    // ✅ 调用完整分析服务
    onProgress?.call('分析骨架中...');
    final analysis = await VideoAnalysisService().analyze(
      videoPath: videoPath,
      sessionDir: sessionDir,
      durationSeconds: durationSeconds,
      onProgress: (progress, label) => onProgress?.call(label),
    );

    if (analysis == null) {
      debugPrint('[VideoAnalysisPipeline] ❌ 基础分析失败');
      return null;
    }

    final hasCSV = await File(csvPath).exists();
    final hasAudio = analysis.audioPath.isNotEmpty && 
                     await File(analysis.audioPath).exists();

    debugPrint('[VideoAnalysisPipeline] ✅ 基础分析完成: CSV=$hasCSV, Audio=$hasAudio');

    return BasicAnalysisResult(
      csvPath: csvPath,
      audioPath: analysis.audioPath,
      isComplete: hasCSV && hasAudio,
    );
  } catch (e) {
    debugPrint('[VideoAnalysisPipeline] ❌ 基础分析错误: $e');
    return null;
  }
}
```

**关键点**:
- ✅ 检查缓存：CSV 和 audio.pcm 都存在则返回
- ✅ 调用 VideoAnalysisService().analyze()
- ✅ 返回结果包含 audioPath

---

### 2. VideoAnalysisService.analyze()

**文件**: `lib/services/video_analysis_service.dart:19-48`

```dart
Future<VideoAnalysisResult> analyze({
  required String videoPath,
  required String sessionDir,
  required int durationSeconds,
  void Function(double progress, String label)? onProgress,
}) async {
  final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
  final audioPath = p.join(sessionDir, 'audio.pcm');
  final poseService = PoseDetectorService(mode: PoseDetectionMode.single);

  try {
    // ✅ Stage 1: 骨架分析 (0-75%)
    await _analyzePose(
      videoPath: videoPath,
      csvPath: csvPath,
      durationSeconds: durationSeconds,
      poseService: poseService,
      onProgress: (prog) => onProgress?.call(
        prog * 0.75,
        '分析骨架中... ${(prog * 100).round()}%',
      ),
    );

    // ✅ Stage 2: 音频提取 (75-100%)
    onProgress?.call(0.75, '提取音讯中...');
    bool hasAudio = false;
    try {
      hasAudio = await _extractAudio(videoPath: videoPath, audioPath: audioPath);
    } catch (e) {
      debugPrint('[VideoAnalysis] audio extraction failed: $e');
    }

    onProgress?.call(1.0, '完成');
    return VideoAnalysisResult(
      csvPath: csvPath,
      audioPath: hasAudio ? audioPath : '',
    );
  } finally {
    poseService.dispose();
  }
}
```

**进度分配**:
- 0-75%: 骨架分析
- 75-100%: 音频提取
- 返回: VideoAnalysisResult (包含 audioPath)

---

### 3. VideoAnalysisService._extractAudio()

**文件**: `lib/services/video_analysis_service.dart:135-170`

这是 **关键方法**！

```dart
Future<bool> _extractAudio({
  required String videoPath,
  required String audioPath,
}) async {
  // 🔧 使用 audio_extractor_channel 调用 Android 原生方法
  final result = await _audioChannel.invokeMethod<Map>('extractAudio', {
    'videoPath': videoPath,
  });
  if (result == null) return false;

  final wavPath = result['path'] as String?;
  if (wavPath == null) return false;

  final wavFile = File(wavPath);
  if (!await wavFile.exists()) return false;

  // 📖 WAV 文件格式：44 字节头 + int16 LE PCM 样本
  final wavBytes = await wavFile.readAsBytes();
  try {
    await wavFile.delete();  // 清理临时 WAV 文件
  } catch (_) {}

  if (wavBytes.length <= 44) return false;

  // 🔄 关键转换：int16 LE → float32 LE
  // 这与实时录制格式一致
  final pcmData = wavBytes.sublist(44);  // 跳过 WAV 头
  final sampleCount = pcmData.length ~/ 2;
  
  final src = pcmData.buffer.asByteData();
  final dst = ByteData(sampleCount * 4);
  
  for (var i = 0; i < sampleCount; i++) {
    // int16 (有符号) → float32 ([-1.0, 1.0])
    final s = src.getInt16(i * 2, Endian.little) / 32768.0;
    // 钳制到 [-1.0, 1.0]
    dst.setFloat32(i * 4, s.clamp(-1.0, 1.0), Endian.little);
  }

  // 💾 保存为 PCM Float32 Little Endian
  await File(audioPath).writeAsBytes(dst.buffer.asUint8List());
  debugPrint('[VideoAnalysis] audio done: $sampleCount samples → $audioPath');
  return true;
}
```

**转换流程**:
```
1. 调用 audio_extractor_channel
   ↓
2. Android 返回 WAV 文件
   ↓
3. 读取 WAV 文件内容
   ↓
4. 跳过 44 字节头，获取音频数据
   ↓
5. int16 (有符号) ÷ 32768 → float32 [-1.0, 1.0]
   ↓
6. 钳制到范围内
   ↓
7. 保存为 PCM Float32 Little Endian
```

---

## 🔄 完整流程图

```
偵測擊球按钮被按下
  │
  └─→ RecordingHistoryPage._detectHits()
      │
      ├─ 检查 CSV 存在?
      │   ├─ YES: 跳过基础分析
      │   └─ NO: 进入下面的流程
      │
      └─→ VideoAnalysisPipelineService.analyzeBasic()
          │
          ├─ 检查缓存
          │   ├─ CSV 和 audio.pcm 都存在? → 返回缓存结果
          │   └─ 否则进行完整分析
          │
          └─→ VideoAnalysisService.analyze()
              │
              ├─ Stage 1 (0-75%): _analyzePose()
              │   ├─ 逐帧提取
              │   ├─ 使用 ML Kit 检测骨架
              │   └─ 写入 pose_landmarks.csv
              │
              ├─ Stage 2 (75-100%): _extractAudio()
              │   │
              │   ├─① 调用 audio_extractor_channel
              │   │   └─ Android: MediaCodec 解码
              │   │
              │   ├─② 获得 WAV 文件
              │   │   └─ File: {cache}/audio_extract_*.wav
              │   │
              │   ├─③ WAV → PCM 转换
              │   │   ├─ 读取 WAV 文件
              │   │   ├─ 跳过 44 字节头
              │   │   ├─ int16 → float32
              │   │   └─ 钳制范围
              │   │
              │   └─④ 保存 PCM
              │       └─ File: {sessionDir}/audio.pcm
              │
              └─ 返回结果: {csvPath, audioPath}
              
      ↓
      返回 BasicAnalysisResult
      │
      ├─ csvPath: {sessionDir}/pose_landmarks.csv
      └─ audioPath: {sessionDir}/audio.pcm
      
  ↓
[偵測擊球] 读取 audio.pcm
  │
  ├─ 若存在: 加载为 List<double>
  └─ 若不存在: 用空列表 []
  
  ↓
[偵測擊球] 传递给 SwingImpactDetector.detect()
  │
  ├─ 输入: CSV + PCM
  ├─ 输出: List<SwingHit>
  └─ 进度: 0.5-1.0
```

---

## 📊 与完整分析的区别

### 偵測擊球的 PCM 提取

| 步骤 | 方式 | 代码位置 |
|------|------|--------|
| **触发** | 基础分析的一部分 | VideoAnalysisService.analyze() |
| **获得 WAV** | audio_extractor_channel | _extractAudio() |
| **转换方式** | int16 ÷ 32768 + clamp | _extractAudio() L161 |
| **保存位置** | {sessionDir}/audio.pcm | _extractAudio() L167 |
| **缓存机制** | 若已存在则跳过 | analyzeBasic() L24 |

### 完整分析的 PCM 提取

| 步骤 | 方式 | 代码位置 |
|------|------|--------|
| **触发** | 独立的提取流程 | RecordingHistoryPage._runCombinedAnalysis() |
| **获得 WAV** | audio_extractor_channel | AudioExtractionService.extractAudioFromVideo() |
| **转换方式** | int16 ÷ 32768 | AudioExtractionService._convertWavToPcm() |
| **保存位置** | {sessionDir}/audio.pcm | AudioExtractionService._convertWavToPcm() |
| **采样率转换** | 支持重采样到 44.1kHz | AudioExtractionService._resampleAudio() |

---

## ⚠️ 关键差异

### 1. 转换公式不同

**偵測擊球** (VideoAnalysisService._extractAudio):
```dart
final s = src.getInt16(i * 2, Endian.little) / 32768.0;
dst.setFloat32(i * 4, s.clamp(-1.0, 1.0), Endian.little);
```

**完整分析** (AudioExtractionService._convertWavToPcm):
```dart
final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;
pcmSamples.add(signedInt16 / 32768.0);
```

**区别**:
- 偵測擊球: 直接除法 + 钳制
- 完整分析: 显式符号转换

两者最终结果应该相同，但实现略有不同。

---

### 2. 采样率处理

**偵測擊球**:
```dart
// ❌ 不做采样率转换
// 直接使用 WAV 的原始采样率
```

**完整分析**:
```dart
// ✅ 支持采样率转换
if (sampleRate != targetSampleRate) {
  finalSamples = _resampleAudio(
    samples: pcmSamples,
    sourceSampleRate: sampleRate,
    targetSampleRate: 44100,
  );
}
```

**风险**: 如果视频的采样率不是 44.1kHz，偵測擊球的 PCM 采样率可能不同，影响击球检测。

---

### 3. WAV 处理

两者都做了相同的处理：
- ✅ 读取 WAV 文件
- ✅ 跳过 44 字节头
- ✅ 删除临时 WAV 文件

---

## 🎯 偵測擊球中 PCM 的使用方式

在 RecordingHistoryPage._detectHits() 中：

```dart
// 2️⃣ 读取 PCM（来自基础分析）
List<double> audioPcm = [];
const int sampleRate = 44100;
final pcmFile = File(audioPath);  // 来自 BasicAnalysisResult.audioPath

if (await pcmFile.exists()) {
  final bytes = await pcmFile.readAsBytes();
  final byteData = bytes.buffer.asByteData();
  audioPcm = List<double>.generate(
    bytes.length ~/ 4,
    (i) => byteData.getFloat32(i * 4, Endian.little),
  );
} else {
  audioPcm = [];  // ⚠️ 若不存在，用空列表
}

// 3️⃣ 传递给击球检测器
final hits = await SwingImpactDetector.detect(
  csvPath: csvPath,
  audioPcm: audioPcm,           // ← PCM 数据
  audioSampleRate: sampleRate,
);
```

**读取方式**:
1. 检查文件存在性
2. 读取字节数据
3. 逐个转换为 Float32 (Little Endian)
4. 若文件不存在，用空列表继续

---

## 🔧 配置信息

### Channel 定义

**偵測擊球** (VideoAnalysisService):
```dart
static const _audioChannel = MethodChannel('audio_extractor_channel');
```

**完整分析** (AudioExtractionService):
```dart
static const platform = MethodChannel('audio_extractor_channel');
```

**相同**: 都使用 `'audio_extractor_channel'`

---

### Android 原生实现

两者都调用同一个 Android Channel 实现：
- 使用 MediaExtractor 查找音轨
- 使用 MediaCodec 解码
- 输出 WAV 文件

---

## 📈 进度分配

在偵測擊球中：
```
0% - 开始
0-30%: 基础分析 (若需要)
  ├─ 0-22.5%: 骨架分析 (75% of 30%)
  └─ 22.5-30%: 音频提取 (25% of 30%)
30-35%: 读取 PCM
35-50%: 击球检测
50-100%: 裁切片段
```

在完整分析中：
```
0-70%: 视频分析
72-82%: 音频提取 (AudioExtractionService)
82-92%: WAV 转 PCM
92-100%: 音频分析 (AudioExportService)
```

---

## ✨ 总结

**偵測擊球中的 PCM 提取流程**:

1. **触发**: 调用 `VideoAnalysisPipelineService.analyzeBasic()`
2. **检查**: 若 CSV 和 audio.pcm 都存在则跳过
3. **分析**: 调用 `VideoAnalysisService.analyze()`
   - 0-75%: 骨架分析
   - 75-100%: 音频提取
4. **提取**: `_extractAudio()` 方法
   - 调用 `audio_extractor_channel`
   - WAV → PCM Float32 转换
   - 保存到 {sessionDir}/audio.pcm
5. **读取**: PCM 文件转为 `List<double>`
6. **使用**: 传递给 `SwingImpactDetector`

**关键特点**:
- ✅ 与完整分析使用同一个 Channel
- ⚠️ 不进行采样率转换（潜在风险）
- ✅ 缓存机制避免重复分析
- ⚠️ PCM 不存在时用空列表继续（精度下降）

