# 🔊 音频提取对比分析：完整分析 vs 偵測擊球

## 📊 场景概览

```
长影片 (60-120秒) 工作流程
│
├─ [完整分析] 📹 + 🎵
│   ├─ 视频分析 (0-70%)
│   ├─ 音频提取 (72-82%) ← AudioExtractionService
│   ├─ 音频分析 (82-100%) ← AudioExportService
│   └─ 生成：PCM + CSV + TXT
│
└─ [偵測擊球] 🎵 + 🔍
    ├─ 加载基础分析 (CSV已存在)
    ├─ 读取 PCM (假设已存在)
    ├─ 击球检测 (0.5-1.0) ← SwingImpactDetector
    └─ 生成：多个片段
```

---

## 🔄 完整流程对比

### 场景 1: **完整分析** (`_runCombinedAnalysis`)

```dart
// 文件: lib/pages/recording_history_page.dart:868-1100

// ✅ 特点：自动处理音频提取 + 分析
final clipPath = widget.entry.filePath;           // 当前视频
final sessionDir = p.dirname(clipPath);            // 工作目录
const int sampleRate = 44100;
final pcmFile = File(p.join(sessionDir, 'audio.pcm'));

// 1️⃣ 检查 PCM 存在性
var pcmExists = await pcmFile.exists();

// 2️⃣ PCM 不存在？尝试从视频提取
if (!pcmExists) {
  debugPrint('[完整分析] 📥 PCM 不存在，尝试从视频提取...');
  progressNotifier.value = (0.72, '从视频提取音频中...');
  
  // 🔧 核心：调用音频提取服务
  final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
    videoPath: clipPath,
    outputPcmPath: pcmFile.path,
    onProgress: (progress, message) {
      final adjustedProgress = 0.72 + progress * 0.08;
      progressNotifier.value = (adjustedProgress, message);
    },
  );
  
  if (samplesExtracted > 0) {
    debugPrint('[完整分析] ✅ 音频提取成功: $samplesExtracted 样本');
    pcmExists = await pcmFile.exists();
  } else {
    debugPrint('[完整分析] ⚠️  音频提取失败或系统无FFmpeg支持');
  }
}

// 3️⃣ 如果 PCM 存在，进行音频分析
if (pcmExists) {
  try {
    final bytes = await pcmFile.readAsBytes();
    if (bytes.isNotEmpty) {
      final byteData = bytes.buffer.asByteData();
      final pcmSamples = List<double>.generate(
        bytes.length ~/ 4,
        (i) => byteData.getFloat32(i * 4, Endian.little),
      );
      
      // 🔧 核心：调用音频分析服务
      audioResult = await AudioExportService.analyzeFromPcm(
        pcmSamples: pcmSamples,
        sessionDir: sessionDir,
        sampleRate: sampleRate,
        onProgress: (progress) {
          final adjustedProgress = 0.8 + progress.progress * 0.2;
          progressNotifier.value = (adjustedProgress, progress.message);
        },
      );
      
      // 更新条目
      updatedEntry = updatedEntry!.copyWith(
        audioCrispness: audioResult.features.isNotEmpty
            ? audioResult.features.first.sharpnessHfxLoud
            : null,
        goodShot: audioResult.predictedClass == 'pro' || audioResult.predictedClass == 'good',
        audioLabel: audioResult.feedbackLabel,
      );
    }
  } catch (e) {
    debugPrint('[完整分析] ❌ 音频分析异常：$e');
  }
}
```

**关键特征**:
- ✅ **自动提取**: 无 PCM 时自动从视频提取
- ✅ **双步骤**: 提取 + 分析
- ✅ **进度显示**: 72-82% 提取，82-100% 分析
- ✅ **错误恢复**: 提取失败不中断主流程
- ✅ **结果保存**: 更新 RecordingHistoryEntry

---

### 场景 2: **偵測擊球** (`_detectHits`)

