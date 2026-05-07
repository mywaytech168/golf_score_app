import 'package:flutter/foundation.dart';
// import 'package:camera/camera.dart';  // ✅ 已移除 - 現在使用 camerawesome

/// 錄制狀態枚舉
enum RecordingState {
  idle,          // 閒置
  initializing,  // 初始化中
  ready,         // 就緒
  recording,     // 錄制中
  paused,        // 已暫停
  processing,    // 後期處理中
  completed,     // 已完成
  error,         // 錯誤
}

/// 當前錄制信息
class CurrentRecording {
  final String? sessionId;      // 錄制會話 ID
  final DateTime? startTime;    // 開始時間
  final Duration? duration;     // 錄制時長
  final int? frameCount;        // 幀數
  final String? videoPath;      // 視頻路徑
  final bool isWithAudio;       // 是否包含音頻
  final bool isWithIMU;         // 是否包含 IMU 數據

  CurrentRecording({
    this.sessionId,
    this.startTime,
    this.duration,
    this.frameCount,
    this.videoPath,
    this.isWithAudio = true,
    this.isWithIMU = true,
  });

  /// 已錄制時長（秒）
  double get recordedSeconds => duration?.inMilliseconds.toDouble() ?? 0.0;

  /// 創建副本
  CurrentRecording copyWith({
    String? sessionId,
    DateTime? startTime,
    Duration? duration,
    int? frameCount,
    String? videoPath,
    bool? isWithAudio,
    bool? isWithIMU,
  }) {
    return CurrentRecording(
      sessionId: sessionId ?? this.sessionId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      frameCount: frameCount ?? this.frameCount,
      videoPath: videoPath ?? this.videoPath,
      isWithAudio: isWithAudio ?? this.isWithAudio,
      isWithIMU: isWithIMU ?? this.isWithIMU,
    );
  }
}

/// 錄制提供者
/// 
/// 管理當前錄制會話狀態（已移除舊 camera 包相機控制，現使用 camerawesome）
class RecordingProvider with ChangeNotifier {
  // 狀態變數
  RecordingState _state = RecordingState.idle;
  CurrentRecording? _currentRecording;
  String? _errorMessage;
  // CameraController? _cameraController;  // ✅ 已移除 - 使用 camerawesome
  // List<CameraDescription>? _availableCameras;  // ✅ 已移除
  int _selectedCameraIndex = 0;
  bool _isFlashEnabled = false;
  bool _captureAudio = true;
  bool _captureIMU = true;

  // Getters
  RecordingState get state => _state;
  CurrentRecording? get currentRecording => _currentRecording;
  String? get errorMessage => _errorMessage;
  // CameraController? get cameraController => _cameraController;  // ✅ 已移除
  // List<CameraDescription>? get availableCameras => _availableCameras;  // ✅ 已移除
  int get selectedCameraIndex => _selectedCameraIndex;
  bool get isFlashEnabled => _isFlashEnabled;
  bool get isRecording => _state == RecordingState.recording;
  bool get isPaused => _state == RecordingState.paused;
  bool get isCapturingAudio => _captureAudio;
  bool get isCapturingIMU => _captureIMU;

  /// 初始化相機（已移至 RecordScreen - camerawesome 自動處理）
  Future<void> initializeCamera(dynamic cameras) async {  // ✅ dynamic 而非 CameraDescription
    // 相機初始化已由 camerawesome 自動處理
    _state = RecordingState.ready;
    _errorMessage = null;
    notifyListeners();
  }

  /// 開始錄制
  Future<void> startRecording() async {
    // ⚠️ 實際錄制由 RecordScreen 和 camerawesome 處理
    // 此方法僅用於狀態管理
    
    try {
      _state = RecordingState.recording;
      _currentRecording = CurrentRecording(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        startTime: DateTime.now(),
        isWithAudio: _captureAudio,
        isWithIMU: _captureIMU,
      );
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _state = RecordingState.error;
      _errorMessage = '開始錄制失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 停止錄制
  Future<String?> stopRecording() async {
    if (!isRecording) {
      _state = RecordingState.error;
      _errorMessage = '未在錄制中';
      notifyListeners();
      return null;
    }

    try {
      _state = RecordingState.processing;
      notifyListeners();

      // Camerawesome handles stopping automatically through UI
      _state = RecordingState.completed;
      _errorMessage = null;
      return _currentRecording?.videoPath;
    } catch (e) {
      _state = RecordingState.error;
      _errorMessage = '停止錄制失敗: $e';
      debugPrint(_errorMessage);
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// 暫停錄制
  Future<void> pauseRecording() async {
    if (!isRecording) return;

    try {
      // await _cameraController!.pauseVideoRecording();
      _state = RecordingState.paused;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '暫停錄制失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 恢復錄制
  Future<void> resumeRecording() async {
    if (!isPaused) return;

    try {
      // await _cameraController!.resumeVideoRecording();
      _state = RecordingState.recording;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '恢復錄制失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 切換閃光燈（已移除 - camerawesome 自動處理）
  Future<void> toggleFlash() async {
    // ⚠️ 閃光燈控制已由 camerawesome 處理
    _isFlashEnabled = !_isFlashEnabled;
    notifyListeners();
  }

  /// 切換相機（前置/後置）（已移除 - camerawesome 自動處理）
  Future<void> switchCamera(int cameraIndex) async {
    // ⚠️ 相機切換已由 camerawesome 處理
    _selectedCameraIndex = cameraIndex;
    notifyListeners();
  }

  /// 設置音頻捕獲
  void setAudioCapture(bool enabled) {
    _captureAudio = enabled;
    notifyListeners();
  }

  /// 設置 IMU 捕獲
  void setIMUCapture(bool enabled) {
    _captureIMU = enabled;
    notifyListeners();
  }

  /// 重置狀態
  void reset() {
    _state = RecordingState.idle;
    _currentRecording = null;
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
    // Camerawesome handles cleanup automatically
    super.dispose();
  }
}
