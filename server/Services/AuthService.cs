using System;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    /// <summary>
    /// 身份驗證和授權服務
    /// </summary>
    public class AuthService
    {
        private readonly VideoDbContext _context;
        private readonly IConfiguration _config;
        private readonly ILogger<AuthService> _logger;

        public AuthService(VideoDbContext context, IConfiguration config, ILogger<AuthService> logger)
        {
            _context = context;
            _config = config;
            _logger = logger;
        }

        // ============================================================
        // 本地帳號註冊
        // ============================================================
        public async Task<(bool Success, UserDto User, string Error)> RegisterAsync(
            string username, string email, string password, string displayName)
        {
            try
            {
                // 驗證輸入
                if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
                {
                    return (false, null, "用戶名、郵箱和密碼為必需");
                }

                // 檢查用戶名是否已存在
                if (await _context.Users.AnyAsync(u => u.Username == username))
                {
                    return (false, null, "用戶名已被使用");
                }

                // 檢查郵箱是否已存在
                if (await _context.Users.AnyAsync(u => u.Email == email))
                {
                    return (false, null, "該郵箱已被註冊");
                }

                // 密碼驗證（至少 6 個字符）
                if (password.Length < 6)
                {
                    return (false, null, "密碼至少需要 6 個字符");
                }

                // 創建新用戶
                var user = new User
                {
                    Username = username,
                    Email = email,
                    DisplayName = displayName ?? username,
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
                    Provider = AuthProvider.Local,
                    Status = UserStatus.Active,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                };

                _context.Users.Add(user);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 新用戶已註冊: UserId={user.Id}, Username={username}");

                var userDto = MapUserToDto(user);
                return (true, userDto, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 註冊失敗");
                return (false, null, ex.Message);
            }
        }

        // ============================================================
        // 本地帳號登入
        // ============================================================
        public async Task<(bool Success, string Token, string RefreshToken, UserDto User, string Error)> 
            LoginAsync(string username, string password)
        {
            try
            {
                var user = await _context.Users.FirstOrDefaultAsync(
                    u => u.Username == username || u.Email == username);
                if (user == null)
                {
                    return (false, null, null, null, "用戶名或密碼錯誤");
                }

                // 驗證密碼
                if (!BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
                {
                    return (false, null, null, null, "用戶名或密碼錯誤");
                }

                // 檢查帳戶狀態
                if (user.Status != UserStatus.Active)
                {
                    return (false, null, null, null, $"帳戶已被 {user.Status}");
                }

                // 更新最後登入時間
                user.LastLoginAt = DateTime.UtcNow;
                _context.Users.Update(user);
                await _context.SaveChangesAsync();

                // 生成 Token
                var (token, refreshToken) = GenerateTokens(user);
                var userDto = MapUserToDto(user);

                _logger.LogInformation($"✅ 用戶已登入: UserId={user.Id}, Username={username}");

                return (true, token, refreshToken, userDto, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 登入失敗");
                return (false, null, null, null, ex.Message);
            }
        }

        // ============================================================
        // Google OAuth 登入/註冊
        // ============================================================
        public async Task<(bool Success, string Token, string RefreshToken, UserDto User, string Error)>
            GoogleLoginAsync(string googleId, string email, string displayName, string avatarUrl)
        {
            try
            {
                // 尋找現有的 Google 帳戶
                var user = await _context.Users.FirstOrDefaultAsync(u => u.GoogleId == googleId);

                if (user != null)
                {
                    // 已存在，更新登入信息
                    user.LastLoginAt = DateTime.UtcNow;
                    user.UpdatedAt = DateTime.UtcNow;
                    // 可選：更新頭像 URL
                    if (!string.IsNullOrEmpty(avatarUrl))
                    {
                        user.AvatarUrl = avatarUrl;
                    }

                    _context.Users.Update(user);
                    await _context.SaveChangesAsync();

                    _logger.LogInformation($"✅ Google 用戶已登入: UserId={user.Id}, Email={email}");
                }
                else
                {
                    // 新用戶，建立帳戶
                    // 檢查郵箱是否已被本地帳戶使用
                    var existingEmail = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);
                    if (existingEmail != null)
                    {
                        return (false, null, null, null, "該郵箱已與本地帳戶關聯");
                    }

                    user = new User
                    {
                        GoogleId = googleId,
                        Email = email,
                        DisplayName = displayName,
                        AvatarUrl = avatarUrl,
                        Username = $"google_{googleId}",
                        PasswordHash = "[GOOGLE_AUTH]", // Google 用户不需要密码
                        Provider = AuthProvider.Google,
                        Status = UserStatus.Active,
                        LastLoginAt = DateTime.UtcNow,
                        CreatedAt = DateTime.UtcNow,
                        UpdatedAt = DateTime.UtcNow,
                    };

                    _context.Users.Add(user);
                    await _context.SaveChangesAsync();

                    _logger.LogInformation($"✅ 新 Google 用戶已建立: UserId={user.Id}, Email={email}");
                }

                // 生成 Token
                var (token, refreshToken) = GenerateTokens(user);
                var userDto = MapUserToDto(user);

                return (true, token, refreshToken, userDto, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Google 登入失敗");
                return (false, null, null, null, ex.Message);
            }
        }

        // ============================================================
        // 刷新 Token
        // ============================================================

        /// <summary>
        /// 以 Refresh Token（JWT）換取新的 Access + Refresh Token 組合。
        /// Refresh Token 本身是一個長效 JWT（30 天），帶有 token_type=refresh claim，
        /// 用以區別一般 Access Token，防止以 Access Token 冒充刷新。
        /// </summary>
        public async Task<(string NewToken, string NewRefreshToken)> RefreshTokenAsync(string refreshToken)
        {
            try
            {
                var principal = GetPrincipalFromExpiredToken(refreshToken);

                // 確認 token_type 為 refresh，防止用 Access Token 來刷新
                var tokenType = principal?.FindFirst("token_type")?.Value;
                if (tokenType != "refresh")
                {
                    _logger.LogWarning("❌ 刷新 Token 失敗：token_type 不符（收到: {Type}）", tokenType);
                    return (null, null);
                }

                var userIdClaim = principal?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userIdClaim))
                    return (null, null);

                // 從 DB 取完整 User，確保新 JWT 帶有正確的 Username / Email claims
                var user = await _context.Users.FindAsync(userIdClaim);
                if (user == null || user.Status != UserStatus.Active)
                {
                    _logger.LogWarning("❌ 刷新 Token 失敗：用戶不存在或已停用 (UserId={UserId})", userIdClaim);
                    return (null, null);
                }

                var (newToken, newRefresh) = GenerateTokens(user);
                return (newToken, newRefresh);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 刷新 Token 失敗");
                return (null, null);
            }
        }

        // ============================================================
        // Token 生成
        // ============================================================
        public (string Token, string RefreshToken) GenerateTokens(User user)
        {
            var jwtSecret        = _config["Jwt:Secret"] ?? "default_secret_key_please_change_in_production_environment";
            var jwtExpiryMinutes = int.Parse(_config["Jwt:ExpiryMinutes"] ?? "60");

            var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));
            var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);
            var handler     = new JwtSecurityTokenHandler();

            // ── Access Token ──────────────────────────────────────
            var accessClaims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim(ClaimTypes.Name,  user.Username    ?? ""),
                new Claim(ClaimTypes.Email, user.Email       ?? ""),
                new Claim("DisplayName",    user.DisplayName ?? ""),
                new Claim("Provider",       user.Provider    ?? AuthProvider.Local),
                new Claim("token_type",     "access"),
            };

            var accessJwt = new JwtSecurityToken(
                issuer:            "GolfScoreApp",
                audience:          "GolfScoreAppUsers",
                claims:            accessClaims,
                expires:           DateTime.UtcNow.AddMinutes(jwtExpiryMinutes),
                signingCredentials: credentials
            );

            // ── Refresh Token（長效 JWT，30 天，僅含 userId）────────
            // 帶 token_type=refresh，防止與 Access Token 互換使用。
            var refreshClaims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim("token_type", "refresh"),
            };

            var refreshJwt = new JwtSecurityToken(
                issuer:            "GolfScoreApp",
                audience:          "GolfScoreAppUsers",
                claims:            refreshClaims,
                expires:           DateTime.UtcNow.AddDays(30),
                signingCredentials: credentials
            );

            return (handler.WriteToken(accessJwt), handler.WriteToken(refreshJwt));
        }

        // ============================================================
        // 驗證 Token
        // ============================================================
        public ClaimsPrincipal GetPrincipalFromExpiredToken(string token)
        {
            try
            {
                var jwtSecret = _config["Jwt:Secret"] ?? "default_secret_key_please_change_in_production_environment";
                var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));

                var tokenHandler = new JwtSecurityTokenHandler();
                var principal = tokenHandler.ValidateToken(token, new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = securityKey,
                    ValidateIssuer = false,
                    ValidateAudience = false,
                    ValidateLifetime = false, // 允許過期 Token（用於刷新）
                }, out SecurityToken securityToken);

                return principal;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Token 驗證失敗");
                return null;
            }
        }

        // ============================================================
        // 密碼變更
        // ============================================================
        public async Task<(bool Success, string Error)> ChangePasswordAsync(
            string userId, string oldPassword, string newPassword)
        {
            try
            {
                var user = await _context.Users.FindAsync(userId);
                if (user == null)
                {
                    return (false, "用戶不存在");
                }

                // 驗證舊密碼
                if (!BCrypt.Net.BCrypt.Verify(oldPassword, user.PasswordHash))
                {
                    return (false, "舊密碼錯誤");
                }

                // 驗證新密碼
                if (newPassword.Length < 6)
                {
                    return (false, "新密碼至少需要 6 個字符");
                }

                // 更新密碼
                user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(newPassword);
                user.UpdatedAt = DateTime.UtcNow;

                _context.Users.Update(user);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 用戶密碼已變更: UserId={userId}");

                return (true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 密碼變更失敗");
                return (false, ex.Message);
            }
        }

        // ============================================================
        // 輔助方法
        // ============================================================
        private UserDto MapUserToDto(User user)
        {
            return new UserDto
            {
                Id = user.Id,
                Username = user.Username,
                Email = user.Email,
                DisplayName = user.DisplayName,
                AvatarUrl = user.AvatarUrl,
                Provider = user.Provider,
                Status = user.Status,
                CreatedAt = user.CreatedAt,
                LastLoginAt = user.LastLoginAt,
            };
        }
    }
}
