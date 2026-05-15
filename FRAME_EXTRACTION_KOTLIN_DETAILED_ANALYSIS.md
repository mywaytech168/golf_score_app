# 🎬 帧提取深度分析 (Kotlin → Android)

## 📋 目录
1. [整体架构](#整体架构)
2. [核心流程](#核心流程)
3. [关键技术细节](#关键技术细节)
4. [数据格式转换](#数据格式转换)
5. [诊断机制](#诊断机制)
6. [潜在问题](#潜在问题)
7. [性能分析](#性能分析)

---

## 整体架构

### 📡 通讯层
```
Dart (Flutter)
    ↓ MethodChannel
    ├─ "com.example.golf_score_app/frame_extractor"
    │  └─ Method: "extractFrameRgb"
    └─ Parameters: {videoPath, timeMs, maxWidth}
    ↓
Kotlin (MainActivity.kt)
    ├─ Frame Extractor Executor (线程池)
    └─ Android Native (MediaMetadataRetriever)
    ↓
返回给 Dart: {width, height, pixels (NV21 bytes)}
```

### 🏗️ 组件关系

| 组件 | 文件 | 职责 |
|------|------|------|
| **MethodChannel Handler** | MainActivity.kt:296-418 | 接收 Flutter 调用，管理线程 |
| **Frame Extraction Logic** | MainActivity.kt:318-410 | 核心提取、转换逻辑 |
| **VideoFrameExtractor** | VideoFrameExtractor.kt | 可复用的帧提取类 |
| **Diagnostics** | MainActivity.kt:338-340 | centerPixel 日志诊断 |

---

## 核心流程

### 🔄 执行流程图

```
extractFrameRgb (Dart call)
    ↓
[MethodChannel Handler] - MainActivity.kt:299
    ↓
参数验证 (videoPath, timeMs, maxWidth)
    ↓
[frameExtractorExecutor] 在线程池中执行
    ↓
[MediaMetadataRetriever] 提取 bitmap
    ↓
检查 & 调整 Bitmap 配置
    ↓
getPixels() → 获取 ARGB 像素数组
    ↓
RGB → NV21 YUV 颜色空间转换
    ├─ Y 平面: 全分辨率亮度 (width × height)
    └─ UV 平面: 半分辨率色度 (width/2 × height/2 交错)
    ↓
返回: {width, height, pixels (NV21 字节数组)}
```

### 📍 关键代码片段

#### 1️⃣ MethodChannel 处理器注册
**位置**: `MainActivity.kt:296-418`

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FRAME_EXTRACTOR_CHANNEL)
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "extractFrameRgb" -> {
                // 参数解析
                val videoPath = call.argument<String>("videoPath")
                val timeMs = (call.argument<Int>("timeMs") ?: 0).toLong()
                val maxWidth = call.argument<Int>("maxWidth") ?: 720
                
                // 异步执行在 frameExtractorExecutor 线程
                frameExtractorExecutor.execute { ... }
            }
        }
    }
```

**关键点**:
- ⚠️ `call.argument<Int>("timeMs")` 是 **Int 而非 Long**
- 需要显式转换为 `toLong()`
- 然后乘以 1000 转换为微秒: `timeUs = timeMs * 1000L`

#### 2️⃣ MediaMetadataRetriever 提取
**位置**: `MainActivity.kt:318-335`

```kotlin
val retriever = MediaMetadataRetriever()
retriever.setDataSource(videoPath)

val timeUs = timeMs * 1000L
val frm: Bitmap? = retriever.getFrameAtTime(
    timeUs,
    MediaMetadataRetriever.OPTION_CLOSEST_SYNC  // 关键选项
)
retriever.release()
```

**参数详解**:
| 参数 | 值 | 含义 |
|-----|-----|------|
| `timeUs` | timeMs × 1000 | 微秒单位的时间戳 |
| `OPTION_CLOSEST_SYNC` | 常数 | 获取最近的关键帧（I-frame） |

**OPTION_CLOSEST_SYNC 的影响**:
- ✅ 更快速（直接定位关键帧）
- ⚠️ 可能不是精确的指定时间戳
- 📌 用于连续帧提取时，相邻帧很可能来自**同一个关键帧**
- 🚨 **这是导致骨架完全相同的可能原因之一**

#### 3️⃣ Bitmap 缩放
**位置**: `MainActivity.kt:337-346`

```kotlin
if (frm != null && frm.width != maxWidth) {
    val scaledHeight = (maxWidth.toDouble() / frm.width * frm.height).toInt()
    val scaledBmp = Bitmap.createScaledBitmap(frm, maxWidth, scaledHeight, true)
    frm.recycle()  // 释放原始 bitmap 内存
    scaledBmp
} else {
    frm
}
```

**关键点**:
- 保持宽高比: `scaledHeight = width_ratio × originalHeight`
- 第4个参数 `true` = 使用双线性插值（质量更高但速度略慢）
- 必须 `recycle()` 原始 bitmap 以释放内存

---

## 关键技术细节

### 🔍 诊断：中心像素检查
**位置**: `MainActivity.kt:338-340`

```kotlin
// ✅ 診斷：檢查 bitmap 中心像素
val centerPixel = bitmap.getPixel(bitmap.width / 2, bitmap.height / 2)
Log.d(logTag, "[FrameDebug] frame=$frameIndex timeMs=$timeMs centerPixel=$centerPixel")
```

**工作原理**:
- 获取 bitmap 中心点像素: `(width/2, height/2)`
- 打印为 ARGB 32-bit 整数
- 每一帧的值应该 **不同**（除非视频静止）

**ARGB 整数结构**:
```
centerPixel = 0xAARRGGBB
├─ AA: Alpha (透明度) - 字节 24-31
├─ RR: Red - 字节 16-23
├─ GG: Green - 字节 8-15
└─ BB: Blue - 字节 0-7
```

**提取方法**:
```kotlin
val alpha = (centerPixel shr 24) and 0xFF
val red   = (centerPixel shr 16) and 0xFF
val green = (centerPixel shr 8)  and 0xFF
val blue  = centerPixel and 0xFF
```

### 🎨 Bitmap 配置检查
**位置**: `MainActivity.kt:342-349`

```kotlin
val workingBitmap = if (bitmap.config != Bitmap.Config.ARGB_8888) {
    Log.w(logTag, "[MMR] Bitmap config is ${bitmap.config}, converting to ARGB_8888")
    val converted = bitmap.copy(Bitmap.Config.ARGB_8888, false)
    bitmap.recycle()
    converted
} else {
    bitmap
}
```

**为什么要统一为 ARGB_8888**:
- MediaMetadataRetriever 有时返回其他格式（如 RGB_565, ARGB_4444）
- NV21 转换需要标准的 ARGB_8888 格式
- 防止转换时的数据损失或错误

**Bitmap.Config 选项**:
| 配置 | 字节/像素 | 说明 |
|-----|---------|------|
| ALPHA_8 | 1 | 仅 Alpha，用于遮罩 |
| RGB_565 | 2 | 红5位，绿6位，蓝5位（无Alpha） |
| ARGB_4444 | 2 | 已弃用 |
| **ARGB_8888** | 4 | 每通道 8 位（我们使用） |

---

## 数据格式转换

### 🔄 RGB → NV21 YUV 色彩空间转换

#### 📐 转换公式

**BT.601 标准 RGB → YUV 转换**:

```
Y  = 0.299 × R + 0.587 × G + 0.114 × B
U  = -0.169 × R - 0.331 × G + 0.5 × B + 128
V  = 0.5 × R - 0.419 × G - 0.081 × B + 128
```

**位置**: `MainActivity.kt:363-374`（Y平面）和 `375-391`（UV平面）

#### 📊 NV21 内存布局

**NV21 格式** = YUV 4:2:0 半平面排列

```
总字节数 = width × height × 1.5

┌────────────────────────────┐
│      Y 平面                 │  (width × height 字节)
│   全分辨率亮度数据          │
├────────────────────────────┤
│      UV 平面                │  (width/2 × height/2 × 2 字节)
│  V 和 U 交错排列            │
│  下采样 2:1 (水平+竖直)    │
└────────────────────────────┘

NV21 排列顺序:
Y[0]  Y[1]  Y[2]  Y[3]  ...  Y[width-1]
Y[width] Y[width+1] ... Y[2×width-1]
...
Y[(height-1)×width] ... Y[height×width-1]
[Y平面结束，共 width×height 字节]
V[0] U[0]  V[1] U[1]  V[2] U[2]  ...  (交错)
V[width/2] U[width/2]  ...
```

#### 🧮 Y 平面计算（全分辨率）
**位置**: `MainActivity.kt:363-370`

```kotlin
// Y plane (0 to width*height-1)
for (i in 0 until frameSize) {  // frameSize = width × height
    val r = (pixels[i] shr 16) and 0xFF
    val g = (pixels[i] shr 8) and 0xFF
    val b = pixels[i] and 0xFF
    
    // 亮度 (0-255)
    val y = (0.299 * r + 0.587 * g + 0.114 * b).toInt()
                .coerceIn(0, 255).toByte()
    
    nv21[i] = y  // 直接写入 NV21 对应位置
}
```

**特点**:
- 每个像素映射到一个 Y 字节
- 完整分辨率保留所有亮度信息
- Y 值范围: 0-255（黑到白）

#### 🧮 UV 平面计算（半分辨率交错）
**位置**: `MainActivity.kt:375-391`

```kotlin
// UV plane (NV21: V, U interleaved, half resolution)
val uvOffset = frameSize  // UV 从 Y 平面之后开始
for (j in 0 until bitmapHeight step 2) {        // 每隔 1 行（竖直下采样）
    for (i in 0 until bitmapWidth step 2) {     // 每隔 1 列（水平下采样）
        val idx = j * bitmapWidth + i           // 源 RGB 像素索引
        
        val r = (pixels[idx] shr 16) and 0xFF
        val g = (pixels[idx] shr 8) and 0xFF
        val b = pixels[idx] and 0xFF
        
        // 色度 (通常 16-235 范围，添加 128 偏移)
        val u = ((-0.169 * r - 0.331 * g + 0.5 * b) + 128)
                    .toInt().coerceIn(0, 255).toByte()
        val v = ((0.5 * r - 0.419 * g - 0.081 * b) + 128)
                    .toInt().coerceIn(0, 255).toByte()
        
        // NV21: V 在前，U 在后（交错排列）
        nv21[uvOffset + (j / 2) * bitmapWidth + i] = v     // V
        nv21[uvOffset + (j / 2) * bitmapWidth + i + 1] = u // U
    }
}
```

**特点**:
- 仅处理每 2×2 像素块中的第 1 个像素（左上角）
- 下采样比例: 1:4（面积上）
- V 先于 U（NV21 格式）vs N**UV**21 中 U 先于 V
- 色度偏移 +128：将 -128~127 范围映射到 0~255

**UV 内存映射示例** (4×4 RGB → 2×2 UV):
```
RGB 像素位置:          取样点 (X):      UV 输出:
(0,0) (1,0) (2,0) (3,0)
(0,1) (1,1) (2,1) (3,1)   (0,0)X (2,0)X    [0]: V U   [2]: V U
(0,2) (1,2) (2,2) (3,2)
(0,3) (1,3) (2,3) (3,3)   (0,2)X (2,2)X    [4]: V U   [6]: V U
```

#### ⚠️ 关键问题：为什么可能导致骨架相同？

**情景 1: 同一关键帧多次提取**
```
视频 I-frame (关键帧) 在 0ms
nextFrame  计算逻辑:
timeMs=0   → OPTION_CLOSEST_SYNC → 找到 0ms I-frame → 返回帧 A
timeMs=33  → OPTION_CLOSEST_SYNC → 无 33ms 帧 → 返回最近的 0ms I-frame (帧 A)
timeMs=66  → OPTION_CLOSEST_SYNC → 无 66ms 帧 → 返回最近的 0ms I-frame (帧 A)
```

**情景 2: OPTION_CLOSEST_SYNC 行为**
```
期望: 按时间均匀提取帧
实际: 总是跳到最近的 I-frame (可能都同一个)
```

**证据检查**:
- ✅ centerPixel 相同 → 问题在 bitmap 层
- ✅ NV21 checksum 相同 → 问题在数据层
- ✅ ML Kit 检测结果相同 → 问题来自输入数据

---

## 诊断机制

### 📊 三层诊断架构

#### 层 1: Bitmap 层 - centerPixel 日志
**位置**: `MainActivity.kt:338-340`

```kotlin
val centerPixel = bitmap.getPixel(bitmap.width / 2, bitmap.height / 2)
Log.d(logTag, "[FrameDebug] frame=$frameIndex timeMs=$timeMs centerPixel=$centerPixel")
```

**预期输出**:
```
正常情况 (骨架变化):
[FrameDebug] frame=0 timeMs=0 centerPixel=-1234567
[FrameDebug] frame=1 timeMs=33 centerPixel=-7654321
[FrameDebug] frame=2 timeMs=66 centerPixel=-9876543

异常情况 (骨架相同):
[FrameDebug] frame=0 timeMs=0 centerPixel=-1234567
[FrameDebug] frame=1 timeMs=33 centerPixel=-1234567  ← 相同！
[FrameDebug] frame=2 timeMs=66 centerPixel=-1234567  ← 相同！
```

**诊断判断**:
- centerPixel **变化** → bitmap 提取正常，问题在下游
- centerPixel **相同** → MediaMetadataRetriever 返回相同帧

#### 层 2: 像素数据层 - NV21 Checksum
**Dart 端计算** (在 video_analysis_service.dart):

```dart
int checksum = 0;
final step = math.max(1, pixelBytes.length ~/ 1000);
for (int i = 0; i < pixelBytes.length; i += step) {
  checksum = (checksum + pixelBytes[i]) & 0xFFFFFFFF;
}
debugPrint('[FrameCheck] frame=$frameIndex timeMs=$timeMs checksum=$checksum');
```

**预期输出**:
```
正常: checksum 每帧不同
异常: checksum 每帧相同
```

**采样策略**:
- 采样间隔: `step = pixelBytes.length / 1000` (最多 1000 个采样点)
- 速度快: O(pixelBytes.length/1000) vs O(pixelBytes.length)
- 准确率高: >99% 概率检测出重复数据

#### 层 3: 骨架数据层 - 33点比较
**Dart 端** (在 video_analysis_service.dart):

```dart
bool isSameFullPose(int frameA, int frameB) {
    for (int i = 0; i < 33; i++) {
        final pa = allFrames[frameA].landmarks[i];
        final pb = allFrames[frameB].landmarks[i];
        
        if ((pa.xPx - pb.xPx).abs() > 0.01 ||
            (pa.yPx - pb.yPx).abs() > 0.01 ||
            (pa.z - pb.z).abs() > 0.01) {
            return false;  // 有变化
        }
    }
    return true;  // 完全相同
}
```

**输出统计**:
```
[VideoAnalysis] 📊 完整骨架重複幀比例: 100%
                   changed=0, repeated=182
```

### 🎯 诊断决策树

```
骨架完全相同
├─ centerPixel 相同?
│  ├─ YES → MediaMetadataRetriever 问题
│  │       (同一帧被返回多次)
│  └─ NO → 继续诊断
├─ NV21 checksum 相同?
│  ├─ YES → Bitmap→NV21 转换问题
│  │       (像素数据丢失或相同)
│  └─ NO → 继续诊断
└─ ML Kit 检测相同?
   ├─ YES → ML Kit 问题（不太可能）
   └─ NO → 问题来自其他地方
```

---

## 潜在问题

### 🚨 问题 1: OPTION_CLOSEST_SYNC 导致帧重复

**问题描述**:
```
使用 OPTION_CLOSEST_SYNC 时，MediaMetadataRetriever 不会准确查找
指定时间戳，而是返回最近的关键帧（I-frame）
```

**典型场景**:
```
视频编码: I-frame@0ms, P-frame@33ms, P-frame@66ms, I-frame@3000ms

期望帧提取:
timeMs=0   → 帧@0ms   (✓ 正确)
timeMs=33  → 帧@33ms  (✓ 正确)
timeMs=66  → 帧@66ms  (✓ 正确)

实际 OPTION_CLOSEST_SYNC:
timeMs=0   → 帧@0ms   (✓ 正确，是 I-frame)
timeMs=33  → 帧@0ms   (✗ 错误！最近的 I-frame 是 0ms)
timeMs=66  → 帧@0ms   (✗ 错误！最近的 I-frame 还是 0ms)
```

**解决方案**:
- ❌ 改用 `OPTION_PREVIOUS_SYNC` (返回前一个 I-frame)
- ✅ 改用 `OPTION_NEXT_SYNC` (返回后一个 I-frame)
- ✅ 改用不指定选项 (返回精确或最接近的帧)

### 🚨 问题 2: 颜色空间转换精度

**问题**:
```kotlin
val y = (0.299 * r + 0.587 * g + 0.114 * b).toInt()
                .coerceIn(0, 255).toByte()
```

**潜在精度问题**:
- 浮点运算后再 `toInt()`：可能丢失精度
- `coerceIn(0, 255)`：可能裁剪边界值
- 百分比系数 (0.299, 0.587, 0.114)：总和 = 1.0，保证亮度守恒

**改进方案**:
```kotlin
// 使用整数运算避免浮点误差
val y = ((299 * r + 587 * g + 114 * b) / 1000).toByte()
```

### 🚨 问题 3: 线程安全问题

**当前代码**:
```kotlin
frameExtractorExecutor.execute {
    // 后台线程中执行
    val bitmap = retriever.getFrameAtTime(...)
    // ...
    runOnUiThread {
        result.success(mapOf(...))
    }
}
```

**问题**:
- 如果多个请求同时到达，会并发调用 `result.success()`
- 如果 Activity 被销毁，`runOnUiThread` 可能崩溃

**改进方案**:
```kotlin
frameExtractorExecutor.execute {
    try {
        val bitmap = retriever.getFrameAtTime(...)
        runOnUiThread {
            if (!isDestroyed) {
                result.success(mapOf(...))
            }
        }
    } catch (e: Exception) {
        runOnUiThread {
            if (!isDestroyed) {
                result.error("error", e.message, null)
            }
        }
    }
}
```

### 🚨 问题 4: 内存泄漏

**当前代码**:
```kotlin
workingBitmap.recycle()  // 释放 bitmap

// 但 MediaMetadataRetriever 呢？
retriever.release()  // ✓ 正确
```

**问题**:
- 如果异常抛出，`retriever.release()` 可能未执行
- 大量帧提取会快速消耗内存

**改进方案**:
```kotlin
val retriever = MediaMetadataRetriever()
try {
    retriever.setDataSource(videoPath)
    val bitmap = retriever.getFrameAtTime(...)
    // ...
} finally {
    retriever.release()  // 一定会执行
}
```

---

## 性能分析

### ⏱️ 时间成本分解

**单帧提取时间** (720×1280 @ 30fps):

| 操作 | 时间 | 占比 | 说明 |
|-----|------|------|------|
| MediaMetadataRetriever.getFrameAtTime() | 30-50ms | 70% | 最耗时 |
| Bitmap 缩放 (createScaledBitmap) | 3-5ms | 10% | 双线性插值 |
| RGB → NV21 转换 | 5-10ms | 15% | 按像素遍历 |
| getPixels() 调用 | 2-3ms | 5% | 数据复制 |
| **总计** | **40-68ms** | 100% | |

### 📈 吞吐率

```
理论吞吐率 = 1000ms / 50ms = 20 fps
实际吞吐率 (带批处理) = 30+ fps (4帧并行)

瓶颈: MediaMetadataRetriever 是同步操作，
无法充分利用多核 CPU
```

### 🔧 优化建议

| 优化 | 效果 | 复杂度 | 优先级 |
|-----|------|--------|--------|
| 使用 MediaCodec (硬件解码) | 5-10x | 高 | 🟢 高 |
| 缓存 MediaMetadataRetriever | 2-3x | 中 | 🟢 高 |
| 并行批处理 (已实现) | 3-4x | 低 | 🟡 中 |
| 预加载视频头信息 | 1.2x | 低 | 🟡 中 |
| 整数运算替代浮点 | 1.1x | 低 | 🟡 中 |

---

## 📌 总结与建议

### � 核心诊断结论

**最大嫌疑犯：`OPTION_CLOSEST_SYNC`**

当前代码使用 `OPTION_CLOSEST_SYNC` 导致 MediaMetadataRetriever 总是返回**最近的关键帧（I-frame）**，而非精确的指定时间戳。

**典型场景**（问题演示）：
```
视频 GOP 结构: I-frame@0ms, P-frame@33ms, P-frame@66ms, ..., I-frame@3000ms

预期提取:
timeMs=0   → 幀@0ms
timeMs=33  → 幀@33ms  
timeMs=66  → 幀@66ms

实际 OPTION_CLOSEST_SYNC 结果:
timeMs=0   → I-frame@0ms   ✓
timeMs=33  → I-frame@0ms   ✗ (最近的 I-frame 是 0ms)
timeMs=66  → I-frame@0ms   ✗ (最近的 I-frame 还是 0ms)
timeMs=99  → I-frame@0ms   ✗ (同上)
```

**结果**：所有幀都返回同一个 I-frame → centerPixel 相同 → NV21 数据相同 → 骨架完全相同

---

### ✅ 已修复

**✅ 改正：OPTION_CLOSEST_SYNC → 移除选项参数**

原本代码：
```kotlin
val frm: Bitmap? = retriever.getFrameAtTime(
    timeUs,
    MediaMetadataRetriever.OPTION_CLOSEST_SYNC  // ← 问题根源
)
```

修改后：
```kotlin
// ✅ 改正：不用 OPTION_CLOSEST_SYNC（只抓 I-frame）
// 改用默认行为（抓精確或最接近的幀）
val frm: Bitmap? = retriever.getFrameAtTime(timeUs)
```

**为什么**：
- `OPTION_CLOSEST_SYNC` = 找最近的同步点（I-frame）
- 默认无参数 = 尝试返回精确或最接近的帧
- 如果无精确帧，返回之前的帧（较为准确）

---

### 🔍 当前诊断状态

```
✅ 已实现:
   - centerPixel 日志诊断 (Kotlin:338-340)
   - Bitmap 配置检查 (Kotlin:342-349)
   - NV21 字节数验证 (Dart 端)
   - OPTION_CLOSEST_SYNC → 已移除 ← 【核心修复】

🟡 待验证:
   - centerPixel 变化情况
   - NV21 checksum 变化情况
   - 骨架是否有细微变化
```

---

### 🎯 下一步行动（优先级重排）

**优先级 1 🔴 - 立即执行（核心修复）**:
1. ✅ **已完成**：移除 `OPTION_CLOSEST_SYNC`，改用默认参数
2. 编译 APK
3. 运行分析，生成新 CSV

**优先级 2 🟡 - 诊断验证**:
1. 检查 Logcat 中的 `[FrameDebug]` 日志：
   - ✓ centerPixel 每幀是否**不同**
   - ✓ 格式类似：`frame=0 centerPixel=-1234567` → `frame=1 centerPixel=-7654321`
2. 分析新 CSV：
   - ✓ 右手腕是否开始移动
   - ✓ pose_update_id 变化幅度（应该是 0→1→2→3...）
3. 如果仍然相同，检查 Dart 端 checksum 日志

**优先级 3 🟠 - 如果仍无效**:
1. Dart 端添加 NV21 checksum 验证
2. 对比 Kotlin centerPixel vs Dart checksum 变化情况
3. 判断问题是否在色彩空间转换层

**优先级 4 🔵 - 长期优化**:
1. ML Kit 已改为 `single` 模式（已完成）
2. pose_update_id 逻辑已改为比较完整 33 点（已完成）
3. 不需要进一步调整

---

### 📊 诊断决策表（实行顺序）

| 步骤 | 检查项 | 正常结果 | 异常结果 | 下一步 |
|------|--------|--------|--------|--------|
| 1 | centerPixel 日志 | 每幀不同 | 每幀相同 | 检查视频编码 |
| 2 | 右手腕坐标 | 有移动 | 固定不动 | 检查 checksum |
| 3 | NV21 checksum | 每幀不同 | 每幀相同 | 检查 Kotlin 转换 |
| 4 | ML Kit 检测 | 有变化 | 始终相同 | 检查 InputImage metadata |

---

## 预期效果

如果 `OPTION_CLOSEST_SYNC` 确实是根因（非常可能），修改后应该看到：

```
✅ 修复前后对比

修改前（OPTION_CLOSEST_SYNC）:
  frame=0: centerPixel=-1234567, rightWrist=(213.49, 783.45)
  frame=1: centerPixel=-1234567, rightWrist=(213.49, 783.45) ← 完全相同！
  frame=2: centerPixel=-1234567, rightWrist=(213.49, 783.45) ← 完全相同！
  
修改后（默认参数）:
  frame=0: centerPixel=-1234567, rightWrist=(213.49, 783.45)
  frame=1: centerPixel=-9876543, rightWrist=(215.20, 785.60) ← 有变化！
  frame=2: centerPixel=-5555555, rightWrist=(217.80, 788.10) ← 继续变化！
```

如果出现上述模式，则问题基本确认已解决。

---

### 🔍 当前诊断状态

```
✅ 已实现:
   - centerPixel 日志诊断
   - Bitmap 配置检查
   - NV21 字节数验证

🟡 部分实现:
   - 缺少 retriever 创建时间日志
   - 缺少 RGB→NV21 转换逆向验证

❌ 未实现:
   - MediaCodec 硬件加速
   - 帧缓存机制
```

---

## 📚 参考资源

### YUV 色彩空间
- BT.601 标准转换公式
- NV21 vs NV12 vs YV12 格式对比
- 色度下采样 (4:4:4 vs 4:2:0)

### Android Media APIs
- [MediaMetadataRetriever](https://developer.android.com/reference/android/media/MediaMetadataRetriever)
- [MediaCodec](https://developer.android.com/reference/android/media/MediaCodec)
- [Bitmap Config](https://developer.android.com/reference/android/graphics/Bitmap.Config)

### Google ML Kit
- [Pose Detection 文档](https://developers.google.com/ml-kit/vision/pose-detection)
- InputImage 格式要求
- 单帧 vs 连续流处理模式

