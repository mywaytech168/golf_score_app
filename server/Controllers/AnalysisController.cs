using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    [ApiController]
    [Route("api/analysis")]
    [Authorize]
    public class AnalysisController : ControllerBase
    {
        private readonly VideoDbContext _db;
        private readonly B2Service _b2;
        private readonly ILogger<AnalysisController> _logger;

        public AnalysisController(VideoDbContext db, B2Service b2, ILogger<AnalysisController> logger)
        {
            _db     = db;
            _b2     = b2;
            _logger = logger;
        }

        private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("sub")
            ?? "";

        /// <summary>
        /// 步驟 1：建立分析請求，回傳 clip 上傳 URL
        /// POST /api/analysis/request
        /// </summary>
        [HttpPost("request")]
        public async Task<IActionResult> Request([FromBody] AnalysisRequestDto req)
        {
            if (string.IsNullOrWhiteSpace(req.VideoId))
                return BadRequest(new { message = "video_id 不可空白" });

            // 確認 video 屬於此用戶
            var video = await _db.Videos.FirstOrDefaultAsync(v => v.Id == req.VideoId && v.UserId == UserId);
            if (video == null)
                return NotFound(new { message = "影片不存在" });

            var analysis = new AiCoachAnalysis
            {
                VideoId       = req.VideoId,
                ErrorTypeHint = req.ErrorTypeHint,
                Status        = "pending",
            };
            analysis.ClipB2Path = B2Service.AiCoachClipKey(analysis.Id);

            _db.AiCoachAnalyses.Add(analysis);
            await _db.SaveChangesAsync();

            var uploadUrl = _b2.GenerateClipUploadUrl(analysis.Id);

            _logger.LogInformation("建立 AI Coach 分析請求: {Id}", analysis.Id);
            return Ok(new AnalysisRequestResponse
            {
                AnalysisId    = analysis.Id,
                ClipUploadUrl = uploadUrl,
            });
        }

        /// <summary>
        /// 步驟 2：Flutter 上傳 B2 完成後通知，觸發 Worker
        /// POST /api/analysis/{id}/ready
        /// </summary>
        [HttpPost("{id}/ready")]
        public async Task<IActionResult> Ready(string id)
        {
            var analysis = await _db.AiCoachAnalyses
                .Include(a => a.Video)
                .FirstOrDefaultAsync(a => a.Id == id && a.Video.UserId == UserId);

            if (analysis == null)
                return NotFound(new { message = "分析記錄不存在" });

            if (analysis.Status != "pending")
                return BadRequest(new { message = $"狀態不正確: {analysis.Status}" });

            analysis.Status = "queued";
            await _db.SaveChangesAsync();

            _logger.LogInformation("AI Coach 分析已加入佇列: {Id}", id);
            return Ok(new { message = "已加入分析佇列" });
        }

        /// <summary>
        /// 輪詢分析狀態與結果
        /// GET /api/analysis/{id}
        /// </summary>
        [HttpGet("{id}")]
        public async Task<IActionResult> GetStatus(string id)
        {
            var analysis = await _db.AiCoachAnalyses
                .Include(a => a.Video)
                .FirstOrDefaultAsync(a => a.Id == id && a.Video.UserId == UserId);

            if (analysis == null)
                return NotFound(new { message = "分析記錄不存在" });

            object? result = null;
            if (analysis.Status == "completed" && !string.IsNullOrEmpty(analysis.ResultJson))
            {
                try { result = JsonSerializer.Deserialize<JsonElement>(analysis.ResultJson); }
                catch { result = analysis.ResultJson; }
            }

            return Ok(new AnalysisStatusResponse
            {
                AnalysisId = analysis.Id,
                Status     = analysis.Status,
                Summary    = analysis.Summary,
                Severity   = analysis.Severity,
                Result     = result,
            });
        }

        /// <summary>
        /// 查詢某影片的所有分析記錄
        /// GET /api/analysis/video/{videoId}
        /// </summary>
        [HttpGet("video/{videoId}")]
        public async Task<IActionResult> GetByVideo(string videoId)
        {
            var video = await _db.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == UserId);
            if (video == null)
                return NotFound(new { message = "影片不存在" });

            var analyses = await _db.AiCoachAnalyses
                .Where(a => a.VideoId == videoId)
                .OrderByDescending(a => a.CreatedAt)
                .Select(a => new AnalysisStatusResponse
                {
                    AnalysisId = a.Id,
                    Status     = a.Status,
                    Summary    = a.Summary,
                    Severity   = a.Severity,
                })
                .ToListAsync();

            return Ok(analyses);
        }
    }
}
