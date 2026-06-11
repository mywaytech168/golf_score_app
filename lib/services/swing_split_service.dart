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
  final double audioCrispness;

  SwingClipResult({
    required this.tag,
    required this.hitSecond,
    required this.startSecond,
    required this.endSecond,
    required this.peakValue,
    required this.videoPath,
    required this.csvPath,
    required this.goodShot,
    required this.audioCrispness,
  });
}

/// Pure Dart swing splitter: parse IMU CSV, detect peaks, and cut video/CSV (no ffmpeg dependency).
class SwingSplitService {
  static const MethodChannel _trimChannel =
      MethodChannel('com.example.golf_score_app/trimmer');
  static const double _defaultWindowBefore = 3.0;
  static const double _defaultWindowAfter = 3.0;
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
    debugPrint('[SWING_SPLIT] ===== 開始切片流程 =====');
    debugPrint('[SWING_SPLIT] 影片路徑: $videoPath');
    debugPrint('[SWING_SPLIT] IMU CSV 路徑: $imuCsvPath');
    debugPrint('[SWING_SPLIT] 參數設定: 前置=${windowBeforeSec}s, 後置=${windowAfterSec}s, 閾值=${threshG}G, 最小間隔=${minIntervalSec}s');
    
    final File csvFile = File(imuCsvPath);
    final File videoFile = File(videoPath);
    if (!await csvFile.exists()) {
      debugPrint('[SWING_SPLIT] ❌ IMU CSV 不存在: $imuCsvPath');
      throw ArgumentError('IMU CSV not found: $imuCsvPath');
    }
    if (!await videoFile.exists()) {
      debugPrint('[SWING_SPLIT] ❌ 影片文件不存在: $videoPath');
      throw ArgumentError('Video not found: $videoPath');
    }
    debugPrint('[SWING_SPLIT] ✓ 檔案驗證通過');

    debugPrint('[SWING_SPLIT] 正在載入 IMU 數據...');
    final _ImuSeries series = await _loadImu(csvFile);
    debugPrint('[SWING_SPLIT] ✓ IMU 數據已載入: ${series.time.length} 個樣本, 時長 ${series.time.last.toStringAsFixed(2)}s');
    
    debugPrint('[SWING_SPLIT] 正在偵測加速度峰值...');
    final List<_Peak> peaks = _detectPeaks(
      series,
      smoothWinSec: smoothWinSec,
      threshG: threshG,
      minIntervalSec: minIntervalSec,
      prominenceG: prominenceG,
    );
    debugPrint('[SWING_SPLIT] ✓ 偵測完成: 找到 ${peaks.length} 個擊棒');
    for (int i = 0; i < peaks.length; i++) {
      debugPrint('[SWING_SPLIT]   ├─ 擊棒 #${i + 1}: 時刻=${peaks[i].time.toStringAsFixed(3)}s, 峰值=${peaks[i].value.toStringAsFixed(2)}G');
    }
    
    if (peaks.isEmpty) {
      debugPrint('[SWING_SPLIT] ⚠ 未找到任何擊棒，返回空列表');
      return const [];
    }

    final Directory outDir = await _makeUniqueOutDir(
      Directory(p.dirname(videoPath)),
      outDirName,
    );
    debugPrint('[SWING_SPLIT] ✓ 輸出目錄: ${outDir.path}');

    debugPrint('[SWING_SPLIT] 正在獲取影片時長...');
    final double? videoDuration = await _getVideoDuration(videoPath);
    debugPrint('[SWING_SPLIT] ✓ 影片時長: ${videoDuration?.toStringAsFixed(2) ?? "未知"}s');
    
    final List<SwingClipResult> results = [];

