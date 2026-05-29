import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class V3AnalysisService {
  static final V3AnalysisService _instance = V3AnalysisService._internal();
  factory V3AnalysisService() => _instance;
  static V3AnalysisService get instance => _instance;

  V3AnalysisService._internal();

  Future<List<String>> extractKeyframes({
    required String clipPath,
    required Map<String, double> phaseTimestamps,
  }) async {
    final List<String> keyframes = [];
    final tempDir = await getTemporaryDirectory();

    for (final phase in phaseTimestamps.entries) {
      final timestamp = phase.value;
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: clipPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: (timestamp * 1000).toInt(),
        quality: 90,
      );

      if (thumbnailPath != null) {
        final bytes = await File(thumbnailPath).readAsBytes();
        final base64Image = base64Encode(bytes);
        keyframes.add(base64Image);
      }
    }

    return keyframes;
  }
}
