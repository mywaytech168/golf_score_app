using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Linq;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using UploadServer.Constants;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    public class AuthService
    {
        private readonly VideoDbContext _context;
        private readonly IConfiguration _config;
        private readonly ILogger<AuthService> _logger;

        public AuthService(VideoDbContext context, IConfiguration config, ILogger<AuthService> logger)
        {
            _context = context;
            _config  = config;
            _logger  = logger;
        }

        // ============================================================
        // 本地帳號註冊
        // ============================================================
        public async Task<(bool Success, UserDto User, string Error)> RegisterAsync(
            string username, string email, string password, string displayName)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
                    return (false, null, "用戶名、郵箱和密碼為必需");

                if (await _context.Users.AnyAsync(u => u.Username == username))
                    return (false, null, "用戶名已被使用");

                if (await _context.Users.AnyAsync(u => u.Email == email))
                    return (false, null, "該郵箱已被註冊");

                if (password.Length < 8)
                    return (false, null, "密碼須至少 8 位且包含大寫字母、小寫字母及數字");

                var user = new User
                {
                    Username    = username,
                    Email       = email,
                    DisplayName = displayName ?? username,
                    Status      = UserStatus.Active,
                    CreatedAt   = DateTime.UtcNow,
                    UpdatedAt   = DateTime.UtcNow,
                };

                var auth = new UserAuth
                {
                    UserId         = user.Id,
                    Provider       = AuthProvider.Local,
                    ProviderUserId = email,
                    CredentialHash = BCrypt.Net.BCrypt.HashPassword(password),
                    CreatedAt      = DateTime.UtcNow,
                };

                _context.Users.Add(user);
                _context.UserAuths.Add(auth);
                await _context.SaveChangesAsync();

                _logger.LogInformation("✅ 新用戶已註冊: UserId={UserId}, Username={Username}", user.Id, username);

                return (true, MapUserToDto(user, new List<string> { AuthProvider.Local }), null);
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
            LoginAsync(string usernameOrEmail, string password)
        {
            try
            {
                // 先找 User（by username or email），再找 local UserAuth
                var user = await _context.Users
                    .FirstOrDefaultAsync(u => u.Username == usernameOrEmail || u.Email == usernameOrEmail);

                if (user == null)
                    return (false, null, null, null, "用戶名或密碼錯誤");

                var auth = await _context.UserAuths
                    .FirstOrDefaultAsync(a => a.UserId == user.Id && a.Provider == AuthProvider.Local);

                if (auth == null || !BCrypt.Net.BCrypt.Verify(password, auth.CredentialHash))
                    return (false, null, null, null, "用戶名或密碼錯誤");

                if (user.Status != UserStatus.Active)
                    return (false, null, null, null, $"帳戶已被 {user.Status}");

                user.LastLoginAt   = DateTime.UtcNow;
                auth.LastUsedAt    = DateTime.UtcNow;
                await _context.SaveChangesAsync();

                var providers = await GetProvidersAsync(user.Id);
                var (token, refreshToken) = GenerateTokens(user, providers);

                _logger.LogInformation("✅ 用戶已登入: UserId={UserId}", user.Id);

                return (true, token, refreshToken, MapUserToDto(user, providers), null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 登入失敗");
                return (false, null, null, null, ex.Message);
            }
        }

        // ============================================================
        // Google OAuth 登入 / 註冊 / 帳號合併
        // ============================================================
        public async Task<(bool Success, string Token, string RefreshToken, UserDto User, string Error)>
            GoogleLoginAsync(string googleId, string email, string displayName, string avatarUrl)
        {
            try
            {
                // 1. 找到現有的 Google UserAuth
                var googleAuth = await _context.UserAuths
                    .Include(a => a.User)
                    .FirstOrDefaultAsync(a => a.Provider == AuthProvider.Google && a.ProviderUserId == googleId);

                User user;

                if (googleAuth != null)
                {
                    // 已有 Google 登入記錄 → 直接登入
                    user = googleAuth.User;
                    googleAuth.LastUsedAt = DateTime.UtcNow;
                    if (!string.IsNullOrEmpty(avatarUrl))
                        user.AvatarUrl = avatarUrl;
                    user.LastLoginAt = DateTime.UtcNow;
                    user.UpdatedAt   = DateTime.UtcNow;
                }
                else
                {
                    // 2. 以 email 找到現有 User（帳號合併：同信箱不同 provider）
                    user = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);

                    if (user != null)
                    {
                        // 合併：在既有 User 下新增 Google UserAuth
                        var newGoogleAuth = new UserAuth
                        {
                            UserId         = user.Id,
                            Provider       = AuthProvider.Google,
                            ProviderUserId = googleId,
                            CreatedAt      = DateTime.UtcNow,
                            LastUsedAt     = DateTime.UtcNow,
                        };
                        _context.UserAuths.Add(newGoogleAuth);

                        if (!string.IsNullOrEmpty(avatarUrl) && string.IsNullOrEmpty(user.AvatarUrl))
                            user.AvatarUrl = avatarUrl;
                        user.LastLoginAt = DateTime.UtcNow;
                        user.UpdatedAt   = DateTime.UtcNow;

                        _logger.LogInformation("✅ Google 帳號已合併至現有 User: UserId={UserId}", user.Id);
                    }
                    else
                    {
                        // 3. 全新 Google 用戶
                        user = new User
                        {
                            Email       = email,
                            DisplayName = displayName,
                            AvatarUrl   = avatarUrl,
                            Username    = $"google_{googleId[..Math.Min(8, googleId.Length)]}",
                            Status      = UserStatus.Active,
                            LastLoginAt = DateTime.UtcNow,
                            CreatedAt   = DateTime.UtcNow,
                            UpdatedAt   = DateTime.UtcNow,
                        };

                        var newGoogleAuth = new UserAuth
                        {
                            UserId         = user.Id,
                            Provider       = AuthProvider.Google,
                            ProviderUserId = googleId,
                            CreatedAt      = DateTime.UtcNow,
                            LastUsedAt     = DateTime.UtcNow,
                        };

                        _context.Users.Add(user);
                        _context.UserAuths.Add(newGoogleAuth);

                        _logger.LogInformation("✅ 新 Google 用戶已建立: UserId={UserId}, Email={Email}", user.Id, email);
                    }
                }

                await _context.SaveChangesAsync();

                var providers = await GetProvidersAsync(user.Id);
                var (token, refreshToken) = GenerateTokens(user, providers);

                return (true, token, refreshToken, MapUserToDto(user, providers), null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Google 登入失敗");
                return (false, null, null, null, ex.Message);
            }
        }

        // ============================================================
        // Apple Sign In 登入 / 註冊 / 帳號合併
        // 注意：Apple 僅在首次授權提供 email/displayName，後續登入皆為 null
        // ============================================================
        public async Task<(bool Success, string Token, string RefreshToken, UserDto User, string Error)>
            AppleLoginAsync(string appleId, string? email, string? displayName)
        {
            try
            {
                // 1. 找到現有的 Apple UserAuth
                var appleAuth = await _context.UserAuths
                    .Include(a => a.User)
                    .FirstOrDefaultAsync(a => a.Provider == AuthProvider.Apple && a.ProviderUserId == appleId);

                User user;

                if (appleAuth != null)
                {
                    user = appleAuth.User;
                    appleAuth.LastUsedAt = DateTime.UtcNow;
                    user.LastLoginAt = DateTime.UtcNow;
                    user.UpdatedAt   = DateTime.UtcNow;
                }
                else
                {
                    // 2. 以 email 合併現有 User（首次授權才有 email；private relay 信箱也視為有效）
                    user = !string.IsNullOrEmpty(email)
                        ? await _context.Users.FirstOrDefaultAsync(u => u.Email == email)
                        : null;

                    if (user != null)
                    {
                        _context.UserAuths.Add(new UserAuth
                        {
                            UserId         = user.Id,
                            Provider       = AuthProvider.Apple,
                            ProviderUserId = appleId,
                            CreatedAt      = DateTime.UtcNow,
                            LastUsedAt     = DateTime.UtcNow,
                        });
                        user.LastLoginAt = DateTime.UtcNow;
                        user.UpdatedAt   = DateTime.UtcNow;

                        _logger.LogInformation("✅ Apple 帳號已合併至現有 User: UserId={UserId}", user.Id);
                    }
                    else
                    {
                        // 3. 全新 Apple 用戶。非首次授權且查無記錄時 email 為 null
                        //    （例如用戶移除 App 授權後 DB 又遺失），以佔位信箱建立。
                        var sub8 = appleId[..Math.Min(8, appleId.Length)];
                        user = new User
                        {
                            Email       = email ?? $"apple_{sub8}@apple.local",
                            DisplayName = string.IsNullOrEmpty(displayName) ? "Golfer" : displayName,
                            Username    = $"apple_{sub8}",
                            Status      = UserStatus.Active,
                            LastLoginAt = DateTime.UtcNow,
                            CreatedAt   = DateTime.UtcNow,
                            UpdatedAt   = DateTime.UtcNow,
                        };

                        _context.Users.Add(user);
                        _context.UserAuths.Add(new UserAuth
                        {
                            UserId         = user.Id,
                            Provider       = AuthProvider.Apple,
                            ProviderUserId = appleId,
                            CreatedAt      = DateTime.UtcNow,
                            LastUsedAt     = DateTime.UtcNow,
                        });

                        _logger.LogInformation("✅ 新 Apple 用戶已建立: UserId={UserId}", user.Id);
                    }
                }

                await _context.SaveChangesAsync();

                var providers = await GetProvidersAsync(user.Id);
                var (token, refreshToken) = GenerateTokens(user, providers);

                return (true, token, refreshToken, MapUserToDto(user, providers), null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Apple 登入失敗");
                return (false, null, null, null, ex.Message);
            }
        }

        // ============================================================
        // 刷新 Token
        // ============================================================
        public async Task<(string NewToken, string NewRefreshToken)> RefreshTokenAsync(string refreshToken)
        {
            try
            {
                var principal = GetPrincipalFromExpiredToken(refreshToken);

                var tokenType = principal?.FindFirst("token_type")?.Value;
                if (tokenType != "refresh")
                {
                    _logger.LogWarning("❌ 刷新 Token 失敗：token_type 不符（收到: {Type}）", tokenType);
                    return (null, null);
                }

                var userIdClaim = principal?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userIdClaim))
                    return (null, null);

                var user = await _context.Users.FindAsync(userIdClaim);
                if (user == null || user.Status != UserStatus.Active)
                {
                    _logger.LogWarning("❌ 刷新 Token 失敗：用戶不存在或已停用 (UserId={UserId})", userIdClaim);
                    return (null, null);
                }

                var providers = await GetProvidersAsync(user.Id);
                var (newToken, newRefresh) = GenerateTokens(user, providers);
                return (newToken, newRefresh);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 刷新 Token 失敗");
                return (null, null);
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
                    return (false, "用戶不存在");

                var auth = await _context.UserAuths
                    .FirstOrDefaultAsync(a => a.UserId == userId && a.Provider == AuthProvider.Local);

                if (auth == null)
                    return (false, "此帳號未設定本地密碼");

                if (!BCrypt.Net.BCrypt.Verify(oldPassword, auth.CredentialHash))
                    return (false, "舊密碼錯誤");

                if (newPassword.Length < 8)
                    return (false, "新密碼須至少 8 位且包含大寫字母、小寫字母及數字");

                auth.CredentialHash = BCrypt.Net.BCrypt.HashPassword(newPassword);
                user.UpdatedAt      = DateTime.UtcNow;
                await _context.SaveChangesAsync();

                _logger.LogInformation("✅ 用戶密碼已變更: UserId={UserId}", userId);
                return (true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 密碼變更失敗");
                return (false, ex.Message);
            }
        }

        // ============================================================
        // Google 帳號綁定（設定頁主動綁定，與登入時的 email 自動合併互補）
        // ============================================================
        public async Task<(bool Success, string Error)> LinkGoogleAsync(string userId, string googleId)
        {
            try
            {
                var user = await _context.Users.FindAsync(userId);
                if (user == null)
                    return (false, "用戶不存在");

                var existing = await _context.UserAuths
                    .FirstOrDefaultAsync(a => a.Provider == AuthProvider.Google && a.ProviderUserId == googleId);
                if (existing != null)
                {
                    // 同一用戶重複綁定視為成功（冪等）
                    if (existing.UserId == userId) return (true, null);
                    return (false, "此 Google 帳號已綁定其他帳號");
                }

                var alreadyLinked = await _context.UserAuths
                    .AnyAsync(a => a.UserId == userId && a.Provider == AuthProvider.Google);
                if (alreadyLinked)
                    return (false, "此帳號已綁定其他 Google 帳號");

                _context.UserAuths.Add(new UserAuth
                {
                    UserId         = userId,
                    Provider       = AuthProvider.Google,
                    ProviderUserId = googleId,
                    CreatedAt      = DateTime.UtcNow,
                    LastUsedAt     = DateTime.UtcNow,
                });
                user.UpdatedAt = DateTime.UtcNow;
                await _context.SaveChangesAsync();
                return (true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Google 綁定失敗");
                return (false, ex.Message);
            }
        }

        // ============================================================
        // 設定密碼（純 OAuth 帳號首次建立本地密碼，不需舊密碼）
        // ============================================================
        public async Task<(bool Success, string Error)> SetPasswordAsync(
            string userId, string newPassword)
        {
            try
            {
                var user = await _context.Users.FindAsync(userId);
                if (user == null)
                    return (false, "用戶不存在");

                var existing = await _context.UserAuths
                    .FirstOrDefaultAsync(a => a.UserId == userId && a.Provider == AuthProvider.Local);
                if (existing != null)
                    return (false, "此帳號已設定密碼，請使用修改密碼");

                _context.UserAuths.Add(new UserAuth
                {
                    UserId         = userId,
                    Provider       = AuthProvider.Local,
                    ProviderUserId = user.Email,
                    CredentialHash = BCrypt.Net.BCrypt.HashPassword(newPassword),
                    CreatedAt      = DateTime.UtcNow,
                });
                user.UpdatedAt = DateTime.UtcNow;
                await _context.SaveChangesAsync();

                _logger.LogInformation("✅ 用戶已設定本地密碼: UserId={UserId}", userId);
                return (true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 設定密碼失敗");
                return (false, ex.Message);
            }
        }

        // ============================================================
        // Token 生成
        // ============================================================
        public (string Token, string RefreshToken) GenerateTokens(User user, List<string> providers)
        {
            var jwtSecret        = _config["Jwt:Secret"] ?? "default_secret_key_please_change_in_production_environment";
            var jwtExpiryMinutes = int.Parse(_config["Jwt:ExpiryMinutes"] ?? "60");

            var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));
            var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);
            var handler     = new JwtSecurityTokenHandler();

            var providersValue = string.Join(",", providers);

            // ── Access Token ──────────────────────────────────────
            var accessClaims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim(ClaimTypes.Name,  user.Username    ?? ""),
                new Claim(ClaimTypes.Email, user.Email       ?? ""),
                new Claim("DisplayName",    user.DisplayName ?? ""),
                new Claim("Providers",      providersValue),
                new Claim("token_type",     "access"),
            };

            var accessJwt = new JwtSecurityToken(
                issuer:             "GolfScoreApp",
                audience:           "GolfScoreAppUsers",
                claims:             accessClaims,
                expires:            DateTime.UtcNow.AddMinutes(jwtExpiryMinutes),
                signingCredentials: credentials
            );

            // ── Refresh Token（長效 JWT，30 天，僅含 userId）────────
            var refreshClaims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim("token_type", "refresh"),
            };

            var refreshJwt = new JwtSecurityToken(
                issuer:             "GolfScoreApp",
                audience:           "GolfScoreAppUsers",
                claims:             refreshClaims,
                expires:            DateTime.UtcNow.AddDays(30),
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
                var jwtSecret   = _config["Jwt:Secret"] ?? "default_secret_key_please_change_in_production_environment";
                var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));

                var tokenHandler = new JwtSecurityTokenHandler();
                var principal = tokenHandler.ValidateToken(token, new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey         = securityKey,
                    ValidateIssuer           = true,
                    ValidIssuer              = _config["Jwt:Issuer"],
                    ValidateAudience         = true,
                    ValidAudience            = _config["Jwt:Audience"],
                    ValidateLifetime         = false, // 允許過期 Token（用於刷新）
                }, out _);

                return principal;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Token 驗證失敗");
                return null;
            }
        }

        // ============================================================
        // 輔助方法
        // ============================================================
        private async Task<List<string>> GetProvidersAsync(string userId)
        {
            return await _context.UserAuths
                .Where(a => a.UserId == userId)
                .Select(a => a.Provider)
                .ToListAsync();
        }

        private static UserDto MapUserToDto(User user, List<string> providers)
        {
            return new UserDto
            {
                Id          = user.Id,
                Username    = user.Username,
                Email       = user.Email,
                DisplayName = user.DisplayName,
                AvatarUrl   = user.AvatarUrl,
                Providers   = providers,
                Status      = user.Status,
                CreatedAt   = user.CreatedAt,
                LastLoginAt = user.LastLoginAt,
            };
        }
    }
}
