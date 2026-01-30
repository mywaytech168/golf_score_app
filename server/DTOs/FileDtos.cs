namespace UploadServer.DTOs
{
    /// <summary>
    /// 檔案相关的 DTOs
    /// </summary>

    // ============================================================
    // 創建檔案請求
    // ============================================================
    public class CreateFileRequest
    {
        /// <summary>
        /// 影片 ID
        /// </summary>
        public string VideoId { get; set; }

        /// <summary>
        /// 檔案類型：original, clip, trajectory, thumbnail, processed
        /// </summary>
        public string Type { get; set; }

        /// <summary>
        /// 檔案名稱
        /// </summary>
        public string FileName { get; set; }

        /// <summary>
        /// 檔案 MIME 類型
        /// </summary>
        public string MimeType { get; set; }
    }

    // ============================================================
    // 檔案響應
    // ============================================================
    public class FileResponse
    {
        public string Id { get; set; }
        public string VideoId { get; set; }
        public string Type { get; set; }
        public string FileName { get; set; }
        public string FilePath { get; set; }
        public long FileSize { get; set; }
        public string MimeType { get; set; }
        public string Status { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public string? ErrorMessage { get; set; }
    }

    // ============================================================
    // 檔案上傳完成請求
    // ============================================================
    public class CompleteFileUploadRequest
    {
        /// <summary>
        /// 檔案大小
        /// </summary>
        public long FileSize { get; set; }

        /// <summary>
        /// 最終檔案路徑
        /// </summary>
        public string FilePath { get; set; }
    }

    // ============================================================
    // 檔案上傳完成響應
    // ============================================================
    public class CompleteFileUploadResponse
    {
        public string FileId { get; set; }
        public string VideoId { get; set; }
        public string Type { get; set; }
        public string Status { get; set; }
        public long FileSize { get; set; }
        public DateTime CompletedAt { get; set; }
        public string FilePath { get; set; }
    }

    // ============================================================
    // 删除檔案請求
    // ============================================================
    public class DeleteFileRequest
    {
        public List<string> FileIds { get; set; } = new();
    }

    // ============================================================
    // 删除檔案響應
    // ============================================================
    public class DeleteFileResponse
    {
        public int DeletedCount { get; set; }
        public List<string> FailedIds { get; set; } = new();
    }

    // ============================================================
    // 按類型列出檔案
    // ============================================================
    public class GetFilesByTypeRequest
    {
        /// <summary>
        /// 影片 ID
        /// </summary>
        public string VideoId { get; set; }

        /// <summary>
        /// 檔案類型
        /// </summary>
        public string Type { get; set; }
    }

    // ============================================================
    // 按類型列出檔案響應
    // ============================================================
    public class GetFilesByTypeResponse
    {
        public string VideoId { get; set; }
        public string Type { get; set; }
        public List<FileResponse> Files { get; set; } = new();
    }
}
