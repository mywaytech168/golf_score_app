/// MediaPipe PoseLandmarker 結果（取代 google_mlkit_pose_detection 的 Pose）
///
/// 33 個地標索引與 ML Kit PoseLandmarkType 完全一致：
///   11=leftShoulder, 12=rightShoulder, 13=leftElbow, 14=rightElbow,
///   15=leftWrist,    16=rightWrist,    23=leftHip,   24=rightHip,
///   25=leftKnee,     26=rightKnee,     27=leftAnkle, 28=rightAnkle, ...
class NativePoseLandmark {
  final double x;           // 歸一化 0-1（顯示座標系，已含旋轉）
  final double y;           // 歸一化 0-1
  final double z;           // 深度（相對單位）
  final double visibility;  // 0-1

  const NativePoseLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  factory NativePoseLandmark.fromMap(Map<Object?, Object?> m) =>
      NativePoseLandmark(
        x:          (m['x'] as num?)?.toDouble() ?? 0.0,
        y:          (m['y'] as num?)?.toDouble() ?? 0.0,
        z:          (m['z'] as num?)?.toDouble() ?? 0.0,
        visibility: (m['vis'] as num?)?.toDouble() ?? 0.0,
      );

  // 像素座標（供 CSV writer 及速度計算使用）
  double px(double imageWidth)  => x * imageWidth;
  double py(double imageHeight) => y * imageHeight;
}

class NativePoseResult {
  final List<NativePoseLandmark> landmarks; // 33 個，可能為空（未偵測到人體）
  final int timestampMs;

  const NativePoseResult({
    required this.landmarks,
    required this.timestampMs,
  });

  bool get isEmpty => landmarks.isEmpty;

  NativePoseLandmark? landmark(int index) =>
      index < landmarks.length ? landmarks[index] : null;

  NativePoseLandmark? get rightWrist  => landmark(16);
  NativePoseLandmark? get leftWrist   => landmark(15);
  NativePoseLandmark? get rightHip    => landmark(24);
  NativePoseLandmark? get leftHip     => landmark(23);
  NativePoseLandmark? get rightShoulder => landmark(12);
  NativePoseLandmark? get leftShoulder  => landmark(11);

  factory NativePoseResult.empty(int timestampMs) =>
      NativePoseResult(landmarks: const [], timestampMs: timestampMs);

  factory NativePoseResult.fromMap(Map<Object?, Object?> m) {
    final raw = m['landmarks'] as List<Object?>? ?? [];
    final lms = raw
        .whereType<Map<Object?, Object?>>()
        .map(NativePoseLandmark.fromMap)
        .toList();
    return NativePoseResult(
      landmarks:   lms,
      timestampMs: (m['ts'] as num?)?.toInt() ?? 0,
    );
  }
}
