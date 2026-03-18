# 錄影歷史版面修復報告

## 🎯 問題分析

錄影歷史卡片原始版面存在以下問題：

### 原始布局問題

```
❌ 問題 1: 標題和徽章在同一行
  - 標題太長時會被徽章擠壓
  - 徽章位置不穩定

❌ 問題 2: 影片類型和檔名共用一行
  - 檔名過長時會溢出
  - 需要更好的斷行處理

❌ 問題 3: 右側按鈕區域沒有固定寬度
  - 播放和菜單按鈕可能導致約束衝突
  - 版面在小屏幕上容易破裂

❌ 問題 4: 整體排版空間浪費
  - 內邊距過大（20px）
  - 行間距配置不當
```

## ✅ 修復方案

### 新布局結構

```
卡片 (Container, padding: 16px)
├─ 第一行: Row(crossAxisAlignment: start)
│  ├─ 縮圖 (112x72)
│  ├─ 間隔 (12px)
│  ├─ 擴展列 (Expanded)
│  │  ├─ 標題 (maxLines: 1, ellipsis)
│  │  ├─ 間隔 (4px)
│  │  └─ 同步狀態徽章
│  ├─ 間隔 (8px)
│  └─ 操作區 (SizedBox: 60x44)
│     ├─ 播放按鈕
│     └─ 菜單按鈕
├─ 間隔 (12px)
├─ 第二行: 時間 · 時長 · 模式 (maxLines: 1, ellipsis)
├─ 間隔 (6px)
├─ 第三行: 影片類型和檔名
│  ├─ 影片類型 (separate line)
│  ├─ 檔名 (maxLines: 1, ellipsis)
├─ 間隔 (6px, if hasImuCsv)
└─ CSV 信息 (maxLines: 1, ellipsis, optional)
```

### 關鍵改進

#### 1. **Column 布局代替 Row 布局**
   - 分為多行顯示內容
   - 避免水平約束衝突
   - 更好的適應不同屏幕尺寸

#### 2. **固定寬度操作區**
   ```dart
   SizedBox(
     width: 60,
     height: 44,
     child: Row(
       mainAxisAlignment: MainAxisAlignment.end,
       children: [
         // 播放和菜單按鈕
       ],
     ),
   )
   ```

#### 3. **文本溢出處理**
   ```dart
   // 所有文本都添加了控制
   Text(
     content,
     maxLines: 1,
     overflow: TextOverflow.ellipsis,  // 超出部分顯示...
   )
   ```

#### 4. **合理的間距**
   - 卡片內邊距: 16px (減少自 20px)
   - 行高間距: 12px (一級) / 6px (二級) / 4px (三級)
   - 水平間距: 12px (縮圖和內容) / 8px (內容和操作)

#### 5. **獨立的影片類型行**
   ```dart
   // 影片類型和檔名分開顯示
   Text('🎥 本地原始影片'),
   SizedBox(height: 2),
   Text('file_name.mp4'),  // 單獨一行
   ```

## 📐 布局細節

### 卡片尺寸
- **寬度**: 響應式（match_parent）
- **高度**: 自適應（包含所有行）
- **最小高度**: ~180px（含縮圖和所有信息）
- **最大寬度**: 無限制（受父容器約束）

### 行高估計
```
第一行 (縮圖 + 標題 + 操作): 72px (縮圖高度)
間隔: 12px
第二行 (時間): 18px (fontSize: 12 + 行間距)
間隔: 6px
第三行 (影片類型): 18px
間隔: 2px
第四行 (檔名): 18px
間隔: 6px (if CSV)
CSV 行: 18px (optional)
─────────────────────────
總計: ~150-180px（取決於是否有 CSV）
```

### 對齊方式
- **縮圖**: 頂部對齐 (crossAxisAlignment: start)
- **標題和徽章**: 頂部對齊，垂直排列
- **操作按鈕**: 右側對齐，垂直居中
- **信息行**: 左對齐，支持單行 + 省略號

## 🎨 樣式調整

### 字體大小
- 標題: 16px, w600 (主要識別)
- 時間/模式: 12px, 灰色 (次要信息)
- 類型標籤: 12px, 淺灰色
- 徽章: 10px, 彩色 (同步狀態)
- CSV 信息: 11px, 深灰色 (輔助)

### 顏色配置
```dart
标题 → Color(0xFF123B70)     // 深藍
時間 → Color(0xFF6F7B86)     // 中灰
檔名 → Color(0xFF9AA6B2)     // 淺灰
CSV  → Color(0xFF4F5D75)     // 深灰
```

### 同步狀態徽章
- **已同步**: 綠色 (Color(0xFF1E8E5A))
- **未同步**: 藍色 (Color(0xFF1E88E5))
- **同步中**: 橙色 (Color(0xFFFF9800))
- **失敗**: 紅色 (Color(0xFFD32F2F))

## 🔧 代碼實現

### 修復前後對比

#### ❌ 修復前 (Row 布局混亂)
```dart
child: Row(
  children: [
    // 縮圖、標題、徽章、按鈕都在一行
    // 導致寬度約束衝突
  ],
)
```

#### ✅ 修復後 (Column + Row 結構)
```dart
child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // 第一行: 縮圖、標題、操作
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HistoryPreview(...),
        Expanded(
          child: Column(
            children: [
              Text(title, maxLines: 1, overflow: ellipsis),
              Container(badge...),
            ],
          ),
        ),
        SizedBox(width: 60, child: Row(buttons...)),
      ],
    ),
    // 第二行: 時間信息
    Text(time, maxLines: 1),
    // 第三行: 影片類型
    Text(type),
    // 第四行: 檔名
    Text(fileName, maxLines: 1),
    // 可選: CSV 信息
    if (hasImuCsv) Text(csv, maxLines: 1),
  ],
)
```

## ✨ 修復成果

### 解決的問題
✅ 標題太長不再擠壓徽章  
✅ 檔名溢出正確處理 (ellipsis)  
✅ 按鈕區域固定寬度，不再破裂  
✅ 小屏幕適應更好  
✅ 大屏幕空間利用更均勻  

### 用戶體驗改進
✅ 更清晰的視覺層級  
✅ 信息更易掃讀  
✅ 操作按鈕位置更穩定  
✅ 各行各占用合理空間  

## 📱 屏幕適應性

### 小屏幕 (320px)
```
[縮圖][標題] [操作]
[時間...]
[🎥 原始影片]
[file_na...]
```
✅ 正常顯示，無溢出

### 中等屏幕 (480px)
```
[縮圖][標題 - 狀態] [操作]
[時間 · 秒數 · 模式]
[🎥 本地原始影片]
[file_name.mp4]
```
✅ 完整顯示

### 大屏幕 (600px+)
```
[縮圖][標題很長很長的名稱 - 狀態徽章] [操作]
[時間 · 秒數 · 模式標籤]
[🎥 本地原始影片]
[file_name_with_full_path.mp4]
```
✅ 充分利用空間

## 📊 編譯狀態

- ✅ 編譯成功
- ✅ 無編譯錯誤
- ⚠️ 2 條警告 (deprecated API，非本修復引入)

---

**版面修復完成！卡片布局現在更加穩定和美觀。** 🎉
