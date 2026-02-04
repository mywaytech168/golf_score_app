import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../models/hits_summary.dart';

/// 管理 hits_summary 数据的服务
/// 提供读取、保存和删除摆球摘要的功能
class HitsSummaryStorage {
  /// 从指定路径读取 hits_summary.csv 文件
  /// 返回摆球摘要列表，如果文件不存在返回空列表
  static Future<List<HitsSummary>> loadHitsSummary(String csvPath) async {
    final file = File(csvPath);
    if (!await file.exists()) {
      return [];
    }

    try {
      final lines = await file.readAsLines();
      final hitsSummary = <HitsSummary>[];

      // 跳过 header 行
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        try {
          hitsSummary.add(HitsSummary.fromCsvLine(line));
        } catch (e) {
          print('Failed to parse hits summary line: $line, error: $e');
        }
      }

      return hitsSummary;
    } catch (e) {
      print('Error loading hits summary from $csvPath: $e');
      return [];
    }
  }

  /// 保存摆球摘要列表到 CSV 文件
  static Future<void> saveHitsSummary(
    List<HitsSummary> hitsSummary,
    String csvPath,
  ) async {
    try {
      final file = File(csvPath);
      final dir = Directory(p.dirname(csvPath));
      
      // 确保目录存在
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final StringBuffer buf = StringBuffer();
      // 写入 header
      buf.writeln('hit,t_hit,start_t,end_t,peak_smooth,detect_from');
      
      // 写入数据行
      for (final hit in hitsSummary) {
        buf.writeln(hit.toCsvLine());
      }

      await file.writeAsString(buf.toString(), encoding: utf8);
    } catch (e) {
      print('Error saving hits summary to $csvPath: $e');
      rethrow;
    }
  }

  /// 删除 hits_summary.csv 文件
  static Future<void> deleteHitsSummary(String csvPath) async {
    try {
      final file = File(csvPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting hits summary $csvPath: $e');
    }
  }

  /// 获取摆球摘要文件的标准路径
  /// 例如: /path/to/cut/hits_summary.csv
  static String getHitsSummaryPath(String videoOrCutDirPath) {
    final path = videoOrCutDirPath;
    
    // 如果路径以 hits_summary.csv 结尾，直接返回
    if (path.endsWith('hits_summary.csv')) {
      return path;
    }
    
    // 如果是目录路径
    if (path.endsWith(Platform.pathSeparator)) {
      return p.join(path, 'hits_summary.csv');
    }
    
    // 尝试作为目录
    return p.join(path, 'hits_summary.csv');
  }

  /// 从视频文件路径推断摆球摘要文件路径
  /// 例如: /path/REC_xxx.mp4 -> /path/cut/hits_summary.csv
  static String getHitsSummaryPathFromVideo(String videoPath, [String cutDirName = 'cut']) {
    final videoDir = p.dirname(videoPath);
    return p.join(videoDir, cutDirName, 'hits_summary.csv');
  }

  /// 获取摆球数据统计信息
  static Map<String, dynamic> getStatistics(List<HitsSummary> hits) {
    if (hits.isEmpty) {
      return {
        'total': 0,
        'avgPeak': 0.0,
        'maxPeak': 0.0,
        'minPeak': 0.0,
        'totalDuration': 0.0,
      };
    }

    final peaks = hits.map((h) => h.peakSmooth).toList();
    final durations = hits.map((h) => h.duration).toList();

    return {
      'total': hits.length,
      'avgPeak': peaks.reduce((a, b) => a + b) / peaks.length,
      'maxPeak': peaks.reduce((a, b) => a > b ? a : b),
      'minPeak': peaks.reduce((a, b) => a < b ? a : b),
      'totalDuration': durations.reduce((a, b) => a + b),
    };
  }
}
