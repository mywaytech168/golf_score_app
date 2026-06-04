namespace UploadServer.DTOs;

// ── Request ──────────────────────────────────────────────────

public class BallTrajectoryRequestDto
{
    /// <summary>Flutter 本地 session ID（純參考）</summary>
    public string? VideoId { get; set; }

    /// <summary>擊球秒數（null = 全影片搜尋）</summary>
    public double? HitSec { get; set; }

    /// <summary>翻轉模式（0 = Android coded-space 影片）</summary>
    public int FlipMode { get; set; } = 0;

    public double RoiCxRatio { get; set; } = 1149.0 / 1920;
    public double RoiCyRatio { get; set; } = 406.0  / 1080;
    public int    RoiRadius  { get; set; } = 200;
}

// ── Response: 建立請求後回傳 ──────────────────────────────────

public class BallTrajectoryRequestResponse
{
    public string AnalysisId    { get; set; } = "";
    public string ClipUploadUrl { get; set; } = "";
}

// ── Response: 輪詢狀態 ────────────────────────────────────────

public class BallTrajectoryStatusResponse
{
    public string  AnalysisId    { get; set; } = "";
    public string? VideoId       { get; set; }
    public string  Status        { get; set; } = "";

    /// <summary>completed 時包含軌跡資料</summary>
    public BallTrajectoryResult? Result { get; set; }

    public string? ErrorMessage  { get; set; }
    public DateTime CreatedAt    { get; set; }
    public DateTime? CompletedAt { get; set; }
}

/// <summary>軌跡結果（Status = completed 時填入）</summary>
public class BallTrajectoryResult
{
    /// <summary>軌跡點，每點 {x, y, frame_idx, pts_us}</summary>
    public List<BallTrajectoryPoint> TrackPts { get; set; } = [];

    public double Fps      { get; set; }
    public int    Width    { get; set; }
    public int    Height   { get; set; }
    public int    Rotation { get; set; }
}

public class BallTrajectoryPoint
{
    public int X        { get; set; }
    public int Y        { get; set; }
    /// <summary>影片全局 0-based 幀號</summary>
    public int FrameIdx { get; set; }
    /// <summary>呈現時間戳（微秒），= frame_idx * (1_000_000 / fps)</summary>
    public long PtsUs   { get; set; }
}
