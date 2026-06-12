using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;

namespace UploadServer.Services
{
    /// <summary>
    /// 驗證 Sign in with Apple 的 identity token（JWT）。
    /// 公鑰來自 Apple JWKS（https://appleid.apple.com/auth/keys），快取 1 小時。
    /// </summary>
    public class AppleTokenValidator
    {
        private const string JwksUrl = "https://appleid.apple.com/auth/keys";
        private const string Issuer  = "https://appleid.apple.com";

        private readonly IHttpClientFactory _httpFactory;
        private readonly IConfiguration _config;
        private readonly ILogger<AppleTokenValidator> _logger;

        private JsonWebKeySet? _cachedKeys;
        private DateTime _keysCachedAt = DateTime.MinValue;
        private static readonly TimeSpan _keysCacheTtl = TimeSpan.FromHours(1);
        private readonly SemaphoreSlim _keysLock = new(1, 1);

        public AppleTokenValidator(
            IHttpClientFactory httpFactory,
            IConfiguration config,
            ILogger<AppleTokenValidator> logger)
        {
            _httpFactory = httpFactory;
            _config      = config;
            _logger      = logger;
        }

        /// <summary>
        /// 驗證 identity token，成功回傳 (sub, email)。email 可能為 null
        /// （Apple 僅在用戶首次授權時提供，且可能是 private relay 信箱）。
        /// </summary>
        public async Task<(bool Valid, string? Sub, string? Email, string? Error)>
            ValidateAsync(string identityToken)
        {
            try
            {
                var bundleId = _config["Apple:BundleId"] ?? "com.aethertek.orvia";
                var keys = await GetKeysAsync();

                var parameters = new TokenValidationParameters
                {
                    ValidIssuer      = Issuer,
                    ValidAudience    = bundleId,
                    IssuerSigningKeys = keys.Keys,
                    ValidateIssuer   = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                };

                var handler = new JwtSecurityTokenHandler();
                // 預設 JwtSecurityTokenHandler 會把 "sub" 映射成 ClaimTypes.NameIdentifier、
                // "email" 等也會被改名，導致 FindFirst("sub") 取不到值。關閉 inbound 映射，
                // 保留 Apple token 原始 claim 名稱。
                handler.MapInboundClaims = false;
                handler.InboundClaimTypeMap.Clear();
                var principal = handler.ValidateToken(identityToken, parameters, out _);

                var sub   = principal.FindFirst("sub")?.Value;
                var email = principal.FindFirst("email")?.Value;
                if (string.IsNullOrEmpty(sub))
                    return (false, null, null, "token 缺少 sub claim");

                return (true, sub, email, null);
            }
            catch (SecurityTokenException ex)
            {
                _logger.LogWarning(ex, "Apple identity token 驗證失敗");
                return (false, null, null, "無效的 Apple identity token");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Apple token 驗證異常");
                return (false, null, null, ex.Message);
            }
        }

        private async Task<JsonWebKeySet> GetKeysAsync()
        {
            if (_cachedKeys != null && DateTime.UtcNow - _keysCachedAt < _keysCacheTtl)
                return _cachedKeys;

            await _keysLock.WaitAsync();
            try
            {
                if (_cachedKeys != null && DateTime.UtcNow - _keysCachedAt < _keysCacheTtl)
                    return _cachedKeys;

                var http = _httpFactory.CreateClient();
                http.Timeout = TimeSpan.FromSeconds(10);
                var json = await http.GetStringAsync(JwksUrl);
                _cachedKeys   = new JsonWebKeySet(json);
                _keysCachedAt = DateTime.UtcNow;
                return _cachedKeys;
            }
            finally
            {
                _keysLock.Release();
            }
        }
    }
}
