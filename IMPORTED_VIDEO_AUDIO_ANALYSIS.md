# 📋 短影片导入的音频处理分析

## 当前问题

### 短影片导入流程
**文件**: [lib/pages/external_video_importer_local.dart](../lib/pages/external_video_importer_local.dart)

```
1️⃣ 复制视频文件
   源路径 → sessionDir/swing.mp4

2️⃣ 验证时长
   必须是 5-120 秒

3️⃣ 生成缩图
   获取视频的第一帧

❌ 缺少：提取音频
   导入的视频没有 audio.pcm
```

### 当前状态

```
✅ 自录制视频（RecordScreen）
   ├── swing.mp4 ✅
   ├── audio.pcm ✅ 由录制过程产生
   ├── pose_landmarks.csv ✅ 分析时产生
   └── thumbnail.jpg ✅

❌ 导入的短视频（ExternalVideoImporter）
   ├── swing.mp4 ✅
   ├── audio.pcm ❌ 缺失！
   ├── pose_landmarks.csv ❌ 缺失（分析时产生）
   └── thumbnail.jpg ✅
```

---

## 问题分析

### 为什么导入的视频没有 audio.pcm？

1. **自录制流程**
   - RecordScreen 使用 `flutter_audio_capture` 插件实时捕获麦克风
   - 同时录制视频和音频
   - 音频保存为 audio.pcm (44.1kHz Float32 PCM)

2. **导入流程**
   - 只复制了视频文件
   - 视频文件可能包含音频轨道，但没有被提取
   - 没有创建对应的 audio.pcm

### 两个可能的方案

---

## 方案 A：从导入视频中提取音频

### 优点
- ✅ 保留原视频的音频信息
- ✅ 支持完整的音频分析
- ✅ 与自录制视频的处理流程一致

### 缺点
- ❌ 需要 FFmpeg 或类似工具
- ❌ 复杂度增加
- ❌ 转码耗时（可能 1-2 分钟）

### 实现方式

```dart
// 伪代码
Future<String?> extractAudioFromVideo({
  required String videoPath,
  required String sessionDir,
}) async {
  // 需要使用 FFmpeg 或 flutter_ffmpeg
  // ffmpeg -i video.mp4 -q:a 9 -n audio.wav
  // 然后转换 WAV → PCM Float32 44.1kHz
}
```

### 所需依赖
- `flutter_ffmpeg` 或 `ffmpeg_kit_flutter`
- 增加 APK 体积 (~30-50MB)

---

## 方案 B：标记为无音频，跳过音频分析

### 优点
- ✅ 无需额外依赖
- ✅ 实现简单快速
- ✅ 用户清晰地知道导入视频没有音频

### 缺点
- ❌ 导入视频无法进行音频分析
- ❌ 功能受限

### 实现方式

```dart
// 在导入流程中标记
return RecordingHistoryEntry(
  filePath: videoPath,
  // ...
  hasAudio: false,  // 新增字段
  audioStatus: AudioStatus.notAvailable,  // 标记
);

// 在分析时检查
if (!entry.hasAudio) {
  showMessage('此视频无音频，将跳过音频分析');
  // 仅进行视频分析（骨架、球轨迹）
}
```

---

## 方案 C：提示用户自行处理（推荐）

### 做法
1. **导入时检测音频轨道**
   ```dart
   // 使用 ffprobe 或 MediaInfo 检查视频
   bool hasAudioTrack = await checkVideoAudio(videoPath);
   ```

2. **提示用户**
   - 有音频 → 正常导入
   - 无音频 → 询问用户是否继续导入（无音频分析）

3. **文档说明**
   - 提供关于"导入视频建议"的指南
   - 推荐用户准备有音频的视频

### 实现难度
- ⭐ 低（无需提取）

---

## 建议方案：混合方式

### 第一阶段（当前）✅
```
保持原样，不提取音频
- 自录制视频：有完整音频
- 导入视频：显示"无音频"标记
```

### 第二阶段（可选升级）
```
如果需要，添加音频提取功能
- 在导入时添加选项
- 用户可选"提取音频"（可能耗时）
- 或仅进行视频分析
```

---

## 数据模型修改（可选）

```dart
// lib/models/recording_history_entry.dart

@immutable
class RecordingHistoryEntry {
  final String filePath;
  final int roundIndex;
  final DateTime recordedAt;
  final int durationSeconds;
  final String? customName;
  final String? thumbnailPath;
  final VideoType videoType;
  final String? sourceVideoPath;
  final double? hitSecond;
  final double? startSecond;
  final int? hitIndex;
  final bool isAnalyzed;
  final bool? goodShot;
  final String? audioLabel;
  final double? audioCrispness;
  
  // 新增字段（可选）
  final bool hasAudio;        // 是否有音频
  final AudioSource? audioSource;  // 音频来源

  const RecordingHistoryEntry({
    // ...
    this.hasAudio = true,       // 默认有音频
    this.audioSource = AudioSource.recorded,  // 默认来自录制
  });
}

enum AudioSource {
  recorded,      // 录制时产生
  extracted,     // 从视频提取
  none,          // 无音频
}
```

---

## 对音频分析流程的影响

### 当前流程
```
RecordingHistoryPage._runCombinedAnalysis()
  ├─ 视频分析 (0-70%)
  └─ 音频分析 (70-100%)
      ├─ 查找 audio.pcm
      ├─ 如不存在 → 跳过
      └─ 显示结果或提示
```

### 改进后的流程
```
RecordingHistoryPage._runCombinedAnalysis()
  ├─ 检查 hasAudio 标记
  ├─ 视频分析 (0-70%)
  └─ 条件音频分析 (70-100%)
      ├─ 如 hasAudio = true
      │   ├─ 查找 audio.pcm
      │   └─ 执行分析
      └─ 如 hasAudio = false
          └─ 跳过音频分析，显示提示
```

---

## 推荐决策

### ✅ 短期方案（建议实施）
1. 保持导入流程不变
2. 在 RecordingHistoryPage 添加检查
3. 如无 audio.pcm，提示用户"此视频无音频"
4. 仅进行视频分析

### ❌ 暂不实施
- 添加 FFmpeg 依赖（增加复杂度）
- 自动提取音频（可能耗时长）

### 📝 文档更新
- 说明导入视频的限制
- 推荐使用"开始录制"以获得完整功能

---

## 实现清单

- [ ] 修改导入函数，添加 `hasAudio` 标记
- [ ] 更新数据模型
- [ ] 修改分析流程，检查 `hasAudio`
- [ ] 添加用户提示 UI
- [ ] 更新帮助文档

---

## 代码修改地点

1. **external_video_importer_local.dart**
   - importVideo() 方法
   - 返回 RecordingHistoryEntry 时设置 hasAudio = false

2. **recording_history_entry.dart**
   - 添加 hasAudio 字段

3. **recording_history_page.dart**
   - _runCombinedAnalysis() 方法
   - 检查 hasAudio 后决定是否分析音频