    debugPrint('[SWING_SPLIT] 開始逐個切割 ${peaks.length} 個擊棒...');
    for (int i = 0; i < peaks.length; i++) {
      final _Peak pk = peaks[i];
      final double start = math.max(0.0, pk.time - windowBeforeSec);
      final double end = videoDuration != null
          ? math.min(videoDuration, pk.time + windowAfterSec)
          : pk.time + windowAfterSec;
      final String tag = 'hit_${(i + 1).toString().padLeft(3, '0')}';
      final String clipPath = p.join(outDir.path, '$tag.mp4');
      final String clipCsv = p.join(outDir.path, '${tag}_imu.csv');

      debugPrint('[SWING_SPLIT] \n  [#${i + 1}/${peaks.length}] $tag');
      debugPrint('[SWING_SPLIT]   ├─ 時刻範圍: ${start.toStringAsFixed(3)}s ~ ${end.toStringAsFixed(3)}s (擊棒時刻: ${pk.time.toStringAsFixed(3)}s)');
      debugPrint('[SWING_SPLIT]   ├─ 峰值: ${pk.value.toStringAsFixed(2)}G');
      
      debugPrint('[SWING_SPLIT]   ├─ 切割影片...');
      try {
        await _cutVideo(
          src: videoPath,
          dst: clipPath,
          start: start,
          end: end,
          forceSar1: forceSar1,
        );
        debugPrint('[SWING_SPLIT]   │  ✓ 影片切割完成: $clipPath');
      } catch (e) {
        debugPrint('[SWING_SPLIT]   │  ❌ 影片切割失敗: $e');
        rethrow;
      }
      
      debugPrint('[SWING_SPLIT]   ├─ 寫入 CSV 數據...');
      try {
        await _writeCsvSegment(series, clipCsv, start, end, pk.time);
        debugPrint('[SWING_SPLIT]   │  ✓ CSV 數據寫入完成: $clipCsv');
      } catch (e) {
        debugPrint('[SWING_SPLIT]   │  ❌ CSV 寫入失敗: $e');
        rethrow;
      }

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
      
      final bool goodShot = pk.value > 30.0;
      
      debugPrint('[SWING_SPLIT]   └─ 品質判定: ${goodShot ? "✓ 優秀擊棒" : "⚠ 普通擊棒"}');
      
      results.add(
        SwingClipResult(
          tag: tag,
          hitSecond: pk.time,
          startSecond: start,
          endSecond: end,
          peakValue: pk.value,
          videoPath: clipPath,
          csvPath: clipCsv,
          goodShot: goodShot,
          audioCrispness: 0.0, // 待後續獲取
        ),
      );

      // 將結果同步到後端
      if (memberId != null) {
        final label = goodShot ? 'good' : 'unknown';
        final payload = {
          'memberId': memberId,
          'videoPath': clipPath,
          'label': label,
          'avgSpeedMph': null,
          'csvPath': clipCsv,
          'dateTime': DateTime.now().toIso8601String(),
          'extraJson': '{"peak":${pk.value.toStringAsFixed(4)},"hit":${pk.time.toStringAsFixed(4)}}',
        };
        debugPrint('[SWING_SPLIT]   └─ 上傳後端: memberId=$memberId, label=$label');
        unawaited(_postSwing(apiBase, payload));
      }
    }

    final String summaryPath = p.join(outDir.path, 'hits_summary.csv');
    debugPrint('[SWING_SPLIT] \n正在寫入摘要檔案...');
    await _writeSummary(results, summaryPath);
    debugPrint('[SWING_SPLIT] ✓ 摘要檔案已生成: $summaryPath');
    
    debugPrint('[SWING_SPLIT] ===== 切片完成 =====');
    debugPrint('[SWING_SPLIT] 總計: ${results.length} 個片段已生成');
    debugPrint('[SWING_SPLIT] 輸出位置: ${outDir.path}\n');
    
