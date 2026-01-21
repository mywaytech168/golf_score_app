import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

/// Result for each generated swing clip.
class SwingClipResult {
  final String tag;
  final double hitSecond;
  final double startSecond;
  final double endSecond;
  final double peakValue;
  final String videoPath;
  final String csvPath;
  final bool goodShot;
  final bool badShot;
  final double maxAcceleration;
  final double avgAcceleration;

  SwingClipResult({
    required this.tag,
    required this.hitSecond,
    required this.startSecond,
    required this.endSecond,
    required this.peakValue,
    required this.videoPath,
    required this.csvPath,
    required this.goodShot,
    required this.badShot,
    required this.maxAcceleration,
    required this.avgAcceleration,
  });
}

/// Pure Dart swing splitter: parse IMU CSV, detect peaks, and cut video/CSV (no ffmpeg dependency).
class SwingSplitService {
  static const MethodChannel _trimChannel =
      MethodChannel('com.example.golf_score_app/trimmer');
  static const double _defaultWindowBefore = 3.0;
  static const double _defaultWindowAfter = 1.0;
  static const double _defaultSmoothWinSec = 0.05;
  static const double _defaultThreshG = 20.0;
  static const double _defaultMinInterval = 1.0;
  static const String _defaultOutDirName = 'cut';

  static Future<List<SwingClipResult>> split({
    required String videoPath,
    required String imuCsvPath,
    double windowBeforeSec = _defaultWindowBefore,
    double windowAfterSec = _defaultWindowAfter,
    double smoothWinSec = _defaultSmoothWinSec,
    double threshG = _defaultThreshG,
    double minIntervalSec = _defaultMinInterval,
    double? prominenceG,
    String outDirName = _defaultOutDirName,
    bool forceSar1 = true,
    int? memberId,
    String apiBase = 'http://192.168.0.232:8000',
  }) async {
    final File csvFile = File(imuCsvPath);
    final File videoFile = File(videoPath);
    if (!await csvFile.exists()) {
      throw ArgumentError('IMU CSV not found: $imuCsvPath');
    }
    if (!await videoFile.exists()) {
      throw ArgumentError('Video not found: $videoPath');
    }

    final _ImuSeries series = await _loadImu(csvFile);
    final List<_Peak> peaks = _detectPeaks(
      series,
      smoothWinSec: smoothWinSec,
      threshG: threshG,
      minIntervalSec: minIntervalSec,
      prominenceG: prominenceG,
    );
    if (peaks.isEmpty) return const [];

    final Directory outDir = await _makeUniqueOutDir(
      Directory(p.dirname(videoPath)),
      outDirName,
    );

    final double? videoDuration = await _getVideoDuration(videoPath);
    final List<SwingClipResult> results = [];

    for (int i = 0; i < peaks.length; i++) {
      final _Peak pk = peaks[i];
      final double start = math.max(0.0, pk.time - windowBeforeSec);
      final double end = videoDuration != null
          ? math.min(videoDuration, pk.time + windowAfterSec)
          : pk.time + windowAfterSec;
      final String tag = 'hit_${(i + 1).toString().padLeft(3, '0')}';
      final String clipPath = p.join(outDir.path, '$tag.mp4');
      final String clipCsv = p.join(outDir.path, '${tag}_imu.csv');

      await _cutVideo(
        src: videoPath,
        dst: clipPath,
        start: start,
        end: end,
        forceSar1: forceSar1,
      );
      await _writeCsvSegment(series, clipCsv, start, end, pk.time);

      // 計算時間區段內的最大 / 平均加速度（使用 |acc| 而非單軸）
      final List<double> windowMag = [];
      for (int j = 0; j < series.time.length; j++) {
        final t = series.time[j];
        if (t < start || t > end) continue;
        final mag = math.sqrt(series.ax[j] * series.ax[j] +
            series.ay[j] * series.ay[j] +
            series.az[j] * series.az[j]);
        windowMag.add(mag);
      }
      final double maxAccel = windowMag.isEmpty ? 0 : windowMag.reduce(math.max);
      final double avgAccel =
          windowMag.isEmpty ? 0 : windowMag.reduce((a, b) => a + b) / windowMag.length;

      results.add(
        SwingClipResult(
          tag: tag,
          hitSecond: pk.time,
          startSecond: start,
          endSecond: end,
          peakValue: pk.value,
          videoPath: clipPath,
          csvPath: clipCsv,
          goodShot: pk.value > 30.0, // Example threshold for good shot
          badShot: pk.value < 10.0, // Example threshold for bad shot
          maxAcceleration: maxAccel,
          avgAcceleration: avgAccel,
        ),
      );

      // 將結果同步到後端
      if (memberId != null) {
        final label = pk.value >= 30
            ? 'good'
            : pk.value <= 10
                ? 'bad'
                : 'unknown';
        final payload = {
          'memberId': memberId,
          'videoPath': clipPath,
          'label': label,
          'avgSpeedMph': null,
          'maxAcceleration': maxAccel,
          'avgAcceleration': avgAccel,
          'csvPath': clipCsv,
          'dateTime': DateTime.now().toIso8601String(),
          'extraJson': '{"peak":${pk.value.toStringAsFixed(4)},"hit":${pk.time.toStringAsFixed(4)}}',
        };
        unawaited(_postSwing(apiBase, payload));
      }
    }

    await _writeSummary(results, p.join(outDir.path, 'hits_summary.csv'));
    return results;
  }

