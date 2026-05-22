using System.IdentityModel.Tokens.Jwt;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Google.Apis.Auth;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
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
        private readonly IEmailService _email;
        private readonly VideoDbContext _db;
        private readonly ILogger<AuthController> _logger;
        private readonly IConfiguration _config;

        public AuthController(
            AuthService authService,
            ITokenBlacklistService blacklist,
            IEmailService email,
            VideoDbContext db,
            IConfiguration config,
            ILogger<AuthController> logger)
        {
            _authService = authService;
            _blacklist   = blacklist;
            _email       = email;
            _db          = db;
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
        /// 忘記密碼：寄送 6 位驗證碼至信箱
        /// POST: /api/auth/forgot-password
        /// </summary>
        [HttpPost("forgot-password")]
        [AllowAnonymous]
        public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest req)
        {
            // 固定回傳成功（防 email 枚舉攻擊）
            const string okMsg = "如果此 Email 已在系統中，驗證碼將在數分鐘內送達";
            try
            {
                if (string.IsNullOrWhiteSpace(req?.Email))
                    return Ok(new ForgotPasswordResponse { Success = true, Message = okMsg });

                var email = req.Email.Trim().ToLowerInvariant();
                var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
                if (user == null)
                {
                    _logger.LogInformation("ForgotPassword: 查無此 Email={Email}（已靜默回傳）", email);
                    return Ok(new ForgotPasswordResponse { Success = true, Message = okMsg });
                }

                // 生成 6 位數驗證碼
                var code = new Random().Next(100000, 999999).ToString();
                var codeHash = BCrypt.Net.BCrypt.HashPassword(code);

                // 將舊有未使用的 token 標記已使用
                var oldTokens = await _db.PasswordResetTokens
                    .Where(t => t.UserId == user.Id && !t.IsUsed && t.ExpiresAt > DateTime.UtcNow)
                    .ToListAsync();
                foreach (var t in oldTokens) t.IsUsed = true;

                // 建立新 token 記錄
                var resetToken = new PasswordResetToken
                {
                    UserId    = user.Id,
                    CodeHash  = codeHash,
                    ExpiresAt = DateTime.UtcNow.AddMinutes(15),
                };
                _db.PasswordResetTokens.Add(resetToken);
                await _db.SaveChangesAsync();

                // 寄信
                await _email.SendPasswordResetCodeAsync(
                    user.Email,
                    user.DisplayName ?? user.Username,
                    code);

                _logger.LogInformation("ForgotPassword: 驗證碼已寄至 UserId={UserId}", user.Id);
                return Ok(new ForgotPasswordResponse { Success = true, Message = okMsg });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ForgotPassword 失敗");
                return StatusCode(500, new ForgotPasswordResponse
                {
                    Success = false,
                    Message = "寄送失敗，請稍後再試",
                });
            }
        }

        /// <summary>
        /// 重設密碼：驗證碼 + 新密碼
        /// POST: /api/auth/reset-password
        /// </summary>
        [HttpPost("reset-password")]
        [AllowAnonymous]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest req)
        {
            try
            {
                if (req == null ||
                    string.IsNullOrWhiteSpace(req.Email) ||
                    string.IsNullOrWhiteSpace(req.Code) ||
                    string.IsNullOrWhiteSpace(req.NewPassword))
                {
                    return BadRequest(new ResetPasswordResponse
                    {
                        Success = false, Message = "請填寫 Email、驗證碼與新密碼",
                    });
                }

                // 新密碼強度
                if (req.NewPassword.Length < 8 ||
                    !Regex.IsMatch(req.NewPassword, @"[A-Z]") ||
                    !Regex.IsMatch(req.NewPassword, @"[a-z]") ||
                    !Regex.IsMatch(req.NewPassword, @"[0-9]"))
                {
                    return BadRequest(new ResetPasswordResponse
                    {
                        Success = false,
                        Message = "新密碼須至少 8 位且包含大寫、小寫及數字",
                    });
                }

                var email = req.Email.Trim().ToLowerInvariant();
                var user  = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
                if (user == null)
                    return BadRequest(new ResetPasswordResponse
                        { Success = false, Message = "驗證碼無效或已過期" });

                // 找最新一筆有效 token
                var token = await _db.PasswordResetTokens
                    .Where(t => t.UserId == user.Id && !t.IsUsed && t.ExpiresAt > DateTime.UtcNow)
                    .OrderByDescending(t => t.CreatedAt)
                    .FirstOrDefaultAsync();

                if (token == null || !BCrypt.Net.BCrypt.Verify(req.Code.Trim(), token.CodeHash))
                    return BadRequest(new ResetPasswordResponse
                        { Success = false, Message = "驗證碼無效或已過期" });

                // 標記已使用
                token.IsUsed = true;

                // 更新密碼雜湊（local auth）
                var auth = await _db.UserAuths
                    .FirstOrDefaultAsync(a => a.UserId == user.Id && a.Provider == "local");

                if (auth == null)
                    return BadRequest(new ResetPasswordResponse
                        { Success = false, Message = "此帳號非本地帳號，無法重設密碼" });

                auth.CredentialHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
                await _db.SaveChangesAsync();

                _logger.LogInformation("ResetPassword: 密碼已重設 UserId={UserId}", user.Id);
                return Ok(new ResetPasswordResponse
                {
                    Success = true,
                    Message = "密碼已重設，請使用新密碼登入",
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ResetPassword 失敗");
                return StatusCode(500, new ResetPasswordResponse
                {
                    Success = false, Message = "重設失敗，請稍後再試",
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
