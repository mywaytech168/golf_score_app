# 🔥 回調後自動上傳輸出文件 - 實施指南

## 📋 概述

當 Python 服務器完成視頻處理後，C# 後端會自動收集和上傳所有生成的輸出文件到資料庫，無需手動干預。

---

## ✨ 新增功能

### 自動文件收集和上傳

在回調控制器 (`CallbackController.cs`) 中新增了 **`ProcessAndUploadOutputFilesAsync()`** 方法，當接收到 `"completed"` 狀態時自動觸發：

```csharp
case "completed":
    // 處理完畢 - 標記成功
    queueItem.Status = "completed";
    queueItem.IsSuccess = true;
    queueItem.CompletedAt = callbackData.CompletedAt ?? DateTime.Now;
    
    _logger.LogInformation($"   ✅ 處理完畢，耗時: {callbackData.ProcessingDurationSeconds}秒");
    
    // 🔥 新增：在處理完成後自動收集和上傳所有輸出文件
    await ProcessAndUploadOutputFilesAsync(queueItem, callbackData);
    break;
```

---

## 📂 支持的輸出文件類型

自動上傳以下文件類型：

| 文件類型 | 路徑 | 用途 |
|---------|------|------|
| `stabilized_video` | `clip_stabilized.mp4` | 穩定化後的視頻 |
| `pose_phase_video` | `phase/clip_stabilized_pose_phase.mp4` | 姿勢分析視頻 |
| `pose_phase_trajectory_video` | `phase/clip_stabilized_pose_phase_traj.mp4` | 姿勢 + 軌跡視頻 |
| `audio_analysis` | `audio_analysis.csv` | 音頻分析數據 |
| `audio_scoring` | `audio_scoring_results.csv` | 音頻評分結果 |
| `ball_trajectory` | `traj_out/ball_trajectory.mp4` | 球軌跡視頻 |
| `trajectory_data` | `traj_out/trajectory_data.json` | 軌跡數據（JSON） |
| `processing_log` | `processing.log` | 處理日誌 |

---

## 🔄 工作流程

```
┌─────────────────────────────────────────────────────┐
│ Python 服務器完成處理                                │
│ 發送回調：callback/processing-result                 │
│ Status = "completed"                               │
└────────────┬──────────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────────────┐
│ C# 回調控制器接收請求                                 │
│ 查找隊列項目和視頻記錄                                 │
└────────────┬──────────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────────────┐
│ ProcessAndUploadOutputFilesAsync()                  │
│ 從輸出目錄收集所有生成的文件                            │
│ 例如：\\10.1.1.101\ORVIA\videos\{videoId}\...    │
└────────────┬──────────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────────────┐
│ 逐個上傳文件                                         │
│ • 檢查文件是否存在                                    │
│ • 轉換為 IFormFile 格式                             │
│ • 調用 VideoUploadService.UploadFileAsync()         │
│ • 保存文件記錄到數據庫                                │
└────────────┬──────────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────────────┐
│ 上傳完成                                            │
│ 文件記錄已存儲在 Files 表中                          │
│ 返回成功響應                                        │
└─────────────────────────────────────────────────────┘
```

---

## 📊 處理流程詳解

### 1️⃣ 輸出目錄定位

```csharp
// 從隊列項目的 SourceLocalFilePath 提取目錄
// 例如：\\10.1.1.101\ORVIA\videos\video-id-1\clip.mp4
// 目錄：\\10.1.1.101\ORVIA\videos\video-id-1\
var outputDir = Path.GetDirectoryName(queueItem.SourceLocalFilePath);
```

### 2️⃣ 文件收集

構造出需要上傳的文件列表：

```csharp
var outputFiles = new Dictionary<string, string>
{
    { "stabilized_video", Path.Combine(outputDir, "clip_stabilized.mp4") },
    { "pose_phase_video", Path.Combine(outputDir, "phase", "clip_stabilized_pose_phase.mp4") },
    { "pose_phase_trajectory_video", Path.Combine(outputDir, "phase", "clip_stabilized_pose_phase_traj.mp4") },
    { "audio_analysis", Path.Combine(outputDir, "audio_analysis.csv") },
    { "audio_scoring", Path.Combine(outputDir, "audio_scoring_results.csv") },
    { "ball_trajectory", Path.Combine(outputDir, "traj_out", "ball_trajectory.mp4") },
    { "trajectory_data", Path.Combine(outputDir, "traj_out", "trajectory_data.json") },
    { "processing_log", Path.Combine(outputDir, "processing.log") },
};
```

