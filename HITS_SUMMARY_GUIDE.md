# 手机版 Hits Summary 实现指南

## 概述

为手机版（Flutter）应用实现了与Python版本类似的 `hits_summary` 功能，用于在摆球切片后自动生成和显示摆球摘要数据。

## 核心组件

### 1. **HitsSummary 模型类** (`lib/models/hits_summary.dart`)

数据模型类，代表单个摆球的信息：

```dart
class HitsSummary {
  final String hit;              // 摆球编号，例如 "hit_001"
  final double tHit;             // 摆球的时间戳（秒）
  final double startT;           // 切片视频的开始时间
  final double endT;             // 切片视频的结束时间
  final double peakSmooth;       // 加速度峰值（G）
  final String? detectFrom;      // 检测来源，例如 "Codi2"
}
```

主要方法：
- `fromCsvLine()` - 从 CSV 行解析数据
- `toCsvLine()` - 转换为 CSV 行
- `formattedHitTime` - 获取友好的时间显示格式
- `duration` - 获取摆球时长

### 2. **HitsSummaryStorage 服务** (`lib/services/hits_summary_storage.dart`)

管理 `hits_summary.csv` 文件的读写操作：

```dart
// 加载摆球摘要
final summaries = await HitsSummaryStorage.loadHitsSummary('/path/to/hits_summary.csv');

// 保存摆球摘要
await HitsSummaryStorage.saveHitsSummary(summaries, '/path/to/hits_summary.csv');

// 删除摆球摘要文件
await HitsSummaryStorage.deleteHitsSummary('/path/to/hits_summary.csv');

// 获取统计信息
final stats = HitsSummaryStorage.getStatistics(summaries);
// {
//   'total': 5,
//   'avgPeak': 45.2,
//   'maxPeak': 65.3,
//   'minPeak': 32.1,
//   'totalDuration': 30.5,
// }
```

### 3. **HitsSummaryWidget** (`lib/widgets/hits_summary_widget.dart`)

提供多个 UI 组件用于显示摆球数据：

#### **HitsSummaryWidget**
显示摆球列表的卡片视图：

```dart
HitsSummaryWidget(
  hitsSummary: summaries,
  showDetails: true,
  onHitTap: (hit) {
    print('点击了摆球: ${hit.hit}');
  },
)
```

#### **HitsSummaryExpansionTile**
带展开/折叠功能的摆球摘要面板（推荐用于历史页面）：

```dart
HitsSummaryExpansionTile(
  hitsSummary: summaries,
  title: '摆球摘要',
  initiallyExpanded: false,
  onHitTap: (hit) {
    // 处理点击事件
  },
)
```

### 4. **SwingSplitService 更新** (`lib/swing_split_service.dart`)

新增方法和模型：

#### **SwingSplitResultWithSummary**
包含切片结果和摆球摘要的完整结果对象：

```dart
class SwingSplitResultWithSummary {
  final List<SwingClipResult> clips;        // 所有生成的切片
  final List<HitsSummary> hitsSummary;      // 摆球摘要列表
  final String summaryPath;                 // 摘要 CSV 文件路径
}
```

#### **splitWithSummary() 方法**
带摆球摘要的分割方法：

```dart
final result = await SwingSplitService.splitWithSummary(
  videoPath: '/path/to/video.mp4',
  imuCsvPath: '/path/to/imu.csv',
  detectFrom: 'Codi2',  // 新参数：检测来源
);

// 访问摆球摘要
for (final hit in result.hitsSummary) {
  print('${hit.hit}: ${hit.formattedHitTime} (Peak: ${hit.peakSmooth}G)');
}
```

#### **split() 方法增强**
原有的 `split()` 方法现在也支持 `detectFrom` 参数：

```dart
final clips = await SwingSplitService.split(
  videoPath: '/path/to/video.mp4',
  imuCsvPath: '/path/to/imu.csv',
  detectFrom: 'Codi2',  // 新增参数
);
```

## 集成到录影历史页面

摆球摘要已自动集成到 `RecordingHistoryPage` 中：

```dart
// 在历史记录卡片中显示摆球摘要
// 会自动从 cut/ 目录加载 hits_summary.csv
HitsSummaryExpansionTile(
  hitsSummary: hitsSummary,
  title: '摆球摘要',
  initiallyExpanded: false,
)
```

每个录影记录的卡片底部现在会显示一个可展开的摆球摘要部分，点击时会加载并显示该录影对应的所有摆球数据。

## CSV 文件格式

生成的 `hits_summary.csv` 格式：

```csv
hit,t_hit,start_t,end_t,peak_smooth,detect_from
hit_001,1.234567,0.123456,6.234567,45.23,Codi2
hit_002,8.567890,5.567890,13.567890,52.45,Codi2
...
```

## 使用示例

### 示例 1：加载并显示摆球摘要

```dart
final csvPath = '/path/to/cut/hits_summary.csv';
final summaries = await HitsSummaryStorage.loadHitsSummary(csvPath);

// 显示摆球列表
HitsSummaryWidget(
  hitsSummary: summaries,
  showDetails: true,
)
```

### 示例 2：执行分片并获取摆球摘要

```dart
// 使用新的 splitWithSummary 方法
final result = await SwingSplitService.splitWithSummary(
  videoPath: videoPath,
  imuCsvPath: csvPath,
  windowBeforeSec: 3.0,
  windowAfterSec: 1.0,
  detectFrom: 'Codi2',
);

// 访问摆球摘要
print('共检测到 ${result.hitsSummary.length} 个摆球');
for (final hit in result.hitsSummary) {
  print('${hit.hit}: ${hit.formattedHitTime}');
}
```

### 示例 3：获取统计信息

```dart
final stats = HitsSummaryStorage.getStatistics(summaries);
print('平均峰值: ${stats['avgPeak']}G');
print('最大峰值: ${stats['maxPeak']}G');
print('总摆球数: ${stats['total']}');
```

## 与Python版本的对应关系

| Python 版本 | Flutter 版本 | 说明 |
|-----------|------------|------|
| `hits_summary.csv` | `HitsSummary` 模型 + `hits_summary_storage.dart` | 数据模型和存储 |
| CSV 字段解析 | `HitsSummary.fromCsvLine()` | CSV 行解析 |
| 摆球列表显示 | `HitsSummaryWidget` | UI 组件 |
| 文件管理 | `HitsSummaryStorage` | 文件读写操作 |

## 文件位置

```
lib/
├── models/
│   └── hits_summary.dart          # 数据模型
├── services/
│   └── hits_summary_storage.dart  # 存储服务
├── widgets/
│   └── hits_summary_widget.dart   # UI 组件
└── pages/
    └── recording_history_page.dart # 集成示例
```

## 特点

✅ 与 Python 版本格式兼容  
✅ 自动生成和管理 CSV 文件  
✅ 完整的 UI 组件（卡片、展开面板）  
✅ 统计信息计算  
✅ 错误处理和日志记录  
✅ 已集成到历史页面  

## 后续扩展建议

1. **导出功能** - 支持导出摆球数据为 Excel/PDF
2. **可视化** - 绘制摆球峰值图表
3. **分析** - 计算摆球频率、速度等统计指标
4. **比较** - 对比不同录影的摆球数据
5. **标签** - 为摆球添加备注和分类标签
