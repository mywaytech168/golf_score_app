using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace UploadServer.Services
{
    /// <summary>
    /// 驗證 Apple App Store Server Notifications V2 的 JWS 簽名。
    /// JWS header 帶 x5c 憑證鏈（葉→中繼→根），流程：
    ///   1. 取 x5c，葉憑證鏈須驗證到 Apple Root CA - G3（OS 信任存放區）
    ///   2. 用葉憑證公鑰驗證 header.payload 的 ES256 簽名（JOSE R||S 格式）
    /// 驗證通過才回傳 payload JSON；任何一步失敗回 null。
    /// </summary>
    public class AppleJwsVerifier
    {
        private const string AppleRootCaG3Subject = "Apple Root CA - G3";

        private readonly ILogger<AppleJwsVerifier> _logger;

        public AppleJwsVerifier(ILogger<AppleJwsVerifier> logger)
        {
            _logger = logger;
        }

        /// <summary>驗簽通過回傳 payload JSON 字串，否則 null。</summary>
        public string? VerifyAndGetPayload(string signedPayload)
        {
            if (string.IsNullOrEmpty(signedPayload)) return null;

            var parts = signedPayload.Split('.');
            if (parts.Length != 3) return null;

            try
            {
                // ── 1. header 取 x5c ──
                var headerJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[0]));
                using var headerDoc = JsonDocument.Parse(headerJson);
                if (!headerDoc.RootElement.TryGetProperty("x5c", out var x5cArr)
                    || x5cArr.GetArrayLength() == 0)
                {
                    _logger.LogWarning("Apple JWS: header 缺 x5c");
                    return null;
                }

                var certs = new List<X509Certificate2>();
                foreach (var c in x5cArr.EnumerateArray())
                {
                    var der = Convert.FromBase64String(c.GetString()!);
                    certs.Add(new X509Certificate2(der));
                }

                var leaf = certs[0];

                // ── 2. 驗證憑證鏈到 Apple Root CA - G3 ──
                if (!VerifyChain(certs))
                {
                    _logger.LogWarning("Apple JWS: 憑證鏈驗證失敗");
                    return null;
                }

                // ── 3. 用葉憑證公鑰驗 ES256 簽名 ──
                var signingInput = Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}");
                var signature    = Base64UrlDecode(parts[2]); // JOSE R||S（P-256 = 64 bytes）

                using var ecdsa = leaf.GetECDsaPublicKey();
                if (ecdsa == null)
                {
                    _logger.LogWarning("Apple JWS: 葉憑證非 ECDSA");
                    return null;
                }

                var ok = ecdsa.VerifyData(signingInput, signature, HashAlgorithmName.SHA256,
                    DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
                if (!ok)
                {
                    _logger.LogWarning("Apple JWS: 簽名驗證不通過");
                    return null;
                }

                return Encoding.UTF8.GetString(Base64UrlDecode(parts[1]));
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Apple JWS 驗簽異常");
                return null;
            }
        }

        private bool VerifyChain(List<X509Certificate2> certs)
        {
            using var chain = new X509Chain();
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck; // 離線環境避免 OCSP 卡住
            chain.ChainPolicy.TrustMode      = X509ChainTrustMode.System;  // 由 OS 信任存放區提供 Apple Root CA - G3

            // 把 x5c 帶來的中繼/根加入 ExtraStore 供建鏈（信任仍以 OS 根為準）
            for (int i = 1; i < certs.Count; i++)
                chain.ChainPolicy.ExtraStore.Add(certs[i]);

            var built = chain.Build(certs[0]);
            if (!built)
            {
                foreach (var st in chain.ChainStatus)
                    _logger.LogWarning("Apple JWS 鏈狀態: {Status} {Info}", st.Status, st.StatusInformation);
                return false;
            }

            // 釘選根憑證必須為 Apple Root CA - G3，避免「鏈有效但非 Apple 簽發」
            var root = chain.ChainElements[^1].Certificate;
            if (!root.Subject.Contains(AppleRootCaG3Subject, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogWarning("Apple JWS: 根憑證非 Apple Root CA - G3，實際={Subject}", root.Subject);
                return false;
            }

            return true;
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
