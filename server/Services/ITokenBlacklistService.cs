namespace UploadServer.Services
{
    /// <summary>
    /// JWT JTI 黑名單介面。
    /// 預設實作為記憶體版（單機），多節點部署時替換為 Redis 實作即可。
    /// </summary>
    public interface ITokenBlacklistService
    {
        /// <summary>撤銷指定 JTI，直到 token 自然過期</summary>
        void Revoke(string jti, DateTime expiresAt);

        /// <summary>回傳 true 表示該 JTI 已被撤銷（尚未過期）</summary>
        bool IsRevoked(string jti);
    }
}
