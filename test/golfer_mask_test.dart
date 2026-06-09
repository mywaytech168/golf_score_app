import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/services/golfer_mask.dart';

void main() {
  group('displayBoxToCoded', () {
    // Display box for a portrait video (dispW=1080, dispH=1920).
    // Box near the left-center golfer: x[100..400], y[500..1500].
    const dx1 = 100.0, dy1 = 500.0, dx2 = 400.0, dy2 = 1500.0;

    test('rotation 0 = identity', () {
      final b = GolferMask.displayBoxToCoded(dx1, dy1, dx2, dy2, 1080, 1920, 0);
      expect(b, [100, 500, 400, 1500]);
    });

    test('rotation 90 maps display→coded and stays in coded bounds (1920x1080)', () {
      // codedW=dispH=1920, codedH=dispW=1080
      final b = GolferMask.displayBoxToCoded(dx1, dy1, dx2, dy2, 1080, 1920, 90);
      // x' = y  -> [500,1500];  y' = (1080-1)-x -> from 400->679, 100->979
      expect(b, [500, 679, 1500, 979]);
      expect(b[0] >= 0 && b[2] <= 1920, isTrue);
      expect(b[1] >= 0 && b[3] <= 1080, isTrue);
    });

    test('rotation 180 flips both axes', () {
      final b = GolferMask.displayBoxToCoded(dx1, dy1, dx2, dy2, 1080, 1920, 180);
      // x' = 1079-x, y' = 1919-y
      expect(b, [679, 419, 979, 1419]);
    });

    test('rotation 270 maps display→coded', () {
      final b = GolferMask.displayBoxToCoded(dx1, dy1, dx2, dy2, 1080, 1920, 270);
      // x' = (1920-1)-y -> from 1500->419, 500->1419; y' = x -> [100,400]
      expect(b, [419, 100, 1419, 400]);
      expect(b[0] >= 0 && b[2] <= 1920, isTrue);
      expect(b[1] >= 0 && b[3] <= 1080, isTrue);
    });

    test('round-trip area is preserved (rotation 90)', () {
      final b = GolferMask.displayBoxToCoded(dx1, dy1, dx2, dy2, 1080, 1920, 90);
      final wDisp = (dx2 - dx1), hDisp = (dy2 - dy1);
      final wCoded = (b[2] - b[0]).toDouble(), hCoded = (b[3] - b[1]).toDouble();
      // 90° swaps width/height
      expect((wCoded - hDisp).abs() <= 1, isTrue);
      expect((hCoded - wDisp).abs() <= 1, isTrue);
    });
  });
}
