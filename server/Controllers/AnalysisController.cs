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
                UserId               = UserId,
                VideoId              = req.VideoId,
                ErrorTypeHint        = req.ErrorTypeHint,
                Mode                 = req.Mode,
                PromptVersion        = req.PromptVersion,
                Status               = "pending",
                PhaseTimestampsJson  = req.PhaseTimestamps != null
                    ? System.Text.Json.JsonSerializer.Serialize(req.PhaseTimestamps)
                    : null,
                AudioAnalysisJson    = req.AudioAnalysisJson,
                SwingMetricsJson     = req.SwingMetricsJson,
                Lang                 = req.Lang,
                V2Fps                = req.V2Fps,
                V2Resolution         = req.V2Resolution,
            };
            analysis.ClipB2Path = B2Service.AiCoachClipKey(analysis.Id);
            if (req.HasCsv)
                analysis.CsvB2Path   = B2Service.AiCoachCsvKey(analysis.Id);
            if (req.HasAudio)
                analysis.AudioB2Path = B2Service.AiCoachAudioKey(analysis.Id);
            if (req.KeyframeCount > 0)
                analysis.KeyframeCount = req.KeyframeCount;

            _db.AiCoachAnalyses.Add(analysis);
            await _db.SaveChangesAsync();

            var clipUploadUrl  = _b2.GenerateClipUploadUrl(analysis.Id);
            var csvUploadUrl   = req.HasCsv   ? _b2.GenerateCsvUploadUrl(analysis.Id)   : null;
            var audioUploadUrl = req.HasAudio ? _b2.GenerateAudioUploadUrl(analysis.Id) : null;
            var metaUploadUrl  = _b2.GenerateMetaUploadUrl(analysis.Id);

            List<string>? keyframeUploadUrls = null;
            if (req.KeyframeCount > 0)
                keyframeUploadUrls = Enumerable.Range(0, req.KeyframeCount)
                    .Select(i => _b2.GenerateKeyframeUploadUrl(analysis.Id, i))
                    .ToList();

            _logger.LogInformation(
                "建立 AI Coach 分析請求: {Id} Mode={Mode} HasCsv={HasCsv} HasAudio={HasAudio} KeyframeCount={KF}",
                analysis.Id, analysis.Mode, req.HasCsv, req.HasAudio, req.KeyframeCount);

            return Ok(new AnalysisRequestResponse
            {
                AnalysisId        = analysis.Id,
                ClipUploadUrl     = clipUploadUrl,
                CsvUploadUrl      = csvUploadUrl,
                AudioUploadUrl    = audioUploadUrl,
                KeyframeUploadUrls = keyframeUploadUrls,
                MetaUploadUrl     = metaUploadUrl,
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
        /// 升級 idle 記錄為完整 Gemini 分析
        /// POST /api/analysis/{id}/upgrade
        /// </summary>
        [HttpPost("{id}/upgrade")]
        public async Task<IActionResult> Upgrade(string id, [FromBody] AnalysisUpgradeDto? dto)
        {
            var analysis = await _db.AiCoachAnalyses
                .FirstOrDefaultAsync(a => a.Id == id && a.UserId == UserId);

            if (analysis == null)
                return NotFound(new { message = "分析記錄不存在" });

            if (analysis.Status != "idle")
                return BadRequest(new { message = $"只有 idle 狀態可升級，目前: {analysis.Status}" });

            analysis.Mode   = "full";
            analysis.Status = "queued";
            if (dto?.PromptVersion != null)
                analysis.PromptVersion = dto.PromptVersion;
            if (dto?.Lang != null)
                analysis.Lang = dto.Lang;

            // 重置重試計數，讓 Worker 可以重新處理
            analysis.RetryCount = 0;

            await _db.SaveChangesAsync();

            _logger.LogInformation(
                "升級分析: {Id} → Mode=full PromptVersion={Ver}",
                id, analysis.PromptVersion);

            return Ok(new { message = "升級請求已提交", promptVersion = analysis.PromptVersion });
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

            return Ok(BuildStatusResponse(analysis));
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
                    AnalysisId    = a.Id,
                    VideoId       = a.VideoId,
                    Status        = a.Status,
                    Mode          = a.Mode,
                    PromptVersion = a.PromptVersion,
                    Summary       = a.Summary,
                    Severity      = a.Severity,
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
            var rows = await _db.AiCoachAnalyses
                .Where(a => a.UserId == UserId && a.VideoId == videoId)
                .OrderByDescending(a => a.CreatedAt)
                .Take(10)
                .ToListAsync();

            return Ok(rows.Select(BuildStatusResponse).ToList());
        }

        // ── helpers ────────────────────────────────────────────────────────────

        private static AnalysisStatusResponse BuildStatusResponse(AiCoachAnalysis a)
        {
            object? result = null;
            if (a.Status == "completed" && !string.IsNullOrEmpty(a.ResultJson))
            {
                try { result = JsonSerializer.Deserialize<JsonElement>(a.ResultJson); }
                catch { result = a.ResultJson; }
            }

            object? onnxResult = null;
            if (!string.IsNullOrEmpty(a.OnnxResultJson))
            {
                try { onnxResult = JsonSerializer.Deserialize<JsonElement>(a.OnnxResultJson); }
                catch { /* ONNX JSON 損毀時忽略 */ }
            }

            return new AnalysisStatusResponse
            {
                AnalysisId    = a.Id,
                VideoId       = a.VideoId,
                Status        = a.Status,
                Mode          = a.Mode,
                PromptVersion = a.PromptVersion,
                Summary       = a.Summary,
                Severity      = a.Severity,
                Result        = result,
                OnnxResult    = onnxResult,
                InputTokens   = a.InputTokens,
                OutputTokens  = a.OutputTokens,
            };
        }
    }
}
