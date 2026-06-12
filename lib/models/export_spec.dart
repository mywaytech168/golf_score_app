import 'export_quality.dart';

/// 匯出合成規格：使用者於下載前勾選的疊加元素。
///
/// MVP 已接通：[skeleton] / [trajectory] / [watermark]（單 pass 燒錄）。
/// P1/P2 預留欄位（[postureText] / [aiPanel] / [hitGlow] / [sweetSpot]）目前
/// 僅佔位，尚未串到原生繪製，預設關閉。
///
/// [watermark] 由付費狀態決定，免費版強制 true、UI 不可關。
class ExportSpec {
  final bool skeleton;
  final bool trajectory;
  final bool watermark;

  // ── 預留（尚未實作繪製）──────────────────────────────
  final bool postureText;
  final bool aiPanel;
  final bool hitGlow;
  final bool sweetSpot;

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

  /// 已啟用且 MVP 已實作的疊加層數（不含浮水印）。
  int get activeOverlayCount => (skeleton ? 1 : 0) + (trajectory ? 1 : 0);

  /// 快取檔名識別碼：相同選擇 → 相同輸出檔，重複下載直接重用。
  /// 例：`export_s1_t0_w1_standard.mp4`
  String get cacheKey =>
      'export_s${skeleton ? 1 : 0}_t${trajectory ? 1 : 0}'
      '_w${watermark ? 1 : 0}_${quality.name}';
}
