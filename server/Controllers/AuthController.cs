using System.IdentityModel.Tokens.Jwt;
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

        public AuthController(AuthService authService, ITokenBlacklistService blacklist, ILogger<AuthController> logger)
        {
            _authService = authService;
            _blacklist   = blacklist;
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
                    return BadRequest(new RegisterResponse
                    {
                        Success = false,
                        Message = "請求體為空",
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
                    var validationSettings = new GoogleJsonWebSignature.ValidationSettings()
                    {
                        Audience = new List<string>
                        {
                            "446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com", // Android/Web client
                            // 添加其他有效的 Google Client IDs（如 iOS、Web 等）
                        }
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

                // 驗證郵箱是否匹配
                if (!string.IsNullOrEmpty(request.Email) && payload.Email != request.Email)
                {
                    _logger.LogWarning($"⚠️ Google token 郵箱不匹配: Token={payload.Email}, Request={request.Email}");
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
        public IActionResult RefreshToken([FromBody] RefreshTokenRequest request)
        {
            try
            {
                if (request == null || string.IsNullOrEmpty(request.RefreshToken))
                {
                    return BadRequest(new RefreshTokenResponse
                    {
                        Success = false,
                    });
                }

                var (newToken, newRefreshToken) = _authService.RefreshToken(request.RefreshToken);

                if (string.IsNullOrEmpty(newToken))
                {
                    return Unauthorized(new RefreshTokenResponse
                    {
                        Success = false,
                    });
                }

                _logger.LogInformation($"✅ Token 已刷新");

                return Ok(new RefreshTokenResponse
                {
                    Success = true,
                    Token = newToken,
                    RefreshToken = newRefreshToken,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 刷新 Token 失敗");
                return StatusCode(500, new RefreshTokenResponse
                {
                    Success = false,
                });
            }
        }

        /// <summary>
        /// 密碼變更
        /// POST: /api/auth/change-password
        /// </summary>
        [HttpPost("change-password")]
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

                var (success, error) = await _authService.ChangePasswordAsync(
                    request.UserId,
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

                _logger.LogInformation($"✅ 密碼已變更: UserId={request.UserId}");

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
