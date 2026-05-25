import 'package:camerawesome/pigeon.dart';

/// 影片畫質（對應 camerawesome VideoRecordingQuality）
enum VideoQuality {
  sd(VideoRecordingQuality.sd,   '480p'),
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

/// 預覽／錄製裁切比例
enum AspectRatioMode {
  square('1:1',   1 / 1),
  standard('4:3', 4 / 3),
  wide('16:9',    16 / 9),
  full('全螢幕',   null);

  /// 顯示標籤
  final String label;

  /// 寬高比；null 表示全螢幕（不做裁切）
  final double? ratio;

  const AspectRatioMode(this.label, this.ratio);
}

/// 錄製設定
class RecordingConfig {
  VideoQuality quality;
  FrameRate fps;
  AspectRatioMode aspectRatio;

  RecordingConfig({
    this.quality = VideoQuality.hd,
    this.fps = FrameRate.fps30,
    this.aspectRatio = AspectRatioMode.full,
  });

  /// 給 CameraAwesomeBuilder 的 key，設定變更時強制重建相機
  String get cameraKey => '${quality.name}_${fps.value}_${aspectRatio.name}';

  /// 轉為 camerawesome VideoOptions
  VideoOptions toVideoOptions() => VideoOptions(
        enableAudio: true,
        quality: quality.recordingQuality,
        ios: CupertinoVideoOptions(fps: fps.value),
      );
}
