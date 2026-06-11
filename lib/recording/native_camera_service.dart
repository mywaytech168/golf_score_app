import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pose_result.dart';

// ── Channel 名稱（Android CameraRecorderChannel / iOS MediaPipeCameraChannel 共用）
const _kMethodChannel = MethodChannel('com.aethertek.orvia/camera_recorder');
const _kPoseChannel   = EventChannel('com.aethertek.orvia/pose_landmarks');

// ─────────────────────────────────────────────────────────────────────────────

/// 統一相機服務（Android Camera2 + iOS AVFoundation + MediaPipe）
///
/// 兩平台皆使用 Flutter Texture 顯示預覽；姿勢資料透過 [poseStream] 推送。
/// 不再傳送原始幀給 Flutter，也不依賴 google_mlkit_pose_detection。
class NativeCameraService {
  int?  _textureId;
  int   _sensorOrientation = 90;
  bool  _isFront = false;
  bool  _supportsStabilization = false;
  bool  _stabilizationEnabled  = true;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  StreamSubscription<dynamic>? _poseSub;
  final _poseController = StreamController<NativePoseResult>.broadcast();

  int? get textureId => _textureId;
  int  get sensorOrientation => _sensorOrientation;
  bool get isFrontCamera => _isFront;
  bool get supportsVideoStabilization => _supportsStabilization;
  bool get videoStabilizationEnabled  => _stabilizationEnabled;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  /// MediaPipe 骨架資料流（僅在相機開啟後有資料；錄影期間可能暫停）
  Stream<NativePoseResult> get poseStream => _poseController.stream;

  // ── 開啟相機 ──────────────────────────────────────────────────────────────

  Future<void> openCamera({
    int facing = 0,          // 0=後鏡頭, 1=前鏡頭
    String quality = 'hd',  // 'hd' | 'fhd'
    int fps = 30,            // 30 | 60
  }) async {
    await _poseSub?.cancel();
    _poseSub = null;
    _textureId = null;

    // Android: LENS_FACING_BACK=1, LENS_FACING_FRONT=0（與 Flutter 慣例相反）
    final androidFacing = defaultTargetPlatform == TargetPlatform.android
        ? (facing == 0 ? 1 : 0)
        : facing;

    _poseSub = _kPoseChannel.receiveBroadcastStream().listen(
      _onPoseEvent,
      onError: (e) => debugPrint('[NativeCamera] pose channel error: $e'),
    );

    final result = await _kMethodChannel.invokeMethod<Map>(
      'openCamera',
      {'facing': androidFacing, 'quality': quality, 'fps': fps},
    );
    if (result == null) return;

    _textureId          = result['textureId'] as int?;
    _sensorOrientation  = result['sensorOrientation'] as int? ?? 0;
    _isFront            = facing == 1;
    _supportsStabilization = result['supportsVideoStabilization'] as bool? ?? false;

    debugPrint('[NativeCamera] opened: textureId=$_textureId '
        'sensorOri=$_sensorOrientation isFront=$_isFront');
  }

  void _onPoseEvent(dynamic event) {
    if (_poseController.isClosed) return;
    try {
      final m = Map<Object?, Object?>.from(event as Map);
      _poseController.add(NativePoseResult.fromMap(m));
    } catch (e) {
      debugPrint('[NativeCamera] pose parse error: $e');
    }
  }

  // ── 切換前後鏡頭 ──────────────────────────────────────────────────────────

  Future<void> switchCamera({String quality = 'hd', int fps = 30}) =>
      openCamera(facing: _isFront ? 0 : 1, quality: quality, fps: fps);

  // ── 錄製 ─────────────────────────────────────────────────────────────────

  /// 提前建立含 MediaRecorder 的 CaptureSession，解決「開始錄影閃一下」問題。
  /// 在使用者「即將開始錄影」的前 0.5-2 秒呼叫（如：進入準備狀態、倒數開始）。
  /// startRecording 時若此路徑已預備，直接 rec.start()，無需重建 Session → 零閃爍。
  Future<void> prepareForRecording({required String path}) async {
    try {
      await _kMethodChannel.invokeMethod('prepareForRecording', {'path': path});
    } catch (e) {
      debugPrint('[NativeCamera] prepareForRecording error: $e');
    }
  }

  /// 最近一次錄影起點的原生時間戳（ms，BOOTTIME，與 pose.timestampMs 同時鐘）。
  /// iOS / 舊版原生未回傳時為 0。
  int lastRecordStartTsMs = 0;

  Future<void> startRecording({required String path}) async {
    final result =
        await _kMethodChannel.invokeMethod('startRecording', {'path': path});
    lastRecordStartTsMs =
        (result is Map ? (result['startTsMs'] as num?)?.toInt() : null) ?? 0;
  }

  /// 停止錄製。回傳 true 表示影片已成功封口可播放；
  /// 丟出 PlatformException(record_failed) 表示本次錄製未產生有效影格（壞檔已被 native 刪除）。
  Future<bool> stopRecording() async {
    final ok = await _kMethodChannel.invokeMethod<bool>('stopRecording');
    return ok ?? true;
  }

  // ── 縮放 ─────────────────────────────────────────────────────────────────

  Future<void> setZoom(double frac) async {
    try {
      await _kMethodChannel.invokeMethod('setZoom', {'zoom': frac});
    } catch (e) {
      debugPrint('[NativeCamera] setZoom error: $e');
    }
  }

  // ── 防震 ─────────────────────────────────────────────────────────────────

  Future<void> setVideoStabilization(bool enabled) async {
    _stabilizationEnabled = enabled;
    if (!_supportsStabilization) return;
    try {
      await _kMethodChannel.invokeMethod('setVideoStabilization', {'enabled': enabled});
    } catch (e) {
      debugPrint('[NativeCamera] setVideoStabilization error: $e');
    }
  }

  // ── 預覽 Widget ───────────────────────────────────────────────────────────

  /// 回傳相機預覽 Widget（兩平台皆用 Flutter Texture）
  /// 骨架已由原生 Kotlin/Swift 繪製在 Texture 上，Flutter 端直接顯示即可。
  Widget buildPreviewWidget() {
    final id = _textureId;
    if (id == null) return const SizedBox.expand();
    // Rotation is handled natively (Bitmap rotation on Android, AVFoundation orientation on iOS)
    // so sensorOrientation always returns 0 from native side.
    return SizedBox.expand(child: Texture(textureId: id));
  }

  bool get isReady => _textureId != null;

  // ── 釋放 ─────────────────────────────────────────────────────────────────

  // 錄影頁 pop 時呼叫：關 session/camera，但 native HandlerThread 保持活著
  Future<void> dispose() async {
    await _poseSub?.cancel();
    _poseSub   = null;
    _textureId = null;
    try { await _kMethodChannel.invokeMethod('dispose'); } catch (_) {}
    if (!_poseController.isClosed) await _poseController.close();
  }

  // App 真正退出時呼叫：完整關閉 native thread / poseHelper
  Future<void> destroy() async {
    await _poseSub?.cancel();
    _poseSub   = null;
    _textureId = null;
    try { await _kMethodChannel.invokeMethod('destroy'); } catch (_) {}
    if (!_poseController.isClosed) await _poseController.close();
  }
}
