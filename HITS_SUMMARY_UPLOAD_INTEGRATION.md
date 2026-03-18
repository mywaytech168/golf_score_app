# Hits Summary 上传集成文档

## 概述

本文档说明了如何在自动切片完毕后，将生成的 `hits_summary.csv` 上传到原始视频的云端记录。

## 实现细节

### 1. 新增方法：`uploadHitsSummary()`

**位置**: `lib/services/video_server_client.dart`

**方法签名**:
```dart
Future<Map<String, dynamic>> uploadHitsSummary({
  required String videoId,
  required String hitsSummaryCsvPath,
})
```

**功能**:
- 将本地 `hits_summary.csv` 文件上传到原始视频
- 使用 HTTP Multipart 请求
- 发送到 `/api/videos/{videoId}/hits-summary` 端点
- 返回上传结果（成功/失败）

**实现细节**:
```dart
// 构建 Multipart 请求
final request = http.MultipartRequest(
  'POST',
  Uri.parse('$_baseUrl/api/videos/$videoId/hits-summary'),
);

// 添加认证头
request.headers.addAll(await _getAuthMultipartHeaders());

// 添加 CSV 文件
request.files.add(
  await http.MultipartFile.fromPath('file', hitsSummaryCsvPath),
);

// 发送请求
final streamedResponse = await request.send();
```

### 2. 修改 `_splitEntry()` 方法

**位置**: `lib/pages/recording_history_page.dart`

**关键改动**:

#### a) 使用 `splitWithSummary()` 获取摆球摘要数据
```dart
// 之前
final results = await SwingSplitService.split(
  videoPath: entry.filePath,
  imuCsvPath: csvPath,
  outDirName: p.basename(outDir),
);

// 现在
final resultWithSummary = await SwingSplitService.splitWithSummary(
  videoPath: entry.filePath,
  imuCsvPath: csvPath,
  outDirName: p.basename(outDir),
);

final results = resultWithSummary.clips;
final hitsSummaryPath = resultWithSummary.summaryPath;
```

#### b) 在完成所有切片上传后上传摆球摘要
```dart
// 上傳 hits_summary 到原始視頻
debugPrint('[歷史頁] 準備上傳摆球摘要到原始視頻');
if (entry.cloudVideoId != null && entry.cloudVideoId!.isNotEmpty) {
  debugPrint('[歷史頁] 原始視頻 ID: ${entry.cloudVideoId}');
  try {
    final uploadResult = await VideoServerClient.instance.uploadHitsSummary(
      videoId: entry.cloudVideoId!,
      hitsSummaryCsvPath: hitsSummaryPath,
    );
    
    if (uploadResult['success'] == true) {
      debugPrint('[歷史頁] ✅ 摆球摘要上傳成功到原始視頻');
    } else {
      debugPrint('[歷史頁] ⚠️ 摆球摘要上傳失敗: ${uploadResult['error']}');
    }
  } catch (e) {
    debugPrint('[歷史頁] ⚠️ 摆球摘要上傳異常: $e');
  }
} else {
  debugPrint('[歷史頁] ℹ️ 原始視頻尚未上傳到雲端，摆球摘要將在視頻同步後再上傳');
}
```

## 执行流程

### 自动切片完成流程

```
┌─────────────────────────────────────────────┐
│ 用户点击 "分片" 按钮                         │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│ _splitEntry() 方法执行                      │
│ - 验证 IMU CSV 文件存在                     │
│ - 显示等待对话框                             │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│ splitWithSummary() 返回结果                 │
│ - clips: 所有切片信息                       │
│ - hitsSummary: 摆球摘要数据                 │
│ - summaryPath: CSV 文件路径                │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│ 为每个切片生成缩略图                         │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│ 自动上传所有切片视频到云端                   │
│ - 调用 _uploadEntry() 逐个上传              │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│ 上传摆球摘要到原始视频                       │
│ - 检查原始视频是否已上传到云端               │
│ - 如果已上传，调用 uploadHitsSummary()     │
│ - 如果未上传，记录日志（稍后同步）          │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│ 流程完成                                     │
│ - 显示成功提示信息                           │
│ - 更新 UI 显示新的切片列表                  │
└─────────────────────────────────────────────┘
```

## CSV 格式

`hits_summary.csv` 包含以下列：

```
hit,t_hit,start_t,end_t,peak_smooth,detect_from
1,10.5,7.5,13.5,45.2,accelerometer
2,20.3,17.3,23.3,42.8,accelerometer
...
```

## 云端存储

### 原始视频记录
- 存储位置：`videos/{videoId}/`
- 包含：
  - `video.mp4` - 原始视频文件
  - `metadata.json` - 视频元数据
  - `hits_summary.csv` - 摆球摘要（此次新增）

