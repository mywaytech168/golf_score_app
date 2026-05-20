using Microsoft.AspNetCore.Http;
using UploadServer.Models;
using FileModel = UploadServer.Models.File;

namespace UploadServer.Services
{
    public class VideoUploadService
    {
        private readonly ILogger<VideoUploadService> _logger;

        public VideoUploadService(ILogger<VideoUploadService> logger)
        {
            _logger = logger;
        }

        public async Task<(bool Success, Video Video, string Error)> CreateVideoAsync(
            string userId,
            string name,
            string? parentVideoId = null,
            double? hitSecond = null,
            double? startSecond = null,
            double? endSecond = null,
            double? peakValue = null,
            bool? goodShot = null,
            double? audioCrispness = null,
            string? sourceLocalFilePath = null)
        {
            try
            {
                var video = new Video
                {
                    Id            = Guid.NewGuid().ToString(),
                    UserId        = userId,
                    Name          = name,
                    ParentVideoId = parentVideoId,
                    HitSecond     = hitSecond,
                    StartSecond   = startSecond,
                    EndSecond     = endSecond,
                    PeakValue     = peakValue,
                    GoodShot      = goodShot,
                    AudioCrispness = audioCrispness,
                    Status        = VideoStatus.Pending,
                    CreatedAt     = DateTime.UtcNow,
                    UpdatedAt     = DateTime.UtcNow,
                };

                _logger.LogInformation($"✅ Created video: {video.Name} (ID: {video.Id}) for user {userId}");
                return (true, video, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Error creating video");
                return (false, null, ex.Message);
            }
        }

        /// <summary>
        /// 建立檔案元數據記錄（實際檔案存於 Backblaze B2）。
        /// fileName / b2Key 由呼叫端（Flutter 直傳 B2 後回報）提供。
        /// </summary>
        public Task<(bool Success, FileModel FileRecord, string Error)> UploadFileAsync(
            string userId,
            string videoId,
            string fileType,
            IFormFile? formFile = null,
            string? fileName = null,
            string? sourceLocalFilePath = null)
        {
            try
            {
                var actualFileName = fileName ?? formFile?.FileName ?? $"{fileType}.bin";
                var fileSize       = formFile?.Length ?? 0;
                var b2Key          = sourceLocalFilePath ?? "";   // B2 object key / URL 由呼叫端填入

                var fileRecord = new FileModel
                {
                    Id          = Guid.NewGuid().ToString(),
                    VideoId     = videoId,
                    Type        = fileType,
                    FileName    = actualFileName,
                    FilePath    = b2Key,
                    FileSize    = fileSize,
                    MimeType    = formFile?.ContentType ?? "application/octet-stream",
                    Status      = VideoStatus.Completed,
                    CreatedAt   = DateTime.UtcNow,
                    CompletedAt = DateTime.UtcNow,
                    SourceLocalFilePath = b2Key,
                };

                _logger.LogInformation(
                    $"✅ 檔案元數據已記錄: {actualFileName} (Type: {fileType}) for video {videoId}");

                return Task.FromResult<(bool, FileModel, string)>((true, fileRecord, null));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ 建立檔案記錄失敗: 視頻 {videoId}");
                return Task.FromResult<(bool, FileModel, string)>((false, null, ex.Message));
            }
        }

        public async Task<List<(bool Success, FileModel FileRecord, string Error)>> UploadMultipleFilesAsync(
            string userId,
            string videoId,
            List<(string Type, IFormFile FormFile)> files)
        {
            var results = new List<(bool, FileModel, string)>();
            foreach (var (type, formFile) in files)
                results.Add(await UploadFileAsync(userId, videoId, type, formFile));
            return results;
        }

        public Task<bool> DeleteFileAsync(string filePath)
        {
            // 實際刪除由 B2Service 負責；此處僅記錄
            _logger.LogInformation($"🗑️ B2 file deletion not implemented here: {filePath}");
            return Task.FromResult(true);
        }
    }
}
