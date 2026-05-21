using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using UploadServer.DTOs;

namespace UploadServer.Services;

/// <summary>
/// 高爾夫揮桿錯誤分析服務。
/// 接收 Flutter 上傳的骨架序列，執行與 Python predict_pose_error.py 相同的
/// 預處理流程，再透過 ONNX Runtime 執行 PoseTCN 推論。
/// </summary>
public sealed class GolfSwingAnalyzerService : IDisposable
{
    // ── 模型常數 ─────────────────────────────────────────────────
    private const int LandmarkCount = 33;
    private const int RawFeatures = 4;           // x, y, z, visibility
    private const int VelFeatures = 3;            // vx, vy, vz (xyz diff)
    private const int FeatPerLandmark = RawFeatures + VelFeatures; // 7

    private const float HighConfidence = 0.85f;
    private const float Acceptable = 0.75f;
    private const float Suspect = 0.60f;

    // 標籤順序必須與 Python dataset.py ERROR_LABELS 一致
    private static readonly string[] Labels =
    [
        "early_release_casting",
        "impact",
        "over_the_top",
        "spine_angle",
        "weight_shift"
    ];

    // ── 執行期欄位 ────────────────────────────────────────────────
    private readonly InferenceSession _session;
    private readonly int _targetFrames;
    private readonly int _inputDim;
    private readonly ILogger<GolfSwingAnalyzerService> _logger;

    public GolfSwingAnalyzerService(
        IConfiguration config,
        ILogger<GolfSwingAnalyzerService> logger)
    {
        _logger = logger;

        var modelPath = config["GolfSwing:ModelPath"]
            ?? Path.Combine(AppContext.BaseDirectory, "Assets", "Models", "pose_error_tcn.onnx");

        if (!File.Exists(modelPath))
            throw new FileNotFoundException($"ONNX 模型不存在: {modelPath}");

        _session = new InferenceSession(modelPath);

        // 從 ONNX metadata 讀取實際輸入維度
        var inputMeta = _session.InputMetadata["pose_sequence"];
        var dims = inputMeta.Dimensions;

        // Bug fix: dims 可能為 -1（dynamic axis），必須驗證為正整數
        if (dims.Length < 3 || dims[1] <= 0 || dims[2] <= 0)
            throw new InvalidOperationException(
                $"ONNX 模型輸入維度無效（expected [batch, frames, features]，got [{dims[0]}, {dims[1]}, {dims[2]}]）。" +
                $"請確認 export_onnx.py 的 dynamic_axes 只設定 batch 維度。");

        _targetFrames = dims[1];
        _inputDim = dims[2];

        // Bug fix: 驗證模型 inputDim 與預處理產生的 featuresPerFrame 一致
        int expectedDim = LandmarkCount * FeatPerLandmark;
        if (_inputDim != expectedDim)
            throw new InvalidOperationException(
                $"ONNX 模型 input_dim={_inputDim}，但預處理產生 {expectedDim}（{LandmarkCount} landmarks × {FeatPerLandmark} features）。" +
                $"請確認訓練時使用的特徵數量，並更新 FeatPerLandmark 常數。");

        _logger.LogInformation(
            "GolfSwingAnalyzer 初始化完成 | 模型: {Path} | 輸入: [1, {Frames}, {Dim}]",
            modelPath, _targetFrames, _inputDim);
    }

    // ── 公開介面 ──────────────────────────────────────────────────

    public GolfSwingAnalysisResponse Analyze(GolfSwingAnalysisRequest request)
    {
        if (request.Frames.Count < 2)
            throw new ArgumentException("至少需要 2 幀骨架資料");

        // Step 1: 組成 [N, 33, 4] 原始序列
        var seq = BuildRawSequence(request.Frames);

        // Step 2: 線性插值補缺失值 (NaN)
        FillMissing(seq);

        // Step 3: 髖部中心正規化 + 尺度正規化
        NormalizePose(seq);

        // Step 4: 重採樣到 targetFrames（預設 128）
        var resampled = ResampleSequence(seq, _targetFrames);

        // Step 5: 加入速度特徵 → [targetFrames, 33, 7]
        var withVel = AddVelocityFeatures(resampled);

        // Step 6: 攤平為 [targetFrames, inputDim] 並執行推論
        var probs = RunInference(withVel);

        // Step 7: 信心度決策
        return ApplyDecisionPolicy(probs);
    }

    // ── 預處理：步驟 1 ─────────────────────────────────────────────

