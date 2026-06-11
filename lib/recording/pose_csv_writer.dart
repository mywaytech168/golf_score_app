import 'dart:io';
import 'package:csv/csv.dart';
import 'pose_frame_model.dart';

class PoseCsvWriter {
  final String outputPath;
  final List<List<dynamic>> _rows = [];

  PoseCsvWriter(this.outputPath);

  static List<String> get header {
    final h = ['frame', 'time_sec', 'pose_update_id'];  // ✅ 新增
    for (int i = 0; i < 33; i++) {
      h.addAll([
        'lm${i}_x_norm',
        'lm${i}_y_norm',
        'lm${i}_z',
        'lm${i}_visibility',
        'lm${i}_x_px',
        'lm${i}_y_px',
      ]);
    }
    return h;
  }

  /// CSV 對時偏移（秒）：影片 t=0（第一個編碼幀）晚於 rec.start() 的量。
  /// flush 時整體前移，使 CSV 時鐘與影片時鐘一致（負值幀剔除）。
  double timeOffsetSec = 0.0;

  void addFrame(PoseFrameModel frame) => _rows.add(frame.toCsvRow());

  Future<void> flush() async {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    var rows = _rows;
    if (timeOffsetSec != 0.0) {
      rows = [];
      for (final r in _rows) {
        final t = double.tryParse(r[1] as String) ?? 0.0;
        final shifted = t - timeOffsetSec;
        if (shifted < -0.05) continue; // 影片開始前的幀直接剔除
        rows.add([r[0], shifted.clamp(0.0, double.infinity).toStringAsFixed(6), ...r.sublist(2)]);
      }
    }
    final csv = const ListToCsvConverter().convert([header, ...rows]);
    await file.writeAsString(csv);
  }
}
