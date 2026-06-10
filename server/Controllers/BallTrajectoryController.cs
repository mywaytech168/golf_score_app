using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Controllers;

[ApiController]
[Route("api/ball-trajectory")]
[Authorize]
public class BallTrajectoryController : ControllerBase
{
    private readonly VideoDbContext _db;
    private readonly B2Service      _b2;
    private readonly ILogger<BallTrajectoryController> _logger;

    public BallTrajectoryController(
        VideoDbContext db, B2Service b2,
        ILogger<BallTrajectoryController> logger)
    {
        _db     = db;
        _b2     = b2;
        _logger = logger;
    }

    private string UserId =>
        User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub") ?? "";

    /// <summary>
    /// 建立球軌跡分析請求，回傳 clip 上傳 URL。
    /// POST /api/ball-trajectory/request
    /// </summary>
    [HttpPost("request")]
    public async Task<IActionResult> Request([FromBody] BallTrajectoryRequestDto req)
    {
        var analysis = new BallTrajectoryAnalysis
        {
            UserId     = UserId,
            VideoId    = req.VideoId,
            HitSec     = req.HitSec,
            FlipMode   = req.FlipMode,
            RoiCxRatio = req.RoiCxRatio,
            RoiCyRatio = req.RoiCyRatio,
            RoiRadius  = req.RoiRadius,
            Status     = "pending",
        };
        analysis.ClipB2Path = B2Service.BallTrajectoryClipKey(analysis.Id);

        _db.BallTrajectoryAnalyses.Add(analysis);
        await _db.SaveChangesAsync();

        var uploadUrl = _b2.GenerateBallTrajectoryClipUploadUrl(analysis.Id);

        _logger.LogInformation(
            "建立球軌跡請求: {Id} VideoId={Vid} HitSec={Hit}",
            analysis.Id, analysis.VideoId, analysis.HitSec);

        return Ok(new BallTrajectoryRequestResponse
        {
            AnalysisId    = analysis.Id,
            ClipUploadUrl = uploadUrl,
        });
    }

    /// <summary>
    /// Flutter 上傳 B2 完成後通知，觸發 Worker。
    /// POST /api/ball-trajectory/{id}/ready
    /// </summary>
    [HttpPost("{id}/ready")]
    public async Task<IActionResult> Ready(string id)
    {
        var analysis = await _db.BallTrajectoryAnalyses
            .FirstOrDefaultAsync(a => a.Id == id && a.UserId == UserId);

        if (analysis == null)
            return NotFound(new { message = "記錄不存在" });
        if (analysis.Status != "pending")
            return BadRequest(new { message = $"狀態不正確: {analysis.Status}" });

        analysis.Status = "queued";
        await _db.SaveChangesAsync();

        return Ok(new { message = "已加入球軌跡分析佇列" });
    }

    /// <summary>
    /// 輪詢分析狀態與結果。
    /// GET /api/ball-trajectory/{id}
    /// </summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetStatus(string id)
    {
        var analysis = await _db.BallTrajectoryAnalyses
            .FirstOrDefaultAsync(a => a.Id == id && a.UserId == UserId);

        if (analysis == null)
            return NotFound(new { message = "記錄不存在" });

        return Ok(BuildResponse(analysis));
    }

    /// <summary>
    /// 查詢特定 videoId 的最新球軌跡記錄（最多 5 筆）。
    /// GET /api/ball-trajectory/by-video/{videoId}
    /// </summary>
    [HttpGet("by-video/{videoId}")]
    public async Task<IActionResult> GetByVideo(string videoId)
    {
        var rows = await _db.BallTrajectoryAnalyses
            .Where(a => a.UserId == UserId && a.VideoId == videoId)
            .OrderByDescending(a => a.CreatedAt)
            .Take(5)
            .ToListAsync();

        return Ok(rows.Select(BuildResponse).ToList());
    }

    // ── helpers ──────────────────────────────────────────────

    private static BallTrajectoryStatusResponse BuildResponse(BallTrajectoryAnalysis a)
    {
        BallTrajectoryResult? result = null;
        if (a.Status == "completed" && !string.IsNullOrEmpty(a.TrackPtsJson))
        {
            try
            {
                var opts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var pts  = JsonSerializer.Deserialize<List<BallTrajectoryPoint>>(a.TrackPtsJson, opts) ?? [];
                result = new BallTrajectoryResult
                {
                    TrackPts = pts,
                    Fps      = a.VideoFps      ?? 30.0,
                    Width    = a.VideoWidth    ?? 0,
                    Height   = a.VideoHeight   ?? 0,
                    Rotation = a.VideoRotation ?? 0,
                };
            }
            catch (JsonException ex)
            {
                // 資料損毀要讓前端看得到，不可與「完成但無軌跡」混淆
                return new BallTrajectoryStatusResponse
                {
                    AnalysisId   = a.Id,
                    VideoId      = a.VideoId,
                    Status       = a.Status,
                    Result       = null,
                    ErrorMessage = $"軌跡資料損毀：{ex.Message}",
                    CreatedAt    = a.CreatedAt,
                    CompletedAt  = a.CompletedAt,
                };
            }
        }

        return new BallTrajectoryStatusResponse
        {
            AnalysisId   = a.Id,
            VideoId      = a.VideoId,
            Status       = a.Status,
            Result       = result,
            ErrorMessage = a.ErrorMessage,
            CreatedAt    = a.CreatedAt,
            CompletedAt  = a.CompletedAt,
        };
    }
}
