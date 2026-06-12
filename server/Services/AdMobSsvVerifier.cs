using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace UploadServer.Services
{
    /// <summary>
    /// AdMob 獎勵廣告 SSV（Server-Side Verification）回呼驗簽。
    /// 簽名內容 = query string 中 signature 參數之前的全部內容（保持原始順序與編碼），
    /// 演算法 = ECDSA P-256 + SHA-256（DER 簽名、base64url 編碼），
    /// 公鑰來自 Google 金鑰伺服器（依 key_id 選取），快取 24 小時、遇未知 key_id 強制刷新。
    /// </summary>
    public class AdMobSsvVerifier
    {
        private const string KeyServerUrl = "https://www.gstatic.com/admob/reward/verifier-keys.json";
        private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);

        private readonly IHttpClientFactory _httpFactory;
        private readonly ILogger<AdMobSsvVerifier> _logger;
        private readonly SemaphoreSlim _refreshLock = new(1, 1);

        private Dictionary<string, byte[]> _keys = new(); // keyId → SubjectPublicKeyInfo DER
        private DateTime _fetchedAt = DateTime.MinValue;

        public AdMobSsvVerifier(IHttpClientFactory httpFactory, ILogger<AdMobSsvVerifier> logger)
        {
            _httpFactory = httpFactory;
            _logger      = logger;
        }

        /// <summary>
        /// 驗證 SSV 回呼。rawQuery 為原始 query string（含開頭 '?' 可有可無）。
        /// </summary>
        public async Task<bool> VerifyAsync(string rawQuery)
        {
            if (string.IsNullOrEmpty(rawQuery)) return false;
            var query = rawQuery.StartsWith('?') ? rawQuery[1..] : rawQuery;

            // 簽名內容是 &signature= 之前的原始字串（不可重排或重編碼）
            var sigIdx = query.IndexOf("&signature=", StringComparison.Ordinal);
            if (sigIdx < 0) return false;
            var message = Encoding.UTF8.GetBytes(query[..sigIdx]);

            string? signatureB64 = null, keyId = null;
            foreach (var pair in query[(sigIdx + 1)..].Split('&'))
            {
                var eq = pair.IndexOf('=');
                if (eq < 0) continue;
                var name = pair[..eq];
                var value = pair[(eq + 1)..];
                if (name == "signature") signatureB64 = value;
                else if (name == "key_id") keyId = value;
            }
            if (signatureB64 == null || keyId == null) return false;

            byte[] signature;
            try { signature = Base64UrlDecode(signatureB64); }
            catch { return false; }

            var keyDer = await GetKeyAsync(keyId);
            if (keyDer == null)
            {
                _logger.LogWarning("AdMob SSV 未知 key_id={KeyId}", keyId);
                return false;
            }

            try
            {
                using var ecdsa = ECDsa.Create();
                ecdsa.ImportSubjectPublicKeyInfo(keyDer, out _);
                return ecdsa.VerifyData(message, signature, HashAlgorithmName.SHA256,
                    DSASignatureFormat.Rfc3279DerSequence);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "AdMob SSV 驗簽異常 key_id={KeyId}", keyId);
                return false;
            }
        }

        private async Task<byte[]?> GetKeyAsync(string keyId)
        {
            if (DateTime.UtcNow - _fetchedAt < CacheTtl && _keys.TryGetValue(keyId, out var cached))
                return cached;

            await _refreshLock.WaitAsync();
            try
            {
                // double-check：可能等鎖期間已被其他請求刷新
                if (DateTime.UtcNow - _fetchedAt >= CacheTtl || !_keys.ContainsKey(keyId))
                {
                    var client = _httpFactory.CreateClient();
                    var json = await client.GetStringAsync(KeyServerUrl);
                    using var doc = JsonDocument.Parse(json);

                    var keys = new Dictionary<string, byte[]>();
                    foreach (var k in doc.RootElement.GetProperty("keys").EnumerateArray())
                    {
                        var id  = k.GetProperty("keyId").GetInt64().ToString();
                        var b64 = k.GetProperty("base64").GetString();
                        if (b64 != null) keys[id] = Convert.FromBase64String(b64);
                    }
                    _keys      = keys;
                    _fetchedAt = DateTime.UtcNow;
                    _logger.LogInformation("AdMob SSV 公鑰已更新，共 {Count} 把", keys.Count);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "AdMob SSV 公鑰下載失敗");
            }
            finally
            {
                _refreshLock.Release();
            }

            return _keys.TryGetValue(keyId, out var key) ? key : null;
        }

        private static byte[] Base64UrlDecode(string input)
        {
            var s = input.Replace('-', '+').Replace('_', '/');
            switch (s.Length % 4)
            {
                case 2: s += "=="; break;
                case 3: s += "=";  break;
            }
            return Convert.FromBase64String(s);
        }
    }
}
