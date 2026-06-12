import 'package:shared_preferences/shared_preferences.dart';

/// 揮桿偵測偏好：是否啟用「雙手判斷」。
///
/// 雙手判斷＝雙手腕都偵測到且一起移動才算一次揮桿擊球，可濾掉撿球/調整裝備/
/// 單手比劃等單手雜訊。其中一隻手被遮擋（數值無法取得）時，自動退回以另一隻
/// 手判斷（避免上桿頂點/收桿單手掉訊整桿漏掉）。
///
/// 由 SHOT 模式與錄影模式設定共用，偵測揮桿對話框以此為預設值。
class SwingDetectPrefs {
  static const _kBothHands = 'swing_both_hands';

  /// 讀取「雙手判斷」開關（預設關閉，維持單手主導行為）。
  static Future<bool> getBothHands() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kBothHands) ?? false;
  }

  /// 寫入「雙手判斷」開關。
  static Future<void> setBothHands(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kBothHands, value);
  }
}
