import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// 將 camerawesome 的 AnalysisImage 轉換為 Google ML Kit 的 InputImage
/// 支援 Android (NV21) 與 iOS (BGRA8888) 兩種格式
extension AnalysisImageToInputImage on AnalysisImage {
  InputImage? toInputImage() {
    return when(
      nv21: (img) => InputImage.fromBytes(
        bytes: img.bytes,
        metadata: InputImageMetadata(
          size: img.size,
          rotation: _toMlKitRotation(img.rotation),
          format: InputImageFormat.nv21,
          bytesPerRow: img.width,
        ),
      ),
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
