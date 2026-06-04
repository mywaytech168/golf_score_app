using System.Text;
using System.Text.Json;
using UploadServer.DTOs;

namespace UploadServer.Services;

/// <summary>
/// 呼叫 Python Flask server 的 /api/ball-trajectory 取得球軌跡。
///
/// 設定（appsettings.json "BallTrajectory" 節）：
///   FlaskUrl   : Python Flask server 根 URL（預設 "http://localhost:6000"）
///   TimeoutSec : 單次追蹤最長秒數（預設 120）
/// </summary>
public class BallTrajectoryPythonService
{
    private readonly string _flaskUrl;
    private readonly int    _timeoutSec;
    private readonly IHttpClientFactory _httpFactory;
    private readonly ILogger<BallTrajectoryPythonService> _logger;

    public BallTrajectoryPythonService(
        IConfiguration config,
        IHttpClientFactory httpFactory,
        ILogger<BallTrajectoryPythonService> logger)
    {
        _logger     = logger;
        _httpFactory = httpFactory;
        _flaskUrl   = (config["BallTrajectory:FlaskUrl"] ?? "http://localhost:6000").TrimEnd('/');
        _timeoutSec = int.TryParse(config["BallTrajectory:TimeoutSec"], out var t) ? t : 120;

        _logger.LogInformation("BallTrajectoryPythonService → {Url}", _flaskUrl);
    }

    public bool IsAvailable => !string.IsNullOrEmpty(_flaskUrl);

    /// <summary>
    /// 對 <paramref name="videoUrl"/>（B2 presigned URL）執行球軌跡追蹤。
    /// Flask server 負責從 URL 下載影片到自己的本地暫存後處理。
    /// 成功回傳 <see cref="BallTrajectoryResult"/>；失敗拋出例外。
    /// </summary>
    public async Task<BallTrajectoryResult> RunAsync(
        string  videoUrl,
        double? hitSec,
        int     flipMode,
        double  roiCxRatio,
        double  roiCyRatio,
        int     roiRadius,
        CancellationToken ct = default)
    {
        if (!IsAvailable)
            throw new InvalidOperationException("BallTrajectory Flask URL 未設定");

        var payload = new
        {
            video_url    = videoUrl,   // Flask 自行下載
            hit_sec      = hitSec,
            flip_mode    = flipMode,
            roi_cx_ratio = roiCxRatio,
            roi_cy_ratio = roiCyRatio,
            roi_radius   = roiRadius,
        };

        var json    = JsonSerializer.Serialize(payload);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(_timeoutSec));

        var client = _httpFactory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(_timeoutSec + 5);

        _logger.LogInformation("POST {Url}/api/ball-trajectory hitSec={Hit}", _flaskUrl, hitSec);

        var resp = await client.PostAsync($"{_flaskUrl}/api/ball-trajectory", content, cts.Token);

        var body = await resp.Content.ReadAsStringAsync(cts.Token);

        if (!resp.IsSuccessStatusCode)
            throw new Exception($"Flask server 回應 {(int)resp.StatusCode}: {body.TrimEnd()}");

        return ParseResult(body);
    }

    // ── helpers ──────────────────────────────────────────────

    private static BallTrajectoryResult ParseResult(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root      = doc.RootElement;

        var pts = new List<BallTrajectoryPoint>();
        if (root.TryGetProperty("track_pts", out var ptsEl))
        {
            foreach (var pt in ptsEl.EnumerateArray())
            {
                pts.Add(new BallTrajectoryPoint
                {
                    X        = pt.TryGetProperty("x",         out var x)  ? x.GetInt32()  : 0,
                    Y        = pt.TryGetProperty("y",         out var y)  ? y.GetInt32()  : 0,
                    FrameIdx = pt.TryGetProperty("frame_idx", out var fi) ? fi.GetInt32() : 0,
                    PtsUs    = pt.TryGetProperty("pts_us",    out var pu) ? pu.GetInt64() : 0,
                });
            }
        }

        return new BallTrajectoryResult
        {
            TrackPts = pts,
            Fps      = root.TryGetProperty("fps",      out var fps) ? fps.GetDouble() : 30.0,
            Width    = root.TryGetProperty("width",    out var w)   ? w.GetInt32()   : 0,
            Height   = root.TryGetProperty("height",   out var h)   ? h.GetInt32()   : 0,
            Rotation = root.TryGetProperty("rotation", out var rot) ? rot.GetInt32() : 0,
        };
    }
}