### 3️⃣ 檔案上傳

對每個文件：
- ✅ 檢查是否存在（不存在則跳過）
- ✅ 讀取文件內容為流
- ✅ 轉換為 `IFormFile` 格式
- ✅ 調用 `VideoUploadService.UploadFileAsync()`
- ✅ 保存文件記錄

```csharp
foreach (var (fileType, filePath) in outputFiles)
{
    if (!System.IO.File.Exists(filePath))
    {
        // 跳過不存在的文件
        _logger.LogInformation($"   ⏭️  跳過不存在的文件: {fileType}");
        skippedCount++;
        continue;
    }

    using (var fileStream = System.IO.File.OpenRead(filePath))
    {
        var formFile = new FormFile(
            fileStream,
            0,
            fileStream.Length,
            fileType,
            Path.GetFileName(filePath))
        {
            Headers = new HeaderDictionary(),
            ContentType = GetContentType(filePath)
        };

        var (success, fileRecord, error) = await _uploadService.UploadFileAsync(
            userId,
            videoId,
            fileType,
            formFile,
            sourceLocalFilePath: filePath);

        if (success && fileRecord != null)
        {
            _context.Files.Add(fileRecord);
            uploadedCount++;
            _logger.LogInformation($"   ✅ 上傳成功: {fileType}");
        }
    }
}

// 批量保存
await _context.SaveChangesAsync();
```

---

## 📝 日誌示例

當回調完成時，可以看到類似的日誌輸出：

```
📬 收到回調: QueueItemId=queue-item-123, Status=completed
📝 更新狀態: pending → completed
   ✅ 處理完畢，耗時: 5.2秒
📦 開始收集和上傳輸出文件: video-id-456
   ✅ 上傳成功: stabilized_video (clip_stabilized.mp4) - 52428800 bytes
   ✅ 上傳成功: pose_phase_video (clip_stabilized_pose_phase.mp4) - 45670000 bytes
   ⏭️  跳過不存在的文件: pose_phase_trajectory_video
   ✅ 上傳成功: audio_analysis (audio_analysis.csv) - 2048 bytes
   ✅ 上傳成功: audio_scoring (audio_scoring_results.csv) - 1536 bytes
   ⏭️  跳過不存在的文件: ball_trajectory
   ⏭️  跳過不存在的文件: trajectory_data
   ✅ 上傳成功: processing_log (processing.log) - 8192 bytes
📦 文件上傳完成: 成功 5 個，跳過 3 個
✅ 成功更新隊列項目: queue-item-123
   最終狀態: completed, 成功: True
```

---

## 🔧 技術細節

### MIME 類型自動檢測

`GetContentType()` 方法自動根據文件副檔名判斷 MIME 類型：

```csharp
private string GetContentType(string filePath)
{
    var extension = Path.GetExtension(filePath).ToLower();
    return extension switch
    {
        ".mp4" => "video/mp4",
        ".csv" => "text/csv",
        ".json" => "application/json",
        ".log" => "text/plain",
        ".mov" => "video/quicktime",
        ".avi" => "video/x-msvideo",
        ".mkv" => "video/x-matroska",
        _ => "application/octet-stream"
    };
}
```

### 文件記錄數據結構

上傳的文件會在資料庫中存儲以下信息：

```csharp
var fileRecord = new FileModel
{
    Id = Guid.NewGuid().ToString(),
    VideoId = videoId,
    Type = fileType,  // 例如："stabilized_video"
    FileName = actualFileName,  // 例如："stabilized_video.mp4"
    FilePath = filePath,  // 本地文件路徑
    FileSize = formFile.Length,  // 文件大小（字節）
    MimeType = formFile.ContentType,
    Status = "completed",
    CreatedAt = DateTime.Now,
    CompletedAt = DateTime.Now,
    SourceLocalFilePath = sourceLocalFilePath  // 原始路徑
};
```

---

## ⚠️ 注意事項

### 文件存在性檢查
- 不是所有輸出文件都會在每次處理中生成
- 例如，如果只執行穩定化，則可能沒有音頻分析文件
- 代碼會自動跳過不存在的文件，不會導致錯誤

