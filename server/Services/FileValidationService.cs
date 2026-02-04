using Microsoft.AspNetCore.Http;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;

namespace UploadServer.Services
{
    /// <summary>
    /// 檔案驗證服務 (修復 2️⃣: 檔案類型驗證)
    /// </summary>
    public class FileValidationService
    {
        private readonly ILogger<FileValidationService> _logger;

        // 允許的副檔名白名單
        private static readonly HashSet<string> AllowedExtensions = new()
        {
            ".mp4", ".avi", ".mov", ".mkv", ".webm",  // 視頻
            ".wav", ".mp3", ".aac", ".flac",            // 音頻
            ".jpg", ".jpeg", ".png", ".bmp", ".webp",   // 圖像
            ".json", ".xml", ".csv"                      // 數據
        };

        // MIME 類型白名單
        private static readonly Dictionary<string, string[]> MimeTypeMap = new()
        {
            { ".mp4", new[] { "video/mp4" } },
            { ".avi", new[] { "video/x-msvideo", "video/avi" } },
            { ".mov", new[] { "video/quicktime" } },
            { ".mkv", new[] { "video/x-matroska" } },
            { ".webm", new[] { "video/webm" } },
            { ".wav", new[] { "audio/wav", "audio/x-wav" } },
            { ".mp3", new[] { "audio/mpeg", "audio/mp3" } },
            { ".aac", new[] { "audio/aac", "audio/aacp" } },
            { ".flac", new[] { "audio/flac" } },
            { ".jpg", new[] { "image/jpeg" } },
            { ".jpeg", new[] { "image/jpeg" } },
            { ".png", new[] { "image/png" } },
            { ".bmp", new[] { "image/bmp" } },
            { ".webp", new[] { "image/webp" } },
            { ".json", new[] { "application/json" } },
            { ".xml", new[] { "application/xml", "text/xml" } },
            { ".csv", new[] { "text/csv" } }
        };

        public FileValidationService(ILogger<FileValidationService> logger)
        {
            _logger = logger;
        }

        /// <summary>
        /// 驗證上傳的檔案
        /// </summary>
        public async Task<FileValidationResult> ValidateFileAsync(
            IFormFile file,
            string requestedFileType)
        {
            try
            {
                // 1. 檢查檔案是否為空
                if (file == null || file.Length == 0)
                {
                    return new FileValidationResult(false, "檔案為空");
                }

                // 2. 驗證副檔名
                var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
                if (string.IsNullOrEmpty(extension))
                {
                    return new FileValidationResult(false, "檔案沒有副檔名");
                }

                if (!AllowedExtensions.Contains(extension))
                {
                    _logger.LogWarning($"⚠️ 不允許的檔案類型: {extension}");
                    return new FileValidationResult(false, 
                        $"不允許的檔案類型: {extension}");
                }

                // 3. 驗證 MIME 類型
                var mimeType = file.ContentType;
                if (!IsValidMimeType(extension, mimeType))
                {
                    _logger.LogWarning($"⚠️ MIME 類型不符: {mimeType} for {extension}");
                    return new FileValidationResult(false, 
                        $"MIME 類型不符: {mimeType}");
                }

                // 4. 驗證檔案簽名 (魔法數字)
                var signatureValid = await IsValidFileSignatureAsync(file, extension);
                if (!signatureValid)
                {
                    _logger.LogWarning($"⚠️ 檔案簽名不符: {extension}");
                    return new FileValidationResult(false, 
                        "檔案簽名不符，可能是偽造檔案");
                }

                _logger.LogInformation($"✅ 檔案驗證通過: {file.FileName} ({extension})");
                return new FileValidationResult(true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 檔案驗證異常");
                return new FileValidationResult(false, $"驗證異常: {ex.Message}");
            }
        }

        /// <summary>
        /// 驗證 MIME 類型是否允許
        /// </summary>
        private bool IsValidMimeType(string extension, string mimeType)
        {
            if (!MimeTypeMap.TryGetValue(extension, out var validMimes))
            {
                return true; // 如果沒有定義的 MIME 類型，允許
            }

            return validMimes.Contains(mimeType);
        }

        /// <summary>
        /// 驗證檔案簽名 (魔法數字)
        /// </summary>
        private async Task<bool> IsValidFileSignatureAsync(IFormFile file, string extension)
        {
            try
            {
                var buffer = new byte[8];
                using var stream = file.OpenReadStream();
                await stream.ReadAsync(buffer, 0, 8);

                return extension switch
                {
                    // MP4: 00 00 00 XX 66 74 79 70
                    ".mp4" => buffer[4] == 0x66 && buffer[5] == 0x74 && buffer[6] == 0x79 && buffer[7] == 0x70,
                    
                    // MP3: FF FB 或 FF FA
                    ".mp3" => buffer[0] == 0xFF && (buffer[1] == 0xFB || buffer[1] == 0xFA),
                    
                    // WAV: 52 49 46 46 (RIFF)
                    ".wav" => buffer[0] == 0x52 && buffer[1] == 0x49 && buffer[2] == 0x46 && buffer[3] == 0x46,
                    
                    // JPEG: FF D8 FF
                    ".jpg" or ".jpeg" => buffer[0] == 0xFF && buffer[1] == 0xD8 && buffer[2] == 0xFF,
                    
                    // PNG: 89 50 4E 47
                    ".png" => buffer[0] == 0x89 && buffer[1] == 0x50 && buffer[2] == 0x4E && buffer[3] == 0x47,
                    
                    // 其他類型允許
                    _ => true
                };
            }
            catch (Exception ex)
            {
                _logger.LogWarning($"⚠️ 無法驗證檔案簽名: {ex.Message}");
                return true; // 如果無法讀取簽名，允許
            }
        }
    }

    /// <summary>
    /// 檔案驗證結果
    /// </summary>
    public class FileValidationResult
    {
        public bool IsValid { get; }
        public string Error { get; }

        public FileValidationResult(bool isValid, string error)
        {
            IsValid = isValid;
            Error = error;
        }
    }
}
