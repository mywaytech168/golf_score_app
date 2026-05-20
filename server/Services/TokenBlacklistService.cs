namespace UploadServer.Services
{
    /// <summary>
    /// 記憶體式 JWT JTI 黑名單，用於使登出後的 token 立即失效。
    /// 單機部署適用；多節點部署應改用 Redis。
    /// </summary>
    public class TokenBlacklistService : ITokenBlacklistService
    {
        private readonly Dictionary<string, DateTime> _revokedJtis = new();
        private readonly object _lock = new();

        /// <summary>將指定 JTI 加入黑名單，直到 token 自然過期</summary>
        public void Revoke(string jti, DateTime expiresAt)
        {
            lock (_lock)
            {
                _revokedJtis[jti] = expiresAt;
                Cleanup();
            }
        }

        /// <summary>檢查 JTI 是否已被撤銷</summary>
        public bool IsRevoked(string jti)
        {
            lock (_lock)
            {
                if (!_revokedJtis.TryGetValue(jti, out var exp)) return false;
                if (exp < DateTime.UtcNow) { _revokedJtis.Remove(jti); return false; }
                return true;
            }
        }

        private void Cleanup()
        {
            var now = DateTime.UtcNow;
            foreach (var key in _revokedJtis.Where(kvp => kvp.Value < now).Select(kvp => kvp.Key).ToList())
                _revokedJtis.Remove(key);
        }
    }
}
