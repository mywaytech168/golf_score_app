import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Lightweight MoveNet single-pose estimator.
///
/// Designed for low-overhead overlay usage in preview/playback; throttling
/// should be handled by the caller.
class PoseEstimatorService {
  PoseEstimatorService._();

  static final PoseEstimatorService instance = PoseEstimatorService._();

  static const _modelAsset = 'assets/models/movenet_singlepose_lightning.tflite';
  static const _inputSize = 192; // MoveNet lightning expects 192x192
  static const _numKeypoints = 17;

  Interpreter? _interpreter;

  Future<void> ensureLoaded() async {
    if (_interpreter != null) return;
    final options = InterpreterOptions()
      ..threads = 2
      ..useNnApiForAndroid = true;
    _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
  }

  /// Estimate pose from a camera YUV frame.
  Future<PoseResult?> estimateFromCameraImage({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int uvRowStride,
    required int uvPixelStride,
  }) async {
    await ensureLoaded();
    final rgbImage = _yuv420ToImage(
      y: y,
      u: u,
      v: v,
      width: width,
      height: height,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
    );
    if (rgbImage == null) return null;
    return _runOnImage(rgbImage, originalSize: Size(width.toDouble(), height.toDouble()));
  }

  /// Estimate pose from an RGB(A) image (e.g., thumbnail bytes).
  Future<PoseResult?> estimateFromBytes(Uint8List bytes) async {
    await ensureLoaded();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return _runOnImage(decoded, originalSize: Size(decoded.width.toDouble(), decoded.height.toDouble()));
  }

  PoseResult? _runOnImage(img.Image image, {required Size originalSize}) {
    final inputImage = img.copyResize(image, width: _inputSize, height: _inputSize);

    final Uint8List input = Uint8List(_inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = inputImage.getPixel(x, y);
        input[idx++] = pixel.r.toInt();
        input[idx++] = pixel.g.toInt();
        input[idx++] = pixel.b.toInt();
      }
    }

    // MoveNet output shape: [1,1,17,3] -> [y, x, score]
    final output = List.generate(
      1,
      (_) => List.generate(
        1,
        (_) => List.generate(_numKeypoints, (_) => List<double>.filled(3, 0)),
      ),
    );

    final inputAsList = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final base = (y * _inputSize + x) * 3;
            return [
              input[base],
              input[base + 1],
              input[base + 2],
            ];
          },
        ),
      ),
    );

    _interpreter!.run(inputAsList, output);

    final keypoints = <PoseKeypoint>[];
    final raw = output[0][0];
    for (int i = 0; i < _numKeypoints; i++) {
      final kp = raw[i];
      final y = kp[0].toDouble(); // normalized
      final x = kp[1].toDouble(); // normalized
      final score = kp[2].toDouble();
      keypoints.add(PoseKeypoint(x: x, y: y, score: score));
    }

    return PoseResult(
      keypoints: keypoints,
      inputSize: originalSize,
    );
  }

  img.Image? _yuv420ToImage({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final image = img.Image(width: width, height: height);
    int uvIndex = 0;
    for (int yIndex = 0; yIndex < height; yIndex++) {
      final uvRow = uvRowStride * (yIndex >> 1);
      for (int xIndex = 0; xIndex < width; xIndex++) {
        final yp = y[yIndex * width + xIndex] & 0xFF;
        uvIndex = uvRow + (xIndex >> 1) * uvPixelStride;
        final up = u[uvIndex] & 0xFF;
        final vp = v[uvIndex] & 0xFF;

        final r = (yp + 1.403 * (vp - 128)).clamp(0, 255).toInt();
        final g = (yp - 0.344 * (up - 128) - 0.714 * (vp - 128)).clamp(0, 255).toInt();
        final b = (yp + 1.770 * (up - 128)).clamp(0, 255).toInt();

        image.setPixelRgba(xIndex, yIndex, r, g, b, 255);
      }
    }
    return image;
  }
}

class PoseKeypoint {
  final double x; // normalized [0,1]
  final double y; // normalized [0,1]
  final double score;

  const PoseKeypoint({
    required this.x,
    required this.y,
    required this.score,
  });
}

class PoseResult {
  final List<PoseKeypoint> keypoints;
  final Size inputSize;

  const PoseResult({
    required this.keypoints,
    required this.inputSize,
  });
}
