# 🎯 RecordingHistoryPage - TAB 與按鈕功能檢查

**分析日期**: 2026-05-08  
**頁面**: [lib/pages/recording_history_page.dart](lib/pages/recording_history_page.dart)

---

## 📋 目錄

1. [AppBar 按鈕](#appbar-按鈕)
2. [篩選 TAB](#篩選-tab)
3. [排序 TAB](#排序-tab)
4. [功能流程](#功能流程)
5. [狀態管理](#狀態管理)

---

## 🔘 AppBar 按鈕

### 位置
```dart
AppBar(
  title: const Text('錄影歷史'),
  leading: IconButton(...),     // ← 返回按鈕
  actions: [
    IconButton(...),   // 🐛 Debug 資訊
  ],
)
```

---

### 1️⃣ 返回按鈕 (Leading)

| 屬性 | 值 |
|------|-----|
| **圖標** | `Icons.arrow_back` |
| **功能** | 返回上一頁並帶出更新後的清單 |
| **回調** | `_finishWithResult()` |
| **位置** | `line 1005-1009` |

#### 代碼
```dart
leading: IconButton(
  onPressed: _finishWithResult,
  icon: const Icon(Icons.arrow_back),
),
```

#### 實現邏輯
```dart
void _finishWithResult() {
  Navigator.of(context).pop(
    List<RecordingHistoryEntry>.from(_entries)
  );
}
```

**特性**:
- ✅ 返回時帶回完整的更新清單
- ✅ 支持 WillPopScope 攔截返回
- ✅ 用於同步首頁數據

---

### 2️⃣ Debug 按鈕 (隱藏功能)

| 屬性 | 值 |
|------|-----|
| **圖標** | `Icons.bug_report_outlined` |
| **提示** | Debug: 本地紀錄 JSON |
| **功能** | 顯示本地存儲的 JSON 數據 |
| **回調** | `_showDebugJsonInfo()` |
| **位置** | `line 1020-1024` |
| **狀態** | ⚠️ 開發用途 |

#### 代碼
```dart
IconButton(
  onPressed: _showDebugJsonInfo,
  tooltip: 'Debug: 本地紀錄 JSON',
  icon: const Icon(Icons.bug_report_outlined),
),
```

#### 功能詳情

**顯示的對話框**:
```
┌────────────────────────────────────┐
│ 本地錄製歷史 JSON                   │
├────────────────────────────────────┤
│ [SelectableText - 可複製]           │
│                                    │
│ [{                                 │
│   "filePath": "...",              │
│   "roundIndex": 1,                │
│   "recordedAt": "2026-02-05...",  │
│   ...                             │
│ }]                                 │
│                                    │
│ [複製] [關閉]                      │
└────────────────────────────────────┘
```

**用途**:
- 📊 檢查本地 JSON 結構
- 🔍 驗證數據完整性
- 🐛 調試問題
- 📋 導出數據查看

---

## 📑 篩選 TAB

### 位置
```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      FilterChip(...),  // 全部
      FilterChip(...),  // 好球 ✓
      FilterChip(...),  // 壞球 ✗
    ],
  ),
)
```

### 1️⃣ 全部

| 屬性 | 值 |
|------|-----|
| **標籤** | 全部 |
| **選中條件** | `_selectedGoodShot == null` |
| **功能** | 顯示所有記錄 |
| **狀態變數** | `_selectedGoodShot: null` |
| **行數** | ~1043-1051 |

#### 代碼
```dart
FilterChip(
  selected: _selectedGoodShot == null,
  label: const Text('全部'),
  onSelected: (selected) {
    if (selected) {
      setState(() => _selectedGoodShot = null);
    }
  },
),
```

#### 篩選邏輯
```dart
var filteredEntries = _selectedGoodShot == null
    ? _entries  // 顯示所有記錄
    : _entries.where((entry) => entry.goodShot == _selectedGoodShot).toList();
```

---

### 2️⃣ 好球 ✓

| 屬性 | 值 |
|------|-----|
| **標籤** | 好球 ✓ |
| **選中條件** | `_selectedGoodShot == true` |
| **功能** | 只顯示好球記錄 |
| **狀態變數** | `_selectedGoodShot: true` |
| **行數** | ~1052-1062 |
| **篩選準則** | `entry.goodShot == true` |

#### 代碼
```dart
FilterChip(
  selected: _selectedGoodShot == true,
  label: const Text('好球 ✓'),
  onSelected: (selected) {
    if (selected) {
      setState(() => _selectedGoodShot = true);
    }
  },
),
```

#### 好球判定來源
- **音頻分析**: `SwingImpactDetector.detect()`
- **評分標籤**: `audioLabel: "Pro"` 或 `"Sweet"`
- **清脆度**: `audioCrispness > 80`

---

### 3️⃣ 壞球 ✗

| 屬性 | 值 |
|------|-----|
| **標籤** | 壞球 ✗ |
| **選中條件** | `_selectedGoodShot == false` |
| **功能** | 只顯示壞球記錄 |
| **狀態變數** | `_selectedGoodShot: false` |
| **行數** | ~1063-1073 |
| **篩選準則** | `entry.goodShot == false` |

#### 代碼
```dart
FilterChip(
  selected: _selectedGoodShot == false,
  label: const Text('壞球 ✗'),
  onSelected: (selected) {
    if (selected) {
      setState(() => _selectedGoodShot = false);
    }
  },
),
```

---

## 📊 排序 TAB

### 位置
```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      Text('排序: '),
      FilterChip(...),  // 時間
      FilterChip(...),  // 最佳速度 🎯
    ],
  ),
)
```

### 1️⃣ 時間

| 屬性 | 值 |
|------|-----|
| **標籤** | 時間 |
| **排序標準** | `_SortBy.date` |
| **排序順序** | 新 → 舊 (最新優先) |
| **行數** | ~1088-1098 |
| **狀態變數** | `_sortBy = _SortBy.date` |

#### 代碼
```dart
FilterChip(
  selected: _sortBy == _SortBy.date,
  label: const Text('時間'),
  onSelected: (selected) {
    if (selected) {
      setState(() => _sortBy = _SortBy.date);
    }
  },
),
```

#### 排序邏輯
```dart
case _SortBy.date:
  filteredEntries.sort(
    (a, b) => b.recordedAt.compareTo(a.recordedAt)
  );
  break;
```

**應用場景**: 
- 📌 查看最新的錄製
- 🕐 按時間順序瀏覽

---

### 2️⃣ 最佳速度 🎯

| 屬性 | 值 |
|------|-----|
| **標籤** | 最佳速度 🎯 |
| **排序標準** | `_SortBy.peakValue` |
| **排序順序** | 高 → 低 (最高優先) |
| **行數** | ~1099-1109 |
| **狀態變數** | `_sortBy = _SortBy.peakValue` |
| **排序字段** | `entry.audioCrispness` |

#### 代碼
```dart
FilterChip(
  selected: _sortBy == _SortBy.peakValue,
  label: const Text('最佳速度 🎯'),
  onSelected: (selected) {
    if (selected) {
      setState(() => _sortBy = _SortBy.peakValue);
    }
  },
),
```

#### 排序邏輯
```dart
case _SortBy.peakValue:
  filteredEntries.sort((a, b) {
    final aVal = a.audioCrispness ?? 0;
    final bVal = b.audioCrispness ?? 0;
    return bVal.compareTo(aVal);  // 高 → 低
  });
  break;
```

**應用場景**:
- 🏌️ 找出最好的揮桿
- 📈 性能追踪
- 🎯 品質評估

---

## 🔄 功能流程

### 篩選流程

```
用戶點擊 TAB
  ↓
setState(_selectedGoodShot = value)
  ↓
build() 重新執行
  ↓
filteredEntries = _entries.where(...)
  ├─→ null: 全部
  ├─→ true: 好球
  └─→ false: 壞球
  ↓
排序應用
  ↓
ListView 更新顯示
```

### 排序流程

```
用戶點擊排序 TAB
  ↓
setState(_sortBy = value)
  ↓
build() 重新執行
  ↓
_sortEntries() 執行
  ├─→ date: 按時間排序 (新→舊)
  └─→ peakValue: 按速度排序 (高→低)
  ↓
ListView 更新顯示
```

### 組合流程

```
篩選 + 排序 = 最終結果

步驟 1: 篩選
  _entries → filteredEntries

步驟 2: 排序
  filteredEntries → sortedEntries

步驟 3: 顯示
  ListView 列出 sortedEntries
```

---

## 📌 狀態管理

### 狀態變數

```dart
class _RecordingHistoryPageState {
  // 記錄列表
  List<RecordingHistoryEntry> _entries = [];
  
  // 加載狀態
  bool _isLoading = true;
  
  // 防止重繪衝突
  bool _rebuildScheduled = false;
  
  // 篩選狀態 ← TAB 相關
  bool? _selectedGoodShot;  // null=全部, true=好球, false=壞球
  
  // 排序狀態 ← TAB 相關
  _SortBy _sortBy = _SortBy.date;
}
```

### 初始值

| 變數 | 初始值 | 含義 |
|------|--------|------|
| `_selectedGoodShot` | `null` | 顯示全部記錄 |
| `_sortBy` | `_SortBy.date` | 按時間排序 |

### 狀態轉移

```
┌─────────────────────────────────────┐
│ 初始狀態                             │
│ ├─ _selectedGoodShot: null          │
│ └─ _sortBy: date                    │
└─────────────────────────────────────┘
        ↙     ↓     ↘
   篩選  排序  篩選+排序
        ↙     ↓     ↘
┌─────────────────────────────────────┐
│ 用戶操作後                           │
│ ├─ _selectedGoodShot: [值]          │
│ └─ _sortBy: [值]                    │
└─────────────────────────────────────┘
```

---

## ✅ 功能完成度檢查

| 功能 | 狀態 | 備註 |
|------|------|------|
| 返回按鈕 | ✅ | 帶回清單 |
| Debug 按鈕 | ✅ | 顯示 JSON |
| 好球篩選 | ✅ | 過濾 `goodShot == true` |
| 壞球篩選 | ✅ | 過濾 `goodShot == false` |
| 全部篩選 | ✅ | 顯示所有 |
| 時間排序 | ✅ | 新→舊 |
| 速度排序 | ✅ | 高→低 |
| 篩選+排序 | ✅ | 組合效果 |

---

**報告更新完成**  
Removed Features:
- 建立新記錄 (新增按鈕 + 對話框)
- 開啟其他影片 (FilePicker 導入)

Generated: 2026-05-08
