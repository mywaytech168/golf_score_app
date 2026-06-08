import 'package:camerawesome/pigeon.dart';

/// 影片畫質（對應 camerawesome VideoRecordingQuality）
enum VideoQuality {
  hd(VideoRecordingQuality.hd,   '720p'),
  fhd(VideoRecordingQuality.fhd, '1080p');

  final VideoRecordingQuality recordingQuality;
  final String label;
  const VideoQuality(this.recordingQuality, this.label);
}

/// 幀率選項（30fps / 60fps）
enum FrameRate {
  fps30(30, '30fps'),
  fps60(60, '60fps');

  final int value;
  final String label;
  const FrameRate(this.value, this.label);
}

/// 錄製設定（16:9 直式，輸出 1920×1080 / 1280×720）
class RecordingConfig {
  VideoQuality quality;
  FrameRate fps;

  RecordingConfig({
    this.quality = VideoQuality.hd,
    this.fps = FrameRate.fps30,
  });

  /// 給 CameraAwesomeBuilder 的 key，設定變更時強制重建相機
  String get cameraKey => '${quality.name}_${fps.value}';

  /// 轉為 camerawesome VideoOptions
  VideoOptions toVideoOptions() => VideoOptions(
        enableAudio: true,
        quality: quality.recordingQuality,
        ios: CupertinoVideoOptions(fps: fps.value),
      );
}
