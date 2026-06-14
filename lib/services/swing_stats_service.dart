import 'dart:math' as math;
import 'dart:ui';

import '../recording/trajectory_painter.dart';

/// 揮桿/球軌跡統計（純計算，無 IO，供播放頁統計面板使用）。
///
/// 注意：軌跡只有像素座標、無實際尺度，因此不提供球速 km/h——
/// 只計算幾何上可靠的指標（發射角、飛行時間、揮桿節奏）。
class SwingStats {
  /// 發射角（度，0 = 水平，正值 = 向上）；軌跡點不足時為 null
  final double? launchAngleDeg;

  /// 球在畫面內的飛行時間（秒）；無軌跡時為 null
  final double? flightTimeSec;

  /// 軌跡點數
  final int trajectoryPointCount;

  /// 上桿時間（takeaway → top，秒）
  final double? backswingSec;

  /// 下桿時間（top → impact，秒）
  final double? downswingSec;

  /// 節奏比（上桿:下桿，職業選手約 3.0）
  final double? tempoRatio;

  /// 節奏比是否落在合理區間（2:1~4:1）；false = 數值可疑（偵測雜訊/極端），UI 標低信心
  final bool tempoConfident;

  const SwingStats({
    this.launchAngleDeg,
    this.flightTimeSec,
    this.trajectoryPointCount = 0,
    this.backswingSec,
    this.downswingSec,
    this.tempoRatio,
    this.tempoConfident = true,
  });

  bool get hasTrajectoryStats => launchAngleDeg != null || flightTimeSec != null;
  bool get hasTempoStats => tempoRatio != null;
  bool get isEmpty => !hasTrajectoryStats && !hasTempoStats && trajectoryPointCount == 0;

  static SwingStats compute({
    TrajectoryTrack? track,
    Map<String, double>? phases,
  }) {
    final (angle, flight, count) = _trajectoryStats(track);
    final (back, down, tempo, tempoOk) = _tempoStats(phases);
    return SwingStats(
      launchAngleDeg: angle,
      flightTimeSec: flight,
      trajectoryPointCount: count,
      backswingSec: back,
      downswingSec: down,
      tempoRatio: tempo,
      tempoConfident: tempoOk,
    );
  }

  /// 發射角：取起飛後最初 ~5 點做線性擬合（display 空間，y 軸向下故取負）。
  /// 像素為非等向性（寬高比不影響角度——同一空間下 dx/dy 同尺度）。
  static (double?, double?, int) _trajectoryStats(TrajectoryTrack? track) {
    if (track == null || track.points.length < 2) {
      return (null, null, track?.points.length ?? 0);
    }
    final pts = track.points;
    final flight = (pts.last.ptsUs - pts.first.ptsUs) / 1e6;

    // display 空間像素座標（套用 rotation，免得直片角度算錯）
    final display = pts
        .take(5)
        .map((p) {
          final n = track.normalizedDisplay(p);
          return Offset(n.dx * track.displayW, n.dy * track.displayH);
        })
        .toList();

    // 最小平方法擬合 dy/dx；垂直軌跡（dx≈0）回傳 ±90
    final n = display.length;
    final meanX = display.map((o) => o.dx).reduce((a, b) => a + b) / n;
    final meanY = display.map((o) => o.dy).reduce((a, b) => a + b) / n;
    double sxx = 0, sxy = 0;
    for (final o in display) {
      sxx += (o.dx - meanX) * (o.dx - meanX);
      sxy += (o.dx - meanX) * (o.dy - meanY);
    }
    double angleDeg;
    if (sxx < 1e-6) {
      angleDeg = display.last.dy < display.first.dy ? 90 : -90;
    } else {
      // y 向下為正 → 向上飛行斜率為負，取負轉成「向上為正」
      angleDeg = math.atan2(-sxy / sxx, 1) * 180 / math.pi;
      // 軌跡向左飛（dx 遞減）時，atan 斜率方向相反，需翻轉
      if (display.last.dx < display.first.dx) angleDeg = -angleDeg;
    }
    return (angleDeg, flight, pts.length);
  }

  static (double?, double?, double?, bool) _tempoStats(Map<String, double>? phases) {
    if (phases == null) return (null, null, null, true);
    final takeaway = phases['takeaway'];
    final top      = phases['top'];
    final impact   = phases['impact'];

    final back = (takeaway != null && top != null && top > takeaway)
        ? top - takeaway
        : null;
    final down = (top != null && impact != null && impact > top)
        ? impact - top
        : null;
    final tempo = (back != null && down != null && down > 0.05)
        ? back / down
        : null;
    // 合理節奏比 2:1~4:1；超出視為偵測雜訊/極端 → 標低信心（UI 加「?」）
    final tempoOk = tempo == null || (tempo >= 2.0 && tempo <= 4.0);
    return (back, down, tempo, tempoOk);
  }
}
