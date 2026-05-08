import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 骨架偵測服務
///
/// [stream] 模式（預設）：適合即時錄影，ML Kit 利用相鄰幀時序做追蹤平滑。
/// [singleImage] 模式：適合影片匯入批次處理，每幀獨立偵測，
///   避免 stream 模式因幀間隔不規律（67ms 取幀）而產生錯誤的時序預測。
class PoseDetectorService {
  PoseDetector? _detector;
  final PoseDetectionMode mode;

  PoseDetectorService({this.mode = PoseDetectionMode.stream});

  Future<List<Pose>> detect(InputImage image) async {
    _detector ??= PoseDetector(
      options: PoseDetectorOptions(
        mode: mode,
        model: PoseDetectionModel.base,
      ),
    );
    return await _detector!.processImage(image);
  }

  void dispose() => _detector?.close();
}
