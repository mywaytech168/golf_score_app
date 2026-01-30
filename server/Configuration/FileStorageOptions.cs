namespace UploadServer.Configuration
{
    /// <summary>
    /// 文件存儲配置選項
    /// </summary>
    public class FileStorageOptions
    {
        public const string SectionName = "FileStorage";

        /// <summary>
        /// 基礎目錄（NAS 路徑）
        /// </summary>
        public string BaseDirectory { get; set; }

        /// <summary>
        /// 視頻存儲子目錄
        /// </summary>
        public string VideoDirectory { get; set; }

        /// <summary>
        /// 上傳檔案子目錄
        /// </summary>
        public string UploadDirectory { get; set; }

        /// <summary>
        /// 最大文件大小（字節）
        /// </summary>
        public long MaxFileSize { get; set; }

        /// <summary>
        /// 允許的文件副檔名
        /// </summary>
        public string[] AllowedExtensions { get; set; }

        /// <summary>
        /// 取得完整的視頻目錄路徑
        /// </summary>
        public string GetVideoPath()
        {
            return Path.Combine(BaseDirectory, VideoDirectory);
        }

        /// <summary>
        /// 取得完整的上傳目錄路徑
        /// </summary>
        public string GetUploadPath()
        {
            return Path.Combine(BaseDirectory, UploadDirectory);
        }
    }
}
