import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'ball_tracker.dart';
import 'detection_config.dart';

class EnhancedBallTracker {
  final double dt;

  // ROI 配置常數（與 TrajectoryOverlayRenderer.kt 同步，用於 calculateRoiBounds 測試）
  static const double ROI_X_FRAC = 0.6519;
  static const double ROI_Y_FRAC = 0.5646;

  // 每幀追蹤基準 ROI 尺寸（對應 1080×1920 原始解析度）
  static const int baseRoiSize = 400;

  // P1 必須在 P0 後 N 幀內出現，否則重置追蹤
  static const int _p1DeadlineFrames = 5;

  late Kalman2D kalman;
  final TrackingConfigManager configManager = TrackingConfigManager();
  final List<TrackPoint> trackPoints = [];

  int noCandCount = 0;
  int outlierStrikes = 0;
  bool trackingFrozen = false;
  int? _yDir;
  int? _p0FrameIdx;

  EnhancedBallTracker({required this.dt}) {
    kalman = Kalman2D(dt: dt);
  }

  void reset() {
    trackPoints.clear();
    kalman = Kalman2D(dt: dt);
    configManager.reset();
    noCandCount = 0;
    outlierStrikes = 0;
    trackingFrozen = false;
    _yDir = null;
    _p0FrameIdx = null;
  }

  // ── 核心：逐幀追蹤 ──────────────────────────────────────────

  /// 處理單幀 blob 資料。回傳 false 表示追蹤已凍結（呼叫方應停止迴圈）。
  bool processFrame(
    FrameBlobs frame,
    int frameIdx, {
    required int videoW,
    required int videoH,
  }) {
    // 1. Kalman 預測（P2+）
    if (trackPoints.length >= 2) predictKalman();

    // 2. P1 期限：若 P0 後超過 _p1DeadlineFrames 幀未找到 P1，重置
    if (trackPoints.length == 1 &&
        _p0FrameIdx != null &&
        (frameIdx - _p0FrameIdx!) > _p1DeadlineFrames) {
      reset();
    }

    // 3. 建立候選列表
    var candidates = frame.blobs
        .map((b) => Offset(b.cx.toDouble(), b.cy.toDouble()))
        .toList();

    if (candidates.isEmpty) {
      recordNoCandidate();
      return true;
    }
    recordFoundCandidates();

    // 4. P0 確定後以 Kalman 預測（或上一點）為中心做 ROI 過濾
    if (trackPoints.isNotEmpty) {
      final roiHalf = getDynamicRoiSize(
            baseRoiSize,
            videoW: videoW,
            videoH: videoH,
          ) /
          2.0;
      final roiCenter = isKalmanInitialized
          ? Offset(getKalmanPos().$1, getKalmanPos().$2)
          : Offset(trackPoints.last.x.toDouble(), trackPoints.last.y.toDouble());
      candidates = candidates
          .where((c) =>
              (c.dx - roiCenter.dx).abs() <= roiHalf &&
              (c.dy - roiCenter.dy).abs() <= roiHalf)
          .toList();
    }

    if (candidates.isEmpty) {
      recordNoCandidate();
      return true;
    }

    // 5. 步距衛士
    candidates = candidates.where(stepDistanceGuardCheck).toList();

    // 6. Y 方向約束
    candidates = filterByYDirection(candidates);

    if (candidates.isEmpty) {
      return !handleOutlierDetection(); // false = frozen → 停止迴圈
    }

    // 7. 選取最佳候選
    final best = _selectBestCandidate(candidates, frame);

    // 8. 更新面積 EMA
    if (frame.blobs.isNotEmpty) updateAreaEmaFromBlob(frame.blobs.first.area);

    // 9. 新增追蹤點
    if (trackPoints.isEmpty) {
      _p0FrameIdx = frameIdx;
      addTrackPoint(best.dx.toInt(), best.dy.toInt(), frameIdx, frame.ptsUs);
    } else if (trackPoints.length == 1) {
      _p0FrameIdx = null;
      initKalman(
        trackPoints[0].x.toDouble(),
        trackPoints[0].y.toDouble(),
        best.dx,
        best.dy,
      );
      addTrackPoint(best.dx.toInt(), best.dy.toInt(), frameIdx, frame.ptsUs);
    } else {
      updateKalman(best.dx, best.dy);
      addTrackPoint(best.dx.toInt(), best.dy.toInt(), frameIdx, frame.ptsUs);
    }

    return true;
  }

  Offset _selectBestCandidate(List<Offset> candidates, FrameBlobs frame) {
    if (isKalmanInitialized) {
      final pos = getKalmanPos();
      final kalmanPt = Offset(pos.$1, pos.$2);
      return candidates.reduce((a, b) =>
          distance(a, kalmanPt) <= distance(b, kalmanPt) ? a : b);
    }
    if (trackPoints.length == 1) {
      final p0 = Offset(
          trackPoints[0].x.toDouble(), trackPoints[0].y.toDouble());
      return candidates.reduce(
          (a, b) => distance(a, p0) <= distance(b, p0) ? a : b);
    }
    // P0: 面積最小的 blob 最像球體
    final smallest =
        frame.blobs.reduce((a, b) => a.area <= b.area ? a : b);
    return Offset(smallest.cx.toDouble(), smallest.cy.toDouble());
  }

