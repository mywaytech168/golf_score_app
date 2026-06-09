import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Derives a golfer exclude-box (in the ball tracker's CODED coordinate space)
/// from the MediaPipe pose CSV, so blobs landing on the body/club are dropped.
///
/// pose_landmarks.csv columns are in DISPLAY space (lmN_x_px = xNorm*dispW),
/// while BallTracker works in CODED space. The two differ only by the video
/// `rotation` metadata, so we map display→coded by rotating the bbox corners.
class GolferMask {
  static const String _tag = '[GolferMask]';

  /// Map a DISPLAY-space box to CODED space for a given Android rotation
  /// (degrees the coded frame is rotated CLOCKWISE to display upright).
  /// Returns an axis-aligned coded box [x1,y1,x2,y2]. Pure + unit-tested.
  static List<int> displayBoxToCoded(
    double dx1, double dy1, double dx2, double dy2,
    int dispW, int dispH, int rotation,
  ) {
    // coded = display rotated COUNTER-clockwise by `rotation`.
    List<double> toCoded(double x, double y) {
      switch (rotation) {
        case 90:
          return [y, (dispW - 1) - x];        // codedW=dispH, codedH=dispW
        case 180:
          return [(dispW - 1) - x, (dispH - 1) - y];
        case 270:
          return [(dispH - 1) - y, x];
        default: // 0
          return [x, y];
      }
    }

    final corners = [
      toCoded(dx1, dy1), toCoded(dx2, dy1),
      toCoded(dx2, dy2), toCoded(dx1, dy2),
    ];
    double minX = corners[0][0], minY = corners[0][1];
    double maxX = minX, maxY = minY;
    for (final c in corners) {
      minX = math.min(minX, c[0]); maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]); maxY = math.max(maxY, c[1]);
    }
    return [minX.floor(), minY.floor(), maxX.ceil(), maxY.ceil()];
  }

  /// Read the pose CSV, take the frame nearest [hitSec], build the body bbox
  /// from visible landmarks, expand by [margin], and convert to coded space.
  /// Returns null if unavailable (caller then tracks without a golfer mask).
  static Future<List<int>?> codedBoxFromPoseCsv({
    required String csvPath,
    required double hitSec,
    required int codedW,
    required int codedH,
    required int rotation,
    double margin = 0.15,
    double minVisibility = 0.3,
  }) async {
    try {
      final file = File(csvPath);
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      if (lines.length < 2) return null;

      final headers = lines[0].split(',');
      final timeIdx = headers.indexOf('time_sec');
      if (timeIdx < 0) return null;

      // Collect indices for all landmarks present: lmN_x_px / lmN_y_px / lmN_visibility
      final lm = <int, ({int x, int y, int vis})>{};
      for (int n = 0; n < 33; n++) {
        final xi = headers.indexOf('lm${n}_x_px');
        final yi = headers.indexOf('lm${n}_y_px');
        final vi = headers.indexOf('lm${n}_visibility');
        if (xi >= 0 && yi >= 0) lm[n] = (x: xi, y: yi, vis: vi);
      }
      if (lm.isEmpty) return null;

      // Pick the row whose time_sec is closest to hitSec.
      List<String>? best;
      double bestDt = double.infinity;
      for (int i = 1; i < lines.length; i++) {
        final cols = lines[i].split(',');
        if (cols.length <= timeIdx) continue;
        final t = double.tryParse(cols[timeIdx].trim());
        if (t == null) continue;
        final dt = (t - hitSec).abs();
        if (dt < bestDt) { bestDt = dt; best = cols; }
      }
      if (best == null) return null;

      // Body bbox from visible landmarks (DISPLAY space).
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      int used = 0;
      lm.forEach((n, idx) {
        if (idx.x >= best!.length || idx.y >= best.length) return;
        final x = double.tryParse(best[idx.x].trim());
        final y = double.tryParse(best[idx.y].trim());
        if (x == null || y == null) return;
        if (idx.vis >= 0 && idx.vis < best.length) {
          final v = double.tryParse(best[idx.vis].trim());
          if (v != null && v < minVisibility) return;
        }
        minX = math.min(minX, x); maxX = math.max(maxX, x);
        minY = math.min(minY, y); maxY = math.max(maxY, y);
        used++;
      });
      if (used < 4 || !minX.isFinite) return null;

      // Expand by margin (fraction of bbox size).
      final mw = (maxX - minX) * margin, mh = (maxY - minY) * margin;
      final dispW = (rotation == 90 || rotation == 270) ? codedH : codedW;
      final dispH = (rotation == 90 || rotation == 270) ? codedW : codedH;
      final coded = displayBoxToCoded(
        (minX - mw), (minY - mh), (maxX + mw), (maxY + mh),
        dispW, dispH, rotation,
      );
      // Clamp to coded bounds.
      final box = [
        coded[0].clamp(0, codedW - 1),
        coded[1].clamp(0, codedH - 1),
        coded[2].clamp(0, codedW - 1),
        coded[3].clamp(0, codedH - 1),
      ];
      debugPrint('$_tag hit=$hitSec dt=${bestDt.toStringAsFixed(3)}s used=$used '
          'displayBox=[$minX,$minY,$maxX,$maxY] rot=$rotation → coded=$box');
      return box;
    } catch (e) {
      debugPrint('$_tag failed: $e');
      return null;
    }
  }
}