  static Future<void> _postSwing(String apiBase, Map<String, dynamic> payload) async {
    try {
      final resp = await http.post(
        Uri.parse('$apiBase/api/Swing/update-or-create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (resp.statusCode != 200) {
        debugPrint('swing sync failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('swing sync exception: $e');
    }
  }

  // ---- IMU parsing / detection ----

  static Future<_ImuSeries> _loadImu(File csvFile) async {
    final List<String> lines = await csvFile.readAsLines();
    int headerIdx = -1;
    List<String> headers = [];
    for (int i = 0; i < lines.length && i < 80; i++) {
      final String line = lines[i].trim();
      if (line.startsWith('ElapsedSec') &&
          line.contains('AccelX') &&
          line.contains('AccelY') &&
          line.contains('AccelZ')) {
        headerIdx = i;
        headers = line.split(',');
        break;
      }
    }
    if (headerIdx == -1) {
      throw StateError('Trim failed: output path is empty.');
    }

    int idxElapsed = headers.indexOf('ElapsedSec');
    int idxAx = headers.indexOf('AccelX');
    int idxAy = headers.indexOf('AccelY');
    int idxAz = headers.indexOf('AccelZ');
    if (idxElapsed < 0 || idxAx < 0 || idxAy < 0 || idxAz < 0) {
      throw StateError('Trim failed: output path is empty.');
    }

    final List<double> t = [];
    final List<double> ax = [];
    final List<double> ay = [];
    final List<double> az = [];

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final List<String> parts = lines[i].split(',');
      if (parts.length <= math.max(idxElapsed, math.max(idxAx, math.max(idxAy, idxAz)))) {
        continue;
      }
      double? e = double.tryParse(parts[idxElapsed].trim());
      double? x = double.tryParse(parts[idxAx].trim());
      double? y = double.tryParse(parts[idxAy].trim());
      double? z = double.tryParse(parts[idxAz].trim());
      if (e == null || x == null || y == null || z == null) continue;
      t.add(e);
      ax.add(x);
      ay.add(y);
      az.add(z);
    }

    if (t.isEmpty) throw StateError('Trim failed: output path is empty.');

    final double t0 = t.first;
    final List<double> tNorm = t.map((v) => v - t0).toList();
    return _ImuSeries(time: tNorm, ax: ax, ay: ay, az: az);
  }

  static List<_Peak> _detectPeaks(
    _ImuSeries s, {
    required double smoothWinSec,
    required double threshG,
    required double minIntervalSec,
    double? prominenceG,
  }) {
    final int n = s.time.length;
    if (n < 3) return const [];

    final double dtEst = (s.time.last - s.time.first) / math.max(1, (n - 1));
    final int win = math.max(1, (smoothWinSec / math.max(1e-6, dtEst)).round());
    final int minDistSamples = math.max(1, (minIntervalSec / math.max(1e-6, dtEst)).round());

    // 取 |acc| 並做居中移動平均，模擬 python 版 rolling(center=True)
    final List<double> mag = List<double>.generate(
        n, (i) => math.sqrt(s.ax[i] * s.ax[i] + s.ay[i] * s.ay[i] + s.az[i] * s.az[i]));
    final List<double> smooth = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final int half = win ~/ 2;
      final int start = math.max(0, i - half);
      final int end = math.min(n - 1, i + half);
      double sum = 0;
      for (int j = start; j <= end; j++) {
        sum += mag[j];
      }
      smooth[i] = sum / (end - start + 1);
    }

    final List<_Peak> peaks = [];
    int lastPeakIdx = -999999;
    for (int i = 1; i < n - 1; i++) {
      final double v = smooth[i];
      if (v < threshG) continue;
      if (v < smooth[i - 1] || v < smooth[i + 1]) continue; // 必須是局部峰
      if (i - lastPeakIdx < minDistSamples) continue;

      if (prominenceG != null) {
        final double leftMin = smooth[math.max(0, i - win)];
        final double rightMin = smooth[math.min(n - 1, i + win)];
        final double prom = v - math.min(leftMin, rightMin);
        if (prom < prominenceG) continue;
      }

      peaks.add(_Peak(time: s.time[i], value: v));
      lastPeakIdx = i;
    }
    peaks.sort((a, b) => a.time.compareTo(b.time));
    return peaks;
  }

  // ---- video helpers ----

  static Future<void> _cutVideo({
    required String src,
    required String dst,
    required double start,
    required double end,
    required bool forceSar1,
  }) async {
    await Directory(p.dirname(dst)).create(recursive: true);
    final int startMs = (start * 1000).round();
    final int endMs = (end * 1000).round();
    try {
      await _trimChannel.invokeMethod<bool>('trim', {
        'srcPath': src,
        'dstPath': dst,
        'startMs': startMs,
        'endMs': endMs,
      });
    } on PlatformException catch (e) {
      // fallback: copy full video to avoid silent failure
      await File(src).copy(dst);
      throw StateError('Video trim failed: ${e.message}');
    }
  }

  static Future<void> _writeCsvSegment(
    _ImuSeries s,
    String dst,
    double start,
    double end,
    double hit,
  ) async {
    final StringBuffer buf = StringBuffer();
    buf.writeln('Time,AccelX,AccelY,AccelZ,Time_rel');
    for (int i = 0; i < s.time.length; i++) {
      final double t = s.time[i];
      if (t < start || t > end) continue;
      buf.writeln(
          '${t.toStringAsFixed(6)},${s.ax[i]},${s.ay[i]},${s.az[i]},${(t - hit).toStringAsFixed(6)}');
    }
    await File(dst).writeAsString(buf.toString());
  }

  static Future<void> _writeSummary(List<SwingClipResult> results, String dst) async {
    final StringBuffer buf = StringBuffer();
    buf.writeln('hit,t_hit,start_t,end_t,peak_smooth,video_path,csv_path,good_shot,bad_shot,max_acceleration,avg_acceleration');
    for (final r in results) {
      buf.writeln(
          '${r.tag},${r.hitSecond.toStringAsFixed(6)},${r.startSecond.toStringAsFixed(6)},${r.endSecond.toStringAsFixed(6)},${r.peakValue.toStringAsFixed(6)},${r.videoPath},${r.csvPath},${r.goodShot},${r.badShot},${r.maxAcceleration.toStringAsFixed(6)},${r.avgAcceleration.toStringAsFixed(6)}');
    }
    await File(dst).writeAsString(buf.toString());
  }

  static Future<Directory> _makeUniqueOutDir(Directory base, String name) async {
    final Directory first = Directory(p.join(base.path, name));
    if (!await first.exists()) {
      await first.create(recursive: true);
      return first;
    }
    if (await first.exists() && await first.list().isEmpty) {
      return first;
    }
    for (int i = 1; i < 100; i++) {
      final Directory cand = Directory(p.join(base.path, '${name}_${i.toString().padLeft(2, '0')}'));
      if (!await cand.exists()) {
        await cand.create(recursive: true);
        return cand;
      }
    }
    final String ts =
        DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '');
    final Directory fallback = Directory(p.join(base.path, '${name}_$ts'));
    await fallback.create(recursive: true);
    return fallback;
  }

  static Future<double?> _getVideoDuration(String path) async {
    try {
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      final seconds = controller.value.duration.inMicroseconds / 1e6;
      await controller.dispose();
      return seconds;
    } catch (_) {
      return null;
    }
  }
}

class _ImuSeries {
  final List<double> time;
  final List<double> ax;
  final List<double> ay;
  final List<double> az;

  _ImuSeries({
    required this.time,
    required this.ax,
    required this.ay,
    required this.az,
  });
}

class _Peak {
  final double time;
  final double value;
  _Peak({required this.time, required this.value});
}
