import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
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
    final poseService = PoseDetectorService();

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
    final totalMs = durationSeconds * 1000;
    final totalSteps = (totalMs / _frameIntervalMs).ceil().clamp(1, 99999);
    var frameIndex = 0;
    double imgW = 720, imgH = 1280;

    for (var ms = 0; ms < totalMs; ms += _frameIntervalMs) {
      try {
        // 取得 JPEG bytes（不寫磁碟）
        final jpegBytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: ms,
          quality: 85,
        );

        if (jpegBytes != null && jpegBytes.isNotEmpty) {
          // 解碼 JPEG → raw RGBA（dart:ui，在記憶體中完成）
          final codec = await ui.instantiateImageCodec(jpegBytes);
          final frame = await codec.getNextFrame();
          final uiImage = frame.image;

          if (frameIndex == 0) {
            imgW = uiImage.width.toDouble();
            imgH = uiImage.height.toDouble();
            debugPrint('[VideoAnalysis] video frame size: ${imgW}x$imgH');
          }

          final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
          uiImage.dispose();

          if (byteData != null) {
            final inputImage = InputImage.fromBytes(
              bytes: byteData.buffer.asUint8List(),
              metadata: InputImageMetadata(
                size: Size(imgW, imgH),
                rotation: InputImageRotation.rotation0deg,
                format: InputImageFormat.bgra8888,
                bytesPerRow: imgW.toInt() * 4,
              ),
            );
            final poses = await poseService.detect(inputImage);
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
          } else {
            writer.addFrame(PoseFrameModel.empty(frame: frameIndex, timeSec: ms / 1000.0));
          }
        }
      } catch (e) {
        debugPrint('[VideoAnalysis] frame $frameIndex error: $e');
        writer.addFrame(PoseFrameModel.empty(frame: frameIndex, timeSec: ms / 1000.0));
      }

      frameIndex++;
      onProgress?.call(frameIndex / totalSteps);
    }

    await writer.flush();
    debugPrint('[VideoAnalysis] pose done: $frameIndex frames → $csvPath');
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