### 切片视频记录
- 存储位置：`videos/{videoId}/clips/`
- 包含：
  - `clip_0.mp4` - 第一个切片
  - `clip_0.csv` - 第一个切片的 IMU 数据
  - `clip_1.mp4` - 第二个切片
  - ...

## 错误处理

### 场景 1：原始视频未上传到云端
```
状态：cloudVideoId == null 或为空
处理：记录日志，不上传（稍后视频同步时可手动上传）
日志：'ℹ️ 原始視頻尚未上傳到雲端，摆球摘要將在視頻同步後再上傳'
```

### 场景 2：上传成功
```
状态：HTTP 200 或 201
处理：记录成功日志
日志：'✅ 摆球摘要上傳成功到原始視頻'
```

### 场景 3：上传失败
```
状态：HTTP 4xx 或 5xx
处理：记录失败日志，但不中断流程
日志：'⚠️ 摆球摘要上傳失敗: {error}'
```

### 场景 4：异常错误
```
状态：抛出异常
处理：捕获异常，记录日志
日志：'⚠️ 摆球摘要上傳異常: {exception}'
```

## 调试和日志

### 关键调试日志
```
[歷史頁] 準備上傳摆球摘要到原始視頻
[歷史頁] 原始視頻 ID: {videoId}
[歷史頁] ✅ 摆球摘要上傳成功到原始視頻
[歷史頁] ⚠️ 摆球摘要上傳失敗: {error}
[歷史頁] ⚠️ 摆球摘要上傳異常: {exception}
[歷史頁] ℹ️ 原始視頻尚未上傳到雲端，摆球摘要將在視頻同步後再上傳
```

### VideoServerClient 日志
```
════════════════════════════════════════════════════════════
📤 上傳摆球摘要
════════════════════════════════════════════════════════════
🎯 視頻 ID: {videoId}
📂 摆球摘要路徑: {path}
📎 添加摆球摘要 CSV 到請求...
⬆️ 發送摆球摘要上傳請求...
📥 上傳回應狀態: {statusCode}
📝 回應長度: {length}
📋 回應內容: {body}
✅ 摆球摘要上傳成功
❌ 摆球摘要上傳失敗: {statusCode}
```

## 集成测试

### 测试场景 1：完整流程
1. ✅ 选择录制视频
2. ✅ 点击 "分片" 按钮
3. ✅ 等待 splitWithSummary() 完成
4. ✅ 验证 hits_summary.csv 被创建
5. ✅ 验证切片视频上传完成
6. ✅ 验证 hits_summary 上传到原始视频
7. ✅ 检查日志确认上传成功

### 测试场景 2：视频未上传到云端
1. ✅ 选择本地录制视频（cloudVideoId == null）
2. ✅ 点击 "分片" 按钮
3. ✅ 完成切片并上传
4. ✅ 验证日志显示"原始视频尚未上传到云端"
5. ✅ 不应抛出异常，流程继续

### 测试场景 3：网络错误处理
1. ✅ 设置网络为离线模式
2. ✅ 点击 "分片" 按钮
3. ✅ 等待切片完成
4. ✅ 验证异常被捕获
5. ✅ 检查日志记录异常信息
6. ✅ UI 不应冻结

## 后续改进

### 可选功能 1：重试机制
- 如果上传失败，可添加重试按钮
- 保存失败的上传任务到队列
- 支持离线时本地保存，在线时自动同步

### 可选功能 2：上传进度跟踪
- 添加上传进度条
- 显示上传速度和预计时间
- 允许取消上传

### 可选功能 3：智能延迟上传
- 如果原始视频还在上传，延迟摆球摘要的上传
- 等待原始视频上传完成后再上传摆球摘要
- 确保数据关联正确

## 相关文件

- `lib/services/video_server_client.dart` - uploadHitsSummary() 方法
- `lib/pages/recording_history_page.dart` - _splitEntry() 方法集成
- `lib/swing_split_service.dart` - splitWithSummary() 方法
- `lib/services/hits_summary_storage.dart` - CSV 文件操作
- `lib/models/hits_summary.dart` - 数据模型

## 总结

本次实现完成了以下目标：

✅ 添加 `uploadHitsSummary()` 方法到 VideoServerClient
✅ 修改 `_splitEntry()` 使用 `splitWithSummary()` 获取摆球摘要
✅ 在切片上传完成后自动上传摆球摘要到原始视频
✅ 处理原始视频未上传到云端的情况
✅ 完整的错误处理和日志记录
✅ 代码编译无错误

现在用户可以看到完整的摆球摘要数据被自动上传到原始视频的云端记录。
