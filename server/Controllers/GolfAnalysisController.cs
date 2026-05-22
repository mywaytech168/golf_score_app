using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UploadServer.DTOs;
using UploadServer.Services;

namespace UploadServer.Controllers;

[ApiController]
[Route("api/golf")]
[Authorize]
public class GolfAnalysisController : ControllerBase
{
    private readonly GolfSwingAnalyzerService _analyzer;
    private readonly ILogger<GolfAnalysisController> _logger;

    public GolfAnalysisController(
        GolfSwingAnalyzerService analyzer,
        ILogger<GolfAnalysisController> logger)
    {
        _analyzer = analyzer;
        _logger = logger;
    }

    /// <summary>
    /// 分析揮桿骨架序列，回傳錯誤分類結果。
    ///
    /// Flutter 端流程：
    ///   1. 錄影/選片
    ///   2. ML Kit PoseDetector 逐幀萃取 33 個關鍵點
    ///   3. 將正規化座標（x/imageWidth, y/imageHeight）組成此請求
    ///   4. POST 到本端點
    ///
    /// 關鍵點 Id 對應 BlazePose / MediaPipe Pose 定義（0-32）。
    /// </summary>
    [HttpPost("analyze-swing")]
    [ProducesResponseType(typeof(GolfSwingAnalysisResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public ActionResult<GolfSwingAnalysisResponse> AnalyzeSwing(
        [FromBody] GolfSwingAnalysisRequest request)
    {
        if (!_analyzer.IsAvailable)
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = "ONNX 模型尚未部署，揮桿分析暫不可用" });

        if (request.Frames.Count < 2)
            return BadRequest("至少需要 2 幀骨架資料");

        if (request.Frames.Count > 600)
            return BadRequest("幀數過多（上限 600 幀）");

        // 驗證每幀是否含有正規化必需的 4 個關鍵點（具體 ID 而非只檢查數量）
        // NormalizePose 需要: 11=左肩, 12=右肩, 23=左髖, 24=右髖
        int[] requiredIds = [11, 12, 23, 24];
        foreach (var frame in request.Frames)
        {
            var presentIds = frame.Landmarks.Select(l => l.Id).ToHashSet();
            var missing = requiredIds.Where(id => !presentIds.Contains(id)).ToArray();
            if (missing.Length > 0)
                return BadRequest(
                    $"幀 {frame.FrameIndex} 缺少必要關鍵點 ID: [{string.Join(", ", missing)}]" +
                    $"（需要: 11-左肩, 12-右肩, 23-左髖, 24-右髖）");
        }

        try
        {
            var result = _analyzer.Analyze(request);

            _logger.LogInformation(
                "揮桿分析完成 | 幀數={Frames} | 正式錯誤={Official}",
                request.Frames.Count,
                string.Join(",", result.OfficialErrors));

            return Ok(result);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "揮桿分析失敗");
            return StatusCode(StatusCodes.Status500InternalServerError, "分析過程發生錯誤");
        }
    }
}
