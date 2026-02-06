using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using UploadServer.Configuration;
using UploadServer.Models;
using UploadServer.DTOs;
using FileModel = UploadServer.Models.File;

namespace UploadServer.Services
{
    /// <summary>
    /// 視頻檔案上傳服務
    /// </summary>
    public class VideoUploadService
    {
        private readonly string _baseUploadDir;
        private readonly ILogger<VideoUploadService> _logger;
        private readonly FileStorageOptions _fileStorageOptions;

        public VideoUploadService(
            ILogger<VideoUploadService> logger,
            IOptions<FileStorageOptions> fileStorageOptions)
        {
            _logger = logger;
            _fileStorageOptions = fileStorageOptions.Value;
            _baseUploadDir = _fileStorageOptions.GetVideoPath();
            Directory.CreateDirectory(_baseUploadDir);
            
            _logger.LogInformation($"✅ VideoUploadService initialized with base directory: {_baseUploadDir}");
        }

        /// <summary>
        /// 建立新影片紀錄
        /// </summary>
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
                    Id = Guid.NewGuid().ToString(),
                    UserId = userId,
                    Name = name,
                    ParentVideoId = parentVideoId,
                    HitSecond = hitSecond,
                    StartSecond = startSecond,
                    EndSecond = endSecond,
                    PeakValue = peakValue,
                    GoodShot = goodShot,
                    AudioCrispness = audioCrispness,
                    Status = "pending",
                    CreatedAt = DateTime.Now,
                    UpdatedAt = DateTime.Now,
                };

                _logger.LogInformation($"✅ Created video: {video.Name} (ID: {video.Id}) for user {userId}");
                if (hitSecond.HasValue) _logger.LogInformation($"   HitSecond: {hitSecond}");
                if (startSecond.HasValue) _logger.LogInformation($"   StartSecond: {startSecond}");
                if (endSecond.HasValue) _logger.LogInformation($"   EndSecond: {endSecond}");
                if (peakValue.HasValue) _logger.LogInformation($"   PeakValue: {peakValue}");
                if (goodShot.HasValue) _logger.LogInformation($"   GoodShot: {goodShot}");
                if (audioCrispness.HasValue) _logger.LogInformation($"   AudioCrispness: {audioCrispness}");
                
                return (true, video, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Error creating video");
                return (false, null, ex.Message);
            }
        }

        /// <summary>
        /// 上傳檔案
        /// 支援兩種模式：
        /// 1. 手機端上傳 (saveToStorage=true) - 保存檔案到磁盤
        /// 2. Python server 上傳 (saveToStorage=false) - 只記錄元數據到數據庫
        /// </summary>
        public async Task<(bool Success, FileModel FileRecord, string Error)> UploadFileAsync(
            string userId,
            string videoId,
            string fileType,
            IFormFile formFile = null,
            string fileName = null,
            string sourceLocalFilePath = null,
            bool saveToStorage = false)
        {
            try
            {
                // 如果 formFile 為 null，使用 fileName；否則使用 formFile.FileName
                string actualFileName = fileName ?? formFile?.FileName ?? $"{fileType}.bin";
                
                // 建立目錄結構：/storage/videos/{userId}/{videoId}/
                var fileDir = System.IO.Path.Combine(_baseUploadDir, userId, videoId);
                Directory.CreateDirectory(fileDir);

                // 從檔名取得副檔名
                var extension = System.IO.Path.GetExtension(actualFileName);
                // 使用格式：{fileType}.{extension}
                if (string.IsNullOrEmpty(extension))
                {
                    extension = ".bin";
                }
                actualFileName = $"{fileType}{extension}";
                var filePath = System.IO.Path.Combine(fileDir, actualFileName);

                // 計算檔案大小
                long fileSize = formFile?.Length ?? 0;

                // 如果需要保存檔案（手機端上傳），將檔案寫入磁盤
                if (saveToStorage && formFile != null && formFile.Length > 0)
                {
                    using (var stream = System.IO.File.Create(filePath))
                    {
                        await formFile.CopyToAsync(stream);
                    }
                    _logger.LogInformation(
                        $"✅ 手機端檔案已保存: {actualFileName} (Type: {fileType}) for video {videoId}. " +
                        $"路徑: {filePath}, 大小: {fileSize} bytes"
                    );
                }
                else
                {
                    filePath = sourceLocalFilePath;

                    _logger.LogInformation(
                        $"✅ Python server 檔案元數據已記錄: {actualFileName} (Type: {fileType}) for video {videoId}. " +
                        $"路徑: {filePath}, 大小: {fileSize} bytes"
                    );
                }

                var fileRecord = new FileModel
                {
                    Id = Guid.NewGuid().ToString(),
                    VideoId = videoId,
                    Type = fileType,
                    FileName = actualFileName,
                    FilePath = filePath,
                    FileSize = fileSize,
                    MimeType = formFile?.ContentType ?? "application/octet-stream",
                    Status = "completed",
                    CreatedAt = DateTime.Now,
                    CompletedAt = DateTime.Now,
                    SourceLocalFilePath = sourceLocalFilePath
                };

                if (!string.IsNullOrEmpty(sourceLocalFilePath))
                {
                    _logger.LogInformation($"   Source: {sourceLocalFilePath}");
                }

                return (true, fileRecord, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ 上傳檔案失敗: 視頻 {videoId}");
                return (false, null, ex.Message);
            }
        }

        /// <summary>
        /// 批量上傳檔案
        /// </summary>
        public async Task<List<(bool Success, FileModel FileRecord, string Error)>> UploadMultipleFilesAsync(
            string userId,
            string videoId,
            List<(string Type, IFormFile FormFile)> files)
        {
            var results = new List<(bool Success, FileModel FileRecord, string Error)>();

            foreach (var (type, formFile) in files)
            {
                var result = await UploadFileAsync(userId, videoId, type, formFile);
                results.Add(result);
            }

            return results;
        }

        /// <summary>
        /// 刪除檔案
        /// </summary>
        public async Task<bool> DeleteFileAsync(string filePath)
        {
            try
            {
                if (System.IO.File.Exists(filePath))
                {
                    System.IO.File.Delete(filePath);
                    _logger.LogInformation($"✅ Deleted file: {filePath}");
                    return true;
                }

                _logger.LogWarning($"⚠️ File not found: {filePath}");
                return false;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ Error deleting file: {filePath}");
                return false;
            }
        }

        /// <summary>
        /// 取得檔案清單
        /// </summary>
        public List<string> GetFilesInDirectory(string dirPath)
        {
            var files = new List<string>();

            if (!Directory.Exists(dirPath))
            {
                return files;
            }

            try
            {
                var fileInfos = Directory.GetFiles(dirPath);
                files = fileInfos.Select(System.IO.Path.GetFileName).ToList();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ Error reading files from directory {dirPath}");
            }

            return files;
        }
    }
}
