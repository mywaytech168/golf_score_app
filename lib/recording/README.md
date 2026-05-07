# 錄影模組整合完成 ✅

## 集成内容

### 新建文件

```
lib/recording/
├── pose_frame_model.dart        # 骨架数据模型（33个关键点）
├── pose_csv_writer.dart         # CSV导出器（200列格式）
├── pose_detector_service.dart   # MediaPipe 推论服务
├── skeleton_painter.dart        # CustomPainter 骨架可视化
├── record_screen.dart           # 完整录影页面组件
└── INTEGRATION_GUIDE.dart       # 使用指南和示例代码
```

### 依赖更新

已在 `pubspec.yaml` 中添加：

```yaml
google_mlkit_pose_detection: ^0.12.0   # 骨架检测
flutter_sound: ^9.2.13                  # 独立录音
csv: ^6.0.0                             # CSV 导出
```

### 平台权限

✅ **Android** `AndroidManifest.xml`
- `CAMERA` 已配置
- `RECORD_AUDIO` 已配置
- `WRITE_EXTERNAL_STORAGE` 已配置

✅ **iOS** `Info.plist`
- `NSCameraUsageDescription` 已配置
- `NSMicrophoneUsageDescription` 已配置

## 核心功能

### 三並行工作流程

| 工作 | 驱动 | 输出 |
|------|------|------|
| 视频录制 | `CameraController.startVideoRecording()` | `raw.mp4` |
| 骨架推论 | `startImageStream()` + MediaPipe | 内存缓冲 |
| 独立录音 | `FlutterSoundRecorder.startRecorder()` | `audio.aac` |

**停止后输出三个文件：**

```
{Documents}/session_{timestamp}/
├── raw.mp4                      # 原始视频
├── pose_landmarks.csv           # 骨架数据（200列）
└── audio.aac                    # 音频轨道
```

## 使用示例

### 最简单的用法

```dart
import 'package:golf_score_app/recording/record_screen.dart';

// 打开录影页面
Navigator.push(context, MaterialPageRoute(
  builder: (_) => RecordScreen(
    onComplete: ({required videoPath, required csvPath, required audioPath}) {
      print('录影完成！');
      print('Video: $videoPath');
      print('Pose CSV: $csvPath');
      print('Audio: $audioPath');
    },
  ),
));
```

## CSV 格式说明

每行对应一帧，共200列：

```
frame, time_sec, 
lm0_x_norm, lm0_y_norm, lm0_z, lm0_visibility, lm0_x_px, lm0_y_px,
lm1_x_norm, lm1_y_norm, ...
...
lm32_x_norm, lm32_y_norm, lm32_z, lm32_visibility, lm32_x_px, lm32_y_px
```

- **frame**: 帧序号 (0-based)
- **time_sec**: 时间戳（秒，精确到 0.000001）
- **lmN_x_norm**: 正规化 x 坐标 (0~1)
- **lmN_y_norm**: 正规化 y 坐标 (0~1)
- **lmN_z**: 深度估算值
- **lmN_visibility**: 可见度置信度 (0~1)
- **lmN_x_px**: 像素 x 坐标
- **lmN_y_px**: 像素 y 坐标

## 33 个关键点编号

```
0=nose, 1-6=眼睛, 7-8=耳朵, 9-10=嘴,
11-12=肩膀, 13-16=手臂, 17-22=手指,
23-24=髋部, 25-28=腿, 29-32=脚
```

## 下一步

1. **运行 `flutter pub get`** 以安装新依赖
2. **在需要的页面导入** `record_screen.dart`
3. **集成到现有 RecorderPage** 或创建新的录影选项
4. **测试并调整** 帧率、分辨率等参数
5. **建立后端上传流程** 处理输出的三个文件

## 注意事项

⚠️ **iOS 模拟器限制**
- ML Kit Pose Detection 不支持模拟器，需真机测试

⚠️ **内存管理**
- `_frameBuffer` 全程内存缓冲，建议录影 < 60 秒
- 更长录影需改用流式写入

⚠️ **帧率**
- 固定 30 FPS，与 CSV `time_sec` 计算一致
- 推论速度跟不上时自动跳帧，不阻塞录影

⚠️ **音视同步**
- 视频和音频独立录制
- 后续需通过 `time_sec` 列进行时间对齐

## 架构对比

| 特性 | 新模块 | 现有 RecordingSessionPage |
|------|--------|------------------------|
| 骨架检测 | ✅ MediaPipe | ❌ |
| 独立录音 | ✅ AAC | ⚠️ 音视一体 |
| CSV 输出 | ✅ 200列格式 | ❌ |
| IMU 集成 | ❌ | ✅ BLE |
| 自定义分析 | ✅ 灵活 | ⚠️ 内置逻辑 |

---

**文档更新时间**: 2026-04-21
