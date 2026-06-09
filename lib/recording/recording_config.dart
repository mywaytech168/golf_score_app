// ── 長寬比 ────────────────────────────────────────────────────────────────────

enum RecordingAspectRatio {
  r16x9('16:9'),
  r4x3 ('4:3');

  final String label;
  const RecordingAspectRatio(this.label);
}

// ── 畫質 ──────────────────────────────────────────────────────────────────────

enum VideoQuality {
  sd ('SD',  '480p'),
  hd ('HD',  '720p'),
  fhd('FHD', '1080p');

  final String label;
  final String resolution;
  const VideoQuality(this.label, this.resolution);

  String get nativeQuality => switch (this) {
    VideoQuality.fhd => 'fhd',
    _                => 'hd',
  };
}

// ── 幀率 ──────────────────────────────────────────────────────────────────────

enum FrameRate {
  fps30(30, '30fps'),
  fps60(60, '60fps');

  final int value;
  final String label;
  const FrameRate(this.value, this.label);
}

// ── 錄製設定 ──────────────────────────────────────────────────────────────────

class RecordingConfig {
  VideoQuality         quality;
  FrameRate            fps;
  RecordingAspectRatio aspectRatio;
  bool                 enableAudio;

  RecordingConfig({
    this.quality     = VideoQuality.fhd,
    this.fps         = FrameRate.fps30,
    this.aspectRatio = RecordingAspectRatio.r16x9,
    this.enableAudio = true,
  });

  (int width, int height) get targetSize {
    switch (aspectRatio) {
      case RecordingAspectRatio.r16x9:
        return switch (quality) {
          VideoQuality.fhd => (1080, 1920),
          VideoQuality.hd  => (720,  1280),
          VideoQuality.sd  => (480,  854),
        };
      case RecordingAspectRatio.r4x3:
        return switch (quality) {
          VideoQuality.fhd => (1080, 1440),
          VideoQuality.hd  => (720,  960),
          VideoQuality.sd  => (480,  640),
        };
    }
  }

  String get aspectRatioMode {
    final q = quality.name;
    final a = aspectRatio == RecordingAspectRatio.r16x9 ? '16x9' : '4x3';
    return '${a}_$q';
  }

  String get overlayAsset {
    return quality == VideoQuality.fhd
        ? 'assets/overlays/Group 1080x1920_0.png'
        : 'assets/overlays/Group 720x1280_0.png';
  }
}
