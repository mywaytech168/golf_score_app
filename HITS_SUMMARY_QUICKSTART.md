# Hits Summary 快速开始指南

## 🎯 快速开始（5 分钟）

### 1. 查看摆球摘要（无需编码）

打开应用 → 录影历史 → 点击任意录影卡片 → 展开"摆球摘要"面板

### 2. 在代码中使用 Hits Summary

#### 方式 A：自动分割并获取摆球（推荐）

```dart
import 'package:golf_score_app/services/swing_split_service.dart';

// 执行分割并获取摆球摘要
final result = await SwingSplitService.splitWithSummary(
  videoPath: '/path/to/video.mp4',
  imuCsvPath: '/path/to/imu.csv',
  detectFrom: 'Codi2',  // 检测来源
);

// 使用结果
print('摆球总数: ${result.hitsSummary.length}');
for (final hit in result.hitsSummary) {
  print('${hit.hit}: ${hit.formattedHitTime} - 峰值: ${hit.peakSmooth}G');
}
```

#### 方式 B：加载已有的摆球数据

```dart
import 'package:golf_score_app/services/hits_summary_storage.dart';

// 加载摆球数据
final hits = await HitsSummaryStorage.loadHitsSummary(
  '/path/to/cut/hits_summary.csv'
);

// 显示摆球列表
print('已加载 ${hits.length} 个摆球数据');
```

#### 方式 C：显示摆球 UI

```dart
import 'package:golf_score_app/widgets/hits_summary_widget.dart';

// 在 build 方法中
@override
Widget build(BuildContext context) {
  return HitsSummaryExpansionTile(
    hitsSummary: hitsSummary,
    title: '摆球摘要',
    onHitTap: (hit) {
      print('点击了: ${hit.hit}');
    },
  );
}
```

## 📚 核心 API 参考

### HitsSummary 类

```dart
// 属性
hit          // String - 摆球编号 (hit_001, hit_002, ...)
tHit         // double - 摆球时间戳（秒）
startT       // double - 切片开始时间
endT         // double - 切片结束时间
peakSmooth   // double - 加速度峰值（G）
detectFrom   // String? - 检测来源（如 Codi2）

// 计算属性
hitNumber       // int - 摆球编号数字
duration        // double - 时长（秒）
formattedHitTime // String - 格式化时间 (mm:ss.ms)

// 方法
toCsvLine()     // String - 转换为 CSV 行
copyWith()      // HitsSummary - 创建副本
```

### HitsSummaryStorage 类

```dart
// 加载
loadHitsSummary(String csvPath)
  → Future<List<HitsSummary>>

// 保存
saveHitsSummary(List<HitsSummary> hits, String csvPath)
  → Future<void>

// 删除
deleteHitsSummary(String csvPath)
  → Future<void>

// 统计
getStatistics(List<HitsSummary> hits)
  → Map<String, dynamic>
  // {
  //   'total': 5,          // 摆球总数
  //   'avgPeak': 45.2,     // 平均峰值
  //   'maxPeak': 65.3,     // 最大峰值
  //   'minPeak': 32.1,     // 最小峰值
  //   'totalDuration': 30.5, // 总时长
  // }

// 路径管理
getHitsSummaryPath(String path)
  → String
getHitsSummaryPathFromVideo(String videoPath)
  → String
```

### SwingSplitService 更新

```dart
// 新方法：带摆球摘要的分割
splitWithSummary({
  required String videoPath,
  required String imuCsvPath,
  double windowBeforeSec = 3.0,
  double windowAfterSec = 1.0,
  double smoothWinSec = 0.05,
  double threshG = 20.0,
  double minIntervalSec = 1.0,
  double? prominenceG,
  String outDirName = 'cut',
  bool forceSar1 = true,
  String? detectFrom,  // 新参数
}) → Future<SwingSplitResultWithSummary>

// 增强的原有方法
split({
  // ... 原有参数 ...
  String? detectFrom,  // 新参数
}) → Future<List<SwingClipResult>>
```

## 📊 数据示例

### HitsSummary 数据示例

