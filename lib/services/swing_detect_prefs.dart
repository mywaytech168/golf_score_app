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
  static const _kGlowDelayMs = 'impact_glow_delay_ms';

  /// 擊球光暈延遲預設（ms）：偵測抓手腕弧底，桿頭碰球略晚於弧底，故延後對齊觸球。
  static const int defaultGlowDelayMs = 500;

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

  /// 讀取擊球光暈延遲（ms，0~2000）。
  static Future<int> getGlowDelayMs() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kGlowDelayMs) ?? defaultGlowDelayMs;
  }

  /// 寫入擊球光暈延遲（ms）。
  static Future<void> setGlowDelayMs(int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kGlowDelayMs, value.clamp(0, 2000));
  }

  static const _kOverlayLeadMs = 'overlay_lead_ms';

  /// 疊圖播放補償預設（ms）：video_player position 與實際顯示幀有解碼延遲，
  /// 取樣 CSV 時提前此值把骨架/軌跡往前拉對齊顯示幀。骨架落後→調大、超前→調小。
  static const int defaultOverlayLeadMs = 100;

  /// 讀取疊圖播放補償（ms，-200~600）。
  static Future<int> getOverlayLeadMs() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kOverlayLeadMs) ?? defaultOverlayLeadMs;
  }

  /// 寫入疊圖播放補償（ms）。
  static Future<void> setOverlayLeadMs(int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kOverlayLeadMs, value.clamp(-200, 600));
  }

  static const _kShowTelemetry = 'show_wrist_telemetry';

  /// 讀取「顯示腕點數值（除錯 HUD）」開關（預設關閉）。
  static Future<bool> getShowTelemetry() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kShowTelemetry) ?? false;
  }

  /// 寫入「顯示腕點數值」開關。
  static Future<void> setShowTelemetry(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kShowTelemetry, value);
  }

  static const _kSwingSpeedFloor = 'swing_speed_floor';

  /// 揮桿速度門檻預設（歸一化位移/幀）：峰值速度需達此值才算真揮桿；雙手判斷下快手
  /// 須達此值、慢手達 ×0.4。ADB 實錄真桿峰值 ≥0.209，預設 0.15 留 ~28% 裕度（真桿
  /// 不漏）同時擋掉 waggle/走路/半揮等中速雜訊（實測較緩半揮 hi 0.10~0.16）。
  static const double defaultSwingSpeedFloor = 0.15;

  /// 讀取揮桿速度門檻（歸一化 0.05~0.30）。
  static Future<double> getSwingSpeedFloor() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(_kSwingSpeedFloor) ?? defaultSwingSpeedFloor;
  }

  /// 寫入揮桿速度門檻（歸一化）。
  static Future<void> setSwingSpeedFloor(double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kSwingSpeedFloor, value.clamp(0.05, 0.30));
  }

  static const _kAnchorGate = 'impact_anchor_gate';

  /// 讀取「錨點偵測閘門」開關（預設關閉）。開啟＝揮桿須經過錨點半徑內才算一桿。
  static Future<bool> getAnchorGate() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kAnchorGate) ?? false;
  }

  /// 寫入「錨點偵測閘門」開關。
  static Future<void> setAnchorGate(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAnchorGate, value);
  }

  static const _kAnchorRadius = 'impact_anchor_radius';

  /// 錨點命中半徑預設（歸一化）：主導腕回歸需逼近到此半徑內才算錨點擊球。
  /// 預設放寬至 0.50——因錨點常點在「球」上，但偵測追手腕，觸球時手腕離球約一個
  /// 桿身（>0.3 歸一化），門檻太緊會把正常揮桿全擋掉退回峰值。寬鬆＝取最接近幀
  /// （時間≈觸球），需要更嚴再往下調。
  static const double defaultAnchorRadius = 0.50;

  /// 讀取錨點命中半徑（歸一化 0.05~0.80）。
  static Future<double> getAnchorRadius() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(_kAnchorRadius) ?? defaultAnchorRadius;
  }

  /// 寫入錨點命中半徑（歸一化）。
  static Future<void> setAnchorRadius(double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kAnchorRadius, value.clamp(0.05, 0.80));
  }

  static const _kUseAnchor = 'impact_use_anchor';

  /// 讀取「錨點擊球（V4）」開關（**預設關閉**：退回手腕弧底 V1 判定；
  /// 使用者於設定開啟後，已設錨點時才用錨點當擊球點）。
  static Future<bool> getUseAnchor() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kUseAnchor) ?? false;
  }

  /// 寫入「錨點擊球（V4）」開關。
  static Future<void> setUseAnchor(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kUseAnchor, value);
  }

  static const _kPSysTextLabel = 'psystem_text_label';

  /// P-System 標籤樣式：true=文字簡稱（預備/桿平上…）、false=字母簡稱（P1…P10，預設）。
  static Future<bool> getPSystemTextLabel() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kPSysTextLabel) ?? false;
  }

  static Future<void> setPSystemTextLabel(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPSysTextLabel, value);
  }

  static const _kAnchorX = 'impact_anchor_x';
  static const _kAnchorY = 'impact_anchor_y';

  /// 讀取擊球錨點（歸一化 0-1）；未設定回傳 null。
  static Future<(double, double)?> getAnchor() async {
    final sp = await SharedPreferences.getInstance();
    final x = sp.getDouble(_kAnchorX), y = sp.getDouble(_kAnchorY);
    if (x == null || y == null) return null;
    return (x, y);
  }

  /// 寫入擊球錨點（歸一化）。
  static Future<void> setAnchor(double x, double y) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kAnchorX, x.clamp(0.0, 1.0));
    await sp.setDouble(_kAnchorY, y.clamp(0.0, 1.0));
  }

  /// 清除擊球錨點。
  static Future<void> clearAnchor() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kAnchorX);
    await sp.remove(_kAnchorY);
  }
}
