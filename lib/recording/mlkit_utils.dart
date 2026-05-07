import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Extension to convert AnalysisImage to InputImage for MLKit
/// Compatible with camerawesome 2.5.0 and google_mlkit_commons 0.8.1
extension AnalysisImageToInputImage on AnalysisImage {
  /// Converts AnalysisImage from camerawesome to InputImage for Google MLKit
  InputImage toInputImage() {
    // camerawesome 2.5.0 AnalysisImage has direct properties
    final metadata = InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      format: InputImageFormat.nv21,
      bytesPerRow: width,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: metadata,
    );
  }
}


