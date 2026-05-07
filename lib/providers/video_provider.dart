import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

/// 視頻播放狀態
enum VideoPlaybackState {
  uninitialized, // 未初始化
  initialized,   // 已初始化
  playing,       // 播放中
  paused,        // 已暫停
  stopped,       // 已停止
  error,         // 錯誤
}

/// 視頻信息
class VideoInfo {
  final String path;
  final Duration? duration;
  final Size? videoSize;
  final int? frameRate;
  final String? imuCsvPath; // 關聯的 IMU 數據

  VideoInfo({
    required this.path,
    this.duration,
    this.videoSize,
    this.frameRate,
    this.imuCsvPath,
  });

  /// 視頻時間戳（秒）
  double get durationSeconds => duration?.inMilliseconds.toDouble() ?? 0.0;
}

/// 視頻提供者
/// 
/// 管理視頻播放狀態、進度、元數據等
class VideoProvider with ChangeNotifier {
  // 狀態變數
  VideoPlaybackState _state = VideoPlaybackState.uninitialized;
  VideoPlayerController? _controller;
  VideoInfo? _currentVideo;
  Duration _currentPosition = Duration.zero;
  bool _isLooping = false;
  double _playbackSpeed = 1.0;
  String? _errorMessage;

  // Getters
  VideoPlaybackState get state => _state;
  VideoPlayerController? get controller => _controller;
  VideoInfo? get currentVideo => _currentVideo;
  Duration get currentPosition => _currentPosition;
  bool get isLooping => _isLooping;
  double get playbackSpeed => _playbackSpeed;
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _state == VideoPlaybackState.playing;
  bool get isPaused => _state == VideoPlaybackState.paused;

  /// 初始化視頻
  Future<void> initializeVideo(String videoPath, {String? imuCsvPath}) async {
    try {
      // 先清理舊的控制器
      await _controller?.dispose();

      _state = VideoPlaybackState.uninitialized;
      notifyListeners();

      _controller = VideoPlayerController.file(FileSystemEntity.typeSync(videoPath) == FileSystemEntityType.file
          ? File(videoPath)
          : null as dynamic);

      if (_controller == null) {
        throw Exception('無法打開視頻文件: $videoPath');
      }

      await _controller!.initialize();

      _currentVideo = VideoInfo(
        path: videoPath,
        duration: _controller!.value.duration,
        videoSize: Size(
          _controller!.value.size.width,
          _controller!.value.size.height,
        ),
        imuCsvPath: imuCsvPath,
      );

      _state = VideoPlaybackState.initialized;
      _errorMessage = null;
      _currentPosition = Duration.zero;

      // 監聽播放進度
      _controller!.addListener(_onVideoPositionChanged);
    } catch (e) {
      _state = VideoPlaybackState.error;
      _errorMessage = '初始化視頻失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      notifyListeners();
    }
  }

  /// 播放視頻
  Future<void> play() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _state = VideoPlaybackState.error;
      _errorMessage = '視頻未初始化';
      notifyListeners();
      return;
    }

    try {
      await _controller!.play();
      _state = VideoPlaybackState.playing;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _state = VideoPlaybackState.error;
      _errorMessage = '播放失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 暫停視頻
  Future<void> pause() async {
    if (_controller == null || !isPlaying) return;

    try {
      await _controller!.pause();
      _state = VideoPlaybackState.paused;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '暫停失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 停止視頻
  Future<void> stop() async {
    if (_controller == null) return;

    try {
      await _controller!.pause();
      await _controller!.seekTo(Duration.zero);
      _state = VideoPlaybackState.stopped;
      _currentPosition = Duration.zero;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '停止視頻失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 跳轉到指定位置
  Future<void> seekTo(Duration position) async {
    if (_controller == null) return;

    try {
      await _controller!.seekTo(position);
      _currentPosition = position;
      notifyListeners();
    } catch (e) {
      _errorMessage = '跳轉失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 設置播放速度
  Future<void> setPlaybackSpeed(double speed) async {
    if (_controller == null) return;

    try {
      await _controller!.setPlaybackSpeed(speed);
      _playbackSpeed = speed;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '設置播放速度失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 設置循環播放
  void setLooping(bool looping) {
    if (_controller == null) return;

    _controller!.setLooping(looping);
    _isLooping = looping;
    notifyListeners();
  }

  /// 監聽視頻進度變化
  void _onVideoPositionChanged() {
    if (_controller != null && _controller!.value.isInitialized) {
      _currentPosition = _controller!.value.position;
      notifyListeners();
    }
  }

  /// 獲取進度百分比（0-1）
  double getProgressPercentage() {
    if (_currentVideo == null || _currentVideo!.duration == null) {
      return 0.0;
    }

    final totalSeconds = _currentVideo!.duration!.inMilliseconds.toDouble();
    if (totalSeconds == 0) return 0.0;

    return (_currentPosition.inMilliseconds.toDouble() / totalSeconds).clamp(0.0, 1.0);
  }

  /// 清空視頻
  Future<void> clearVideo() async {
    if (_controller != null) {
      _controller!.removeListener(_onVideoPositionChanged);
      await _controller!.dispose();
      _controller = null;
    }

    _state = VideoPlaybackState.uninitialized;
    _currentVideo = null;
    _currentPosition = Duration.zero;
    _errorMessage = null;
    notifyListeners();
  }

  /// 清除錯誤訊息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_controller != null) {
      _controller!.removeListener(_onVideoPositionChanged);
      await _controller!.dispose();
    }
    super.dispose();
  }
}
