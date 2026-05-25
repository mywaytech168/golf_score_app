import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseFrameModel {
  final int frame;
  final double timeSec;
  final int poseUpdateId;  // ✅ 追踪骨架是否實際更新
  final List<LandmarkData> landmarks;

  PoseFrameModel({
    required this.frame,
    required this.timeSec,
    required this.poseUpdateId,
    required this.landmarks,
  });

  factory PoseFrameModel.fromPose({
    required int frame,
    required double timeSec,
    required int poseUpdateId,
    required Pose pose,
    required double imgWidth,
    required double imgHeight,
    bool isFrontCamera = false,
  }) {
    final lms = List<LandmarkData>.generate(33, (i) {
      final type = PoseLandmarkType.values[i];
      final lm = pose.landmarks[type];
      if (lm == null) return LandmarkData.empty();
      // 前鏡頭預覽水平鏡像，X 座標翻轉使 CSV 與視覺畫面一致
      final rawX  = isFrontCamera ? (imgWidth - lm.x) : lm.x;
      return LandmarkData(
        xNorm: rawX / imgWidth,
        yNorm: lm.y / imgHeight,
        z: lm.z,
        visibility: lm.likelihood,
        xPx: rawX,
        yPx: lm.y,
      );
    });
    return PoseFrameModel(
      frame: frame,
      timeSec: timeSec,
      poseUpdateId: poseUpdateId,
      landmarks: lms,
    );
  }

  factory PoseFrameModel.empty({
    required int frame,
    required double timeSec,
    int poseUpdateId = 0,
  }) {
    return PoseFrameModel(
      frame: frame,
      timeSec: timeSec,
      poseUpdateId: poseUpdateId,
      landmarks: List.generate(33, (_) => LandmarkData.empty()),
    );
  }

  List<dynamic> toCsvRow() {
    final row = <dynamic>[frame, timeSec.toStringAsFixed(6), poseUpdateId];
    for (final lm in landmarks) {
      row.addAll([
        lm.xNorm.isNaN ? 0.0 : lm.xNorm,  // ✅ 用 0.0 代替空字符串，保持 CSV 完整性
        lm.yNorm.isNaN ? 0.0 : lm.yNorm,
        lm.z.isNaN ? 0.0 : lm.z,
        lm.visibility,
        lm.xPx.isNaN ? 0.0 : lm.xPx,
        lm.yPx.isNaN ? 0.0 : lm.yPx,
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
    xNorm: double.nan,
    yNorm: double.nan,
    z: double.nan,
    visibility: 0.0,
    xPx: double.nan,
    yPx: double.nan,
  );
}