```dart
// 文件: lib/pages/recording_history_page.dart:720-790

// ✅ 特点：只读取 PCM，不提取、不分析
final sessionDir = p.dirname(widget.entry.filePath);
final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
final audioPath = p.join(sessionDir, 'audio.pcm');

// 1️⃣ 确保 CSV 存在（若无则先进行基础分析）
if (!await File(csvPath).exists()) {
  debugPrint('[偵測擊球] CSV 不存在，先執行基礎分析...');
  final basicAnalysis = await VideoAnalysisPipelineService.analyzeBasic(
    videoPath: widget.entry.filePath,
    sessionDir: sessionDir,
    durationSeconds: widget.entry.durationSeconds,
    onProgress: (label) {
      progressNotifier.value = (0.3, label);
    },
  );
  // ✅ 基础分析会生成 audio.pcm
}

// 2️⃣ 读取 PCM（假设已存在）
progressNotifier.value = (0.35, '載入音訊中...');
List<double> audioPcm = [];
const int sampleRate = 44100;
final pcmFile = File(audioPath);

if (await pcmFile.exists()) {
  final bytes = await pcmFile.readAsBytes();
  final byteData = bytes.buffer.asByteData();
  audioPcm = List<double>.generate(
    bytes.length ~/ 4,
    (i) => byteData.getFloat32(i * 4, Endian.little),
  );
} else {
  // ⚠️ PCM 不存在则用空列表
  audioPcm = [];
}

// 3️⃣ 调用击球检测（不做音频分析）
progressNotifier.value = (0.5, '偵測擊球中...');
final hits = await SwingImpactDetector.detect(
  csvPath: csvPath,
  audioPcm: audioPcm,           // ← 传递 PCM，但不分析
  audioSampleRate: sampleRate,
);

// 4️⃣ 如果检测到击球，进行裁切
if (hits.isNotEmpty) {
  final results = await ClipPipelineService.run(
    hits: hits,
    srcVideoPath: widget.entry.filePath,
    sourceEntry: widget.entry,
    // ...
  );
}
```

**关键特征**:
- ⚠️ **被动读取**: 只读 PCM，不主动提取
- ⚠️ **单步骤**: 只用于击球检测，无音频分析
- ⚠️ **依赖前置**: 假设基础分析已生成 PCM
- ⚠️ **容错处理**: 无 PCM 时用空列表继续
- ⚠️ **无结果保存**: 只用于检测，不修改条目

---

## 📋 关键差异表

| 指标 | 完整分析 | 偵測擊球 |
|------|--------|--------|
| **PCM 不存在时** | ✅ 自动提取 | ⚠️ 用空列表 |
| **音频分析** | ✅ 进行分析 | ❌ 不分析 |
| **进度显示** | ✅ 详细(72-100%) | ⚠️ 简略(35-50%) |
| **结果保存** | ✅ 更新条目 | ❌ 无保存 |
| **前置依赖** | ❌ 无(自动处理) | ✅ 需基础分析 |
| **调用服务** | AudioExtractionService + AudioExportService | SwingImpactDetector |
| **应用场景** | 单个短视频完整分析 | 长视频击球检测+切片 |

---

## 🎯 音频提取策略

### ✅ 完整分析的策略（主动+被动）

```
┌─ 完整分析开始
│
├─ 视频分析完成
│   └─ 生成 skeleton.mp4 或 final.mp4
│
├─ 检查 audio.pcm?
│   ├─ YES → 使用现有 PCM
│   │
│   └─ NO → 【提取流程】
│       ├─ VideoPath: clipPath (final.mp4 or skeleton.mp4)
│       ├─ Output: audio.pcm
│       ├─ Service: AudioExtractionService
│       └─ 进度: 72-82%
│
├─ 音频分析
│   ├─ 特征提取
│   ├─ Bayesian 分类
│   ├─ 进度: 82-100%
│   └─ 保存: CSV + TXT + 字段更新
│
└─ 完成，更新条目
```

### ⚠️ 偵測擊球的策略（被动+缓落）

```
┌─ 偵測擊球开始
│
├─ CSV存在?
│   ├─ YES → 跳过基础分析
│   │
│   └─ NO → 执行基础分析
│       ├─ 生成 CSV + audio.pcm
│       └─ 进度: 0-30%
│
├─ 读取 audio.pcm
│   ├─ YES → 转为 List<double>
│   │
│   └─ NO → 用空列表 []
│
├─ 击球检测
│   ├─ 输入: CSV + PCM (可能为空)
│   ├─ 输出: List<SwingHit>
│   └─ 进度: 35-50%
│
├─ 如果检测到击球
│   ├─ 裁切流程 (ClipPipelineService)
│   └─ 生成多个片段
│
└─ 完成，无条目更新
```

