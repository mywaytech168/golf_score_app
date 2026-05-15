import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 骨架偵測服務
///
/// [single] 模式：適合影片匯入批次處理，每幀獨立偵測，
///   不做時序追蹤。解決離散幀提取時 stream 模式的誤追蹤問題。
/// [stream] 模式（棄用）：原本用於即時錄影（Camera Stream），
///   會進行跨幀追蹤，但對 MediaMetadataRetriever 離散提取不適合。
class PoseDetectorService {
  PoseDetector? _detector;
  final PoseDetectionMode mode;

  PoseDetectorService({this.mode = PoseDetectionMode.single});

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
