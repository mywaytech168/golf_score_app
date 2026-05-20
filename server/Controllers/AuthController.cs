using System.IdentityModel.Tokens.Jwt;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Google.Apis.Auth;
using UploadServer.DTOs;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 身份驗證和授權 API 控制器
    /// 支持本地帳號和 Google OAuth
    /// </summary>
    [ApiController]
    [Route("api/auth")]
    public class AuthController : ControllerBase
    {
        private readonly AuthService _authService;
        private readonly ITokenBlacklistService _blacklist;
        private readonly ILogger<AuthController> _logger;
        private readonly IConfiguration _config;

        public AuthController(AuthService authService, ITokenBlacklistService blacklist, IConfiguration config, ILogger<AuthController> logger)
        {
            _authService = authService;
            _blacklist   = blacklist;
            _config      = config;
            _logger      = logger;
        }

        /// <summary>
        /// 本地帳號註冊
        /// POST: /api/auth/register
        /// </summary>
        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegisterRequest request)
        {
            try
            {
                if (request == null)
                {
                    return BadRequest(new RegisterResponse { Success = false, Message = "請求體為空" });
                }

                // Email 格式驗證
                if (!string.IsNullOrEmpty(request.Email) &&
                    !Regex.IsMatch(request.Email, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
                {
                    return BadRequest(new RegisterResponse { Success = false, Message = "Email 格式不正確" });
                }

                // 密碼強度：至少 8 位，含大寫、小寫、數字
                if (string.IsNullOrEmpty(request.Password) || request.Password.Length < 8 ||
                    !Regex.IsMatch(request.Password, @"[A-Z]") ||
                    !Regex.IsMatch(request.Password, @"[a-z]") ||
                    !Regex.IsMatch(request.Password, @"[0-9]"))
                {
                    return BadRequest(new RegisterResponse
                    {
                        Success = false,
                        Message = "密碼須至少 8 位且包含大寫字母、小寫字母及數字",
                    });
                }

                var (success, user, error) = await _authService.RegisterAsync(
                    request.Username,
                    request.Email,
                    request.Password,
                    request.DisplayName
                );

                if (!success)
                {
                    return BadRequest(new RegisterResponse
                    {
                        Success = false,
                        Message = error,
                    });
                }

                _logger.LogInformation($"✅ 用戶註冊成功: {request.Username}");

                return Ok(new RegisterResponse
                {
                    Success = true,
                    Message = "註冊成功，請登入",
                    User = user,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 註冊失敗");
                return StatusCode(500, new RegisterResponse
                {
                    Success = false,
                    Message = ex.Message,
                });
            }
        }

        /// <summary>
        /// 本地帳號登入
        /// POST: /api/auth/login
        /// </summary>
        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginRequest request)
        {
            try
            {
                if (request == null || string.IsNullOrEmpty(request.Username))
                {
                    return BadRequest(new LoginResponse
                    {
                        Success = false,
                        Message = "用戶名和密碼為必需",
                    });
                }

                var (success, token, refreshToken, user, error) = await _authService.LoginAsync(
                    request.Username,
                    request.Password
                );

                if (!success)
                {
                    return Unauthorized(new LoginResponse
                    {
                        Success = false,
                        Message = error,
                    });
                }

                _logger.LogInformation($"✅ 用戶登入成功: {request.Username}");

                return Ok(new LoginResponse
                {
                    Success = true,
                    Message = "登入成功",
                    Token = token,
                    RefreshToken = refreshToken,
                    User = user,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 登入失敗");
                return StatusCode(500, new LoginResponse
                {
                    Success = false,
                    Message = ex.Message,
                });
            }
        }

        /// <summary>
        /// Google OAuth 登入
        /// POST: /api/auth/google-login
        /// </summary>
        [HttpPost("google-login")]
        public async Task<IActionResult> GoogleLogin([FromBody] GoogleLoginRequest request)
        {
            try
            {
                if (request == null || string.IsNullOrEmpty(request.IdToken))
                {
                    return BadRequest(new GoogleLoginResponse
                    {
                        Success = false,
                        Message = "Google ID Token 為必需",
                    });
                }

                // 驗證 Google ID Token
                GoogleJsonWebSignature.Payload payload;
                try
                {
                    var clientId = _config["Google:AndroidClientId"]
                        ?? throw new InvalidOperationException("Google:AndroidClientId 未設定");

                    var validationSettings = new GoogleJsonWebSignature.ValidationSettings()
                    {
                        Audience = new List<string> { clientId }
                    };
                    
                    payload = await GoogleJsonWebSignature.ValidateAsync(request.IdToken, validationSettings);
                }
                catch (InvalidOperationException ex)
                {
                    _logger.LogError(ex, $"❌ Google Token 驗證失敗: {ex.Message}");
                    return Unauthorized(new GoogleLoginResponse
                    {
                        Success = false,
                        Message = "無效的 Google ID Token",
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, $"❌ Google Token 驗證異常: {ex.Message}");
                    return BadRequest(new GoogleLoginResponse
                    {
                        Success = false,
                        Message = $"Google Token 驗證異常: {ex.Message}",
                    });
                }

                // 驗證郵箱是否匹配（不匹配視為偽造請求，硬性拒絕）
                if (!string.IsNullOrEmpty(request.Email) && payload.Email != request.Email)
                {
                    _logger.LogWarning("⚠️ Google token 郵箱不匹配: Token={TokenEmail}, Request={RequestEmail}",
                        payload.Email, request.Email);
                    return BadRequest(new GoogleLoginResponse { Success = false, Message = "郵箱與 Google 帳號不符" });
                }

                // 使用 Google 返回的信息（Email 來自已驗證的 token）
                var googleUserId = payload.Subject; // Google 用戶 ID
                var verifiedEmail = payload.Email;  // 已驗證的郵箱

                var (success, token, refreshToken, user, error) = await _authService.GoogleLoginAsync(
                    googleUserId,
                    verifiedEmail,
                    request.DisplayName,
                    request.AvatarUrl
                );

                if (!success)
                {
                    return BadRequest(new GoogleLoginResponse
                    {
                        Success = false,
                        Message = error,
                    });
                }

                _logger.LogInformation($"✅ Google 登入成功: Email={verifiedEmail}, GoogleId={googleUserId}");

                return Ok(new GoogleLoginResponse
                {
                    Success = true,
                    Message = "Google 登入成功",
                    Token = token,
                    RefreshToken = refreshToken,
                    User = user,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Google 登入失敗");
                return StatusCode(500, new GoogleLoginResponse
                {
                    Success = false,
                    Message = ex.Message,
                });
            }
        }

        /// <summary>
        /// 刷新 Token
        /// POST: /api/auth/refresh-token
        /// </summary>
        [HttpPost("refresh-token")]
        public async Task<IActionResult> RefreshToken([FromBody] RefreshTokenRequest request)
        {
            try
            {
                if (request == null || string.IsNullOrEmpty(request.RefreshToken))
                    return BadRequest(new RefreshTokenResponse { Success = false });

                var (newToken, newRefreshToken) = await _authService.RefreshTokenAsync(request.RefreshToken);

                if (string.IsNullOrEmpty(newToken))
                    return Unauthorized(new RefreshTokenResponse { Success = false });

                _logger.LogInformation("✅ Token 已刷新");

                return Ok(new RefreshTokenResponse
                {
                    Success      = true,
                    Token        = newToken,
                    RefreshToken = newRefreshToken,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 刷新 Token 失敗");
                return StatusCode(500, new RefreshTokenResponse { Success = false });
            }
        }

        /// <summary>
        /// 密碼變更
        /// POST: /api/auth/change-password
        /// </summary>
        [HttpPost("change-password")]
        [Authorize]
        public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request)
        {
            try
            {
                if (request == null)
                {
                    return BadRequest(new ChangePasswordResponse
                    {
                        Success = false,
                        Message = "請求體為空",
                    });
                }

                // 從 JWT 取出已驗證的 userId，忽略 body 中的 UserId 防止越權
                var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                    return Unauthorized(new ChangePasswordResponse { Success = false, Message = "無效的身份驗證" });

                // 新密碼強度驗證
                if (string.IsNullOrEmpty(request.NewPassword) || request.NewPassword.Length < 8 ||
                    !Regex.IsMatch(request.NewPassword, @"[A-Z]") ||
                    !Regex.IsMatch(request.NewPassword, @"[a-z]") ||
                    !Regex.IsMatch(request.NewPassword, @"[0-9]"))
                {
                    return BadRequest(new ChangePasswordResponse
                    {
                        Success = false,
                        Message = "新密碼須至少 8 位且包含大寫字母、小寫字母及數字",
                    });
                }

                var (success, error) = await _authService.ChangePasswordAsync(
                    userId,
                    request.OldPassword,
                    request.NewPassword
                );

                if (!success)
                {
                    return BadRequest(new ChangePasswordResponse
                    {
                        Success = false,
                        Message = error,
                    });
                }

                _logger.LogInformation($"✅ 密碼已變更: UserId={userId}");

                return Ok(new ChangePasswordResponse
                {
                    Success = true,
                    Message = "密碼已成功變更",
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 密碼變更失敗");
                return StatusCode(500, new ChangePasswordResponse
                {
                    Success = false,
                    Message = ex.Message,
                });
            }
        }

        /// <summary>
        /// 登出（將當前 token 加入黑名單，立即失效）
        /// POST: /api/auth/logout
        /// </summary>
        [HttpPost("logout")]
        [Authorize]
        public IActionResult Logout()
        {
            try
            {
                var jti    = User.FindFirst(JwtRegisteredClaimNames.Jti)?.Value;
                var expStr = User.FindFirst(JwtRegisteredClaimNames.Exp)?.Value;
                var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

                if (!string.IsNullOrEmpty(jti))
                {
                    var exp = expStr is not null
                        ? DateTimeOffset.FromUnixTimeSeconds(long.Parse(expStr)).UtcDateTime
                        : DateTime.UtcNow.AddHours(1);
                    _blacklist.Revoke(jti, exp);
                }

                _logger.LogInformation("✅ 用戶已登出: UserId={UserId}", userId);
                return Ok(new LogoutResponse { Success = true, Message = "已成功登出" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 登出失敗");
                return StatusCode(500, new LogoutResponse { Success = false, Message = ex.Message });
            }
        }
    }
}
