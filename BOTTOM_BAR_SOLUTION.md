## ✅ 底部導航欄 (Bottom Bar) 跨頁面持久化解決方案

**問題**: 底部導航欄只在首頁出現，跨頁面時消失
**解決方案**: 創建 MainShellPage 導航殼層，管理全局底部導航欄

---

## 🏗️ 新的導航架構

```
main.dart
  │
  └─ MaterialApp
      │
      └─ _buildHome()
          │
          ├─ 未登入 → LoginPage
          │
          └─ 已登入 → MainShellPage [新增]
                    │
                    ├─ Scaffold
                    │   │
                    │   ├─ body: PageView (管理頁面切換)
                    │   │   ├─ 第 0 頁: HomePage
                    │   │   ├─ 第 1 頁: TodayInfoPage
                    │   │   ├─ 第 2 頁: RecordingHistoryPage
                    │   │   └─ 第 3 頁: UpgradePage
                    │   │
                    │   └─ bottomNavigationBar: [永遠顯示]
                    │       ├─ Home (icon: home)
                    │       ├─ Today (icon: calendar)
                    │       ├─ Record (icon: videocam, 推送 RecorderPage)
                    │       ├─ Metrics (icon: bar_chart)
                    │       └─ Upgrade (icon: premium)
```

---

## 📝 關鍵改變

### 1. 新建文件: `lib/pages/main_shell_page.dart`
- **用途**: 主導航殼層，包含全局 Scaffold 和 BottomNavigationBar
- **功能**:
  - 使用 PageView 管理 4 個主要頁面的切換
  - 維護當前選中的導航欄項目軌跡 (`_currentIndex`)
  - 禁用 PageView 的手勢滑動（只允許點擊導航欄）
  - `Record` 按鈕推送 RecorderPage，返回後保留執行

### 2. 修改 `main.dart`
```dart
// 修改前
if (snapshot.data == true) {
  return HomePage(cameras: _cameras);
}

// 修改後
if (snapshot.data == true) {
  return MainShellPage(cameras: _cameras);  // ← 使用新的導航殼層
}
```

### 3. 修改 `lib/pages/home_page.dart`
```dart
// 修改前
Scaffold(
  // ... 內容
  bottomNavigationBar: _buildBottomBar(),  // ← 自己提供導航欄
)

// 修改後
Scaffold(
  // ... 內容
  // bottomNavigationBar 移除 ← 現在由 MainShellPage 提供
)
```

---

## 🔄 頁面導航流程

### 點擊 Home / Today / Metrics / Upgrade
```
用戶點擊底部導覽項
    ↓
_onBottomNavTap(index)
    ↓
_pageController.animateToPage(pageIndex)
    ↓
PageView 平滑過渡到對應頁面
    ↓
_currentIndex 更新，導航欄高亮顯示
```

### 點擊 Record (Quick Start)
```
用戶點擊 Record 按鈕
    ↓
_onBottomNavTap(2)
    ↓
Navigator.push() → RecorderPage
    ↓
用戶返回 (返回按鈕或手勢)
    ↓
回到 MainShellPage
    ↓
底部導航欄繼續顯示 ✓
```

---

## 🎯 底部導航欄行為

| 按鈕 | 圖示 | 頁面 | 行為 |
|------|------|------|------|
| **Home** | 🏠 home | HomePage | 切換到第 0 頁 |
| **Today** | 📅 calendar | TodayInfoPage | 切換到第 1 頁 |
| **Record** | 🎥 videocam (綠色圓形) | RecorderPage | 推送疊加頁面 |
| **Metrics** | 📊 bar_chart | RecordingHistoryPage | 切換到第 2 頁 |
| **Upgrade** | ⭐ premium | UpgradePage | 切換到第 3 頁 |

---

## 📊 頁面狀態說明

### 保持狀態的頁面 (PageView)
- ✅ HomePage 的狀態在切換時保留
- ✅ TodayInfoPage 的狀態在切換時保留
- ✅ RecordingHistoryPage 的狀態在切換時保留
- ✅ UpgradePage 的狀態在切換時保留

