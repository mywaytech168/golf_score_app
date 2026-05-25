import 'package:camerawesome/camerawesome_plugin.dart';
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
  standard('4:3', 3 / 4),   // 直式 4:3（寬/高 = 3/4）
  wide('16:9',    9 / 16),   // 直式 16:9（寬/高 = 9/16）
  full('全螢幕',   null);

  /// 顯示標籤
  final String label;

  /// 寬高比（Flutter AspectRatio = width/height）；null 表示全螢幕
  final double? ratio;

  const AspectRatioMode(this.label, this.ratio);

  /// 對應 CameraAwesome 的原生比例設定（傳給 SensorConfig，影響實際錄製的 mp4 尺寸）
  /// 全螢幕使用 ratio_16_9（最接近現代手機螢幕比例，錄製 9:16 直式影片）
  CameraAspectRatios get cameraRatio {
    switch (this) {
      case AspectRatioMode.square:
        return CameraAspectRatios.ratio_1_1;
      case AspectRatioMode.standard:
        return CameraAspectRatios.ratio_4_3;
      case AspectRatioMode.wide:
      case AspectRatioMode.full:
        return CameraAspectRatios.ratio_16_9;
    }
  }
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