    private static float[,,] BuildRawSequence(List<PoseFrameDto> frames)
    {
        int n = frames.Count;
        var seq = new float[n, LandmarkCount, RawFeatures];

        // 預設填 NaN，代表缺失
        for (int f = 0; f < n; f++)
            for (int l = 0; l < LandmarkCount; l++)
                for (int feat = 0; feat < RawFeatures; feat++)
                    seq[f, l, feat] = float.NaN;

        for (int f = 0; f < n; f++)
        {
            foreach (var lm in frames[f].Landmarks)
            {
                if (lm.Id < 0 || lm.Id >= LandmarkCount) continue;
                seq[f, lm.Id, 0] = lm.X;
                seq[f, lm.Id, 1] = lm.Y;
                seq[f, lm.Id, 2] = lm.Z;
                seq[f, lm.Id, 3] = lm.Visibility;
            }
        }
        return seq;
    }

    // ── 預處理：步驟 2  FillMissing ────────────────────────────────

    private static void FillMissing(float[,,] seq)
    {
        int n = seq.GetLength(0);
        for (int l = 0; l < LandmarkCount; l++)
        {
            for (int feat = 0; feat < RawFeatures; feat++)
            {
                var validIdx = new List<int>(n);
                var validVal = new List<float>(n);

                for (int f = 0; f < n; f++)
                {
                    if (!float.IsNaN(seq[f, l, feat]))
                    {
                        validIdx.Add(f);
                        validVal.Add(seq[f, l, feat]);
                    }
                }

                if (validIdx.Count == n) continue;  // 全部有效，跳過

                if (validIdx.Count == 0)
                {
                    for (int f = 0; f < n; f++) seq[f, l, feat] = 0f;
                    continue;
                }

                for (int f = 0; f < n; f++)
                {
                    if (!float.IsNaN(seq[f, l, feat])) continue;
                    seq[f, l, feat] = LinearInterp(f, validIdx, validVal);
                }
            }
        }
    }

    private static float LinearInterp(int x, List<int> xs, List<float> ys)
    {
        if (x <= xs[0]) return ys[0];
        if (x >= xs[^1]) return ys[^1];

        int hi = xs.BinarySearch(x);
        if (hi < 0) hi = ~hi;
        int lo = hi - 1;
        float t = (x - xs[lo]) / (float)(xs[hi] - xs[lo]);
        return ys[lo] + t * (ys[hi] - ys[lo]);
    }

    // ── 預處理：步驟 3  NormalizePose ──────────────────────────────

    private static void NormalizePose(float[,,] seq)
    {
        int n = seq.GetLength(0);
        var hipCx = new float[n];
        var hipCy = new float[n];
        var hipCz = new float[n];
        var scales = new float[n];

        for (int f = 0; f < n; f++)
        {
            // 左髖=23, 右髖=24, 左肩=11, 右肩=12
            float lhx = seq[f, 23, 0], lhy = seq[f, 23, 1], lhz = seq[f, 23, 2];
            float rhx = seq[f, 24, 0], rhy = seq[f, 24, 1], rhz = seq[f, 24, 2];
            float lsx = seq[f, 11, 0], lsy = seq[f, 11, 1];
            float rsx = seq[f, 12, 0], rsy = seq[f, 12, 1];

            hipCx[f] = (lhx + rhx) * 0.5f;
            hipCy[f] = (lhy + rhy) * 0.5f;
            hipCz[f] = (lhz + rhz) * 0.5f;

            float sw = MathF.Sqrt((lsx - rsx) * (lsx - rsx) + (lsy - rsy) * (lsy - rsy));
            float hw = MathF.Sqrt((lhx - rhx) * (lhx - rhx) + (lhy - rhy) * (lhy - rhy));
            scales[f] = MathF.Max(sw, hw);
        }

        // fallback scale = 有效 scale 的中位數
        var validScales = scales
            .Where(s => float.IsFinite(s) && s > 1e-6f)
            .OrderBy(s => s)
            .ToArray();
        // Bug fix: 與 Python np.median 對齊（偶數取兩中間值平均）
        float fallback = 1.0f;
        if (validScales.Length > 0)
        {
            int mid = validScales.Length / 2;
            fallback = validScales.Length % 2 == 0
                ? (validScales[mid - 1] + validScales[mid]) / 2f
                : validScales[mid];
        }

        for (int f = 0; f < n; f++)
        {
            float sc = (float.IsFinite(scales[f]) && scales[f] > 1e-6f) ? scales[f] : fallback;

            for (int l = 0; l < LandmarkCount; l++)
            {
                seq[f, l, 0] = Math.Clamp((seq[f, l, 0] - hipCx[f]) / sc, -5f, 5f);
                seq[f, l, 1] = Math.Clamp((seq[f, l, 1] - hipCy[f]) / sc, -5f, 5f);
                seq[f, l, 2] = Math.Clamp((seq[f, l, 2] - hipCz[f]) / sc, -5f, 5f);
                seq[f, l, 3] = Math.Clamp(seq[f, l, 3], 0f, 1f);
            }
        }
    }

