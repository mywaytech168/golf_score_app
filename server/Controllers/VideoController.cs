using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using UploadServer.Constants;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 影片管理 API 控制器 (UUID-based Architecture)
    /// </summary>
    [ApiController]
    [Route("api")]
    public class VideoController : ControllerBase
    {
        private readonly VideoDbContext _context;
        private readonly VideoUploadService _uploadService;
        private readonly ILogger<VideoController> _logger;

        public VideoController(
            VideoDbContext context,
            VideoUploadService uploadService,
            ILogger<VideoController> logger)
        {
            _context       = context;
            _uploadService = uploadService;
            _logger        = logger;
        }

        /// <summary>
        /// 取得目前登入用戶的 UUID
        /// </summary>
        private string GetUserIdFromClaims()
        {
            var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(claim))
            {
                return null;
            }
            return claim;
        }

        /// <summary>
        /// 健康檢查端點
        /// GET: /api/health
        /// </summary>
        [HttpGet("health")]
        public IActionResult HealthCheck()
        {
            return Ok(new
            {
                status = "healthy",
                timestamp = DateTime.UtcNow,
                database = "connected",
                uploadEndpointExample = "POST /api/videos/{videoId}/files",
            });
        }

        /// <summary>
        /// 診斷路由端點 - 檢查是否能接收到請求
        /// POST: /api/videos/{videoId}/files/test
        /// </summary>
        [Authorize]
        [HttpPost("videos/{videoId}/files/test")]
        public IActionResult TestUploadRoute([FromRoute] string videoId, [FromForm] string fileType)
        {
            _logger.LogInformation($"✅ 診斷端點收到請求: VideoId={videoId}, FileType={fileType}");
            return Ok(new
            {
                success = true,
                message = "診斷端點工作正常",
                videoId = videoId,
                fileType = fileType,
            });
        }

        /// <summary>
        /// 建立新影片紀錄
        /// POST: /api/videos
        /// </summary>
        [Authorize]
        [HttpPost("videos")]
        public async Task<IActionResult> CreateVideo([FromBody] CreateVideoRequest request)
        {
            try
            {
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                if (string.IsNullOrEmpty(request?.Name))
                {
                    return BadRequest(new { success = false, error = "名稱為必需" });
                }

                var (success, video, error) = await _uploadService.CreateVideoAsync(
                    userId, 
                    request.Name, 
                    request.ParentVideoId,
                    request.HitSecond,
                    request.StartSecond,
                    request.EndSecond,
                    request.PeakValue,
                    request.GoodShot,
                    request.AudioCrispness,
                    request.SourceLocalFilePath);

                if (!success)
                {
                    return BadRequest(new { success = false, error });
                }

                _context.Videos.Add(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 影片已建立: Id={video.Id}, Name={video.Name}");

                return Created($"api/videos/{video.Id}", new
                {
                    success = true,
                    video = video,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 建立影片失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 上傳檔案
        /// POST: /api/videos/{videoId}/files
        /// </summary>
        [Authorize]
        [HttpPost("videos/{videoId}/files")]
        public async Task<IActionResult> UploadFile(
            [FromRoute] string videoId, 
            [FromForm] string fileType, 
            [FromForm] IFormFile file, 
            [FromForm] string sourceLocalFilePath = null,
            [FromForm] double? peakValue = null)
        {
            try
            {
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("📤 接收上傳文件請求");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation($"🎯 VideoId: {videoId}");
                _logger.LogInformation($"🏷️ FileType: {fileType}");
                _logger.LogInformation($"📎 File: {file?.FileName} ({file?.Length} 字節)");
                if (!string.IsNullOrEmpty(sourceLocalFilePath))
                {
                    _logger.LogInformation($"💾 SourceLocalFilePath: {sourceLocalFilePath}");
                }
                if (peakValue != null)
                {
                    _logger.LogInformation($"📊 PeakValue: {peakValue}");
                }
                
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("❌ 未找到用戶身份");
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }
                
                _logger.LogInformation($"👤 UserId: {userId}");

                // 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限");
                    _logger.LogWarning($"   查詢條件: VideoId={videoId}, UserId={userId}");
                    
                    var allVideos = await _context.Videos.Where(v => v.UserId == userId).Select(v => new { v.Id, v.Name }).ToListAsync();
                    _logger.LogWarning($"📋 用戶擁有的影片總數: {allVideos.Count}");
                    foreach (var v in allVideos)
                    {
                        _logger.LogWarning($"   - {v.Id}: {v.Name}");
                    }
                    
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }
                
                _logger.LogInformation($"✅ 影片存在: {video.Name}");

                // 如果提供了 peakValue，更新到影片
                if (peakValue != null)
                {
                    video.PeakValue = peakValue;
                    _context.Videos.Update(video);
                    await _context.SaveChangesAsync();
                    _logger.LogInformation($"✅ 影片的 PeakValue 已更新: {peakValue}");
                }

                var (success, fileRecord, error) = await _uploadService.UploadFileAsync(
                    userId,
                    videoId,
                    fileType,
                    file,
                    sourceLocalFilePath: sourceLocalFilePath);

                if (!success)
                {
                    _logger.LogError($"❌ 檔案上傳服務失敗: {error}");
                    return BadRequest(new { success = false, error });
                }

                _context.Files.Add(fileRecord);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 檔案已上傳: Id={fileRecord.Id}, Type={fileType}");
                _logger.LogInformation("════════════════════════════════════════════════════════════");

                // 返回簡化的檔案信息，避免序列化問題
                return Created($"api/files/{fileRecord.Id}", new 
                { 
                    success = true, 
                    file = new 
                    {
                        id = fileRecord.Id,
                        videoId = fileRecord.VideoId,
                        type = fileRecord.Type,
                        fileName = fileRecord.FileName,
                        fileSize = fileRecord.FileSize,
                        mimeType = fileRecord.MimeType,
                        status = fileRecord.Status,
                        createdAt = fileRecord.CreatedAt,
                        completedAt = fileRecord.CompletedAt,
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 上傳檔案失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 標記影片上傳完成
        /// POST: /api/videos/{videoId}/complete
        /// 當所有檔案上傳完成後調用此端點
        /// </summary>
        [Authorize]
        [HttpPost("videos/{videoId}/complete")]
        public async Task<IActionResult> CompleteVideoUpload([FromRoute] string videoId)
        {
            try
            {
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("✅ 標記影片上傳完成");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation($"🎯 VideoId: {videoId}");

                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("❌ 未找到用戶身份");
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                _logger.LogInformation($"👤 UserId: {userId}");

                // 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限");
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                _logger.LogInformation($"✅ 影片存在: {video.Name}");

                // 獲取該影片的所有檔案
                var files = await _context.Files.Where(f => f.VideoId == videoId).ToListAsync();
                _logger.LogInformation($"📂 影片包含 {files.Count} 個檔案");

                // 檢查是否所有檔案都已上傳完成
                var allFilesCompleted = files.All(f => f.Status == VideoStatus.Completed || f.CompletedAt != null);
                if (!allFilesCompleted)
                {
                    var incompleteCount = files.Count(f => f.Status != VideoStatus.Completed && f.CompletedAt == null);
                    _logger.LogWarning($"⚠️ 還有 {incompleteCount} 個檔案未完成上傳");
                    return BadRequest(new 
                    { 
                        success = false, 
                        error = "並非所有檔案都已上傳完成",
                        completedFiles = files.Count(f => f.Status == VideoStatus.Completed).ToString(),
                        totalFiles = files.Count.ToString()
                    });
                }

                // 更新影片狀態為 completed
                video.Status = VideoStatus.Completed;
                video.UpdatedAt = DateTime.UtcNow;
                _context.Videos.Update(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 影片狀態已更新為 completed");

                // ✅ 改進：創建對應的處理隊列項目
                if (files.Any(x=>x.Type == VideoType.Clip))
                {
                    var queueItem = new ProcessQueueItem
                    {
                        Id = Guid.NewGuid().ToString(),
                        VideoId = videoId,
                        Status = QueueStatus.Ready,
                        CreatedAt = DateTime.UtcNow,
                        Video = video
                    };
                    _context.ProcessQueueItems.Add(queueItem);
                    await _context.SaveChangesAsync();
                    _logger.LogInformation($"✅ 處理隊列項目已創建: {queueItem.Id}");
                    _logger.LogInformation("════════════════════════════════════════════════════════════");
                }


                return Ok(new
                {
                    success = true,
                    message = "影片上傳完成",
                    video = new
                    {
                        id = video.Id,
                        name = video.Name,
                        status = video.Status,
                        filesCount = files.Count,
                        completedAt = video.UpdatedAt,
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 標記影片上傳完成失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 取得用戶的影片列表（帶處理隊列狀態與好球/壞球篩選）
        /// GET: /api/videos?status={status}&goodShot={true/false}
        /// </summary>
        [Authorize]
        [HttpGet("videos")]
        public async Task<IActionResult> GetVideos(
            [FromQuery] string status = null,
            [FromQuery] bool? goodShot = null)
        {
            try
            {
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                var query = _context.Videos
                    .Where(v => v.UserId == userId)
                    .AsQueryable();

                if (!string.IsNullOrEmpty(status))
                {
                    query = query.Where(v => v.Status == status);
                }

                // 添加好球/壞球篩選
                if (goodShot.HasValue)
                {
                    query = query.Where(v => v.GoodShot == goodShot.Value);
                }

                var videos = await query
                    .OrderByDescending(v => v.CreatedAt)
                    .Select(v => new VideoResponse
                    {
                        Id = v.Id,
                        Name = v.Name,
                        Status = v.Status,
                        GoodShot = v.GoodShot,
                        ParentVideoId = v.ParentVideoId,
                        CreatedAt = v.CreatedAt,
                        UpdatedAt = v.UpdatedAt,
                    })
                    .ToListAsync();

                // 為每個影片獲取其處理隊列狀態
                var videosWithQueueStatus = new List<dynamic>();
                foreach (var video in videos)
                {
                    // 查詢該影片的最新隊列項目
                    var queueItem = await _context.ProcessQueueItems
                        .Where(q => q.VideoId == video.Id)
                        .OrderByDescending(q => q.CreatedAt)
                        .FirstOrDefaultAsync();

                    var queueStatus = queueItem != null ? new
                    {
                        status = queueItem.Status,
                        isSuccess = queueItem.IsSuccess
                    } : null;

                    // 獲取該影片的主要文件類型（優先順序：pose_phase_trajectory_video > clip > original）
                    var videoFiles = await _context.Files
                        .Where(f => f.VideoId == video.Id)
                        .OrderByDescending(f => f.Type == VideoType.Clip)
                        .FirstOrDefaultAsync();
                    var mainFileType = videoFiles?.Type ?? "unknown";

                    videosWithQueueStatus.Add(new
                    {
                        video.Id,
                        video.Name,
                        video.Status,
                        video.ParentVideoId,
                        mainFileType,
                        video.CreatedAt,
                        video.UpdatedAt,
                        queueStatus,
                        video.GoodShot
                    });
                }

                _logger.LogInformation($"📊 查詢影片列表: UserId={userId}, Total={videosWithQueueStatus.Count}, GoodShot={goodShot}");

                return Ok(new
                {
                    success = true,
                    data = videosWithQueueStatus,
                    total = videosWithQueueStatus.Count,
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 取得影片列表失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 取得特定影片的處理隊列狀態
        /// GET: /api/videos/{videoId}/queue-status
        /// </summary>
        [Authorize]
        [HttpGet("videos/{videoId}/queue-status")]
        public async Task<IActionResult> GetVideoQueueStatus(string videoId)
        {
            try
            {
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                // 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限: VideoId={videoId}");
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                // 查詢該影片的所有隊列項目
                var queueItems = await _context.ProcessQueueItems
                    .Where(q => q.VideoId == videoId)
                    .OrderByDescending(q => q.CreatedAt)
                    .ToListAsync();

                var queueStatus = new
                {
                    videoId,
                    videoName = video.Name,
                    summary = new
                    {
                        total = queueItems.Count,
                        pending = queueItems.Count(q => q.Status == VideoStatus.Pending),
                        processing = queueItems.Count(q => q.Status == VideoStatus.Processing),
                        completed = queueItems.Count(q => q.Status == VideoStatus.Completed),
                        failed = queueItems.Count(q => q.Status == VideoStatus.Failed),
                        successCount = queueItems.Count(q => q.IsSuccess == true),
                    },
                    items = queueItems.Select(q => new
                    {
                        id = q.Id,
                        status = q.Status,
                        isSuccess = q.IsSuccess,
                        createdAt = q.CreatedAt,
                        startedAt = q.StartedAt,
                        completedAt = q.CompletedAt,
                        retryCount = q.RetryCount
                    }).ToList()
                };

                _logger.LogInformation($"📊 查詢影片隊列狀態: VideoId={videoId}, Items={queueItems.Count}");

                return Ok(new
                {
                    success = true,
                    data = queueStatus
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 取得影片隊列狀態失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 取得單個影片詳細信息
        /// GET: /api/videos/{videoId}
        /// </summary>
        [Authorize]
        [HttpGet("videos/{videoId}")]
        public async Task<IActionResult> GetVideoDetail(string videoId)
        {
            try
            {
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                var video = await _context.Videos
                    .FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);

                if (video == null)
                {
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                var files = await _context.Files.Where(f => f.VideoId == videoId).ToListAsync();
                var processQueue = await _context.ProcessQueueItems.Where(pq => pq.VideoId == videoId).ToListAsync();

                _logger.LogInformation($"📋 查詢影片詳情: VideoId={videoId}");

                // 按優先度排序檔案：pose_phase_trajectory_video 優先，然後是 clip，最後是 original
                var sortedFiles = files
                    .OrderByDescending(f => f.Type == FileType.PosePhaseVideo)
                    .ThenByDescending(f => f.Type == VideoType.Clip)
                    .ToList();

                // 取得主要文件類型（優先順序：pose_phase_trajectory_video > clip > original）
                var mainFileType = sortedFiles.FirstOrDefault()?.Type ?? "unknown";

                // 查詢該影片的最新隊列項目
                var queueItem = await _context.ProcessQueueItems
                    .Where(q => q.VideoId == videoId)
                    .OrderByDescending(q => q.CreatedAt)
                    .FirstOrDefaultAsync();

                var queueStatus = queueItem != null ? new
                {
                    latestStatus = queueItem.Status,
                    isSuccess = queueItem.IsSuccess
                } : null;

                return Ok(new
                {
                    success = true,
                    mainFileType = mainFileType,
                    queueStatus = queueStatus,
                    video = new VideoResponse
                    {
                        Id = video.Id,
                        Name = video.Name,
                        Status = video.Status,
                        ParentVideoId = video.ParentVideoId,
                        CreatedAt = video.CreatedAt,
                        UpdatedAt = video.UpdatedAt,
                    },
                    files = sortedFiles.Select(f => new
                    {
                        f.Id,
                        f.Type,
                        f.FileName,
                        f.FileSize,
                        f.Status,
                    }),
                    processQueue = processQueue.Select(p => new
                    {
                        p.Id,
                        p.Status,
                        p.RetryCount,
                        p.CreatedAt,
                    }),
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 取得影片詳情失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 重新分析影片 (Re-run Analysis)
        /// POST: /api/videos/{videoId}/rerun-analysis
        /// 邏輯：
        ///   1. 檢查該影片是否已經在隊列中 + status = QueueStatus.Ready
        ///   2. 如果有 → 重用現有隊列項目（改為 QueueStatus.Queued）
        ///   3. 如果沒有 → 創建新的隊列項目
        /// </summary>
        [Authorize]
        [HttpPost("videos/{videoId}/rerun-analysis")]
        public async Task<IActionResult> RerunAnalysis(string videoId)
        {
            try
            {
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("🔄 重新分析影片 (Re-run Analysis)");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation($"🎯 VideoId: {videoId}");

                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("❌ 未找到用戶身份");
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                _logger.LogInformation($"👤 UserId: {userId}");

                // ✅ 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限");
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                _logger.LogInformation($"✅ 影片存在: {video.Name}");

                // ✅ 檢查該影片是否已有隊列項目
                var existingReadyQueue = await _context.ProcessQueueItems
                    .FirstOrDefaultAsync(q => q.VideoId == videoId);

                ProcessQueueItem queueItem;

                if (existingReadyQueue != null)
                {
                    // 📌 情況 1：有現成的 QueueStatus.Ready 隊列項目 → 重用它
                    _logger.LogInformation($"♻️ 找到現成的 'ready' 隊列項目: {existingReadyQueue.Id}");
                    
                    // 重設隊列項目狀態為 QueueStatus.Queued
                    existingReadyQueue.Status = QueueStatus.Ready;
                    existingReadyQueue.RetryCount = 0;
                    existingReadyQueue.StartedAt = null;
                    existingReadyQueue.CompletedAt = null;
                    existingReadyQueue.IsSuccess = false;
                    
                    _context.ProcessQueueItems.Update(existingReadyQueue);
                    queueItem = existingReadyQueue;

                    _logger.LogInformation($"✅ 已重用隊列項目，狀態改為 'ready': {queueItem.Id}");
                }
                else
                {
                    // 📌 情況 2：沒有現成的隊列項目 → 創建新的
                    _logger.LogInformation($"✨ 沒有現成的隊列項目，創建新的");
                    
                    queueItem = new ProcessQueueItem
                    {
                        Id = Guid.NewGuid().ToString(),
                        VideoId = videoId,
                        Status = QueueStatus.Ready,
                        CreatedAt = DateTime.UtcNow,
                        Video = video
                    };
                    
                    _context.ProcessQueueItems.Add(queueItem);

                    _logger.LogInformation($"✅ 新隊列項目已創建: {queueItem.Id}");
                }

                // ✅ 保存變更
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 數據庫已更新");
                _logger.LogInformation("════════════════════════════════════════════════════════════");

                return Ok(new
                {
                    success = true,
                    message = "重新分析已排隊",
                    queueItem = new
                    {
                        id = queueItem.Id,
                        videoId = queueItem.VideoId,
                        status = queueItem.Status,
                        createdAt = queueItem.CreatedAt,
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 重新分析影片失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 刪除影片
        /// DELETE: /api/videos/{videoId}
        /// </summary>
        [Authorize]
        [HttpDelete("videos/{videoId}")]
        public async Task<IActionResult> DeleteVideo(string videoId)
        {
            try
            {
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);

                if (video == null)
                {
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                // 刪除相關檔案
                var files = await _context.Files.Where(f => f.VideoId == videoId).ToListAsync();
                foreach (var file in files)
                {
                    await _uploadService.DeleteFileAsync(file.FilePath);
                }

                _context.Files.RemoveRange(files);
                _context.Videos.Remove(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"🗑️ 影片已刪除: VideoId={videoId}");

                return Ok(new { success = true, message = "影片已刪除" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 刪除影片失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 解除雲端綁定
        /// POST: /api/videos/{videoId}/unbind
        /// 將影片狀態更新為 VideoStatus.Unbind
        /// </summary>
        [Authorize]
        [HttpPost("videos/{videoId}/unbind")]
        public async Task<IActionResult> UnbindVideo([FromRoute] string videoId)
        {
            try
            {
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("🔓 解除雲端綁定");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation($"🎯 VideoId: {videoId}");

                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("❌ 未找到用戶身份");
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                _logger.LogInformation($"👤 UserId: {userId}");

                // 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限");
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                _logger.LogInformation($"✅ 影片存在: {video.Name}");

                // 更新影片狀態為 VideoStatus.Unbind
                video.Status = VideoStatus.Unbind;
                video.UpdatedAt = DateTime.UtcNow;
                _context.Videos.Update(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 影片已解除綁定: Id={video.Id}, Status=unbind");
                _logger.LogInformation("════════════════════════════════════════════════════════════");

                return Ok(new
                {
                    success = true,
                    message = "影片已解除雲端綁定",
                    video = new
                    {
                        id = video.Id,
                        name = video.Name,
                        status = video.Status,
                        updatedAt = video.UpdatedAt,
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 解除綁定失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 標記影片為刪除
        /// POST: /api/videos/{videoId}/delete
        /// 將影片狀態更新為 VideoStatus.Deleted
        /// </summary>
        [Authorize]
        [HttpPost("videos/{videoId}/delete")]
        public async Task<IActionResult> MarkVideoAsDeleted([FromRoute] string videoId)
        {
            try
            {
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("🗑️ 標記影片為刪除");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation($"🎯 VideoId: {videoId}");

                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("❌ 未找到用戶身份");
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                _logger.LogInformation($"👤 UserId: {userId}");

                // 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限");
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                _logger.LogInformation($"✅ 影片存在: {video.Name}");

                // 更新影片狀態為 VideoStatus.Deleted
                video.Status = VideoStatus.Deleted;
                video.UpdatedAt = DateTime.UtcNow;
                _context.Videos.Update(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 影片已標記為刪除: Id={video.Id}, Status=deleted");
                _logger.LogInformation("════════════════════════════════════════════════════════════");

                return Ok(new
                {
                    success = true,
                    message = "影片已標記為刪除",
                    video = new
                    {
                        id = video.Id,
                        name = video.Name,
                        status = video.Status,
                        updatedAt = video.UpdatedAt,
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 標記刪除失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

        /// <summary>
        /// 更新影片名稱
        /// PUT: /api/videos/{videoId}
        /// 根據請求體中的 name 欄位更新影片名稱
        /// </summary>
        [Authorize]
        [HttpPut("videos/{videoId}")]
        public async Task<IActionResult> UpdateVideo([FromRoute] string videoId, [FromBody] UpdateVideoNameRequest request)
        {
            try
            {
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("📝 更新影片名稱");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation($"🎯 VideoId: {videoId}");
                _logger.LogInformation($"📛 新名稱: {request?.Name}");

                if (request == null || string.IsNullOrWhiteSpace(request.Name))
                {
                    _logger.LogWarning("❌ 影片名稱不能為空");
                    return BadRequest(new { success = false, error = "影片名稱不能為空" });
                }

                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("❌ 未找到用戶身份");
                    return Unauthorized(new { success = false, error = "無效的用戶身份" });
                }

                _logger.LogInformation($"👤 UserId: {userId}");

                // 驗證影片是否存在且屬於當前用戶
                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == videoId && v.UserId == userId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 影片未找到或無權限");
                    return NotFound(new { success = false, error = "影片不存在或無權限" });
                }

                _logger.LogInformation($"✅ 影片存在: 舊名稱={video.Name}");

                // 更新影片名稱
                video.Name = request.Name.Trim();
                video.UpdatedAt = DateTime.UtcNow;
                _context.Videos.Update(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 影片名稱已更新: Id={video.Id}, 新名稱={video.Name}");
                _logger.LogInformation("════════════════════════════════════════════════════════════");

                return Ok(new
                {
                    success = true,
                    message = "影片名稱已更新",
                    video = new
                    {
                        id = video.Id,
                        name = video.Name,
                        status = video.Status,
                        updatedAt = video.UpdatedAt,
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 更新名稱失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }


        /// <summary>
        /// 統計汇总数据 API
        /// 支持时间维度：all（总表）、today（今天）、tomorrow（明天）、指定日期
        /// </summary>
        [Authorize]
        [HttpGet("statistics")]
        public async Task<IActionResult> GetStatistics([FromQuery] string period = "all", [FromQuery] string? date = null)
        {
            try
            {
                var userId = GetUserIdFromClaims();
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized(new { success = false, error = "未授权的用户" });
                }

                var query = _context.Videos
                    .Where(v => v.UserId == userId && v.Status == VideoStatus.Completed && v.GoodShot != null);

                // 根据时间维度筛选
                DateTime? startDate = null;
                DateTime? endDate = null;

                switch (period.ToLower())
                {
                    case "today":
                        startDate = DateTime.UtcNow.Date;
                        endDate = DateTime.UtcNow.Date.AddDays(1);
                        break;
                    case "yesterday":
                        startDate = DateTime.UtcNow.Date.AddDays(-1);
                        endDate = DateTime.UtcNow.Date;
                        break;
                    case "date":
                        if (DateTime.TryParse(date, out var parsedDate))
                        {
                            startDate = parsedDate.Date;
                            endDate = parsedDate.Date.AddDays(1);
                        }
                        break;
                    case "all":
                    default:
                        // 无日期限制
                        break;
                }

                if (startDate.HasValue && endDate.HasValue)
                {
                    query = query.Where(v => v.CreatedAt >= startDate && v.CreatedAt < endDate);
                }

                var videos = await query.ToListAsync();

                // 计算统计数据
                var totalVideos = videos.Count;
                var goodShots = videos.Count(v => v.GoodShot == true);
                var badShots = videos.Count(v => v.GoodShot == false);
                var goodShotPercentage = totalVideos > 0 ? (double)goodShots / totalVideos * 100 : 0;

                // 计算峰值速度的平均值和最大值
                var peakValues = videos.Where(v => v.PeakValue.HasValue).Select(v => v.PeakValue.Value).ToList();
                var avgPeakValue = peakValues.Count > 0 ? peakValues.Average() : 0;
                var maxPeakValue = peakValues.Count > 0 ? peakValues.Max() : 0;

                // 计算音频清脆度的平均值和最小值
                var crispnessValues = videos.Where(v => v.AudioCrispness.HasValue).Select(v => v.AudioCrispness.Value).ToList();
                var avgAudioCrispness = crispnessValues.Count > 0 ? crispnessValues.Average() : 0;
                var minAudioCrispness = crispnessValues.Count > 0 ? crispnessValues.Min() : 0;

                var statistics = new
                {
                    success = true,
                    period = period,
                    date = date,
                    totalCount = totalVideos,
                    goodShot = goodShots,
                    badShot = badShots,
                    sweetSpotPercentage = Math.Round(goodShotPercentage, 2),
                    peakValue = new
                    {
                        average = Math.Round(avgPeakValue, 2),
                        maximum = Math.Round(maxPeakValue, 2)
                    },
                    audioCrispness = new
                    {
                        average = Math.Round(avgAudioCrispness, 2),
                        minimum = Math.Round(minAudioCrispness, 2)
                    }
                };

                _logger.LogInformation($"📊 获取统计数据成功 - 用户: {userId}, 时间段: {period}, 总数: {totalVideos}");
                return Ok(statistics);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 获取统计数据失败");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }

    }
}
