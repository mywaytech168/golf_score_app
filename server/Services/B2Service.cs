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

        // ── AI Coach clip 路徑規則 ──────────────────────────────────────
        public static string AiCoachClipKey(string analysisId) =>
            $"ai_coach/{analysisId}/clip.mp4";

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

        /// <summary>產生 clip 下載的 pre-signed GET URL（Worker 下載用）</summary>
        public string GenerateClipDownloadUrl(string b2Path, int expiryMinutes = 10)
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
    }
}
