// Verifies the p0-SAHI fusion seam: when a YOLO seed P0 is supplied, BallTracker
// seeds P0 at the seed location (no frame-diff p0 search) and then tracks the flight
// from the moving blobs. Pure Dart, runnable with `flutter test`.
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/services/ball_tracker.dart';

void main() {
  // coded space 1920x1080, 30 fps. Impact ~ frame 6.
  const int videoW = 1920, videoH = 1080, fps = 30;
  const double hitSec = 6 / 30; // hitFrame = 6
  const int seedX = 900, seedY = 560, seedFrame = 6;

  BlobData ball(int x, int y) =>
      BlobData(cx: x, cy: y, area: 40, circ: 0.7, diffMean: 60);

  /// Build frames: NO static ball at the tee (diff can't see it), only a moving
  /// ball appears AFTER impact as a clean rising parabola near the seed.
  List<FrameBlobs> buildFrames() {
    final frames = <FrameBlobs>[];
    for (int f = 0; f < 22; f++) {
      final blobs = <BlobData>[];
      if (f > seedFrame && f <= seedFrame + 10) {
        final k = f - seedFrame; // 1..10
        final x = seedX - 4 * k;
        final y = (seedY - 70 * k + 2 * k * k).round();
        blobs.add(ball(x, y));
      }
      frames.add(FrameBlobs(ptsUs: f * 33333, blobs: blobs));
    }
    return frames;
  }

  test('without seed: no static ball → no usable track', () {
    final trail = BallTracker().track(
      frames: buildFrames(), fps: fps.toDouble(),
      videoW: videoW, videoH: videoH, rotation: 90, hitSec: hitSec,
    );
    // diff never sees a static p0 at the tee, so it cannot anchor reliably.
    expect(trail.length, lessThan(3));
  });

  test('with YOLO seed: p0 seeded, flight tracked from moving blobs', () {
    final trail = BallTracker().track(
      frames: buildFrames(), fps: fps.toDouble(),
      videoW: videoW, videoH: videoH, rotation: 90, hitSec: hitSec,
      seedP0X: seedX, seedP0Y: seedY, seedP0Frame: seedFrame,
    );
    expect(trail.length, greaterThanOrEqualTo(3), reason: 'should track the flight');
    // First point is the seeded P0 (raw coords preserved).
    expect(trail.first.rawX, seedX);
    expect(trail.first.rawY, seedY);
    // Trajectory climbs (y decreases) — it followed the ball, not noise.
    expect(trail.last.rawY, lessThan(trail.first.rawY));
  });
}
