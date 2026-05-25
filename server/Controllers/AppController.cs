using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// App 公開資訊 API（不需登入）
    /// </summary>
    [ApiController]
    [Route("api/app")]
    [AllowAnonymous]
    public class AppController : ControllerBase
    {
        private readonly AppVersionService _versionService;
        private readonly ILogger<AppController> _logger;

        public AppController(AppVersionService versionService, ILogger<AppController> logger)
        {
            _versionService = versionService;
            _logger         = logger;
        }

        /// <summary>
        /// GET /api/app/version — 查詢最新版本資訊
        ///
        /// Query params:
        ///   platform = android | ios
        ///   version  = 客戶端目前版本號，e.g. 1.0.0
        ///
        /// 回應範例：
        /// {
        ///   "data": {
        ///     "latestVersion": "1.2.0",
        ///     "minRequiredVersion": "1.0.0",
        ///     "forceUpdate": false,
        ///     "updateUrl": "https://play.google.com/...",
        ///     "releaseNotes": ["修正 A", "新增 B"],
        ///     "releaseDate": "2026-05-25"
        ///   }
        /// }
        /// </summary>
        [HttpGet("version")]
        public async Task<IActionResult> GetVersion(
            [FromQuery] string platform = "android",
            [FromQuery] string version  = "1.0.0")
        {
            // 只允許已知平台
            if (platform != "android" && platform != "ios")
                return BadRequest(new { message = "platform 必須為 android 或 ios" });

            try
            {
                var result = await _versionService.GetVersionAsync(platform, version);
                return Ok(new { data = result });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "版本查詢失敗 platform={Platform}", platform);
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }
    }
}
