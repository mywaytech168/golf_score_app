import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../recording/pose_csv_writer.dart';
import '../recording/pose_detector_service.dart';
import '../recording/pose_frame_model.dart';

class VideoAnalysisService {
  static const _audioChannel = MethodChannel('audio_extractor_channel');
  static const _frameIntervalMs = 67; // ~15fps

  Future<VideoAnalysisResult> analyze({
    required String videoPath,
    required String sessionDir,
    required int durationSeconds,
    void Function(double progress, String label)? onProgress,
  }) async {
    final csvPath = p.join(sessionDir, 'pose_landmarks.csv');
    final audioPath = p.join(sessionDir, 'audio.pcm');
    final poseService = PoseDetectorService(mode: PoseDetectionMode.single);

    try {
      await _analyzePose(
        videoPath: videoPath,
        csvPath: csvPath,
        durationSeconds: durationSeconds,
        poseService: poseService,
        onProgress: (prog) => onProgress?.call(
          prog * 0.75,
          '分析骨架中... ${(prog * 100).round()}%',
        ),
      );

      onProgress?.call(0.75, '提取音訊中...');
      bool hasAudio = false;
      try {
        hasAudio = await _extractAudio(videoPath: videoPath, audioPath: audioPath);
      } catch (e) {
        debugPrint('[VideoAnalysis] audio extraction failed: $e');
      }

      onProgress?.call(1.0, '完成');
      return VideoAnalysisResult(
        csvPath: csvPath,
        audioPath: hasAudio ? audioPath : '',
      );
    } finally {
      poseService.dispose();
    }
  }

  Future<void> _analyzePose({
    required String videoPath,
    required String csvPath,
    required int durationSeconds,
    required PoseDetectorService poseService,
    void Function(double)? onProgress,
  }) async {
    final writer = PoseCsvWriter(csvPath);
    final tmpDir = (await getTemporaryDirectory()).path;
    final totalMs = durationSeconds * 1000;
    final totalSteps = (totalMs / _frameIntervalMs).ceil().clamp(1, 99999);
    var frameIndex = 0;
    double imgW = 720, imgH = 1280;

    for (var ms = 0; ms < totalMs; ms += _frameIntervalMs) {
      String? thumbPath;
      try {
        // maxWidth: 720 對齊 Python 原版的 FAST_POSE_LONG_SIDE=720
        // 縮小輸入尺寸可加速 ML Kit 推理，同時減少磁碟 I/O
        thumbPath = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: tmpDir,
          imageFormat: ImageFormat.JPEG,
          timeMs: ms,
          quality: 85,
          maxWidth: 720,
        );

        if (thumbPath != null && await File(thumbPath).exists()) {
          if (frameIndex == 0) {
            // 第一幀從 JPEG header 解析尺寸
            final bytes = await File(thumbPath).readAsBytes();
            final dims = _parseJpegSize(bytes);
            imgW = dims.$1.toDouble();
            imgH = dims.$2.toDouble();
            debugPrint('[VideoAnalysis] video frame size: ${imgW}x$imgH');
          }

          final poses = await poseService.detect(InputImage.fromFilePath(thumbPath));
          if (poses.isNotEmpty) {
            writer.addFrame(PoseFrameModel.fromPose(
              frame: frameIndex,
              timeSec: ms / 1000.0,
              pose: poses.first,
              imgWidth: imgW,
              imgHeight: imgH,
            ));
          } else {
            writer.addFrame(PoseFrameModel.empty(frame: frameIndex, timeSec: ms / 1000.0));
          }
        }
      } catch (e) {
        debugPrint('[VideoAnalysis] frame $frameIndex error: $e');
        writer.addFrame(PoseFrameModel.empty(frame: frameIndex, timeSec: ms / 1000.0));
      } finally {
        if (thumbPath != null) {
          try { await File(thumbPath).delete(); } catch (_) {}
        }
      }

      frameIndex++;
      onProgress?.call(frameIndex / totalSteps);
    }

    await writer.flush();
    debugPrint('[VideoAnalysis] pose done: $frameIndex frames → $csvPath');
  }

  // Parses JPEG SOF0/SOF1/SOF2 marker to extract image width and height.
  static (int, int) _parseJpegSize(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return (720, 1280);
    }
    var i = 2;
    while (i + 3 < bytes.length) {
      while (i < bytes.length && bytes[i] != 0xFF) { i++; }
      if (i + 1 >= bytes.length) break;
      final marker = bytes[i + 1];
      if (marker == 0xD9 || marker == 0xDA) break;
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        if (i + 8 < bytes.length) {
          final h = (bytes[i + 5] << 8) | bytes[i + 6];
          final w = (bytes[i + 7] << 8) | bytes[i + 8];
          if (w > 0 && h > 0) return (w, h);
        }
      }
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      if (segLen < 2) { i += 2; continue; }
      i += 2 + segLen;
    }
    return (720, 1280);
  }

  Future<bool> _extractAudio({
    required String videoPath,
    required String audioPath,
  }) async {
    final result = await _audioChannel.invokeMethod<Map>('extractAudio', {
      'videoPath': videoPath,
    });
    if (result == null) return false;

    final wavPath = result['path'] as String?;
    if (wavPath == null) return false;

    final wavFile = File(wavPath);
    if (!await wavFile.exists()) return false;

    // WAV layout: 44-byte header + int16 LE PCM samples
    final wavBytes = await wavFile.readAsBytes();
    try {
      await wavFile.delete();
    } catch (_) {}

    if (wavBytes.length <= 44) return false;

    // Convert int16 LE → float32 LE (matching live recording format)
    final pcmData = wavBytes.sublist(44);
    final sampleCount = pcmData.length ~/ 2;
    final src = pcmData.buffer.asByteData();
    final dst = ByteData(sampleCount * 4);
    for (var i = 0; i < sampleCount; i++) {
      final s = src.getInt16(i * 2, Endian.little) / 32768.0;
      dst.setFloat32(i * 4, s.clamp(-1.0, 1.0), Endian.little);
    }

    await File(audioPath).writeAsBytes(dst.buffer.asUint8List());
    debugPrint('[VideoAnalysis] audio done: $sampleCount samples → $audioPath');
    return true;
  }
}

class VideoAnalysisResult {
  final String csvPath;
  final String audioPath;
  const VideoAnalysisResult({required this.csvPath, required this.audioPath});
}
