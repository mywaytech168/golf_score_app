using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
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
            _context = context;
            _uploadService = uploadService;
            _logger = logger;
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
                timestamp = DateTime.Now,
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

                var (success, video, error) = await _uploadService.CreateVideoAsync(userId, request.Name, request.ParentVideoId);

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
        public async Task<IActionResult> UploadFile([FromRoute] string videoId, [FromForm] string fileType, [FromForm] IFormFile file, [FromForm] string sourceLocalFilePath = null)
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

                var (success, fileRecord, error) = await _uploadService.UploadFileAsync(userId, videoId, fileType, file, sourceLocalFilePath: sourceLocalFilePath);

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
                var allFilesCompleted = files.All(f => f.Status == "completed" || f.CompletedAt != null);
                if (!allFilesCompleted)
                {
                    var incompleteCount = files.Count(f => f.Status != "completed" && f.CompletedAt == null);
                    _logger.LogWarning($"⚠️ 還有 {incompleteCount} 個檔案未完成上傳");
                    return BadRequest(new 
                    { 
                        success = false, 
                        error = "並非所有檔案都已上傳完成",
                        completedFiles = files.Count(f => f.Status == "completed").ToString(),
                        totalFiles = files.Count.ToString()
                    });
                }

                // 更新影片狀態為 completed
                video.Status = "completed";
                video.UpdatedAt = DateTime.Now;
                _context.Videos.Update(video);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 影片狀態已更新為 completed");

                // ✅ 改進：創建對應的處理隊列項目
                if (files.Any(x=>x.Type == "clip"))
                {
                    var queueItem = new ProcessQueueItem
                    {
                        Id = Guid.NewGuid().ToString(),
                        VideoId = videoId,
                        Status = "ready",
                        CreatedAt = DateTime.Now,
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
        /// 取得用戶的影片列表（帶處理隊列狀態）
        /// GET: /api/videos?status={status}&page={page}&limit={limit}
        /// </summary>
        [Authorize]
        [HttpGet("videos")]
        public async Task<IActionResult> GetVideos(
            [FromQuery] string status = null,
            [FromQuery] int page = 1,
            [FromQuery] int limit = 10)
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

                var total = await query.CountAsync();

                var videos = await query
                    .OrderByDescending(v => v.CreatedAt)
                    .Skip((page - 1) * limit)
                    .Take(limit)
                    .Select(v => new VideoResponse
                    {
                        Id = v.Id,
                        Name = v.Name,
                        Status = v.Status,
                        ParentVideoId = v.ParentVideoId,
                        CreatedAt = v.CreatedAt,
                        UpdatedAt = v.UpdatedAt,
                    })
                    .ToListAsync();

                // 為每個影片獲取其處理隊列狀態
                var videosWithQueueStatus = new List<dynamic>();
                foreach (var video in videos)
                {
                    // 查詢該影片的所有隊列項目
                    var queueItems = await _context.ProcessQueueItems
                        .Where(q => q.VideoId == video.Id)
                        .OrderByDescending(q => q.CreatedAt)
                        .ToListAsync();

                    var queueStatus = queueItems.Any() ? new
                    {
                        total = queueItems.Count,
                        pending = queueItems.Count(q => q.Status == "pending"),
                        processing = queueItems.Count(q => q.Status == "processing"),
                        completed = queueItems.Count(q => q.Status == "completed"),
                        failed = queueItems.Count(q => q.Status == "failed"),
                        successCount = queueItems.Count(q => q.IsSuccess == true),
                        latestStatus = queueItems.FirstOrDefault()?.Status
                    } : null;

                    videosWithQueueStatus.Add(new
                    {
                        video.Id,
                        video.Name,
                        video.Status,
                        video.ParentVideoId,
                        video.CreatedAt,
                        video.UpdatedAt,
                        queueStatus
                    });
                }

                _logger.LogInformation($"📊 查詢影片列表: UserId={userId}, Total={total}");

                return Ok(new
                {
                    success = true,
                    data = videosWithQueueStatus,
                    pagination = new
                    {
                        page,
                        limit,
                        total,
                        pages = (int)Math.Ceiling((decimal)total / limit),
                    },
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
                        pending = queueItems.Count(q => q.Status == "pending"),
                        processing = queueItems.Count(q => q.Status == "processing"),
                        completed = queueItems.Count(q => q.Status == "completed"),
                        failed = queueItems.Count(q => q.Status == "failed"),
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

                // 按優先度排序檔案：clip 優先，然後是 pose_phase_trajectory_video
                var sortedFiles = files
                    .OrderByDescending(f => f.Type == "clip")
                    .ThenByDescending(f => f.Type == "pose_phase_trajectory_video")
                    .ToList();

                return Ok(new
                {
                    success = true,
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
        ///   1. 檢查該影片是否已經在隊列中 + status = "ready"
        ///   2. 如果有 → 重用現有隊列項目（改為 "queued"）
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
                    // 📌 情況 1：有現成的 "ready" 隊列項目 → 重用它
                    _logger.LogInformation($"♻️ 找到現成的 'ready' 隊列項目: {existingReadyQueue.Id}");
                    
                    // 重設隊列項目狀態為 "queued"
                    existingReadyQueue.Status = "ready";
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
                        Status = "ready",
                        CreatedAt = DateTime.Now,
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
        /// 獲取影片文件流（用於播放）
        /// GET: /api/videos/{videoId}/stream
        /// 優先返回 clip 類型，其次是 original 類型
        /// </summary>
        [Authorize]
        [HttpGet("videos/{videoId}/stream")]
        public async Task<IActionResult> GetVideoStream(string videoId)
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

                // 優先取得 clip，其次是 original
                var videoFile = await _context.Files
                    .Where(f => f.VideoId == videoId && (f.Type == "clip" || f.Type == "original"))
                    .OrderByDescending(f => f.Type == "clip") // clip 優先
                    .FirstOrDefaultAsync();

                if (videoFile == null)
                {
                    _logger.LogWarning($"❌ 影片檔案未找到: VideoId={videoId}");
                    return NotFound(new { success = false, error = "影片檔案不存在" });
                }

                _logger.LogInformation($"📤 獲取影片流: VideoId={videoId}, FileType={videoFile.Type}, FilePath={videoFile.FilePath}");

                // 檢查檔案是否存在
                if (!System.IO.File.Exists(videoFile.FilePath))
                {
                    _logger.LogWarning($"❌ 檔案不存在: {videoFile.FilePath}");
                    return NotFound(new { success = false, error = "影片檔案不存在於伺服器" });
                }

                // 打開檔案流並返回
                var stream = System.IO.File.OpenRead(videoFile.FilePath);
                return File(stream, videoFile.MimeType ?? "video/mp4", enableRangeProcessing: true);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 獲取影片流失敗");
                return StatusCode(500, new { success = false, error = ex.Message });
            }
        }
    }
}
