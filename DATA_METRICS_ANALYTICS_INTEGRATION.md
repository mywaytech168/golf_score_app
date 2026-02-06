# Data Metrics 和 Analytics 共用統計數據 - 實現總結

## 概述

完成了 Data Metrics 和 Analytics 統計數據的整合，通過引入 `StatisticsService` 統一管理後端 API 數據和本地計算數據，確保兩個模塊共享相同的數據源。

## 核心改變

### 1. 創建統計數據服務 (`statistics_service.dart`)

**位置**: `lib/services/statistics_service.dart`

**功能**:
- **統一數據管理**: 合併後端 API 數據和本地計算數據
- **緩存機制**: 5分鐘的 API 緩存，避免頻繁請求
- **Stream 支持**: 提供響應式數據訂閱
- **靈活的數據模型**:
  - `StatisticsResponse`: 後端 API 返回的數據
  - `LocalMetrics`: 本地計算的指標（如 consistencyScore）
  - `MergedStatistics`: 合併後的完整統計數據
  - `LoadingState`: 加載狀態追蹤
  - `ComparisonSnapshot`: 比較數據快照

**核心 API**:
```dart
// 從 API 加載統計數據
await statisticsService.loadStatisticsFromApi(period: 'all');

// 設置本地計算的指標
statisticsService.setLocalMetrics(
  consistencyScore: metrics.consistencyScore,
  bestSpeedMph: metrics.bestSpeedMph,
  // ... 其他指標
);

// 獲取合併後的統計數據
final merged = statisticsService.mergedStatistics;

// 訂閱數據變化
statisticsService.watchStatistics().listen((stats) {
  // 響應統計數據變化
});
```

### 2. 修改 `home_page.dart`

**改進點**:

#### a) 移除冗餘狀態管理
```dart
// 移除: _allStatistics, _isLoadingAllStatistics
// 改用: _statisticsService 中的統一管理
```

#### b) 初始化改造
```dart
// 舊方式: 直接調用 _loadAllStatistics()
@override
void initState() {
  super.initState();
  _loadAllStatistics(); // 移除
}

// 新方式: 初始化統計服務
@override
void initState() {
  super.initState();
  _initializeStatistics(); // 使用服務
}

Future<void> _initializeStatistics() async {
  await _statisticsService.loadStatisticsFromApi(period: 'all');
}
```

#### c) 數據刷新流程改造
```dart
// _refreshDashboardMetrics() 現在也更新 StatisticsService
_statisticsService.setLocalMetrics(
  consistencyScore: metrics.consistencyScore,
  bestSpeedMph: metrics.bestSpeedMph,
  // ... 其他本地計算的指標
);
```

#### d) UI 更新 - Data Metrics 部分
```dart
// 舊方式:
final speedValue = _isLoadingAllStatistics ? '...' : _allStatistics!.peakValue.maximum;

// 新方式:
final backendStats = _statisticsService.statistics;
final isLoadingStats = _statisticsService.loadingState.isLoading;
final speedValue = isLoadingStats ? '...' : backendStats?.peakValue.maximum;
```

#### e) UI 更新 - Analytics 部分
同樣改用 `backendStats` 和 `isLoadingStats`

#### f) 資源清理
```dart
@override
void dispose() {
  _statisticsService.dispose();
  super.dispose();
}
```

## 數據流

```
後端 API (period: 'all')
    ↓
StatisticsService.loadStatisticsFromApi()
    ↓
_statisticsService.statistics (後端數據)
    
    +
    
本地錄影歷史
    ↓
_MetricsCalculator.compute()
    ↓
本地計算指標 (consistencyScore, bestSpeedMph, etc.)
    ↓
StatisticsService.setLocalMetrics()
    ↓
_statisticsService.localMetrics (本地數據)
    
    =
    
StatisticsService.mergedStatistics (完整統計)
    ↓
Data Metrics 和 Analytics UI
```

## 數據來源對應

### Data Metrics 顯示
| 指標 | 數據來源 | 字段 |
|-----|--------|------|
| 練習次數 | 本地 | `_practiceCount` |
| 最佳速度 | 後端 API | `backendStats.peakValue.maximum` |
| 甜蜜點命中 | 後端 API | `backendStats.sweetSpotPercentage` |

### Analytics 顯示
| 指標 | 數據來源 | 字段 |
|-----|--------|------|
| Best Speed | 後端 API | `backendStats.peakValue.maximum` |
| Stability | 本地計算 | `_consistencyScore` |
| Sweet Spot | 後端 API | `backendStats.sweetSpotPercentage` |
| Audio Crispness | 後端 API | `backendStats.audioCrispness.average` |

## 優勢

1. **單一數據源原則**: 避免多個組件獨立查詢相同數據
2. **智能緩存**: 減少不必要的 API 調用
3. **易於維護**: 後續修改只需更新 Service
4. **靈活擴展**: 可輕鬆添加更多統計維度
5. **自動同步**: Stream 和 getter 確保數據一致性
6. **性能優化**: 減少 UI 重建頻率

## 驗證清單

- [x] StatisticsService 創建並實現核心功能
- [x] home_page.dart 集成 StatisticsService
- [x] Data Metrics 使用後端 API 數據
- [x] Analytics 使用後端 API 數據（除 Stability 使用本地計算）
- [x] 移除冗餘狀態變量
- [x] 添加資源清理邏輯
- [x] 沒有編譯錯誤
- [ ] 運行時測試（待執行）

## 後續改進方向

1. **增強後端 API**: 考慮在後端也計算 Stability 指標
2. **實時更新**: 實現 WebSocket 或 SignalR 推送統計數據更新
3. **分時段統計**: 支持日、週、月等時間維度
4. **詳細報告**: 提供更詳細的數據分析視圖
5. **導出功能**: 支持統計數據導出（CSV、PDF）
