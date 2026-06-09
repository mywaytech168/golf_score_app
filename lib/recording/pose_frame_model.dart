import 'pose_result.dart';

class PoseFrameModel {
  final int frame;
  final double timeSec;
  final int poseUpdateId;
  final List<LandmarkData> landmarks;

  PoseFrameModel({
    required this.frame,
    required this.timeSec,
    required this.poseUpdateId,
    required this.landmarks,
  });

  /// 從 MediaPipe NativePoseResult 建立（歸一化座標 → 像素座標反算）
  factory PoseFrameModel.fromNative({
    required int frame,
    required double timeSec,
    required int poseUpdateId,
    required NativePoseResult pose,
    required double imgWidth,
    required double imgHeight,
    bool isFrontCamera = false,
  }) {
    final lms = List<LandmarkData>.generate(33, (i) {
      if (i >= pose.landmarks.length) return LandmarkData.empty();
      final lm = pose.landmarks[i];
      return LandmarkData(
        xNorm:      lm.x,
        yNorm:      lm.y,
        z:          lm.z,
        visibility: lm.visibility,
        xPx:        lm.x * imgWidth,
        yPx:        lm.y * imgHeight,
      );
    });
    return PoseFrameModel(
      frame: frame, timeSec: timeSec, poseUpdateId: poseUpdateId, landmarks: lms,
    );
  }

  factory PoseFrameModel.empty({
    required int frame,
    required double timeSec,
    int poseUpdateId = 0,
  }) =>
      PoseFrameModel(
        frame: frame,
        timeSec: timeSec,
        poseUpdateId: poseUpdateId,
        landmarks: List.generate(33, (_) => LandmarkData.empty()),
      );

  List<dynamic> toCsvRow() {
    final row = <dynamic>[frame, timeSec.toStringAsFixed(6), poseUpdateId];
    for (final lm in landmarks) {
      row.addAll([
        lm.xNorm.isNaN     ? 0.0 : lm.xNorm,
        lm.yNorm.isNaN     ? 0.0 : lm.yNorm,
        lm.z.isNaN         ? 0.0 : lm.z,
        lm.visibility,
        lm.xPx.isNaN       ? 0.0 : lm.xPx,
        lm.yPx.isNaN       ? 0.0 : lm.yPx,
      ]);
    }
    return row;
  }
}

class LandmarkData {
  final double xNorm, yNorm, z, visibility, xPx, yPx;
  const LandmarkData({
    required this.xNorm,
    required this.yNorm,
    required this.z,
    required this.visibility,
    required this.xPx,
    required this.yPx,
  });
  factory LandmarkData.empty() => const LandmarkData(
    xNorm: double.nan, yNorm: double.nan, z: double.nan,
    visibility: 0.0, xPx: double.nan, yPx: double.nan,
  );
}
