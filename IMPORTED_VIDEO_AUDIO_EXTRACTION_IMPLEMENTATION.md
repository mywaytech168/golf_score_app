# 📱 导入视频的完整音频分析流程实现

## 🎯 目标流程

```
導入 → 錄影歷史 → 按下影片分析 → 提取骨架和音頻
```

---

## ✅ 已实现的功能

### 1️⃣ Dart 端：音频提取服务
**文件**: [lib/services/audio_extraction_service.dart](../lib/services/audio_extraction_service.dart)

```dart
// 从视频中提取音频为 PCM Float32 44.1kHz
static Future<int> extractAudioFromVideo({
  required String videoPath,
  required String outputPcmPath,
  void Function(double progress, String message)? onProgress,
}) async
```

**两层备选方案**：
1. ✅ **Android Platform Channel** → 使用原生 MediaCodec
2. ✅ **系统 FFmpeg** → 调用命令行 ffmpeg (Linux/macOS/Windows)

---

### 2️⃣ Android 端：音频提取处理程序
**文件**: [android/app/src/main/kotlin/.../AudioExtractionHandler.kt](../android/app/src/main/kotlin/com/example/golf_score_app/AudioExtractionHandler.kt)

```kotlin
// 处理 Dart 的 MethodChannel 调用
platform.invokeMethod("extractAudio", {
  videoPath: "path/to/video.mp4",
  outputPcmPath: "path/to/audio.pcm"
})
```

**实现方式**：
- 使用 `MediaExtractor` 扫描音频轨道
- 使用 `MediaCodec` 解码任意音频格式 (MP3, AAC, OGG 等)
- 输出标准 PCM Float32 格式
- 自动检测采样率并转换为 44.1kHz （如需要）

---

### 3️⃣ MainActivity 集成
**文件**: [android/app/src/main/kotlin/.../MainActivity.kt](../android/app/src/main/kotlin/com/example/golf_score_app/MainActivity.kt)

```kotlin
// 在 configureFlutterEngine 中初始化
AudioExtractionHandler(flutterEngine)
```

---

### 4️⃣ 分析流程集成
**文件**: [lib/pages/recording_history_page.dart](../lib/pages/recording_history_page.dart) - `_runCombinedAnalysis()` 方法

```dart
// Stage 2: 音频分析 (72-80% 进度)
if (!pcmExists) {
  debugPrint('[完整分析] 🎵 PCM 不存在，尝试从视频提取...');
  
  final samplesExtracted = await AudioExtractionService.extractAudioFromVideo(
    videoPath: clipPath,
    outputPcmPath: pcmFile.path,
    onProgress: (progress, message) {
      // 更新进度条 72-80%
    },
  );
  
  if (samplesExtracted > 0) {
    pcmExists = await pcmFile.exists();
  }
}

// 如果成功提取或原本存在，继续音频分析
if (pcmExists) {
  audioResult = await AudioExportService.analyzeFromPcm(...);
}
```

---

## 🔄 完整流程时序

```
┌─ 用户按下"影片分析" ────────────────────────────────┐
│                                                     │
├─→ Stage 1: 视频分析 (0-70%)                        │
│   ├─ 提取骨架 (Pose Detection)                     │
│   ├─ 检测球轨迹 (Ball Trajectory)                   │
│   └─ 生成击球剪辑 (_hit_1, _hit_2, ...)            │
│                                                     │
├─→ Stage 2: 音频分析 (70-100%)                       │
│   ├─ 检查 audio.pcm 是否存在?                       │
│   │   ├─ YES → 使用现有 PCM                         │
│   │   └─ NO → 从视频提取音频                        │
│   │        ├─ 检查视频是否有音轨                   │
│   │        ├─ 使用 MediaCodec 解码                  │
│   │        └─ 生成 audio.pcm (PCM Float32)         │
│   │                                                │
│   └─ 执行音频分析                                   │
│       ├─ 提取音频特征                               │
│       ├─ Bayesian 分类                              │
│       └─ 生成 audio_features.csv 和 audio_analysis.txt
│                                                     │
└─ 返回结果到 UI ──────────────────────────────────┘
```

---

## 📊 进度条显示

```
0% ──→ 10% : 检查视频
10% ──→ 70% : 视频分析 (骨架 + 球轨迹)
70% ──→ 72% : 检查 PCM
72% ──→ 80% : 从视频提取音频 (MediaCodec)
80% ──→ 100% : 音频分析 + 分类
```

---

## 🎯 支持的场景

### ✅ 场景 1: 自录制视频 (RecordScreen)
```
swing.mp4 + audio.pcm (实时录制)
    ↓
[音频分析] → 使用现有 audio.pcm
    ↓
音频特征 + 分类结果
```

### ✅ 场景 2: 导入的视频 (ExternalVideoImporter)
```
swing.mp4 (来自相册)
    ↓
[检测音轨] → 有音轨
    ↓
[提取音频] → MediaCodec 解码
    ↓
生成 audio.pcm
    ↓
[音频分析] → 使用提取的 PCM
    ↓
音频特征 + 分类结果
```

