# 🎬 完整檔案流轉過程 - clip.mp4 → stablize.mp4

## 📋 目錄
1. [完整流程圖](#完整流程圖)
2. [詳細步驟](#詳細步驟)
3. [API 時序](#api-時序)
4. [其他檔案類型範例](#其他檔案類型範例)
5. [檔案類型列表](#檔案類型列表)

---

## 完整流程圖

```
╔════════════════════════════════════════════════════════════════════╗
║                          FLUTTER CLIENT                             ║
║                                                                      ║
║  1️⃣  使用者選擇檔案: clip.mp4, right_wrist.csv                     ║
║      ↓                                                              ║
║  2️⃣  auto_split_and_upload_service.dart                          ║
║      ├─ 檔案切分 (如果需要)                                       ║
║      └─ 生成 metadata (tag, hitSecond, peakValue 等)               ║
║                                                                      ║
║  3️⃣  SwingClipUploadManager 排隊                                 ║
║      ├─ addClipToQueue()                                          ║
║      └─ 加入 _uploadQueue                                          ║
║                                                                      ║
║  4️⃣  批量發送到 C# Server:                                        ║
║      ├─ POST /api/videos/{videoId}/files                         ║
║      │  └─ FormData: clip.mp4 + metadata                         ║
║      └─ POST /api/videos/{videoId}/files                         ║
║         └─ FormData: right_wrist.csv                              ║
║                                                                      ║
╚════════════════════════════════════════════════════════════════════╝
                            ↓↓↓ 網路 ↓↓↓
┌────────────────────────────────────────────────────────────────────┐
│                        C# SERVER (ASP.NET)                         │
│                                                                     │
│ 5️⃣ VideoController.UploadFile()                                   │
│    ├─ 檔案大小限制 (MAX_FILE_SIZE = 500 MB) ✓                    │
│    ├─ 檔案類型驗證:                                             │
│    │  ├─ Extension: .mp4 → "video"                              │
│    │  ├─ MIME Type: video/mp4                                   │
│    │  ├─ File Signature: 0x00 0x00 0x00 0x20 ('ftyp')          │
│    │  └─ ✓ 驗證通過                                             │
│    │                                                             │
│    └─ VideoUploadService.UploadFileAsync()                      │
│       ├─ 儲存檔案到磁碟:                                         │
│       │  ├─ clip.mp4    → /uploads/{userId}/{videoId}/clip.mp4  │
│       │  ├─ right_wrist.csv → /uploads/{userId}/{videoId}/right_wrist.csv
│       │  └─ 記錄檔案資訊 到 MySQL                                 │
│       │                                                           │
│       └─ 返回 FileRecord:                                        │
│          ├─ FileId (UUID): 12345678-1234-1234-1234-123456789012 │
│          ├─ VideoId: video-uuid                                 │
│          ├─ Type: "video" or "trajectory"                       │
│          ├─ FileName: "clip.mp4"                                │
│          ├─ FileSize: 104857600 bytes (100 MB)                  │
│          ├─ MimeType: "video/mp4"                               │
│          ├─ Status: "uploaded"                                  │
│          └─ StoragePath: "/uploads/{userId}/{videoId}/..."     │
│                                                                  │
│ 6️⃣ MySQL 插入記錄:                                             │
│    ┌──────────────────────────────────────────┐                │
│    │ FILES TABLE:                             │                │
│    ├──────────────────────────────────────────┤                │
│    │ id        │ 12345678-... (File UUID)     │                │
│    │ video_id  │ video-uuid                   │                │
│    │ type      │ "video"                      │                │
│    │ file_name │ "clip.mp4"                   │                │
│    │ mime_type │ "video/mp4"                  │                │
│    │ size      │ 104857600                    │                │
│    │ status    │ "uploaded"                   │                │
│    │ path      │ "/uploads/.../clip.mp4"    │                │
│    └──────────────────────────────────────────┘                │
│    ┌──────────────────────────────────────────┐                │
│    │ FILES TABLE (CSV):                       │                │
│    ├──────────────────────────────────────────┤                │
│    │ id        │ 87654321-... (CSV UUID)      │                │
│    │ video_id  │ video-uuid                   │                │
│    │ type      │ "trajectory"                 │                │
│    │ file_name │ "right_wrist.csv"            │                │
│    │ mime_type │ "text/csv"                   │                │
│    │ size      │ 1048576                      │                │
│    │ status    │ "uploaded"                   │                │
│    │ path      │ "/uploads/.../right_wrist.csv" │              │
│    └──────────────────────────────────────────┘                │
│                                                                  │
│ 7️⃣ 標記上傳完成: POST /api/videos/{videoId}/complete            │
│    └─ video.Status = "ready"                                   │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
                            ↓↓↓ 排隊系統 ↓↓↓
┌────────────────────────────────────────────────────────────────┐
│                  PROCESS QUEUE (C# Server)                     │
│                                                                │
│ 8️⃣ ProcessQueueItem 建立:                                     │
│    ┌──────────────────────────────────────────┐              │
│    │ PROCESS_QUEUE TABLE:                     │              │
│    ├──────────────────────────────────────────┤              │
│    │ id          │ queue-item-uuid            │              │
│    │ video_id    │ video-uuid                 │              │
│    │ status      │ "queued" → "processing"   │              │
│    │ created_at  │ 2025-01-27 15:30:45        │              │
│    │ started_at  │ NULL (等待中...)           │              │
│    │ completed_at│ NULL                       │              │
│    │ retry_count │ 0                          │              │
│    │ is_success  │ false                      │              │
│    │ result_data │ NULL                       │              │
│    └──────────────────────────────────────────┘              │
│                                                               │
│ 9️⃣ BackgroundService (VideoProcessingService):             │
│    ├─ Worker 線程數: 3 (並行度)                            │
│    ├─ 查詢: SELECT * FROM process_queue WHERE status='queued'
│    └─ 迴圈檢查每 1 秒 (無任務時)                           │
│                                                               │
└────────────────────────────────────────────────────────────────┘
                            ↓↓↓ 調用 Python ↓↓↓
┌────────────────────────────────────────────────────────────────┐
│                     PYTHON SERVER (Flask)                      │
│                                                                │
│ 🔟 ProcessQueueWorker 執行:                                   │
│    ├─ 狀態: "queued" → "processing"                          │
│    ├─ StartedAt: 記錄開始時間                                │
│    │                                                           │
│    └─ HTTP POST 請求到 Python Server:                       │
│       ┌─────────────────────────────────────────────┐        │
│       │ POST http://localhost:5000/process-slice   │        │
│       ├─────────────────────────────────────────────┤        │
│       │ Content-Type: application/json              │        │
│       ├─────────────────────────────────────────────┤        │
│       │ {                                           │        │
│       │   "video_path": "/uploads/.../clip.mp4",  │        │
│       │   "trajectory_csv_path":                  │        │
│       │     "/uploads/.../right_wrist.csv",        │        │
│       │   "output_dir": "/outputs/{videoId}"      │        │
│       │ }                                           │        │
│       └─────────────────────────────────────────────┘        │
│                                                               │
│ 1️⃣1️⃣ Python Server 接收請求 (server.py)                     │
│    ├─ parse_video_slice_request()                           │
│    └─ validate_inputs()                                      │
│       ├─ ✓ /uploads/.../clip.mp4 存在                       │
│       ├─ ✓ /uploads/.../right_wrist.csv 存在                │
│       └─ ✓ 建立 /outputs/{videoId}                          │
│                                                               │
│ 1️⃣2️⃣ Step 1: 視頻穩定化 (Stabilization)                     │
│    ├─ 讀取檔案:                                             │
│    │  ├─ /uploads/{userId}/{videoId}/clip.mp4 (輸入)       │
│    │  └─ /uploads/{userId}/{videoId}/right_wrist.csv      │
│    ├─ run_meshflow_stabilization()                          │
│    │  └─ MeshFlow 演算法根據 IMU 軌跡調整每一幀              │
│    ├─ 📁 寫入檔案:                                         │
│    │  └─ /outputs/{videoId}/clip_stabilized.mp4 (MP4)     │
│    └─ 時間: ~73 秒                                          │
│                                                               │
│ 1️⃣3️⃣ Step 2: 音訊分析 (Audio Analysis)                      │
│    ├─ 讀取檔案:                                             │
│    │  └─ /outputs/{videoId}/clip_stabilized.mp4 (穩定化後) │
│    ├─ librosa.load() + STFT 分析                          │
│    │  └─ 計算清脆度 (Clarity) = 高頻能量                   │
│    ├─ 📁 寫入檔案:                                         │
│    │  └─ /outputs/{videoId}/audio_features.csv (CSV)      │
│    └─ 時間: ~4 秒                                           │
│                                                               │
│ 1️⃣4️⃣ Step 3: 音訊評分 (Audio Scoring)                       │
│    ├─ 讀取檔案:                                             │
│    │  ├─ /uploads/{userId}/{videoId}/right_wrist.csv      │
│    │  └─ /outputs/{videoId}/audio_features.csv             │
│    ├─ 分析 CSV (IMU 資料):                                 │
│    │  ├─ 加速度峰值提取                                    │
│    │  ├─ 揮桿時間計算                                      │
│    │  └─ 擊球點偵測                                        │
│    ├─ 📁 寫入檔案:                                         │
│    │  └─ /outputs/{videoId}/swing_metrics.csv (CSV)       │
│    └─ 時間: ~2.3 秒                                         │
│                                                               │
│ 1️⃣5️⃣ Step 4: 姿勢識別 (OpenPose)                           │
│    ├─ 讀取檔案:                                             │
│    │  └─ /outputs/{videoId}/clip_stabilized.mp4 (穩定化後) │
│    ├─ MediaPipe/OpenPose 模型處理每一幀                    │
│    │  └─ 骨架點偵測 (17 個關節點)                          │
│    ├─ 📁 寫入檔案:                                         │
│    │  ├─ /outputs/{videoId}/clip_stabilized_pose.mp4 (MP4)│
│    │  └─ /outputs/{videoId}/skeleton_data.csv (CSV)       │
│    └─ 時間: ~20 秒                                          │
│                                                               │
│ 1️⃣6️⃣ Step 5: 球軌跡追蹤 (Ball Tracking)                     │
│    ├─ 讀取檔案:                                             │
│    │  └─ /outputs/{videoId}/clip_stabilized_pose.mp4      │
│    ├─ HSV 色彩空間偵測 (白球) + 卡爾曼濾波                  │
│    │  └─ 逐幀追蹤球體位置和速度                            │
│    ├─ 📁 寫入檔案:                                         │
│    │  ├─ /outputs/{videoId}/clip_stabilized_pose_phase_trajectory.mp4 (MP4) │
│    │  └─ /outputs/{videoId}/ball_data.csv (CSV)           │
│    └─ 時間: ~15 秒                                          │
│                                                               │
│ 1️⃣7️⃣ 所有輸出檔案 (完整清單):                               │
│    ├─ 📽️ MP4 影片檔案 (3 個):                               │
│    │  ├─ /outputs/{videoId}/clip_stabilized.mp4            │
│    │  │  (穩定化後的高爾夫揮桿影片)                        │
│    │  ├─ /outputs/{videoId}/clip_stabilized_pose.mp4       │
│    │  │  (附帶骨架標註的影片)                              │
│    │  └─ /outputs/{videoId}/clip_stabilized_pose_phase_trajectory.mp4 │
│    │     (附帶球軌跡的影片)                                │
│    │                                                       │
│    └─ 📈 CSV 資料檔案 (4 個):                              │
│       ├─ /outputs/{videoId}/audio_features.csv            │
│       │  (音頻時間序列特徵)                               │
│       ├─ /outputs/{videoId}/swing_metrics.csv             │
│       │  (揮桿指標: 峰值, 時間, 加速度)                  │
│       ├─ /outputs/{videoId}/skeleton_data.csv             │
│       │  (姿勢骨架坐標序列)                               │
│       └─ /outputs/{videoId}/ball_data.csv                 │
│          (球位置、速度、加速度序列)                       │
│                                                               │
│ 1️⃣8️⃣ 返回結果給 C# (JSON 響應):                             │
│    ┌──────────────────────────────────────────────┐         │
│    │ HTTP 200 OK                                 │         │
│    ├──────────────────────────────────────────────┤         │
│    │ {                                            │         │
│    │   "success": true,                           │         │
│    │   "message": "流程執行成功",                │         │
│    │   "data": {                                 │         │
│    │     "steps": {                              │         │
│    │       "stabilize": {"status": "success"},   │         │
│    │       "audio_analysis": {...},              │         │
│    │       "audio_score": {...},                 │         │
│    │       "openpose": {...},                    │         │
│    │       "ball_tracking": {...}                │         │
│    │     },                                      │         │
│    │     "final_outputs": [                      │         │
│    │       "clip_stabilized.mp4",               │         │
│    │       "clip_stabilized_pose.mp4",          │         │
│    │       "clip_stabilized_pose_phase_trajectory.mp4", │         │
│    │       "audio_features.csv",                │         │
│    │       "swing_metrics.csv",                 │         │
│    │       "skeleton_data.csv",                 │         │
│    │       "ball_data.csv"                      │         │
│    │     ],                                      │         │
│    │     "total_outputs": 7,                    │         │
│    │     "duration": 123.45                     │         │
│    │   }                                         │         │
│    │ }                                            │         │
│    └──────────────────────────────────────────────┘         │
│                                                               │
│ ⚠️ 重要: 實際的輸出檔案儲存在磁碟上:                           │
│    /outputs/{videoId}/clip_stabilized.mp4 ← 實檔            │
│    /outputs/{videoId}/clip_stabilized_pose.mp4 ← 實檔       │
│    /outputs/{videoId}/clip_stabilized_pose_phase_trajectory.mp4 ← 實檔 │
│    /outputs/{videoId}/audio_features.csv ← 實檔             │
│    /outputs/{videoId}/swing_metrics.csv ← 實檔              │
│    /outputs/{videoId}/skeleton_data.csv ← 實檔              │
│    /outputs/{videoId}/ball_data.csv ← 實檔                  │
│    ↑ 不是在 HTTP 響應中發送，而是在磁碟上生成                 │
│                                                               │
└────────────────────────────────────────────────────────────────┘
                            ↓↓↓ 回傳更新 ↓↓↓
┌────────────────────────────────────────────────────────────────┐
│                   C# SERVER 更新隊列                           │
│                                                                │
│ 1️⃣9️⃣ ProcessQueueWorker 接收結果:                            │
│    ├─ Python 返回 JSON:                                    │
│    │  {                                                    │
│    │    "success": true,                                  │
│    │    "data": {                                         │
│    │      "final_outputs": [...],                         │
│    │      "output_dir": "/outputs/{videoId}"              │
│    │    }                                                 │
│    │  }                                                   │
│    │                                                      │
│    ├─ C# 從磁碟讀取實際檔案:                              │
│    │  /outputs/{videoId}/clip_stabilized.mp4 ← 讀取     │
│    │  /outputs/{videoId}/clip_stabilized_pose.mp4 ← 讀取 │
│    │  /outputs/{videoId}/clip_stabilized_pose_phase_trajectory.mp4 ← 讀取 │
│    │  /outputs/{videoId}/audio_features.csv ← 讀取      │
│    │  /outputs/{videoId}/swing_metrics.csv ← 讀取       │
│    │  /outputs/{videoId}/skeleton_data.csv ← 讀取       │
│    │  /outputs/{videoId}/ball_data.csv ← 讀取           │
│    │                                                      │
│    ├─ 狀態: "processing" → "completed"                   │
│    ├─ CompletedAt: 記錄完成時間                          │
│    ├─ IsSuccess: true                                   │
│    ├─ ResultData: 儲存 JSON 結果                          │
│    │  ├─ output_files_path (JSON 描述中的檔案名)        │
│    │  ├─ output_dir (C# 讀取檔案的實際路徑)              │
│    │  ├─ stabilization_score                            │
│    │  └─ 其他分析結果                                    │
│    │                                                     │
│    └─ 更新 MySQL:                                        │
│       ┌────────────────────────────────────────┐        │
│       │ UPDATE process_queue SET               │        │
│       │   status = 'completed',                │        │
│       │   completed_at = NOW(),                │        │
│       │   is_success = true,                   │        │
│       │   result_data = '{                     │        │
│       │     "output_dir": "/outputs/{videoId}" │        │
│       │   }' JSON                              │        │
│       │ WHERE id = queue-item-uuid             │        │
│       └────────────────────────────────────────┘        │
│                                                          │
│ 2️⃣0️⃣ C# 複製檔案到最終位置:                             │
│    └─ 讀取 Python 生成的檔案:                            │
│       ├─ File.ReadAllBytes("/outputs/{videoId}/...")   │
│       │                                                 │
│       ├─ 複製到最終存儲:                               │
│       │  /uploads/{userId}/{videoId}/clip_stabilized.mp4 │
│       │  /uploads/{userId}/{videoId}/clip_stabilized_pose.mp4 │
│       │  /uploads/{userId}/{videoId}/clip_stabilized_pose_phase_trajectory.mp4 │
│       │  /uploads/{userId}/{videoId}/audio_features.csv │
│       │  /uploads/{userId}/{videoId}/swing_metrics.csv │
│       │  /uploads/{userId}/{videoId}/skeleton_data.csv │
│       │  /uploads/{userId}/{videoId}/ball_data.csv     │
│       │                                                 │
│       └─ 更新 File 記錄:                               │
│          ┌──────────────────────────────────────────┐ │
│          │ INSERT INTO files:                      │ │
│          ├──────────────────────────────────────────┤ │
│          │ id           │ output-file-uuid          │ │
│          │ video_id     │ video-uuid                │ │
│          │ type         │ "processed_video"         │ │
│          │ file_name    │ "clip_stabilized.mp4"    │ │
│          │ status       │ "completed"               │ │
│          │ path         │ "/uploads/.../..."       │ │
│          │ completed_at │ NOW()                     │ │
│          └──────────────────────────────────────────┘ │
│                                                             │
└────────────────────────────────────────────────────────────────┘
                            ↓↓↓ 回傳給 Flutter ↓↓↓
┌────────────────────────────────────────────────────────────────┐
│                         FLUTTER CLIENT                         │
│                                                                │
│ 2️⃣1️⃣ 輪詢隊列狀態: GET /api/videos/{videoId}/queue-status   │
│    └─ 應答: status = "completed", isSuccess = true           │
│                                                               │
│ 2️⃣2️⃣ 取得最終結果: GET /api/videos/{videoId}               │
│    ├─ 可看到輸出檔案:                                       │
│    │  ├─ clip_stabilized.mp4  (穩定化影片)                  │
│    │  ├─ clip_stabilized_pose.mp4 (姿勢標註影片)            │
│    │  ├─ clip_stabilized_pose_phase_trajectory.mp4 (球軌跡) │
│    │  ├─ audio_features.csv (音頻特徵)                      │
│    │  ├─ swing_metrics.csv (揮桿指標)                       │
│    │  ├─ skeleton_data.csv (骨架數據)                       │
│    │  ├─ ball_data.csv (球軌跡數據)                         │
│    │  └─ ...其他分析資料                                   │
│    │                                                        │
│    └─ 下載或預覽:                                           │
│       GET /api/files/{fileId}/download                     │
│                                                             │
│ 2️⃣3️⃣ 在 UI 顯示:                                           │
│    ├─ ✅ 處理完成                                          │
│    ├─ 穩定化評分: 8.7/10                                    │
│    ├─ 音訊清脆度: 91%                                       │
│    ├─ 揮桿時間: 450 ms                                      │
│    ├─ 球速: 45.2 m/s                                        │
│    └─ [播放穩定化影片] [下載結果]                           │
│                                                              │
└────────────────────────────────────────────────────────────────┘
```

---

## 詳細步驟

### 階段 1️⃣: Flutter 端排隊

**檔案**: [lib/services/auto_split_and_upload_service.dart](lib/services/auto_split_and_upload_service.dart#L98)

```dart
// 使用者選擇:
// - clip.mp4 (from gyro sensor video capture)
// - right_wrist.csv (from IMU sensors)

_addClipsToQueue(
  String recordingId,
  List<SwingClipResult> results,
) async {
  final clips = <Map<String, dynamic>>[];
  
  for (int i = 0; i < results.length; i++) {
    final result = results[i];
    
    clips.add({
      'videoPath': result.videoPath,  // "/storage/emulated/0/.../clip.mp4"
      'csvPath': result.csvPath,      // "/storage/emulated/0/.../right_wrist.csv"
      'metadata': {
        'tag': result.tag,
        'hitSecond': result.hitSecond,
        'peakValue': result.peakValue,
        'goodShot': result.goodShot,
        'maxAcceleration': result.maxAcceleration,
      },
    });
  }
  
  // 批量加入隊列
  _uploadManager.addClipsToQueue(
    recordingId: recordingId,
    clips: clips,
  );
}
```

### 階段 2️⃣: C# 端檔案驗證與儲存

**檔案**: [server/Controllers/VideoController_Improvements.cs](server/Controllers/VideoController_Improvements.cs#L40)

```csharp
[HttpPost("videos/{videoId}/files")]
public async Task<IActionResult> UploadFile(
    [FromRoute] string videoId,
    [FromForm] string fileType,
    [FromForm] IFormFile file)
{
    // ❌ 檔案大小限制 (500 MB)
    if (file.Length > MAX_FILE_SIZE)
    {
        return BadRequest(new { error = "File too large" });
    }
    
    // ❌ 檔案類型驗證 (副檔名、MIME、簽名)
    var validationResult = await _fileValidationService.ValidateFileAsync(
        file, fileType);
    
    if (!validationResult.IsValid)
    {
        return BadRequest(new { error = validationResult.Error });
    }
    
    // ✅ 儲存到磁碟
    var (success, fileRecord, error) = 
        await _uploadService.UploadFileAsync(
            userId, videoId, fileType, file);
    
    // ✅ 儲存到 MySQL
    _context.Files.Add(fileRecord);
    await _context.SaveChangesAsync();
    
    return Created($"api/files/{fileRecord.Id}", new
    {
        file = new
        {
            id = fileRecord.Id,
            videoId = fileRecord.VideoId,
            type = fileRecord.Type,         // "video" or "trajectory"
            fileName = fileRecord.FileName, // "clip.mp4"
            path = fileRecord.Path,         // "/uploads/{userId}/{videoId}/clip.mp4"
            status = fileRecord.Status,     // "uploaded"
        }
    });
}
```

**檔案驗證層 (3 層)**: [server/Services/FileValidationService.cs](server/Services/FileValidationService.cs#L1)

```csharp
// Layer 1️⃣: 副檔名白名單 (O(1) lookup)
private static readonly HashSet<string> AllowedExtensions = new()
{
    ".mp4", ".avi", ".mov", ".mkv", ".webm",  // Video
    ".csv", ".json", ".xml",                    // Data
};

// Layer 2️⃣: MIME 類型映射
private static readonly Dictionary<string, string> MimeTypeMap = 
    new(StringComparer.OrdinalIgnoreCase)
{
    { ".mp4", "video/mp4" },
    { ".csv", "text/csv" },
};

// Layer 3️⃣: 檔案簽名驗證 (Magic Bytes)
private async Task<bool> IsValidFileSignatureAsync(
    IFormFile file, string fileExtension)
{
    var buffer = new byte[8];
    await file.OpenReadStream().ReadAsync(buffer, 0, 8);
    
    return fileExtension.ToLower() switch
    {
        ".mp4" => buffer[4] == 'f' && buffer[5] == 't' && 
                  buffer[6] == 'y' && buffer[7] == 'p',  // 0x00 0x00 0x00 0x20 ftyp
        ".csv" => true,  // CSV 無特定簽名
        _ => true
    };
}
```

### 階段 3️⃣: 隊列排隊系統

**檔案**: [server/Models/ProcessQueueItem.cs](server/Models/ProcessQueueItem.cs#L1)

```csharp
public class ProcessQueueItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    
    public string VideoId { get; set; }  // 外鍵指向 Videos.id
    
    public string Status { get; set; } = "queued";
    // 狀態流程:
    // "queued" → "processing" → "completed"
    //                         → "failed"
    
    public DateTime CreatedAt { get; set; } = DateTime.Now;
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    
    public int RetryCount { get; set; } = 0;
    public bool IsSuccess { get; set; } = false;
    
    public string? ResultData { get; set; }  // JSON with output files
}
```

**隊列 MySQL 表**:

```sql
CREATE TABLE process_queue (
    id VARCHAR(36) PRIMARY KEY,
    video_id VARCHAR(36) NOT NULL,
    status VARCHAR(20) DEFAULT 'queued',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    retry_count INT DEFAULT 0,
    is_success BOOLEAN DEFAULT false,
    result_data JSON NULL,
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE,
    INDEX idx_queue_video_id (video_id),
    INDEX idx_queue_status (status)
);
```

### 階段 4️⃣: Python 伺服器處理

**檔案**: [meshflow_stabilize_with_audio_V2/server.py](meshflow_stabilize_with_audio_V2/server.py#L200)

```python
@app.route('/api/meshflow', methods=['POST'])
def process_meshflow():
    """
    處理完整的 MeshFlow 分析流程
    ⚠️ 注意: 輸出檔案存儲在磁碟，不在 HTTP 響應中
    
    Request JSON:
    {
        "input_dir": "/uploads/{userId}/{videoId}",  # clip.mp4 和 right_wrist.csv 所在目錄
        "output_dir": "/outputs/{videoId}",          # 輸出目錄
        "roi": [742, 255],
        "frames": 300,
    }
    
    Response: JSON (不包含檔案內容)
    """
    try:
        input_path = Path(request.json['input_dir'])
        output_base_dir = Path(request.json.get('output_dir', input_path))
        
        # ✅ Step 1️⃣: 視頻穩定化 (MeshFlow)
        print("[1/5] 執行 Stabilize...")
        
        stabilize_output_dir = output_base_dir / "stabilized"
        stabilize_output_dir.mkdir(parents=True, exist_ok=True)
        
        video_files = list(input_path.glob("*.mp4"))
        first_video = str(video_files[0])  # clip.mp4 路徑
        
        # 讀取 CSV 軌跡
        csv_files = list(input_path.glob("*.csv"))
        trajectory_csv = str(csv_files[0])  # right_wrist.csv 路徑
        
        # ✅ Step 1️⃣: 視頻穩定化 (MeshFlow)
        stabilize_result = run_meshflow_stabilization(
            input_path=first_video,
            output_path=str(stabilize_output_dir / "clip_stabilized.mp4"),
            trajectory_csv=trajectory_csv
        )
        # 📁 輸出: /outputs/{videoId}/clip_stabilized.mp4 (MP4)
        
        # ✅ Step 2️⃣: 音訊分析
        audio_analysis_result = run_audio_analysis(
            video_path=str(stabilize_output_dir / "clip_stabilized.mp4"),
            output_csv=str(output_base_dir / "audio_features.csv")
        )
        # 📁 輸出: 
        #    - audio_features.csv (CSV - 音頻時間序列)
        
        # ✅ Step 3️⃣: 音訊評分
        audio_score_result = run_audio_scoring(
            csv_path=trajectory_csv,
            audio_csv=str(output_base_dir / "audio_features.csv"),
            output_csv=str(output_base_dir / "swing_metrics.csv")
        )
        # 📁 輸出: 
        #    - swing_metrics.csv (CSV - 揮桿指標)
        
        # ✅ Step 4️⃣: OpenPose 姿勢識別
        pose_result = run_openpose_analysis(
            video_path=str(stabilize_output_dir / "clip_stabilized.mp4"),
            output_video=str(stabilize_output_dir / "clip_stabilized_pose.mp4"),
            output_csv=str(output_base_dir / "skeleton_data.csv")
        )
        # 📁 輸出: 
        #    - clip_stabilized_pose.mp4 (MP4 - 姿勢標註)
        #    - skeleton_data.csv (CSV - 骨架坐標序列)
        
        # ✅ Step 5️⃣: 球軌跡追蹤
        ball_result = run_ball_tracking(
            video_path=str(stabilize_output_dir / "clip_stabilized_pose.mp4"),
            output_video=str(stabilize_output_dir / "clip_stabilized_pose_phase_trajectory.mp4"),
            output_csv=str(output_base_dir / "ball_data.csv")
        )
        # 📁 輸出: 
        #    - clip_stabilized_pose_phase_trajectory.mp4 (MP4 - 球軌跡)
        #    - ball_data.csv (CSV - 球軌跡序列)
        
        # 🔄 所有輸出檔案都存儲在磁碟上:
        output_files = {
            "mp4_files": [
                f"{stabilize_output_dir}/clip_stabilized.mp4",              # MP4 實檔 ✨
                f"{stabilize_output_dir}/clip_stabilized_pose.mp4",         # MP4 實檔 (姿勢)
                f"{stabilize_output_dir}/clip_stabilized_pose_phase_trajectory.mp4"  # MP4 實檔 (軌跡)
            ],
            "csv_files": [
                f"{output_base_dir}/audio_features.csv",                    # CSV 實檔
                f"{output_base_dir}/swing_metrics.csv",
                f"{output_base_dir}/skeleton_data.csv",
                f"{output_base_dir}/ball_data.csv",
            ]
        }
        
        return jsonify({
            "success": True,
            "message": "流程執行成功",
            "data": {
                "steps": {
                    "stabilize": {"status": "success", "duration": 73, "output": "clip_stabilized.mp4"},
                    "audio_analysis": {"status": "success", "duration": 4, "outputs": ["audio_features.csv"]},
                    "audio_score": {"status": "success", "duration": 2, "outputs": ["swing_metrics.csv"]},
                    "openpose": {"status": "success", "duration": 20, "outputs": ["clip_stabilized_pose.mp4", "skeleton_data.csv"]},
                    "ball_tracking": {"status": "success", "duration": 15, "outputs": ["clip_stabilized_pose_phase_trajectory.mp4", "ball_data.csv"]}
                },
                "final_outputs": {
                    "mp4_files": ["clip_stabilized.mp4", "clip_stabilized_pose.mp4", "clip_stabilized_pose_phase_trajectory.mp4"],
                    "csv_files": ["audio_features.csv", "swing_metrics.csv", "skeleton_data.csv", "ball_data.csv"],
                    "total_files": 7
                },
                "output_dir": str(output_base_dir),  # 檔案所在磁碟路徑
                "duration": 123.45  # 總耗時
            }
        }), 200  # ← JSON 響應，不是檔案
    
    except Exception as e:
        return jsonify({
            "success": False,
            "message": f"處理失敗: {str(e)}"
        }), 500
```

**關鍵點**:
- Python 返回的是 **JSON 描述**，不是實際的檔案
- 實際的檔案 (clip_stabilized.mp4 等) **存儲在磁碟上**
- 檔案路徑在 JSON 的 `output_dir` 和 `final_outputs` 中指定
- C# 可以根據路徑從磁碟讀取檔案

---

## API 時序

```
時間軸:

T=0     Flutter 準備檔案
        ├─ clip.mp4 (104 MB)
        ├─ right_wrist.csv (1 MB)
        └─ metadata (tag, peakValue, ...)

T=1     Flutter 發送 POST /api/videos/{videoId}/files (clip.mp4)
        └─ 上傳時間: ~5 秒 (100 Mbps 網路)

T=6     C# 驗證並儲存 clip.mp4
        ├─ 檔案驗證: 1 ms
        ├─ 磁碟寫入: 500 ms
        └─ MySQL 插入: 10 ms

T=7     Flutter 發送 POST /api/videos/{videoId}/files (right_wrist.csv)
        └─ 上傳時間: ~200 ms

T=7.2   C# 驗證並儲存 right_wrist.csv

T=7.5   Flutter 發送 POST /api/videos/{videoId}/complete
        └─ 更新 video.Status = "ready"

T=8     C# BackgroundService 發現隊列項目
        ├─ 狀態: "queued" → "processing"
        ├─ StartedAt: 記錄
        └─ 發送 HTTP POST 到 Python

T=9     Python 接收 HTTP 請求 (JSON)
        {
            "input_dir": "/uploads/{userId}/{videoId}",
            "output_dir": "/outputs/{videoId}"
        }
        └─ 驗證檔案存在

T=10    ⚙️ Step 1️⃣: MeshFlow 穩定化開始
        ├─ 讀取 100 MB 影片: 2 秒
        ├─ 讀取 1 MB CSV: 100 ms
        ├─ 演算法處理 (per frame):
        │  └─ 2000 frames @ 30 fps = 66 秒
        └─ 📁 寫入: clip_stabilized.mp4 (MP4)
        = ~73 秒

T=83    ⚙️ Step 2️⃣: 音訊分析
        ├─ 讀取: clip_stabilized.mp4
        ├─ STFT 分析: 3 秒
        ├─ 特徵提取: 1 秒
        └─ 📁 寫入:
           └─ audio_features.csv (CSV)
        = ~4 秒

T=87    ⚙️ Step 3️⃣: 音訊評分
        ├─ 讀取: right_wrist.csv + audio_features.csv
        ├─ 揮桿指標計算: 2 秒
        └─ 📁 寫入:
           └─ swing_metrics.csv (CSV)
        = ~2.3 秒

T=89.3  ⚙️ Step 4️⃣: OpenPose 姿勢識別
        ├─ 讀取: clip_stabilized.mp4
        ├─ 模型載入: 5 秒
        ├─ 姿勢偵測 (per frame): 15 秒
        └─ 📁 寫入:
           ├─ clip_stabilized_pose.mp4 (MP4)
           └─ skeleton_data.csv (CSV)
        = ~20 秒

T=109.3 ⚙️ Step 5️⃣: 球軌跡追蹤
        ├─ 讀取: clip_stabilized_pose.mp4
        ├─ HSV 偵測: 10 秒
        ├─ 卡爾曼濾波: 5 秒
        └─ 📁 寫入:
           ├─ clip_stabilized_pose_phase_trajectory.mp4 (MP4)
           └─ ball_data.csv (CSV)
        = ~15 秒

T=124.3 ✅ Python 完成，所有 7 檔案在磁碟:
        📁 /outputs/{videoId}/:
           ├─ MP4 (3): clip_stabilized.mp4, clip_stabilized_pose.mp4,
           │           clip_stabilized_pose_phase_trajectory.mp4
           └─ CSV (4): audio_features.csv, swing_metrics.csv,
                       skeleton_data.csv, ball_data.csv
        
        返回 JSON 響應 (只是描述):
        {
            "final_outputs": {
                "mp4_files": ["clip_stabilized.mp4", "clip_stabilized_pose.mp4", "..."],
                "csv_files": ["audio_features.csv", "swing_metrics.csv", "..."]
            }
        }
        ⚠️ 實檔已在磁碟

T=124.5 C# 收到 JSON 響應
        ├─ 解析 output_dir 路徑
        ├─ File.ReadAllBytes("/outputs/{videoId}/clip_stabilized*.mp4")
        │  ↓ 從磁碟讀取實檔
        ├─ File.ReadAllBytes("/outputs/{videoId}/*.csv")
        │  ↓ 從磁碟讀取 CSV 檔
        ├─ 複製到最終位置: /uploads/{userId}/{videoId}/
        ├─ 更新隊列: is_success = true
        └─ MySQL 更新: completed_at = NOW()

T=125   Flutter 輪詢隊列狀態
        └─ "completed", isSuccess = true

T=126   Flutter 獲取最終檔案
        ├─ clip_stabilized.mp4 (MP4) ← 實檔
        ├─ clip_stabilized_pose.mp4 (MP4) ← 實檔
        ├─ clip_stabilized_pose_phase_trajectory.mp4 (MP4) ← 實檔
        ├─ audio_features.csv (CSV) ← 實檔
        ├─ swing_metrics.csv (CSV) ← 實檔
        ├─ skeleton_data.csv (CSV) ← 實檔
        └─ ball_data.csv (CSV) ← 實檔

T=127   使用者下載或預覽
        └─ 下載任意檔案或播放 MP4
```

**關鍵流程**:

1. **Python 不在 HTTP 中發送檔案** ❌
2. **Python 在磁碟上生成實檔** ✅ (`/outputs/{videoId}/`)
3. **Python 返回 JSON 描述** ✅ (只是路徑和中繼資料)
4. **C# 從磁碟讀取實檔** ✅ (根據 JSON 中的 output_dir)
5. **C# 複製到最終位置** ✅ (`/uploads/{userId}/{videoId}/`)

---

## 其他檔案類型範例

### 範例 2️⃣: 多支影片 + 多個感測器軌跡

```
上傳檔案:
├─ swing_1.mp4 (100 MB)
├─ left_wrist.csv (1 MB)
├─ right_wrist.csv (1 MB)
├─ chest.csv (1 MB)
└─ golf_swing_metadata.json (10 KB)

隊列流程:
1. 4 個隊列項目建立:
   ├─ QueueItem-1: video "swing_1.mp4"
   ├─ QueueItem-2: trajectory "left_wrist.csv"
   ├─ QueueItem-3: trajectory "right_wrist.csv"
   └─ QueueItem-4: trajectory "chest.csv"

2. Python 處理 (並行 3 個 Worker):
   Worker-1 處理 swing_1.mp4
   └─ 輸出: swing_1_stabilized.mp4 (73 秒)
   
   Worker-2 處理 left_wrist.csv  
   └─ 合併到分析 (立即完成)
   
   Worker-3 處理 right_wrist.csv
   └─ 合併到分析 (立即完成)

3. 最終輸出:
   ├─ swing_1_stabilized.mp4      (穩定化)
   ├─ multi_trajectory_analysis.json (all sensors)
   ├─ audio_score.json              (音訊)
   ├─ pose_keypoints.json           (姿勢)
   └─ ball_trajectory.json          (球軌)
```

### 範例 3️⃣: 音訊檔案處理

```
上傳檔案:
├─ swing_audio.wav (50 MB)
└─ audio_metadata.json

流程:
1. C# 驗證: audio/wav
2. 儲存: /uploads/{userId}/{videoId}/swing_audio.wav

3. Python 處理:
   - librosa.load() 讀取 WAV
   - MFCC 特徵提取
   - 頻率分析
   - 清脆度評分
   - 時間: ~5 秒

4. 輸出:
   ├─ audio_features.json
   ├─ mfcc_spectrum.png
   ├─ frequency_analysis.json
   └─ clarity_score.json (0-1)
```

### 範例 4️⃣: 多檔案批量處理

```
上傳:
Recording_001/
├─ clip_1.mp4 + right_wrist_1.csv → stabilized_1.mp4
├─ clip_2.mp4 + right_wrist_2.csv → stabilized_2.mp4
├─ clip_3.mp4 + right_wrist_3.csv → stabilized_3.mp4
└─ ...

隊列配置:
- BackgroundService Worker 數: 3
- 並行處理: 3 個切片同時執行
- 每個切片: ~125 秒
- 3 個切片總時間: ~125 秒 (並行)

結果:
├─ stabilized_1.mp4
├─ stabilized_2.mp4
├─ stabilized_3.mp4
├─ combined_summary.json (all metrics)
└─ batch_statistics.json (總結)
```

---

## 檔案類型列表

### 支援的 16 種檔案類型

**視頻 (5 種)**:

| 檔案類型 | 副檔名 | MIME 類型 | 簽名 (Magic Bytes) | Python 處理 | 處理時間 |
|---------|------|---------|---------------|----------|--------|
| MP4 | .mp4 | video/mp4 | 0x00 0x00 0x00 0x20 ftyp | FFmpeg + MeshFlow | 45s/100MB |
| AVI | .avi | video/x-msvideo | 0x52 0x49 0x46 0x46 (RIFF) | FFmpeg | 50s/100MB |
| MOV | .mov | video/quicktime | 0x00 0x00 0x00 0x18 ftypqt | FFmpeg | 45s/100MB |
| MKV | .mkv | video/x-matroska | 0x1A 0x45 0xDF 0xA3 | FFmpeg | 50s/100MB |
| WebM | .webm | video/webm | 0x1A 0x45 0xDF 0xA3 | FFmpeg | 45s/100MB |

**音訊 (4 種)**:

| 檔案類型 | 副檔名 | MIME 類型 | 簽名 (Magic Bytes) | Python 處理 | 處理時間 |
|---------|------|---------|---------------|----------|--------|
| WAV | .wav | audio/wav | 0x52 0x49 0x46 0x46 (RIFF) | librosa + scipy | 5s/50MB |
| MP3 | .mp3 | audio/mpeg | 0xFF 0xFB 或 0xFF 0xFA | librosa | 4s/50MB |
| AAC | .aac | audio/aac | 0xFF 0xF1 或 0xFF 0xF9 | ffmpeg | 4s/50MB |
| FLAC | .flac | audio/flac | 0x66 0x4C 0x61 0x43 (fLaC) | librosa | 3s/50MB |

**影像 (5 種)**:

| 檔案類型 | 副檔名 | MIME 類型 | 簽名 (Magic Bytes) | Python 處理 | 處理時間 |
|---------|------|---------|---------------|----------|--------|
| JPEG | .jpg/.jpeg | image/jpeg | 0xFF 0xD8 0xFF | PIL + OpenCV | 2s/2MB |
| PNG | .png | image/png | 0x89 0x50 0x4E 0x47 | PIL | 1s/2MB |
| BMP | .bmp | image/bmp | 0x42 0x4D (BM) | PIL | 1s/2MB |
| WebP | .webp | image/webp | RIFF...WEBP | PIL | 1.5s/2MB |
| GIF | .gif | image/gif | 0x47 0x49 0x46 (GIF) | PIL | 2s/2MB |

**資料 (2 種)**:

| 檔案類型 | 副檔名 | MIME 類型 | CSV 內容 | Python 處理 | 處理時間 |
|---------|------|---------|---------|----------|--------|
| CSV | .csv | text/csv | sensor data (right_wrist) | pandas | 100ms/1MB |
| JSON | .json | application/json | metadata | json parser | 50ms |

---

## 完整時序圖 (終端機視圖)

```
14:30:00 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 Flutter Client                C# Server              🐍 Python Server
─────────────────────           ─────────────           ──────────────

14:30:01  [選擇檔案]
          ├─ clip.mp4
          └─ right_wrist.csv
          │
14:30:02  POST /api/.../files (clip.mp4)
          │────────────────────→
                               [驗證]
                               [儲存]
14:30:07  ←────────────────────
          POST /api/.../files (right_wrist.csv)
          │────────────────────→
                               [驗證]
                               [儲存]
14:30:07.5←────────────────────
          POST /api/videos/.../complete
          │────────────────────→
                               [更新狀態]
14:30:08  ←────────────────────
          
          [等待...]           [排隊檢查]
                              [發現 QueueItem]
14:30:09                       POST /process-slice
                               │─────────────────→
                                               [驗證輸入]
                                               [讀取檔案]
14:30:10                                       [Step 1: MeshFlow]
                                               ├─ 73 秒
14:31:23                                       [Step 2: Audio]
                                               ├─ 4 秒
14:31:27                                       [Step 3: Scoring]
                                               ├─ 2 秒
14:31:29                                       [Step 4: OpenPose]
                                               ├─ 20 秒
14:31:49                                       [Step 5: Tracking]
                                               ├─ 15 秒
14:32:04                                       [完成處理]
                               ←──────────────
                               [更新隊列]
                               [複製檔案]
14:32:05  GET /api/.../queue-status
          │────────────────────→
                               [查詢]
          ←────────────────────
          [應答: completed]
14:32:06  GET /api/videos/.../
          │────────────────────→
                               [查詢]
          ←────────────────────
          [返回所有檔案]
14:32:07  [顯示結果]
          ├─ ✅ 穩定化: 8.7/10
          ├─ 🔊 清脆度: 91%
          ├─ 🎯 擊球點: 380 frame
          └─ ⚾ 球速: 45.2 m/s
```

---

## 總結

✅ **完整流程**: clip.mp4 + right_wrist.csv → stablize.mp4
- **上傳**: ~7 秒 (網路限制)
- **隊列等待**: 1-10 秒
- **Python 處理**: ~124 秒 (主要是 MeshFlow)
- **總計**: ~140 秒 (~2 分鐘)

✅ **檔案流向**:
```
clip.mp4 + right_wrist.csv (Flutter)
    ↓ 上傳
/uploads/{userId}/{videoId}/ (C# 磁碟)
    ↓ 排隊
Python 讀取檔案
    ↓ 處理
/outputs/{videoId}/ (Python 磁碟 - 實檔)
    ↓ JSON 描述 + 路徑
C# 回收結果
    ↓ 複製檔案
/uploads/{userId}/{videoId}/ (C# 最終位置)
    ↓ 下載
使用者取得 clip_stabilized.mp4
```

✅ **Python 返回內容**:
- **是什麼**: JSON 響應 (只是描述)
- **不是什麼**: 不在 HTTP 中發送實際檔案
- **實檔位置**: 在磁碟 `/outputs/{videoId}/`
- **C# 處理**: 讀取磁碟上的實檔並複製

✅ **並行度**: 3 個 Worker，可同時處理 3 個切片

✅ **檔案類型**: 支援 16 種 (5 視頻 + 4 音訊 + 5 影像 + 2 資料)

✅ **驗證層**: 3 層 (副檔名 + MIME + 簽名)

✅ **輸出**: 5 個分析檔案 (穩定化、音訊、姿勢、球軌、中繼資料)
