import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/export_quality.dart';
import '../models/export_spec.dart';
import 'ball_trajectory_service.dart';
import 'export_composer_service.dart';
import 'skeleton_csv_locator.dart';
import 'skeleton_overlay_service.dart';

/// 隨選燒錄：分析階段不再產生 skeleton.mp4 / final.mp4（播放器即時疊圖），
/// 只在使用者「下載」時現場燒錄一次，之後重複下載直接用快取檔。
class OverlayBurnService {
  /// 是否具備燒錄骨架版的素材（乾淨 clip + 骨架 CSV）。
  static bool canBurnSkeleton(String sessionDir) =>
      File(p.join(sessionDir, 'clip.mp4')).existsSync() &&
      resolveSkeletonCsv(sessionDir) != null;

  /// 是否具備燒錄完整版的素材（骨架素材 + trajectory.json）。
  static bool canBurnFinal(String sessionDir) =>
      canBurnSkeleton(sessionDir) &&
      File(p.join(sessionDir, 'trajectory.json')).existsSync();

  /// 確保 skeleton.mp4 存在；不存在則以 clip.mp4 + 骨架 CSV 現場燒錄。
  /// 回傳檔案路徑，素材不足或燒錄失敗回傳 null。
  static Future<String?> ensureSkeletonVideo(
    String sessionDir, {
    ExportQuality quality = ExportQuality.standard,
  }) async {
    final out = p.join(sessionDir, 'skeleton.mp4');
    if (File(out).existsSync()) return out;
    final clip = p.join(sessionDir, 'clip.mp4');
    final csv  = resolveSkeletonCsv(sessionDir);
    if (!File(clip).existsSync() || csv == null) return null;
    debugPrint('[OverlayBurn] 燒錄 skeleton.mp4 …');
    return SkeletonOverlayService.render(
      clipPath:   clip,
      csvPath:    csv,
      startSec:   0.0,   // clip 目錄的 CSV 為 clip 相對時間
      outputPath: out,
      quality:    quality,
    );
  }

  /// 是否具備任何可疊加素材（決定要不要顯示「自訂匯出」）。
  static bool canCompose(String sessionDir) =>
      File(p.join(sessionDir, 'clip.mp4')).existsSync();

  /// 依 [spec] 單 pass 合成可下載影片，回傳輸出路徑（失敗回傳 null）。
  ///
  /// 來源固定為 clip.mp4（乾淨片段）。骨架/軌跡素材不足時自動跳過該 layer。
  /// 相同 [spec.cacheKey] 已存在則直接重用，不重燒。
  static Future<String?> composeForExport(
    String sessionDir,
    ExportSpec spec,
  ) async {
    final clip = p.join(sessionDir, 'clip.mp4');
    if (!File(clip).existsSync()) {
      debugPrint('[OverlayBurn] composeForExport: clip.mp4 不存在');
      return null;
    }

    final out = p.join(sessionDir, '${spec.cacheKey}.mp4');
    if (File(out).existsSync()) return out;

    // 骨架素材（clip 目錄 CSV 為 clip 相對時間 → startSec=0）
    final csv = (spec.skeleton ? resolveSkeletonCsv(sessionDir) : null);

    // 軌跡素材
    List<Map<String, dynamic>> trackPts = const [];
    if (spec.trajectory) {
      final trajFile = File(p.join(sessionDir, 'trajectory.json'));
      if (trajFile.existsSync()) {
        try {
          final raw = jsonDecode(await trajFile.readAsString()) as Map<String, dynamic>;
          trackPts = (raw['points'] as List)
              .map((e) => <String, dynamic>{
                    'x':   (e['x'] as num).round(),
                    'y':   (e['y'] as num).round(),
                    'pts': (e['pts'] as num).toInt(),
                  })
              .toList();
        } catch (e) {
          debugPrint('[OverlayBurn] trajectory.json 解析失敗: $e');
        }
      }
    }

    debugPrint('[OverlayBurn] composeForExport ${spec.cacheKey} '
        '(skeleton=${csv != null}, trajPts=${trackPts.length}, watermark=${spec.watermark})');

    return ExportComposerService.compose(
      clipPath:   clip,
      csvPath:    csv,
      startSec:   0.0,
      trackPts:   trackPts,
      watermark:  spec.watermark,
      outputPath: out,
      quality:    spec.quality,
    );
  }

  /// 確保 final.mp4（骨架 + 球軌跡）存在；不存在則先確保 skeleton.mp4，
  /// 再把 trajectory.json 的軌跡點疊上去。
  static Future<String?> ensureFinalVideo(
    String sessionDir, {
    ExportQuality quality = ExportQuality.standard,
  }) async {
    final out = p.join(sessionDir, 'final.mp4');
    if (File(out).existsSync()) return out;

    final trajFile = File(p.join(sessionDir, 'trajectory.json'));
    if (!trajFile.existsSync()) return null;

    final base = await ensureSkeletonVideo(sessionDir, quality: quality);
    if (base == null) return null;

    List<Map<String, dynamic>> trackPts;
    try {
      final raw = jsonDecode(await trajFile.readAsString()) as Map<String, dynamic>;
      trackPts = (raw['points'] as List)
          .map((e) => <String, dynamic>{
                'x':   (e['x'] as num).round(),
                'y':   (e['y'] as num).round(),
                'pts': (e['pts'] as num).toInt(),
              })
          .toList();
    } catch (e) {
      debugPrint('[OverlayBurn] trajectory.json 解析失敗: $e');
      return null;
    }
    if (trackPts.isEmpty) return base;   // 無軌跡點 → 骨架版即等同完整版

    debugPrint('[OverlayBurn] 燒錄 final.mp4 …（${trackPts.length} 點）');
    return BallTrajectoryService.renderOverlay(
      inputPath:  base,
      outputPath: out,
      trackPts:   trackPts,
      quality:    quality,
    );
  }
}
