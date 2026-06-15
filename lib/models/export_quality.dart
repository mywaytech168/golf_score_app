import 'package:golf_score_app/l10n/app_localizations.dart';

/// 影片輸出品質模式（對應 Kotlin ExportQuality 枚舉）。
enum ExportQuality {
  /// 低位元率（~10 Mbps 上限）；檔案最小，適合分享 / 上傳
  small,

  /// 預設品質（~20 Mbps 上限）；平衡畫質與大小
  standard,

  /// 高品質（~40 Mbps 上限）；最清晰，適合本機保存
  high;

  /// 傳遞給 Kotlin MethodChannel 的字串識別碼
  String get channelKey => name.toUpperCase(); // "SMALL" / "STANDARD" / "HIGH"

  /// UI 顯示標題
  String get label => switch (this) {
        ExportQuality.small    => '一般畫質',
        ExportQuality.standard => '標準畫質',
        ExportQuality.high     => '高清畫質',
      };

  /// 預估位元率說明
  String get bitrateHint => switch (this) {
        ExportQuality.small    => '≤ 10 Mbps',
        ExportQuality.standard => '≤ 20 Mbps',
        ExportQuality.high     => '≤ 40 Mbps',
      };

  /// 預估相對檔案大小說明
  String get sizeHint => switch (this) {
        ExportQuality.small    => '檔案最小，適合分享',
        ExportQuality.standard => '平衡畫質與大小',
        ExportQuality.high     => '畫質最佳，檔案較大',
      };

  /// UI 顯示標題（多語系）
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        ExportQuality.small    => l10n.exportQualitySmallLabel,
        ExportQuality.standard => l10n.exportQualityStandardLabel,
        ExportQuality.high     => l10n.exportQualityHighLabel,
      };

  /// 檔案大小說明（多語系）
  String localizedSizeHint(AppLocalizations l10n) => switch (this) {
        ExportQuality.small    => l10n.exportQualitySmallDesc,
        ExportQuality.standard => l10n.exportQualityStandardDesc,
        ExportQuality.high     => l10n.exportQualityHighDesc,
      };
}
