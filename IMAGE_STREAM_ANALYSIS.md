# Image Stream 与视频录制冲突分析

## 问题确认

**根本原因**：Flutter `camera` plugin 的底层限制
- 不支持 **同时** 进行 `startVideoRecording()` + `startImageStream()`
- Android 层调用 API 会相互冲突
- 启动顺序无关（已验证：image → video 和 video → image 都失败）

**当前状态**：
```
第二次录影结果：
- ❌ _frameIdx = 0 (未捕获任何帧)
- ⚠️ stopImageStream 失败: "No camera is streaming images"
  → 说明 startImageStream 从未真正成功
- ✅ 视频 + 音频正常工作
```

## 为什么当前的顺序和延迟都不起作用

```dart
// 当前代码（第一次尝试）
await _camera!.startVideoRecording();          // ← 获得相机独占权
await Future.delayed(Duration(milliseconds: 200));
_camera!.startImageStream(_onFrame);           // ← 被拒：相机已被视频录制占用
```

**问题**：
1. `startVideoRecording()` 后，相机进入 **视频录制模式**
2. 任何其他模式（如 image stream）都会被底层驱动拒绝
3. 延迟无法改变这一点，因为这是模式冲突而非时序问题

---

## 📋 可行的解决方案对比

### 方案 A：**后处理姿态检测** ✅ 推荐短期解决方案

**流程**：
1. 只录制视频（当前已工作）✅
2. 录制完后，用 MediaPipe 在后台逐帧检测视频
3. 生成 CSV 和关键帧图像

**优点**：
- ✅ 简单可靠，不需要同时操作
- ✅ 可离线处理，对实时性无要求
- ✅ 支持所有设备
- ✅ 可精确控制帧提取（25, 30, 60 FPS）

**缺点**：
- ❌ 不是 **实时** 骨架显示（录制后显示）
- ❌ 需要额外的 `video_player` + `image` 库处理
- ❌ 处理延迟 1-2 秒（针对 15 秒视频）

**实现复杂度**：中等（1-2 小时）

**代码框架**：
```dart
Future<void> _processVideoForPose(String videoPath) async {
  final VideoController = VideoPlayerController.file(File(videoPath));
  await controller.initialize();
  
  final duration = controller.value.duration;
  final frameCount = (duration.inMilliseconds / 33.33).toInt(); // 30 FPS
  
  for (int i = 0; i < frameCount; i++) {
    // 查找到第 i 帧
    final frame = await _extractFrameAtTime(
      videoPath, 
      Duration(milliseconds: (i * 33).toInt())
    );
    
    // 用 MediaPipe 检测
    final poses = await _poseDetector.processImage(frame);
    _frameBuffer.add(PoseFrameModel(...));
  }
  
  // 生成 CSV
  await _csvWriter.write(_frameBuffer);
}
```

---

### 方案 B：分离相机实例

**流程**：
1. 实例 A：用于视频录制（startVideoRecording）
2. 实例 B：用于图像流（startImageStream）
3. 同时运行两个相机

**优点**：
- ✅ 理论上可行（两个独立实例）
- ✅ 实时骨架显示

**缺点**：
- ❌ 需要两个相机权限集成
- ❌ 高耗电/CPU（两个相机同时工作）
- ❌ 文件同步复杂
- ❌ 大多数设备只有 1 个后摄像头

**可行性**：❌ 低（设备硬件限制）

---

### 方案 C：使用 `camera_android` 直接 API

**流程**：
- 绕过 Flutter plugin，直接调用 Android CameraX 或 Camera2 API
- 在 Kotlin 代码中实现视频+ 图像流

**优点**：
- ✅ 完全控制底层 API
- ✅ 可能支持同时操作

**缺点**：
- ❌ 需要编写 Kotlin 代码（当前团队无 Android 经验）
- ❌ 维护成本高
- ❌ 失去 Flutter 跨平台优势

**可行性**：⚠️ 中等（技术干扰）

---

### 方案 D：使用 MediaPipe Solutions 的视频录制能力

**流程**：
- 用 MediaPipe 自身的录制功能（而不是 Flutter camera）
- MediaPipe 可能有优化的视频+姿态同步方案

**优点**：
- ✅ MediaPipe 官方支持的方式

**缺点**：
- ❌ 学习曲线陡峭
- ❌ 可能需要完全重写录制逻辑

**可行性**：⚠️ 低（复杂度）

---

## 🎯 推荐方案：**方案 A（后处理）**

### 为什么推荐？

1. **最小改动**：保持当前视频+音频录制不变 ✅
2. **高可靠性**：不依赖设备特定的同时操作支持
3. **快速交付**：1-2 小时实现
4. **用户体验**：虽然不是实时，但对高尔夫分析足够（录制后立即分析可接受）
5. **可扩展**：将来可添加实时显示为可选项

### 实现路线图

**第 1 阶段**（当前）：
- ✅ 视频 + 音频录制（已完成）
- ✅ 文件保存（已完成）

