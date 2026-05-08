# 🔍 錄製歷史 - 實現細節指南

**詳細程度**: 開發者  
**適用於**: 代碼檢查、功能擴展、問題排查

---

## 📑 目錄

1. [RecordingHistoryEntry 深入](#recordinghistoryentry-深入)
2. [存儲機制詳解](#存儲機制詳解)
3. [核心方法實現](#核心方法實現)
4. [狀態流轉](#狀態流轉)
5. [常見操作示例](#常見操作示例)
6. [性能考量](#性能考量)
7. [錯誤處理](#錯誤處理)

---

## 🎯 RecordingHistoryEntry 深入

### 完整的 JSON 序列化實現

```dart
// 序列化 (Dart → JSON)
Map<String, dynamic> toJson() {
  return {
    'filePath': filePath,
    'roundIndex': roundIndex,
    'recordedAt': recordedAt.toIso8601String(),  // DateTime → ISO 8601
    'durationSeconds': durationSeconds,
    'customName': customName,
    'thumbnailPath': thumbnailPath,
    'videoType': videoType.name,                 // 枚舉 → 字串
    'isClipped': isClipped,
    'hitSecond': hitSecond,
    'startSecond': startSecond,
    'endSecond': endSecond,
    'audioCrispness': audioCrispness,
    'goodShot': goodShot,
    'audioLabel': audioLabel,
  };
}

// 反序列化 (JSON → Dart)
factory RecordingHistoryEntry.fromJson(Map<String, dynamic> json) {
  return RecordingHistoryEntry(
    filePath: json['filePath'] as String? ?? '',
    roundIndex: json['roundIndex'] as int? ?? 0,
    recordedAt: json['recordedAt'] != null
        ? DateTime.parse(json['recordedAt'] as String)  // ISO 8601 → DateTime
        : DateTime.now(),
    durationSeconds: json['durationSeconds'] as int? ?? 0,
    customName: json['customName'] as String?,
    thumbnailPath: json['thumbnailPath'] as String?,
    videoType: VideoType.values.byName(json['videoType'] as String? ?? 'original'),
    isClipped: json['isClipped'] as bool? ?? false,
    hitSecond: (json['hitSecond'] as num?)?.toDouble(),
    startSecond: (json['startSecond'] as num?)?.toDouble(),
    endSecond: (json['endSecond'] as num?)?.toDouble(),
    audioCrispness: (json['audioCrispness'] as num?)?.toDouble(),
    goodShot: json['goodShot'] as bool?,
    audioLabel: json['audioLabel'] as String?,
  );
}
```

### copyWith() 使用模式

```dart
// ✅ 更新單個字段
final updated = entry.copyWith(
  customName: '新名稱',
);

// ✅ 更新多個字段
final updated = entry.copyWith(
  customName: '完美揮桿',
  goodShot: true,
  audioLabel: 'Pro',
);

// ✅ 清除字段
final updated = entry.copyWith(
  customName: null,  // 清除自訂名稱，回到預設
);

// ✅ 鏈式調用
final entries = _entries
    .map((e) => e.copyWith(isClipped: true))
    .toList();
```

### displayTitle 邏輯

```dart
String get displayTitle {
  final name = customName?.trim();
  
  // 優先顯示自訂名稱
  if (name != null && name.isNotEmpty) {
    return name;  // "完美揮桿"
  }
  
  // 回退到預設標題
  return '第 $roundIndex 輪錄影';  // "第 5 輪錄影"
}

// 使用示例
print(entry.displayTitle);  // 輸出: "完美揮桿" 或 "第 1 輪錄影"
```

---

## 💾 存儲機制詳解

### RecordingHistoryStorage 工作流

#### 1. 初始化路徑解析

```dart
Future<File> _resolveHistoryFile() async {
  // 1️⃣ 取得應用文件目錄
  final baseDir = await getApplicationDocumentsDirectory();
  // 典型路徑: /data/user/0/com.example.app/documents

  // 2️⃣ 組合資料夾路徑
  final targetDir = Directory(p.join(baseDir.path, _folderName));
  // 結果: /data/user/0/com.example.app/documents/golf_recordings

  // 3️⃣ 確保資料夾存在
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);  // 遞迴建立
  }

  // 4️⃣ 組合檔案路徑並返回
  return File(p.join(targetDir.path, _fileName));
  // 最終: /data/user/0/com.example.app/documents/golf_recordings/recording_history.json
}
```

#### 2. 載入流程 (loadHistory)

```dart
Future<List<RecordingHistoryEntry>> loadHistory() async {
  try {
    // 第 1 步: 取得檔案路徑
    final file = await _resolveHistoryFile();
    debugPrint('[RecordingHistoryStorage] 加載檔案: ${file.path}');

    // 第 2 步: 檢查檔案存在
    if (!await file.exists()) {
      debugPrint('[RecordingHistoryStorage] 檔案不存在，返回空陣列');
      return [];  // 首次啟動時檔案不存在
    }

    // 第 3 步: 讀取檔案內容
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      debugPrint('[RecordingHistoryStorage] 檔案為空');
      return [];
    }

    // 第 4 步: JSON 解碼
    final decoded = jsonDecode(content);  // String → dynamic
    if (decoded is! List) {
      debugPrint('[RecordingHistoryStorage] JSON 格式不正確');
      return [];
    }

    // 第 5 步: 逐個反序列化
    final entries = <RecordingHistoryEntry>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        entries.add(RecordingHistoryEntry.fromJson(item));
      } else if (item is Map) {
        // 容錯: 動態鍵值 Map 轉換
        entries.add(
          RecordingHistoryEntry.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }

    // 第 6 步: 排序 (新 → 舊)
    entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    // 第 7 步: 檔案驗證
    // 過濾掉已刪除的視頻，避免 UI 錯誤
    final validated = entries
        .where((entry) => File(entry.filePath).existsSync())
        .toList(growable: false);

    debugPrint('[RecordingHistoryStorage] ✅ 加載成功: ${validated.length} 筆記錄');
    return validated;

  } catch (e) {
    debugPrint('[RecordingHistoryStorage] ❌ 加載失敗: $e');
    return [];  // 失敗時靜默返回空陣列
  }
}
```

#### 3. 保存流程 (saveHistory)

```dart
Future<void> saveHistory(List<RecordingHistoryEntry> entries) async {
  try {
    // 第 1 步: 取得檔案路徑
    final file = await _resolveHistoryFile();

    // 第 2 步: 序列化
    final payload = entries
        .map((e) => e.toJson())  // RecordingHistoryEntry → Map
        .toList(growable: false);

    // 第 3 步: JSON 編碼
    final jsonString = jsonEncode(payload);  // List<Map> → JSON String

    // 第 4 步: 寫入檔案 (原子操作)
    await file.writeAsString(jsonString);

    debugPrint('[RecordingHistoryStorage] ✅ 保存成功: ${entries.length} 筆');

  } catch (e) {
    debugPrint('[RecordingHistoryStorage] ❌ 保存失敗: $e');
    // 保持靜默，不拋出異常
    // 目的: 避免打斷錄影流程
  }
}
```

### 容量計算

```
單筆記錄 (JSON)
├─→ 基本字段: ~150 bytes
├─→ 路徑字串: ~100 bytes (典型)
├─→ 日期 ISO 字串: ~30 bytes
└─→ 總計: ~280 bytes (典型)

100 筆記錄
├─→ 28 KB JSON 資料
├─→ 1-10 GB 視頻
├─→ 100 MB 縮圖
└─→ 1 MB CSV 軌跡

結論: JSON 檔案 < 1 MB，瓶頸在於視頻存儲
```

---

## 🔧 核心方法實現

### 方法 1: 刪除記錄 (_deleteEntry)

```dart
Future<void> _deleteEntry(RecordingHistoryEntry entry) async {
  debugPrint('[歷史頁] 開始刪除: ${entry.displayTitle}');

  try {
    // 第 1 步: 物理刪除檔案
    final videoFile = File(entry.filePath);
    if (await videoFile.exists()) {
      await videoFile.delete();
      debugPrint('[歷史頁] ✅ 刪除視頻: ${entry.filePath}');
    }

    // 第 2 步: 刪除縮圖
    if (entry.thumbnailPath != null) {
      final thumbFile = File(entry.thumbnailPath!);
      if (await thumbFile.exists()) {
        await thumbFile.delete();
        debugPrint('[歷史頁] ✅ 刪除縮圖: ${entry.thumbnailPath}');
      }
    }

    // 第 2 步: 刪除音頻檔
    final audioPath = entry.filePath.replaceFirst(RegExp(r'\.[^.]*$'), '.pcm');
    final audioFile = File(audioPath);
    if (await audioFile.exists()) {
      await audioFile.delete();
      debugPrint('[歷史頁] ✅ 刪除音頻檔: $audioPath');
    }

    // 第 4 步: 更新列表
    _entries.remove(entry);  // 從列表移除
    debugPrint('[歷史頁] 刪除後剩餘 ${_entries.length} 筆');

    // 第 5 步: 持久化
    await RecordingHistoryStorage.instance.saveHistory(_entries);

    // 第 6 步: UI 更新
    if (!mounted) return;
    setState(() {});  // 觸發重繪

    // 第 7 步: 使用者提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已刪除 ${entry.fileName}')),
    );

  } catch (e) {
    debugPrint('[歷史頁] ❌ 刪除失敗: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('刪除失敗: $e')),
    );
  }
}
```

### 方法 2: 重新命名 (_renameEntry)

```dart
Future<void> _renameEntry(RecordingHistoryEntry entry) async {
  final initialText = entry.customName != null && entry.customName!.trim().isNotEmpty
      ? entry.customName!.trim()
      : entry.displayTitle;

  debugPrint('[歷史頁] 準備重新命名: $initialText');

  // 顯示對話框取得使用者輸入
  if (!mounted) return;
  
  final controller = TextEditingController(text: initialText);
  
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('重新命名'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: '輸入新名稱'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            final newName = controller.text.trim();
            
            // 驗證
            if (newName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('名稱不能為空')),
              );
              return;
            }

            // 更新資料
            final index = _entries.indexOf(entry);
            if (index >= 0) {
              _entries[index] = entry.copyWith(customName: newName);
            }

            // 保存
            await RecordingHistoryStorage.instance.saveHistory(_entries);

            // UI 更新
            if (!mounted) return;
            setState(() {});

            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已將影片命名為 $newName')),
            );

            debugPrint('[歷史頁] ✅ 重命名完成: $newName');
          },
          child: const Text('確認'),
        ),
      ],
    ),
  );
}
```

### 方法 3: 動態生成縮圖

```dart
Future<String?> _generateThumbnailForVideo(String videoPath) async {
  try {
    debugPrint('[歷史頁] 生成縮圖: $videoPath');

    // 第 1 步: 取得縮圖路徑 (/path/video.mp4 → /path/video.jpg)
    final withoutExtension = videoPath.replaceFirst(RegExp(r'\.[^.]*$'), '');
    final thumbnailPath = '$withoutExtension.jpg';

    // 第 2 步: 檢查縮圖是否已存在
    if (await File(thumbnailPath).exists()) {
      debugPrint('[歷史頁] 縮圖已存在: $thumbnailPath');
      return thumbnailPath;
    }

    // 第 3 步: 使用 VideoThumbnail 套件生成
    final uint8list = await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxHeight: 192,  // 高度限制
      maxWidth: 144,   // 寬度限制
      quality: 75,     // JPEG 品質
      timeMs: 100,     // 視頻前 100ms 處取圖
    );

    if (uint8list == null) {
      debugPrint('[歷史頁] ⚠️ 生成縮圖失敗: 返回 null');
      return null;
    }

    // 第 4 步: 寫入檔案
    final file = File(thumbnailPath);
    await file.writeAsBytes(uint8list);
    debugPrint('[歷史頁] ✅ 縮圖已保存: $thumbnailPath (${uint8list.length} bytes)');

    return thumbnailPath;

  } catch (e) {
    debugPrint('[歷史頁] ❌ 生成縮圖失敗: $e');
    return null;
  }
}
```

### 方法 4: 檢測擊球 (_detectSwingHits)

```dart
Future<void> _detectSwingHits() async {
  debugPrint('[歷史頁] 開始檢測擊球點');
  
  if (!mounted) return;

  setState(() {
    _isDetecting = true;
  });

  try {
    // 第 1 步: 確定會話目錄
    final sessionDir = Directory(p.dirname(_selectedEntry!.filePath));

    // 第 2 步: 讀取 IMU 數據 (CSV)
    final csvPath = p.join(sessionDir.path, 'pose_landmarks.csv');
    debugPrint('[歷史頁] CSV 路徑: $csvPath');

    // 第 3 步: 讀取音頻 (PCM)
    List<double> audioPcm = [];
    const int sampleRate = 44100;
    final pcmFile = File(p.join(sessionDir.path, 'audio.pcm'));
    
    if (await pcmFile.exists()) {
      final bytes = await pcmFile.readAsBytes();
      final byteData = bytes.buffer.asByteData();
      
      // 將 PCM 字節轉換為浮點數
      audioPcm = List<double>.generate(
        bytes.length ~/ 4,  // 每個 float32 佔 4 bytes
        (i) => byteData.getFloat32(i * 4, Endian.little),
      );
      debugPrint('[歷史頁] 音頻 PCM 長度: ${audioPcm.length} 樣本');
    }

    // 第 4 步: 呼叫檢測服務
    final hits = await SwingImpactDetector.detect(
      csvPath: csvPath,
      audioPcm: audioPcm,
      audioSampleRate: sampleRate,
    );

    // 第 5 步: 保存結果
    await SwingHit.saveToSession(sessionDir.path, hits);
    debugPrint('[歷史頁] ✅ 檢測完成: ${hits.length} 個擊球');

    if (!mounted) return;
    setState(() {
      _swingHitsFuture = Future.value(hits);
      _isDetecting = false;
    });

  } catch (e) {
    debugPrint('[歷史頁] ❌ 檢測失敗: $e');
    if (!mounted) return;
    setState(() => _isDetecting = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('擊球檢測失敗: $e')),
    );
  }
}
```

---

## 🔄 狀態流轉

### RecordingHistoryPage 狀態機

```
                    [初始化]
                        ↓
                    加載中...
                     ↙    ↖
              [成功]       [失敗]
               ↓            ↓
          顯示列表    顯示錯誤提示
            ↙ ↓ ↖
    查看/編輯/刪除
        ↓ ↓ ↓
    操作中...
    ↙ ↓ ↖
[成功] [失敗]
  ↓      ↓
重新排序  顯示
      ↓   錯誤
  刷新列表
```

### 操作序列圖

```
用戶操作流程:

1️⃣ 進入頁面
   RecordingHistoryPage()
   → initState()
   → _loadFromStorage()  [async]
   → setState({ _isLoading = true })
   → UI 顯示加載動畫

2️⃣ 加載完成
   loadHistory() 返回
   → setState({ _entries = loaded, _isLoading = false })
   → UI 顯示列表

3️⃣ 用戶刪除
   _deleteEntry(entry)
   → 刪除檔案
   → 移除 _entries
   → saveHistory()  [async]
   → setState({})
   → 刷新列表

4️⃣ 用戶播放
   _playHistoryEntry(entry)
   → 檢查檔案存在
   → 導航到 VideoPlayerPage
   → 傳遞 entry 資料
```

---

## 📝 常見操作示例

### 範例 1: 載入並顯示記錄

```dart
void _initializeRecordingHistory() async {
  // 方式 1: 直接使用 storage
  final entries = await RecordingHistoryStorage.instance.loadHistory();
  debugPrint('載入了 ${entries.length} 筆記錄');
  
  // 方式 2: 通過 Provider (如果有)
  // final entries = await recordingProvider.loadHistory();
  
  // 方式 3: 按需篩選
  final originalVideos = entries
      .where((e) => e.videoType == VideoType.original)
      .toList();
  
  final goodShots = entries
      .where((e) => e.goodShot == true)
      .toList();
}
```

### 範例 2: 新增記錄

```dart
void _addNewRecording(
  String videoPath,
  int durationSeconds,
) async {
  // 計算下一輪次編號
  final maxRound = _entries
      .map((e) => e.roundIndex)
      .fold<int>(0, (a, b) => a > b ? a : b);
  
  final newEntry = RecordingHistoryEntry(
    filePath: videoPath,
    roundIndex: maxRound + 1,
    recordedAt: DateTime.now(),
    durationSeconds: durationSeconds,
    videoType: VideoType.original,
  );
  
  // 新增到列表頂部
  _entries.insert(0, newEntry);
  
  // 保存
  await RecordingHistoryStorage.instance.saveHistory(_entries);
  
  // 更新 UI
  setState(() {});
}
```

### 範例 3: 批量操作

```dart
void _batchDeleteGoodShots() async {
  // 篩選好球
  final goodShots = _entries.where((e) => e.goodShot == true).toList();
  
  if (goodShots.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('沒有好球記錄')),
    );
    return;
  }
  
  // 確認刪除
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('確認刪除'),
      content: Text('要刪除 ${goodShots.length} 筆好球嗎？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            
            // 逐個刪除
            for (final entry in goodShots) {
              await _deleteEntry(entry);
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已刪除 ${goodShots.length} 筆')),
            );
          },
          child: const Text('確認'),
        ),
      ],
    ),
  );
}
```

### 範例 4: 排序與篩選

```dart
List<RecordingHistoryEntry> _getDisplayEntries() {
  var result = List<RecordingHistoryEntry>.from(_entries);
  
  // 篩選: 好球/壞球
  if (_selectedGoodShot != null) {
    result = result.where((e) => e.goodShot == _selectedGoodShot).toList();
  }
  
  // 排序
  switch (_sortBy) {
    case _SortBy.date:
      result.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      break;
    case _SortBy.duration:
      result.sort((a, b) => b.durationSeconds.compareTo(a.durationSeconds));
      break;
    case _SortBy.peakValue:
      result.sort((a, b) {
        final aVal = a.audioCrispness ?? 0;
        final bVal = b.audioCrispness ?? 0;
        return bVal.compareTo(aVal);
      });
      break;
    case _SortBy.audioCrispness:
      result.sort((a, b) {
        final aVal = a.audioCrispness ?? 0;
        final bVal = b.audioCrispness ?? 0;
        return bVal.compareTo(aVal);
      });
      break;
  }
  
  return result;
}
```

---

## ⚡ 性能考量

### 優化策略

```
🚀 載入優化
├─→ 分頁加載 (大列表時)
├─→ 延遲縮圖生成 (首次滾動時)
└─→ 快取常用排序結果

📊 排序優化
├─→ 快速排序 O(n log n)
├─→ 快取排序結果
└─→ 增量排序 (新增時)

🎬 UI 優化
├─→ ListView.builder (虛擬列表)
├─→ RepaintBoundary 邊界隔離
├─→ FutureBuilder 異步加載
└─→ const Widget 複用

💾 存儲優化
├─→ 批量寫入 (减少 IO)
├─→ 非同步持久化
└─→ 增量備份
```

### 時間複雜度分析

```
操作              時間複雜度    頻率
─────────────────────────────────────────
載入全部記錄     O(n)        應用啟動時
新增記錄          O(1)        每次錄製後
刪除記錄          O(n)        用戶操作時
排序             O(n log n)   切換排序時
篩選             O(n)        切換篩選時
查找單筆          O(1)        按 ID 查找時
```

### 記憶體使用

```
100 筆記錄
├─→ JSON 物件: ~28 KB
├─→ Dart 物件: ~50 KB (額外開銷)
├─→ Flutter 框架: ~100 KB (ListView 等)
└─→ 總計: ~178 KB (可接受)

1000 筆記錄
├─→ JSON 物件: ~280 KB
├─→ Dart 物件: ~500 KB
├─→ Flutter 框架: ~1 MB (虛擬化)
└─→ 總計: ~2 MB (可接受)

結論: 記憶體不是瓶頸，主要是視頻文件存儲
```

---

## 🛡️ 錯誤處理

### 常見錯誤場景

#### 1. 檔案遺失

```dart
// 問題: 記錄存在但視頻檔案已被刪除
// 解決: 讀取時過濾，顯示時檢查

// 讀取時
final validated = entries
    .where((entry) => File(entry.filePath).existsSync())
    .toList();

// 播放時
if (!await File(entry.filePath).exists()) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('視頻檔案已遺失: ${entry.fileName}')),
  );
  return;
}
```

#### 2. JSON 格式錯誤

```dart
// 問題: recording_history.json 損壞或格式錯誤
// 解決: 逐行驗證，使用 try-catch

final entries = <RecordingHistoryEntry>[];
for (final item in decoded) {
  try {
    if (item is Map<String, dynamic>) {
      entries.add(RecordingHistoryEntry.fromJson(item));
    }
  } catch (e) {
    debugPrint('[警告] 跳過格式錯誤的記錄: $e');
    // 繼續處理其他記錄
  }
}
```

#### 3. 非同步操作衝突

```dart
// 問題: 同時進行保存和刪除操作
// 解決: 使用 Mutex 或排序隊列

// 簡單方案: 操作鎖
bool _isSaving = false;

Future<void> _safeDelete(RecordingHistoryEntry entry) async {
  if (_isSaving) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在保存中，請稍候')),
    );
    return;
  }
  
  _isSaving = true;
  try {
    await _deleteEntry(entry);
  } finally {
    _isSaving = false;
  }
}
```

#### 4. 狀態不同步

```dart
// 問題: UI 狀態與檔案不同步
// 解決: 操作後重新加載

Future<void> _deleteWithRefresh(RecordingHistoryEntry entry) async {
  await _deleteEntry(entry);  // 刪除
  
  // 重新加載確保同步
  final reloaded = await RecordingHistoryStorage.instance.loadHistory();
  if (!mounted) return;
  setState(() {
    _entries = reloaded;  // 使用伺服器真實狀態
  });
}
```

---

**完成**  
此文檔提供詳細的實現細節，適合開發者學習和擴展功能。
