import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import 'skeleton_csv_locator.dart';

/// 圖表用單點資料（x = 時間秒, y = 數值）
class ChartPoint {
  final double x;
  final double y;
  const ChartPoint(this.x, this.y);
}

/// 三張圖表的完整資料集
class ChartDataSet {
  final List<ChartPoint> audioRms;   // 聲音峰值 (rms_dbfs)
  final List<ChartPoint> wristY;     // 手腕 Y (lm16_y_px, 螢幕座標)
  final List<ChartPoint> wristSpeed; // 手腕速度 (pixel/frame)

  const ChartDataSet({
    required this.audioRms,
    required this.wristY,
    required this.wristSpeed,
  });

  bool get isEmpty =>
      audioRms.isEmpty && wristY.isEmpty && wristSpeed.isEmpty;
}

/// 解析 CSV 並計算圖表數據
class ChartDataService {
  static const _tag = '[ChartData]';

  static Future<ChartDataSet> loadFromEntry(RecordingHistoryEntry entry) async {
    final sessionDir = p.dirname(entry.filePath);
    final audioCsvPath = '$sessionDir/audio_features.csv';
    // 逐幀 CSV 優先；背景分析未完成時退回 live CSV（低取樣，曲線較疏但可看）
    final poseCsvPath  = resolveSkeletonCsv(sessionDir) ?? '$sessionDir/pose_landmarks.csv';

    final audioFuture = _parseAudioCsv(audioCsvPath);
    final poseFuture  = _parsePoseCsv(poseCsvPath);

    final audio = await audioFuture;
    final pose  = await poseFuture;
    final wristY = pose[0];
    final speed  = pose[1];

    return ChartDataSet(audioRms: audio, wristY: wristY, wristSpeed: speed);
  }

  // ── 解析 audio_features.csv ─────────────────────────────────

  static Future<List<ChartPoint>> _parseAudioCsv(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('$_tag audio CSV 不存在: $path');
        return [];
      }

      final lines = await file.readAsLines();
      if (lines.length < 2) return [];

      // 找欄位 index
      final headers = lines[0].split(',');
      final timeIdx = headers.indexOf('time_sec');
      final rmsIdx  = headers.indexOf('rms_dbfs');
      if (timeIdx < 0 || rmsIdx < 0) {
        debugPrint('$_tag audio CSV 缺少必要欄位');
        return [];
      }

      final points = <ChartPoint>[];
      for (int i = 1; i < lines.length; i++) {
        final cols = lines[i].split(',');
        if (cols.length <= max(timeIdx, rmsIdx)) continue;
        final t = double.tryParse(cols[timeIdx].trim());
        final y = double.tryParse(cols[rmsIdx].trim());
        if (t == null || y == null) continue;
        // rms_dbfs 通常為負值（-60 ~ 0），轉為正值方便顯示
        points.add(ChartPoint(t, y));
      }

      debugPrint('$_tag audio: ${points.length} 點');
      return points;
    } catch (e) {
      debugPrint('$_tag audio CSV 解析失敗: $e');
      return [];
    }
  }

  // ── 解析 pose_landmarks.csv → 手腕 Y + 速度 ─────────────────

  static Future<List<List<ChartPoint>>> _parsePoseCsv(String path) async {
    final empty = [<ChartPoint>[], <ChartPoint>[]];
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('$_tag pose CSV 不存在: $path');
        return empty;
      }

      final lines = await file.readAsLines();
      if (lines.length < 2) {
        debugPrint('$_tag pose CSV 行數不足: ${lines.length} < 2');
        return empty;
      }

      final headers = lines[0].split(',');
      final timeIdx = headers.indexOf('time_sec');
      // 右手腕 landmark 16 的 y_px 和 x_px
      final ywIdx = headers.indexOf('lm16_y_px');
      final xwIdx = headers.indexOf('lm16_x_px');
      final visIdx = headers.indexOf('lm16_visibility');

      // ✅ 診斷：顯示實際的 header
      debugPrint('$_tag pose CSV header 數量: ${headers.length}');
      debugPrint('$_tag pose CSV 字段位置: timeIdx=$timeIdx, ywIdx=$ywIdx, xwIdx=$xwIdx, visIdx=$visIdx');
      if (timeIdx < 0 || ywIdx < 0 || xwIdx < 0) {
        debugPrint('$_tag pose CSV 缺少手腕欄位');
        debugPrint('$_tag 預期欄位: time_sec, lm16_y_px, lm16_x_px');
        debugPrint('$_tag 實際 header: ${headers.join(", ")}');
        return empty;
      }

      final wristY  = <ChartPoint>[];
      final speedPts = <ChartPoint>[];

      double? prevX, prevY;
      int validRows = 0;
      int skippedRows = 0;

      for (int i = 1; i < lines.length; i++) {
        final cols = lines[i].split(',');
        final maxIdx = [timeIdx, ywIdx, xwIdx, visIdx].reduce(max);
        if (cols.length <= maxIdx) {
          skippedRows++;
          continue;
        }

        final t   = double.tryParse(cols[timeIdx].trim());
        final yw  = double.tryParse(cols[ywIdx].trim());
        final xw  = double.tryParse(cols[xwIdx].trim());
        final vis = visIdx >= 0 && visIdx < cols.length
            ? double.tryParse(cols[visIdx].trim())
            : null;

        // ✅ 跳過無效或低信心的數據
        if (t == null || yw == null || xw == null) {
          skippedRows++;
          continue;
        }
        // ✅ 跳過低可見度或全零坐標（未檢測）
        if (vis != null && vis < 0.1) {
          skippedRows++;
          continue;
        }
        if ((yw == 0.0 && xw == 0.0) && vis != null && vis > 0) {
          // 非零可見度但座標為 0，這通常表示檢測失敗
          skippedRows++;
          continue;
        }

        validRows++;
        wristY.add(ChartPoint(t, yw));

        if (prevX != null && prevY != null) {
          final dx = xw - prevX;
          final dy = yw - prevY;
          final spd = sqrt(dx * dx + dy * dy);
          speedPts.add(ChartPoint(t, spd));
        }
        prevX = xw;
        prevY = yw;
      }

      debugPrint('$_tag pose: wristY=${wristY.length}, speed=${speedPts.length}, validRows=$validRows, skipped=$skippedRows');
      return [wristY, speedPts];
    } catch (e) {
      debugPrint('$_tag pose CSV 解析失敗: $e');
      return empty;
    }
  }
}