### 異常處理
- 如果某個文件上傳失敗，會記錄錯誤但繼續處理其他文件
- 不會因為單個文件失敗而中止整個流程

### 性能考慮
- 文件上傳是順序進行的（不是並行）
- 大型視頻文件的上傳可能需要幾秒到幾十秒
- 建議使用異步操作（已實現 `async/await`）

---

## 🔌 集成點

### 必需的服務註冊

確保在 `Program.cs` 中正確註冊了 `VideoUploadService`：

```csharp
services.AddScoped<VideoUploadService>();
```

### 依賴注入

回調控制器自動接收注入的 `VideoUploadService`：

```csharp
public CallbackController(
    VideoDbContext context,
    ILogger<CallbackController> logger,
    VideoUploadService uploadService)
{
    _context = context;
    _logger = logger;
    _uploadService = uploadService;  // ✅ 注入
}
```

---

## 📊 數據庫變化

### Files 表新增記錄

每次成功上傳會在 `Files` 表中添加記錄：

```sql
SELECT * FROM Files 
WHERE VideoId = 'video-id-456' 
ORDER BY CreatedAt DESC;
```

查詢結果示例：

| Id | VideoId | Type | FileName | FileSize | CreatedAt |
|----|---------|------|----------|----------|-----------|
| file-1 | video-456 | stabilized_video | stabilized_video.mp4 | 52428800 | 2026-02-03 13:45:00 |
| file-2 | video-456 | audio_analysis | audio_analysis.csv | 2048 | 2026-02-03 13:45:05 |
| file-3 | video-456 | processing_log | processing_log.log | 8192 | 2026-02-03 13:45:10 |

---

## 🚀 使用示例

### 查詢已上傳的文件

```csharp
var video = await context.Videos.FirstOrDefaultAsync(v => v.Id == videoId);
var files = await context.Files
    .Where(f => f.VideoId == videoId)
    .OrderByDescending(f => f.CreatedAt)
    .ToListAsync();

Console.WriteLine($"視頻 {video.Name} 有 {files.Count} 個文件：");
foreach (var file in files)
{
    Console.WriteLine($"  - {file.Type}: {file.FileName} ({file.FileSize} bytes)");
}
```

### 通過類型查詢特定文件

```csharp
var stabilizedVideo = await context.Files
    .FirstOrDefaultAsync(f => f.VideoId == videoId && f.Type == "stabilized_video");

if (stabilizedVideo != null)
{
    Console.WriteLine($"穩定化視頻: {stabilizedVideo.FilePath}");
}
```

---

## 🔍 故障排除

### 日誌顯示「跳過不存在的文件」

這是正常的。不是所有文件都會在每次處理中生成，代碼會自動跳過。

檢查：
- Python 服務器是否成功執行了該步驟
- 輸出文件是否在預期的目錄中

### 日誌顯示「輸出目錄不存在」

檢查：
1. `SourceLocalFilePath` 是否正確設置
2. 網絡共享路徑是否可訪問（如果使用 UNC 路徑）
3. 文件權限是否允許讀取

### 文件上傳失敗

檢查：
1. 文件大小是否超過服務器限制
2. 磁盤空間是否充足
3. 路徑是否包含特殊字符

---

## ✅ 驗證清單

- [ ] CallbackController 已更新，包含新的 `ProcessAndUploadOutputFilesAsync()` 方法
- [ ] C# 項目編譯無誤
- [ ] VideoUploadService 已正確註冊
- [ ] 隊列項目的 `SourceLocalFilePath` 已正確設置
- [ ] Python 服務器返回的回調數據包含 `ResultData`
- [ ] 輸出文件在預期的目錄中生成
- [ ] 查看日誌確認文件上傳成功
- [ ] 數據庫 Files 表中出現了新記錄

---

## 📞 技術支持

### 關鍵文件位置
- 回調控制器: `Controllers/CallbackController.cs`
- 上傳服務: `Services/VideoUploadService.cs`
- 回調 DTO: `DTOs/ProcessingResultDtos.cs`

### 調試建議
1. 檢查 `_logger` 輸出，查看詳細的上傳日誌
2. 驗證隊列項目和視頻記錄是否存在
3. 確認文件路徑和權限

---

**實施日期**: 2026-02-03  
**狀態**: ✅ 已實施並驗證  
**編譯狀態**: ✅ 成功  
