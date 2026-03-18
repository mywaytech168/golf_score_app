using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Newtonsoft.Json;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;
using Microsoft.AspNetCore.Http;
using System.IO;
using System.Text.Json;
using FileModel = UploadServer.Models.File;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 處理回調 API 控制器
    /// 接收來自 Python Server 的處理結果
    /// </summary>
    [ApiController]
    [Route("api/callback")]
    public class CallbackController : ControllerBase
    {
        private readonly VideoDbContext _context;
        private readonly ILogger<CallbackController> _logger;
        private readonly VideoUploadService _uploadService;

        public CallbackController(
            VideoDbContext context,
            ILogger<CallbackController> logger,
            VideoUploadService uploadService)
        {
            _context = context;
            _logger = logger;
            _uploadService = uploadService;
        }

        /// <summary>
        /// 接收 Python Server 的處理結果回調
        /// POST: /api/callback/processing-result
        /// </summary>
        [HttpPost("processing-result")]
        public async Task<IActionResult> ReceiveProcessingResult(
            [FromBody] ProcessingResultCallbackDto callbackData)
        {
            try
            {
                // 驗證請求
                if (string.IsNullOrWhiteSpace(callbackData?.QueueItemId))
                {
                    _logger.LogWarning("❌ 回調請求缺少 QueueItemId");
                    return BadRequest(new CallbackResponseDto
                    {
                        Success = false,
                        Message = "QueueItemId 為必需"
                    });
                }

                // 驗證狀態值
                var validStatus = new[] { "processing", "completed", "failed" };
                if (string.IsNullOrWhiteSpace(callbackData.Status) || !validStatus.Contains(callbackData.Status))
                {
                    _logger.LogWarning($"❌ 無效的狀態: {callbackData.Status}");
                    return BadRequest(new CallbackResponseDto
                    {
                        Success = false,
                        Message = "狀態必須是: processing, completed 或 failed",
                        QueueItemId = callbackData.QueueItemId
                    });
                }

                _logger.LogInformation($"📬 收到回調: QueueItemId={callbackData.QueueItemId}, Status={callbackData.Status}");

                // 查找隊列項目
                var queueItem = await _context.ProcessQueueItems
                    .FirstOrDefaultAsync(q => q.Id == callbackData.QueueItemId);

                if (queueItem == null)
                {
                    _logger.LogWarning($"❌ 隊列項目不存在: {callbackData.QueueItemId}");
                    return NotFound(new CallbackResponseDto
                    {
                        Success = false,
                        Message = "隊列項目不存在",
                        QueueItemId = callbackData.QueueItemId
                    });
                }

                // 根據狀態更新隊列項目
                _logger.LogInformation($"📝 更新狀態: {queueItem.Status} → {callbackData.Status}");

                switch (callbackData.Status)
                {
                    case "processing":
                        // 處理中 - 更新時間戳和進度
                        queueItem.Status = "processing";
                        if (queueItem.StartedAt == null)
                        {
                            queueItem.StartedAt = callbackData.CompletedAt ?? DateTime.Now;
                        }
                        _logger.LogInformation($"   ⏳ 處理進度: {callbackData.ProgressPercent}%");
                        break;

                    case "completed":
                        // 處理完畢 - 標記成功
                        queueItem.Status = "completed";
                        queueItem.IsSuccess = true;
                        queueItem.CompletedAt = callbackData.CompletedAt ?? DateTime.Now;
                        
                        _logger.LogInformation($"   ✅ 處理完畢，耗時: {callbackData.ProcessingDurationSeconds}秒");
                        
                        // 🔥 新增：在處理完成後自動收集和上傳所有輸出文件
                        await ProcessAndUploadOutputFilesAsync(queueItem, callbackData);
                        break;

                    case "failed":
                        // 處理失敗 - 標記失敗
                        queueItem.Status = "failed";
                        queueItem.IsSuccess = false;
                        queueItem.CompletedAt = callbackData.CompletedAt ?? DateTime.Now;
                        
                        if (!string.IsNullOrEmpty(callbackData.ErrorMessage))
                        {
                            _logger.LogWarning($"   ❌ 錯誤: {callbackData.ErrorMessage}");
                        }
                        break;
                }

                // 保存到資料庫
                _context.ProcessQueueItems.Update(queueItem);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"✅ 成功更新隊列項目: {callbackData.QueueItemId}");
                _logger.LogInformation($"   最終狀態: {queueItem.Status}, 成功: {queueItem.IsSuccess}");

                // 返回成功響應
                return Ok(new CallbackResponseDto
                {
                    Success = true,
                    Message = $"狀態已更新為: {callbackData.Status}",
                    QueueItemId = callbackData.QueueItemId,
                    Timestamp = DateTime.UtcNow
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ 處理回調時出錯");
                return StatusCode(500, new CallbackResponseDto
                {
                    Success = false,
                    Message = $"處理失敗: {ex.Message}",
                    QueueItemId = callbackData?.QueueItemId
                });
            }
        }

        /// <summary>
        /// 查詢隊列項目的處理結果
        /// GET: /api/callback/result/{queueItemId}
        /// </summary>
        [HttpGet("result/{queueItemId}")]
        public async Task<IActionResult> GetProcessingResult([FromRoute] string queueItemId)
        {
            try
            {
                var queueItem = await _context.ProcessQueueItems
                    .FirstOrDefaultAsync(q => q.Id == queueItemId);

                if (queueItem == null)
                {
                    return NotFound(new { error = "隊列項目不存在" });
                }

                var response = new
                {
                    queueItemId = queueItem.Id,
                    videoId = queueItem.VideoId,
                    status = queueItem.Status,
                    success = queueItem.IsSuccess,
                    createdAt = queueItem.CreatedAt,
                    startedAt = queueItem.StartedAt,
                    completedAt = queueItem.CompletedAt,
                    processingDurationMs = queueItem.CompletedAt.HasValue && queueItem.StartedAt.HasValue
                        ? (queueItem.CompletedAt.Value - queueItem.StartedAt.Value).TotalMilliseconds
                        : 0
                };

                return Ok(response);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ 查詢結果時出錯: {queueItemId}");
                return StatusCode(500, new { error = ex.Message });
            }
        }

        /// <summary>
        /// 健康檢查
        /// GET: /api/callback/health
        /// </summary>
        [HttpGet("health")]
        public IActionResult Health()
        {
            return Ok(new
            {
                status = "healthy",
                service = "CallbackReceiver",
                timestamp = DateTime.UtcNow
            });
        }

        /// <summary>
        /// 🔥 新增：處理和上傳輸出文件
        /// 從 Python 服務器的輸出目錄收集所有生成的文件並上傳到資料庫
        /// </summary>
        private async Task ProcessAndUploadOutputFilesAsync(
            ProcessQueueItem queueItem,
            ProcessingResultCallbackDto callbackData)
        {
            try
            {
                _logger.LogInformation($"📦 開始收集和上傳輸出文件: {queueItem.VideoId}");

                // 💡 從回調數據中提取輸出路徑
                // ResultData 結構預期：
                // {
                //   "steps": {
                //     "stabilization": { "status": "completed", "result": { "output": "..." } },
                //     "audio_analysis": { "status": "completed", "result": { ... } },
                //     ...
                //   },
                //   "audio_analysis": {
                //     "audio_crispness": 75.5,
                //     "good_shot": true
                //   },
                //   "outputPath": "\\10.1.1.101\TekSwing\videos\{videoId}\..."
                // }

                // 🔍 DEBUG: 打印完整的 ResultData 結構
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                _logger.LogInformation("🔍 DEBUG: ResultData 內容");
                _logger.LogInformation("════════════════════════════════════════════════════════════");
                
                if (callbackData?.ResultData == null)
                {
                    _logger.LogWarning($"⚠️ 回調數據中沒有 ResultData，跳過文件上傳");
                    return;
                }

                // 遞迴印出 ResultData 的所有鍵值對
                foreach (var kvp in callbackData.ResultData)
                {
                    _logger.LogInformation($"📌 Key: {kvp.Key}");
                    
                    if (kvp.Value is Dictionary<string, object> dictValue)
                    {
                        _logger.LogInformation($"   Type: Dictionary<string, object>");
                        foreach (var innerKvp in dictValue)
                        {
                            _logger.LogInformation($"     - {innerKvp.Key}: {innerKvp.Value?.GetType().Name ?? "null"} = {innerKvp.Value?.ToString() ?? "null"}");
                        }
                    }
                    else if (kvp.Value is Dictionary<string, Dictionary<string, object>> nestedDict)
                    {
                        _logger.LogInformation($"   Type: Dictionary<string, Dictionary<string, object>>");
                        foreach (var innerKvp in nestedDict)
                        {
                            _logger.LogInformation($"     - {innerKvp.Key}: {innerKvp.Value?.Count ?? 0} 項");
                            foreach (var deepKvp in innerKvp.Value)
                            {
                                _logger.LogInformation($"       • {deepKvp.Key}: {deepKvp.Value?.ToString() ?? "null"}");
                            }
                        }
                    }
                    else
                    {
                        _logger.LogInformation($"   Type: {kvp.Value?.GetType().Name ?? "null"}");
                        _logger.LogInformation($"   Value: {kvp.Value?.ToString() ?? "null"}");
                    }
                }
                
                _logger.LogInformation("════════════════════════════════════════════════════════════");

                var video = await _context.Videos.FirstOrDefaultAsync(v => v.Id == queueItem.VideoId);
                if (video == null)
                {
                    _logger.LogWarning($"❌ 找不到視頻記錄: {queueItem.VideoId}");
                    return;
                }

                var userId = video.UserId;
                var videoId = video.Id;

                // 🎯 解析 audio_crispness 和 good_shot
                _logger.LogInformation($"🔍 開始解析音頻分析數據...");
                
                // 從 ResultData 中提取音頻分析結果
                if (callbackData.ResultData.TryGetValue("audio_analysis", out var audioAnalysisObj))
                {
                    _logger.LogInformation($"   📌 找到 audio_analysis: {audioAnalysisObj?.GetType().Name ?? "null"}");
                    
                    try
                    {
                        // 支持 Dictionary 和 JsonElement 兩種類型
                        double? parsedCrispness = null;
                        bool? parsedGoodShot = null;
                        
                        if (audioAnalysisObj is Dictionary<string, object> audioAnalysis)
                        {
                            _logger.LogInformation($"   ✅ audio_analysis 是 Dictionary<string, object>，包含 {audioAnalysis.Count} 個鍵");
                            
                            // 解析 audio_crispness
                            if (audioAnalysis.TryGetValue("audio_crispness", out var crispnessObj))
                            {
                                _logger.LogInformation($"      📌 audio_crispness: {crispnessObj?.GetType().Name ?? "null"} = {crispnessObj?.ToString() ?? "null"}");
                                if (double.TryParse(crispnessObj?.ToString(), out var crispness))
                                {
                                    parsedCrispness = crispness;
                                    _logger.LogInformation($"      ✅ 解析成功: {crispness}");
                                }
                                else
                                {
                                    _logger.LogWarning($"      ❌ 無法將 {crispnessObj} 解析為 double");
                                }
                            }
                            else
                            {
                                _logger.LogWarning($"      ⚠️ audio_analysis 中找不到 audio_crispness");
                            }

                            // 解析 good_shot
                            if (audioAnalysis.TryGetValue("good_shot", out var goodShotObj))
                            {
                                _logger.LogInformation($"      📌 good_shot: {goodShotObj?.GetType().Name ?? "null"} = {goodShotObj?.ToString() ?? "null"}");
                                if (bool.TryParse(goodShotObj?.ToString(), out var goodShot))
                                {
                                    parsedGoodShot = goodShot;
                                    _logger.LogInformation($"      ✅ 解析成功: {goodShot}");
                                }
                                else
                                {
                                    _logger.LogWarning($"      ❌ 無法將 {goodShotObj} 解析為 bool");
                                }
                            }
                            else
                            {
                                _logger.LogWarning($"      ⚠️ audio_analysis 中找不到 good_shot");
                            }
                        }
                        else if (audioAnalysisObj is JsonElement jsonElement)
                        {
                            _logger.LogInformation($"   ✅ audio_analysis 是 JsonElement，嘗試解析...");
                            
                            // 解析 audio_crispness 從 JsonElement
                            if (jsonElement.TryGetProperty("audio_crispness", out var crispnessElem))
                            {
                                _logger.LogInformation($"      📌 audio_crispness: {crispnessElem.ValueKind} = {crispnessElem}");
                                try
                                {
                                    parsedCrispness = crispnessElem.GetDouble();
                                    _logger.LogInformation($"      ✅ 解析成功: {parsedCrispness}");
                                }
                                catch (Exception parseEx)
                                {
                                    _logger.LogWarning($"      ❌ 無法將 {crispnessElem} 解析為 double: {parseEx.Message}");
                                }
                            }
                            else
                            {
                                _logger.LogWarning($"      ⚠️ audio_analysis 中找不到 audio_crispness");
                            }

                            // 解析 good_shot 從 JsonElement
                            if (jsonElement.TryGetProperty("good_shot", out var goodShotElem))
                            {
                                _logger.LogInformation($"      📌 good_shot: {goodShotElem.ValueKind} = {goodShotElem}");
                                try
                                {
                                    parsedGoodShot = goodShotElem.GetBoolean();
                                    _logger.LogInformation($"      ✅ 解析成功: {parsedGoodShot}");
                                }
                                catch (Exception parseEx)
                                {
                                    _logger.LogWarning($"      ❌ 無法將 {goodShotElem} 解析為 bool: {parseEx.Message}");
                                }
                            }
                            else
                            {
                                _logger.LogWarning($"      ⚠️ audio_analysis 中找不到 good_shot");
                            }
                        }
                        else
                        {
                            _logger.LogWarning($"   ⚠️ audio_analysis 不是 Dictionary 或 JsonElement，而是 {audioAnalysisObj?.GetType().Name ?? "null"}");
                        }
                        
                        // 將解析的值分配給 video 對象
                        if (parsedCrispness.HasValue)
                        {
                            video.AudioCrispness = parsedCrispness;
                        }
                        if (parsedGoodShot.HasValue)
                        {
                            video.GoodShot = parsedGoodShot;
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning($"⚠️ 解析音頻分析數據失敗: {ex.Message}");
                    }
                }
                else
                {
                    _logger.LogWarning($"   ⚠️ ResultData 中找不到 audio_analysis");
                }

                // 保存解析結果到資料庫
                if (video.AudioCrispness.HasValue || video.GoodShot.HasValue)
                {
                    _context.Videos.Update(video);
                    await _context.SaveChangesAsync();
                    _logger.LogInformation($"✅ 已保存視頻元數據: AudioCrispness={video.AudioCrispness}, GoodShot={video.GoodShot}");
                }

                // 獲取視頻的檔案目錄
                var videoFiles = await _context.Files
                    .Where(f => f.VideoId == queueItem.VideoId)
                    .Where(f => f.Type == "clip")
                    .FirstOrDefaultAsync();

                var inputDir = "";
                if (videoFiles != null && !string.IsNullOrEmpty(videoFiles.FilePath))
                {
                    // 從檔案路徑提取目錄
                    inputDir = Path.GetDirectoryName(videoFiles.FilePath) ?? "";
                    _logger.LogInformation($"📁 提取的檔案目錄: {inputDir} (來自: {videoFiles.FilePath})");
                }
                else
                {
                    _logger.LogWarning($"⚠️  無法找到視頻檔案，使用默認空目錄");
                }

                // 構造輸出文件路徑
                // 預期路徑類似：\\10.1.1.101\TekSwing\videos\{videoId}\phase\traj_out\clip_stabilized_pose_phase_traj.mp4
                var outputDir = inputDir + "\\clip_stabilized_pose_phase_traj.mp4";

                if (string.IsNullOrEmpty(outputDir) || !System.IO.File.Exists(outputDir))
                {
                    _logger.LogWarning($"⚠️ 輸出文件不存在或路徑無效: {outputDir}");
                    return;
                }

                // � 上傳單一文件
                try
                {
                    var fileType = "pose_phase_trajectory_video";
                    var filePath = outputDir;

                    // 讀取文件內容
                    using (var fileStream = System.IO.File.OpenRead(filePath))
                    {
                        // 轉換為 IFormFile 格式（用於上傳服務）
                        var fileName = Path.GetFileName(filePath);
                        var formFile = new FormFile(
                            fileStream,
                            0,
                            fileStream.Length,
                            fileType,
                            fileName)
                        {
                            Headers = new HeaderDictionary(),
                            ContentType = GetContentType(filePath)
                        };

                        // 上傳文件
                        var (success, fileRecord, error) = await _uploadService.UploadFileAsync(
                            userId,
                            videoId,
                            fileType,
                            formFile,
                            sourceLocalFilePath: filePath);

                        if (success && fileRecord != null)
                        {
                            // 保存文件記錄到資料庫
                            _context.Files.Add(fileRecord);
                            await _context.SaveChangesAsync();
                            _logger.LogInformation($"✅ 文件上傳成功: {fileType} ({fileName}) - {fileRecord.FileSize} bytes");
                        }
                        else
                        {
                            _logger.LogWarning($"❌ 文件上傳失敗: {fileType} - {error}");
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, $"❌ 上傳文件出錯: {outputDir}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ 處理和上傳輸出文件時出錯");
            }
        }

        /// <summary>
        /// 根據文件副檔名判斷 MIME 類型
        /// </summary>
        private string GetContentType(string filePath)
        {
            var extension = Path.GetExtension(filePath).ToLower();
            return extension switch
            {
                ".mp4" => "video/mp4",
                ".csv" => "text/csv",
                ".json" => "application/json",
                ".log" => "text/plain",
                ".mov" => "video/quicktime",
                ".avi" => "video/x-msvideo",
                ".mkv" => "video/x-matroska",
                _ => "application/octet-stream"
            };
        }
    }
}
