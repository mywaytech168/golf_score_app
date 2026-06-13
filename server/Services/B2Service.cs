using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;

namespace UploadServer.Services
{
    /// <summary>
    /// Backblaze B2 S3-compatible API 封裝
    /// </summary>
    public class B2Service
    {
        private readonly AmazonS3Client _s3;
        private readonly string _bucketName;
        private readonly ILogger<B2Service> _logger;

        public B2Service(IConfiguration config, ILogger<B2Service> logger)
        {
            _logger = logger;

            var keyId      = config["B2:KeyId"]         ?? throw new InvalidOperationException("B2:KeyId 未設定");
            var appKey     = config["B2:ApplicationKey"] ?? throw new InvalidOperationException("B2:ApplicationKey 未設定");
            var endpoint   = config["B2:Endpoint"]       ?? throw new InvalidOperationException("B2:Endpoint 未設定");
            _bucketName    = config["B2:BucketName"]     ?? throw new InvalidOperationException("B2:BucketName 未設定");

            var credentials = new BasicAWSCredentials(keyId, appKey);
            var s3Config = new AmazonS3Config
            {
                ServiceURL            = endpoint,
                ForcePathStyle        = true,   // B2 需要 path-style
                SignatureVersion      = "4",
                UseHttp               = false,
            };

            _s3 = new AmazonS3Client(credentials, s3Config);
        }

        /// <summary>產生 pre-signed PUT URL（讓 Flutter 直傳 B2）</summary>
        public string GenerateUploadUrl(string objectKey, int expiryMinutes = 15)
        {
            var request = new GetPreSignedUrlRequest
            {
                BucketName = _bucketName,
                Key        = objectKey,
                Verb       = HttpVerb.PUT,
                Expires    = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "application/zip",
            };

            var url = _s3.GetPreSignedURL(request);
            _logger.LogInformation("產生 B2 PUT URL: {Key}", objectKey);
            return url;
        }

        /// <summary>產生 pre-signed GET URL（讓 Flutter 下載）</summary>
        public string GenerateDownloadUrl(string objectKey, int expiryMinutes = 5)
        {
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = objectKey,
                Verb        = HttpVerb.GET,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ResponseHeaderOverrides =
                {
                    ContentDisposition = $"attachment; filename=\"session.zip\"",
                },
            };

            return _s3.GetPreSignedURL(request);
        }

        // ── AI Coach 路徑規則 ────────────────────────────────────────────
        public static string AiCoachClipKey(string analysisId) =>
            $"ai_coach/{analysisId}/clip.mp4";

        public static string AiCoachCsvKey(string analysisId) =>
            $"ai_coach/{analysisId}/pose_landmarks.csv";

        public static string AiCoachAudioKey(string analysisId) =>
            $"ai_coach/{analysisId}/audio.wav";

        public static string AiCoachKeyframeKey(string analysisId, int index) =>
            $"ai_coach/{analysisId}/keyframe_{index}.jpg";