```dart
HitsSummary(
  hit: 'hit_001',
  tHit: 1.234567,
  startT: 0.123456,
  endT: 6.234567,
  peakSmooth: 45.23,
  detectFrom: 'Codi2',
)

// 输出
hit.hitNumber        // 1
hit.duration         // 6.111111
hit.formattedHitTime // "00:01.23"
hit.toCsvLine()      // "hit_001,1.234567,0.123456,6.234567,45.230000,Codi2"
```

## 🎨 UI 组件演示

### 1. HitsSummaryWidget (基础列表)

```dart
HitsSummaryWidget(
  hitsSummary: [
    HitsSummary(...),
    HitsSummary(...),
  ],
  showDetails: true,
  onHitTap: (hit) {
    // 处理点击
  },
)
```

**显示效果**:
- 摆球卡片列表
- 每个卡片显示：摆球号、时间、峰值、时长等
- 支持点击回调

### 2. HitsSummaryExpansionTile (推荐用于列表)

```dart
HitsSummaryExpansionTile(
  hitsSummary: hits,
  title: '摆球摘要',
  initiallyExpanded: false,
  onHitTap: (hit) {
    // 处理点击
  },
)
```

**显示效果**:
- 可展开的标题栏，显示摆球总数
- 展开后显示完整的摆球列表
- 适合嵌入到其他 UI 中

## 🔧 常见任务

### 任务 1：获取指定录影的摆球摘要

```dart
final videoPath = entry.filePath;
final summaryPath = HitsSummaryStorage.getHitsSummaryPathFromVideo(videoPath);
final hits = await HitsSummaryStorage.loadHitsSummary(summaryPath);
```

### 任务 2：计算摆球统计信息

```dart
final stats = HitsSummaryStorage.getStatistics(hits);
print('总摆球数: ${stats['total']}');
print('平均峰值: ${stats['avgPeak'].toStringAsFixed(2)}G');
print('峰值范围: ${stats['minPeak'].toStringAsFixed(2)}-${stats['maxPeak'].toStringAsFixed(2)}G');
```

### 任务 3：找到最强的摆球

```dart
final strongest = hits.reduce((a, b) => a.peakSmooth > b.peakSmooth ? a : b);
print('最强摆球: ${strongest.hit} (${strongest.peakSmooth}G)');
```

### 任务 4：按时间排序摆球

```dart
final sorted = [...hits]..sort((a, b) => a.tHit.compareTo(b.tHit));
```

### 任务 5：筛选高强度摆球（>50G）

```dart
final strongHits = hits.where((h) => h.peakSmooth > 50).toList();
print('高强度摆球: ${strongHits.length} 个');
```

## 📁 文件位置

需要导入的文件：

```dart
// 数据模型
import 'package:golf_score_app/models/hits_summary.dart';

// 存储服务
import 'package:golf_score_app/services/hits_summary_storage.dart';

// UI 组件
import 'package:golf_score_app/widgets/hits_summary_widget.dart';

// 分割服务（已更新）
import 'package:golf_score_app/services/swing_split_service.dart';
```

## ✅ 检查清单

完成部署前：

- [ ] 导入必要的文件
- [ ] 更新 SwingSplitService 调用加入 detectFrom
- [ ] 在 UI 中集成 HitsSummaryWidget 或 HitsSummaryExpansionTile
- [ ] 测试摆球数据的加载和显示
- [ ] 验证 CSV 文件生成正确
- [ ] 检查 hits_summary.csv 文件位置

## 🐛 常见问题

**Q: 为什么没有显示摆球摘要？**  
A: 检查 hits_summary.csv 文件是否存在于 cut/ 目录中。

**Q: 如何获取详细的摆球信息？**  
A: 使用 `showDetails: true` 参数在 UI 中显示完整信息。

**Q: 可以自定义摆球显示吗？**  
A: 可以，创建自定义 Widget 使用 `HitsSummary` 数据。

**Q: 与 Python 版本兼容吗？**  
A: 完全兼容，CSV 格式完全相同。

## 📖 更多文档

- [详细实现指南](./HITS_SUMMARY_GUIDE.md) - 完整的 API 文档
- [实现总结](./HITS_SUMMARY_IMPLEMENTATION.md) - 技术细节和架构
