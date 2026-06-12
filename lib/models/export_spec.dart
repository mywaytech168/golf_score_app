import 'export_quality.dart';

/// 匯出合成規格：使用者於下載前勾選的疊加元素。
///
/// MVP 已接通：[skeleton] / [trajectory] / [watermark]（單 pass 燒錄）。
/// 擊球特效：[hitGlow]（中性光暈）/ [sweetSpot]（甜蜜點品質光圈）已接通原生繪製，
/// 需有擊球時刻（clip 相對秒）才可用。
/// P1 預留欄位（[postureText] / [aiPanel]）仍僅佔位，尚未串到原生繪製。
///
/// [watermark] 由付費狀態決定，免費版強制 true、UI 不可關。
class ExportSpec {
  final bool skeleton;
  final bool trajectory;
  final bool watermark;

  // ── 擊球特效（已接通原生繪製）────────────────────────
  /// 中性亮白擴散光暈（擊球瞬間，不帶品質語意）。
  final bool hitGlow;
  /// 甜蜜點品質光圈（金/藍/灰，依 goodShot + passCount）。
  final bool sweetSpot;

  // ── 預留（尚未實作繪製）──────────────────────────────
  final bool postureText;
  final bool aiPanel;

  final ExportQuality quality;

  const ExportSpec({
    this.skeleton = false,
    this.trajectory = false,
    this.watermark = false,
    this.postureText = false,
    this.aiPanel = false,
    this.hitGlow = false,
    this.sweetSpot = false,
    this.quality = ExportQuality.standard,
  });

  ExportSpec copyWith({
    bool? skeleton,
    bool? trajectory,
    bool? watermark,
    bool? postureText,
    bool? aiPanel,
    bool? hitGlow,
    bool? sweetSpot,
    ExportQuality? quality,
  }) =>
      ExportSpec(
        skeleton: skeleton ?? this.skeleton,
        trajectory: trajectory ?? this.trajectory,
        watermark: watermark ?? this.watermark,
        postureText: postureText ?? this.postureText,
        aiPanel: aiPanel ?? this.aiPanel,
        hitGlow: hitGlow ?? this.hitGlow,
        sweetSpot: sweetSpot ?? this.sweetSpot,
        quality: quality ?? this.quality,
      );

  /// 已啟用且已實作的疊加層數（不含浮水印）。
  int get activeOverlayCount =>
      (skeleton ? 1 : 0) + (trajectory ? 1 : 0) +
      (hitGlow ? 1 : 0) + (sweetSpot ? 1 : 0);

  /// 快取檔名識別碼：相同選擇 → 相同輸出檔，重複下載直接重用。
  /// 例：`export_s1_t0_w1_g0_ss0_standard.mp4`
  String get cacheKey =>
      'export_s${skeleton ? 1 : 0}_t${trajectory ? 1 : 0}'
      '_w${watermark ? 1 : 0}_g${hitGlow ? 1 : 0}_ss${sweetSpot ? 1 : 0}'
      '_${quality.name}';
}
