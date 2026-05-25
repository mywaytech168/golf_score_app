import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// 將 camerawesome 的 AnalysisImage 轉換為 Google ML Kit 的 InputImage
/// 支援 Android (NV21) 與 iOS (BGRA8888) 兩種格式
extension AnalysisImageToInputImage on AnalysisImage {
  InputImage? toInputImage() {
    return when(
      nv21: (img) {
        // ImageUtil.yuv_420_888toNv21 copies the raw Y-plane buffer including
        // CameraX row-stride padding.  If we tell ML Kit bytesPerRow = img.width
        // but the actual stride is larger, every row is misaligned and ML Kit
        // returns 0 poses.  Use the real Y-plane rowStride from the planes list.
        final int bytesPerRow = img.planes.isNotEmpty
            ? img.planes[0].bytesPerRow
            : img.width;
        final int expectedCompact = img.width * img.height * 3 ~/ 2;
        debugPrint(
          '[MLKit] nv21 ${img.width}x${img.height} '
          'bytes=${img.bytes.length} compact=$expectedCompact '
          'bytesPerRow=$bytesPerRow rot=${img.rotation}',
        );
        return InputImage.fromBytes(
          bytes: img.bytes,
          metadata: InputImageMetadata(
            size: img.size,
            rotation: _toMlKitRotation(img.rotation),
            format: InputImageFormat.nv21,
            bytesPerRow: bytesPerRow,
          ),
        );
      },
      bgra8888: (img) => InputImage.fromBytes(
        bytes: img.bytes,
        metadata: InputImageMetadata(
          size: img.size,
          rotation: _toMlKitRotation(img.rotation),
          format: InputImageFormat.bgra8888,
          bytesPerRow: img.width * 4,
        ),
      ),
    );
  }
}

InputImageRotation _toMlKitRotation(InputAnalysisImageRotation r) {
  return switch (r) {
    InputAnalysisImageRotation.rotation0deg => InputImageRotation.rotation0deg,
    InputAnalysisImageRotation.rotation90deg => InputImageRotation.rotation90deg,
    InputAnalysisImageRotation.rotation180deg => InputImageRotation.rotation180deg,
    InputAnalysisImageRotation.rotation270deg => InputImageRotation.rotation270deg,
  };
}