---

## 🔌 关键服务对比

### AudioExtractionService (完整分析使用)

```dart
Future<int> extractAudioFromVideo({
  required String videoPath,        // clipPath
  required String outputPcmPath,    // sessionDir/audio.pcm
  void Function(...)? onProgress,
}) → Future<int>                    // 返回样本数
```

**作用**:
1. 调用 Android audio_extractor_channel
2. MediaCodec 解码视频音轨 → WAV
3. WAV 转 PCM Float32 44.1kHz
4. 保存为 audio.pcm

---

### AudioExportService (完整分析使用)

```dart
Future<AudioAnalysisResult?> analyzeFromPcm({
  required List<double> pcmSamples,
  required String sessionDir,
  required int sampleRate,
  void Function(...)? onProgress,
}) → Future<AudioAnalysisResult?>
```

**作用**:
1. 特征提取 (MFCC, ZCR 等)
2. Bayesian 分类 (good/bad/pro)
3. 生成 CSV + TXT 报告
4. 返回分类结果

---

### SwingImpactDetector (偵測擊球使用)

```dart
Future<List<SwingHit>> detect({
  required String csvPath,
  required List<double> audioPcm,   // 可能为空
  required int audioSampleRate,
}) → Future<List<SwingHit>>
```

**作用**:
1. IMU 数据分析 (从 CSV)
2. 音频辅助检测 (可选)
3. 返回击球时间点列表

---

## ⚠️ 潜在问题

### 问题 1: 偵測擊球中 PCM 为空

**情况**:
```
偵測擊球
  ├─ 基础分析失败 (FFmpeg 问题)
  └─ audio.pcm 未生成
  
结果: audioPcm = [] (空列表)
      SwingImpactDetector 继续运行但检测精度下降
```

**建议**: 添加警告日志

```dart
if (audioPcm.isEmpty) {
  debugPrint('[偵測擊球] ⚠️ 音频为空，击球检测精度可能下降');
}
```

---

### 问题 2: 完整分析和偵測擊球的 PCM 来源不同

**来源路径对比**:

| 场景 | PCM 来源 | 生成方式 |
|------|---------|--------|
| **完整分析-导入视频** | 从 final.mp4 提取 | AudioExtractionService |
| **完整分析-本地录制** | 从 swing.mp4 提取 | AudioExtractionService |
| **偵測擊球** | 来自基础分析 | VideoAnalysisPipelineService.analyzeBasic |

**风险**: 如果基础分析的 PCM 生成方式与完整分析不同，击球检测精度可能差异

---

## ✨ 改进建议

### 1. 统一 PCM 生成方式

```dart
// 为偵測擊球添加主动提取
if (!await File(audioPath).exists()) {
  debugPrint('[偵測擊球] PCM 不存在，尝试从视频提取...');
  await AudioExtractionService.extractAudioFromVideo(
    videoPath: widget.entry.filePath,
    outputPcmPath: audioPath,
  );
}
```

### 2. 添加 PCM 缓存检查

```dart
// 在提取前检查
if (await File(outputPcmPath).exists()) {
  final size = await File(outputPcmPath).length();
  if (size > 0) {
    debugPrint('[AudioExtraction] 使用缓存 PCM (${size} 字节)');
    return size ~/ 4;  // 样本数
  }
}
```

### 3. 增强错误处理

```dart
try {
  audioResult = await AudioExportService.analyzeFromPcm(...);
} catch (e) {
  debugPrint('[完整分析] ❌ 音频分析异常：$e');
  // 降级处理：继续流程但不保存音频结果
  audioResult = null;
}
```

---

## 📊 流程总结

```
导入视频
  │
  ├─→ 完整分析
  │   ├─ 视频分析 (0-70%)
  │   ├─ 音频提取 (72-82%) ← AudioExtractionService
  │   ├─ 音频分析 (82-100%) ← AudioExportService
  │   └─ 保存结果 ✅
  │
  └─→ 偵測擊球
      ├─ 基础分析 (若需要)
      ├─ 加载 PCM (被动)
      ├─ 击球检测 (0.5-1.0) ← SwingImpactDetector
      └─ 生成片段 ✅
```

**核心差异**: 
- **完整分析** = 主动提取 + 主动分析 + 结果保存
- **偵測擊球** = 被动读取 + 纯检测 + 无保存

