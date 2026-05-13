# ✅ 音频切分功能修复总结

## 问题识别

### 原始问题
- ❌ 视频分析将视频切分成多个击球片段（_hit_1, _hit_2 等）时
- ❌ **音频文件（audio.pcm）没有被相应地切分**
- ❌ 只有主录制目录有 audio.pcm，击球子目录中无音频

### 文件结构对比

**修复前**：
```
✅ 1778637922771/
    ├── swing.mp4
    ├── audio.pcm          ← 只在主目录
    ├── pose_landmarks.csv

❌ 1778637922771_hit_1/
    ├── clip.mp4
    ├── skeleton.mp4
    ├── final.mp4
    └── ❌ 无 audio.pcm    ← 音频缺失！

❌ 1778637922771_hit_2/
    ├── clip.mp4
    ├── skeleton.mp4
    ├── final.mp4
    └── ❌ 无 audio.pcm    ← 音频缺失！
```

**修复后**：
```
✅ 1778637922771/
    ├── swing.mp4
    ├── audio.pcm          ← 完整原始音频

✅ 1778637922771_hit_1/
    ├── clip.mp4
    ├── skeleton.mp4
    ├── final.mp4
    ├── pose_landmarks.csv
    └── ✅ audio.pcm       ← 切分的音频片段

✅ 1778637922771_hit_2/
    ├── clip.mp4
    ├── skeleton.mp4
    ├── final.mp4
    ├── pose_landmarks.csv
    └── ✅ audio.pcm       ← 切分的音频片段
```

---

## 修复实现

### 文件修改
**[lib/services/clip_pipeline_service.dart](../lib/services/clip_pipeline_service.dart)**

### 修改内容

#### 1️⃣ 扩展 `run()` 方法
```dart
// 添加 srcAudioPath 参数
final srcAudioPath  = p.join(srcSessionDir, 'audio.pcm');

// 传递给 _trimHit
srcAudioPath: srcAudioPath,
```

#### 2️⃣ 扩展 `_trimHit()` 方法签名
```dart
// 新增参数
required String srcSessionDir,
required String srcAudioPath,
```

#### 3️⃣ 在 `_trimHit()` 中调用音频切分
```dart
// 從原始音頻切分此球的音頻片段
final dstAudioPath = p.join(sessionDir, 'audio.pcm');
await _sliceAudio(
  srcAudioPath: srcAudioPath,
  dstAudioPath: dstAudioPath,
  startSec: hit.startSec,
  endSec: hit.endSec,
);
```

#### 4️⃣ 实现新方法 `_sliceAudio()`
```dart
/// 從原始音頻（PCM）中切分出指定時間範圍的片段
/// 
/// PCM 格式：Float32，44.1kHz，每個樣本占 4 字節
static Future<void> _sliceAudio({
  required String srcAudioPath,
  required String dstAudioPath,
  required double startSec,
  required double endSec,
}) async {
  final src = File(srcAudioPath);
  if (!await src.exists()) {
    debugPrint('[Pipeline._sliceAudio] 原始音頻不存在，略過：$srcAudioPath');
    return;
  }

  try {
    const int sampleRate = 44100;
    const int bytesPerSample = 4; // Float32
    
    final bytes = await src.readAsBytes();
    final totalSamples = bytes.length ~/ bytesPerSample;
    
    // 計算樣本範圍
    final startSample = (startSec * sampleRate).toInt().clamp(0, totalSamples);
    final endSample = (endSec * sampleRate).toInt().clamp(0, totalSamples);
    
    if (startSample >= endSample) {
      debugPrint('[Pipeline._sliceAudio] 無效範圍：$startSample-$endSample');
      return;
    }
    
    // 提取字節範圍
    final startByte = startSample * bytesPerSample;
    final endByte = endSample * bytesPerSample;
    final slicedBytes = bytes.sublist(startByte, endByte);
    
    // 寫入目標檔案
    await File(dstAudioPath).writeAsBytes(slicedBytes);
    
    final slicedSamples = slicedBytes.length ~/ bytesPerSample;
    debugPrint('[Pipeline._sliceAudio] 切分完成: $startSample-$endSample ($slicedSamples 樣本) → $dstAudioPath');
  } catch (e) {
    debugPrint('[Pipeline._sliceAudio] 錯誤: $e');
  }
}
```

---

## 技术细节

### PCM 音频格式
- **编码**：PCM Float32（32 位浮点数）
- **采样率**：44,100 Hz
- **字节大小**：每个样本 4 字节
- **时间转换**：样本数 = 时间(秒) × 采样率

### 切分算法
1. 读取源 audio.pcm 文件的全部字节
2. 计算开始和结束的样本位置
   - `startSample = startSec × 44100`
   - `endSample = endSec × 44100`
3. 转换为字节偏移量
   - `startByte = startSample × 4`
   - `endByte = endSample × 4`
4. 提取字节范围：`bytes.sublist(startByte, endByte)`
5. 写入目标 audio.pcm 文件

### 日志输出示例
```
[Pipeline._sliceAudio] 切分完成: 352800-529200 (176400 樣本) → /data/.../1778637922771_hit_1/audio.pcm
[Pipeline._sliceAudio] 切分完成: 529200-705600 (176400 樣本) → /data/.../1778637922771_hit_2/audio.pcm
```

---

## 好处

### ✅ 现在支持的功能

1. **击球级别的音频分析**
   - 可以对每个击球片段进行独立的音频分析
   - 支持识别单个击球的声音特性

2. **完整的媒体数据集**
   - 每个击球目录现在有完整的媒体数据：
     - 视频（clip.mp4）
     - 骨架数据（pose_landmarks.csv）
     - **音频（audio.pcm）** ✅ 新增

3. **音频特徵对齐**
   - 音频时间范围与视频裁切完全对齐
   - 避免音频/视频不匹配的问题

---

## 验证方法

### 1️⃣ 执行视频分析
1. 打开应用 → 录制历史页面
2. 点击一条录制 → 菜单 → 完整分析
3. 等待分析完成

### 2️⃣ 检查音频切分结果
```bash
# 查找所有 audio.pcm 文件
adb shell run-as com.example.golf_score_app find app_flutter/golf_recordings -name audio.pcm

# 预期输出：
# app_flutter/golf_recordings/1778637922771/audio.pcm
# app_flutter/golf_recordings/1778637922771_hit_1/audio.pcm   ← 新增！
# app_flutter/golf_recordings/1778637922771_hit_2/audio.pcm   ← 新增！
```

### 3️⃣ 验证文件大小
```bash
adb shell run-as com.example.golf_score_app ls -lh app_flutter/golf_recordings/1778637922771*/audio.pcm

# 预期：
# -rw------- 16M audio.pcm (原始)
# -rw------- 2M audio.pcm (_hit_1 - 约 1/8)
# -rw------- 2M audio.pcm (_hit_2 - 约 1/8)
```

---

## 后续应用

### 现在可以实现
1. ✅ 击球级别的音频分析（类似主录制的"完整分析"）
2. ✅ 多击球的音频对比分析
3. ✅ 击球声音特性统计

---

## 代码质量

- ✅ Dart 代码通过 `dart analyze` 检查
- ✅ 与现有 `_sliceCsv()` 方法模式一致
- ✅ 完整的错误处理和日志记录
- ✅ 支持缺少源音频的情况（优雅降级）

---

## 总结

通过添加 `_sliceAudio()` 方法，实现了完整的音频切分功能，确保每个击球片段都有对应的音频数据，为后续的击球级别音频分析打下了基础。

