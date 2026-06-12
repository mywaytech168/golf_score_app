import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/export_quality.dart';

/// 匯出合成服務：呼叫原生單 pass 合成器，將軌跡/骨架/浮水印一次燒錄。
///
/// 對應 Android `ExportComposerRenderer`（iOS 待實作）。
class ExportComposerService {
  static const _channel =
      MethodChannel('com.example.golf_score_app/export_composer');

  /// 浮水印素材（branding logo）→ 暫存檔（原生需檔案路徑，asset 無法直接用）。
  /// 第一次呼叫複製一次，之後重用。
  static const _watermarkAsset = 'assets/branding/logo_horizontal.png';
  static String? _cachedWatermarkPath;

  static Future<String?> _ensureWatermarkFile() async {
    final cached = _cachedWatermarkPath;
    if (cached != null && File(cached).existsSync()) return cached;
    try {
      final bytes = await rootBundle.load(_watermarkAsset);
      final dir = await getTemporaryDirectory();
      final dst = p.join(dir.path, 'orvia_watermark.png');
      await File(dst).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      _cachedWatermarkPath = dst;
      return dst;
    } catch (e) {
      debugPrint('[ExportComposer] 浮水印素材準備失敗: $e');
      return null;
    }
  }

  /// 單 pass 合成。任一 layer 可關（傳 null / 空 / false）。
  ///
  /// [clipPath]    乾淨來源片段
  /// [csvPath]     骨架 CSV；null → 不畫骨架
  /// [startSec]    片段在原片起始秒（對齊 CSV）
  /// [trackPts]    軌跡點 [{x,y,pts}]；空 → 不畫軌跡
  /// [watermark]   true → 燒錄 ORVIA 浮水印
  /// [hitGlow]     true → 擊球瞬間中性光暈（需 [impactSec]）
  /// [sweetSpot]   true → 甜蜜點品質光圈（需 [impactSec]，色彩依 [goodShot]/[passCount]）
  /// [impactSec]   擊球時刻（clip 相對秒）；null → 不畫擊球特效
  /// [goodShot]    擊球品質（甜蜜點色彩）：true=好球、false=薄球、null=未知（不畫甜蜜點）
  /// [passCount]   音訊通過數（≥4 → 金色甜蜜點）
  /// [outputPath]  輸出 mp4
  ///
  /// 成功回傳 [outputPath]，失敗回傳 null。
  static Future<String?> compose({
    required String clipPath,
    String? csvPath,
    double startSec = 0.0,
    List<Map<String, dynamic>> trackPts = const [],
    bool watermark = false,
    bool hitGlow = false,
    bool sweetSpot = false,
    double? impactSec,
    bool? goodShot,
    int passCount = 0,
    required String outputPath,
    ExportQuality quality = ExportQuality.standard,
  }) async {
    try {
      final watermarkPath = watermark ? await _ensureWatermarkFile() : null;
      final saved = await _channel.invokeMethod<String>('compose', {
        'clipPath':      clipPath,
        'csvPath':       csvPath,
        'startSec':      startSec,
        'trackPts':      trackPts,
        'watermarkPath': watermarkPath,
        'hitGlow':       hitGlow,
        'sweetSpot':     sweetSpot,
        'impactSec':     impactSec,
        'goodShot':      goodShot,
        'passCount':     passCount,
        'outputPath':    outputPath,
        'quality':       quality.channelKey,
      });
      return saved;
    } catch (e) {
      debugPrint('[ExportComposer] compose error: $e');
      return null;
    }
  }
}
