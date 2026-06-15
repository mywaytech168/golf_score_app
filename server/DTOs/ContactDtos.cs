namespace UploadServer.DTOs
{
    // ════════════════════════════════════════════════════════════════
    // 聯絡我們表單（App + 官網共用）
    // ════════════════════════════════════════════════════════════════

    /// <summary>POST /api/contact 請求</summary>
    public record ContactMessageRequest(
        string? Name,
        string Email,
        string? Subject,
        string Message,
        /// <summary>來源: "app" | "web"；省略時後端視為 "web"</summary>
        string? Source = null,
        /// <summary>Cloudflare Turnstile token（官網表單）；App 來源不需要</summary>
        string? Turnstile = null);

    /// <summary>POST /api/contact 回應</summary>
    public record ContactMessageResponse(bool Success, string Message);

    /// <summary>GET /api/admin/contact-messages — 單筆</summary>
    public record AdminContactMessageDto(
        string Id,
        string Source,
        string? Name,
        string Email,
        string? Subject,
        string Message,
        string? UserId,
        bool Handled,
        string? HandledAt,
        string? AdminNote,
        string CreatedAt);

    /// <summary>POST /api/admin/contact-messages/{id}/handle 請求</summary>
    public record HandleContactMessageRequest(bool Handled, string? Note);
}
