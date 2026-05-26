namespace UploadServer.Models
{
    public class Announcement
    {
        public string Id          { get; set; } = Guid.NewGuid().ToString();
        public string Title       { get; set; } = string.Empty;
        public string Body        { get; set; } = string.Empty;
        public string Type        { get; set; } = "info";   // info | important | event | update
        public DateTime PublishedAt { get; set; } = DateTime.UtcNow;
        public DateTime? ExpiresAt  { get; set; }
        public string? ImageUrl     { get; set; }
        public bool IsActive      { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
