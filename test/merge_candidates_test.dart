import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/services/swing_auto_clip_service.dart';

void main() {
  group('mergeCandidates 骨架為主、音訊精修', () {
    test('live impact 附近有音訊峰值 → 取峰值時間（fromAudio=true）', () {
      final out = SwingAutoClipService.mergeCandidates(
        audioPeaks: [77.495],
        liveImpacts: [78.473], // 腕速偵測晚 ~1 秒
      );
      expect(out.length, 1);
      expect(out.first.sec, 77.495);
      expect(out.first.fromAudio, isTrue);
    });

    test('純環境音峰值（附近無 live impact）不成桿', () {
      final out = SwingAutoClipService.mergeCandidates(
        // 187~198 一串為隔壁打位擊球聲（真實錄影觀測）
        audioPeaks: [187.675, 190.425, 193.065, 197.925],
        liveImpacts: [203.626],
      );
      expect(out.length, 1);
      expect(out.first.sec, 203.626);
      expect(out.first.fromAudio, isFalse);
    });

    test('窗口不對稱：峰值最多早 4 秒、晚 1 秒', () {
      // 早 3.9s → 配對；晚 1.5s → 不配對
      final early = SwingAutoClipService.mergeCandidates(
        audioPeaks: [96.1],
        liveImpacts: [100.0],
      );
      expect(early.first.sec, 96.1);
      final late = SwingAutoClipService.mergeCandidates(
        audioPeaks: [101.5],
        liveImpacts: [100.0],
      );
      expect(late.first.sec, 100.0);
      expect(late.first.fromAudio, isFalse);
    });

    test('無 live impacts（匯入影片）→ 退回音訊峰值', () {
      final out = SwingAutoClipService.mergeCandidates(
        audioPeaks: [5.0, 12.0],
        liveImpacts: [],
      );
      expect(out.length, 2);
      expect(out.every((c) => c.fromAudio), isTrue);
    });

    test('兩個 live impact 精修到同一峰值 → 去重保留前者', () {
      final out = SwingAutoClipService.mergeCandidates(
        audioPeaks: [50.0],
        liveImpacts: [50.5, 51.0],
      );
      expect(out.length, 1);
      expect(out.first.sec, 50.0);
    });

    test('真實錄影回歸：22 桿 + 17 峰值（含環境音）→ 22 桿，不爆量', () {
      // 2026-06-12 後鏡頭錄製模式實測數據（原邏輯產出 33 個候選）
      final audio = [
        2315, 77495, 99865, 110585, 130985, 134515, 151185, 169705, 181045,
        187675, 190425, 193065, 197925, 209235, 214505, 216915, 222195,
      ].map((ms) => ms / 1000.0).toList();
      final live = [
        10.365, 19.995, 25.359, 34.489, 42.72, 48.051, 62.545, 78.473,
        85.004, 91.168, 98.765, 105.363, 117.158, 124.789, 140.283, 146.414,
        155.91, 170.038, 178.102, 203.626, 212.022, 222.952,
      ];
      final out = SwingAutoClipService.mergeCandidates(
        audioPeaks: audio,
        liveImpacts: live,
      );
      // 桿數以骨架為準：22 桿（去重後容許略少，但絕不能超過）
      expect(out.length, lessThanOrEqualTo(22));
      expect(out.length, greaterThanOrEqualTo(20));
      // 開頭 2.3s 與 187~198 環境音串不得成桿
      expect(out.any((c) => c.sec < 5.0), isFalse);
      expect(
        out.where((c) => c.sec >= 185.0 && c.sec <= 199.0).length,
        0,
      );
    });
  });
}
