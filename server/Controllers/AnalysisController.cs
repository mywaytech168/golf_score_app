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
            var analysis = new AiCoachAnalysis
            {
                UserId        = UserId,
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
                .FirstOrDefaultAsync(a => a.Id == id && a.UserId == UserId);

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
                .FirstOrDefaultAsync(a => a.Id == id && a.UserId == UserId);

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
        /// 查詢當前用戶的所有分析記錄
        /// GET /api/analysis
        /// </summary>
        [HttpGet]
        public async Task<IActionResult> GetMyAnalyses()
        {
            var analyses = await _db.AiCoachAnalyses
                .Where(a => a.UserId == UserId)
                .OrderByDescending(a => a.CreatedAt)
                .Select(a => new AnalysisStatusResponse
                {
                    AnalysisId = a.Id,
                    VideoId    = a.VideoId,
                    Status     = a.Status,
                    Summary    = a.Summary,
                    Severity   = a.Severity,
                })
                .ToListAsync();

            return Ok(analyses);
        }

        /// <summary>
        /// 查詢特定 videoId 的分析記錄（最多回傳 10 筆，最新在前）
        /// GET /api/analysis/by-video/{videoId}
        /// </summary>
        [HttpGet("by-video/{videoId}")]
        public async Task<IActionResult> GetByVideo(string videoId)
        {
            var analyses = await _db.AiCoachAnalyses
                .Where(a => a.UserId == UserId && a.VideoId == videoId)
                .OrderByDescending(a => a.CreatedAt)
                .Take(10)
                .Select(a => new AnalysisStatusResponse
                {
                    AnalysisId = a.Id,
                    VideoId    = a.VideoId,
                    Status     = a.Status,
                    Summary    = a.Summary,
                    Severity   = a.Severity,
                })
                .ToListAsync();

            return Ok(analyses);
        }
    }
}
