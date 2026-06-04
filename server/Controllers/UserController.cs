using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using System.Security.Claims;
using UploadServer.DTOs;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 使用者方案 + 獎勵球數 API
    /// </summary>
    [ApiController]
    [Route("api/user")]
    [Authorize]
    public class UserController : ControllerBase
    {
        private readonly UserService _userService;
        private readonly B2Service _b2;
        private readonly IConfiguration _config;
        private readonly ILogger<UserController> _logger;

        public UserController(UserService userService, B2Service b2, IConfiguration config, ILogger<UserController> logger)
        {
            _userService = userService;
            _b2          = b2;
            _config      = config;
            _logger      = logger;
        }

        private bool IsAdmin() =>
            Request.Headers.TryGetValue("X-Admin-Key", out var key) &&
            key == _config["Admin:SecretKey"];

        private string? GetUserId() =>
            User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        // ════════════════════════════════════════════════════════════════
        // 方案
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/user/plan — 取得方案狀態與今日用量
        /// </summary>
        [HttpGet("plan")]
        public async Task<IActionResult> GetPlanStatus()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.GetPlanStatusAsync(userId);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// PUT /api/user/plan — 管理員直接更新方案（需 X-Admin-Key 標頭）
        /// Body: { "plan": "free|pro|elite" }
        /// </summary>
        [HttpPut("plan")]
        public async Task<IActionResult> UpdatePlan([FromBody] UpdatePlanRequest req)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var ok = await _userService.UpdatePlanAsync(userId, req.Plan);
            return ok
                ? Ok(new { message = "方案已更新", plan = req.Plan })
                : BadRequest(new { message = "無效的方案名稱" });
        }

        /// <summary>
        /// POST /api/user/plan/purchase — 付款後升級方案
        /// Body: { "plan": "pro|elite", "store": "google_pay|google_play|app_store", "purchaseToken": "...", "productId": "..." }
        /// </summary>
        [HttpPost("plan/purchase")]
        public async Task<IActionResult> PurchasePlan([FromBody] PurchasePlanRequest req)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.PurchasePlanAsync(userId, req);
            return result.Success
                ? Ok(new { data = result })
                : BadRequest(new { message = result.Message });
        }

        /// <summary>
        /// POST /api/user/plan/use — 增加今日用量（Flutter 分析完成後呼叫）
        /// </summary>
        [HttpPost("plan/use")]
        public async Task<IActionResult> IncrementUsage()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.IncrementUsageAsync(userId);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// POST /api/user/balls/purchase — 購買球數包（consumable 內購）
        /// Body: { "productId": "golf_balls_10", "store": "google_play|app_store", "purchaseToken": "..." }
        /// </summary>
        [HttpPost("balls/purchase")]
        public async Task<IActionResult> PurchaseBalls([FromBody] PurchaseBallsRequest req)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.PurchaseBallsAsync(userId, req);
            return result.Success
                ? Ok(new { data = result })
                : BadRequest(new { message = result.Message });
        }

        // ════════════════════════════════════════════════════════════════
        // 獎勵
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/user/rewards — 取得獎勵狀態
        /// </summary>
        [HttpGet("rewards")]
        public async Task<IActionResult> GetRewardStatus()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.GetRewardStatusAsync(userId);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// POST /api/user/rewards/ad — 認領廣告獎勵（每日上限 5 次）
        /// </summary>
        [HttpPost("rewards/ad")]
        public async Task<IActionResult> ClaimAdReward()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.ClaimAdRewardAsync(userId);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            if (result.Balls == 0)
                return Ok(new { data = result, message = "今日廣告獎勵已達上限" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// GET /api/user/invite-code — 取得（或生成）邀請碼
        /// </summary>
        [HttpGet("invite-code")]
        public async Task<IActionResult> GetInviteCode()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var code = await _userService.GetOrCreateInviteCodeAsync(userId);
            if (code == null) return NotFound(new { message = "用戶不存在" });

            var status = await _userService.GetRewardStatusAsync(userId);
            return Ok(new { data = new InviteCodeResponse(code, status?.InviteCount ?? 0) });
        }

        /// <summary>        /// GET /api/user/rewards/feedback/image-upload-url — 取得回饋圖片上傳 URL
        /// 回傳 pre-signed PUT URL（Flutter 直傳 B2 用）及 imageId
        /// </summary>
        [HttpGet("rewards/feedback/image-upload-url")]
        public IActionResult GetFeedbackImageUploadUrl()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var imageId   = Guid.NewGuid().ToString("N");
            var uploadUrl = _b2.GenerateFeedbackImageUploadUrl(imageId);
            return Ok(new { data = new FeedbackImageUploadUrlResponse(uploadUrl, imageId) });
        }

        /// <summary>        /// POST /api/user/rewards/feedback — 提交問題回饋並領取獎勵（每日限 1 次）
        /// Body: { "type": "bug|feature|other", "text": "..." }
        /// </summary>
        [HttpPost("rewards/feedback")]
        public async Task<IActionResult> SubmitFeedback([FromBody] SubmitFeedbackRequest req)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            if (string.IsNullOrWhiteSpace(req.Text))
                return BadRequest(new { message = "回饋內容不得為空" });

            var result = await _userService.SubmitFeedbackAsync(
                userId, req.Type, req.Text, req.VideoId, req.ImageB2Key);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            if (result.Balls == 0)
                return Ok(new { data = result, message = "今日已提交過回饋" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// POST /api/user/rewards/upload — 上傳本地分析資料並領取獎勵
        /// Body: { "sessions": [...] }
        /// </summary>
        [HttpPost("rewards/upload")]
        public async Task<IActionResult> ClaimUploadReward([FromBody] UploadSessionsRequest req)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            if (req.Sessions == null || req.Sessions.Count == 0)
                return BadRequest(new { message = "請提供至少一筆錄影資料" });

            var result = await _userService.ClaimUploadRewardAsync(userId, req.Sessions);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        // ════════════════════════════════════════════════════════════════
        // 使用紀錄
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/user/analysis/history?page=1&amp;pageSize=20 — 分頁查詢 AI 分析紀錄
        /// </summary>
        [HttpGet("analysis/history")]
        public async Task<IActionResult> GetAnalysisHistory(
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 20)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.GetAnalysisHistoryAsync(userId, page, pageSize);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// GET /api/user/balls/history?page=1&amp;pageSize=20 — 分頁查詢球數流水帳
        /// </summary>
        [HttpGet("balls/history")]
        public async Task<IActionResult> GetBallsHistory(
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 20)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.GetBallsHistoryAsync(userId, page, pageSize);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        // ════════════════════════════════════════════════════════════════
        // 邀請好友
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/user/invite/friends — 取得已邀請好友清單
        /// </summary>
        [HttpGet("invite/friends")]
        public async Task<IActionResult> GetInvitedFriends()
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            var result = await _userService.GetInvitedFriendsAsync(userId);
            if (result == null) return NotFound(new { message = "用戶不存在" });

            return Ok(new { data = result });
        }

        /// <summary>
        /// POST /api/user/invite/apply — 好友使用邀請碼（Auth callback 或客戶端呼叫）
        /// Body: { "inviteCode": "ABC12345" }
        /// </summary>
        [HttpPost("invite/apply")]
        public async Task<IActionResult> ApplyInviteCode([FromBody] ApplyInviteRequest req)
        {
            var userId = GetUserId();
            if (userId == null) return Unauthorized();

            if (string.IsNullOrWhiteSpace(req.InviteCode))
                return BadRequest(new { message = "邀請碼不得為空" });

            var result = await _userService.ApplyInviteRewardAsync(
                userId, req.InviteCode.Trim().ToUpperInvariant());

            return result.Success
                ? Ok(new { data = result })
                : BadRequest(new { message = result.Message });
        }
    }

    /// <summary>套用邀請碼請求</summary>
    public record ApplyInviteRequest(string InviteCode);
}
