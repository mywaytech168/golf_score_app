import 'package:assets_audio_player/assets_audio_player.dart';

/// 即時揮桿模式的提示音服務。
/// 三個事件用相同音效但不同節奏區分：
///   站姿偵測到 → 1 短聲
///   揮桿撞擊   → 2 短聲
///   錄製完成   → 3 短聲
class ShotSoundService {
  static final ShotSoundService _instance = ShotSoundService._();
  factory ShotSoundService() => _instance;
  ShotSoundService._();

  final _player = AssetsAudioPlayer.newPlayer();
  bool _disposed = false;

  static const _asset = 'assets/sounds/1.mp3';
  static const _beepGap = Duration(milliseconds: 130);

  Future<void> playPostureDetected() => _beeps(1);
  Future<void> playSwingImpact()      => _beeps(2);
  Future<void> playRecordingDone()    => _beeps(3);

  Future<void> _beeps(int count) async {
    if (_disposed) return;
    for (int i = 0; i < count; i++) {
      if (i > 0) await Future.delayed(_beepGap);
      try {
        await _player.open(
          Audio(_asset),
          autoStart: true,
          showNotification: false,
          respectSilentMode: false,
        );
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
    _player.dispose();
  }
}