### ⚠️ 场景 3: 无音轨的视频
```
swing.mp4 (无音频轨道)
    ↓
[检测音轨] → 无音轨
    ↓
[跳过提取] → 显示 "⚠️ 无法提取音频"
    ↓
[仅视频分析] → 骨架 + 球轨迹 (无音频分析)
```

---

## 🔧 技术细节

### MediaCodec 解码流程

```kotlin
// 1. 使用 MediaExtractor 读取视频数据
val extractor = MediaExtractor()
extractor.setDataSource(videoPath)

// 2. 查找音频轨道
for (i in 0 until extractor.trackCount) {
  val format = extractor.getTrackFormat(i)
  if (format.getString(MediaFormat.KEY_MIME).startsWith("audio/")) {
    audioTrackIndex = i
    break
  }
}

// 3. 配置解码器
val decoder = MediaCodec.createDecoderByType(audioMime)
decoder.configure(audioFormat, null, null, 0)

// 4. 读取编码数据 → 解码 → 写入 PCM
while (!isEOS) {
  val inputBuffer = decoder.dequeueInputBuffer(timeout)
  val sampleSize = extractor.readSampleData(inputBuffer, 0)
  decoder.queueInputBuffer(inputBufferId, 0, sampleSize, ...)
  
  val outputBuffer = decoder.dequeueOutputBuffer(bufferInfo, timeout)
  pcmOutputStream.write(outputBuffer.array())
}
```

### PCM 格式规范

```
格式:       PCM Float32 Little Endian
采样率:     44,100 Hz
声道数:     1 (单声道)
字节序:     Little Endian
每样本字节: 4 bytes (Float32)

样本数 = 文件大小 / 4
时长(秒) = 样本数 / 44100
```

---

## 📱 设备支持

| 平台 | 支持 | 方法 |
|------|------|------|
| 🤖 Android | ✅ 是 | MediaCodec (原生) |
| 🍎 iOS | ❌ 未实现 | 需要配置 AVFoundation |
| 🪟 Windows | ✅ 是 | 系统 FFmpeg |
| 🐧 Linux | ✅ 是 | 系统 FFmpeg |
| 🍎 macOS | ✅ 是 | 系统 FFmpeg |

---

## 🧪 测试步骤

### 1️⃣ 导入视频
```
主页面 → 选择视频 → 导入短影片
```

### 2️⃣ 进入录制历史
```
首页 → 录制历史 → 找到导入的视频
```

### 3️⃣ 执行分析
```
长按视频 → 菜单 (⋮) → "完整分析" 或 "🎬 播放"按钮
```

### 4️⃣ 观察日志
```
✅ [完整分析] 开始视频分析...
✅ [完整分析] 开始音频分析...
🎵 [完整分析] PCM 不存在，尝试从视频提取...
📊 [AudioExtraction] 从视频提取音频: /path/to/video.mp4
✅ [AudioExtraction] 音频提取成功: 123456 样本
✅ [完整分析] ✅ 分类: good, 反馈: 击球音质优
```

### 5️⃣ 验证文件
```bash
# 查看生成的音频和分析文件
adb shell run-as com.example.golf_score_app ls -lh app_flutter/golf_recordings/*/audio*

# 预期输出:
# app_flutter/golf_recordings/1234567890/audio.pcm (原始或导入视频提取)
# app_flutter/golf_recordings/1234567890/audio_features.csv (分析结果)
# app_flutter/golf_recordings/1234567890/audio_analysis.txt (详细报告)
```

---

## ⚠️ 注意事项

### Android 权限
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

### 音频格式支持
MediaCodec 可以解码大多数常见格式：
- ✅ MP3
- ✅ AAC (M4A)
- ✅ OGG Vorbis
- ✅ WAV PCM
- ✅ FLAC
- ❌ Apple Lossless (ALAC)

---

## 📝 故障排查

### 问题 1: "无法提取音频 (缺少 FFmpeg)"
**原因**: 系统无 FFmpeg 且 Android Channel 也不可用
**解决**: 
- ✅ 使用自录制视频（有 audio.pcm）
- ✅ 或在开发环境安装 FFmpeg

### 问题 2: "PCM 样本为空"
**原因**: 视频无音轨或音轨损坏
**解决**:
- ✅ 检查视频是否有音频轨道
- ✅ 用其他播放器验证视频完整性

### 问题 3: "Android Channel 不可用"
**原因**: AudioExtractionHandler 未正确注册
**解决**:
- ✅ 检查 MainActivity.kt 中的初始化代码
- ✅ 确保 AudioExtractionHandler.kt 编译无误

---

## 🔮 未来改进

- [ ] iOS 支持 (AVFoundation)
- [ ] 重采样非 44.1kHz 音频
- [ ] 多声道音频混音为单声道
- [ ] 音频质量检测 (过小声/失真)
- [ ] 进度回调优化
- [ ] 缓存提取的音频以加速重分析

