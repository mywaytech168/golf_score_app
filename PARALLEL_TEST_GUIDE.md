# 並行優化 - 實機測試指南

## 🎯 測試目標
驗證並行優化是否達到預期的性能改進 (45s → 15-20s)

---

## 📋 測試準備

### 必需
- ✅ 應用已編譯部署 (build\app\outputs\flutter-apk\app-debug.apk)
- ✅ ASUS I005DA 設備已連接
- ✅ 高爾夫視頻文件 (30+ 秒)

### 建議
- 清空 /sdcard/Android/data/com.example.golf_score_app/
- 設備電量 > 50%
- 只運行該應用 (減少干擾)

---

## 🔬 測試流程

### 階段 1: 基準測試 (VideoThumbnail - 舊方案)

**暫不執行** (已完全替換)

### 階段 2: 新方案驗證 (Native + 並行)

#### 2.1 準備視頻
```bash
# 選項 A: 使用設備已有視頻
adb shell ls /sdcard/Movies/
adb shell ls /sdcard/DCIM/Camera/

# 選項 B: 複製測試視頻
adb push ~/golf_test.mp4 /sdcard/Movies/
```

#### 2.2 啟動應用
1. 打開應用
2. 導航至「錄制」或「分析」界面
3. 選擇視頻進行離線分析

#### 2.3 測量耗時
```bash
# 查看日誌
adb logcat | grep VideoAnalysis

# 期望輸出:
# [VideoAnalysis] 開始並行分析 (4 幀/批次, 450 幀總數)
# [VideoAnalysis] 寫入 450 幀到 CSV...
# [VideoAnalysis] ✅ 並行分析完成: 450 幀 → /path/to/csv

# 記錄:
# - 開始時間 (log timestamp)
# - 結束時間 (log timestamp)
# - 計算: 耗時 = 結束 - 開始
```

#### 2.4 驗證結果
```bash
# 檢查 CSV 是否生成
adb shell ls -la /sdcard/Android/data/com.example.golf_score_app/files/

# 驗證 CSV 內容 (前 10 行)
adb shell head -10 /path/to/pose_landmarks.csv

# 驗證完整性 (應有 450+ 行)
adb shell wc -l /path/to/pose_landmarks.csv
```

---

## 📊 預期結果

### 性能指標
| 指標 | 期望值 | 可接受範圍 |
|------|--------|----------|
| 總耗時 | 15-18s | 13-22s |
| 幀提取速率 | 15-20ms | 10-25ms |
| 推理速率 | 35-50ms | 30-60ms |
| 批處理效率 | 75-85% | >70% |

### 日誌跡象

✅ **成功跡象**:
```
[VideoAnalysis] 開始並行分析 (4 幀/批次, 450 幀總數)
[VideoAnalysis] 寫入 450 幀到 CSV...
[VideoAnalysis] ✅ 並行分析完成: 450 幀
```

❌ **問題跡象**:
```
[VideoAnalysis] 幀 XXX 錯誤
[VideoAnalysis] 批次 XX-XX 失敗
OutOfMemoryError (如果批大小太大)
```

---

## 🔍 詳細測試場景

### 場景 1: 短視頻 (15 秒)
- **幀數**: ~224
- **預期耗時**: 8-10s
- **用途**: 快速驗證

### 場景 2: 標準視頻 (30 秒)
- **幀數**: ~450
- **預期耗時**: 15-18s
- **用途**: 標準測試

### 場景 3: 長視頻 (60 秒)
- **幀數**: ~900
- **預期耗時**: 30-35s
- **用途**: 耐久性測試

---

## 💡 性能分析技巧

### 1. 批大小調整
如果性能低於預期，嘗試調整 `batchSize`:
```dart
const batchSize = 4;  // 目前值
// 試試: 2 (更保守), 6-8 (更激進)
```

### 2. 識別瓶頸
查看日誌的詳細時序:
```dart
// 在 _processFrameAsync() 中添加時間戳
final extractStart = DateTime.now();
final result = await _frameExtractorChannel...
final extractMs = DateTime.now().difference(extractStart).inMilliseconds;

final inferStart = DateTime.now();
final poses = await poseService.detect(...);
final inferMs = DateTime.now().difference(inferStart).inMilliseconds;

debugPrint('[Frame $frameIndex] 提取=${extractMs}ms 推理=${inferMs}ms');
```

### 3. 記憶體監控
```bash
adb shell dumpsys meminfo com.example.golf_score_app | grep "TOTAL"
```

---

## 🐛 故障排除

### 問題 1: OutOfMemory 錯誤
**症狀**: 批處理中途崩潰
**解決**: 減少 batchSize (4 → 2)

### 問題 2: 結果不一致
**症狀**: CSV 中有缺失幀或亂序
**解決**: 檢查異常捕獲邏輯

### 問題 3: 性能沒有改進
**症狀**: 耗時仍 > 25s
**可能原因**:
- 設備性能限制
- 其他進程干擾
- 視頻編碼格式不支持

---

## 📝 測試報告範本

```
=== 並行優化性能測試 ===
日期: 2026-05-14
設備: ASUS I005DA
視頻: 30 秒
幀數: 450

結果:
- 開始時間: HH:MM:SS
- 結束時間: HH:MM:SS
- 耗時: XX 秒
- 改進: vs 45s (原始) = X.Xx

CSV 驗證:
- ✅ 幀數: 450
- ✅ 順序: 完整
- ✅ 數據: 正常

結論: ✅ 達成預期 / ⚠️ 需要調整 / ❌ 失敗
```

---

## 🎉 成功標準

測試通過需滿足:
1. ✅ 應用成功啟動並執行分析
2. ✅ CSV 正確生成，所有幀完整無損
3. ✅ 耗時 < 22 秒 (比 45s 改進至少 50%)
4. ✅ 無運行時錯誤或崩潰

---

**下一步**: 按上述流程進行實機測試並記錄結果！
