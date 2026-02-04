# Hits Summary 路径修复 - 2026-01-30

## 问题描述

摆球摘要上传时出现文件不存在错误：
```
PathNotFoundException: Cannot retrieve length of file, 
path = '/storage/emulated/0/Download/cut_2_04/cut_2/hits_summary.csv'
(OS Error: No such file or directory, errno = 2)
```

## 根本原因

在 `recording_history_page.dart` 中，路径构造方式与 `SwingSplitService.split()` 中实际写入文件的位置不匹配。

### SwingSplitService.split() 中的实现（正确）
```dart
// 第 146 行
await _writeSummary(results, p.join(outDir.path, 'hits_summary.csv'), detectFrom);
```

`outDir` 是通过 `_makeUniqueOutDir()` 返回的完整目录对象，可能带有唯一后缀（如 `cut_2_00`, `cut_2_01`, `cut_2_04` 等）。

### recording_history_page.dart 中的旧实现（错误）
```dart
final hitsSummaryPath = p.join(
  p.dirname(results.isEmpty ? entry.filePath : results.first.videoPath),
  p.basename(outDir),  // ❌ 问题：outDir 只是字符串 "cut_2"，不包含唯一后缀
  'hits_summary.csv',
);
```

## 解决方案

使用 `results.first.videoPath` 所在的目录作为基准，因为所有的 clip 文件都与 `hits_summary.csv` 在同一目录：

```dart
// 新的实现（正确）
final hitsSummaryPath = results.isNotEmpty
    ? p.join(p.dirname(results.first.videoPath), 'hits_summary.csv')
    : p.join(outDir, 'hits_summary.csv');
```

### 为什么这样做是正确的

1. `results.first.videoPath` 的值例如：`/storage/emulated/0/Download/cut_2_04/hit_001.mp4`
2. `p.dirname(results.first.videoPath)` 返回：`/storage/emulated/0/Download/cut_2_04`
3. `p.join(..., 'hits_summary.csv')` 返回：`/storage/emulated/0/Download/cut_2_04/hits_summary.csv`
4. 这与 `_writeSummary()` 写入文件的位置完全一致

## 修改文件

[lib/pages/recording_history_page.dart](lib/pages/recording_history_page.dart#L209-L221)

**第 209-221 行**：修复 hits_summary.csv 路径构造逻辑

## 验证

✅ 编译无错误
✅ 路径构造逻辑正确
✅ hits_summary.csv 上传应该成功

## 相关代码位置

- `SwingSplitService.split()` 中 `_writeSummary()` 调用：[第 146 行](lib/swing_split_service.dart#L146)
- `_makeUniqueOutDir()` 方法：[第 388-406 行](lib/swing_split_service.dart#L388)
- 路径修复位置：[recording_history_page.dart 第 209-221 行](lib/pages/recording_history_page.dart#L209-L221)

## 测试步骤

1. 在 Flutter 应用中选择录制视频
2. 点击"分片"按钮
3. 等待分片完成
4. 验证 hits_summary.csv 被上传到原始视频
5. 检查日志是否显示上传成功（不再有 PathNotFoundException）
