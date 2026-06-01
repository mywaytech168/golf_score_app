import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class V3AnalysisService {
  static final V3AnalysisService _instance = V3AnalysisService._internal();
  factory V3AnalysisService() => _instance;
  static V3AnalysisService get instance => _instance;

  V3AnalysisService._internal();

  /// 抽取各揮桿階段的關鍵禎圖片，回傳 JPEG bytes 陣列（不做 base64 編碼）。
  Future<List<Uint8List>> extractKeyframeBytes({
    required String clipPath,
    required Map<String, double> phaseTimestamps,
  }) async {
    final List<Uint8List> keyframes = [];
    final tempDir = await getTemporaryDirectory();

    for (final phase in phaseTimestamps.entries) {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: clipPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: (phase.value * 1000).toInt(),
        quality: 90,
      );

      if (thumbnailPath != null) {
        keyframes.add(await File(thumbnailPath).readAsBytes());
      }
    }

    return keyframes;
  }
}