    return results;
  }

  static Future<void> _postSwing(String apiBase, Map<String, dynamic> payload) async {
    try {
      debugPrint('[SWING_POST] 正在上傳擊棒數據: ${payload['videoPath']}');
      final resp = await http.post(
        Uri.parse('$apiBase/api/Swing/update-or-create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (resp.statusCode == 200) {
        debugPrint('[SWING_POST] ✓ 上傳成功 (HTTP ${resp.statusCode})');
      } else {
        debugPrint('[SWING_POST] ❌ 上傳失敗 (HTTP ${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      debugPrint('[SWING_POST] ❌ 上傳異常: $e');
    }
  }

  // ---- IMU parsing / detection ----

  static Future<_ImuSeries> _loadImu(File csvFile) async {
    debugPrint('[LOAD_IMU] 正在讀取 CSV 檔案: ${csvFile.path}');
    final List<String> lines = await csvFile.readAsLines();
    debugPrint('[LOAD_IMU] 總行數: ${lines.length}');
    
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
        debugPrint('[LOAD_IMU] ✓ 找到表頭在第 ${i + 1} 行');
        break;
      }
    }
    if (headerIdx == -1) {
      debugPrint('[LOAD_IMU] ❌ 未找到有效的表頭行，搜尋了前 80 行');
      throw StateError('Trim failed: output path is empty.');
    }

    int idxElapsed = headers.indexOf('ElapsedSec');
    int idxAx = headers.indexOf('AccelX');
    int idxAy = headers.indexOf('AccelY');
    int idxAz = headers.indexOf('AccelZ');
    debugPrint('[LOAD_IMU] 列索引: ElapsedSec=$idxElapsed, AccelX=$idxAx, AccelY=$idxAy, AccelZ=$idxAz');
    
    if (idxElapsed < 0 || idxAx < 0 || idxAy < 0 || idxAz < 0) {
      debugPrint('[LOAD_IMU] ❌ 無效的列索引');
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

    if (t.isEmpty) {
      debugPrint('[LOAD_IMU] ❌ 無有效數據行');
      throw StateError('Trim failed: output path is empty.');
    }

    debugPrint('[LOAD_IMU] ✓ 已載入 ${t.length} 個樣本');
    debugPrint('[LOAD_IMU] 時刻範圍: ${t.first.toStringAsFixed(3)}s ~ ${t.last.toStringAsFixed(3)}s');
    
    final double t0 = t.first;
    final List<double> tNorm = t.map((v) => v - t0).toList();
    debugPrint('[LOAD_IMU] ✓ 時刻軸已歸一化');
    
    return _ImuSeries(time: tNorm, ax: ax, ay: ay, az: az);
  }

  static List<_Peak> _detectPeaks(
    _ImuSeries s, {
    required double smoothWinSec,
    required double threshG,
    required double minIntervalSec,
    double? prominenceG,
  }) {
    debugPrint('[DETECT_PEAKS] 開始峰值偵測');
    final int n = s.time.length;
    if (n < 3) {
      debugPrint('[DETECT_PEAKS] ⚠ 樣本數不足 (n=$n < 3)');
      return const [];
    }

    final double dtEst = (s.time.last - s.time.first) / math.max(1, (n - 1));
    final int win = math.max(1, (smoothWinSec / math.max(1e-6, dtEst)).round());
    final int minDistSamples = math.max(1, (minIntervalSec / math.max(1e-6, dtEst)).round());
    
    debugPrint('[DETECT_PEAKS] 參數: 採樣間隔=${dtEst.toStringAsFixed(6)}s, 平滑窗=$win樣本, 最小距離=$minDistSamples樣本');

    // 取 |acc| 並做居中移動平均，模擬 python 版 rolling(center=True)
    final List<double> mag = List<double>.generate(
        n, (i) => math.sqrt(s.ax[i] * s.ax[i] + s.ay[i] * s.ay[i] + s.az[i] * s.az[i]));
    
    debugPrint('[DETECT_PEAKS] 計算加速度幅度: ${mag.length} 個樣本');
    debugPrint('[DETECT_PEAKS]   ├─ 最小: ${mag.reduce(math.min).toStringAsFixed(2)}G');
    debugPrint('[DETECT_PEAKS]   └─ 最大: ${mag.reduce(math.max).toStringAsFixed(2)}G');
    
    debugPrint('[DETECT_PEAKS] 執行移動平均平滑 (窗口大小=$win樣本)...');
    final List<double> smooth = List<double>.filled(n, 0);
    double maxSmooth = 0;
    double minSmooth = double.infinity;
    
    for (int i = 0; i < n; i++) {
      final int half = win ~/ 2;
      final int start = math.max(0, i - half);
      final int end = math.min(n - 1, i + half);
      double sum = 0;
      for (int j = start; j <= end; j++) {
        sum += mag[j];
      }
      final int windowSize = end - start + 1;
      smooth[i] = sum / windowSize;
      
      // 追踪極值
      if (smooth[i] > maxSmooth) maxSmooth = smooth[i];
      if (smooth[i] < minSmooth) minSmooth = smooth[i];
      
      // 針對高峰值樣本打印詳細信息
      if (smooth[i] >= threshG && i > 0 && i < n - 1) {
        final bool isLocalMax = smooth[i] > smooth[i - 1] && smooth[i] > smooth[i + 1];
        if (isLocalMax) {
          debugPrint('[DETECT_PEAKS]   ├─ 候選峰值 @ i=$i (t=${s.time[i].toStringAsFixed(3)}s): ' '平滑值=${smooth[i].toStringAsFixed(2)}G, 窗口=[$start:$end] (大小=$windowSize), ' '原始=[${mag[start].toStringAsFixed(2)}-${mag[end].toStringAsFixed(2)}]G');
        }
      }
    }
    
    debugPrint('[DETECT_PEAKS] ✓ 平滑完成:');
    debugPrint('[DETECT_PEAKS]   ├─ 最小平滑值: ${minSmooth.toStringAsFixed(2)}G');
    debugPrint('[DETECT_PEAKS]   ├─ 最大平滑值: ${maxSmooth.toStringAsFixed(2)}G');
    debugPrint('[DETECT_PEAKS]   └─ 超過閾值(${threshG}G)的樣本數: ${smooth.where((v) => v >= threshG).length}');

    final List<_Peak> peaks = [];
    int lastPeakIdx = -999999;
    for (int i = 1; i < n - 1; i++) {
      final double v = smooth[i];
      // ✓ 條件 1：超過閾值
      if (v < threshG) continue;
      
      // ✓ 條件 2：必須是局部峰值（中間比兩側都高）
      if (v < smooth[i - 1] || v < smooth[i + 1]) continue;
      
      // ✓ 條件 3：與上一個峰值距離足夠遠
      if (i - lastPeakIdx < minDistSamples) continue;

      if (prominenceG != null) {
        final double leftMin = smooth[math.max(0, i - win)];
        final double rightMin = smooth[math.min(n - 1, i + win)];
        final double prom = v - math.min(leftMin, rightMin);
        if (prom < prominenceG) continue;
      }

      peaks.add(_Peak(time: s.time[i], value: v));
      lastPeakIdx = i;
      debugPrint('[DETECT_PEAKS]   ├─ 峰值 #${peaks.length}: t=${s.time[i].toStringAsFixed(3)}s, 加速度=${v.toStringAsFixed(2)}G');
    }
    peaks.sort((a, b) => a.time.compareTo(b.time));
    debugPrint('[DETECT_PEAKS] ✓ 共偵測到 ${peaks.length} 個峰值');
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
    debugPrint('[CUT_VIDEO] 正在切割影片...');
    debugPrint('[CUT_VIDEO]   ├─ 來源: $src');
    debugPrint('[CUT_VIDEO]   ├─ 目的地: $dst');
    debugPrint('[CUT_VIDEO]   └─ 時刻範圍: ${start.toStringAsFixed(3)}s - ${end.toStringAsFixed(3)}s');
    
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
      debugPrint('[CUT_VIDEO] ✓ 影片切割成功');
    } on PlatformException catch (e) {
      debugPrint('[CUT_VIDEO] ❌ 平台調用失敗: ${e.message}');
      // fallback: copy full video to avoid silent failure
      debugPrint('[CUT_VIDEO] ⚠ 使用備用方案：複製整個影片');
      await File(src).copy(dst);
      throw StateError('Video trim failed: ${e.message}');
    } catch (e) {
      debugPrint('[CUT_VIDEO] ❌ 切割異常: $e');
      rethrow;
    }
  }

  static Future<void> _writeCsvSegment(
    _ImuSeries s,
    String dst,
    double start,
    double end,
    double hit,
  ) async {
    debugPrint('[WRITE_CSV] 寫入 IMU 資料片段...');
    final StringBuffer buf = StringBuffer();
    buf.writeln('Time,AccelX,AccelY,AccelZ,Time_rel');
    
    int rowCount = 0;
    for (int i = 0; i < s.time.length; i++) {
      final double t = s.time[i];
      if (t < start || t > end) continue;
      buf.writeln(
          '${t.toStringAsFixed(6)},${s.ax[i]},${s.ay[i]},${s.az[i]},${(t - hit).toStringAsFixed(6)}');
      rowCount++;
    }
    
    debugPrint('[WRITE_CSV]   ├─ 檔案: $dst');
    debugPrint('[WRITE_CSV]   └─ 資料列數: $rowCount');
    
    try {
      await File(dst).writeAsString(buf.toString());
      debugPrint('[WRITE_CSV] ✓ CSV 寫入成功');
    } catch (e) {
      debugPrint('[WRITE_CSV] ❌ CSV 寫入失敗: $e');
      rethrow;
    }
  }

  static Future<void> _writeSummary(List<SwingClipResult> results, String dst) async {
    debugPrint('[SUMMARY] 生成摘要檔案: $dst');
    final StringBuffer buf = StringBuffer();
    buf.writeln('hit,t_hit,start_t,end_t,peak_smooth,video_path,csv_path,good_shot,audio_crispness');
    
    for (final r in results) {
      buf.writeln(
          '${r.tag},${r.hitSecond.toStringAsFixed(6)},${r.startSecond.toStringAsFixed(6)},${r.endSecond.toStringAsFixed(6)},${r.peakValue.toStringAsFixed(6)},${r.videoPath},${r.csvPath},${r.goodShot},${r.audioCrispness.toStringAsFixed(2)}');
    }
    
    try {
      await File(dst).writeAsString(buf.toString());
      debugPrint('[SUMMARY] ✓ 已寫入 ${results.length} 筆紀錄');
    } catch (e) {
      debugPrint('[SUMMARY] ❌ 寫入失敗: $e');
      rethrow;
    }
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
