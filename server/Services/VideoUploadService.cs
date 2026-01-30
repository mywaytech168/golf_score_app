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
            string? parentVideoId = null)
        {
            try
            {
                var video = new Video
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = userId,
                    Name = name,
                    ParentVideoId = parentVideoId,
                    Status = "pending",
                    CreatedAt = DateTime.Now,
                    UpdatedAt = DateTime.Now,
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
        /// 上傳檔案
        /// </summary>
        public async Task<(bool Success, FileModel FileRecord, string Error)> UploadFileAsync(
            string userId,
            string videoId,
            string fileType,
            IFormFile formFile,
            string fileName = null,
            string sourceLocalFilePath = null)
        {
            try
            {
                if (formFile == null || formFile.Length == 0)
                {
                    return (false, null, "File is empty");
                }

                // 建立目錄結構：/storage/videos/{userId}/{videoId}/
                var fileDir = System.IO.Path.Combine(_baseUploadDir, userId, videoId);
                Directory.CreateDirectory(fileDir);

                // 從原始檔名取得副檔名
                var extension = System.IO.Path.GetExtension(formFile.FileName);
                // 使用格式：{fileType}.{extension}
                var actualFileName = $"{fileType}{extension}";
                var filePath = System.IO.Path.Combine(fileDir, actualFileName);

                // 儲存檔案
                using (var stream = System.IO.File.Create(filePath))
                {
                    await formFile.CopyToAsync(stream);
                }

                var fileRecord = new FileModel
                {
                    Id = Guid.NewGuid().ToString(),
                    VideoId = videoId,
                    Type = fileType,
                    FileName = actualFileName,
                    FilePath = filePath,
                    FileSize = formFile.Length,
                    MimeType = formFile.ContentType,
                    Status = "completed",
                    CreatedAt = DateTime.Now,
                    CompletedAt = DateTime.Now,
                    SourceLocalFilePath = sourceLocalFilePath
                };

                _logger.LogInformation(
                    $"✅ 上傳檔案: {actualFileName} (Type: {fileType}) for video {videoId}. " +
                    $"路徑: {filePath}, 大小: {formFile.Length} bytes"
                );

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
