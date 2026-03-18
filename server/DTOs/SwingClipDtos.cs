namespace UploadServer.DTOs;

/// 切片元數據請求
public class SwingClipMetadataRequest
{
    /// 原始錄影 ID
    public string RecordingId { get; set; } = "";

    /// 切片標籤（例如："swing_1", "swing_2"）
    public string Tag { get; set; } = "";

    /// 擊棒時刻（秒）
    public double HitSecond { get; set; }

    /// 切片開始時刻（秒）
    public double StartSecond { get; set; }

    /// 切片結束時刻（秒）
    public double EndSecond { get; set; }

    /// 峰值加速度（G）
    public double PeakValue { get; set; }

    /// 是否好球
    public bool GoodShot { get; set; }

    /// 聲音清脆度 (0-100)
    public double AudioCrispness { get; set; }
}

/// 切片元數據回應 - 返回上傳 URL 和 clipId
public class SwingClipMetadataResponse
{
    /// 切片 ID（伺服器生成）
    public int ClipId { get; set; }

    /// 切片標籤
    public string Tag { get; set; } = "";

    /// 擊棒時刻
    public double HitSecond { get; set; }

    /// 視頻上傳的 URL
    public string UploadUrl { get; set; } = "";

    /// CSV 上傳的 URL
    public string CsvUploadUrl { get; set; } = "";

    /// 上傳 URL 的過期時間（秒）
    public int ExpiresIn { get; set; }
}

/// 切片視頻上傳回應 - 分塊上傳進度
public class SwingClipUploadResponse
{
    /// 切片 ID
    public int ClipId { get; set; }

    /// 當前分塊索引
    public int ChunkIndex { get; set; }

    /// 是否所有分塊都已上傳完成
    public bool IsComplete { get; set; }

    /// 上傳進度（0.0-1.0）
    public double UploadProgress { get; set; }

    /// 完整視頻 URL（IsComplete=true 時有值）
    public string? VideoUrl { get; set; }

    /// 縮圖 URL（IsComplete=true 時有值）
    public string? ThumbnailUrl { get; set; }
}

/// 切片 CSV 上傳回應
public class SwingClipCsvResponse
{
    /// 切片 ID
    public int ClipId { get; set; }

    /// CSV 文件名
    public string CsvFileName { get; set; } = "";

    /// 文件大小（位元組）
    public long FileSize { get; set; }

    /// 保存路徑
    public string SavedPath { get; set; } = "";

    /// 上傳時間
    public DateTime UploadedAt { get; set; }
}

/// 切片上傳完成回應
public class SwingClipCompleteResponse
{
    /// 切片 ID
    public int ClipId { get; set; }

    /// 狀態（completed, processing 等）
    public string Status { get; set; } = "completed";

    /// 完成時間
    public DateTime CompletedAt { get; set; }

    /// 視頻播放 URL
    public string ViewUrl { get; set; } = "";

    /// 分享 URL
    public string ShareUrl { get; set; } = "";
}

/// 切片詳細信息回應
public class SwingClipDetailResponse
{
    /// 切片 ID
    public int ClipId { get; set; }

    /// 切片標籤
    public string Tag { get; set; } = "";

    /// 擊棒時刻（秒）
    public double HitSecond { get; set; }

    /// 切片開始時刻（秒）
    public double StartSecond { get; set; }

    /// 切片結束時刻（秒）
    public double EndSecond { get; set; }

    /// 是否好球
    public bool GoodShot { get; set; }

    /// 是否壞球
    public bool BadShot { get; set; }

    /// 視頻 URL
    public string VideoUrl { get; set; } = "";

    /// 縮圖 URL
    public string ThumbnailUrl { get; set; } = "";

    /// CSV 數據 URL
    public string? CsvUrl { get; set; }

    /// 建立時間
    public DateTime CreatedAt { get; set; }

    /// 完成時間
    public DateTime? CompletedAt { get; set; }
}

/// 切片清單項目
public class SwingClipListItem
{
    /// 切片 ID
    public int ClipId { get; set; }

    /// 切片標籤
    public string Tag { get; set; } = "";

    /// 擊棒時刻（秒）
    public double HitSecond { get; set; }

    /// 是否好球
    public bool GoodShot { get; set; }

    /// 是否壞球
    public bool BadShot { get; set; }

    /// 縮圖 URL
    public string ThumbnailUrl { get; set; } = "";

    /// 視頻時長（秒）
    public double Duration { get; set; }

    /// 建立時間
    public DateTime CreatedAt { get; set; }
}

/// 刪除切片請求
public class DeleteClipsRequest
{
    /// 要刪除的切片 ID 清單
    public List<int> ClipIds { get; set; } = new();

    /// 是否同時刪除相關的 CSV 數據
    public bool AlsoDeleteCsv { get; set; } = true;
}

/// 刪除切片回應
public class DeleteClipsResponse
{
    /// 成功刪除的切片數
    public int SuccessCount { get; set; }

    /// 失敗刪除的切片 ID
    public List<int> FailedClipIds { get; set; } = new();

    /// 錯誤消息
    public string? ErrorMessage { get; set; }
}

/// 切片統計信息回應
public class SwingClipStatsResponse
{
    /// 總切片數
    public int TotalClips { get; set; }

    /// 好球數量
    public int GoodShots { get; set; }

    /// 壞球數量
    public int BadShots { get; set; }

    /// 平均擊棒時刻（秒）
    public double AverageHitSecond { get; set; }

    /// 最後上傳時間
    public DateTime LastUploadedAt { get; set; }

    /// 本月上傳切片數
    public int MonthlyClips { get; set; }

    /// 本週上傳切片數
    public int WeeklyClips { get; set; }
}
