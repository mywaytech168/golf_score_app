import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../recording/pose_csv_writer.dart';
import '../recording/pose_detector_service.dart';
import '../recording/pose_frame_model.dart';

class VideoAnalysisService {
  static const _audioChannel = MethodChannel('audio_extractor_channel');
  static const _frameExtractorChannel = MethodChannel('com.example.golf_score_app/frame_extractor');
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
    final totalMs = durationSeconds * 1000;
    final totalSteps = (totalMs / _frameIntervalMs).ceil().clamp(1, 99999);
    var frameIndex = 0;
    double imgW = 720, imgH = 1280;

    // 使用 Native 直接提取 RGB (無 JPEG 開銷)
    // 預期: VideoThumbnail 50ms → Native 10-15ms (5x 快速!)
    for (var ms = 0; ms < totalMs; ms += _frameIntervalMs) {
      try {
        // 1️⃣ 呼叫 Kotlin VideoFrameExtractor 直接解碼為 RGB
        final result = await _frameExtractorChannel.invokeMethod(
          'extractFrameRgb',
          {
            'videoPath': videoPath,
            'timeMs': ms,
            'maxWidth': 720,
          },
        ) as Map<dynamic, dynamic>?;

        if (result != null) {
          final width = result['width'] as int;
          final height = result['height'] as int;
          final pixelBytes = result['pixels'] as Uint8List;

          if (frameIndex == 0) {
            imgW = width.toDouble();
            imgH = height.toDouble();
            debugPrint('[VideoAnalysis] video frame size: ${imgW}x$imgH');
          }

          // 2️⃣ 將 ARGB byte array 轉為 InputImage (無 JPEG 解碼)
          final inputImage = InputImage.fromBytes(
            bytes: pixelBytes,
            metadata: InputImageMetadata(
              size: Size(imgW, imgH),
              rotation: InputImageRotation.rotation0deg,
              format: InputImageFormat.bgra8888,
              bytesPerRow: width * 4,
            ),
          );

          // 3️⃣ ML Kit 推理
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

    // 直接复制 WAV 文件（改为 .wav 扩展名）
    try {
      await wavFile.copy(audioPath);
      debugPrint('[VideoAnalysis] audio done: $audioPath');
      return true;
    } catch (e) {
      debugPrint('[VideoAnalysis] audio copy failed: $e');
      return false;
    } finally {
      try { await wavFile.delete(); } catch (_) {}
    }
  }
}

class VideoAnalysisResult {
  final String csvPath;
  final String audioPath;
  const VideoAnalysisResult({required this.csvPath, required this.audioPath});
}