  // ── 步距衛士 ─────────────────────────────────────────────────

  static double distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool stepDistanceGuardCheck(Offset candidate) {
    if (trackPoints.isEmpty) return true;

    final lastPt =
        Offset(trackPoints.last.x.toDouble(), trackPoints.last.y.toDouble());
    final step = distance(candidate, lastPt);

    double baseLim = BaseDetectionConfig.STEP_ABS_MAX;
    if (configManager.stepEma != null) {
      baseLim = math.max(
        BaseDetectionConfig.STEP_ABS_MAX,
        configManager.stepEma! * BaseDetectionConfig.STEP_GROWTH_FACTOR,
      );
    }

    final limit = baseLim * (1.0 + 0.35 * noCandCount);
    final hardLimit = math.min(130.0, limit);
    final accepted = step < hardLimit;

    if (accepted) configManager.updateStepEma(step);
    return accepted;
  }

  // ── Y 方向約束 ───────────────────────────────────────────────

  List<Offset> filterByYDirection(List<Offset> candidates) {
    if (_yDir == null) {
      if (trackPoints.length >= 3) {
        final dy = trackPoints[2].y - trackPoints[0].y;
        if (dy.abs() >= 2) _yDir = dy > 0 ? 1 : -1;
      }
      return candidates;
    }

    if (trackPoints.isEmpty) return candidates;

    final lastPt = trackPoints.last;
    const yTol = 1;
    const yMaxStep = 80;

    return candidates.where((c) {
      final dy = (c.dy - lastPt.y).toInt();
      if (_yDir == -1 && c.dy > lastPt.y + yTol) return false;
      if (_yDir == 1 && c.dy < lastPt.y - yTol) return false;
      return dy.abs() <= yMaxStep;
    }).toList();
  }

  // ── 異常值偵測 ───────────────────────────────────────────────

  /// 記錄異常並在達到閾值時凍結追蹤。回傳 true 表示追蹤已凍結。
  bool handleOutlierDetection() {
    outlierStrikes++;
    if (outlierStrikes >= 8 && trackPoints.length >= 8) {
      trackingFrozen = true;
    }
    return trackingFrozen;
  }

  // ── 計數器 ───────────────────────────────────────────────────

  void recordNoCandidate() => noCandCount++;
  void recordFoundCandidates() => noCandCount = 0;

  // ── 追蹤點管理 ───────────────────────────────────────────────

  void addTrackPoint(int x, int y, int frameIdx, int ptsUs) {
    trackPoints.add(TrackPoint(x: x, y: y, frameIdx: frameIdx, ptsUs: ptsUs));
    outlierStrikes = 0;
    trackingFrozen = false; // 新有效點解除凍結
  }

  void updateAreaEmaFromBlob(int area) {
    configManager.updateAreaEma(area.toDouble());
  }

  // ── ROI 計算 ─────────────────────────────────────────────────

  /// 動態 ROI 尺寸：根據視頻解析度縮放基準 ROI，並隨 noCandCount 擴大搜尋範圍。
  int getDynamicRoiSize(
    int baseSize, {
    int videoW = 1080,
    int videoH = 1920,
  }) {
    final base = (baseSize * getResolutionScaleFactor(videoW, videoH)).toInt();
    if (noCandCount <= 0) return base;
    if (noCandCount == 1) return (base * 1.2).toInt();
    if (noCandCount == 2) return (base * 1.4).toInt();
    final m = math.min(1.5 + (noCandCount - 3) * 0.1, 1.8);
    return (base * m).toInt();
  }

  static double getResolutionScaleFactor(int videoW, int videoH) {
    return math.min(videoW / 1080.0, videoH / 1920.0);
  }

  /// ROI 邊界框（以 ROI_X_FRAC / ROI_Y_FRAC 為中心）。主要供測試使用。
  (double, double, double, double) calculateRoiBounds({
    required int videoW,
    required int videoH,
    int roiSize = 0,
  }) {
    final cx = videoW * ROI_X_FRAC;
    final cy = videoH * ROI_Y_FRAC;
    final size = roiSize > 0
        ? roiSize.toDouble()
        : 400.0 * getResolutionScaleFactor(videoW, videoH);
    final half = size / 2;
    return (
      (cx - half).clamp(0.0, (videoW - 1).toDouble()),
      (cy - half).clamp(0.0, (videoH - 1).toDouble()),
      (cx + half).clamp(0.0, (videoW - 1).toDouble()),
      (cy + half).clamp(0.0, (videoH - 1).toDouble()),
    );
  }

  bool isPointInRoi({
    required int x,
    required int y,
    required int videoW,
    required int videoH,
    int roiSize = 0,
  }) {
    final (l, t, r, b) =
        calculateRoiBounds(videoW: videoW, videoH: videoH, roiSize: roiSize);
    return x >= l && x <= r && y >= t && y <= b;
  }

  // ── Kalman 代理 ──────────────────────────────────────────────

  void initKalman(double p0x, double p0y, double p1x, double p1y) =>
      kalman.initFromPoints(p0x, p0y, p1x, p1y);

  void predictKalman() => kalman.predict();

  void updateKalman(double zx, double zy) => kalman.update(zx, zy);

  (double, double) getKalmanPos() => kalman.pos;

  bool get isKalmanInitialized => kalman.initialized;
}
