using System.ComponentModel.DataAnnotations;

namespace UploadServer.Models;

public class BallTrajectoryAnalysis
{
    public string Id { get; set; } = Guid.NewGuid().ToString();

    public string UserId { get; set; } = "";

    /// <summary>Flutter 本地 session ID，純參考，無 FK</summary>
    [MaxLength(255)]
    public string? VideoId { get; set; }

    /// <summary>pending → queued → processing → completed | failed</summary>
    [MaxLength(50)]
    public string Status { get; set; } = "pending";

    /// <summary>clip 在 B2 的路徑（Flutter 直傳）</summary>
    [MaxLength(512)]
    public string? ClipB2Path { get; set; }

    /// <summary>擊球秒數（null = 不限定視窗，全影片搜尋）</summary>
    public double? HitSec { get; set; }

    /// <summary>翻轉模式：0 = coded-space（Android 影片預設）</summary>
    public int FlipMode { get; set; } = 0;

    /// <summary>ROI 中心 X 比例（相對於 coded width，預設 ≈ 0.5984）</summary>
    public double RoiCxRatio { get; set; } = 1149.0 / 1920;

    /// <summary>ROI 中心 Y 比例（相對於 coded height，預設 ≈ 0.3759）</summary>
    public double RoiCyRatio { get; set; } = 406.0 / 1080;

    /// <summary>ROI 搜尋半徑（px，預設 200）</summary>
    public int RoiRadius { get; set; } = 200;

    /// <summary>Python 輸出的 track_pts JSON：[[x,y],...]</summary>
    public string? TrackPtsJson { get; set; }

    /// <summary>fps, width, height, rotation（來自影片 metadata）</summary>
    public double? VideoFps      { get; set; }
    public int?    VideoWidth    { get; set; }
    public int?    VideoHeight   { get; set; }
    public int?    VideoRotation { get; set; }

    public string? ErrorMessage { get; set; }

    public int RetryCount { get; set; } = 0;

    /// <summary>指數退避：失敗後下次允許重試的時間（null = 立即可重試）</summary>
    public DateTime? NextRetryAt { get; set; }

    public DateTime CreatedAt  { get; set; } = DateTime.UtcNow;
    public DateTime? CompletedAt { get; set; }

    // Navigation
    public User? User { get; set; }
}
