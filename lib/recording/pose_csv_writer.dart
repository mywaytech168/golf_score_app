import 'dart:io';
import 'package:csv/csv.dart';
import 'pose_frame_model.dart';

class PoseCsvWriter {
  final String outputPath;
  final List<List<dynamic>> _rows = [];

  PoseCsvWriter(this.outputPath);

  static List<String> get header {
    final h = ['frame', 'time_sec'];
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

  void addFrame(PoseFrameModel frame) => _rows.add(frame.toCsvRow());

  Future<void> flush() async {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final csv = const ListToCsvConverter().convert([header, ..._rows]);
    await file.writeAsString(csv);
  }
}
