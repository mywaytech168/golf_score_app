using Microsoft.AspNetCore.Mvc;
using UploadServer.DTOs;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    [ApiController]
    [Route("api/share")]
    public class ShareController : ControllerBase
    {
        private readonly ShareService _shareService;
        private readonly ILogger<ShareController> _logger;

        public ShareController(ShareService shareService, ILogger<ShareController> logger)
        {
            _shareService = shareService;
            _logger       = logger;
        }

        /// <summary>
        /// 步驟 1：產生 B2 pre-signed PUT URL 與分享碼
        /// POST /api/share/prepare
        /// </summary>
        [HttpPost("prepare")]
        public async Task<IActionResult> Prepare([FromBody] SharePrepareRequest req)
        {
            if (req.SizeBytes <= 0)
                return BadRequest(new { message = "size_bytes 無效" });

            try
            {
                var result = await _shareService.PrepareAsync(req);
                return Ok(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Share prepare 失敗");
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }

        /// <summary>
        /// 步驟 2：Flutter 直傳 B2 完成後通知伺服器確認
        /// POST /api/share/confirm
        /// </summary>
        [HttpPost("confirm")]
        public async Task<IActionResult> Confirm([FromBody] ShareConfirmRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.ShareCode))
                return BadRequest(new { message = "share_code 不可空白" });

            var result = await _shareService.ConfirmAsync(req.ShareCode);
            if (result == null)
                return NotFound(new { message = "分享碼不存在" });

            return Ok(result);
        }

        /// <summary>
        /// 取得分享資訊與下載 URL
        /// GET /api/share/{code}
        /// </summary>
        [HttpGet("{code}")]
        public async Task<IActionResult> Get(string code)
        {
            if (code.Length != 16)
                return BadRequest(new { message = "分享碼格式錯誤" });

            var result = await _shareService.GetAsync(code);
            if (result == null)
                return NotFound(new { message = "分享碼不存在或已過期" });

            return Ok(result);
        }
    }
}
