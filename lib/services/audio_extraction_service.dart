import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 音频提取服务：从视频文件中提取音频为 WAV
/// 
/// 使用现有的 Android audio_extractor_channel 提取 WAV，直接保存（不转换）
class AudioExtractionService {
  static const String _tag = '[AudioExtraction]';
  
  // 使用项目中现有的 audio_extractor_channel
  static const platform = MethodChannel('audio_extractor_channel');

  /// 从视频中提取音频
  /// 
  /// 返回提取后的音频样本数，失败返回 0
  static Future<int> extractAudioFromVideo({
    required String videoPath,
    required String outputWavPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    debugPrint('$_tag 开始从视频提取音频: $videoPath');
    onProgress?.call(0.1, '检查视频文件...');

    // 验证源文件
    final sourceFile = File(videoPath);
    if (!await sourceFile.exists()) {
      debugPrint('$_tag ❌ 视频文件不存在: $videoPath');
      return 0;
    }

    try {
      // 调用现有的 audio_extractor_channel
      onProgress?.call(0.2, '调用 MediaCodec 提取音频...');
      
      final result = await platform.invokeMethod<Map>(
        'extractAudio',
        {'videoPath': videoPath},
      );

      if (result == null) {
        debugPrint('$_tag ❌ 提取失败: 返回 null');
        return 0;
      }

      final wavPath = result['path'] as String?;
      final sampleRate = result['sampleRate'] as int?;
      final channelCount = result['channels'] as int?;

      if (wavPath == null || sampleRate == null) {
        debugPrint('$_tag ❌ 提取结果不完整: wavPath=$wavPath, sampleRate=$sampleRate');
        return 0;
      }

      debugPrint('$_tag ✅ WAV 提取成功: $wavPath (${sampleRate}Hz, $channelCount channels)');
      onProgress?.call(0.5, '保存 WAV 文件...');

      // 直接复制 WAV 文件
      final samplesCount = await _copyWavFile(
        wavPath: wavPath,
        outputWavPath: outputWavPath,
        onProgress: onProgress,
      );

      return samplesCount;
    } on PlatformException catch (e) {
      debugPrint('$_tag ❌ Platform Exception: ${e.message}');
      return 0;
    } catch (e) {
      debugPrint('$_tag ❌ 异常: $e');
      return 0;
    }
  }

  /// 直接复制 WAV 文件（不进行转换）
  static Future<int> _copyWavFile({
    required String wavPath,
    required String outputWavPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        debugPrint('$_tag ❌ WAV 文件不存在: $wavPath');
        return 0;
      }

      onProgress?.call(0.7, '复制 WAV 文件...');
      
      // 直接复制 WAV 文件
      await wavFile.copy(outputWavPath);
      
      // 计算样本数
      final wavBytes = await File(outputWavPath).readAsBytes();
      if (wavBytes.length < 44) {
        debugPrint('$_tag ❌ WAV 文件太小: ${wavBytes.length} 字节');
        return 0;
      }

      // 查找 data chunk 计算样本数
      int dataSize = 0;
      for (int i = 36; i < wavBytes.length - 8; i++) {
        if (wavBytes[i] == 100 && wavBytes[i + 1] == 97 &&
            wavBytes[i + 2] == 116 && wavBytes[i + 3] == 97) {
          dataSize = wavBytes[i + 4] | (wavBytes[i + 5] << 8) |
              (wavBytes[i + 6] << 16) | (wavBytes[i + 7] << 24);
          break;
        }
      }

      final sampleCount = dataSize ~/ 2;  // 16-bit PCM: 每个样本 2 字节

      debugPrint('$_tag ✅ WAV 保存成功: $outputWavPath (${wavBytes.length} 字节, $sampleCount 样本)');

      // 清理临时 WAV 文件
      try {
        await wavFile.delete();
        debugPrint('$_tag 🗑️ 清理临时 WAV');
      } catch (_) {}

      onProgress?.call(1.0, '完成');
      return sampleCount;
    } catch (e) {
      debugPrint('$_tag ❌ 复制异常: $e');
      return 0;
    }
  }

  /// 检查视频是否包含音频轨道
  /// 
  /// 使用 FFprobe 检查媒体信息
  static Future<bool> hasAudioTrack(String videoPath) async {
    try {
      // ffprobe -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 input.mp4
      final result = await Process.run('ffprobe', [
        '-select_streams',
        'a:0',
        '-show_entries',
        'stream=codec_type',
        '-of',
        'csv=p=0',
        videoPath,
      ]);

      final output = result.stdout.toString().trim();
      return output.contains('audio');
    } catch (e) {
      debugPrint('$_tag FFprobe 检查失败: $e');
      return false;
    }
  }

  /// 清理临时音频文件
  static Future<void> cleanupAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('$_tag 🗑️ 清理临时音频: $audioPath');
      }
    } catch (e) {
      debugPrint('$_tag 清理失败: $e');
    }
  }
}
