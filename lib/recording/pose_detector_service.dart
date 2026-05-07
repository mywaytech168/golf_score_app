import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseDetectorService {
  PoseDetector? _detector;

  Future<List<Pose>> detect(InputImage image) async {
    _detector ??= PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream, // 即時串流用
        model: PoseDetectionModel.base,
      ),
    );
    return await _detector!.processImage(image);
  }

  void dispose() => _detector?.close();
}
