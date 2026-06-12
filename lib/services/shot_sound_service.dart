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

  static const _assetPosture = 'assets/sounds/dragon-studio-ding-sfx-472366.mp3';
  static const _assetImpact  = 'assets/sounds/kakaist-camera-shutter-314056.mp3';
  static const _assetDone    = 'assets/sounds/soundshelfstudio-ui-success-chime-513565.mp3';

  Future<void> playPostureDetected() => _play(_assetPosture);
  Future<void> playSwingImpact()      => _play(_assetImpact);
  Future<void> playRecordingDone()    => _play(_assetDone);

  /// 站姿確認音：播放並等到音效結束才返回（含喇叭衰減餘裕）。
  /// 呼叫端靠 await 保證提示音不會被接下來的錄影收進 mp4 音軌。
  Future<void> playAddressConfirmedAndWait() async {
    if (_disposed) return;
    try {
      await _player.open(
        Audio(_assetPosture),
        autoStart: true,
        showNotification: false,
        respectSilentMode: false,
      );
      // 等待播放結束；音檔異常時以 1.5s 上限兜底，避免卡住開錄流程。
      await _player.playlistAudioFinished.first
          .timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
    // 喇叭殘響/路徑延遲餘裕
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _play(String asset) async {
    if (_disposed) return;
    try {
      await _player.open(
        Audio(asset),
        autoStart: true,
        showNotification: false,
        respectSilentMode: false,
      );
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _player.dispose();
  }
}
