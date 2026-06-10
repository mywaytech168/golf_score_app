import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// 球軌跡資料（trajectory.json）：ClipPipeline 追蹤完成時落地，
/// 座標為 coded 空間（與燒錄版 TrajectoryOverlayRenderer 相同輸入）。
class TrajectoryTrack {
  final int codedW;
  final int codedH;
  final int rotation; // 0 / 90 / 180 / 270
  final List<TrajectoryPoint> points; // 依 ptsUs 遞增

  const TrajectoryTrack({
    required this.codedW,
    required this.codedH,
    required this.rotation,
    required this.points,
  });

  /// display 空間尺寸（套用 rotation 後）
  int get displayW => (rotation == 90 || rotation == 270) ? codedH : codedW;
  int get displayH => (rotation == 90 || rotation == 270) ? codedW : codedH;

  static Future<TrajectoryTrack?> load(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final pts = (raw['points'] as List)
          .map((e) => TrajectoryPoint(
                x: (e['x'] as num).toDouble(),
                y: (e['y'] as num).toDouble(),
                ptsUs: (e['pts'] as num).toInt(),
              ))
          .toList()
        ..sort((a, b) => a.ptsUs.compareTo(b.ptsUs));
      return TrajectoryTrack(
        codedW: (raw['codedW'] as num).toInt(),
        codedH: (raw['codedH'] as num).toInt(),
        rotation: (raw['rotation'] as num?)?.toInt() ?? 0,
        points: pts,
      );
    } catch (e) {
      debugPrint('[TrajectoryTrack] 載入失敗: $e');
      return null;
    }
  }

  /// coded → display 正規化座標（0~1），供 painter 乘 canvas 尺寸
  Offset normalizedDisplay(TrajectoryPoint p) {
    switch (rotation) {
      case 90: // display = coded 順時針轉 90°
        return Offset((codedH - p.y) / codedH, p.x / codedW);
      case 180:
        return Offset((codedW - p.x) / codedW, (codedH - p.y) / codedH);
      case 270:
        return Offset(p.y / codedH, (codedW - p.x) / codedW);
      default:
        return Offset(p.x / codedW, p.y / codedH);
    }
  }
}

class TrajectoryPoint {
  final double x; // coded 空間
  final double y;
  final int ptsUs;
  const TrajectoryPoint({required this.x, required this.y, required this.ptsUs});
}

/// 即時球軌跡疊圖：樣式對齊燒錄版 TrajectoryOverlayRenderer
/// （陰影 10px + 金黃線 7px + 末端白點 9px，均為影片像素，依 canvas 換算）。
class TrajectoryPainter extends CustomPainter {
  final TrajectoryTrack track;

  /// 目前播放位置（秒）：只畫 pts ≤ position 的點（與燒錄逐幀邏輯一致）
  final double positionSec;

  const TrajectoryPainter({required this.track, required this.positionSec});

  static const _trajColor = Color(0xE6FFD21E); // argb(230,255,210,30) 金黃

  @override
  void paint(Canvas canvas, Size size) {
    final posUs = (positionSec * 1e6).round();
    final visible = <Offset>[];
    for (final p in track.points) {
      if (p.ptsUs > posUs) break;
      final n = track.normalizedDisplay(p);
      visible.add(Offset(n.dx * size.width, n.dy * size.height));
    }
    if (visible.isEmpty) return;

    // 影片像素 → canvas 邏輯像素換算（燒錄版常數定義於影片空間）
    final scale = size.shortestSide / (track.displayW < track.displayH
        ? track.displayW
        : track.displayH);
    final shadowPaint = Paint()
      ..color = const Color(0x64000000) // alpha 100 黑
      ..strokeWidth = 10 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePaint = Paint()
      ..color = _trajColor
      ..strokeWidth = 7 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (visible.length >= 2) {
      final path = Path()..moveTo(visible.first.dx, visible.first.dy);
      for (final o in visible.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, linePaint);
    }

    // 末端球點：白底 + 金黃描邊
    final last = visible.last;
    final dotR = 9 * scale;
    canvas.drawCircle(last, dotR, Paint()..color = Colors.white);
    canvas.drawCircle(
      last,
      dotR,
      Paint()
        ..color = _trajColor
        ..strokeWidth = 2 * scale
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(TrajectoryPainter old) =>
      old.positionSec != positionSec || old.track != track;
}