**第 2 阶段**（建议）：
- 添加视频帧提取工具函数
- 集成 MediaPipe 批处理模式
- 保存 CSV 和关键帧

**第 3 阶段**（可选）：
- UI：在 VideoPlayerPage 中并排显示骨架
- 实时进度条：处理进度显示

---

## 🔧 实现细节：方案 A - 后处理姿态检测

### 新增文件

**lib/recording/video_pose_processor.dart**
```dart
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img;
import 'package:ml_kit_pose_detector/ml_kit_pose_detector.dart';

class VideoPoseProcessor {
  /// 从视频文件中提取指定时间的帧
  static Future<img.Image?> _extractFrameAtTime(
    String videoPath,
    Duration time,
  ) async {
    // 方案：使用 FFmpeg 或 video_player 控制器
    // NOTE: 实际实现需要选择帧提取库
    // 选项 1: ffmpeg_kit_flutter（完整但重）
    // 选项 2: video_player + texture 截图（轻量）
  }
  
  /// 处理整个视频并生成 CSV
  static Future<List<PoseFrameModel>> processVideo(
    String videoPath, {
    required int targetFps,  // 25, 30, 60 等
    required Function(int current, int total) onProgress,  // 进度回调
  }) async {
    final results = <PoseFrameModel>[];
    
    try {
      // 1. 初始化视频控制器
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration;
      final totalFrames = (duration.inMilliseconds * targetFps / 1000).toInt();
      
      // 2. 逐帧提取和检测
      for (int i = 0; i < totalFrames; i++) {
        final timestamp = Duration(milliseconds: (i * 1000 / targetFps).toInt());
        final frame = await _extractFrameAtTime(videoPath, timestamp);
        
        if (frame != null) {
          final poses = await _detectPose(frame);
          if (poses.isNotEmpty) {
            results.add(PoseFrameModel(
              frameIndex: i,
              timestamp: timestamp,
              landmarks: poses[0].landmarks,
            ));
          }
        }
        
        // 进度更新
        onProgress(i + 1, totalFrames);
      }
      
      await controller.dispose();
      return results;
      
    } catch (e) {
      debugPrint('[VideoPoseProcessor] 处理失败: $e');
      return [];
    }
  }
  
  static Future<List<Pose>> _detectPose(img.Image frame) async {
    // 调用 MediaPipe 或现有的 poseDetectorService
    // ...
  }
}
```

### 集成到 RecordScreen 的停止逻辑

```dart
// 在 _stopRecording() 的文件保存完成后，添加后处理触发
Future<void> _stopRecording() async {
  // ... 现有代码保存文件 ...
  
  // 新增：触发后处理（可选：显示进度对话框）
  if (mounted) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('处理姿态数据...'),
        content: LinearProgressIndicator(),
      ),
    );
    
    final poses = await VideoPoseProcessor.processVideo(
      videoPath,
      targetFps: 30,
      onProgress: (current, total) {
        setState(() => _processingProgress = current / total);
      },
    );
    
    // 更新 CSV
    await csvWriter.writePoses(poses);
    
    Navigator.pop(ctx);
  }
}
```

---

## ❌ 为什么不能在相机插件中解决？

Flutter `camera` 插件源码片段（Android 层典型实现）：

```kotlin
// 伪代码
fun startVideoRecording() {
  mCameraSession.takeExclusiveOwnership()  // ← 获得独占权
  mMediaRecorder.start()
}

fun startImageStream() {
  if (mCameraSession.isExclusive) {
    throw CameraException("已独占，无法流式传输")  // ← 这里被拒
  }
  mPreviewSurface.setCallback(mFrameCallback)
}
```

**解决方法**：需要修改 Flutter camera plugin 的源码或等待官方支持，不是当前项目可快速解决的。

---

## 📊 总结表

| 方案 | 实时性 | 可靠性 | 实现难度 | 推荐度 |
|------|--------|--------|---------|--------|
| A: 后处理姿态检测 | ⏱️ 低（延迟1-2s） | ✅ 高 | 🟢 中 | ⭐⭐⭐ |
| B: 分离相机实例 | ✅ 高 | ❌ 低 | 🔴 高 | ⭐ |
| C: 平台特定代码 | ✅ 高 | ✅ 高 | 🔴 高 | ⭐⭐ |
| D: MediaPipe 完全方案 | ✅ 高 | ✅ 中 | 🔴 高 | ⭐ |

---

## ✅ 建议下一步

**短期（当周）**：
1. 确认用户能接受"录制完成后分析"的原型
2. 实现 **方案 A** 的帧提取工具函数
3. 集成后处理到停止录制流程

**中期（两周）**：
1. 完整的后处理 UI（进度条）
2. 性能优化（帧跳过、GPU 加速）

**长期（查询官方）**：
1. 监视 Flutter camera plugin 是否有更新支持同时操作
2. 或考虑更换低级别相机库