    // ── 預處理：步驟 4  ResampleSequence ───────────────────────────

    private static float[,,] ResampleSequence(float[,,] seq, int targetFrames)
    {
        int n = seq.GetLength(0);
        if (n == targetFrames) return seq;

        var result = new float[targetFrames, LandmarkCount, RawFeatures];
        for (int l = 0; l < LandmarkCount; l++)
        {
            for (int feat = 0; feat < RawFeatures; feat++)
            {
                for (int tf = 0; tf < targetFrames; tf++)
                {
                    // np.linspace(0,1,targetFrames) 對應到 np.linspace(0,1,n)
                    float t = (float)tf / (targetFrames - 1) * (n - 1);
                    int lo = (int)t;
                    int hi = Math.Min(lo + 1, n - 1);
                    float frac = t - lo;
                    result[tf, l, feat] = seq[lo, l, feat] + frac * (seq[hi, l, feat] - seq[lo, l, feat]);
                }
            }
        }
        return result;
    }

    // ── 預處理：步驟 5  AddVelocityFeatures ────────────────────────

    private static float[,,] AddVelocityFeatures(float[,,] seq)
    {
        int n = seq.GetLength(0);
        var result = new float[n, LandmarkCount, FeatPerLandmark];

        for (int f = 0; f < n; f++)
        {
            for (int l = 0; l < LandmarkCount; l++)
            {
                // 複製原始 4 個特徵
                for (int feat = 0; feat < RawFeatures; feat++)
                    result[f, l, feat] = seq[f, l, feat];

                // xyz 速度 (幀差分)，第 0 幀速度為 0
                for (int d = 0; d < 3; d++)
                {
                    result[f, l, RawFeatures + d] = f == 0
                        ? 0f
                        : seq[f, l, d] - seq[f - 1, l, d];
                }
            }
        }
        return result;
    }

    // ── 推論 ──────────────────────────────────────────────────────

    private float[] RunInference(float[,,] seq)
    {
        int frames = seq.GetLength(0);

        // 攤平為 [1, frames, landmarkCount * featPerLandmark]
        // 佈局：frame × (landmark × feature)，與 Python reshape(frames, -1) 相同
        // Bug fix: stride 必須用 LandmarkCount * FeatPerLandmark（與 _inputDim 相同，已在建構子驗證）
        int stride = LandmarkCount * FeatPerLandmark;  // == _inputDim
        var flat = new float[frames * stride];
        for (int f = 0; f < frames; f++)
            for (int l = 0; l < LandmarkCount; l++)
                for (int feat = 0; feat < FeatPerLandmark; feat++)
                    flat[f * stride + l * FeatPerLandmark + feat] = seq[f, l, feat];

        var tensor = new DenseTensor<float>(flat, [1, frames, _inputDim]);
        var inputs = new[] { NamedOnnxValue.CreateFromTensor("pose_sequence", tensor) };

        using var results = _session.Run(inputs);
        return [.. results.First().AsEnumerable<float>()];
    }

    // ── 決策邏輯（與 Python select_errors 完全一致）───────────────

    private static GolfSwingAnalysisResponse ApplyDecisionPolicy(float[] probs)
    {
        var scores = new Dictionary<string, float>(Labels.Length);
        for (int i = 0; i < Labels.Length && i < probs.Length; i++)
            scores[Labels[i]] = probs[i];

        var ordered = scores.OrderByDescending(kv => kv.Value).ToList();
        var official = new List<string>();
        var review = new List<string>();
        var suspect = new List<string>();

        for (int rank = 0; rank < ordered.Count; rank++)
        {
            var label = ordered[rank].Key;
            var score = ordered[rank].Value;

            if (rank == 0)
            {
                // 第一名：>= 0.75 才算 official；0.75-0.85 同時加入 review
                if (score >= Acceptable)
                {
                    official.Add(label);
                    if (score < HighConfidence) review.Add(label);
                }
                else if (score >= Suspect)
                {
                    suspect.Add(label);
                }
                continue;
            }

            // 第二名以後：規則與第一名相同（多標籤門檻 >= 0.75）
            if (score >= Acceptable)
            {
                official.Add(label);
                if (score < HighConfidence) review.Add(label);
            }
            else if (score >= Suspect)
            {
                suspect.Add(label);
            }
        }

        var bands = scores.ToDictionary(kv => kv.Key, kv => ConfidenceBand(kv.Value));
        return new GolfSwingAnalysisResponse(official, review, suspect, scores, bands);
    }

    private static string ConfidenceBand(float score) => score switch
    {
        >= HighConfidence => "high_confidence",
        >= Acceptable     => "acceptable_review",
        >= Suspect        => "suspect_not_official",
        _                 => "low_ignore"
    };

    public void Dispose() => _session.Dispose();
}
