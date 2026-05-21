# 圖表「手腕Y」和「Speed」為空的根本原因分析

## 問題症狀
日誌顯示：
```
[LocalStats] period=today date=null → 2/58 筆
[LocalStats] → total=2 good=1 bad=0 sweet=100.0% crispAvg=0.2 crispMin=0.2
[ChartData] audio: 5 點
[ChartData] pose CSV 缺少手腕欄位
```

- ✅ 聲音峰值有 5 個點
- ❌ 手腕 Y 為空
- ❌ Speed 為空

## 根本原因

### 1️⃣ CSV 格式被破壞
**位置**：`lib/recording/pose_frame_model.dart` → `toCsvRow()`

當骨架檢測失敗時，所有坐標都是 `double.nan`。原代碼返回空字符串 `''`：
```dart
// ❌ 原代碼
lm.xPx.isNaN ? '' : lm.xPx,
lm.yPx.isNaN ? '' : lm.yPx,
```

**問題**：
- CSV 寫入時出現連續逗號：`,,,`
- 在 `_sliceCsv()` 中簡單字符串拼接時可能破壞行格式
- 導致字段列數不匹配

### 2️⃣ CSV Header 查找失敗
**位置**：`lib/services/chart_data_service.dart` → `_parsePoseCsv()`

```dart
final ywIdx = headers.indexOf('lm16_y_px');
final xwIdx = headers.indexOf('lm16_x_px');

if (timeIdx < 0 || ywIdx < 0 || xwIdx < 0) {
  debugPrint('$_tag pose CSV 缺少手腕欄位');
  return empty;  // ❌ 直接返回空數據
}
```

**為什麼找不到**：
- 如果所有行都被 `_sliceCsv()` 破壞（缺少列）
- 或者 pose 檢測完全失敗，生成的 CSV 全是 NaN

### 3️⃣ 數據過濾太嚴格
原代碼跳過可見度 < 0.4 的數據：
```dart
if (vis != null && vis < 0.4) {
  prevX = null; prevY = null;
  continue;  // 跳過
}
```

但沒有累計統計被跳過的行數，導致無法診斷。

---

## 修復方案

### ✅ 修復 1：CSV 生成時保持完整性
**文件**：`lib/recording/pose_frame_model.dart`

```dart
// ✅ 修復後
lm.xPx.isNaN ? 0.0 : lm.xPx,  // 用 0.0 代替空字符串
lm.yPx.isNaN ? 0.0 : lm.yPx,
```

**好處**：
- CSV 格式始終完整，每行列數一致
- `_sliceCsv()` 的字符串拼接不會破壞格式
- 解析時能正確識別字段位置

### ✅ 修復 2：增強 CSV 解析的診斷
**文件**：`lib/services/chart_data_service.dart`

```dart
// 顯示實際的 header 和字段位置
debugPrint('$_tag pose CSV header 數量: ${headers.length}');
debugPrint('$_tag pose CSV 字段位置: timeIdx=$timeIdx, ywIdx=$ywIdx, xwIdx=$xwIdx, visIdx=$visIdx');
if (timeIdx < 0 || ywIdx < 0 || xwIdx < 0) {
  debugPrint('$_tag 預期欄位: time_sec, lm16_y_px, lm16_x_px');
  debugPrint('$_tag 實際 header: ${headers.join(", ")}');
  return empty;
}
```

### ✅ 修復 3：改進數據過濾邏輯
**文件**：`lib/services/chart_data_service.dart`

```dart
// 追蹤統計
int validRows = 0;
int skippedRows = 0;

// 改進的跳過邏輯
if (vis != null && vis < 0.1) {  // 更低的閾值
  skippedRows++;
  continue;
}
// 跳過非零可見度但坐標全零的行（檢測失敗的標記）
if ((yw == 0.0 && xw == 0.0) && vis != null && vis > 0) {
  skippedRows++;
  continue;
}

// 最終診斷
debugPrint('$_tag pose: wristY=${wristY.length}, speed=${speedPts.length}, validRows=$validRows, skipped=$skippedRows');
```

---

## 預期改進

### 情景 1：有效的骨架數據
```
✅ pose CSV header 數量: 204
✅ pose CSV 字段位置: timeIdx=1, ywIdx=103, xwIdx=102, visIdx=101
✅ pose: wristY=45, speed=44, validRows=45, skipped=5
```
→ 圖表將顯示完整的手腕 Y 和 Speed 曲線

### 情景 2：骨架檢測失敗
```
❌ pose CSV 缺少手腕欄位
❌ 預期欄位: time_sec, lm16_y_px, lm16_x_px
❌ 實際 header: frame,time_sec,pose_update_id (只有 3 列)
```
→ 清楚地說明需要完成"姿勢分析"

### 情景 3：CSV 被切片破壞
```
⚠️  pose CSV header 數量: 8 (應該是 204)
❌ pose CSV 缺少手腕欄位
```
→ 表明 `_sliceCsv()` 出現問題

---

## 後續行動

1. **立即測試**
   - 重新構建應用
   - 進行新的錄製測試
   - 查看改進的診斷日誌

2. **如果仍然失敗**
   - 檢查 `pose_landmarks.csv` 的實際內容
   - 驗證 ML Kit pose detection 是否正常工作
   - 檢查錄製時是否有足夠的有效骨架

3. **長期改進**
   - 考慮在錄製時即時驗證 CSV 格式
   - 添加 CSV 驗證工具
   - 改進 pose detection 失敗時的備選方案