### 推送式頁面
- RecorderPage (Record 按鈕)
  - 使用 Navigator.push() 推送
  - 返回時保留底部導航欄

---

## ✨ 優勢

1. **底部導航欄永遠可見** ✓
   - 無論在哪個頁面都能快速導航

2. **頁面狀態保留** ✓
   - HomePage 數據不會因為切換而丟失
   - 快速頁面切換（無需重新加載）

3. **平滑的過渡動畫** ✓
   - PageView.animateToPage() 提供平滑動畫

4. **記錄按鈕特獨立** ✓
   - Record 按鈕仍然推送 RecorderPage
   - 返回後自動回到主導航

5. **易於擴展** ✓
   - 新增頁面只需在 PageView 中添加

---

## 🧪 測試檢查清單

頁面導航測試:
- [ ] 點擊 Home，展示首頁
- [ ] 點擊 Today，展示今日信息頁
- [ ] 點擊 Metrics，展示歷史數據頁
- [ ] 點擊 Upgrade，展示升級頁
- [ ] 在各頁面之間切換，底部導航欄始終顯示 ✓

Record 按鈕測試:
- [ ] 點擊 Record，推送錄影頁面
- [ ] Record 頁面顯示，底部導航欄隱藏（推送式）✓
- [ ] 返回（返回按鈕/手勢），回到主頁面
- [ ] 底部導航欄重新顯示 ✓

狀態保留測試:
- [ ] 在 HomePage 捲動到下方
- [ ] 點擊 Today，切換到 TodayInfoPage
- [ ] 點擊 Home，回到 HomePage
- [ ] HomePage 的捲動位置保留（或頂部）✓

---

## 🔧 故障排除

### 底部導航欄仍然消失

**檢查清單**:
1. ✓ main.dart 已更新為使用 MainShellPage
2. ✓ home_page.dart 的 bottomNavigationBar 已移除
3. ✓ 編譯無錯誤 (flutter pub get && flutter analyze)
4. ✓ 清除緩存 (flutter clean)

**解決**:
```bash
flutter clean
flutter pub get
flutter run
```

### 頁面不切換

**檢查**:
- PageController 是否正確初始化
- PageView 的 physics 是否為 NeverScrollableScrollPhysics（禁用滑動）
- _pageController.animateToPage() 的 pageIndex 是否正確

### Record 按鈕返回後底部導航消失

**原因**: RecorderPage 可能有自己的 Scaffold
**解決**: 确保 RecorderPage 的 Scaffold 没有 bottomNavigationBar

---

## 📁 文件結構

```
lib/
├── pages/
│   ├── main_shell_page.dart ................... [新增] 導航殼層
│   ├── home_page.dart ........................ [修改] 移除 bottomNavigationBar
│   ├── today_info_page.dart .................. [無改變]
│   ├── recording_history_page.dart ........... [無改變]
│   ├── upgrade_page.dart ..................... [無改變]
│   └── ...
├── main.dart ................................ [修改] 使用 MainShellPage
└── ...
```

---

## 🎓 技術細節

### 為什麼使用 PageView？

PageView 的優勢:
- 頁面狀態保留（相比 Navigator.push/pop）
- 平滑的切換動畫
- 管理多個頁面的視圖層級
- 支持禁用手勢滑動

替代方案（不推薦）:
- ❌ Navigator.push/pop - 每次切換時重新構建頁面
- ❌ IndexedStack - 所有頁面同時構建，佔用更多內存

### 為什麼 Record 按鈕仍然使用 push？

因為 RecorderPage 帶有攝像機控制，通常作為一個臨時疊加頁面出現，用戶會返回主頁面。這符合原始設計。

---

## 🚀 後續改進（可選）

1. **導航動畫**
   - 自定義 PageView 切換動畫

2. **頁面指示器**
   - 添加小圓點指示當前頁面

3. **導航欄動畫**
   - 在不同頁面間過渡時改變導航欄顏色

4. **狀態恢復**
   - 應用被殺死後恢復到上次訪問的頁面

---

**更新日期**: 2026-04-16
**版本**: 1.0