        /// <summary>產生 clip 上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateClipUploadUrl(string analysisId, int expiryMinutes = 20)
        {
            var key = AiCoachClipKey(analysisId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "video/mp4",
            };
            _logger.LogInformation("產生 clip PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生 CSV 上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateCsvUploadUrl(string analysisId, int expiryMinutes = 20)
        {
            var key = AiCoachCsvKey(analysisId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "text/csv",
            };
            _logger.LogInformation("產生 CSV PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生單一 keyframe JPEG 上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateKeyframeUploadUrl(string analysisId, int index, int expiryMinutes = 20)
        {
            var key = AiCoachKeyframeKey(analysisId, index);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "image/jpeg",
            };
            _logger.LogInformation("產生 keyframe[{Index}] PUT URL: {Key}", index, key);
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生 audio.wav 上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateAudioUploadUrl(string analysisId, int expiryMinutes = 20)
        {
            var key = AiCoachAudioKey(analysisId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "audio/wav",
            };
            _logger.LogInformation("產生 audio PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生物件下載的 pre-signed GET URL（Worker 下載用）</summary>
        public string GenerateDownloadUrlForKey(string b2Path, int expiryMinutes = 10)
        {
            var request = new GetPreSignedUrlRequest
            {
                BucketName = _bucketName,
                Key        = b2Path,
                Verb       = HttpVerb.GET,
                Expires    = DateTime.UtcNow.AddMinutes(expiryMinutes),
            };
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生 clip 下載的 pre-signed GET URL（Worker 下載用）</summary>
        public string GenerateClipDownloadUrl(string b2Path, int expiryMinutes = 10) =>
            GenerateDownloadUrlForKey(b2Path, expiryMinutes);

        /// <summary>刪除 B2 物件（過期清理用）</summary>
        public async Task DeleteObjectAsync(string objectKey)
        {
            try
            {
                await _s3.DeleteObjectAsync(_bucketName, objectKey);
                _logger.LogInformation("B2 物件已刪除: {Key}", objectKey);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "B2 物件刪除失敗: {Key}", objectKey);
            }
        }

        // ── 球軌跡路徑規則 ───────────────────────────────────────────────
        public static string BallTrajectoryClipKey(string analysisId) =>
            $"ball_trajectory/{analysisId}/clip.mp4";

        /// <summary>產生球軌跡 clip 上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateBallTrajectoryClipUploadUrl(string analysisId, int expiryMinutes = 20)
        {
            var key = BallTrajectoryClipKey(analysisId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "video/mp4",
            };
            _logger.LogInformation("產生球軌跡 clip PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        // ── 訓練資料集（上傳獎勵）路徑規則 ──────────────────────────────
        public static string DatasetVideoKey(string uploadId) =>
            $"dataset/{uploadId}/clip.mp4";

        public static string DatasetCsvKey(string uploadId) =>
            $"dataset/{uploadId}/pose_landmarks.csv";

        /// <summary>產生資料集影片上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateDatasetVideoUploadUrl(string uploadId, int expiryMinutes = 30)
        {
            var key = DatasetVideoKey(uploadId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "video/mp4",
            };
            _logger.LogInformation("產生資料集影片 PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生資料集 CSV 上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateDatasetCsvUploadUrl(string uploadId, int expiryMinutes = 30)
        {
            var key = DatasetCsvKey(uploadId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "text/csv",
            };
            _logger.LogInformation("產生資料集 CSV PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        public static string DatasetMetaKey(string uploadId) =>
            $"dataset/{uploadId}/meta.json";

        /// <summary>產生資料集診斷 meta.json 上傳的 pre-signed PUT URL（偵測 log/錨點/即時擊球等）</summary>
        public string GenerateDatasetMetaUploadUrl(string uploadId, int expiryMinutes = 30)
        {
            var key = DatasetMetaKey(uploadId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "application/json",
            };
            _logger.LogInformation("產生資料集 meta PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        public static string AiCoachMetaKey(string analysisId) =>
            $"ai_coach/{analysisId}/meta.json";

        /// <summary>產生 AI 分析診斷 meta.json 上傳的 pre-signed PUT URL</summary>
        public string GenerateMetaUploadUrl(string analysisId, int expiryMinutes = 20)
        {
            var key = AiCoachMetaKey(analysisId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "application/json",
            };
            _logger.LogInformation("產生 AI 分析 meta PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        // ── 問題回饋圖片路徑規則 ────────────────────────────────────────
        public static string FeedbackImageKey(string imageId) =>
            $"feedback_images/{imageId}.jpg";

        /// <summary>產生回饋圖片上傳的 pre-signed PUT URL（Flutter 直傳用）</summary>
        public string GenerateFeedbackImageUploadUrl(string imageId, int expiryMinutes = 10)
        {
            var key = FeedbackImageKey(imageId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName  = _bucketName,
                Key         = key,
                Verb        = HttpVerb.PUT,
                Expires     = DateTime.UtcNow.AddMinutes(expiryMinutes),
                ContentType = "image/jpeg",
            };
            _logger.LogInformation("產生回饋圖片 PUT URL: {Key}", key);
            return _s3.GetPreSignedURL(request);
        }

        /// <summary>產生回饋圖片下載的 pre-signed GET URL（管理員查看用）</summary>
        public string GenerateFeedbackImageDownloadUrl(string imageId, int expiryMinutes = 30)
        {
            var key = FeedbackImageKey(imageId);
            var request = new GetPreSignedUrlRequest
            {
                BucketName = _bucketName,
                Key        = key,
                Verb       = HttpVerb.GET,
                Expires    = DateTime.UtcNow.AddMinutes(expiryMinutes),
            };
            return _s3.GetPreSignedURL(request);
        }
    }
}
