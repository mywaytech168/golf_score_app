// Configuration enums for recording and pose detection

/// 視頻錄製配置選項
enum VideoQuality {
  low(480, 1500000, '低 (480p)'),
  standard(720, 3000000, '標準 (720p)'),
  hd(1080, 6000000, '高 (1080p)');

  final int height;
  final int bitrate;
  final String displayName;

  const VideoQuality(this.height, this.bitrate, this.displayName);
}

/// 幀率選項
enum FrameRate {
  fps24(24, '24fps'),
  fps30(30, '30fps'),
  fps60(60, '60fps');

  final int value;
  final String displayName;

  const FrameRate(this.value, this.displayName);
}

/// 分析圖像寬度選項（姿態檢測）
enum AnalysisWidth {
  low(320, '低精度 (320px)'),
  medium(480, '中精度 (480px)'),
  high(640, '高精度 (640px)'),
  veryHigh(768, '超高精度 (768px)');

  final int pixels;
  final String displayName;

  const AnalysisWidth(this.pixels, this.displayName);
}

/// 統合配置管理
/// 
/// 提供視頻錄製和圖像分析的配置選項
/// 適用於 camerawesome 2.0.1 及 Google MLKit 集成
class RecordingConfig {
  VideoQuality videoQuality;
  FrameRate frameRate;
  AnalysisWidth analysisWidth;
  bool enableAudio;

  RecordingConfig({
    this.videoQuality = VideoQuality.hd,
    this.frameRate = FrameRate.fps30,
    this.analysisWidth = AnalysisWidth.high,
    this.enableAudio = true,
  });

  /// 獲取視頻錄製選項
  /// 
  /// camerawesome 2.0.1 簡化了視頻 API，只保留 enableAudio
  Map<String, dynamic> getVideoOptions() {
    return {
      'enableAudio': enableAudio,
      'bitrate': videoQuality.bitrate,
      'fps': frameRate.value,
      'height': videoQuality.height,
    };
  }

  /// 獲取圖像分析配置
  /// 用於 MLKit 姿態檢測
  Map<String, dynamic> getAnalysisConfig() {
    return {
      'width': analysisWidth.pixels,
      'maxFramesPerSecond': frameRate.value,
      'autoStart': true,
    };
  }
}
