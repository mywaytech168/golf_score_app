using System.ComponentModel.DataAnnotations;

namespace UploadServer.DTOs
{
    // ════════════════════════════════════════════════════════════════
    // GET /api/announcements 回應
    // ════════════════════════════════════════════════════════════════

    public record AnnouncementResponse(
        string   Id,
        string   Title,
        string   Body,
        string   Type,
        DateTime PublishedAt,
        DateTime? ExpiresAt,
        string?  ImageUrl
    );

    // ════════════════════════════════════════════════════════════════
    // POST /api/admin/announcements  （建立）
    // PUT  /api/admin/announcements/{id}  （更新）
    // ════════════════════════════════════════════════════════════════

    public record UpsertAnnouncementRequest(
        [Required, MaxLength(255)] string Title,
        [Required] string Body,
        string Type = "info",            // info | important | event | update
        DateTime? PublishedAt = null,    // null → 立即發佈
        DateTime? ExpiresAt  = null,
        string?   ImageUrl   = null,
        bool      IsActive   = true
    );
}
