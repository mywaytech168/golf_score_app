namespace UploadServer.DTOs;

/// <summary>單一關鍵點 (ML Kit / MediaPipe BlazePose 33點格式)</summary>
public record PoseLandmarkDto(
    int Id,           // 0-32，對應 BlazePose landmark id
    float X,          // 正規化 x 座標 [0,1]（x_pixel / imageWidth）
    float Y,          // 正規化 y 座標 [0,1]（y_pixel / imageHeight）
    float Z,          // 相對深度（髖部為基準）
    float Visibility  // 可見度 [0,1]
);

/// <summary>單幀資料</summary>
public record PoseFrameDto(
    int FrameIndex,
    List<PoseLandmarkDto> Landmarks  // 最多 33 個點
);

/// <summary>Flutter 上傳的揮桿骨架序列</summary>
public record GolfSwingAnalysisRequest(
    List<PoseFrameDto> Frames  // 全部幀，建議 30-180 幀
);

/// <summary>推論回傳結果</summary>
public record GolfSwingAnalysisResponse(
    List<string> OfficialErrors,   // 正式錯誤 (score >= 0.75)
    List<string> ReviewErrors,     // 需人工複核 (0.75-0.85)
    List<string> SuspectErrors,    // 疑似錯誤 (0.60-0.75)
    Dictionary<string, float> Scores,  // 各標籤原始機率
    Dictionary<string, string> Bands   // 各標籤信心帶
);
